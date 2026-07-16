// KEP-0001 Phase 2: scheduler <-> reactor integration. Complements
// tests_reactor.zig (Phase 1, reactor in isolation) and tests_fibers.zig
// (existing fiber/channel behavior). These tests exercise the new pieces
// specifically: io_waiting exclusion/inclusion in scheduling decisions,
// parkOnReactor's ready-list handling against a real fd, and the
// live-window bound on per-fiber save/restore storage.
const std = @import("std");
const platform = @import("platform.zig");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
const reactor_mod = @import("reactor.zig");

// Cross-platform pair (pipe on POSIX, loopback socket pair on Windows —
// where fd readiness is socket-only, #1608).
const makePipe = th.makeFdPair;
const closeFd = th.closeFd;

fn writeByte(fd: platform.fd_t, byte: u8) void {
    const buf = [1]u8{byte};
    const n = th.fdWrite(fd, &buf);
    std.testing.expectEqual(@as(isize, 1), n) catch unreachable;
}

test "schedule() does not select an io_waiting fiber" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.created, f.status);

    f.status = .io_waiting;
    try std.testing.expectEqual(@as(?usize, null), sched.schedule());

    f.status = .suspended;
    try std.testing.expect(sched.schedule() != null);
}

test "hasRunnableFibers reports io_waiting as alive but not a merely-running ancestor" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    // Main (id 0) is .running here (execute()'s prologue sets it on every
    // top-level form); with f neutralized, nothing should look runnable —
    // parkOnReactor's whole point is that a .running ancestor deep in its
    // own recursive dispatch must not count as "other progress possible".
    f.status = .completed;
    try std.testing.expect(!sched.hasRunnableFibers());

    f.status = .io_waiting;
    try std.testing.expect(sched.hasRunnableFibers());
}

test "parkOnReactor wakes a manually io_waiting fiber when its fd becomes readable" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const reactor = vm.reactor.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    f.status = .io_waiting;
    f.io_fd = pipe[0];
    f.io_interest = .read;
    try reactor.register(pipe[0], .read, f);

    writeByte(pipe[1], 'x');

    const made_progress = try fiber_mod.parkOnReactor(vm, sched, null);
    try std.testing.expect(made_progress);
    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, f.status);
}

test "parkOnReactor reports no progress (genuine deadlock) when nothing is pending" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);
    f.status = .completed; // neutralize: nothing left that could ever wake

    const made_progress = try fiber_mod.parkOnReactor(vm, sched, null);
    try std.testing.expect(!made_progress);
}

test "fiber switch does not grow the fiber's own register storage to match a large VM register file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 42)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);
    try std.testing.expect(f.registers.len < 1024);

    // Simulate the VM having grown large from unrelated deep recursion
    // elsewhere in the program, then switch to and back from the small
    // fiber (main -> f saves main; f -> main saves f — the second switch
    // is the one that would balloon f's storage if save/restore weren't
    // live-window bounded, KEP-0001 Phase 2 resolved question 5).
    try vm.ensureRegisterCapacity(8192);
    try sched.switchTo(1);
    try sched.switchTo(0);

    try std.testing.expect(f.registers.len < 1024);

    // The fiber's saved state must still be semantically correct after
    // the dance above — bounded copying must not lose live data.
    const result = try vm.eval("(fiber-join f)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

// KEP-0002 Phase 3 (#1468): the per-scheduler shared-waiter registry that
// backs sweepSharedWaiters' unconditional flip.

test "enrollSharedWaiter dedups by pointer; removeSharedWaiter is a no-op if absent" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const f_val = try ctx.vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    try sched.enrollSharedWaiter(f);
    try sched.enrollSharedWaiter(f); // dedup: still just one entry
    try std.testing.expectEqual(@as(usize, 1), sched.shared_waiters.items.len);

    sched.removeSharedWaiter(f);
    try std.testing.expectEqual(@as(usize, 0), sched.shared_waiters.items.len);
    sched.removeSharedWaiter(f); // no-op if already absent
    try std.testing.expectEqual(@as(usize, 0), sched.shared_waiters.items.len);
}

