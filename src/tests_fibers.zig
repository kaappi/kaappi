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
        \\(yield)
        \\(channel-send ch 10)
        \\(yield)
        \\(channel-send ch 20)
        \\(yield)
        \\(channel-send ch 30)
        \\(channel-receive out)
    );
    try std.testing.expectEqual(@as(i64, 60), types.toFixnum(result));
}

test "yield inside guard with a runnable fiber is a no-op, not an error" {
    // Regression for #1184: with another fiber schedulable, (yield) inside a
    // guard body armed the Yielded unwind, which with-exception-handler's
    // generic error conversion turned into a contentless "error" exception.
    // An advisory yield under a re-entrant native frame must be a no-op.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define f (spawn (lambda () (channel-receive (make-channel)))))");
    const result = try vm.eval(
        \\(guard (e (#t 'error-caught))
        \\  (begin (yield) 'yield-ok))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("yield-ok", s);
}

test "processor-count returns a positive fixnum" {
    // KEP-0002 Phase 5 (#1470): backs (kaappi parallel), tagged .kaappi_fibers
    // (see src/primitives_parallel.zig) so it's already a global here with no
    // import needed, same as any other registered primitive.
    try th.expectEvalTrue("(and (integer? (processor-count)) (exact? (processor-count)) (> (processor-count) 0))");
}

// Rendezvous channels (KEP-0002 §6 as amended; #1600/#1601/#1602):
// (make-channel 0) pairs a sender with a committed receiver instead of the
// pre-amendment "permanently full" degenerate behavior.

test "rendezvous channel: fiber sender pairs with main receiver (#1600 repro)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define ch (make-channel 0))");
    _ = try vm.eval("(spawn (lambda () (channel-send ch 41)))");
    const result = try vm.eval("(+ 1 (channel-receive ch))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "rendezvous channel: main sender pairs with fiber receiver" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define ch (make-channel 0))");
    _ = try vm.eval("(define f (spawn (lambda () (channel-receive ch))))");
    _ = try vm.eval("(channel-send ch 7)");
    const result = try vm.eval("(fiber-join f)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "rendezvous channel: demand token accounting stays balanced" {
    // The §4 step 7a token discipline: every terminal exit of a receive —
    // timeout, guarded deadlock raise, delivered value — must leave
    // rv_demand at zero once no receiver is committed. A leak here admits
    // sends nobody will ever collect.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define ch (make-channel 0))");
    const ch_val = try vm.eval("ch");
    const ch = types.toObject(ch_val).as(types.Channel);

    // timed-out receive releases its token
    _ = try vm.eval("(channel-receive ch 0.02 'to)");
    try std.testing.expectEqual(@as(u32, 0), ch.rv_demand);

    // a guarded deadlock raise releases too
    _ = try vm.eval("(guard (e (#t 'dead)) (channel-receive ch))");
    try std.testing.expectEqual(@as(u32, 0), ch.rv_demand);

    // a completed handoff releases the receiver's token
    _ = try vm.eval("(spawn (lambda () (channel-send ch 'v)))");
    _ = try vm.eval("(channel-receive ch)");
    try std.testing.expectEqual(@as(u32, 0), ch.rv_demand);
    try std.testing.expectEqual(@as(u32, 0), ch.queue_len);
}

test "rendezvous channel: timed-out receive leaves no phantom demand for senders" {
    // Pure-behavior twin of the accounting test: if the timed-out
    // receiver's token leaked, the later timed send would be admitted and
    // strand its value; if a value were stranded, the final receive would
    // return it instead of timing out.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let ((ch (make-channel 0)))
        \\  (list (channel-receive ch 0.02 'rto)
        \\        (channel-send ch 'v 0.02 'sto)
        \\        (channel-receive ch 0.02 'empty)))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(rto sto empty)", s);
}

test "rendezvous channel: parked timed senders pair under a nested main receive" {
    // Regression for the frozen-ancestor interleaving found while testing
    // #1602: two *timed* sends used to park in-call (driving), the main
    // fiber's receive was dispatched as the innermost nested frame, and its
    // demand-wake could never reach the driving ancestors (#1487) — the
    // receive raised a spurious KP3000 deadlock with two viable senders
    // frozen beneath it. The flat yield_retry park keeps every rendezvous
    // waiter dispatchable.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define ch (make-channel 0))");
    _ = try vm.eval("(define s1 (spawn (lambda () (channel-send ch 'a 0.5 'ta))))");
    _ = try vm.eval("(define s2 (spawn (lambda () (channel-send ch 'b 0.5 'tb))))");
    _ = try vm.eval("(yield)");
    const got = try vm.eval("(channel-receive ch)");
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, got, .write);
    defer std.testing.allocator.free(s);
    const one_of = std.mem.eql(u8, s, "a") or std.mem.eql(u8, s, "b");
    try std.testing.expect(one_of);
}
