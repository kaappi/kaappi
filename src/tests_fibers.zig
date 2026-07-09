const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");

// Regression tests for the fiber scheduler give-up path (#kaappi-book):
// runSchedulerUntil used to silently return VOID when no fiber was runnable
// while intermediate fibers sat blocked in nested channel-receive calls.
// Multi-stage pipelines got VOID instead of blocking, and true deadlocks
// spun forever instead of raising an error.

test "channel values flow through a two-stage fiber pipeline" {
    // Stage fibers block on channels that only fill after an outer-nested
    // fiber runs — the non-LIFO case the recursive scheduler could not
    // resume. Parked fibers must be woken by channel-send and re-execute
    // their receive, not resume with an unspecified value.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define (add-stage in-ch proc)
        \\  (let ((out-ch (make-channel)))
        \\    (spawn (lambda ()
        \\      (let process ()
        \\        (let ((val (channel-receive in-ch)))
        \\          (unless (eq? val 'eof)
        \\            (channel-send out-ch (proc val))
        \\            (process))))
        \\      (channel-send out-ch 'eof)))
        \\    out-ch))
        \\(define source (make-channel))
        \\(define output
        \\  (add-stage (add-stage source (lambda (x) (* x x)))
        \\             (lambda (x) (+ x 1))))
        \\(spawn (lambda ()
        \\  (for-each (lambda (n) (channel-send source n)) '(1 2 3 4 5))
        \\  (channel-send source 'eof)))
    );
    const result = try vm.eval(
        \\(let loop ((acc '()))
        \\  (let ((val (channel-receive output)))
        \\    (if (eq? val 'eof)
        \\        (reverse acc)
        \\        (loop (cons val acc)))))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(2 5 10 17 26)", s);
}

test "channel-receive with no scheduler raises deadlock error" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define ch (make-channel))");
    const result = vm.eval("(channel-receive ch)");
    try std.testing.expectError(vm_mod.VMError.ExceptionRaised, result);
}

test "channel-receive deadlock with blocked fibers raises instead of returning void" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define ch (make-channel))
        \\(define f (spawn (lambda () (channel-receive ch))))
    );
    const result = vm.eval("(channel-receive ch)");
    try std.testing.expectError(vm_mod.VMError.ExceptionRaised, result);
}

test "channel-receive deadlock error is catchable by guard" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e (#t (if (string=? "channel-receive: deadlock — channel is empty and no fibers are running"
        \\                             (error-object-message e))
        \\                  'deadlock-reported
        \\                  'wrong-message)))
        \\  (channel-receive (make-channel)))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("deadlock-reported", s);
}

test "fiber-join on a permanently blocked fiber raises deadlock error" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define ch (make-channel))
        \\(define f (spawn (lambda () (channel-receive ch))))
    );
    const result = vm.eval("(fiber-join f)");
    try std.testing.expectError(vm_mod.VMError.ExceptionRaised, result);
}

test "fiber parked on a channel resumes when a later top-level form sends" {
    // The fiber parks (.waiting) during the first form; the send in a later
    // form must wake it and re-execute its channel-receive.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define ch (make-channel))
        \\(define out (make-channel))
        \\(define f (spawn (lambda () (channel-send out (* 2 (channel-receive ch))))))
        \\(yield)
    );
    _ = try vm.eval("(channel-send ch 21)");
    const result = try vm.eval("(channel-receive out)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "fiber parked inside apply-forwarded channel-receive retries the apply" {
    // apply invokes channel-receive through vm.callWithArgs without a new
    // dispatch loop; the park signal (yield_retry + error.Yielded) must
    // propagate through applyFn intact so the apply call is retried on wake
    // (previously it was swallowed into a TypeError).
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define ch (make-channel))
        \\(define out (make-channel))
        \\(define f (spawn (lambda ()
        \\  (channel-send out (apply channel-receive (list ch))))))
        \\(yield)
    );
    _ = try vm.eval("(channel-send ch 21)");
    const result = try vm.eval("(channel-receive out)");
    try std.testing.expectEqual(@as(i64, 21), types.toFixnum(result));
}

test "fiber blocked inside for-each callback deadlocks when nothing runnable" {
    // The fiber parks inside for-each's callback (now bytecode-driven).
    // With no sender and nothing else runnable the scheduler detects
    // deadlock and raises a catchable error in the blocked fiber.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(define ch (make-channel))
        \\(define f (spawn (lambda ()
        \\  (guard (e (#t 'fiber-deadlock))
        \\    (for-each (lambda (x) (channel-receive ch)) '(1 2))))))
        \\(fiber-join f)
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("fiber-deadlock", s);
}

test "main fiber still blocked after guard-recovered deadlock can be unblocked" {
    // A deadlock error must leave the scheduler in a usable state: parked
    // fibers stay parked and a subsequent send lets everything drain.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define ch (make-channel))
        \\(define out (make-channel))
        \\(define f (spawn (lambda () (channel-send out (+ 1 (channel-receive ch))))))
        \\(define first-try
        \\  (guard (e (#t 'blocked))
        \\    (channel-receive out)))
    );
    const first = try vm.eval("first-try");
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, first, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("blocked", s);

    _ = try vm.eval("(channel-send ch 41)");
    const result = try vm.eval("(channel-receive out)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "fiber parks inside for-each callback and is woken by channel-send" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(define ch (make-channel))
        \\(define out (make-channel))
        \\(define f (spawn (lambda ()
        \\  (define total 0)
        \\  (for-each (lambda (x) (set! total (+ total (channel-receive ch)))) '(a b c))
        \\  (channel-send out total))))
        \\(channel-send ch 10)
        \\(channel-send ch 20)
        \\(channel-send ch 30)
        \\(channel-receive out)
    );
    try std.testing.expectEqual(@as(i64, 60), types.toFixnum(result));
}
