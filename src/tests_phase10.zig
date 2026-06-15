// Phase 10: Continuations (R7RS 6.10)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "call/cc basic — proc returns normally" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-current-continuation (lambda (k) 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call/cc escape continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 1 (call/cc (lambda (k) (+ 2 (k 10)))))");
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "call/cc alias" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call/cc (lambda (k) (k 99)))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "call/cc continuation is a procedure" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call/cc (lambda (k) (procedure? k)))");
    try std.testing.expectEqual(types.TRUE, result);
}

test "call/cc nested escape" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Escape from nested computation
    const result = try vm.eval(
        \\(* 10 (call/cc (lambda (k)
        \\  (+ 1 (+ 2 (k 5))))))
    );
    try std.testing.expectEqual(@as(i64, 50), types.toFixnum(result));
}

test "call/cc with no invocation of continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Continuation is never invoked — proc returns normally
    const result = try vm.eval("(call/cc (lambda (k) (+ 3 4)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "dynamic-wind basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define log '())");
    _ = try vm.eval(
        \\(dynamic-wind
        \\  (lambda () (set! log (cons 'in log)))
        \\  (lambda () (set! log (cons 'body log)))
        \\  (lambda () (set! log (cons 'out log))))
    );
    const result = try vm.eval("(reverse log)");
    // Should be (in body out)
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqualStrings("in", types.symbolName(types.car(result)));
    try std.testing.expectEqualStrings("body", types.symbolName(types.car(types.cdr(result))));
    try std.testing.expectEqualStrings("out", types.symbolName(types.car(types.cdr(types.cdr(result)))));
}

test "dynamic-wind returns thunk result" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(dynamic-wind
        \\  (lambda () #f)
        \\  (lambda () 42)
        \\  (lambda () #f))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "values single value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(values 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call-with-values basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-values (lambda () (values 1 2 3)) +)");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(result));
}

test "call-with-values with list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-values (lambda () (values 1 2)) list)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
}

test "call-with-values single value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Single value should work like a normal call
    const result = try vm.eval("(call-with-values (lambda () 42) (lambda (x) (+ x 1)))");
    try std.testing.expectEqual(@as(i64, 43), types.toFixnum(result));
}

test "values with zero values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // (values) produces multiple values with zero elements
    const result = try vm.eval("(call-with-values (lambda () (values)) (lambda () 99))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "dynamic-wind with escape continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define log '())");
    const result = try vm.eval(
        \\(call/cc (lambda (k)
        \\  (dynamic-wind
        \\    (lambda () (set! log (cons 'in log)))
        \\    (lambda () (k 42))
        \\    (lambda () (set! log (cons 'out log))))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
    // After should have been called even though we escaped
    const log = try vm.eval("(reverse log)");
    try std.testing.expect(types.isPair(log));
    try std.testing.expectEqualStrings("in", types.symbolName(types.car(log)));
    try std.testing.expectEqualStrings("out", types.symbolName(types.car(types.cdr(log))));
}
