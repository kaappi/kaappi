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

// Nested-syntax-rules-generation hygiene/expansion regressions (macros
// whose templates generate a fresh, nested syntax-rules transformer -- the
// mechanism SRFI 147/148 build on) live in tests_macros_nested_sr.zig, kept
// separate to hold this file under the 1500-line policy.

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

test "kaappi#1772: begin as a non-first body form sees its own internal define-syntax" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A literal begin used as a non-first, non-whole-body form compiles via
    // ir.lowerBegin (general IR lowering), not compiler_lambda's sequential
    // compileBegin/scanBodyDefs. lowerBegin used to lower every child eagerly
    // before any of them compiled, so a define-syntax sibling's registration
    // — a side effect of *compiling* its node — wasn't visible yet when a
    // later sibling in the same begin was lowered, and its use compiled as a
    // plain call to an unbound global instead of expanding.
    _ = try vm.eval(
        \\(define (test-fn2)
        \\  (+ 1 1)
        \\  (begin
        \\    (define-syntax inner-mid
        \\      (syntax-rules ()
        \\        ((_ y) (list 'fixed y))))
        \\    (inner-mid 99)))
    );
    const result = try vm.eval("(test-fn2)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expect(types.isSymbol(types.car(result)));
    try std.testing.expectEqualStrings("fixed", types.symbolName(types.car(result)));
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(types.car(types.cdr(result))));
}

test "kaappi#1772: begin inside an if branch sees its own internal define-syntax" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Same bug, reached through a different lowerWithMacros caller (lowerIf
    // instead of a lambda body's compileExprSequence) — confirms the fix
    // lives in lowerBegin itself, not in body-sequencing code.
    _ = try vm.eval(
        \\(define (test-fn3 flag)
        \\  (if flag
        \\      (begin
        \\        (define-syntax inner-if
        \\          (syntax-rules ()
        \\            ((_ y) (list 'from-if y))))
        \\        (inner-if 42))
        \\      'other))
    );
    const result = try vm.eval("(test-fn3 #t)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqualStrings("from-if", types.symbolName(types.car(result)));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(types.car(types.cdr(result))));
}

test "kaappi#1772: define-syntax use-before-def in a nested begin still errors, matching top level" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The reservation added for #1772 only reserves a define-syntax sibling's
    // name once its OWN form is reached, so it must not hoist that name
    // ahead of its textual position: a use compiled before its definition is
    // still an unbound-global error, exactly like the same ordering would be
    // at real top level (an earlier (m7 1), a later define-syntax m7).
    _ = try vm.eval(
        \\(define (test-fn7)
        \\  (begin
        \\    (begin (m7 1))
        \\    (define-syntax m7 (syntax-rules () ((_ y) (list 'm7 y))))))
    );
    try std.testing.expectError(error.UndefinedVariable, vm.eval("(test-fn7)"));
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

test "syntax-rules doubled ellipsis flattens depth-2 bindings (#1243)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax flatten2
        \\  (syntax-rules ()
        \\    ((_ ((x ...) ...)) '(x ... ...))))
    );
    const result = try vm.eval("(equal? (flatten2 ((1 2) (3 4) (5))) '(1 2 3 4 5))");
    try std.testing.expectEqual(types.TRUE, result);

    // Single group
    const r2 = try vm.eval("(equal? (flatten2 ((10 20 30))) '(10 20 30))");
    try std.testing.expectEqual(types.TRUE, r2);

    // Empty groups mixed in
    const r3 = try vm.eval("(equal? (flatten2 ((1) () (2 3))) '(1 2 3))");
    try std.testing.expectEqual(types.TRUE, r3);

    // All empty
    const r4 = try vm.eval("(equal? (flatten2 (() ())) '())");
    try std.testing.expectEqual(types.TRUE, r4);

    // No groups
    const r5 = try vm.eval("(equal? (flatten2 ()) '())");
    try std.testing.expectEqual(types.TRUE, r5);

    // Custom ellipsis identifier
    _ = try vm.eval(
        \\(define-syntax flatten-custom
        \\  (syntax-rules ::: ()
        \\    ((_ ((x :::) :::)) '(x ::: :::))))
    );
    const r6 = try vm.eval("(equal? (flatten-custom ((1 2) (3 4))) '(1 2 3 4))");
    try std.testing.expectEqual(types.TRUE, r6);
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

test "hygiene: macro-expanded body-position define is visible to later siblings (#1800)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // form is a pattern variable, so substituting it preserves the
    // use-site identifier x unrenamed -- expandAndCompileMacroUse used to
    // pop the compiler local compileDefine's in_body_scope branch had just
    // added for x, on the mistaken assumption that everything added while
    // compiling a macro use is transient chain bookkeeping (hygienic
    // aliases). A body-scope `define` reached through the expansion is a
    // real, sibling-visible local, not an alias.
    _ = try vm.eval("(define-syntax n800 (syntax-rules () ((n800 form) form)))");
    const result = try vm.eval("(let () (n800 (define x 10)) x)");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));

    // A local injected purely for R7RS 4.3.1 referential transparency
    // (the sibling test above) must still be discarded after the macro
    // use finishes, even when a LATER, separate macro use in the same
    // body also leaves behind a real, surviving local.
    _ = try vm.eval("(define counter 0)");
    _ = try vm.eval("(define-syntax bump! (syntax-rules () ((bump!) (set! counter (+ counter 1)))))");
    const combined = try vm.eval("(let ((counter 100)) (n800 (define z 5)) (bump!) (list counter z))");
    try std.testing.expectEqual(@as(i64, 100), types.toFixnum(types.car(combined)));
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(types.car(types.cdr(combined))));
    const global_counter = try vm.eval("counter");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(global_counter));
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

test "recursive variadic macro: sibling calls produce correct values (#1215)" {
    try th.expectEval(
        \\(begin
        \\  (define-syntax my-list
        \\    (syntax-rules ()
        \\      ((my-list) '())
        \\      ((my-list x rest ...)
        \\       (cons x (my-list rest ...)))))
        \\  (+ (car (my-list 10 20)) (car (my-list 30 40))))
    , 40);
}

test "macro expanding to a global as a non-final call argument (#1396 oracle find)" {
    // Referential-transparency aliasing loads a template's free global into
    // a fresh register during expansion (#935). That register leaked, so in
    // (+ (m0) 1) the literal 1 landed one slot past the register window the
    // call reads — the call saw the alias's value twice: (+ (m0) 1) => 82.
    // Found by the Kaappi-vs-Chibi differential oracle on its first batch.
    try th.expectEval(
        \\(begin
        \\  (define g1 41)
        \\  (define-syntax m0 (syntax-rules () ((_) g1)))
        \\  (+ (m0) 1))
    , 42);
}

test "macro-with-global expansion keeps later argument slots intact (#1396)" {
    // Same leak, observed structurally: every argument after the expansion
    // was read from the wrong slot, so (list (m0) 1 2) became (41 41 41).
    try th.expectEvalTrue(
        \\(begin
        \\  (define g1 41)
        \\  (define-syntax m0 (syntax-rules () ((_) g1)))
        \\  (equal? (list (m0) 1 2) '(41 1 2)))
    );
}

test "let-syntax sibling macro passed as an argument stays resolvable" {
    // R7RS 4.3.1 says a let-syntax transformer's *template* free references
    // resolve at the definition site, where sibling keywords aren't visible.
    // Kaappi suppressed ALL siblings during an expansion's compilation, so a
    // sibling handed to a helper as an *argument* (a use-site identifier, not
    // a template reference) vanished: `id` was reported undefined. Now only
    // siblings a transformer actually free-references in its template are
    // suppressed. This `(helper macro)` idiom underlies SRFI 257's `classify`
    // (`classify-nonellipsis-symbol`'s `(b () k ...)`).
    try th.expectEval(
        \\(let-syntax ((apply1 (syntax-rules () ((_ m v) (m v))))
        \\             (id     (syntax-rules () ((_ x) x))))
        \\  (apply1 id 42))
    , 42);
}

test "named-let loop gensym survives re-expansion through a macro" {
    // A named let desugars during compilation to a __nlet_N_loop gensym,
    // interleaved with macro expansion. When the (loop ...) call rides through
    // another macro whose template re-emits it, the hygiene renamer used to
    // re-rename the already-gensym'd name (__hyg_M___nlet_N_loop), splitting
    // the recursive call from its letrec binding. renameForHygiene now leaves
    // __nlet_ gensyms alone, as it already does for __hyg_ ones (issue #919).
    // Exercised by SRFI 257's ~etc, which loops with the recursive call nested
    // inside a submatch argument.
    try th.expectEval(
        \\(begin
        \\  (define-syntax again
        \\    (syntax-rules ()
        \\      ((_ call) (let-syntax ((go (syntax-rules () ((_) call)))) (go)))))
        \\  (define-syntax build
        \\    (syntax-rules ()
        \\      ((_ base)
        \\       (let loop ((n base) (acc 0))
        \\         (if (= n 0) acc (again (loop (- n 1) (+ acc 1))))))))
        \\  (build 4))
    , 4);
}

test "let-syntax template reaches an enclosing frame's local (#1644)" {
    // A let-syntax macro defined inside a nested lambda whose template
    // references an OUTER function's local: the reference was hygiene-renamed
    // and the captured-locals slot alias only covers the innermost frame, so
    // __hyg_N_u came out undefined. renameForHygiene now keeps a template
    // free reference unrenamed when the transformer recorded it as a
    // definition-site lexical local (def_site_local_refs) and the name is
    // not resolvable in the current frame — the regular local/upvalue path
    // then reaches the enclosing frame.
    try th.expectEval(
        \\(begin
        \\  (define (f u)
        \\    (lambda ()
        \\      (let-syntax ((mm (syntax-rules () ((_ x) (u x)))))
        \\        (mm 5))))
        \\  ((f (lambda (v) (+ v 37)))))
    , 42);
}

test "same-frame def-site local stays shadow-proof under keep-plain" {
    // The companion guarantee to the previous test: when the definition-site
    // local IS in the current frame, the rename + captured-locals slot alias
    // path is kept, so a user rebinding of the same name between definition
    // and use does not capture the template's reference (R7RS 4.3.1).
    try th.expectEval(
        \\(begin
        \\  (define (f u)
        \\    (let-syntax ((mm (syntax-rules () ((_) (u 1)))))
        \\      (let ((u (lambda (x) 0)))
        \\        (mm))))
        \\  (f (lambda (x) 42)))
    , 42);
}

test "generated macro name colliding with a user variable stays a macro (#1644)" {
    // SRFI 257's submatch protocol generates let-syntax macros named `k`
    // while user code often has a variable `k` in scope. The hygienic-capture
    // alias injection saw the renamed keyword __hyg_N_k, stripped it to `k`,
    // matched the captured user local, and injected a local alias — which
    // SHADOWED the macro (compileForm suppresses a macro when a same-named
    // local resolves), rerouting the macro call into the user's variable.
    // The injection now skips names that are macro-bound.
    try th.expectEval(
        \\(begin
        \\  (define-syntax outer
        \\    (syntax-rules ()
        \\      ((_ sub)
        \\       (let-syntax ((k (syntax-rules () ((_ v) (+ v 2)))))
        \\         (sub k)))))
        \\  (define-syntax call40 (syntax-rules () ((_ m) (m 40))))
        \\  (define (f k) (outer call40))
        \\  (f (lambda (x) 0)))
    , 42);
}

test "captured-local alias reads through a box created by a later capture" {
    // When an inner lambda captures an outer local, the local is boxed at
    // closure creation. Hygienic-capture aliases injected for that local now
    // copy the slot's CURRENT boxing status (and markLocalBoxedBySlot flips
    // every same-slot alias), so the alias reads the value through the box
    // instead of yielding the box object itself.
    try th.expectEvalTrue(
        \\(begin
        \\  (define (f u)
        \\    (define (snap) u)
        \\    (let-syntax ((mm (syntax-rules () ((_) (u 2)))))
        \\      (list (procedure? u) (mm) (procedure? (snap)))))
        \\  (equal? (f (lambda (x) (* x 21))) (list #t 42 #t)))
    );
}

test "quasiquote data symbols in templates are not hygiene-renamed" {
    // Symbols under `quasiquote` in a macro template are data, like plain
    // quote — they leaked as __hyg_N_fst when the template was instantiated.
    // A depth-matching unquote switches back to expression territory where
    // renaming (and pattern-var substitution) resumes.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax tag
        \\    (syntax-rules () ((_ e) `(fst ,e `(nested ,ignore)))))
        \\  (equal? (tag (+ 40 2)) '(fst 42 (quasiquote (nested (unquote ignore))))))
    );
}

test "renamed template token still matches an unbound syntax-rules literal" {
    // cm-match's template emits marker tokens (`<...>`) that a helper macro
    // declares as literals. The token is template-introduced, so hygiene
    // renames it (__hyg_N_<...>); the literal comparison now strips the
    // prefix and accepts the match when the literal is unbound on both
    // sides — the rename existed precisely because the name had no binding.
    try th.expectEval(
        \\(begin
        \\  (define-syntax use (syntax-rules () ((_ m) (m tok))))
        \\  (define-syntax probe
        \\    (syntax-rules (tok) ((_ tok) 42) ((_ x) 0)))
        \\  (use probe))
    , 42);
}

test "user text spliced through generated macros keeps its identity (#1644)" {
    // The SRFI 257 CPS protocol: user identifiers ride through pattern-var
    // substitutions into GENERATED macros' specs, across many expansion
    // generations. Each generation used to re-walk the spliced text as
    // template material, renaming the same identifier under a different
    // scope each time and severing binders from references. Spliced chunks
    // are now wrapped in a provenance marker (USERTEXT_MARKER), instantiated
    // in substitute-don't-rename mode, and unwrapped at the compile boundary.
    // Distilled: `use` builds a macro whose spec embeds the user expression
    // (u 40), which must still see the caller's `u` when it finally expands.
    try th.expectEval(
        \\(begin
        \\  (define-syntax use
        \\    (syntax-rules ()
        \\      ((_ e)
        \\       (let-syntax ((go (syntax-rules () ((_ v) (+ v e)))))
        \\         (go 2)))))
        \\  (define (f u) (use (u 40)))
        \\  (f (lambda (x) x)))
    , 42);
}

test "syntax-rules literal bound in an enclosing frame matches across lambdas" {
    // literal_bound recorded a literal's definition-site binding with a
    // same-frame-only lookup while the use-site check walks the whole
    // lexical chain, so a literal bound in an ENCLOSING function frame
    // compared def=unbound vs use=bound and was rejected. This broke SRFI
    // 257's non-linear patterns: if-new-var's generated matcher runs inside
    // generated backtracking lambdas, and the repeated variable's equality
    // branch was never taken. Both sides now resolve through the chain.
    try th.expectEvalTrue(
        \\(begin
        \\  (define (f p)
        \\    ((lambda ()
        \\       (let-syntax ((hit? (syntax-rules (p) ((_ p) #t) ((_ x) #f))))
        \\         (hit? p)))))
        \\  (f 1))
    );
}

test "macro argument with a cyclic datum-label literal expands and compiles" {
    // stripUsertextMarkers runs on every expansion output; its cdr-spine walk
    // must terminate on cyclic pairs (tortoise-hare, cf. countPairs) instead
    // of hanging when a macro is invoked with #0=(1 . #0#)-style data.
    try th.expectEval(
        \\(begin
        \\  (define-syntax id (syntax-rules () ((_ x) x)))
        \\  (car (id '#0=(1 . #0#))))
    , 1);
}

test "user text spliced into a vector literal is unwrapped" {
    // A pattern-var substitution inside a nested syntax-rules template gets a
    // provenance marker; when the splice lands inside a VECTOR literal, the
    // compile-boundary strip must descend into vector elements or the marker
    // pair leaks into runtime data.
    try th.expectEval(
        \\(begin
        \\  (define-syntax vb
        \\    (syntax-rules ()
        \\      ((_ e)
        \\       (let-syntax ((g (syntax-rules () ((_) (vector-ref #(e) 0)))))
        \\         (g)))))
        \\  (if (equal? (vb foo) 'foo) 42 0))
    , 42);
}

test "macro expanding directly to a vector literal is stripped" {
    // When the WHOLE expansion is a vector (not a pair), the compile-boundary
    // strip call sites must still run — gating on isPair alone let a marker
    // inside #(e) leak into the vector constant.
    try th.expectEval(
        \\(begin
        \\  (define-syntax vb2
        \\    (syntax-rules ()
        \\      ((_ e)
        \\       (let-syntax ((g (syntax-rules () ((_) #(e)))))
        \\         (vector-ref (g) 0)))))
        \\  (if (equal? (vb2 foo) 'foo) 42 0))
    , 42);
}

test "forged cyclic usertext-marker datum does not hang unwrap" {
    // User data shaped like the internal provenance marker is out-of-contract
    // (the __hyg_ namespace is reserved by the expander), but a cyclic forgery
    // #0=(__hyg-usertext . #0#) must still terminate: unwrapUsertext bounds
    // its chain walk. The datum simply flows through as (some) datum.
    try th.expectEval(
        \\(begin
        \\  (define-syntax id (syntax-rules () ((_ x) x)))
        \\  (if (pair? (id '#0=(__hyg-usertext . #0#))) 42 0))
    , 42);
}

test "quoted template symbol is eq? across separate macro invocations (#1801)" {
    // #1801: renameForHygiene used to strip hygiene from a template-
    // introduced identifier the instant it saw QUOTE_FLAG, which happened
    // to make two separate expansions of `'g` collapse to the exact same
    // bare symbol -- correct here, but for the wrong reason (an accident of
    // never distinguishing them at all, rather than the compiler stripping
    // a per-expansion hygienic rename back off). Guards against a fix that
    // over-corrects and makes ordinary quoted-symbol macros stop producing
    // eq? results; see tests_pipeline.zig for the complementary pre-compile
    // check that the two expansions DO differ before this point.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen (syntax-rules () ((gen) 'g)))
        \\  (eq? (gen) (gen)))
    );
}

test "quoted template symbol still prints as the plain symbol (#1801)" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen (syntax-rules () ((gen) 'g)))
        \\  (eq? 'g (gen)))
    );
}

test "let-bound identifier and its quoted cross-macro reference stay consistent (#1801)" {
    // A template-introduced identifier used both as a `let` binding (real
    // code, inside quasiquote's literal structure) and, quoted, as an
    // argument threaded to a SEPARATE macro (SRFI 148's simple-match /
    // %compile-pattern shape, ported in tests/scheme/srfi/srfi148.scm) must
    // resolve to the same base name once compiled. An earlier draft of the
    // #1801 fix cleared VERBATIM_FLAG whenever entering ANY quote/quasiquote
    // reached via a usertext-marker rewalk, which let the `let` binding's
    // own hygienic rename diverge from a separately-compiled quoted
    // reference to it -- desyncing the two.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax with-e-bound
        \\    (syntax-rules ()
        \\      ((_ helper)
        \\       `(let ((e 42))
        \\          ,(helper 'e)))))
        \\  (define-syntax quote-arg
        \\    (syntax-rules ()
        \\      ((_ x) 'x)))
        \\  (eq? 'e (eval (with-e-bound quote-arg) (interaction-environment))))
    );
}

test "nested quasiquote template matches the directly written form" {
    // The template walk tracks quasiquote nesting (3 bits, 0-7, saturating);
    // a nested tower with depth-matching unquotes must expand to exactly what
    // the same expression means written directly — renaming suppressed in the
    // data layers, substitution and expression re-entry intact at depth 0.
    // (Towers whose unquotes fully unwind at depth >= 3 cannot be validated
    // end-to-end: the runtime quasiquote evaluator rejects them, macro or
    // no macro — a separate pre-existing limitation.)
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax q2
        \\    (syntax-rules ()
        \\      ((_ e) ``(a ,,e))))
        \\  (equal? (q2 (+ 40 2))
        \\          ``(a ,,(+ 40 2))))
    );
}

// SRFI 149 (Basic Syntax-rules Template Extensions) regression coverage.
// Confirmed via a dedicated research pass that Kaappi's expander already
// implements both of this SRFI's extensions with zero code changes needed —
// these tests exist purely to guard against a future regression, since
// expander.zig's ellipsis/hygiene logic has a history of subtle breakage.

test "SRFI 149: consecutive ellipses on a depth-2 variable flatten one level" {
    // The spec's own worked example: (my-append (a ...) ...) with template
    // (a ... ...) — R7RS's strict grammar requires extra parens for this
    // ((a ...) ...) with a nested single-ellipsis template); 149 permits the
    // flat two-token form directly, which Kaappi's reader already accepted.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax my-append
        \\    (syntax-rules () ((_ (a ...) ...) (list a ... ...))))
        \\  (equal? (my-append (1 2 3) (4 5 6)) '(1 2 3 4 5 6)))
    );
}

test "SRFI 149: excess ellipsis on a mixed-depth sibling replicates the shallower variable" {
    // The spec's own worked example: (foo (a b ...) ...) with template
    // (((a b) ...) ...) — a is depth 1, b is depth 2; the inner ellipsis run
    // consumes b's own extra nesting while a (already reduced to a scalar
    // one level up) is held constant across it. This is SRFI 149's own
    // "innermost excess ellipsis replicates" rule in its most basic form.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax foo
        \\    (syntax-rules () ((_ (a b ...) ...) (list (list (list 'a 'b) ...) ...))))
        \\  (equal? (foo (bar 1 2) (baz 3 4))
        \\          '(((bar 1) (bar 2)) ((baz 3) (baz 4)))))
    );
}

test "SRFI 149: consecutive-ellipsis flatten composes with a following fixed tail" {
    // Confirms the flatten mechanism correctly resumes ordinary template
    // instantiation for whatever follows the consumed ellipsis run, rather
    // than swallowing the rest of the template.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax flatten-then-tail
        \\    (syntax-rules () ((_ (a ...) ... last) (list a ... ... last))))
        \\  (equal? (flatten-then-tail (1 2) (3 4 5) 'done) '(1 2 3 4 5 done)))
    );
}

// Issue #1791: a syntax-rules template subform followed by `...` whose
// element contains no pattern variable bound under an ellipsis in the
// pattern previously expanded silently to zero copies (R7RS 4.3.2 makes
// this an error). The common trigger is a typo'd bare `...` where the
// literal-ellipsis escape `(... ...)` was meant (kaappi#1787's root cause).
// Fixed in instantiateEllipsis (expander.zig): raises
// error.EllipsisNoPatternVariable instead of silently producing nothing.
// Proven safe against the nested-syntax-rules "belongs to the inner macro"
// carve-out (both call sites already gate on the identical
// ellipsisReferencesOuter predicate before reaching the raise site) — the
// third test below exercises that carve-out directly.

test "syntax-rules: ellipsis subform with no driving pattern variable is an error (#1791)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The issue's own example: `tok` is not a pattern variable at all.
    _ = try vm.eval(
        \\(define-syntax demo
        \\  (syntax-rules ()
        \\    ((_) '(head tok ... tail))))
    );
    const result = vm.eval("(demo)");
    try std.testing.expectError(error.CompileError, result);
}

test "syntax-rules: ordinary ellipsis broadcast still works (#1791 regression guard)" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax my-list
        \\    (syntax-rules () ((_ x ...) (list x ...))))
        \\  (equal? (my-list 1 2 3) '(1 2 3)))
    );
}

test "syntax-rules: macro-generating-macro's own ellipsis is preserved, not flagged (#1791 carve-out guard)" {
    // define-listify's own pattern var is `name` (the generated macro's
    // name); the NESTED syntax-rules template's `x ...` belongs entirely to
    // the generated macro's own grammar and must be preserved literally
    // during define-listify's expansion, not routed through
    // instantiateEllipsis at all. It only becomes a real, correctly-driven
    // ellipsis later, when the generated macro (my-list2) is itself used.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax define-listify
        \\    (syntax-rules ()
        \\      ((_ name)
        \\       (define-syntax name
        \\         (syntax-rules () ((_ x ...) (list x ...)))))))
        \\  (define-listify my-list2)
        \\  (equal? (my-list2 1 2 3) '(1 2 3)))
    );
}

test "syntax-rules: excess ellipsis depth with no sibling now errors (#1791, closes SRFI 149-documented gap)" {
    // lib/srfi/149.sld documented this exact case as a pre-existing,
    // deliberately-deferred gap: `a` has pattern depth 1, but the template
    // asks for 2 ellipses with no sibling variable to drive the extra
    // level. Hits the same !count_set path one recursion level down (via
    // the consecutive-ellipsis "extra_ellipsis" unwrap), so it's fixed as a
    // side effect of the same change.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax over-deep
        \\  (syntax-rules ()
        \\    ((_ a ...) (list a ... ...))))
    );
    const result = vm.eval("(over-deep 1 2 3)");
    try std.testing.expectError(error.CompileError, result);
}

test "ellipsis: sibling list var re-collected wholesale inside per-iteration template (#1721)" {
    // Different counts: formal has 2 elements, binding has 3.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax %test
        \\    (syntax-rules ()
        \\      ((_ (formal ...) (binding ...))
        \\       (list (list formal (list binding ...)) ...))))
        \\  (equal? (%test (1 2) (10 20 30))
        \\          '((1 (10 20 30)) (2 (10 20 30)))))
    );
}

test "ellipsis: sibling list var wholesale even when counts match (#1721)" {
    // Same counts: both formal and binding have 2 elements.
    // binding must still be passed wholesale (not consumed per-iteration).
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax %test
        \\    (syntax-rules ()
        \\      ((_ (formal ...) (binding ...))
        \\       (list (list formal (list binding ...)) ...))))
        \\  (equal? (%test (1 2) (10 20))
        \\          '((1 (10 20)) (2 (10 20)))))
    );
}

// SRFI 147 (Custom Macro Transformers) regression coverage. Unlike SRFI
// 139/149, this genuinely needed an engine change: compileDefineSyntax/
// compileLetSyntax/compileLetrecSyntax (compiler_macro.zig) now resolve a
// transformer-spec through resolveTransformerSpec before parsing it, so a
// macro use that itself expands to a literal (syntax-rules ...) form is
// accepted anywhere a transformer-spec is expected, not just a literal
// syntax-rules form. These tests guard the resolution loop itself and the
// GC-rooting fix found while verifying against the full test suite (see
// the "root strictly around parseSyntaxRules" comments in
// compiler_macro.zig): an earlier draft rooted the resolved spec via
// pushRoot+defer popRoot inside compileLetSyntax's per-binding loop, but
// the SAME iteration pushes an unrelated root for its own result array
// entry before that deferred pop fires, so the deferred call silently
// popped the wrong (most recent) entry off the shared LIFO root stack —
// caught only by tests/scheme/srfi/srfi257.scm failing full-suite, not by
// any of these targeted tests alone, since it takes a macro-heavy,
// multi-binding let-syntax to trigger the interleaving.

test "SRFI 147: define-syntax accepts a custom transformer (the spec's own syntax-rules* example)" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax syntax-rules*
        \\    (syntax-rules ()
        \\      ((_ (literal ...) ((keyword . pattern) . template) ...)
        \\       (syntax-rules (literal ...) ((keyword . pattern) (begin . template)) ...))))
        \\  (define-syntax bar (syntax-rules* () ((bar a b) (+ a b) (* a b))))
        \\  (equal? (bar 5 6) 30))
    );
}

test "SRFI 147: let-syntax accepts a custom transformer, with multiple bindings in one form" {
    // Multiple bindings in one let-syntax exercises the per-binding loop
    // in compileLetSyntax specifically (the site where the LIFO rooting
    // bug above was found).
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax syntax-rules*
        \\    (syntax-rules ()
        \\      ((_ (literal ...) ((keyword . pattern) . template) ...)
        \\       (syntax-rules (literal ...) ((keyword . pattern) (begin . template)) ...))))
        \\  (let-syntax ((foo (syntax-rules* () ((foo a b) (+ a b) (* a b))))
        \\               (baz (syntax-rules* () ((baz a) (- a) (- (- a))))))
        \\    (equal? (list (foo 3 4) (baz 9)) (list 12 9))))
    );
}

test "SRFI 147: letrec-syntax accepts a custom transformer" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax syntax-rules*
        \\    (syntax-rules ()
        \\      ((_ (literal ...) ((keyword . pattern) . template) ...)
        \\       (syntax-rules (literal ...) ((keyword . pattern) (begin . template)) ...))))
        \\  (letrec-syntax ((baz (syntax-rules* () ((baz a b) (+ a b) (* a b)))))
        \\    (equal? (baz 2 10) 20)))
    );
}

test "SRFI 147: a transformer-spec resolves through multiple expansion steps" {
    // alias-of-syntax-rules* expands to a syntax-rules* call, which itself
    // expands to a literal syntax-rules form -- two rounds of resolution.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax syntax-rules*
        \\    (syntax-rules ()
        \\      ((_ (literal ...) ((keyword . pattern) . template) ...)
        \\       (syntax-rules (literal ...) ((keyword . pattern) (begin . template)) ...))))
        \\  (define-syntax alias-of-syntax-rules*
        \\    (syntax-rules () ((_ spec) (syntax-rules* () . spec))))
        \\  (let-syntax ((qux (alias-of-syntax-rules* (((qux a b) (+ a b) (* a b))))))
        \\    (equal? (qux 1 2) 2)))
    );
}

test "SRFI 147: a transformer-spec that resolves to neither syntax-rules nor a macro is a compile error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval("(let-syntax ((oops (not-a-macro))) 1)");
    try std.testing.expectError(error.CompileError, result);
}

test "SRFI 147: a nearer ancestor scope's macro shadows a farther one, not the reverse" {
    // resolveTransformerSpec's ancestor-chain merge must populate
    // farthest-to-nearest (self.macros last of all), matching correct
    // lexical shadowing. A first draft populated nearest-to-farthest,
    // which meant a name redefined in 2+ ancestor generations resolved
    // to the FARTHEST definition instead of the nearest one -- caught by
    // CodeRabbit review of #1760, confirmed via this exact reproduction
    // (a 3-level nested lambda where the innermost scope's own
    // let-syntax has no local definition of its own, forcing the lookup
    // through the full ancestor chain: middle's own definition must win
    // over the outermost/top-level one, not the reverse).
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax mk-transformer
        \\    (syntax-rules () ((_) (syntax-rules () ((_ x) 'top-level)))))
        \\  (define (outer)
        \\    (define (middle)
        \\      (define-syntax mk-transformer
        \\        (syntax-rules () ((_) (syntax-rules () ((_ x) 'middle-level)))))
        \\      (define (inner)
        \\        (let-syntax ((result (mk-transformer)))
        \\          (result 1)))
        \\      (inner))
        \\    (middle))
        \\  (eq? (outer) 'middle-level))
    );
}

// Begin-wrapped-definitions and bare-keyword-alias coverage, extending
// SRFI 147 for SRFI 148's actual needs. Deeper research for SRFI 148
// (reading its reference implementation, not just spec prose) found that
// em-syntax-rules-aux1/em-syntax-rules-aux2's own core expansion bottoms
// out through exactly `(begin (define-syntax a spec) a)` -- initially
// deferred as unneeded, then shipped once this was traced through. The
// contract of resolveTransformerSpecRec changed to return an already-
// parsed Transformer rather than raw syntax-rules source, since the
// bare-symbol case has no source to hand back.

test "SRFI 147: a bare keyword aliases an existing, non-builtin macro" {
    try th.expectEvalTrue(
        \\(let-syntax ((original (syntax-rules () ((_ a) (+ a 3)))))
        \\  (let-syntax ((alias original))
        \\    (equal? (alias 4) 7)))
    );
}

test "SRFI 147: aliasing a builtin special form is still a compile error" {
    // Builtins are recognized structurally (ir_mod.isSpecialForm), never
    // stored as Transformer values in the macro table a bare symbol
    // resolves against -- so there is nothing to alias.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval("(let-syntax ((my-if if)) (my-if #t 1 2))");
    try std.testing.expectError(error.CompileError, result);
}

test "SRFI 147: em-syntax-rules-aux1 shape -- begin-wrapped helper aliased by bare symbol" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-adder
        \\    (syntax-rules ()
        \\      ((_ n)
        \\       (begin
        \\         (define-syntax adder (syntax-rules () ((_ x) (+ x n))))
        \\         adder))))
        \\  (let-syntax ((add10 (gen-adder 10)))
        \\    (equal? (add10 5) 15)))
    );
}

test "SRFI 147: a begin-internal helper referenced BY NAME from the final template must persist" {
    // This is the case #1762 alone did not cover: em-syntax-rules-aux2's
    // own base case expands to `(begin (define-syntax o spec) o)` where
    // the SURROUNDING syntax-rules body also calls `o` directly from
    // within its own rules (not just as the bare tail) -- so `o` must
    // keep resolving every time the macro being defined is later
    // invoked, not just while resolving this one transformer-spec. A
    // helper registered only in resolveTransformerSpec's transient,
    // function-local merged_macros (gone once that call returns) cannot
    // satisfy this: it must be registered in the real, persistent macro
    // table (self.macros / lib_env), matching what an ordinary
    // define-syntax at the same nesting depth gets. Confirmed via direct
    // reproduction: this failed with "undefined variable '__hyg_N_step1'"
    // before the fix. Called twice to confirm persistence, not a
    // one-shot side effect of evaluation order.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-cross-ref
        \\    (syntax-rules ()
        \\      ((_ n)
        \\       (begin
        \\         (define-syntax step1 (syntax-rules () ((_ x) (* x n))))
        \\         (define-syntax step2 (syntax-rules () ((_ x) (step1 (+ x 1)))))
        \\         (syntax-rules () ((_ y) (step2 y)))))))
        \\  (define-syntax use-cross-ref (gen-cross-ref 3))
        \\  (and (equal? (use-cross-ref 4) 15)
        \\       (equal? (use-cross-ref 6) 21)))
    );
}

test "SRFI 147: same begin-internal helper name in two unrelated macros does not collide" {
    // Hygienic renaming must keep each expansion's "step"/"shared-name"
    // distinct even though both end up permanently registered in the
    // same persistent macro table.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-plus
        \\    (syntax-rules ()
        \\      ((_ n)
        \\       (begin (define-syntax shared-name (syntax-rules () ((_ x) (+ x n))))
        \\              shared-name))))
        \\  (define-syntax gen-minus
        \\    (syntax-rules ()
        \\      ((_ n)
        \\       (begin (define-syntax shared-name (syntax-rules () ((_ x) (- x n))))
        \\              shared-name))))
        \\  (define-syntax use-plus (gen-plus 1))
        \\  (define-syntax use-minus (gen-minus 1))
        \\  (equal? (list (use-plus 10) (use-minus 10)) (list 11 9)))
    );
}

test "SRFI 147: persistent registration works inside a nested body scope, not just top level" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define (nested-cross-ref)
        \\    (define-syntax gen-nested
        \\      (syntax-rules ()
        \\        ((_ n)
        \\         (begin
        \\           (define-syntax nested-step (syntax-rules () ((_ x) (* x n))))
        \\           (syntax-rules () ((_ y) (nested-step y)))))))
        \\    (define-syntax use-nested (gen-nested 100))
        \\    (use-nested 3))
        \\  (equal? (nested-cross-ref) 300))
    );
}

test "SRFI 147: chained resolution through nested begin-wrapped aliases" {
    // Simulates em-syntax-rules-aux1 -> aux2's own multi-stage chaining:
    // a begin-wrapped alias whose own helper's spec is ANOTHER macro use
    // that itself resolves to a further begin-wrapped alias.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax stage-inner
        \\    (syntax-rules ()
        \\      ((_ n)
        \\       (begin (define-syntax inner-helper (syntax-rules () ((_ x) (* x n))))
        \\              inner-helper))))
        \\  (define-syntax stage-outer
        \\    (syntax-rules ()
        \\      ((_ n)
        \\       (begin (define-syntax outer-helper (stage-inner n))
        \\              outer-helper))))
        \\  (let-syntax ((chained (stage-outer 7)))
        \\    (equal? (chained 6) 42)))
    );
}

test "SRFI 147: two sibling let-syntax bindings resolving to the same Transformer don't leak" {
    // CodeRabbit-caught on this PR: `p`'s spec is a begin-wrapped helper
    // reference and `q`'s spec is a bare alias of the SAME helper name --
    // compileLetSyntax's per-binding loop then holds the exact same
    // Transformer Value in tx_vals twice. finalizeTransformer already
    // guards captured_locals/bound_free_refs against a second pass, but
    // let_syntax_peer_names/vals are set in a separate block in this same
    // loop with no such guard, and unconditionally `dupe`s+overwrites on
    // every iteration -- the second iteration (`q`) leaked the first pair
    // of allocations (`p`'s) before this test's fix. `h`'s own template
    // references sibling `r` (also bound by this same let-syntax) so
    // peer_names_f/vals are genuinely non-empty for both iterations --
    // with an EMPTY peer set the dupe of a zero-length slice doesn't
    // actually allocate, which would make this test pass even without
    // the fix (confirmed: the first draft of this test used a peer-free
    // template and did not catch the leak on a mutation-test revert of
    // the fix). Also exercises that R7RS 4.3.1 sibling suppression itself
    // still works through the shared-Transformer path: `r`'s outer
    // (pre-let-syntax) binding is a procedure, unrelated to the sibling
    // macro of the same name, so `(q 42)` = `(+ 42 1)` = 43, not the
    // sibling macro's `(* 42 100)`. Run under the Debug allocator (zig
    // build test, no -Doptimize=ReleaseFast), which is what actually
    // catches the leak; the returned value alone wouldn't distinguish a
    // leak from correct behavior.
    try th.expectEvalTrue(
        \\(begin
        \\  (define (r y) (+ y 1))
        \\  (equal?
        \\   (let-syntax ((r (syntax-rules () ((_ y) (* y 100))))
        \\                (p (begin (define-syntax h (syntax-rules () ((_ x) (r x)))) h))
        \\                (q h))
        \\     (q 42))
        \\   43))
    );
}

test "SRFI 147: reusing a persisted helper across two SEPARATE let-syntax forms doesn't leak" {
    // CodeRabbit-caught follow-up to the sibling-reuse leak fix above: a
    // transformer aliased into a DIFFERENT, later, unrelated let-syntax
    // form reaches the SAME peer-computation code a second time.
    // `r1` here is a plain top-level PROCEDURE, never a macro before
    // either form, so let_syntax_peer_names/vals (built from
    // self.macros.get, not self.globals) never captures anything for it
    // either way -- this test only demonstrates the leak (a non-empty
    // allocation from a genuine free reference, freed correctly whether
    // or not the snapshot gets recomputed), not whether recomputing vs.
    // reusing the snapshot changes the RESULT. See the next two tests for
    // that: they use a macro (not a procedure) as the shared free
    // reference specifically because only a macro's identity is
    // captured by this mechanism at all.
    try th.expectEvalTrue(
        \\(begin
        \\  (define (r1 y) (+ y 1))
        \\  (let-syntax ((r1 (syntax-rules () ((_ y) (* y 100))))
        \\               (p (begin (define-syntax h (syntax-rules () ((_ x) (r1 x)))) h)))
        \\    (p 5))
        \\  (equal? (let-syntax ((q h)) (q 10)) 11))
    );
}

test "SRFI 147: a helper's peer snapshot is frozen at its TRUE point of origin, never recomputed" {
    // CodeRabbit-caught: an EARLIER draft of this fix let a transformer's
    // R7RS 4.3.1 sibling-suppression snapshot be recomputed every time it
    // reached a NEW let-syntax form (guarded only by a scan of that one
    // call's own tx_vals, matching the leak-only concern above) --
    // reasoning that a transformer aliased elsewhere "genuinely needs its
    // own peer snapshot against that different form's siblings". That
    // reasoning was WRONG: recomputing doesn't just waste an allocation,
    // it can silently change which binding a macro's free reference
    // resolves to, since the "peer snapshot" is precisely what freezes a
    // template's own references against outer shadowing (R7RS 4.3.1) --
    // recomputing it against a DIFFERENT form's outer bindings defeats
    // the entire mechanism. Confirmed via direct reproduction: redefining
    // the top-level MACRO meaning of a shared sibling name between two
    // forms changed a previously shipped answer from 11 to -10 (using
    // the SECOND form's redefinition instead of the first's, where h1
    // was actually defined) before this fix's peers_computed flag made
    // the snapshot permanent instead of per-call. Using a macro (not a
    // procedure, as the leak test above does) is essential here: a plain
    // procedure reference isn't captured by let_syntax_peer_vals at all
    // (it comes from self.macros, not self.globals), so a test built on
    // one can't distinguish "recomputed" from "reused" -- only a shared
    // sibling that is itself a macro can.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax r1 (syntax-rules () ((_ y) (+ y 1))))
        \\  (define result1
        \\    (let-syntax ((r1 (syntax-rules () ((_ y) (* y 100))))
        \\                 (p (begin (define-syntax h1 (syntax-rules () ((_ x) (r1 x)))) h1)))
        \\      (p 5)))
        \\  (define-syntax r1 (syntax-rules () ((_ y) (- y))))
        \\  (define result2
        \\    (let-syntax ((r1 (syntax-rules () ((_ y) (* y 9999))))
        \\                 (q1 h1))
        \\      (q1 10)))
        \\  (equal? (list result1 result2) (list 6 11)))
    );
}

test "SRFI 147: nesting a reuse inside the defining form's own body doesn't corrupt the outer binding" {
    // CodeRabbit-caught: the reproduction above uses two SEPARATE,
    // sequential top-level forms. This one nests the reuse INSIDE the
    // very same let-syntax body that first defines the helper, then
    // checks the OUTER binding (`p`) still resolves correctly
    // AFTERWARD -- confirming the corruption isn't specific to top-level
    // sequencing. Before this fix, the nested `q1`'s own peer
    // recomputation used ONLY that inner let-syntax's own sibling set
    // (just `q1` itself, no `r1`), silently emptying h1's peer snapshot
    // -- which let the OUTER let-syntax's own `r1` sibling rebinding
    // (`* y 100`) leak through unsuppressed for BOTH the nested call and
    // the later outer one: `(q1 20)` wrongly returned 2000 instead of 21,
    // and `(p 5)` -- called AFTER, unrelated to the nested reuse except
    // for sharing h1's object -- wrongly returned 500 instead of 6.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax r1 (syntax-rules () ((_ y) (+ y 1))))
        \\  (let-syntax ((r1 (syntax-rules () ((_ y) (* y 100))))
        \\               (p (begin (define-syntax h1 (syntax-rules () ((_ x) (r1 x)))) h1)))
        \\    (and (equal? (let-syntax ((q1 h1)) (q1 20)) 21)
        \\         (equal? (p 5) 6))))
    );
}

test "SRFI 147: zero-definition begin resolves directly to the final element" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-plain
        \\    (syntax-rules ()
        \\      ((_ n) (begin (syntax-rules () ((_ x) (- x n)))))))
        \\  (let-syntax ((sub2 (gen-plain 2)))
        \\    (equal? (sub2 10) 8)))
    );
}

test "SRFI 147: malformed begin body is a compile error, not a silent success" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval(
        \\(let-syntax ((oops (begin (define x 1) (syntax-rules () ((_ y) y)))))
        \\  (oops 1))
    );
    try std.testing.expectError(error.CompileError, result);
}

test "SRFI 147: a bare symbol resolving to nothing is a compile error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval(
        \\(let-syntax ((oops (begin (define-syntax a (syntax-rules () ((_ x) x))) b)))
        \\  (oops 1))
    );
    try std.testing.expectError(error.CompileError, result);
}

// ---------------------------------------------------------------------------
// SRFI 211 (procedural macro transformers) + SRFI 213 (identifier
// properties) — the issue #1699 closing slice. The transformer expression
// evaluates at macro-definition time (global env); the ER rename/compare
// procedures ride expander.expandProceduralMacro's threadlocal context;
// SRFI 213 lookups arrive through the procedure-result re-entry protocol.
// End-to-end conformance lives in tests/scheme/srfi/srfi211.scm and
// srfi213.scm; these cover the engine seams.
// ---------------------------------------------------------------------------

test "SRFI 211: er-macro-transformer expands with definition-env resolution" {
    try th.expectEval(
        \\(begin
        \\  (define-syntax add1
        \\    (er-macro-transformer
        \\     (lambda (form rename compare) (list (rename '+) (car (cdr form)) 1))))
        \\  (add1 41))
    , 42);
}

test "SRFI 211: rename gensyms fresh names so introduced binders cannot capture" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax with-t
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'let) (list (list (rename 'er-t) 999))
        \\             (car (cdr form))))))
        \\  (define er-t 'user)
        \\  (eq? (with-t er-t) 'user))
    );
}

test "SRFI 211: rename is consistent within one expansion" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax same?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (eq? (rename 'zzq) (rename 'zzq))))))
        \\  (same?))
    );
}

test "SRFI 211: compare answers free-identifier equality for else" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax is-else?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (compare (car (cdr form)) (rename 'else))))))
        \\  (and (is-else? else) (not (is-else? other))))
    );
}

test "SRFI 211: lisp-transformer receives the whole use datum, unhygienically" {
    try th.expectEval(
        \\(begin
        \\  (define-syntax lt
        \\    (lisp-transformer
        \\     (lambda (form) (list '+ (length form) (car (cdr form))))))
        \\  (lt 40))
    , 42);
}

test "SRFI 211: transformer spec evaluating to a non-procedure is a compile error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval("(define-syntax bad (er-macro-transformer 42))");
    try std.testing.expectError(error.CompileError, result);
}

test "SRFI 211: transformer raising at expansion time is a compile error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(define-syntax boom
        \\  (er-macro-transformer (lambda (f r c) (error "expansion refused"))))
    );
    const result = ctx.vm.eval("(boom)");
    try std.testing.expectError(error.CompileError, result);
}

test "SRFI 211: a global transformer value works as a bare-symbol spec" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define tx-val (er-macro-transformer (lambda (f r c) (list (r 'quote) 'ok))))
        \\  (define-syntax via tx-val)
        \\  (eq? (via) 'ok))
    );
}

test "SRFI 213: define-property evaluates now and lookup reads it back" {
    try th.expectEval(
        \\(begin
        \\  (define pk 'the-key)
        \\  (define pv 40)
        \\  (define-property pv pk (+ 2 40))
        \\  (define-syntax getp
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (lambda (lookup)
        \\         (lookup (car (cdr form)) (car (cdr (cdr form))))))))
        \\  (getp pv pk))
    , 42);
}

test "SRFI 213: missing property is #f and the binding keeps its meaning" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define qk 'k2)
        \\  (define qv 7)
        \\  (define-property qv qk 'present)
        \\  (define-syntax getp2
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (lambda (lookup)
        \\         (list (rename 'quote) (lookup (car (cdr form)) (car (cdr (cdr form)))))))))
        \\  (and (eq? (getp2 qv qk) 'present)
        \\       (eq? (getp2 qv missing) #f)
        \\       (= qv 7)))
    );
}

test "SRFI 213: define-property in a body scope is rejected" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval(
        \\(define (f)
        \\  (define-property f f 1)
        \\  1)
    );
    try std.testing.expectError(error.CompileError, result);
}
