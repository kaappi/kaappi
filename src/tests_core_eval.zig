// Phase 1: Basic eval (integers, booleans, arithmetic, if, define, lambda, quote, set!, begin, nested)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;

// Frame depth captured by `record-eval-depth!` (see the #1253 test below).
var eval_depth_observed: usize = 0;

// Test-only observer: records the VM's live frame count at the instant it is
// called. Used to probe the frame depth reached at the base case of an `eval`
// recursion. A tail-called native runs before its frame is popped, so the
// count reflects the depth accumulated by the surrounding recursion.
fn recordEvalDepth(args: []const Value) primitives.PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return primitives.PrimitiveError.InvalidBytecode; // no VM: internal invariant
    eval_depth_observed = vm.frame_count;
    return types.VOID;
}

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
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);

    // execute() registers the VM in the threadlocal
    _ = try vm.eval("(+ 1 2)");
    try std.testing.expect(vm_mod.vm_instance == vm);

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

// Regression for #1253: eval must be tail-called (R7RS 3.5).
//
// The property is that `eval` in tail position runs in *constant* frame depth
// no matter how deep the recursion goes. Rather than force a frame-limit
// overflow — which only becomes decisive past MAX_FRAME_LIMIT (32768) and so
// needs >32768 compile-heavy eval iterations, hours of full collections under
// -Dgc-stress=true (#1452) — observe the depth directly: `record-eval-depth!`
// captures vm.frame_count at the base case of the recursion. A tail-called
// eval reuses its caller's frame, so the depth is identical for a shallow and
// a deep run; a non-tail-called eval would push a frame per iteration, so the
// deep run's depth would exceed the shallow run's by the iteration difference.
// This is decisive with a few hundred iterations, cheap enough for gc-stress.
test "eval tail position runs in constant frame depth (#1253)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try primitives.reg(ctx.vm, "record-eval-depth!", &recordEvalDepth, .{ .exact = 0 });
    _ = try ctx.vm.eval(
        \\(define (loop-eval n)
        \\  (if (= n 0) (record-eval-depth!)
        \\      (eval (list 'loop-eval (- n 1))
        \\            (interaction-environment))))
    );

    eval_depth_observed = 0;
    _ = try ctx.vm.eval("(loop-eval 100)");
    const depth_shallow = eval_depth_observed;
    try std.testing.expect(depth_shallow > 0); // observer actually ran

    eval_depth_observed = 0;
    _ = try ctx.vm.eval("(loop-eval 1000)");
    const depth_deep = eval_depth_observed;
    try std.testing.expect(depth_deep > 0);

    // Tail-called eval ⇒ identical frame depth despite 10× more iterations.
    try std.testing.expectEqual(depth_shallow, depth_deep);
}

// Regression for #1253: null-environment must not leak VM globals in tail position.
// guard desugars its body into a lambda, putting eval in tail position and
// routing through get_global (not call_global). Without restricted_globals,

// #2033: R7RS 5.3.1 makes a top-level redefinition essentially an assignment,
// so the tail-position superinstructions for apply / call-with-values /
// call/cc / call-with-current-continuation / eval must not fire when the
// global binding is no longer the genuine primitive — the user's procedure
// wins in tail position exactly as it always did in non-tail position.
test "top-level redefinition honoured in tail position (#2033)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define (call/cc f) 'user-callcc)");
    _ = try ctx.vm.eval("(define (tail-use) (call/cc 42))");
    try std.testing.expectEqualStrings("user-callcc", types.symbolName(try ctx.vm.eval("(tail-use)")));

    _ = try ctx.vm.eval("(define (apply . r) 'user-apply)");
    _ = try ctx.vm.eval("(define (apply-tail) (apply + (list 1 2)))");
    try std.testing.expectEqualStrings("user-apply", types.symbolName(try ctx.vm.eval("(apply-tail)")));

    _ = try ctx.vm.eval("(define (call-with-values p c) 'user-cwv)");
    _ = try ctx.vm.eval("(define (cwv-tail) (call-with-values (lambda () 1) list))");
    try std.testing.expectEqualStrings("user-cwv", types.symbolName(try ctx.vm.eval("(cwv-tail)")));

    _ = try ctx.vm.eval("(define (eval x . env) 'user-eval)");
    _ = try ctx.vm.eval("(define (eval-tail) (eval '(+ 1 2)))");
    try std.testing.expectEqualStrings("user-eval", types.symbolName(try ctx.vm.eval("(eval-tail)")));

    _ = try ctx.vm.eval("(define (call-with-current-continuation f) 'user-ccc)");
    _ = try ctx.vm.eval("(define (ccc-tail) (call-with-current-continuation (lambda (k) 1)))");
    try std.testing.expectEqualStrings("user-ccc", types.symbolName(try ctx.vm.eval("(ccc-tail)")));
}

