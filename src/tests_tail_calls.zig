// Phase 2: Tail calls (loop, factorial, mutual, fib, begin)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "tail-recursive loop does not overflow" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (loop n) (if (= n 0) (quote done) (loop (- n 1))))");
    const result = try vm.eval("(loop 1000000)");
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("done", types.symbolName(result));
}

test "tail-recursive factorial with accumulator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc))))");
    const result = try vm.eval("(fact 10 1)");
    try std.testing.expectEqual(@as(i64, 3628800), types.toFixnum(result));
}

test "mutual tail recursion" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))");
    _ = try vm.eval("(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))");
    const result = try vm.eval("(my-even? 10000)");
    try std.testing.expectEqual(types.TRUE, result);
}

test "non-tail recursion still works" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))");
    const result = try vm.eval("(fib 10)");
    try std.testing.expectEqual(@as(i64, 55), types.toFixnum(result));
}

test "tail call in begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (count n) (if (= n 0) 0 (begin (count (- n 1)))))");
    const result = try vm.eval("(count 100000)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result));
}

test "self-tail-recursive loop" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (self-loop n acc) (if (= n 0) acc (self-loop (- n 1) (+ acc n))))");
    const result = try vm.eval("(self-loop 1000 0)");
    try std.testing.expectEqual(@as(i64, 500500), types.toFixnum(result));
}

test "named let self-tail-recursive loop" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let loop ((n 1000) (acc 0)) (if (= n 0) acc (loop (- n 1) (+ acc n))))");
    try std.testing.expectEqual(@as(i64, 500500), types.toFixnum(result));
}

// Regression: a tail call to a global bound to a non-closure callable
// (parameter object) must go through the full tail_call handler, not the
// closure/native-only tail_call_global path. Calling a parameter in tail
// position previously errored with "not a procedure".
test "tail call to a parameter object" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define p (make-parameter 42))");
    _ = try vm.eval("(define (get) (p))");
    const result = try vm.eval("(get)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

// Regression: parameterize desugars to dynamic-wind thunks that tail-call the
// parameter and %parameter-set!. This exercises the same path end to end.
test "parameterize body with tail position calls" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define radix (make-parameter 10))");
    _ = try vm.eval("(define (f) (radix))");
    const result = try vm.eval("(parameterize ((radix 2)) (f))");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}
