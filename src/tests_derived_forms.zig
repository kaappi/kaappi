// Phase 3: Derived expression forms (and, or, when, unless, cond, let, let*, letrec, named let, do)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "eval and" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(and)"));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(and 1 2 3)")));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(and 1 #f 3)"));
}

test "eval or" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(or)"));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(or 1 2)")));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(or #f #f 3)")));
}

test "eval when and unless" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.VOID, try vm.eval("(when #t 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(when #f 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(unless #f 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(unless #t 42)"));
}

test "eval cond" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond (#t 1))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(cond (#f 1) (else 2))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(cond (#f 1) (#t 2) (else 3))")));
}

test "eval let" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(let ((x 1) (y 2)) (+ x y))")));
}

test "eval let*" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(let* ((x 1) (y (+ x 1))) y)")));
}

test "eval letrec" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(letrec ((f (lambda (n) (if (= n 0) 1 (* n (f (- n 1))))))) (f 5))");
    try std.testing.expectEqual(@as(i64, 120), types.toFixnum(result));
}

test "eval named let" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let loop ((i 0) (s 0)) (if (= i 5) s (loop (+ i 1) (+ s i))))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));
}

test "eval do" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Simple do: just counting - void result
    const r0 = try vm.eval("(do ((i 0 (+ i 1))) ((= i 3)))");
    try std.testing.expectEqual(types.VOID, r0);

    // Simple do: just counting
    const r1 = try vm.eval("(do ((i 0 (+ i 1))) ((= i 3) i))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r1));

    // Two variables with accumulation
    const result = try vm.eval("(do ((i 0 (+ i 1)) (s 0 (+ s i))) ((= i 5) s))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));
}
