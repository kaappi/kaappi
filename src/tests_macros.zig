// Phase 5: Hygienic Macros (syntax-rules, define-syntax, let-syntax, letrec-syntax)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "define-syntax simple alias" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define my-if as an alias for if
    _ = try vm.eval("(define-syntax my-if (syntax-rules () ((my-if test then else) (if test then else))))");
    const r1 = try vm.eval("(my-if #t 1 2)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));
    const r2 = try vm.eval("(my-if #f 1 2)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(r2));
}

test "define-syntax constant macro" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define-syntax my-const (syntax-rules () ((my-const) 42)))");
    const result = try vm.eval("(my-const)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "define-syntax with multiple patterns" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A macro with two rules
    _ = try vm.eval("(define-syntax my-op (syntax-rules () ((my-op a) a) ((my-op a b) (+ a b))))");
    const r1 = try vm.eval("(my-op 5)");
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(r1));
    const r2 = try vm.eval("(my-op 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r2));
}

test "syntax-rules with ellipsis" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // my-begin using ellipsis
    _ = try vm.eval("(define-syntax my-begin (syntax-rules () ((my-begin e1 e2 ...) (begin e1 e2 ...))))");
    const result = try vm.eval("(my-begin 1 2 3)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "syntax-rules list construction" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // my-list using ellipsis
    _ = try vm.eval("(define-syntax my-list (syntax-rules () ((my-list e ...) (list e ...))))");
    const result = try vm.eval("(my-list 1 2 3)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(types.cdr(types.cdr(result)))));
}

test "syntax-rules with literals" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A macro that uses a literal keyword
    _ = try vm.eval("(define-syntax my-case (syntax-rules (is) ((my-case x is y) (if (= x y) #t #f))))");
    const r1 = try vm.eval("(my-case 3 is 3)");
    try std.testing.expectEqual(types.TRUE, r1);
    const r2 = try vm.eval("(my-case 3 is 4)");
    try std.testing.expectEqual(types.FALSE, r2);
}

test "syntax-rules zero ellipsis matches" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // my-begin with zero varargs
    _ = try vm.eval("(define-syntax my-begin (syntax-rules () ((my-begin e1 e2 ...) (begin e1 e2 ...))))");
    const result = try vm.eval("(my-begin 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "let-syntax basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let-syntax ((my-const (syntax-rules () ((my-const) 42)))) (my-const))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "let-syntax scoping" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define a macro at top level
    _ = try vm.eval("(define-syntax outer (syntax-rules () ((outer) 1)))");
    // Override inside let-syntax
    const result = try vm.eval("(let-syntax ((outer (syntax-rules () ((outer) 2)))) (outer))");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
    // After let-syntax, original should be restored
    const result2 = try vm.eval("(outer)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result2));
}

