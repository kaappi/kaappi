//! Blocking-wait machinery for fibers (KEP-0001): fd waits (waitForFd and
//! the close-port wake, wakeIoWaitersOnFd), reactor parking (parkOnReactor),
//! and the single shared in-place scheduler drive (runSchedulerStep) behind
//! channel-receive, fiber-join, thread-join!, mutex-lock!, condition-variable
//! waits and thread-sleep!. Split from fiber.zig, which re-exports every pub
//! name here so external fiber.X references are unchanged; the Fiber and
//! FiberScheduler structs themselves stay there.

const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const reactor_mod = @import("reactor.zig");
const fiber_mod = @import("fiber.zig");
const Value = types.Value;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Fiber = fiber_mod.Fiber;
const FiberScheduler = fiber_mod.FiberScheduler;
const ensureScheduler = fiber_mod.ensureScheduler;
const abandonFiberMutexes = fiber_mod.abandonFiberMutexes;
const wakeReadyFiber = fiber_mod.wakeReadyFiber;

/// Wakes every fiber parked on fd readiness for `fd` — close-port's half of
/// the close discipline (KEP-0001 Phase 3, resolved question 4). The woken
/// fibers retry their I/O primitive, observe `is_open == false`, and raise a
/// clean "port closed" error instead of sleeping on an fd that will never
/// fire (the caller unregisters it from the reactor right after this).
/// Mirrors wakeChannelWaiters' iterate-and-flip discipline.
pub fn wakeIoWaitersOnFd(sched: *FiberScheduler, fd: platform.fd_t) void {
    for (sched.fibers.items) |f| {
        if (f) |fiber| {
            if (fiber.status == .io_waiting and fiber.io_fd == fd) {
                fiber.status = .suspended;
                fiber.io_fd = null;
                sched.markRunnable(fiber);
            }
        }
    }
}

/// Wait until the current fiber's own fd readiness resolves: done as soon
/// as something (reactor poll, close-port wake) flips it out of io_waiting.
pub const IoWait = struct {
    me: *Fiber,
    pub fn isDone(self: IoWait) bool {
        return self.me.status != .io_waiting;
    }
    /// #1625: an fd wait is the one drive whose *own* registration defeats
    /// the generic idle escape — hasRunnableFibers counts this fiber's
    /// `.io_waiting` and the fd keeps the reactor non-empty, so
    /// parkOnReactor never returns false and the poll is unbounded. When an
    /// ancestor drive has already resolved, blocking anyway wedges it
    /// forever on an event that may never come; unwinding (waitForFd turns
    /// the broken-off drive into a catchable error) is the only exit that
    /// lets the thread proceed. Waits that resolve through in-thread wakes
    /// (join/channel/mutex/condvar) don't need this: with no fd of their
    /// own, the same idle state already falls out via parkOnReactor's
    /// deadlock check, and timed sleeps must run their full duration.
    pub const unwind_on_resolved_ancestor = true;
};

