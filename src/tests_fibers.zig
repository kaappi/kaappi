const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const fiber_mod = @import("fiber.zig");
const reactor_mod = @import("reactor.zig");
const platform = @import("platform.zig");

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

test "kaappi#1742: channel-receive deadlock names the other thread when one is alive but never shared this channel" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // `t` never touches `ch` -- it exists purely to make
    // crossThreadWaitPossible() true while main's channel-receive on its
    // own, never-promoted `ch` finds nothing runnable and nothing to wait
    // for. Before this fix the raised message was the bare "...and all
    // fibers are blocked", which reads as if fiber scheduling were the
    // whole story and erases the fact that another OS thread exists but
    // was simply never handed this channel.
    const result = try ctx.vm.eval(
        \\(define t (thread-start! (make-thread (lambda () (thread-sleep! 0.05)))))
        \\(define ch (make-channel))
        \\(guard (e (#t (if (and (string-contains (error-object-message e) "all fibers are blocked")
        \\                       (string-contains (error-object-message e) "never shared with it"))
        \\                  'deadlock-explained
        \\                  (error-object-message e))))
        \\  (channel-receive ch))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("deadlock-explained", s);

    _ = try ctx.vm.eval("(thread-join! t)");
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
    _ = try vm.eval("(define s1 (spawn (lambda () (if (eq? (channel-send ch 'a 0.4 'ta) 'ta) 'ta 'sent-a))))");
    _ = try vm.eval("(define s2 (spawn (lambda () (if (eq? (channel-send ch 'b 0.4 'tb) 'tb) 'tb 'sent-b))))");
    _ = try vm.eval("(yield)");
    // One-demand/one-send admission (#1604 review): joining both senders
    // pins EXACTLY one delivery and one timeout, and the final probe pins
    // that no second value was admitted and stranded — the two ways
    // findings 5/6 would have manifested here.
    const summary = try vm.eval(
        \\(let* ((got (channel-receive ch))
        \\       (r1 (fiber-join s1))
        \\       (r2 (fiber-join s2))
        \\       (rest (channel-receive ch 0.05 'empty)))
        \\  (list got r1 r2 rest))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, summary, .write);
    defer std.testing.allocator.free(s);
    const ok = std.mem.eql(u8, s, "(a sent-a tb empty)") or
        std.mem.eql(u8, s, "(b ta sent-b empty)");
    try std.testing.expect(ok);
}

// ---------------------------------------------------------------------------
// ensureScheduler cleanup on a failed allocation (#1864)
// ---------------------------------------------------------------------------
//
// ensureScheduler creates the FiberScheduler with the *raw* allocator and then
// runs two more fallible steps — the main fiber's allocFiber, and addFiber's
// append. Without an errdefer, a failure in either returns with `sched`
// neither destroyed nor stored in `vm.scheduler`, so nothing owns it: the
// struct and the managed `waiter_index` map inside it both leak. (The reactor
// block immediately below it always cleaned up after itself; these tests pin
// the scheduler block to the same contract.)
//
// The leak also blocked writing *any* OOM sweep that reaches a fiber path: the
// leak check aborts the test before its own assertions run.

test "ensureScheduler frees the scheduler when the main fiber allocation fails" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The scheduler struct comes from the raw allocator, which the injector
    // does not count, so the main fiber is ensureScheduler's first *heap*
    // allocation — countdown 0 fails exactly that one.
    gc.oom_countdown = 0;
    try std.testing.expectError(vm_mod.VMError.OutOfMemory, fiber_mod.ensureScheduler(vm));
    gc.oom_countdown = null;
    try std.testing.expect(vm.scheduler == null);
    try std.testing.expect(vm.current_fiber == null);

    // Not sticky: a later call still builds a usable scheduler, and the VM
    // owns that one, so std.testing.allocator sees exactly one of each.
    const ready = try fiber_mod.ensureScheduler(vm);
    try std.testing.expect(vm.scheduler == ready.sched);
    try std.testing.expect(vm.current_fiber != null);
}

test "spawning a fiber leaks nothing when an allocation fails" {
    // End-to-end sweep over the whole first `spawn` — the one call that
    // constructs the scheduler, and so the only point in the sweep that can
    // reach the leaking path. Fails pre-fix with one leaked allocation
    // attributed to spawnFn's `try ensureScheduler`.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var failures: usize = 0;
    var successes: usize = 0;
    var n: usize = 0;
    while (n <= 400) : (n += 1) {
        ctx.gc.oom_countdown = n;
        const result = ctx.vm.eval("(let ((f (spawn (lambda () (list 1 2 3))))) (fiber-join f))");
        ctx.gc.oom_countdown = null;
        if (result) |_| successes += 1 else |_| failures += 1;
        ctx.gc.collect();
    }
    // Both halves matter. `failures` proves the injector fired at all;
    // `successes` proves the bound ran past the *whole* allocation profile of
    // the first spawn — the run that builds the scheduler. Without that second
    // assertion a future spawn that allocates more would push the
    // ensureScheduler window past 400 and quietly make this test vacuous
    // instead of failing.
    try std.testing.expect(failures > 0);
    try std.testing.expect(successes > 0);
}

// ---------------------------------------------------------------------------
// A timeout popped by the dispatch tick must not be followed by an unbounded
// park (#1870)
// ---------------------------------------------------------------------------
//
// runSchedulerStep's loop guard reads `me.timed_out` *before* calling
// scheduleForDispatch(), whose own runReactorTick() then pops expired timers.
// When that tick pops this fiber's own deadline, wakeReadyFiber sets
// `timed_out` and the entry leaves the timer heap — and the pre-tick guard is
// already spent. Pre-fix the idle branch went straight into parkOnReactor with
// nothing left to bound reactor.poll(): the fiber's own shared_waiters entry
// keeps hasRunnableFibers() true, so the "nothing can ever happen" early
// return is skipped and the poll blocks until an unrelated cross-thread notify
// arrives. That is the SRFI-120 flake: a 30 ms timer task that never ran until
// the caller's own timer-cancel! message woke the thread seconds later.
//
// The watchdog is a safety net, not the mechanism under test: it rings the
// notifier so a pre-fix build finishes the wait instead of hanging the suite
// forever, and the elapsed-time assertion is what actually fails there.

const WaitForever = struct {
    pub fn isDone(_: WaitForever) bool {
        return false;
    }
};

fn ringAfter(flag: *std.atomic.Value(bool), n: *reactor_mod.ThreadNotifier) void {
    var waited: u64 = 0;
    while (!flag.load(.acquire) and waited < 3_000_000_000) : (waited += 5_000_000) {
        platform.sleepNs(5_000_000);
    }
    n.notify();
}

test "an expired timer popped by the dispatch tick ends the wait instead of parking unbounded" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const ctx = try fiber_mod.ensureScheduler(vm);
    const me = ctx.sched.fibers.items[ctx.sched.current_idx].?;

    // The state a timed channel-receive on a promoted channel parks in, with
    // the deadline already past so scheduleForDispatch()'s tick — not
    // parkOnReactor's own poll — is what pops it.
    me.status = .waiting;
    me.timed_out = false;
    me.deadline_ns = fiber_mod.clockNs();
    try ctx.reactor.addTimer(me.deadline_ns.?, me);
    try ctx.sched.enrollSharedWaiter(me);
    defer ctx.sched.removeSharedWaiter(me);

    var done = std.atomic.Value(bool).init(false);
    const watchdog = try std.Thread.spawn(.{}, ringAfter, .{ &done, ctx.reactor.notifier });

    const started = fiber_mod.clockNs();
    _ = try fiber_mod.runSchedulerStep(WaitForever, .{}, vm, ctx.sched, me);
    const elapsed = fiber_mod.clockNs() - started;

    done.store(true, .release);
    watchdog.join();

    // The wait must come back on its own timeout, promptly. Pre-fix it comes
    // back only when the watchdog rings, ~3 s later.
    try std.testing.expect(me.timed_out);
    try std.testing.expect(elapsed < 1_000_000_000);
}
