// Phase 1: Basic eval (integers, booleans, arithmetic, if, define, lambda, quote, set!, begin, nested)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "eval integer literal" {
    try th.expectEval("42", 42);
}

test "eval boolean" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try std.testing.expectEqual(types.TRUE, try ctx.vm.eval("#t"));
    try std.testing.expectEqual(types.FALSE, try ctx.vm.eval("#f"));
}

test "eval arithmetic" {
    try th.expectEval("(+ 1 2)", 3);
}

test "eval if true" {
    try th.expectEval("(if #t 1 2)", 1);
}

test "eval if false" {
    try th.expectEval("(if #f 1 2)", 2);
}

test "eval define and reference" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(define x 42)");
    const result = try ctx.vm.eval("x");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval lambda and call" {
    try th.expectEval("((lambda (x) (+ x 1)) 41)", 42);
}

test "eval define function and call" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(define add1 (lambda (x) (+ x 1)))");
    const result = try ctx.vm.eval("(add1 10)");
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "eval quote" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval("'(1 2 3)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    const tail1 = types.cdr(result);
    try std.testing.expect(types.isPair(tail1));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(tail1)));
    const tail2 = types.cdr(tail1);
    try std.testing.expect(types.isPair(tail2));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(tail2)));
    try std.testing.expectEqual(types.NIL, types.cdr(tail2));
}

test "eval set!" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(define x 1)");
    _ = try ctx.vm.eval("(set! x 99)");
    const result = try ctx.vm.eval("x");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "eval begin" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(define a 0)");
    _ = try ctx.vm.eval("(define b 0)");
    const result = try ctx.vm.eval("(begin (set! a 1) (set! b 2) (+ a b))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "eval nested arithmetic" {
    try th.expectEval("(+ (* 2 3) (- 10 4))", 12);
}

test "breakpoint strings freed on deinit" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);

    // Simulate ,break: allocate duped name strings and store as breakpoints
    const name1 = try std.testing.allocator.dupe(u8, "foo");
    const name2 = try std.testing.allocator.dupe(u8, "bar");
    const cond = try std.testing.allocator.dupe(u8, "(> x 0)");
    vm.breakpoints[0] = .{ .name = name1, .condition = cond };
    vm.breakpoints[1] = .{ .name = name2 };
    vm.breakpoint_count = 2;

    // deinit must free the duped strings — std.testing.allocator will
    // report a leak (test failure) if any are missed
    vm.deinit();
}

test "default-random-source is per-VM" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var vm1 = try th.makeTestVM(&gc1);
    defer vm1.deinit();

    const rs1 = try vm1.eval("(%default-random-source)");
    try std.testing.expect(types.isRandomSource(rs1));

    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();
    var vm2 = try th.makeTestVM(&gc2);
    defer vm2.deinit();

    const rs2 = try vm2.eval("(%default-random-source)");
    try std.testing.expect(types.isRandomSource(rs2));

    // Each VM must have its own default random source
    try std.testing.expect(rs1 != rs2);

    // VM1's source must still be its own after VM2 was created
    const rs1_again = try vm1.eval("(%default-random-source)");
    try std.testing.expectEqual(rs1, rs1_again);
}