/// Blocks the current fiber until `fd` is ready for `interest` (KEP-0001
/// Phase 3). Two modes, chosen by whether the fiber can be safely parked:
///
/// - **Park** (a spawned fiber dispatched directly by a scheduler loop):
///   registers with the reactor, flips to `.io_waiting`, arms the
///   yield-retry ip rewind, and returns `error.Yielded` — the same
///   park-and-retry protocol as blockOrDeadlock. The whole primitive
///   re-executes when the fd fires, so callers with partial progress must
///   stash it (e.g. into `port.read_buf`) before propagating the error.
///
/// - **Drive** (the main fiber, or any fiber under re-entrant native frames
///   that cannot be rewound): registers likewise, then drives the scheduler
///   in place — exactly the thread-sleep! pattern — until the reactor
///   reports the fd ready or a close-port wake intervenes, then returns so
///   the caller retries its syscall. Blocking main on I/O this way keeps
///   sibling fibers running while preserving blocking-read semantics. One
///   exception (#1625): if the drive goes idle while an *enclosing* drive's
///   wait has already resolved (IoWait.unwind_on_resolved_ancestor), it
///   raises a catchable "port I/O abandoned" error instead of blocking,
///   because only this fiber's unwinding can let that enclosing wait
///   proceed.
pub fn waitForFd(vm: *VM, fd: platform.fd_t, interest: reactor_mod.Interest) VMError!void {
    const ctx = try ensureScheduler(vm);
    const me = vm.current_fiber orelse return VMError.InvalidArgument;
    const my_idx = ctx.sched.current_idx;

    me.io_fd = fd;
    me.io_interest = interest;
    // Status must flip before register(): the reactor's debug assertion
    // checks that every registered waiter is .io_waiting.
    const prev_status = me.status;
    me.status = .io_waiting;
    ctx.reactor.register(fd, interest, me) catch |err| {
        me.status = prev_status;
        me.io_fd = null;
        if (err == error.OutOfMemory) return VMError.OutOfMemory;
        // A kernel-level arm failure (EBADF on a raced-away fd, resource
        // limits) is not an OOM; surface it diagnosably.
        vm.setErrorDetail("cannot wait on fd {d}: reactor registration failed", .{fd});
        return VMError.InvalidArgument;
    };

    if (my_idx != 0 and vm.dispatched_from_scheduler) {
        vm.yield_retry = true;
        return VMError.Yielded;
    }

    // An fd wait has no deadline; a stale timed_out left by an earlier
    // timed wait would make runSchedulerStep return before the fd is
    // ready, degrading this wait into an EAGAIN retry spin.
    me.timed_out = false;

    // The normal wake paths (reactor poll, close-port) both remove `me`
    // from the waiter lists before flipping its status; this cleanup only
    // has work to do when an error below unwinds the wait mid-flight —
    // without it, the fiber would linger in the lists in a non-io_waiting
    // status and trip register()'s staleness assertion later.
    defer {
        ctx.reactor.removeWaiter(fd, me);
        me.io_fd = null;
        me.status = .running;
    }
    // SRFI 181: a custom port callback (always running with
    // dispatched_from_scheduler forced false, so the park branch above
    // never triggers for it) that blocks on another port's fd would
    // otherwise fall into the unbounded recursive scheduler drive below —
    // a confirmed native-stack-overflow risk under concurrent fibers, not
    // a catchable error. Reject it here instead, after the defer above is
    // already armed so this early return still unregisters the fd wait.
    if (vm.in_custom_port_callback > 0) {
        return raiseCustomPortCallbackBlocked(vm);
    }
    const done = try runSchedulerStep(IoWait, .{ .me = me }, vm, ctx.sched, me);
    // The drive broke off unresolved: IoWait's unwind_on_resolved_ancestor
    // fired (#1625) — an enclosing dispatch's wait has completed and only
    // this fiber's unwinding lets it proceed. Returning normally would
    // retry the syscall, EAGAIN again, and re-enter the same drive: an
    // unbreakable spin. Raise a catchable error instead; the defer above
    // has already pulled `me` off the reactor, and the re-entrant frames
    // that made parking impossible (guard's exception plumbing, a native
    // higher-order driver's callback) all sit under a Zig caller that
    // propagates an error — an ordinary raise is exactly the unwind they
    // already handle.
    if (!done) return raiseIoWaitAbandoned(vm);
}

