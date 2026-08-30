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
    if (comptime platform.is_wasm) return error.SkipZigTest; // the #1742 deadlock diagnostic needs real OS threads, unavailable on wasm
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no OS threads on wasm32-wasi (single-threaded target)
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

// #1983: timeoutToDeadlineNs is pub and backs (kaappi fibers) channel
// timeouts too, so the unguarded @intFromFloat took channel-receive down
// with the whole process on a huge timeout. A fiber sender makes the
// receive complete promptly; the timeout is converted eagerly (the old
// abort site) and then never fires.
test "channel-receive with a huge timeout converts without aborting (#1983)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define ch (make-channel 0))");
    _ = try vm.eval("(spawn (lambda () (channel-send ch 41)))");
    const result = try vm.eval("(+ 1 (channel-receive ch 1e300))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

// #1983: thread-sleep!'s own conversion site (a third copy of the same
// unguarded @intFromFloat). The sleeping fiber saturates to a deadline that
// never fires and parks; the main fiber must keep running -- before the fix
// the conversion aborted the process the moment the fiber was dispatched.
test "thread-sleep! with an unbounded duration parks without aborting (#1983)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define progress 0)
        \\(spawn (lambda () (set! progress (+ progress 1)) (thread-sleep! 1e300) 'unreachable))
        \\(spawn (lambda () (set! progress (+ progress 1)) (thread-sleep! +inf.0) 'unreachable))
        \\(let loop ((i 0))
        \\  (when (and (< progress 2) (< i 10)) (yield) (loop (+ i 1))))
    );
    // progress = 2 proves both fibers ran up to their thread-sleep! call --
    // i.e. both conversions actually executed -- and parked, rather than the
    // test passing because the fibers were never dispatched.
    const got = try vm.eval("progress");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(got));
}

// #1999: spawnFiber builds the fiber's first call frame by hand and performed
// neither the arity check nor the rest-list construction an ordinary call
// does. `registers[0]` held the thunk closure itself while `base = 0` made r0
// the callee's first parameter, so a one-argument procedure ran with its own
// thunk bound to that parameter and any further parameter reading the
// UNDEFINED register fill.
test "spawn rejects a procedure that is not a thunk (#1999)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectError(vm_mod.VMError.ArityMismatch, vm.eval("(spawn (lambda (x) 'body-ran))"));
    try std.testing.expectError(vm_mod.VMError.ArityMismatch, vm.eval("(spawn (lambda (a b c) (list a b c)))"));
    // A required parameter plus a rest parameter is not a thunk either: the
    // rest list would be empty, but `a` has nothing to bind to. This shape
    // used to bind UNDEFINED to both, making (list? r) and (null? r) BOTH #f
    // in violation of R7RS 4.1.4's "newly allocated list".
    try std.testing.expectError(vm_mod.VMError.ArityMismatch, vm.eval("(spawn (lambda (a . r) (list a r)))"));
    // A native procedure of arity >= 1 used to reach the fiber and fail there
    // with the contentless "fiber error (no exception value)".
    try std.testing.expectError(vm_mod.VMError.ArityMismatch, vm.eval("(spawn car)"));
}

test "spawn runs a pure-variadic thunk with an empty rest list (#1999)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The most natural way to write "ignore my arguments" failed outright
    // before the fix, because r0 held the thunk closure rather than the '()
    // an ordinary zero-argument call would have built.
    const result = try vm.eval("(fiber-join (spawn (lambda args (length args))))");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result));

    const shape = try vm.eval("(fiber-join (spawn (lambda args (list (list? args) (null? args)))))");
    try std.testing.expect(types.isPair(shape));
    try std.testing.expectEqual(types.TRUE, types.toObject(shape).as(types.Pair).car);
}

test "a rejected spawn allocates no fiber and leaves the scheduler usable (#1999)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The checks now precede allocFiber, which used to run first -- a refused
    // thunk left a fiber and a consumed id behind it.
    _ = try vm.eval("(define before (spawn (lambda () 'first)))");
    try std.testing.expectError(vm_mod.VMError.ArityMismatch, vm.eval("(spawn (lambda (x) x))"));
    const result = try vm.eval("(list (fiber-join before) (fiber-join (spawn (lambda () 'after))))");
    try std.testing.expect(types.isPair(result));
}