test "vm deinit clears threadlocal vm_instance" {
    const vm_mod = @import("vm.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);

    // execute() registers the VM in the threadlocal
    _ = try vm.eval("(+ 1 2)");
    try std.testing.expect(vm_mod.vm_instance == &vm);

    // deinit must unregister it: a stale pointer here is read by the macro
    // expander (renameForHygiene) during the next VM's first compile, before
    // that VM's own execute() re-registers the threadlocal — a use-after-free
    // that crashed the Linux unit-test runs.
    vm.deinit();
    try std.testing.expect(vm_mod.vm_instance == null);
}

// Regression tests for issue #812: set_global/define_global must clear the
// whole global cache when they bump global_version, not just refresh their own
// slot and re-stamp cache_version. Otherwise an entry cached before an
// unrelated rebinding (which already bumped global_version) gets re-blessed and
// served stale. Each scenario lives inside one procedure body so the caching,
// the rebinding, and the re-stamping all share a single Function's cache.

test "set! of unrelated global does not re-bless stale cache (issue 812)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define (g) 1)");
    _ = try ctx.vm.eval("(define counter 0)");
    _ = try ctx.vm.eval("(define (redefine!) (set! g (lambda () 2)))");
    _ = try ctx.vm.eval(
        \\(define (f)
        \\  (g)
        \\  (redefine!)
        \\  (set! counter 1)
        \\  (g))
    );
    const result = try ctx.vm.eval("(f)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "reference to rebound global not served stale after set! (issue 812)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define (g) 1)");
    _ = try ctx.vm.eval("(define counter 0)");
    _ = try ctx.vm.eval("(define (redefine!) (set! g (lambda () 2)))");
    _ = try ctx.vm.eval(
        \\(define (f)
        \\  (let ((h1 g)) (h1))
        \\  (redefine!)
        \\  (set! counter 1)
        \\  (let ((h2 g)) (h2)))
    );
    const result = try ctx.vm.eval("(f)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "define_global (named let) does not re-bless stale cache (issue 812)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define (g) 1)");
    _ = try ctx.vm.eval("(define (redefine!) (set! g (lambda () 2)))");
    _ = try ctx.vm.eval(
        \\(define (f)
        \\  (g)
        \\  (redefine!)
        \\  (let loop ((n 0)) (if (> n 0) (loop (- n 1))))
        \\  (g))
    );
    const result = try ctx.vm.eval("(f)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "typeName covers all ObjectTags exhaustively" {
    try std.testing.expectEqualStrings("integer", types.typeName(types.makeFixnum(42)));
    try std.testing.expectEqualStrings("nil", types.typeName(types.NIL));
    try std.testing.expectEqualStrings("boolean", types.typeName(types.TRUE));
    try std.testing.expectEqualStrings("boolean", types.typeName(types.FALSE));
    try std.testing.expectEqualStrings("void", types.typeName(types.VOID));
    try std.testing.expectEqualStrings("eof-object", types.typeName(types.EOF));
    try std.testing.expectEqualStrings("char", types.typeName(types.makeChar('A')));

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const pair = try ctx.vm.eval("'(1 2)");
    try std.testing.expectEqualStrings("pair", types.typeName(pair));
    const sym = try ctx.vm.eval("'hello");
    try std.testing.expectEqualStrings("symbol", types.typeName(sym));
    const str = try ctx.vm.eval("\"abc\"");
    try std.testing.expectEqualStrings("string", types.typeName(str));
    const vec = try ctx.vm.eval("#(1 2 3)");
    try std.testing.expectEqualStrings("vector", types.typeName(vec));
    const bv = try ctx.vm.eval("#u8(1 2 3)");
    try std.testing.expectEqualStrings("bytevector", types.typeName(bv));
    const proc = try ctx.vm.eval("(lambda (x) x)");
    try std.testing.expectEqualStrings("procedure", types.typeName(proc));
    const builtin = try ctx.vm.eval("car");
    try std.testing.expectEqualStrings("procedure", types.typeName(builtin));
    const ht = try ctx.vm.eval("(let ((h (make-hash-table))) h)");
    try std.testing.expectEqualStrings("hash-table", types.typeName(ht));
    const prom = try ctx.vm.eval("(delay 42)");
    try std.testing.expectEqualStrings("promise", types.typeName(prom));
    const param = try ctx.vm.eval("(make-parameter 10)");
    try std.testing.expectEqualStrings("parameter", types.typeName(param));
    const rat = try ctx.vm.eval("1/3");
    try std.testing.expectEqualStrings("rational", types.typeName(rat));
    const big = try ctx.vm.eval("99999999999999999999");
    try std.testing.expectEqualStrings("integer", types.typeName(big));
    const rec = try ctx.vm.eval(
        \\(begin (define-record-type <point> (make-point x y) point? (x point-x) (y point-y))
        \\       (make-point 1 2))
    );
    try std.testing.expectEqualStrings("record", types.typeName(rec));
}