test "letrec-syntax basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(letrec-syntax ((my-const (syntax-rules () ((my-const) 99)))) (my-const))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "let-syntax sibling keywords use outer scope (#1140)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define-syntax m (syntax-rules () ((_) 'outer)))");
    // call-m's template (m) must resolve to the OUTER m, not the sibling
    const result = try vm.eval(
        \\(let-syntax ((m      (syntax-rules () ((_) 'inner)))
        \\             (call-m (syntax-rules () ((_) (m)))))
        \\  (call-m))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("outer", types.symbolName(result));
}

test "letrec-syntax sibling keywords see inner scope" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define-syntax m (syntax-rules () ((_) 'outer)))");
    // letrec-syntax: call-m's template (m) must resolve to the INNER m
    const result = try vm.eval(
        \\(letrec-syntax ((m      (syntax-rules () ((_) 'inner)))
        \\                (call-m (syntax-rules () ((_) (m)))))
        \\  (call-m))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("inner", types.symbolName(result));
}

test "define-syntax nested expansion" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define swap that uses let
    _ = try vm.eval(
        \\(define-syntax my-swap
        \\  (syntax-rules ()
        \\    ((my-swap a b)
        \\     (let ((tmp a))
        \\       (set! a b)
        \\       (set! b tmp)))))
    );
    _ = try vm.eval("(define x 1)");
    _ = try vm.eval("(define y 2)");
    _ = try vm.eval("(my-swap x y)");
    const rx = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(rx));
    const ry = try vm.eval("y");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(ry));
}

test "syntax-rules underscore" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Use _ as a wildcard in pattern
    _ = try vm.eval("(define-syntax second (syntax-rules () ((second _ x) x)))");
    const result = try vm.eval("(second 1 2)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "syntax-rules define-syntax my-and" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Classic recursive-style my-and with multiple rules
    _ = try vm.eval(
        \\(define-syntax my-and
        \\  (syntax-rules ()
        \\    ((my-and) #t)
        \\    ((my-and x) x)
        \\    ((my-and x y) (if x y #f))))
    );
    try std.testing.expectEqual(types.TRUE, try vm.eval("(my-and)"));
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(try vm.eval("(my-and 5)")));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(my-and 2 3)")));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(my-and #f 3)"));
}

// ---------------------------------------------------------------------------
// Hygiene tests
// ---------------------------------------------------------------------------

test "hygiene: my-or does not capture user temp" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define my-or which uses 'temp' internally
    _ = try vm.eval(
        \\(define-syntax my-or
        \\  (syntax-rules ()
        \\    ((my-or) #f)
        \\    ((my-or e) e)
        \\    ((my-or e1 e2 ...)
        \\     (let ((temp e1))
        \\       (if temp temp (my-or e2 ...))))))
    );

    // Basic cases
    try std.testing.expectEqual(types.FALSE, try vm.eval("(my-or)"));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(my-or 1)")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(my-or #f 2)")));

    // KEY: user's 'temp' must not be captured by macro's internal 'temp'
    const result = try vm.eval("(let ((temp 42)) (my-or #f temp))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "hygiene: swap! does not capture user tmp" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define swap! which uses 'tmp' internally
    _ = try vm.eval(
        \\(define-syntax swap!
        \\  (syntax-rules ()
        \\    ((swap! a b)
        \\     (let ((tmp a))
        \\       (set! a b)
        \\       (set! b tmp)))))
    );

    // KEY: swap variables where one is named 'tmp' (same as macro internal)
    const result = try vm.eval("(let ((tmp 1) (y 2)) (swap! tmp y) (list tmp y))");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(types.cdr(result))));
}

test "hygiene: nested my-or with temp" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax my-or
        \\  (syntax-rules ()
        \\    ((my-or) #f)
        \\    ((my-or e) e)
        \\    ((my-or e1 e2 ...)
        \\     (let ((temp e1))
        \\       (if temp temp (my-or e2 ...))))))
    );

    // Deeply nested: multiple #f then a value
    const r1 = try vm.eval("(my-or #f #f #f 77)");
    try std.testing.expectEqual(@as(i64, 77), types.toFixnum(r1));

    // Nested my-or inside my-or, with user 'temp' in scope
    const r2 = try vm.eval("(let ((temp 100)) (my-or #f (my-or #f temp)))");
    try std.testing.expectEqual(@as(i64, 100), types.toFixnum(r2));
}

test "hygiene: multiple macro invocations are independent" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax my-or
        \\  (syntax-rules ()
        \\    ((my-or) #f)
        \\    ((my-or e) e)
        \\    ((my-or e1 e2 ...)
        \\     (let ((temp e1))
        \\       (if temp temp (my-or e2 ...))))))
    );

    // Each invocation should get its own hygienic renaming
    const result = try vm.eval("(let ((temp 10)) (let ((a (my-or #f temp)) (b (my-or temp #f))) (list a b)))");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(types.car(types.cdr(result))));
}

test "let-syntax rejects malformed binding without transformer" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval("(let-syntax ((my-macro)) 1)");
    try std.testing.expectError(error.CompileError, result);
}