// #2469: the decision moved to run time. A body compiled BEFORE the
// redefinition — here form by form through vm.eval, the REPL's own route,
// which #2457's whole-unit pre-scan could never cover — must still reach the
// user's procedure, and restoring the genuine binding brings the builtin
// back through the very same bytecode.
test "per-form use-before-define of every fast-path name is honoured (REPL route, #2469)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define (nt-apply) (let ((v (apply + (list 1 2)))) v))");
    _ = try ctx.vm.eval("(define (t-apply) (apply + (list 1 2)))");
    _ = try ctx.vm.eval("(define (nt-cwv) (let ((v (call-with-values (lambda () 1) (lambda (x) x)))) v))");
    _ = try ctx.vm.eval("(define (t-cwv) (call-with-values (lambda () 1) (lambda (x) x)))");
    _ = try ctx.vm.eval("(define (t-cc) (call/cc (lambda (k) 1)))");
    _ = try ctx.vm.eval("(define (t-ccc) (call-with-current-continuation (lambda (k) 1)))");
    _ = try ctx.vm.eval("(define (t-eval) (eval '(+ 1 2)))");
    _ = try ctx.vm.eval("(define (all) (list (nt-apply) (t-apply) (nt-cwv) (t-cwv) (t-cc) (t-ccc) (t-eval)))");
    _ = try ctx.vm.eval("(define saved (list apply call-with-values call/cc call-with-current-continuation eval))");

    try std.testing.expect(types.isTruthy(try ctx.vm.eval("(equal? (all) '(3 3 1 1 1 1 3))")));

    _ = try ctx.vm.eval("(define (apply f xs) 'ua)");
    _ = try ctx.vm.eval("(define (call-with-values p c) 'uc)");
    _ = try ctx.vm.eval("(define (call/cc r) 'uk)");
    _ = try ctx.vm.eval("(define (call-with-current-continuation r) 'ukk)");
    _ = try ctx.vm.eval("(define (eval x . env) 'ue)");
    try std.testing.expect(types.isTruthy(try ctx.vm.eval("(equal? (all) '(ua ua uc uc uk ukk ue))")));

    _ = try ctx.vm.eval("(set! apply (list-ref saved 0))");
    _ = try ctx.vm.eval("(set! call-with-values (list-ref saved 1))");
    _ = try ctx.vm.eval("(set! call/cc (list-ref saved 2))");
    _ = try ctx.vm.eval("(set! call-with-current-continuation (list-ref saved 3))");
    _ = try ctx.vm.eval("(set! eval (list-ref saved 4))");
    try std.testing.expect(types.isTruthy(try ctx.vm.eval("(equal? (all) '(3 3 1 1 1 1 3))")));
}