test "sweepSharedWaiters unconditionally flips every enrolled .waiting fiber and clears the registry" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const f_val = try ctx.vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    f.status = .waiting;
    f.waiting_on = f_val; // arbitrary non-void Value, mirrors a real park
    try sched.enrollSharedWaiter(f);

    sched.sweepSharedWaiters();

    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, f.status);
    try std.testing.expectEqual(types.VOID, f.waiting_on);
    try std.testing.expectEqual(@as(usize, 0), sched.shared_waiters.items.len);
}

test "sweepSharedWaiters does not clobber a fiber no longer .waiting" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const f_val = try ctx.vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    f.status = .waiting;
    try sched.enrollSharedWaiter(f);
    // Simulates a path other than the sweep (e.g. thread-terminate!) moving
    // the fiber out of .waiting without going through removeSharedWaiter
    // first -- the registry entry is stale but must not corrupt the status.
    f.status = .errored;

    sched.sweepSharedWaiters();

    try std.testing.expectEqual(fiber_mod.FiberStatus.errored, f.status);
    try std.testing.expectEqual(@as(usize, 0), sched.shared_waiters.items.len);
}

// #1487: the generic `driving` guard, closing the dirty-snapshot dispatch
// hazard for every runSchedulerStep caller at once (mutex-lock!,
// condition-variable-wait, and any future nested-drive call site) rather
// than per call site.

test "scheduleForDispatch() does not select a .suspended fiber whose own nested drive is still live, but plain schedule() still does" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const f_val = try ctx.vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    // Mirrors what a nested wake looks like mid-flight: something woke f
    // (status flipped to .suspended, e.g. by wakeMutexWaiters) while f's
    // own runSchedulerStep call is still live deeper on the Zig stack.
    f.status = .suspended;
    f.driving = true;
    try std.testing.expectEqual(@as(?usize, null), sched.scheduleForDispatch());

    // Plain schedule() must NOT exclude it -- yieldFn/threadYieldFn's own
    // "is yielding worthwhile" advisory check relies on schedule() still
    // finding f here (f's wait having just resolved is exactly the case
    // where yielding IS worthwhile); excluding it there reproduces #1440's
    // busy-sibling starvation by a different path (confirmed via
    // tests/scheme/smoke/fiber-timed-mutex-lock-not-starved-by-busy-sibling.scm
    // regressing when schedule() itself carried this exclusion).
    try std.testing.expect(sched.schedule() != null);

    // Once f's own call concludes (driving cleared), it's a real dispatch
    // target again too.
    f.driving = false;
    try std.testing.expect(sched.scheduleForDispatch() != null);
}

test "hasRunnableFibers does not count a .suspended fiber whose own nested drive is still live" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const f_val = try ctx.vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    // Must mirror scheduleForDispatch()'s own exclusion -- otherwise
    // parkOnReactor would see "something's runnable" and proceed to a
    // real, possibly uncapped reactor.poll() with nothing left to ever
    // wake it (a hang), instead of promptly reporting "no progress
    // possible right now".
    f.status = .suspended;
    f.driving = true;
    try std.testing.expect(!sched.hasRunnableFibers());

    f.driving = false;
    try std.testing.expect(sched.hasRunnableFibers());
}