// #2204: a VM-level fault in a fiber body (type error, unbound variable,
// bad index, arity mismatch) used to cross the fiber boundary as a
// contentless KP3007 "fiber error (no exception value)". The dispatch
// loop's error arm (fiber_wait.zig) dropped the VMError tag, and
// vm.last_error_detail -- where the whole message lives -- is not part of
// the fiber's saved state, so fiber-join substituted a placeholder
// condition. The loop now converts the fault into the same coded
// ErrorObject a guard sees outside a fiber, before anything else can
// overwrite the detail, and stages it in vm.current_exception for
// saveCurrentFiber/reraiseFiberError to carry to the joiner.
test "fiber-join re-raises a fiber's VM fault with its code and message (#2204)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define five 5)");
    // CONTROL: the same fault outside a fiber is KP3002 with this message.
    const direct = try vm.eval(
        \\(guard (e (#t (list (error-object-code e) (error-object-message e))))
        \\  (car five))
    );
    // A fault after a yield exercises the dispatched-fiber path too, not
    // just the driven-in-place one.
    const joined = try vm.eval(
        \\(guard (e (#t (list (error-object-code e) (error-object-message e))))
        \\  (fiber-join (spawn (lambda () (yield) (car five)))))
    );

    const printer = @import("printer.zig");
    const want = "(KP3002 \"type error in 'car': expected pair, got 5\")";
    const s1 = try printer.valueToString(std.testing.allocator, direct, .write);
    defer std.testing.allocator.free(s1);
    try std.testing.expectEqualStrings(want, s1);
    const s2 = try printer.valueToString(std.testing.allocator, joined, .write);
    defer std.testing.allocator.free(s2);
    // Identical condition outside and inside a fiber: pre-fix the joined
    // form printed (KP3007 "fiber error (no exception value)").
    try std.testing.expectEqualStrings(want, s2);
}

test "each VM fault class keeps its own code across the fiber boundary (#2204)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Unbound variable KP3001, index KP3006, call arity KP3003 -- all used
    // to collapse to the same KP3007 placeholder.
    const result = try vm.eval(
        \\(define (code-of thunk) (guard (e (#t (error-object-code e))) (thunk) 'no-raise))
        \\(list (code-of (lambda () (no-such-variable-2204)))
        \\      (code-of (lambda () (vector-ref (vector 1) 9)))
        \\      (code-of (lambda () ((lambda (x) x))))
        \\      (code-of (lambda () (fiber-join (spawn (lambda () (no-such-variable-2204))))))
        \\      (code-of (lambda () (fiber-join (spawn (lambda () (vector-ref (vector 1) 9))))))
        \\      (code-of (lambda () (fiber-join (spawn (lambda () ((lambda (x) x))))))))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(KP3001 KP3006 KP3003 KP3001 KP3006 KP3003)", s);
}

test "a fiber's VM fault is re-raised identically on every join (#2204)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define five 5)");
    const result = try vm.eval(
        \\(let ((f (spawn (lambda () (car five)))))
        \\  (list (guard (e (#t (error-object-code e))) (fiber-join f))
        \\        (guard (e (#t (error-object-code e))) (fiber-join f))))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(KP3002 KP3002)", s);
}

// #2002: make-channel's capacity is stored as a u32, so a value that IS an
// exact integer outside [0, 2^32-1] is a range rejection -- an argument
// error (KP3007) whose message names the real bound -- while a genuinely
// non-integer argument stays a type error (KP3002). The old one-size
// typeError claimed "expected non-negative exact integer, got 4294967296",
// which argues against itself and hides the actual constraint.
test "make-channel's range rejections are argument errors naming the bound (#2002)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(define (code-of thunk) (guard (e (#t (error-object-code e))) (thunk) 'no-raise))
        \\(list (code-of (lambda () (make-channel 4294967296)))
        \\      (code-of (lambda () (make-channel -1)))
        \\      (code-of (lambda () (make-channel (expt 10 30))))  ; bignum
        \\      (code-of (lambda () (make-channel 1.0)))
        \\      (code-of (lambda () (make-channel 'x))))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(KP3007 KP3007 KP3007 KP3002 KP3002)", s);

    // The range rejection's message states the constraint it enforced.
    // (string-contains is SRFI 13: it returns a match INDEX or #f, so the
    // and-chain ends in an explicit #t rather than the last index.)
    const msg = try vm.eval(
        \\(guard (e (#t (and (string-contains (error-object-message e) "4294967295")
        \\                    (string-contains (error-object-message e) "4294967296")
        \\                    (string-contains (error-object-message e) "make-channel")
        \\                    #t)))
        \\  (make-channel 4294967296)
        \\  'missing-substrings)
    );
    try std.testing.expectEqual(types.TRUE, msg);
}

// #2002: a bad timeout argument to channel-send/channel-receive used to be
// blamed on a procedure named 'thread' -- the shared SRFI-18 helper's
// hardcoded name, which does not exist in (kaappi fibers). Each caller now
// passes its own name through timeoutToDeadlineNs.
test "a bad channel timeout names the channel primitive, not 'thread' (#2002)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e (#t (error-object-message e))) (channel-receive (make-channel) 'bad))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("\"type error in 'channel-receive': expected time object or number, got bad\"", s);

    const send_msg = try vm.eval(
        \\(guard (e (#t (if (and (string-contains (error-object-message e) "channel-send")
        \\                        (not (string-contains (error-object-message e) "thread")))
        \\                  'ok 'wrong-name)))
        \\  (channel-send (make-channel) 1 'bad)
        \\  'not-raised)
    );
    const s2 = try printer.valueToString(std.testing.allocator, send_msg, .write);
    defer std.testing.allocator.free(s2);
    try std.testing.expectEqualStrings("ok", s2);
}

// kaappi#2394 (KEP-0002 §2): channel identity across stubs. eqv?/equal?
// deliberately stay stub-identity (the KEP's as-implemented amendment), so
// channel=?/channel-hash/channel-comparator are the supported way to compare
// and dedup channel handles — the comparator contract the reply-channel and
// registry idioms need.
test "channel=? and channel-hash on local channels (#2394)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    const result = try vm.eval(
        \\(define a (make-channel))
        \\(define b (make-channel))
        \\(list (channel=? a a) (channel=? a b) (channel=? b a)
        \\      (= (channel-hash a) (channel-hash a))
        \\      (< (channel-hash a 100) 100)
        \\      (= (channel-hash a 100) (channel-hash a 100)))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(#t #f #f #t #t #t)", s);

    // Argument discipline matches the rest of the file: a non-channel is a
    // KP3002 type error, a non-positive bound a KP3007 range rejection.
    const codes = try vm.eval(
        \\(define (code-of thunk) (guard (e (#t (error-object-code e))) (thunk) 'no-raise))
        \\(list (code-of (lambda () (channel=? a 5)))
        \\      (code-of (lambda () (channel-hash "x")))
        \\      (code-of (lambda () (channel-hash a 0))))
    );
    const s2 = try printer.valueToString(std.testing.allocator, codes, .write);
    defer std.testing.allocator.free(s2);
    try std.testing.expectEqualStrings("(KP3002 KP3002 KP3007)", s2);
}

// The core #2394 scenario: one channel arrives twice through a thread and
// lands as two stubs. eq? cannot unify them (distinct heap objects); the
// comparator route must — against each other AND against the original
// handle, whose in-place promotion gives it the same `shared` pointer.
test "channel=? unifies stubs of one promoted channel across threads (#2394)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // needs real OS threads
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval(
        \\(import (kaappi fibers) (srfi 18) (srfi 69))
        \\(let ((ch   (make-channel))
        \\      (to-w (make-channel))
        \\      (to-p (make-channel)))
        \\  (define worker
        \\    (thread-start! (make-thread
        \\      (lambda ()
        \\        (let ((c (channel-receive to-w)))
        \\          (channel-send to-p c)
        \\          (channel-send to-p c))))))
        \\  (channel-send to-w ch)
        \\  (thread-join! worker)
        \\  (let ((a (channel-receive to-p))
        \\        (b (channel-receive to-p)))
        \\    (list (channel=? a b) (channel=? a ch) (channel=? b ch)
        \\          (eq? a b) (eqv? a b))))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    // eq?/eqv? on the two stubs: distinct heap objects, so #f — the KEP-0002
    // §2 divergence this issue records. The channel=? column is the promise,
    // kept where the KEP's amendment says it lives.
    try std.testing.expectEqualStrings("(#t #t #t #f #f)", s);
}

// The dedup the issue exists for: a reply-channel registry keyed by channel
// identity. Both table flavors (two procedures, comparator record) must
// collapse a/b/ch to one entry and find it under any of the three handles.
test "channel-keyed hash tables dedup stubs via channel=?/channel-hash (#2394)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // needs real OS threads
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval(
        \\(import (kaappi fibers) (srfi 18) (srfi 69))
        \\(let ((ch   (make-channel))
        \\      (to-w (make-channel))
        \\      (to-p (make-channel)))
        \\  (define worker
        \\    (thread-start! (make-thread
        \\      (lambda ()
        \\        (let ((c (channel-receive to-w)))
        \\          (channel-send to-p c)
        \\          (channel-send to-p c))))))
        \\  (channel-send to-w ch)
        \\  (thread-join! worker)
        \\  (let ((a (channel-receive to-p))
        \\        (b (channel-receive to-p)))
        \\    (define ht  (make-hash-table channel=? channel-hash))
        \\    (define ht2 (make-hash-table (channel-comparator)))
        \\    (hash-table-set! ht a 'first)
        \\    (hash-table-set! ht b 'second)
        \\    (hash-table-set! ht2 a 1)
        \\    (hash-table-set! ht2 b 2)
        \\    (hash-table-set! ht2 ch 3)
        \\    (list (hash-table-size ht)  (hash-table-ref/default ht  ch 'MISS)
        \\          (hash-table-size ht2) (hash-table-ref/default ht2 b 'MISS))))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(1 second 1 3)", s);
}

// (channel-comparator) is a real SRFI-128 comparator — comparator? and the
// field accessors agree with every hand-built (make-comparator ...) result —
// and it builds even when (srfi 128) was never imported (lazy load).
test "channel-comparator is a SRFI-128 comparator built on demand (#2394)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // No (import (srfi 128)) here: the construction lazy-loads it, and the
    // result is already usable through the native comparator bridge —
    // make-hash-table unwraps a <comparator> record's equality/hash fields.
    const result = try vm.eval(
        \\(define cmp (channel-comparator))
        \\(define ht (make-hash-table cmp))
        \\(define ch (make-channel))
        \\(hash-table-set! ht ch 'v)
        \\(list (hash-table-size ht)
        \\      (hash-table-ref/default ht ch 'MISS))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(1 v)", s);

    // With (srfi 128) imported, comparator? and the hash contract agree.
    const result2 = try vm.eval(
        \\(import (srfi 128))
        \\(list (comparator? cmp)
        \\      (comparator-ordered? cmp)
        \\      (comparator-hashable? cmp)
        \\      (= (comparator-hash cmp ch) (channel-hash ch)))
    );
    const s2 = try printer.valueToString(std.testing.allocator, result2, .write);
    defer std.testing.allocator.free(s2);
    try std.testing.expectEqualStrings("(#t #f #t #t)", s2);
}

// CodeRabbit's #2394 review scenario: a channel keyed into a table BEFORE
// its first cross-thread send must stay reachable after promotion rewrites
// the original in place — the hash input is the channel's identity for its
// whole life (SharedChannel.identity_seed preserves the pre-promotion
// Value), not the representation-of-the-moment.
test "channel-hash is stable across promotion: insert, promote, lookup (#2394)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // needs real OS threads
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval(
        \\(import (kaappi fibers) (srfi 18) (srfi 69))
        \\(let ((ch   (make-channel))
        \\      (to-w (make-channel))
        \\      (to-p (make-channel)))
        \\  (define ht (make-hash-table channel=? channel-hash))
        \\  (hash-table-set! ht ch 'early)
        \\  (define worker
        \\    (thread-start! (make-thread
        \\      (lambda ()
        \\        (let ((c (channel-receive to-w)))
        \\          (channel-send to-p c)
        \\          (channel-send to-p c))))))
        \\  (channel-send to-w ch)
        \\  (thread-join! worker)
        \\  (let ((a (channel-receive to-p))
        \\        (b (channel-receive to-p)))
        \\    (list (hash-table-size ht)
        \\          (hash-table-ref/default ht a 'MISS)
        \\          (hash-table-ref/default ht b 'MISS)
        \\          (hash-table-ref/default ht ch 'MISS))))
    );
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(1 early early early)", s);
}

// The comparator is a per-VM constant cached on the VM like
// default_random_source — repeat calls must return the same record.
test "channel-comparator is cached: repeat calls return the same record (#2394)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval("(eq? (channel-comparator) (channel-comparator))");
    try std.testing.expectEqual(types.TRUE, result);
}

// ---------------------------------------------------------------------------
// An error exit from a drive must put the waiting fiber's window back (#2429)
// ---------------------------------------------------------------------------
//
// runSchedulerStep restored `me` in its epilogue only, and five `try`s inside
// the dispatch loop return without ever reaching it — parkOnReactor,
// restoreFiber(next_idx), and the three saveCurrentFiber calls (Yielded,
// errored-dispatch, completed-dispatch). All five surface OutOfMemory, which
// is catchable, so a Scheme `guard` could resume the waiting fiber's bytecode
// against a *sibling's* registers, frames, handler and wind stacks: the #1487
// dispatch-from-stale-snapshot corruption reached by a different route.
//
// The probe uses Terminated rather than an injected OOM because it is
// deterministic and reaches the identical exit — the fix is the one errdefer
// that covers every error return, not a per-error patch. (An OOM here would
// come from ensureXxxCapacity/growFiberXxx, which allocate from the raw
// allocator and so are not reachable by gc.oom_countdown.)

const TerminateAfterDispatches = struct {
    me: *fiber_mod.Fiber,
    calls: *usize,
    /// Never resolves. Once the drive has been round the loop three times —
    /// long enough to have dispatched a sibling and left it suspended
    /// mid-body, with its window loaded into the VM — ask for termination, so
    /// the next `waitTerminated` check at the top of the loop takes an error
    /// exit from exactly that state.
    pub fn isDone(self: TerminateAfterDispatches) bool {
        self.calls.* += 1;
        if (self.calls.* > 3) @atomicStore(bool, &self.me.terminated, true, .monotonic);
        return false;
    }
};

test "a drive that errors out mid-dispatch restores the waiting fiber's window (#2429)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // needs the reactor-backed scheduler
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // TWO siblings, and each yields rather than completing. Yielding is what
    // leaves one suspended with a real frame stack when the drive errors out
    // (a fiber that ran to completion leaves a zero-length window behind, and
    // the frame_count assertion below would be vacuous) — but `thread-yield!`
    // is advisory and no-ops unless some OTHER fiber is runnable. `me` is
    // excluded from that for the whole drive (it is `driving`), so with a
    // single sibling the yield never fires and the sibling spins inside
    // `runUntil` forever.
    _ = try vm.eval(
        \\(define (spin) (let loop ((i 0)) (thread-yield!) (loop (+ i 1))))
        \\(define sib-a (spawn spin))
        \\(define sib-b (spawn spin))
    );
    const sib_a = types.toObject(try vm.eval("sib-a")).as(fiber_mod.Fiber);
    const sib_b = types.toObject(try vm.eval("sib-b")).as(fiber_mod.Fiber);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const my_idx = ctx.sched.current_idx;
    const me = ctx.sched.fibers.items[my_idx].?;
    me.status = .waiting;
    me.timed_out = false;

    var calls: usize = 0;
    try std.testing.expectError(
        vm_mod.VMError.Terminated,
        fiber_mod.runSchedulerStep(TerminateAfterDispatches, .{ .me = me, .calls = &calls }, vm, ctx.sched, me),
    );

    // Non-vacuity: a sibling really was dispatched and really was left holding
    // a window, so pre-fix there was something to be stranded on.
    const ran = if (sib_a.status == .suspended and sib_a.frame_count > 0) sib_a else sib_b;
    if (ran.status != .suspended or ran.frame_count == 0) {
        std.debug.print(
            "no sibling was left suspended mid-body: a={s}/{d} b={s}/{d} (loop ran {d}x)\n",
            .{ @tagName(sib_a.status), sib_a.frame_count, @tagName(sib_b.status), sib_b.frame_count, calls },
        );
        return error.SiblingNeverDispatched;
    }

    // The fix. Pre-fix all three name the sibling instead.
    if (ctx.sched.current_idx != my_idx or vm.current_fiber.? != me or
        vm.frame_count != me.frame_count)
    {
        std.debug.print(
            "drive errored out on a sibling's window — current_idx={d} (want {d}) " ++
                "current_fiber_is_me={} vm.frame_count={d} (want {d}, sibling has {d})\n",
            .{
                ctx.sched.current_idx, my_idx,         vm.current_fiber.? == me,
                vm.frame_count,        me.frame_count, ran.frame_count,
            },
        );
        return error.WaitingFiberWindowNotRestored;
    }
}