// #2469: a redefinition drops the pristine primitive from globals, but every
// guard_builtin compiled before it still compares against that object. The
// registry's fast_path_pristine slots are root-marked so a full collection
// in between neither frees it (a dangling compare) nor lets a recycled
// object alias it (a false "still pristine").
test "pristine fast-path primitives survive a full collection after a redefinition (#2469)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define (t) (apply + (list 1 2)))");
    _ = try ctx.vm.eval("(define orig apply)");
    _ = try ctx.vm.eval("(define (apply f xs) 'user)");
    ctx.vm.gc.collectFull();
    ctx.vm.gc.collectFull();
    // Churn the heap so a freed slot would be recycled before the compare.
    _ = try ctx.vm.eval("(let loop ((i 0) (acc '())) (if (< i 2000) (loop (+ i 1) (cons (make-string 8 #\\a) acc)) (length acc)))");
    try std.testing.expectEqualStrings("user", types.symbolName(try ctx.vm.eval("(t)")));
    _ = try ctx.vm.eval("(set! apply orig)");
    ctx.vm.gc.collectFull();
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try ctx.vm.eval("(t)")));
}

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

test "define-values supports letrec*-style mutual reference, like define (#1719)" {
    // The issue's own repro: two mutually-recursive procedures, each bound
    // by its own define-values clause inside a procedure body. Before the
    // fix, `od?` failed to resolve while compiling `ev?`'s body — its name
    // hadn't been pre-declared yet, since scanBodyDefs's leading-defines
    // prescan only recognized `define`/`define-record-type`, not
    // `define-values`.
    try th.expectEvalTrue(
        \\(define (test-define-values)
        \\  (define-values (ev?) (lambda (n) (if (= n 0) #t (od? (- n 1)))))
        \\  (define-values (od?) (lambda (n) (if (= n 0) #f (ev? (- n 1)))))
        \\  (ev? 10))
        \\(test-define-values)
    );
}

test "define-values mutual reference works via explicit lambda value (#1719)" {
    // Same shape as above, but the outer procedure is written with an
    // explicit `(lambda ...)` value bound by a plain `define`, rather than
    // the `(define (name) ...)` shorthand — this exercises the IR-pipeline
    // lambda body compiler (compileLambdaWithIR) instead of the legacy
    // passthrough (compiler_lambda.compileLambda), a second, independent
    // copy of the same body-scanning/compiling logic.
    try th.expectEvalBool(
        \\(define test-define-values
        \\  (lambda ()
        \\    (define-values (ev?) (lambda (n) (if (= n 0) #t (od? (- n 1)))))
        \\    (define-values (od?) (lambda (n) (if (= n 0) #f (ev? (- n 1)))))
        \\    (ev? 11)))
        \\(test-define-values)
    , false);
}

test "define-values and plain define forward-reference each other (#1719)" {
    // A define-values clause may reference a name bound by a LATER plain
    // `define`, and vice versa — R7RS draws no distinction between them
    // for a body's letrec* scoping.
    try th.expectEval(
        \\(define (mixed-forward-refs)
        \\  (define (get-b) b)
        \\  (define-values (a) (lambda () (get-b)))
        \\  (define-values (b) 14)
        \\  (define (get-a) (a))
        \\  (get-a))
        \\(mixed-forward-refs)
    , 14);
}

test "define-values clause where one bound name calls another (#1719)" {
    // Both names come from the SAME define-values clause's shared init
    // expression — both must already be visible as locals while that
    // init compiles, even though neither has a value yet at that point.
    try th.expectEval(
        \\(define (self-ref)
        \\  (define-values (f g) (values (lambda () (g)) (lambda () 42)))
        \\  (f))
        \\(self-ref)
    , 42);
}

test "top-level define-values enforces lambda-style arity (#550)" {
    // handleDefineValues (the top-level interception in vm_eval.zig) used to
    // bind a prefix of the formals and continue whenever the producer yielded
    // a single non-`values` result, so fixed-arity mismatches ran silently —
    // unlike the internal-definition path, which desugars through
    // call-with-values and a consumer lambda. Each shape below must now raise
    // ArityMismatch (KP3003) at true top level, before defining any global.
    const mismatches = [_][]const u8{
        "(define-values (a b) (values 1))", // too few fixed values
        "(define-values (a b) (values 1 2 3))", // too many fixed values
        "(define-values () 42)", // zero formals against one value
        "(define-values (a b) 1)", // a bare single value for two formals
        "(define-values (a b . rest) (values 1))", // dotted: below the minimum
        "(define-values (a b c) (values 1 2))", // multi-value below the count
    };
    for (mismatches) |src| {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        try std.testing.expectError(vm_mod.VMError.ArityMismatch, ctx.vm.eval(src));
    }
}

test "top-level define-values accepts every well-matched formals shape (#550)" {
    // The arity check must not reject a correct match. A fresh VM per case
    // keeps a raised binding from leaking into the next.
    const Case = struct { src: []const u8, want: i64 };
    const cases = [_]Case{
        .{ .src = "(define-values (a b) (values 1 2)) (+ a b)", .want = 3 },
        .{ .src = "(define-values (x) (+ 20 22)) x", .want = 42 },
        .{ .src = "(define-values (h . t) (values 1 2 3)) (+ h (car t) (cadr t))", .want = 6 },
        .{ .src = "(define-values (h . t) (values 9)) (if (null? t) h -1)", .want = 9 },
        .{ .src = "(define-values xs (values 1 2 3)) (apply + xs)", .want = 6 },
        .{ .src = "(define-values xs (values)) (length xs)", .want = 0 },
        .{ .src = "(define-values () (values)) 7", .want = 7 },
    };
    for (cases) |c| {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const result = try ctx.vm.eval(c.src);
        try std.testing.expectEqual(c.want, types.toFixnum(result));
    }
}

test "begin-wrapped internal define stays local at top level (#2075)" {
    // R7RS 4.2.3: a definition-context `begin` behaves exactly as if the
    // wrapper were absent, so a define inside it must shadow an enclosing
    // let binding and never escape into the global environment — at top
    // level exactly as inside a procedure. Before the fix the begin-wrapped
    // form at top level compiled the define to define_global: the let
    // answered `outer` and the global was silently overwritten.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval(
        \\(define g 'global)
        \\(let ((g 'outer)) (begin (define g 'inner)) g)
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("inner", types.symbolName(result));

    // The global must be untouched...
    const global_after = try ctx.vm.eval("g");
    try std.testing.expect(types.isSymbol(global_after));
    try std.testing.expectEqualStrings("global", types.symbolName(global_after));

    // ...and the identical probe inside a lambda (always correct) must agree.
    const lambda_answer = try ctx.vm.eval(
        \\((lambda () (let ((g2 'outer)) (begin (define g2 'inner)) g2)))
    );
    try std.testing.expect(types.isSymbol(lambda_answer));
    try std.testing.expectEqualStrings("inner", types.symbolName(lambda_answer));
}

test "letrec* region: mutually recursive defines through a begin (#2075)" {
    // The body scanner splices literal begins before pre-declaring the
    // body's definition names, so definitions inside a begin are part of
    // the same letrec* region as unwrapped ones — each init can call a
    // name bound by a LATER spliced define.
    try th.expectEvalBool(
        \\(let ()
        \\  (begin
        \\    (define (ev? n) (if (= n 0) #t (od? (- n 1))))
        \\    (define (od? n) (if (= n 0) #f (ev? (- n 1)))))
        \\  (ev? 10))
    , true);
}

test "macro-produced define in a let body stays local (#2075)" {
    // The compile-time half of #2075: a definition a macro expansion
    // produces inside a let-family body must bind a local in that body,
    // not the global — the same text inside a lambda already did, because
    // only the procedure-body paths set the body-scope flag.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval(
        \\(define-syntax def-inner (syntax-rules () ((_ v) (define v 42))))
        \\(define z 'global)
        \\(let ((z 'outer)) (def-inner z) z)
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));

    const global_after = try ctx.vm.eval("z");
    try std.testing.expect(types.isSymbol(global_after));
    try std.testing.expectEqualStrings("global", types.symbolName(global_after));
}

test "bootstrap stubs fail loudly without vm_bootstrap.install (#1375)" {
    // A VM that registers primitives but never runs vm_bootstrap.install()
    // must raise a clear error from the bootstrapped procedures instead of
    // silently reverting to retired native implementations.
    const primitives_mod = @import("primitives.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(&vm);
    memory.setGCInstance(&gc);
    try primitives_mod.registerAll(&vm);

    const result = vm.eval("(map (lambda (x) x) (list 1 2 3))");
    try std.testing.expectError(vm_mod.VMError.InvalidBytecode, result);
    const detail = vm.last_error_detail[0..vm.last_error_detail_len];
    try std.testing.expect(std.mem.indexOf(u8, detail, "vm_bootstrap.install") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "'map'") != null);

    // The tag is only half of it (#1876) -- what a tool reads is the code. Run
    // the error this eval actually returned through the same mapping
    // `toplevel_driver` reports with: an uninstalled bootstrap must surface as
    // KP9001 "internal error" ("please report it"), not the KP3002 type error
    // ("you passed a bad argument") it claimed until #1876. Deriving the code
    // from `result` rather than from a literal tag is what keeps this coupled
    // to bootstrapStub -- `runtimeErrorCode`'s own table is pinned separately
    // in tests_diagnostics.zig.
    const diagnostics = @import("diagnostics.zig");
    const err = if (result) |_| unreachable else |e| e;
    try std.testing.expectEqual(diagnostics.Code.internal_error, diagnostics.runtimeErrorCode(err));
}

// Regression test: `call_global`/`tail_call_global` populated the per-Function
// inline cache but never stamped `cache_version`, leaving it at its default 0
// while `global_version` had already been bumped past 0 by bootstrap
// (vm_bootstrap.zig) and every library import (vm_library.zig). The fast-path
// guard `cache_version == global_version` was therefore false forever, so every
// call to a global fell through to a full hash-map lookup — measured ~1.4x
// slower on call-dense code. `get_global` already self-healed (memset +
// re-stamp); the two call opcodes did not.
//
// Asserting the stamp rather than timing keeps this deterministic. Child
// SRFI-18 VMs masked the bug: initForThread leaves global_version at 0, which
// happens to match the un-stamped default.
test "call_global stamps cache_version so its inline cache can hit" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // `(>= i n)` and `(+ i 1)` both compile to call_global inside `tick`.
    _ = try ctx.vm.eval("(define (tick i n) (if (>= i n) i (tick (+ i 1) n)))");
    _ = try ctx.vm.eval("(tick 0 3)");

    const tick = ctx.vm.globals.get("tick") orelse return error.TestUnexpectedResult;
    const func = types.toObject(tick).as(types.Closure).func;

    // The cache must exist and be valid for this VM, or it can never hit.
    try std.testing.expect(func.global_cache != null);
    try std.testing.expectEqual(ctx.vm.global_version, func.cache_version);
    // global_version is non-zero in a real VM: that is precisely why an
    // un-stamped (default 0) cache_version could never match.
    try std.testing.expect(ctx.vm.global_version != 0);
}

// The heal must clear the whole cache before re-stamping (issue #812's rule),
// never bless entries cached before the rebinding that bumped the version.
// `(g)` compiles to call_global, so this exercises the call path specifically.
test "call_global heal does not serve a stale callee after rebinding" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define (g) 1)");
    _ = try ctx.vm.eval("(define counter 0)");
    _ = try ctx.vm.eval("(define (redefine!) (set! g (lambda () 2)))");
    _ = try ctx.vm.eval(
        \\(define (h)
        \\  (g)
        \\  (redefine!)
        \\  (set! counter 1)
        \\  (g))
    );
    const result = try ctx.vm.eval("(h)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

// #2185: 255 is the largest argument count the call ISA can encode (nargs is
// a u8), and it is exactly the count that aborted the process -- callClosure
// computed `nargs + 1` in u8 arithmetic for the register window, and the
// three tail-dispatch paths computed the variadic `arity + 1` rest-slot the
// same way. A 256-parameter lambda additionally overflowed the compiler's own
// u8 arity counter at DEFINITION time. All paths must now either work (255)
// or fail as a clean compile error (256).
test "255-argument calls work on every dispatch path; 256 params reject cleanly (#2185)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const a = std.testing.allocator;
    const Gen = struct {
        fn append(buf: *std.ArrayList(u8), al: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
            const s = try std.fmt.allocPrint(al, fmt, args);
            defer al.free(s);
            try buf.appendSlice(al, s);
        }
        /// "(p0 p1 ... pN-1)" without parens; ".. . rest" appended when rest.
        fn params(al: std.mem.Allocator, n: usize, rest: bool) ![]u8 {
            var buf: std.ArrayList(u8) = .empty;
            errdefer buf.deinit(al);
            for (0..n) |i| try append(&buf, al, " p{d}", .{i});
            if (rest) try buf.appendSlice(al, " . rest");
            return buf.toOwnedSlice(al);
        }
        fn nums(al: std.mem.Allocator, n: usize) ![]u8 {
            var buf: std.ArrayList(u8) = .empty;
            errdefer buf.deinit(al);
            for (0..n) |i| try append(&buf, al, " {d}", .{i});
            return buf.toOwnedSlice(al);
        }
    };

    const p255 = try Gen.params(a, 255, false);
    defer a.free(p255);
    const p255r = try Gen.params(a, 255, true);
    defer a.free(p255r);
    const p256 = try Gen.params(a, 256, false);
    defer a.free(p256);
    const n255 = try Gen.nums(a, 255);
    defer a.free(n255);

    // Exact 255-ary callee: direct call (callClosure's u8 `nargs + 1`),
    // tail call, and apply (255 args is the apply limit itself).
    {
        const def = try std.fmt.allocPrint(a, "(define (f {s}) p254)", .{p255});
        defer a.free(def);
        _ = try vm.eval(def);
        const direct = try std.fmt.allocPrint(a, "(f {s})", .{n255});
        defer a.free(direct);
        try std.testing.expectEqual(@as(i64, 254), types.toFixnum(try vm.eval(direct)));
        const tail = try std.fmt.allocPrint(a, "(define (g) (f {s})) (g)", .{n255});
        defer a.free(tail);
        try std.testing.expectEqual(@as(i64, 254), types.toFixnum(try vm.eval(tail)));
        const applied = try std.fmt.allocPrint(a, "(apply f (list {s}))", .{n255});
        defer a.free(applied);
        try std.testing.expectEqual(@as(i64, 254), types.toFixnum(try vm.eval(applied)));
    }

    // Variadic callee with 255 FIXED params: its frame needs arity + 1 = 256
    // arg slots (the rest list), the exact quantity the tail paths computed
    // in u8. The rest list is necessarily empty (nargs tops out at 255).
    {
        const def = try std.fmt.allocPrint(a, "(define (v {s}) (cons p254 rest))", .{p255r});
        defer a.free(def);
        _ = try vm.eval(def);
        const direct = try std.fmt.allocPrint(a, "(equal? '(254) (v {s}))", .{n255});
        defer a.free(direct);
        try std.testing.expectEqual(types.TRUE, try vm.eval(direct));
        const tail = try std.fmt.allocPrint(a, "(define (h) (v {s})) (equal? '(254) (h))", .{n255});
        defer a.free(tail);
        try std.testing.expectEqual(types.TRUE, try vm.eval(tail));
        const applied = try std.fmt.allocPrint(a, "(equal? '(254) (apply v (list {s})))", .{n255});
        defer a.free(applied);
        try std.testing.expectEqual(types.TRUE, try vm.eval(applied));
    }

    // 256 fixed params: uncallable by construction, so definition must be a
    // clean compile error (the compiler's own u8 arity counter overflowed
    // here before the fix).
    {
        const def = try std.fmt.allocPrint(a, "(define (w {s}) p0)", .{p256});
        defer a.free(def);
        try std.testing.expectError(vm_mod.VMError.CompileError, vm.eval(def));
    }
}

// #1961: define/set! into a mutable SchemeEnvironment's map is an old→young
// edge on the wrapper object once promoted; the opcode handlers barrier it
// (vm_dispatch.zig). This drives the real opcode path: promote the env, then
// define and set! a fresh young vector through eval, force a minor
// collection while the vector's only reference is the env's map, and read it
// back intact. Without the barrier the minor sweeps the vector (the old env
// is opaque to the mark) and the read-back dereferences freed memory.
test "define/set! into a promoted mutable env survive a minor collection (#1961)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // Same construction as the #1269 test above: a mutable env with the
    // globals' bindings but a distinct map, reachable from Scheme.
    const env_map = try ctx.gc.allocator.create(std.StringHashMap(types.Value));
    env_map.* = std.StringHashMap(types.Value).init(ctx.gc.allocator);
    var git = ctx.vm.globals.iterator();
    while (git.next()) |entry| {
        try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    var env_val = try ctx.gc.allocEnvironment(env_map, true, false);
    ctx.gc.pushRoot(&env_val);
    defer ctx.gc.popRoot();
    try ctx.vm.globals.put("__test-mut-env", env_val);

    // Promote the env wrapper: two manual minors, marked through the global.
    ctx.gc.enabled = false;
    ctx.gc.minor_cycle_count = 0;
    ctx.gc.collect();
    ctx.gc.minor_cycle_count = 0;
    ctx.gc.collect();
    try std.testing.expectEqual(@as(u1, 1), types.toEnvironment(env_val).header.flags.generation);

    // Real define_global: a fresh young vector stored into the promoted
    // env's map, then a minor collection with the map as its only anchor.
    _ = try ctx.vm.eval("(eval '(define reg-box-1961 (vector 42)) __test-mut-env)");
    ctx.gc.minor_cycle_count = 0;
    ctx.gc.collect();
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try ctx.vm.eval(
        "(eval '(vector-ref reg-box-1961 0) __test-mut-env)",
    )));

    // Real set_global through the same env.
    _ = try ctx.vm.eval("(eval '(set! reg-box-1961 (vector 43)) __test-mut-env)");
    ctx.gc.minor_cycle_count = 0;
    ctx.gc.collect();
    try std.testing.expectEqual(@as(i64, 43), types.toFixnum(try ctx.vm.eval(
        "(eval '(vector-ref reg-box-1961 0) __test-mut-env)",
    )));
}

// #1961 (review follow-up): define-syntax through the interaction-
// environment must NOT enroll its wrapper in the remembered set — the
// wrapper's map is the root-marked globals map, and enrolling it would
// re-walk every global once per minor until process exit. Both routes are
// pinned: GC.envStoreBarrier owns the barrier-side exclusion, and
// referencesYoung's .scheme_environment arm returns false for .owned ==
// false wrappers so the promotion scan and the full-collect re-scan cannot
// enroll it either. The young global defined between the two promotion
// collections is what makes the scan route fire deterministically.
test "define-syntax via interaction-environment does not enroll the wrapper (#1961)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define ie (interaction-environment))");
    const ie_val = try ctx.vm.eval("ie");

    // A fresh wrapper per call. First survival...
    ctx.gc.enabled = false;
    ctx.gc.minor_cycle_count = 0;
    ctx.gc.collect();
    // ...then a young value lands in the wrapper's (root-marked) map...
    _ = try ctx.vm.eval("(define pin-young-global-1961 (vector 7))");
    // ...and the second collection promotes the wrapper with that young
    // value still in the map — exactly the shape that made the promotion
    // scan enroll the wrapper before referencesYoung learned to skip
    // .owned == false maps.
    ctx.gc.minor_cycle_count = 0;
    ctx.gc.collect();
    try std.testing.expectEqual(@as(u1, 1), types.toEnvironment(ie_val).header.flags.generation);

    // The barrier route: a top-level define-syntax through the wrapper.
    _ = try ctx.vm.eval("(eval '(define-syntax k-1961 (syntax-rules () ((_) 1))) ie)");

    const wrapper = types.toObject(ie_val);
    for (ctx.gc.remembered_set.items) |o| {
        try std.testing.expect(o != wrapper);
    }
    // The store itself happened — only the enrollment is skipped.
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try ctx.vm.eval("(eval '(k-1961) ie)")));
}