test "runSchedulerStep sets driving for its whole extent and clears it on return" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const main_fiber = sched.fibers.items[0].?;
    const f = types.toObject(try ctx.vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expect(!main_fiber.driving);

    // f completes in one dispatch; the interesting assertion is that
    // driving is cleared again once runSchedulerStep returns normally.
    _ = try fiber_mod.runSchedulerStep(fiber_mod.TargetWait, .{ .target = f }, ctx.vm, sched, main_fiber);
    try std.testing.expect(!main_fiber.driving);
    try std.testing.expectEqual(fiber_mod.FiberStatus.completed, f.status);

    // The no-progress-possible (genuine deadlock) exit must clear it too.
    _ = try ctx.vm.eval("(define g (spawn (lambda () 1)))");
    const g = types.toObject(try ctx.vm.eval("g")).as(fiber_mod.Fiber);
    g.status = .errored; // neutralize: nothing left for schedule() to find
    const target_fiber = try ctx.gc.allocFiber(types.VOID, 999); // never completes/errors
    const done = try fiber_mod.runSchedulerStep(fiber_mod.TargetWait, .{ .target = target_fiber }, ctx.vm, sched, main_fiber);
    try std.testing.expect(!main_fiber.driving);
    try std.testing.expect(!done);
}

test "review regression: mutex-lock! contended through a 3-level nested dispatch does not corrupt an unrelated fiber's result" {
    // Confirmed VM corruption without the driving guard (git-stash A/B, see
    // tests/scheme/smoke/mutex-nested-dispatch-dirty-snapshot-1487.scm):
    // fiber b sets .waiting on m1 and starts its own nested drive
    // (mutexLockFn's while(true) + runSchedulerStep loop), which dispatches
    // c. c sets .waiting on m2 and starts its own nested drive one level
    // deeper, which repeatedly redispatches d as d alternates unlocking and
    // yielding. When d unlocks m1 (waking b) without yet unlocking m2, it's
    // c's own loop -- not b's -- that next calls scheduleForDispatch().
    // Before the fix that loop could select b right there, resuming b's
    // stale, mid-call snapshot from a *different* fiber's nested drive with
    // the (mutex-lock! m1) destination register never written. Same
    // corruption class as PR #1485's channelReceiveShared fix, reachable
    // here because mutex-lock!/mutex-unlock!+condvar still nest a nested
    // drive after setting .waiting regardless of dispatched status (#1487).
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval(
        \\(import (srfi 18) (kaappi fibers))
        \\(define m1 (make-mutex 'm1))
        \\(define m2 (make-mutex 'm2))
        \\(define d (spawn (lambda ()
        \\  (mutex-lock! m1)
        \\  (mutex-lock! m2)
        \\  (thread-yield!)
        \\  (mutex-unlock! m1)
        \\  (thread-yield!)
        \\  (mutex-unlock! m2)
        \\  'd-done)))
        \\(define b (spawn (lambda () (mutex-lock! m1))))
        \\(define c (spawn (lambda () (mutex-lock! m2))))
        \\(fiber-join d)
        \\(list (fiber-join b) (fiber-join c))
    );
    try std.testing.expectEqual(types.TRUE, types.car(result));
    try std.testing.expectEqual(types.TRUE, types.car(types.cdr(result)));
}

// #1477: O(1) dispatch/spawn. The ready ring and free-slot list are
// accelerators over an authoritative O(n) fallback scan, so these check the
// incremental bookkeeping (slot reuse, sched_idx, the non-consuming advisory)
// rather than the scan the older tests above already cover.

test "#1477: addFiber reuses a vacated slot instead of growing the fibers array" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;

    // First spawn+join leaves one completed slot behind (main is slot 0).
    _ = try ctx.vm.eval("(fiber-join (spawn (lambda () 1)))");
    const len_after_first = sched.fibers.items.len;

    // Each later spawn must retireSlot->free-list->reuse that same slot, so
    // long-running spawn/join churn doesn't grow the array unboundedly.
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        _ = try ctx.vm.eval("(fiber-join (spawn (lambda () 1)))");
    }
    try std.testing.expectEqual(len_after_first, sched.fibers.items.len);
}

test "#1477: addFiber assigns each fiber its stable slot index" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const f = types.toObject(try ctx.vm.eval("f")).as(fiber_mod.Fiber);

    // f lives at exactly the slot addFiber recorded on it, and that slot is
    // what the O(1) wake paths enqueue.
    try std.testing.expect(f.sched_idx != 0); // slot 0 is main
    try std.testing.expectEqual(f, sched.fibers.items[f.sched_idx].?);
}

test "#1477: anyRunnable tracks runnability and does not consume (peek)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    // Only the running main fiber exists -> nothing else is runnable.
    try std.testing.expect(!sched.anyRunnable());

    // A freshly spawned fiber is .created and enqueued -> runnable.
    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () (yield) 1)))");
    const f = types.toObject(try ctx.vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.created, f.status);
    try std.testing.expect(sched.anyRunnable());
    // Peek, not consume: asking twice still reports runnable and leaves the
    // ring entry in place for the real dispatcher.
    try std.testing.expect(sched.anyRunnable());

    // Once f parks, the advisory must report nothing runnable again -- the
    // stale ring entry is validated away at peek, not trusted blindly.
    f.status = .waiting;
    try std.testing.expect(!sched.anyRunnable());
}