/// The catchable error a broken-off in-place I/O drive surfaces as (#1625).
/// A plain ErrorObject like blockOrDeadlock's deadlock errors — this is the
/// I/O drive's analogue of those: "this wait can no longer be serviced
/// without wedging the scheduler."
///
/// The frames named here must be *native* ones (#1959). `dynamic-wind`,
/// `map`/`for-each`, the vector/string mapping procedures and `force` are
/// bootstrapped Scheme (vm_bootstrap.zig): their bodies and callbacks run
/// in the bytecode dispatch loop, so a fiber parks inside them normally.
/// Naming `dynamic-wind` here sent readers of this error hunting in
/// exactly the wrong place. (Its before/after thunks *are* native frames
/// when a continuation transition or an unwind runs them via callThunk —
/// but that is the wind machinery re-entering them, not the ordinary
/// `(dynamic-wind before thunk after)` call this message was read as
/// indicting.) The drive/park split is pinned by the "#1959:" and
/// "#1625:" tests in tests_port_io.zig.
fn raiseIoWaitAbandoned(vm: *VM) VMError {
    var msg = vm.gc.allocString(
        "port I/O abandoned: fiber cannot suspend under re-entrant native frames " ++
            "(guard, and native higher-order drivers such as SRFI-1 fold/filter/find, " ++
            "hash-table-walk, assoc/member with a custom predicate, string-index, eval) " ++
            "while an enclosing completed wait needs this thread",
    ) catch return VMError.OutOfMemory;
    vm.gc.pushRoot(&msg);
    defer vm.gc.popRoot();
    const err_obj = vm.gc.allocErrorObject(msg, types.NIL) catch return VMError.OutOfMemory;
    vm.current_exception = err_obj;
    return VMError.ExceptionRaised;
}

/// SRFI 181: a custom port's read!/write!/get-position/set-position!/
/// close/flush callback tried to block -- on another port's fd (called
/// from waitForFd above), via thread-sleep! (primitives_srfi18
/// .threadSleepFn's equivalent guard), or on any other wait at all, since
/// runSchedulerStep below is the shared body behind every one of them.
/// Every such callback runs through vm.callWithArgs, which always
/// executes with dispatched_from_scheduler forced false — so this fiber
/// could never park here the normal way, only recursively drive the
/// scheduler in place, which is the unbounded-native-stack-growth risk
/// this rejects instead. See vm.in_custom_port_callback's doc comment for
/// the full reasoning.
pub fn raiseCustomPortCallbackBlocked(vm: *VM) VMError {
    var msg = vm.gc.allocString(
        "custom port callback blocked: a SRFI 181 read!/write!/get-position/" ++
            "set-position!/close/flush procedure tried to block (e.g. on " ++
            "another port's I/O, on thread-sleep!, or on a channel, join, " ++
            "mutex or condition-variable wait), which is not " ++
            "supported -- custom port callbacks must be effectively " ++
            "synchronous, non-blocking code",
    ) catch return VMError.OutOfMemory;
    vm.gc.pushRoot(&msg);
    defer vm.gc.popRoot();
    const err_obj = vm.gc.allocErrorObject(msg, types.NIL) catch return VMError.OutOfMemory;
    vm.current_exception = err_obj;
    return VMError.ExceptionRaised;
}

/// Called when sched.schedule() finds nothing immediately runnable. Blocks
/// in the reactor — bounded by its own timer heap, so no separate
/// "nearest deadline" computation is needed here — and flips every fiber
/// it reports ready back to `.suspended` (io_waiting) or
/// `.suspended`+`timed_out` (an expired timed `.waiting` wait). Returns
/// `false` only when nothing could ever produce a wakeup: genuine
/// deadlock/done, the same meaning as the bare `break` this replaces.
///
/// `cap_ns`, when given, additionally bounds the blocking wait itself
/// (independent of any registered timer). Needed by waits that might
/// resolve through state no reactor event announces — a mutex/condvar
/// shared with another OS thread's own scheduler, which has no way to
/// signal this one — so a long real timeout registered on `me` doesn't
/// make this call block for that entire duration on the offhand chance a
/// cross-thread resolution arrives sooner; the caller re-checks after each
/// capped return. `null` preserves the original bounded-only-by-registered-
/// timers behavior.
pub fn parkOnReactor(vm: *VM, sched: *FiberScheduler, cap_ns: ?u64) VMError!bool {
    const reactor = vm.reactor orelse return false;
    // Consume protocol (KEP-0002 §5) before the deadlock check: a notify
    // that arrived just before this call must not be missed by
    // hasRunnableFibers() reading a shared_waiters entry the sweep would
    // otherwise have already cleared.
    while (reactor.notifier.wake_pending.swap(false, .acq_rel)) sched.sweepSharedWaiters();
    if (!sched.hasRunnableFibers() and reactor.isEmpty()) return false;

    var ready: std.ArrayList(*Fiber) = .empty;
    defer ready.deinit(vm.gc.allocator);
    reactor.poll(cap_ns, &ready) catch return VMError.OutOfMemory;
    // A notify arriving *during* the blocking poll() above is what actually
    // interrupted it; its wake_pending flag needs consuming here even though
    // poll()'s own ReadyEvent list never surfaces the notifier's own event
    // (reactor.zig's wait() implementations filter it out).
    while (reactor.notifier.wake_pending.swap(false, .acq_rel)) sched.sweepSharedWaiters();

    for (ready.items) |f| {
        wakeReadyFiber(f);
        sched.markRunnable(f);
    }
    return true;
}