test "hygiene: macro-generating macro shares binding with inner macro" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Issue #919: the inner macro's stored template references march-hare,
    // already hygiene-renamed by the outer expansion. Expanding (mad-hatter)
    // must not rename it a second time, or the reference is severed from
    // the binding the outer expansion created.
    _ = try vm.eval(
        \\(define-syntax jabberwocky
        \\  (syntax-rules ()
        \\    ((_ hatter)
        \\     (begin
        \\       (define march-hare 42)
        \\       (define-syntax hatter
        \\         (syntax-rules ()
        \\           ((_) march-hare)))))))
    );
    _ = try vm.eval("(jabberwocky mad-hatter)");
    const result = try vm.eval("(mad-hatter)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "hygiene: template references sibling define that appears later in body" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // R7RS 5.3.2: body defines have letrec* scope, so the macro-definition
    // environment includes bar399 even though it is defined after the macro.
    // The expander must not hygiene-rename the template's free reference.
    const result = try vm.eval(
        \\(let ()
        \\  (define-syntax foo399
        \\    (syntax-rules () ((foo399) (bar399))))
        \\  (define (quux399) (foo399))
        \\  (define (bar399) 42)
        \\  (quux399))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "internal define shadows a macro keyword bound outside the body" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The first form's (foo bar x) expands to a define-syntax for bar that
    // escapes the let body. The second form's internal (define bar ...) is a
    // variable binding for the whole body (R7RS 5.3), so (bar x y) must
    // compile as a procedure call, not as a use of the leaked macro.
    _ = try vm.eval(
        \\(let ()
        \\  (define-syntax foo
        \\    (syntax-rules ()
        \\      ((foo bar y)
        \\       (define-syntax bar
        \\         (syntax-rules ()
        \\           ((bar x) 'y))))))
        \\  (foo bar x)
        \\  (bar 1))
    );
    const result = try vm.eval(
        \\(let ((x 5))
        \\  (define foo (lambda (y) (bar x y)))
        \\  (define bar (lambda (a b) (+ (* a b) a)))
        \\  (foo (+ x 3)))
    );
    try std.testing.expectEqual(@as(i64, 45), types.toFixnum(result));
}

test "hygiene: inner syntax-rules pattern variables shadow outer bindings" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Issue #919 (pattern-variable scoping variant): the inner macro's
    // pattern variable x must not be confused with the use-site symbol x
    // substituted for the outer pattern variable y.
    const result = try vm.eval(
        \\(let ()
        \\  (define-syntax foo
        \\    (syntax-rules ()
        \\      ((foo bar y)
        \\       (define-syntax bar
        \\         (syntax-rules ()
        \\           ((bar x) 'y))))))
        \\  (foo bar x)
        \\  (bar 1))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("x", types.symbolName(result));
}

test "body scoping: leading define-syntax does not leak past let body" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(let () (define-syntax m (syntax-rules () ((m) 1))) (m))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));

    // After the body, m must be an ordinary identifier again.
    _ = try vm.eval("(define (m) 2)");
    const r2 = try vm.eval("(m)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(r2));
}

test "body scoping: macro-generated define-syntax does not leak past body" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // (foo bar x) expands mid-body to (define-syntax bar ...); the generated
    // macro must work for the remainder of the body (R7RS 5.3)...
    const r1 = try vm.eval(
        \\(let ()
        \\  (define-syntax foo
        \\    (syntax-rules ()
        \\      ((foo bar y)
        \\       (define-syntax bar
        \\         (syntax-rules ()
        \\           ((bar x) 'y))))))
        \\  (foo bar x)
        \\  (bar 1))
    );
    try std.testing.expect(types.isSymbol(r1));
    try std.testing.expectEqualStrings("x", types.symbolName(r1));

    // ...but must not survive the body: a later top-level (bar 1) must call
    // the global procedure, not expand the leaked macro to 'x.
    _ = try vm.eval("(define (bar x) 42)");
    const r2 = try vm.eval("(bar 1)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r2));
}

test "top-level begin: define-syntax persists for later forms" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // R7RS 5.1: top-level (begin ...) splices, so its define-syntax is a
    // top-level definition and must remain visible afterwards.
    _ = try vm.eval("(begin (define-syntax k (syntax-rules () ((k) 7))) #t)");
    const result = try vm.eval("(k)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "syntax-rules nested ellipsis: depth-2 pattern variables" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Regression: variables at ellipsis depth 2 (e.g. b, c in
    // ((a (b c) ...) ...)) were rejected with EllipsisDepthMismatch at the
    // outer ellipsis instead of being unpacked one level per ellipsis.
    // Surfaced by SRFI-35's `condition` construction macro.
    _ = try vm.eval("(define-syntax nest (syntax-rules () ((nest (a (b c) ...) ...) (+ (+ a (* b c) ...) ...))))");
    const result = try vm.eval("(nest (1 (2 3) (4 5)) (10 (6 7)))");
    try std.testing.expectEqual(@as(i64, 79), types.toFixnum(result));
}

test "hygiene: template set! of a free global writes through to the global" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The compiler injects a register alias for a template's free
    // reference to a non-procedure global so the reference pierces
    // use-site shadowing (R7RS 4.3.1). set! through the alias used to
    // update only the register, silently losing the assignment.
    _ = try vm.eval("(define count 0)");
    _ = try vm.eval(
        \\(define-syntax inc!
        \\  (syntax-rules ()
        \\    ((inc!) (set! count (+ count 1)))))
    );
    _ = try vm.eval("(inc!)");
    _ = try vm.eval("(inc!)");
    const result = try vm.eval("count");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));

    // Same expansion inside a lambda body
    _ = try vm.eval("(define (bump) (inc!))");
    _ = try vm.eval("(bump)");
    const result2 = try vm.eval("count");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result2));
}

test "hygiene: template set! reaches the global past a use-site shadow" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define counter 0)");
    _ = try vm.eval(
        \\(define-syntax bump!
        \\  (syntax-rules ()
        \\    ((bump!) (set! counter (+ counter 1)))))
    );
    // The use-site local counter must stay untouched; the template's
    // set! must mutate the definition-site global.
    const local = try vm.eval("(let ((counter 100)) (bump!) counter)");
    try std.testing.expectEqual(@as(i64, 100), types.toFixnum(local));
    const global = try vm.eval("counter");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(global));
}

test "hygiene: template binding shadows a builtin procedure of the same name" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The template binds a variable named exp; references in the
    // template body must follow the hygienic rename of that binding,
    // not resolve to the builtin exp procedure. (This broke the SRFI-19
    // test harness: every `expected` value became #<builtin exp>.)
    _ = try vm.eval(
        \\(define-syntax capture-exp
        \\  (syntax-rules ()
        \\    ((_ v) (let ((exp v)) exp))))
    );
    const result = try vm.eval("(capture-exp 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));

    // A template reference without a template binding must still reach
    // the builtin.
    _ = try vm.eval(
        \\(define-syntax call-exp
        \\  (syntax-rules ()
        \\    ((_ v) (exp v))))
    );
    const builtin = try vm.eval("(exact (round (call-exp 0)))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(builtin));
}

test "keyword shadowed by an enclosing-scope binding compiles as a call inside a lambda (#814)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // R7RS has no reserved words: a lexical binding shadows a syntactic
    // keyword throughout its scope, including inner lambdas. When the
    // binding lives in an enclosing function scope the reference resolves
    // as an upvalue, so the shadowing guard in compileForm must probe
    // resolveUpvalue in addition to resolveLocal. Previously these forms
    // were still compiled as the special form and returned the wrong value.

    // Control: same-scope shadowing already worked.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? (let ((if list)) (if 1 2 3)) '(1 2 3))"));

    // Captured (upvalue) shadowing across a lambda boundary.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((let ((if list))    (lambda () (if 1 2 3)))) '(1 2 3))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((let ((and list))   (lambda () (and 1 2))))  '(1 2))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((let ((begin list)) (lambda () (begin 1 2)))) '(1 2))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((let ((when list))  (lambda () (when 1 2))))  '(1 2))"));

    // Two levels deep: the binding resolves as an upvalue-of-an-upvalue.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? (((let ((if list)) (lambda () (lambda () (if 1 2 3)))))) '(1 2 3))"));

    // A macro that expands to a genuine `if` must still compile it as the
    // special form; the shadow probe must not disturb hygienic renames.
    _ = try vm.eval("(define-syntax my-if (syntax-rules () ((_ a b c) (if a b c))))");
    try std.testing.expectEqualStrings("yes", types.symbolName(try vm.eval("(my-if #t 'yes 'no)")));
}

test "syntax-rules literal binding check: let-rebound literal must not match (#1139)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax has-lit
        \\  (syntax-rules (lit)
        \\    ((_ lit) 'is-literal)
        \\    ((_ x)   'not-literal)))
    );

    // Both unbound: literal matches
    try std.testing.expect(types.isSymbol(try vm.eval("(has-lit lit)")));
    try std.testing.expectEqualStrings("is-literal", types.symbolName(try vm.eval("(has-lit lit)")));

    // Use-site bound, def-site unbound: must NOT match
    try std.testing.expectEqualStrings("not-literal", types.symbolName(try vm.eval("(let ((lit 42)) (has-lit lit))")));

    // Same-scope define-syntax: literal IS def-site bound, use-site also bound → match
    try std.testing.expectEqualStrings("is-literal", types.symbolName(try vm.eval(
        \\(let ((lit 42))
        \\  (define-syntax has-lit2
        \\    (syntax-rules (lit)
        \\      ((_ lit) 'is-literal)
        \\      ((_ x)   'not-literal)))
        \\  (has-lit2 lit))
    )));
}

test "lambda parameter shadows a syntactic keyword in its body (#788)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A lambda body is lowered through the IR, which dispatches special forms
    // by name. When a parameter shadows a keyword the body must compile as an
    // ordinary call to the parameter, not the special form. Previously the IR
    // path ignored lexical scope and (e.g.) folded (if 1 2 3) to a special
    // form — eliminateDeadBranches even constant-folded it to 2.
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try vm.eval("((lambda (if) (if 1 2 3)) (lambda (a b c) 99))")));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((lambda (and) (and 1 2)) list) '(1 2))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((lambda (or) (or 1 2)) list) '(1 2))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((lambda (begin) (begin 1 2)) list) '(1 2))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((lambda (when) (when 1 2)) list) '(1 2))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? ((lambda (unless) (unless 1 2)) list) '(1 2))"));
    try std.testing.expectEqual(@as(i64, -5), types.toFixnum(try vm.eval("((lambda (quote) (quote 5)) -)")));

    // The shadow holds inside nested forms lowered by the same IR pass.
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try vm.eval("((lambda (if) (begin (if 1 2 3))) (lambda (a b c) 99))")));

    // And across a lambda boundary, where the keyword resolves as an upvalue
    // captured from the outer parameter.
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try vm.eval("(((lambda (if) (lambda () (if 1 2 3))) (lambda (a b c) 99)))")));

    // A shadowed primitive must not be constant-folded as the builtin either.
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("((lambda (+) (+ 1 2)) *)")));

    // An unshadowed keyword still compiles as the special form.
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("((lambda (x) (if 1 2 3)) 0)")));
}