test "hasRunnableFibers reports a shared-waiter-registry entry as alive" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const fctx = try fiber_mod.ensureScheduler(ctx.vm);
    const sched = fctx.sched;
    // Only the main fiber exists, and it's .running (deliberately not
    // counted -- see hasRunnableFibers' doc comment).
    try std.testing.expect(!sched.hasRunnableFibers());

    _ = try ctx.vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const f_val = try ctx.vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);
    // .waiting with no deadline trips none of the pre-existing categories
    // (created/suspended/waiting-with-deadline/io_waiting) -- isolates the
    // new shared_waiters check from every other reason this could pass.
    f.status = .waiting;
    try sched.enrollSharedWaiter(f);

    try std.testing.expect(sched.hasRunnableFibers());
}

// Regression (#1529, sibling of the call/cc #1464 fix): a fiber that suspends
// while inside a re-entrant native frame (here a `guard` thunk) must not save
// stale pointers from dead "gap" registers into its snapshot. The `guard`
// bumps the frame base well past the thunk's own window, so registers between
// the windows form a gap; `make-junk` before the guard leaves dead heap values
// lingering there. While the fiber runs it is GC-marked per-frame (markVMRoots
// skips gaps), so an allocation inside the guard frees that gap junk; the
// fiber then blocks on channel-receive and saveCurrentFiber copies the now
// contiguous [0,span) span -- gaps included -- into fiber.registers. A later
// collection while the fiber is suspended marks that snapshot contiguously
// (markFiberState), dereferencing the freed pointers. Under -Dgc-stress=true
// with the testing allocator (which unmaps freed pages) that read segfaults
// without saveCurrentFiber's clearGapRegisters scrub. The result 16 (= 7 + 9)
// also confirms the live values w and v survive the scrub intact.
test "fiber suspend does not save stale gap registers (#1529)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const result = try ctx.vm.eval(
        \\(import (kaappi fibers))
        \\(define ch (make-channel))
        \\(define out #f)
        \\(define (make-junk n)
        \\  (let loop ((i 0) (acc '()))
        \\    (if (< i n) (loop (+ i 1) (cons (make-vector 4000 i) acc)) acc)))
        \\(spawn
        \\  (lambda ()
        \\    (make-junk 6)
        \\    (guard (e (#t 'caught))
        \\      (let ((w (list 7 7 7)) (v (list 9 9 9)))
        \\        (make-junk 3)
        \\        (channel-receive ch)
        \\        (set! out (+ (car w) (car v)))))))
        \\(spawn
        \\  (lambda ()
        \\    (let loop ((i 0)) (when (< i 200) (list i i i) (loop (+ i 1))))
        \\    (channel-send ch 'go)
        \\    (let loop ((i 0)) (when (< i 200) (list i i i) (loop (+ i 1))))))
        \\(yield)(yield)(yield)(yield)
        \\out
    );
    try std.testing.expectEqual(@as(i64, 16), types.toFixnum(result));
}

// #1530: the by-object waiter index (waiter_index / enrollWaiter). These
// drive the index directly — parking a spawned fiber is simulated by setting
// its status/waiting_on and calling enrollWaiter, exactly as the real park
// sites do — so the wake mechanics are checked in isolation from the full
// scheduler loop the Scheme-level tests already cover.

fn parkOn(sched: *fiber_mod.FiberScheduler, f: *fiber_mod.Fiber, key: types.Value) void {
    f.status = .waiting;
    f.waiting_on = key;
    sched.enrollWaiter(f);
}

test "#1530: a broadcast wakes every enrolled waiter on the object and frees the key" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    // A rooted channel Value is the wake key (any non-VOID Value keys the index).
    const key = try ctx.vm.eval("(define k (make-channel)) k");
    _ = try ctx.vm.eval("(define a (spawn (lambda () 1)))");
    _ = try ctx.vm.eval("(define b (spawn (lambda () 2)))");
    _ = try ctx.vm.eval("(define c (spawn (lambda () 3)))");
    const fa = types.toObject(try ctx.vm.eval("a")).as(fiber_mod.Fiber);
    const fb = types.toObject(try ctx.vm.eval("b")).as(fiber_mod.Fiber);
    const fc = types.toObject(try ctx.vm.eval("c")).as(fiber_mod.Fiber);

    for ([_]*fiber_mod.Fiber{ fa, fb, fc }) |f| parkOn(sched, f, key);
    try std.testing.expect(sched.waiter_index.count() == 1); // one object contended
    try std.testing.expectEqual(@as(usize, 3), sched.waiter_index.get(key).?.items.len);

    sched.wakeChannelWaiters(key); // broadcast

    for ([_]*fiber_mod.Fiber{ fa, fb, fc }) |f| {
        try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, f.status);
        try std.testing.expectEqual(types.VOID, f.waiting_on); // channel path clears it
    }
    // The emptied list is dropped so the map stays bounded by live contention.
    try std.testing.expect(sched.waiter_index.count() == 0);
}

test "#1530: a hand-off wakes exactly one waiter and leaves the rest enrolled" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (srfi 18) (kaappi fibers))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const key = try ctx.vm.eval("(define m (make-mutex)) m");
    _ = try ctx.vm.eval("(define a (spawn (lambda () 1)))");
    _ = try ctx.vm.eval("(define b (spawn (lambda () 2)))");
    _ = try ctx.vm.eval("(define c (spawn (lambda () 3)))");
    const fa = types.toObject(try ctx.vm.eval("a")).as(fiber_mod.Fiber);
    const fb = types.toObject(try ctx.vm.eval("b")).as(fiber_mod.Fiber);
    const fc = types.toObject(try ctx.vm.eval("c")).as(fiber_mod.Fiber);

    for ([_]*fiber_mod.Fiber{ fa, fb, fc }) |f| parkOn(sched, f, key);

    sched.wakeMutexWaiters(key); // hand-off: first enrolled (a) only

    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, fa.status);
    try std.testing.expectEqual(fiber_mod.FiberStatus.waiting, fb.status);
    try std.testing.expectEqual(fiber_mod.FiberStatus.waiting, fc.status);
    // a's entry is consumed; b and c stay enrolled for the next unlock.
    try std.testing.expectEqual(@as(usize, 2), sched.waiter_index.get(key).?.items.len);
}