/// thread-terminate! sets the *handle's* `terminated` flag, which an
/// OS-thread child's VM reaches through `terminate_flag` (the bytecode
/// safepoint's own check) and a local fiber reaches directly (`me` IS the
/// handle). A native wait must consult both: it never executes bytecode, so
/// without this a thread parked in thread-sleep!/a mutex/a condvar wait
/// never observes termination, never unwinds, and the joining thread hangs
/// forever in reapOsThread's thread.join() (#1982).
fn waitTerminated(vm: *VM, me: *Fiber) bool {
    if (vm.terminate_flag) |flag| {
        if (@atomicLoad(bool, flag, .monotonic)) return true;
    }
    return @atomicLoad(bool, &me.terminated, .monotonic);
}

/// Drives the scheduler — dispatching other fibers, saving/restoring their
/// state exactly as switchTo would — until `ctx.isDone()` becomes true or
/// `me`'s own timed wait expires (`me.timed_out`), parking on the reactor
/// (parkOnReactor) whenever nothing is immediately runnable. Returns
/// `ctx.isDone()`: `true` means the wait resolved normally; `false` means
/// either `me.timed_out` or genuine deadlock — the caller (which knows
/// whether `me` had a deadline) distinguishes those via `me.timed_out`.
///
/// This is the single shared body behind channel-receive, fiber-join,
/// thread-join!, mutex-lock!, condition-variable waits, and thread-sleep!
/// (KEP-0001 Phase 2) — call sites differ only in `Ctx.isDone`. `Ctx` is a
/// small value type with an `isDone(self: Ctx) bool` method (comptime duck
/// typing), e.g. `TargetWait{ .target = f }`. `Ctx` may optionally also
/// define `pollCapNs(self: Ctx) ?u64` (see parkOnReactor) — omitted by
/// every Ctx type except the SRFI-18 mutex/condvar waits, which need it for
/// cross-OS-thread polling.
///
/// `me.driving` brackets the whole call (set here, cleared on every exit
/// via `defer`) regardless of whether the caller also set `me.status =
/// .waiting` first: it marks that `me`'s native frame is live on the Zig
/// call stack for the duration, which scheduleForDispatch()/
/// hasRunnableFibers() must never treat as dispatchable no matter what
/// happens to `status` while this runs (plain schedule() deliberately
/// keeps finding `me` regardless — see its own doc comment for why that
/// half of this split matters just as much as the exclusion does). Without
/// the exclusion, a wake delivered to `me` by something *this* call itself
/// (transitively) dispatches — e.g. a sibling fiber's own nested
/// runSchedulerStep unlocking a mutex `me` is waiting on — flips
/// `me.status` to `.suspended` while `me`'s real, mid-native-call state is
/// this saved snapshot; a scheduleForDispatch() reached through that
/// sibling's own loop (whose `next_idx == my_idx` guard only protects *its
/// own* index, not `me`'s) would then dispatch `me` from the stale
/// snapshot, resuming bytecode past the in-flight primitive call with the
/// destination register never written (#1487; the exact corruption already
/// fixed for channelReceiveShared's dispatched-fiber path in #1485, but
/// reachable here from *any* caller of this function, main fiber included,
/// since a fiber with `driving == true` is always an ancestor of whichever
/// call is currently asking — the whole scheduler runs on one OS thread, so
/// it can only have gotten a nested dispatch by dispatching something whose
/// own call tree is what's presently executing. Ancestors can never make
/// independent progress while a descendant is active regardless, so
/// excluding them from selection changes no genuine liveness outcome —
/// only the parked fiber's own loop, right here, ever consumes its wake).
pub fn runSchedulerStep(comptime Ctx: type, ctx: Ctx, vm: *VM, sched: *FiberScheduler, me: *Fiber) VMError!bool {
    // SRFI 181: reaching here from inside a custom port callback means that
    // callback is about to block, which it may not do -- see
    // vm.in_custom_port_callback's doc comment. The guard lives at this
    // choke point rather than only at the individual blocking primitives
    // because *every* in-place drive arrives here: waitForFd and
    // thread-sleep! check for themselves (both have earlier state to avoid
    // arming), but channel-receive/channel-send/fiber-join and SRFI-18's
    // thread-join!/mutex-lock!/condition-variable-wait did not, and drove
    // the scheduler recursively on the native stack instead -- a whole
    // sibling fiber running inside the callback, and with enough nesting a
    // SIGBUS from stack exhaustion long before callReentrant's own
    // max_native_depth could fire, since each level is a nested runUntil
    // *plus* this drive (#2000).
    //
    // Nothing below has been armed yet -- no saveCurrentFiber, no `driving`
    // flag, no driving_waits entry -- but several callers arm state of
    // their own *before* calling (a timed channel-send/receive, and
    // mutex-lock!/thread-join!/condition-variable-wait unconditionally):
    // .waiting status, a waiter_index enrolment, a reactor timer. Undo what
    // the normal epilogue below undoes, plus the timer, rather than
    // returning with `me` marked parked while it in fact runs on: the
    // waiter_index tolerates a stale entry by design (indexWakeOn
    // revalidates `status == .waiting`, which is also how the success path
    // disposes of one), but that tolerance is exactly what a lying `.waiting`
    // defeats. removeTimer is remove-first, so a caller's own cleanup after
    // catching this stays correct.
    //
    // Defensive, not a reproduced fix: no program was found that observes
    // the difference. Every caller either has no timer to leave behind or
    // detaches it in its own catch, and a leftover `.waiting` self-heals at
    // the fiber's next genuine park (waiting_on is overwritten) or at its
    // retirement. It is kept because "running fiber marked parked" is the
    // precondition for the #1487 dispatch-from-stale-snapshot corruption,
    // and four lines here is cheaper than proving no future caller reaches
    // it.
    if (vm.in_custom_port_callback > 0) {
        me.status = .running;
        me.timed_out = false;
        if (me.deadline_ns != null) {
            if (vm.reactor) |r| r.removeTimer(me);
            me.deadline_ns = null;
        }
        return raiseCustomPortCallbackBlocked(vm);
    }
    const my_idx = sched.current_idx;
    try sched.saveCurrentFiber();
    const poll_cap_ns: ?u64 = if (@hasDecl(Ctx, "pollCapNs")) ctx.pollCapNs() else null;

    me.driving = true;
    defer me.driving = false;

    // Publish this drive's wait so nested drives can evaluate it (#1625) —
    // see driving_waits' doc comment. `ctx` is this frame's parameter, so
    // the pointer stays valid for exactly the extent the entry is stacked.
    // Unlike the ready ring or waiter_index, this list is a correctness
    // registry with no fallback: an entry silently dropped on OOM would
    // re-open the #1625 wedge for this drive's descendants. Fail the wait
    // loudly instead — callers already handle OutOfMemory from inside the
    // loop (saveCurrentFiber's growth, parkOnReactor's poll), and a clean
    // error beats a silent hang at death's door.
    const erased = struct {
        fn isDone(p: *const anyopaque) bool {
            const c: *const Ctx = @ptrCast(@alignCast(p));
            return c.isDone();
        }
    };
    sched.driving_waits.append(vm.gc.allocator, .{
        .fiber = me,
        .ctx = @ptrCast(&ctx),
        .is_done = &erased.isDone,
    }) catch return VMError.OutOfMemory;
    defer _ = sched.driving_waits.pop();

    while (!ctx.isDone() and !me.timed_out) {
        // Checked at the top of every loop iteration: a capped park
        // (pollCapNs, which the SRFI-18 waits set whenever another OS thread
        // could terminate this one) re-enters this loop at that cadence, and
        // a local sibling terminator runs inside this very drive and is
        // observed on the next iteration.
        if (waitTerminated(vm, me)) {
            vm.setErrorDetail("thread terminated", .{});
            return VMError.Terminated;
        }
        const next_idx = sched.scheduleForDispatch() orelse {
            // Nothing dispatchable — but scheduleForDispatch's own per-tick
            // runReactorTick may have just resolved *this* wait, after the
            // loop guard above already read the pre-tick state. A popped
            // timer is the dangerous case (#1870): wakeReadyFiber sets
            // `me.timed_out` and the entry is gone from the timer heap, so
            // the park below has nothing left to bound it — with this
            // fiber's own shared_waiters entry keeping hasRunnableFibers()
            // true, parkOnReactor blocks in an unbounded reactor.poll()
            // that only an unrelated cross-thread notify can release. Re-
            // check here rather than one `continue` later: the loop guard
            // never gets its turn because the park never returns.
            if (me.timed_out or ctx.isDone()) break;
            // A wait that opted in gives up instead when an ancestor drive's
            // condition has already resolved: that ancestor can only
            // proceed once we unwind, and blocking here — for I/O waits,
            // on this fiber's own fd with no bound — would pin it forever
            // (#1625: a guard-wrapped reader's in-place drive vs. the
            // enclosing fiber-join whose target already completed). Checked
            // only at the idle point so runnable siblings still get
            // dispatched first — one of them may resolve *this* wait, which
            // is always the better outcome.
            if (comptime @hasDecl(Ctx, "unwind_on_resolved_ancestor")) {
                if (sched.anyAncestorWaitResolved(me)) break;
            }
            if (!(try parkOnReactor(vm, sched, poll_cap_ns))) break;
            continue;
        };
        // Unreachable in practice since `driving` (set above) now excludes
        // `me` from scheduleForDispatch() at every index, but kept as
        // defense-in-depth: this is the narrower guard `driving` subsumes
        // (it only ever protected this loop's own re-selection of itself,
        // not the cross-fiber case #1487 fixes).
        if (next_idx == my_idx) break;

        try sched.restoreFiber(next_idx);
        sched.current_idx = next_idx;
        const fiber = sched.fibers.items[next_idx].?;
        fiber.status = .running;
        vm.current_fiber = fiber;

        // A dangling yield_retry (a forwarding native converted a park's
        // Yielded into another error) must not survive into this run.
        vm.yield_retry = false;
        vm.sched_dispatch_pending = true;
        const result = vm.runUntil(0, 0) catch |err| {
            if (err == VMError.Yielded) {
                try sched.saveCurrentFiber();
                if (fiber.status == .running) {
                    fiber.status = .suspended;
                    sched.markRunnable(fiber);
                }
                continue;
            }
            // Fiber 0 is the main fiber: finishing or aborting one
            // top-level form is not thread death, so its mutexes stay
            // valid. retireSlot returns the vacated slot to the free list
            // (a no-op for slot 0), keeping addFiber's fast path fed.
            sched.retireSlot(fiber, .errored);
            if (next_idx != 0) abandonFiberMutexes(fiber, sched);
            try sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        sched.retireSlot(fiber, .completed);
        fiber.result = result;
        vm.gc.writeBarrier(&fiber.header, result);
        if (next_idx != 0) abandonFiberMutexes(fiber, sched);
        try sched.saveCurrentFiber();
        sched.wakeWaiters(fiber);
    }

    // Captured before the epilogue below touches `me`: CondVarWait's
    // isDone() reads me.status, which the next line unconditionally
    // forces to .running — evaluating ctx.isDone() after that would
    // always report true regardless of whether the wait actually resolved.
    const done = ctx.isDone();
    try sched.restoreFiber(my_idx);
    sched.current_idx = my_idx;
    me.status = .running;
    vm.current_fiber = me;
    return done;
}
