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