test "#1530: a terminated (.errored) waiter still in the index is skipped, not resurrected" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const key = try ctx.vm.eval("(define k (make-channel)) k");
    _ = try ctx.vm.eval("(define a (spawn (lambda () 1)))");
    _ = try ctx.vm.eval("(define b (spawn (lambda () 2)))");
    const fa = types.toObject(try ctx.vm.eval("a")).as(fiber_mod.Fiber);
    const fb = types.toObject(try ctx.vm.eval("b")).as(fiber_mod.Fiber);

    parkOn(sched, fa, key);
    parkOn(sched, fb, key);
    // thread-terminate! flips a directly to .errored without de-indexing it
    // (the index holds slot indices, not pointers, so validation catches it).
    fa.status = .errored;

    sched.wakeChannelWaiters(key);

    try std.testing.expectEqual(fiber_mod.FiberStatus.errored, fa.status); // not woken
    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, fb.status); // woken
    try std.testing.expect(sched.waiter_index.count() == 0);
}

test "#1530: tail dedup bounds a same-object re-park; a wake+re-park re-indexes" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (srfi 18) (kaappi fibers))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const key = try ctx.vm.eval("(define m (make-mutex)) m");
    _ = try ctx.vm.eval("(define a (spawn (lambda () 1)))");
    const fa = types.toObject(try ctx.vm.eval("a")).as(fiber_mod.Fiber);

    parkOn(sched, fa, key);
    // Re-parking on the SAME object with no intervening wake must not grow the
    // list (the mutex/condvar spin loops re-enter .waiting repeatedly).
    sched.enrollWaiter(fa);
    sched.enrollWaiter(fa);
    try std.testing.expectEqual(@as(usize, 1), sched.waiter_index.get(key).?.items.len);

    // A hand-off consumes a's entry and drops the now-empty key.
    sched.wakeMutexWaiters(key);
    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, fa.status);
    try std.testing.expect(sched.waiter_index.get(key) == null);

    // The retry loop re-parks: enrollWaiter must re-add it (waiting_on is still
    // the mutex on the mutex path), and the next unlock must find it again.
    fa.status = .waiting;
    sched.enrollWaiter(fa);
    try std.testing.expectEqual(@as(usize, 1), sched.waiter_index.get(key).?.items.len);
    sched.wakeMutexWaiters(key);
    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, fa.status);
}