// Regression for #1203: record-type redefinition must not retarget old
// constructors/predicates — they must close over the original type.
test "record-type redefinition does not retarget old procedures (#1203)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(define-record-type tt (mk-tt) tt?)");
    _ = try ctx.vm.eval("(define old-inst (mk-tt))");
    _ = try ctx.vm.eval("(define old-pred tt?)");
    _ = try ctx.vm.eval("(define old-mk mk-tt)");
    _ = try ctx.vm.eval("(define-record-type tt (mk-tt v) tt? (v tt-v))");
    const r1 = try ctx.vm.eval("(old-pred old-inst)");
    try std.testing.expectEqual(types.TRUE, r1);
    const r2 = try ctx.vm.eval("(tt? (old-mk))");
    try std.testing.expectEqual(types.FALSE, r2);
}

// Regression for #1202: parameterize must evaluate all value expressions
// before installing any bindings — (b (a)) must see the outer value of a.
test "parameterize evaluates values before binding (#1202)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(define a (make-parameter 1))");
    _ = try ctx.vm.eval("(define b (make-parameter 0))");
    const r1 = try ctx.vm.eval("(parameterize ((a 2) (b (a))) (b))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));
    const r2 = try ctx.vm.eval("(parameterize ((b (a)) (a 2)) (b))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r2));
}

// Regression for #1147: define/set! into (environment ...) must signal error
test "eval define into immutable environment signals error (#1147)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(
        \\(guard (e (#t 'error-signaled))
        \\  (eval '(define foo 32) (environment '(scheme base))))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("error-signaled", types.symbolName(result));
}

test "eval set! into immutable environment signals error (#1147)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(
        \\(guard (e (#t 'error-signaled))
        \\  (eval '(set! car 42) (environment '(scheme base))))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("error-signaled", types.symbolName(result));
}

test "eval define-syntax into immutable environment signals error (#1147)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(
        \\(guard (e (#t 'error-signaled))
        \\  (eval '(define-syntax leaked (syntax-rules () ((_) 999)))
        \\        (environment '(scheme base))))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("error-signaled", types.symbolName(result));
}

test "define-syntax in custom environment does not leak to global scope (#1269)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const before_count = ctx.vm.macros.count();
    // define-syntax errors (immutable env) — verify no macro leaked despite the attempt
    _ = try ctx.vm.eval(
        \\(guard (e (#t 'ok))
        \\  (eval '(define-syntax leaked-mac-1269 (syntax-rules () ((_) 999)))
        \\        (environment '(scheme base))))
    );
    try std.testing.expectEqual(before_count, ctx.vm.macros.count());
    // Verify the macro is not usable at global scope
    const result = try ctx.vm.eval(
        \\(guard (e (#t 'not-leaked))
        \\  (eval '(leaked-mac-1269) (interaction-environment)))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("not-leaked", types.symbolName(result));
}

// Genuine regression guard: constructs a mutable non-global environment
// (unreachable from Scheme) where define-syntax succeeds but must not leak.
test "define-syntax in mutable non-global env does not leak (#1269)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // Build a mutable env with the same bindings as globals but a distinct map
    const env_map = try ctx.gc.allocator.create(std.StringHashMap(types.Value));
    env_map.* = std.StringHashMap(types.Value).init(ctx.gc.allocator);
    var git = ctx.vm.globals.iterator();
    while (git.next()) |entry| {
        try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    var env_val = try ctx.gc.allocEnvironment(env_map, true, false);
    ctx.gc.pushRoot(&env_val);
    defer ctx.gc.popRoot();

    // Expose the mutable env so eval can reach it
    try ctx.vm.globals.put("__test-mut-env", env_val);

    const before_count = ctx.vm.macros.count();

    // define-syntax succeeds (env is mutable) but must not leak to vm.macros
    _ = try ctx.vm.eval(
        \\(eval '(define-syntax mut-leak-test
        \\         (syntax-rules () ((_ x) (+ x 1))))
        \\      __test-mut-env)
    );

    try std.testing.expectEqual(before_count, ctx.vm.macros.count());

    // The macro must not be usable at global scope
    const result = try ctx.vm.eval(
        \\(guard (e (#t 'not-leaked))
        \\  (eval '(mut-leak-test 5) (interaction-environment)))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("not-leaked", types.symbolName(result));
}

test "define-syntax in interaction-environment persists globally (#1269)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(eval '(define-syntax ie-mac-1269 (syntax-rules () ((_) 42)))
        \\      (interaction-environment))
    );
    const result = try ctx.vm.eval("(ie-mac-1269)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "interaction-environment allows define (#1147)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(eval '(define ie-test-var 42) (interaction-environment))");
    const result = try ctx.vm.eval("(eval 'ie-test-var (interaction-environment))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

// Regression for #1253: eval must be tail-called (R7RS 3.5)
test "eval tail position runs in constant frame depth (#1253)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(define (loop-eval n)
        \\  (if (= n 0) 'done
        \\      (eval (list 'loop-eval (- n 1))
        \\            (interaction-environment))))
    );
    const result = try ctx.vm.eval("(loop-eval 40000)");
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("done", types.symbolName(result));
}

// Regression for #1253: null-environment must not leak VM globals in tail position.
// guard desugars its body into a lambda, putting eval in tail position and
// routing through get_global (not call_global). Without restricted_globals,
// get_global falls back to vm.globals, letting car resolve.
test "environment accepts import-set modifiers (#1189)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // only
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try ctx.vm.eval(
        "(eval '(+ 1 2) (environment '(only (scheme base) +)))",
    )));
    // except
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try ctx.vm.eval(
        "(eval '(+ 1 2) (environment '(except (scheme base) car)))",
    )));
    // prefix
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(try ctx.vm.eval(
        "(eval '(b:+ 3 4) (environment '(prefix (scheme base) b:)))",
    )));
    // rename
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(try ctx.vm.eval(
        "(eval '(add 10 20) (environment '(rename (scheme base) (+ add))))",
    )));
    // nested: only on prefix
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(try ctx.vm.eval(
        "(eval '(s:+ 5 6) (environment '(only (prefix (scheme base) s:) s:+)))",
    )));
    // only restricts excluded bindings
    const result = try ctx.vm.eval(
        \\(guard (e (#t 'restricted))
        \\  (eval '(- 5 3) (environment '(only (scheme base) +))))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("restricted", types.symbolName(result));
}

test "null-environment eval in tail position respects restriction (#1253)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(
        \\(guard (e (#t 'caught))
        \\  (eval '(car '(1)) (null-environment 5)))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("caught", types.symbolName(result));
}

test "Unicode identifier with modifier letter (#1268)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // U+02B0 (ʰ, Lm modifier letter) — previously rejected by hand-rolled ranges
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try ctx.vm.eval(
        "(define xʰy 42) xʰy",
    )));
    // U+00AA (ª, Lo feminine ordinal) — Alphabetic but not in old ranges
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(try ctx.vm.eval(
        "(define ª 7) ª",
    )));
    // Verify existing Unicode identifiers still work
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try ctx.vm.eval(
        "(define λ 99) λ",
    )));
}

test "Unicode symbol write/read round-trip (#1268)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // write a symbol containing U+02B0, read it back, verify equality
    const result = try ctx.vm.eval(
        \\(let ((p (open-output-string)))
        \\  (write 'xʰy p)
        \\  (let ((s (get-output-string p)))
        \\    (eq? 'xʰy (read (open-input-string s)))))
    );
    try std.testing.expectEqual(types.TRUE, result);
}
