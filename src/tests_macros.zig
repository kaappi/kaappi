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