test "#1530: wakeWaiters hands the completed fiber's result to an indexed joiner" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    _ = try ctx.vm.eval("(define t (spawn (lambda () 1)))");
    _ = try ctx.vm.eval("(define j (spawn (lambda () 2)))");
    const t_val = try ctx.vm.eval("t");
    const ft = types.toObject(t_val).as(fiber_mod.Fiber);
    const fj = types.toObject(try ctx.vm.eval("j")).as(fiber_mod.Fiber);

    // j joins t (keyed on t's own Value, exactly what blockOrDeadlock sets).
    parkOn(sched, fj, t_val);

    ft.status = .completed;
    ft.result = types.makeFixnum(99);
    sched.wakeWaiters(ft);

    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, fj.status);
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(fj.result));
    try std.testing.expect(sched.waiter_index.count() == 0);
}

test "#1530: a degraded index falls back to the full scan and still wakes" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (kaappi fibers))");
    const sched = (try fiber_mod.ensureScheduler(ctx.vm)).sched;
    const key = try ctx.vm.eval("(define k (make-channel)) k");
    _ = try ctx.vm.eval("(define a (spawn (lambda () 1)))");
    _ = try ctx.vm.eval("(define b (spawn (lambda () 2)))");
    const fa = types.toObject(try ctx.vm.eval("a")).as(fiber_mod.Fiber);
    const fb = types.toObject(try ctx.vm.eval("b")).as(fiber_mod.Fiber);

    // Simulate a prior enroll OOM: the index is abandoned and enroll no-ops.
    sched.waiter_index_degraded = true;
    fa.status = .waiting;
    fa.waiting_on = key;
    fb.status = .waiting;
    fb.waiting_on = key;
    sched.enrollWaiter(fa); // no-op while degraded
    try std.testing.expect(sched.waiter_index.count() == 0);

    // The wake must still find both by scanning fibers.items (pre-#1530 path).
    sched.wakeChannelWaiters(key);
    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, fa.status);
    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, fb.status);
}
