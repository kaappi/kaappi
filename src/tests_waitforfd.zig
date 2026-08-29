// Audit v2 Phase 5B: the fiber park-vs-drive protocol (`fiber.waitForFd`),
// its ancestor-unwind escape (`FiberScheduler.anyAncestorWaitResolved` over
// `driving_waits`, #1625), and the yield-retry contract the park branch
// imposes on every caller.
//
// Before this file, `waitForFd`, `driving_waits` and `anyAncestorWaitResolved`
// had ZERO direct references in any `src/tests_*.zig`: the branch was reached
// only incidentally, through Scheme programs that happened to park. Incidental
// coverage cannot tell you *which* branch ran, so a change that made every
// caller drive in place (or every caller park) would have kept the whole
// suite green.
//
// The tests here therefore assert the branch, not just the answer. They are
// deterministic by construction: the selector — `my_idx != 0 and
// vm.dispatched_from_scheduler` — is plain VM state, so each of the four
// cells is set up directly rather than raced into. The end-to-end tests use
// the FIFO-dispatch handshake from tests_port_io's #1625 case (drive the
// scheduler with a trivial join, which dispatches the reader first) to reach
// a *confirmed* parked state before asserting on it, rather than sleeping.
//
// Complements tests_reactor.zig (reactor in isolation), tests_scheduler.zig
// (scheduler plumbing) and tests_port_io.zig (port layer end-to-end).

const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const fiber_mod = @import("fiber.zig");
const reactor_mod = @import("reactor.zig");
const platform = @import("platform.zig");
const printer = @import("printer.zig");
const primitives_fiber = @import("primitives_fiber.zig");
const primitives_srfi18 = @import("primitives_srfi18.zig");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps `fd` in a port bound to `name`. The port owns the fd from here.
fn definePortGlobal(vm: *th.VM, name: []const u8, fd: platform.fd_t, is_input: bool, is_output: bool) !*types.Port {
    const port_val = try vm.gc.allocPort(fd, is_input, is_output, name, false);
    try vm.defineGlobal(name, port_val);
    return types.toObject(port_val).as(types.Port);
}

/// A second fiber occupying a non-zero scheduler slot, so `my_idx != 0` —
/// the first half of waitForFd's park selector — can be set up directly
/// instead of being raced into via a real spawn.
fn addSecondFiber(sched: *fiber_mod.FiberScheduler, gc: *memory.GC) !*fiber_mod.Fiber {
    const f = try gc.allocFiber(types.VOID, sched.next_id);
    sched.next_id += 1;
    try sched.addFiber(f);
    std.debug.assert(f.sched_idx != 0);
    return f;
}

/// Makes `me` the fiber `waitForFd` will see, at slot `me.sched_idx`.
fn becomeCurrent(vm: *th.VM, sched: *fiber_mod.FiberScheduler, me: *fiber_mod.Fiber) void {
    sched.current_idx = me.sched_idx;
    vm.current_fiber = me;
    me.status = .running;
}

/// Undoes a park so the VM can be torn down without leaving a fiber listed
/// on the reactor in a non-parked status (which register()'s Debug
/// staleness assertion would later trip on).
fn unpark(vm: *th.VM, f: *fiber_mod.Fiber, fd: platform.fd_t) void {
    if (vm.reactor) |r| r.removeWaiter(fd, f);
    f.status = .suspended;
    f.io_fd = null;
    vm.yield_retry = false;
}

/// Total fibers currently listed on `fd` in either direction.
fn waiterCount(r: *reactor_mod.Reactor, fd: platform.fd_t) usize {
    const reg = r.regs.getPtr(fd) orelse return 0;
    return reg.read_waiters.items.len + reg.write_waiters.items.len;
}

/// Runs the scheduler once from the main fiber so every already-spawned
/// fiber reaches its first blocking point. FIFO dispatch guarantees the
/// fibers spawned earlier run before the trivial one this join waits on,
/// so on return each of them is parked (or finished) — no sleeping, no
/// wall-clock assumption.
fn settleSpawnedFibers(vm: *th.VM) !void {
    _ = try vm.eval("(fiber-join (spawn (lambda () 'settle)))");
}

// ===========================================================================
// Group A — the park-vs-drive selector, all four cells
//
// waitForFd branches on `my_idx != 0 and vm.dispatched_from_scheduler`
// (fiber.zig). Each cell below sets both terms explicitly and asserts which
// branch ran, so the two cells that must DRIVE are discriminating controls
// for the two terms of the conjunction rather than incidental passes.
//
// The park cells deliberately use an fd that is *already readable*: the park
// branch returns before the wait is ever evaluated, so readiness must make no
// difference. That is what separates "parks because it was told to" from
// "parks because the fd was not ready".
// ===========================================================================

test "waitForFd cell (idx!=0, dispatched): parks — Yielded, io_waiting, retry armed" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    // The port owns fd[0]; fd[1] is ours to close.
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const f = try addSecondFiber(ctx.sched, &gc);
    becomeCurrent(vm, ctx.sched, f);
    vm.dispatched_from_scheduler = true;

    // Readiness must be irrelevant on this branch: make the fd genuinely
    // readable first, so a park here cannot be explained by "not ready".
    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "x"));

    const err = fiber_mod.waitForFd(vm, pair[0], .read);
    try std.testing.expectError(vm_mod.VMError.Yielded, err);

    // The park signature: retry armed, fiber parked on this fd, listed on
    // the reactor so the poll can find it.
    try std.testing.expect(vm.yield_retry);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
    try std.testing.expectEqual(@as(?platform.fd_t, pair[0]), f.io_fd);
    try std.testing.expectEqual(reactor_mod.Interest.read, f.io_interest);
    try std.testing.expectEqual(@as(usize, 1), waiterCount(ctx.reactor, pair[0]));

    unpark(vm, f, pair[0]);
}

test "waitForFd cell (idx==0, dispatched): drives — control for the my_idx term" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const main_fiber = ctx.sched.fibers.items[0].?;
    try std.testing.expectEqual(@as(usize, 0), ctx.sched.current_idx);

    // Same dispatched_from_scheduler as the parking cell above; only the
    // slot index differs. The fd is ready so the in-place drive returns.
    vm.dispatched_from_scheduler = true;
    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "x"));

    try fiber_mod.waitForFd(vm, pair[0], .read);

    // The drive signature: normal return, no retry armed, and waitForFd's
    // own defer has already pulled the fiber back off the reactor.
    try std.testing.expect(!vm.yield_retry);
    try std.testing.expectEqual(fiber_mod.FiberStatus.running, main_fiber.status);
    try std.testing.expectEqual(@as(?platform.fd_t, null), main_fiber.io_fd);
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));
}

test "waitForFd cell (idx!=0, not dispatched): drives — control for the dispatched term" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const f = try addSecondFiber(ctx.sched, &gc);
    becomeCurrent(vm, ctx.sched, f);

    // Same non-zero slot as the parking cell; only dispatched_from_scheduler
    // differs. This is the shape a custom-port callback or any re-entrant
    // native frame runs in — it cannot be rewound, so it must drive.
    vm.dispatched_from_scheduler = false;
    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "x"));

    try fiber_mod.waitForFd(vm, pair[0], .read);

    try std.testing.expect(!vm.yield_retry);
    try std.testing.expectEqual(fiber_mod.FiberStatus.running, f.status);
    try std.testing.expectEqual(@as(?platform.fd_t, null), f.io_fd);
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));
}

test "waitForFd cell (idx==0, not dispatched): drives — the sequential main-fiber path" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    try std.testing.expectEqual(@as(usize, 0), ctx.sched.current_idx);
    try std.testing.expect(!vm.dispatched_from_scheduler);
    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "x"));

    try fiber_mod.waitForFd(vm, pair[0], .read);

    try std.testing.expect(!vm.yield_retry);
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));
}

test "waitForFd's park branch ignores fd readiness entirely" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // The mirror of the park cell above: an fd with nothing to read parks
    // identically. Together the two pin that the branch is chosen by
    // dispatch state alone — readiness is never consulted before the
    // decision, which is exactly why the retry (not this call) is what
    // re-checks the fd.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const f = try addSecondFiber(ctx.sched, &gc);
    becomeCurrent(vm, ctx.sched, f);
    vm.dispatched_from_scheduler = true;

    try std.testing.expectError(vm_mod.VMError.Yielded, fiber_mod.waitForFd(vm, pair[0], .read));
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
    unpark(vm, f, pair[0]);
}

test "waitForFd parks on write interest with the same selector" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // .write is the second interest the port layer uses (drainWriteBuffer);
    // the selector is interest-independent, and the registration must land
    // in the write list, not the read one.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "wp", pair[1], false, true);
    defer th.closeFd(pair[0]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const f = try addSecondFiber(ctx.sched, &gc);
    becomeCurrent(vm, ctx.sched, f);
    vm.dispatched_from_scheduler = true;

    try std.testing.expectError(vm_mod.VMError.Yielded, fiber_mod.waitForFd(vm, pair[1], .write));
    try std.testing.expectEqual(reactor_mod.Interest.write, f.io_interest);
    const reg = ctx.reactor.regs.getPtr(pair[1]).?;
    try std.testing.expectEqual(@as(usize, 1), reg.write_waiters.items.len);
    try std.testing.expectEqual(@as(usize, 0), reg.read_waiters.items.len);

    unpark(vm, f, pair[1]);
}

test "waitForFd restores status and unregisters when reactor registration fails" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // The one pre-branch failure path: register() rejects the fd (EBADF on
    // a closed one). Neither branch has run yet, so the fiber must be left
    // exactly as it was found — not stranded in .io_waiting with a dangling
    // io_fd, which register()'s own staleness assertion would trip on later.
    //
    // POSIX only. The rejection itself is backend-specific: kqueue's EV_ADD
    // and epoll's EPOLL_CTL_ADD both fail EBADF on a closed fd, but
    // Windows' arm() classifies via fdKind first, and WASI's arm() cannot
    // fail at all (it only records interest in a userspace map). What
    // waitForFd does *given* a failed register is backend-independent; only
    // this way of provoking one is not.
    if (comptime platform.is_windows) return error.SkipZigTest;
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const ctx = try fiber_mod.ensureScheduler(vm);
    const main_fiber = ctx.sched.fibers.items[0].?;
    const before = main_fiber.status;

    const pair = th.makeBidiFdPair();
    th.closeFd(pair[0]);
    th.closeFd(pair[1]);

    const r = fiber_mod.waitForFd(vm, pair[0], .read);
    // kqueue/epoll reject a closed fd at arm time. If some backend ever
    // accepts it instead, the wait would hang rather than fail — so a
    // non-error return here is itself the thing to investigate.
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, r);
    try std.testing.expectEqual(before, main_fiber.status);
    try std.testing.expectEqual(@as(?platform.fd_t, null), main_fiber.io_fd);
    try std.testing.expect(!vm.yield_retry);
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));
}

// ===========================================================================
// Group B — the unwind asymmetry (#1625)
//
// `IoWait` is the ONLY wait kind that opts into breaking off an idle drive
// when an enclosing drive's wait has already resolved. runSchedulerStep gates
// that on `@hasDecl(Ctx, "unwind_on_resolved_ancestor")`, so the asymmetry is
// invisible to the type system: adding the decl to a join/channel/mutex wait
// — or deleting it from IoWait — compiles cleanly and silently changes
// blocking semantics for that wait kind.
//
// The table below is the enforcement. The `false` rows are the point: they had
// no coverage at all, and an accidental opt-in would have been silent.
// ===========================================================================

const UnwindRow = struct {
    name: []const u8,
    Ctx: type,
    /// Whether this wait may abandon itself when an ancestor drive resolved.
    unwinds: bool,
};

const unwind_table = [_]UnwindRow{
    // The sole opt-in: an fd wait's own registration defeats the generic
    // idle escape (hasRunnableFibers counts it, the fd keeps the reactor
    // non-empty), so unwinding is the only exit.
    .{ .name = "IoWait", .Ctx = fiber_mod.IoWait, .unwinds = true },

    // Everything below resolves through an in-thread wake or its own
    // deadline, so parkOnReactor's deadlock check already covers the idle
    // case and a timed wait must run its full duration.
    .{ .name = "TargetWait (fiber-join / thread-join!)", .Ctx = fiber_mod.TargetWait, .unwinds = false },
    .{ .name = "OsJoinWait (thread-join! on an OS thread)", .Ctx = primitives_srfi18.OsJoinWait, .unwinds = false },
    .{ .name = "SleepWait (thread-sleep!)", .Ctx = primitives_srfi18.SleepWait, .unwinds = false },
    .{ .name = "MutexWait (mutex-lock!)", .Ctx = primitives_srfi18.MutexWait, .unwinds = false },
    .{ .name = "CondVarWait (condition-variable-wait!)", .Ctx = primitives_srfi18.CondVarWait, .unwinds = false },
    .{ .name = "ChannelWait (channel-receive)", .Ctx = primitives_fiber.ChannelWait, .unwinds = false },
    .{ .name = "ChannelSendWait (channel-send)", .Ctx = primitives_fiber.ChannelSendWait, .unwinds = false },
    .{ .name = "SharedChannelWait", .Ctx = primitives_fiber.SharedChannelWait, .unwinds = false },
    .{ .name = "SharedChannelPoll", .Ctx = primitives_fiber.SharedChannelPoll, .unwinds = false },
    .{ .name = "SharedChannelSendPoll", .Ctx = primitives_fiber.SharedChannelSendPoll, .unwinds = false },
};

test "#1625: exactly one wait kind opts into ancestor-resolved unwinding" {
    var opted_in: usize = 0;
    inline for (unwind_table) |row| {
        const has = @hasDecl(row.Ctx, "unwind_on_resolved_ancestor");
        if (has != row.unwinds) {
            std.debug.print(
                "\nunwind_on_resolved_ancestor changed for {s}: expected {}, found {}\n" ++
                    "This flag decides whether an idle in-place drive may abandon itself.\n" ++
                    "Opting a join/channel/mutex/condvar wait in turns a legitimate block\n" ++
                    "into a spurious raise; opting IoWait out re-opens the #1625 wedge.\n",
                .{ row.name, row.unwinds, has },
            );
            return error.UnwindAsymmetryChanged;
        }
        if (has) {
            try std.testing.expect(row.Ctx.unwind_on_resolved_ancestor);
            opted_in += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), opted_in);
}

test "#1625: every wait context still satisfies runSchedulerStep's duck type" {
    // The comptime contract the table above is only meaningful against:
    // isDone is mandatory, externalWakePossible optional (cross-OS-thread
    // waits only, kaappi#2395), and pollCapNs must be GONE — a reappearing
    // cap means someone reintroduced the 1 ms cross-thread poll the
    // notifier rings replaced.
    var with_external: usize = 0;
    inline for (unwind_table) |row| {
        if (!@hasDecl(row.Ctx, "isDone")) return error.MissingIsDone;
        if (@hasDecl(row.Ctx, "pollCapNs")) return error.PollCapReintroduced;
        if (@hasDecl(row.Ctx, "externalWakePossible")) with_external += 1;
    }
    // The waits resolvable by another OS thread's ring: mutex unlock/
    // abandon (MutexWait), condvar signal/broadcast (CondVarWait), and an
    // OS thread's exit ring-all (OsJoinWait). SleepWait deliberately has
    // none — its park is always timer-bounded, and the terminate interrupt
    // that used to justify its cap (#1982) now rings the victim's notifier
    // directly. A new decl beyond these three means a new cross-thread
    // wake path worth reviewing.
    try std.testing.expectEqual(@as(usize, 3), with_external);
}

// --- anyAncestorWaitResolved, directly ------------------------------------

const AlwaysDone = struct {
    pub fn isDone(_: AlwaysDone) bool {
        return true;
    }
};
const NeverDone = struct {
    pub fn isDone(_: NeverDone) bool {
        return false;
    }
};

fn erasedIsDone(comptime Ctx: type) *const fn (*const anyopaque) bool {
    return &struct {
        fn f(p: *const anyopaque) bool {
            const c: *const Ctx = @ptrCast(@alignCast(p));
            return c.isDone();
        }
    }.f;
}

test "anyAncestorWaitResolved: false when the only live drive is my own" {
    // The identity match (`w.fiber != me`) is what makes the check
    // independent of driving_waits' push/pop bookkeeping. Without it, a
    // fiber whose OWN wait had resolved would read as "an ancestor
    // resolved" and abandon a wait that was about to succeed.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const ctx = try fiber_mod.ensureScheduler(vm);
    const me = ctx.sched.fibers.items[0].?;

    const done_ctx = AlwaysDone{};
    try ctx.sched.driving_waits.append(gc.allocator, .{
        .fiber = me,
        .ctx = @ptrCast(&done_ctx),
        .is_done = erasedIsDone(AlwaysDone),
    });
    defer _ = ctx.sched.driving_waits.pop();

    try std.testing.expect(!ctx.sched.anyAncestorWaitResolved(me));
}

test "anyAncestorWaitResolved: true when another fiber's drive has resolved" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const ctx = try fiber_mod.ensureScheduler(vm);
    const ancestor = ctx.sched.fibers.items[0].?;
    const me = try addSecondFiber(ctx.sched, &gc);

    const done_ctx = AlwaysDone{};
    try ctx.sched.driving_waits.append(gc.allocator, .{
        .fiber = ancestor,
        .ctx = @ptrCast(&done_ctx),
        .is_done = erasedIsDone(AlwaysDone),
    });
    defer _ = ctx.sched.driving_waits.pop();

    try std.testing.expect(ctx.sched.anyAncestorWaitResolved(me));
}

test "anyAncestorWaitResolved: false when another fiber's drive is unresolved" {
    // The discriminating control for the test above: same two-entry shape,
    // only the ancestor's isDone differs.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const ctx = try fiber_mod.ensureScheduler(vm);
    const ancestor = ctx.sched.fibers.items[0].?;
    const me = try addSecondFiber(ctx.sched, &gc);

    const pending = NeverDone{};
    try ctx.sched.driving_waits.append(gc.allocator, .{
        .fiber = ancestor,
        .ctx = @ptrCast(&pending),
        .is_done = erasedIsDone(NeverDone),
    });
    defer _ = ctx.sched.driving_waits.pop();

    try std.testing.expect(!ctx.sched.anyAncestorWaitResolved(me));
    // ...and an expired timed wait resolves it even though isDone stays
    // false: a pure sleep resolves ONLY via timed_out.
    ancestor.timed_out = true;
    try std.testing.expect(ctx.sched.anyAncestorWaitResolved(me));
    ancestor.timed_out = false;
}

test "anyAncestorWaitResolved: scans the whole stack, not just the top entry" {
    // Drives nest arbitrarily deep. A resolved wait two levels up is just
    // as pinned as one level up, so the scan must not stop at the nearest
    // ancestor (nor at the innermost entry, which is the caller's own).
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const ctx = try fiber_mod.ensureScheduler(vm);
    const outer = ctx.sched.fibers.items[0].?;
    const middle = try addSecondFiber(ctx.sched, &gc);
    const me = try addSecondFiber(ctx.sched, &gc);

    const done_ctx = AlwaysDone{};
    const pending = NeverDone{};
    // outermost first: [outer resolved, middle pending, me pending]
    try ctx.sched.driving_waits.append(gc.allocator, .{
        .fiber = outer,
        .ctx = @ptrCast(&done_ctx),
        .is_done = erasedIsDone(AlwaysDone),
    });
    try ctx.sched.driving_waits.append(gc.allocator, .{
        .fiber = middle,
        .ctx = @ptrCast(&pending),
        .is_done = erasedIsDone(NeverDone),
    });
    try ctx.sched.driving_waits.append(gc.allocator, .{
        .fiber = me,
        .ctx = @ptrCast(&pending),
        .is_done = erasedIsDone(NeverDone),
    });
    defer ctx.sched.driving_waits.clearRetainingCapacity();

    try std.testing.expect(ctx.sched.anyAncestorWaitResolved(me));
    // The middle drive sees the same resolved outer one.
    try std.testing.expect(ctx.sched.anyAncestorWaitResolved(middle));
    // The outer drive itself sees no resolved ancestor: its own entry is
    // excluded by identity and both descendants are pending.
    try std.testing.expect(!ctx.sched.anyAncestorWaitResolved(outer));
}

test "an empty driving_waits stack never reports a resolved ancestor" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const ctx = try fiber_mod.ensureScheduler(vm);
    const me = ctx.sched.fibers.items[0].?;
    try std.testing.expectEqual(@as(usize, 0), ctx.sched.driving_waits.items.len);
    try std.testing.expect(!ctx.sched.anyAncestorWaitResolved(me));
}

// ===========================================================================
// Group C — the yield-retry contract
//
// A parked primitive re-executes FROM SCRATCH when the fd fires. Every byte a
// caller holds in a Zig local at that moment is lost, because the read
// position of the underlying port has already advanced past it. The contract
// is that callers stash partial progress into `port.read_buf` first
// (primitives_io.propagateReadErr) — a durable *Port field that survives the
// re-execution.
//
// These tests reach a CONFIRMED park (asserted, not assumed) with the port's
// stream deliberately torn mid-item, then assert both halves: that the bytes
// landed in read_buf, and that the resumed primitive produces the whole item.
// Without the stash the resumed read would see only the tail.
// ===========================================================================

test "yield-retry: a park mid-UTF-8-sequence stashes the consumed prefix" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    const rp = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");

    // U+20AC EURO SIGN is E2 82 AC. Deliver only the lead byte, so the
    // reader consumes it and then EAGAINs mid-sequence — the exact moment
    // the contract exists for.
    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "\xE2"));

    _ = try vm.eval("(define f (spawn (lambda () (read-char rp))))");
    try settleSpawnedFibers(vm);

    // Confirmed parked mid-sequence — this is the state under test, not a
    // hoped-for one.
    const f = types.toObject(try vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
    try std.testing.expectEqual(@as(?platform.fd_t, pair[0]), f.io_fd);

    // The stash: the lead byte is back in the port's durable buffer. Held
    // in a Zig local instead, it would be gone — the fd has advanced past
    // it and no retry could recover it.
    try std.testing.expect(rp.read_buf != null);
    try std.testing.expectEqual(@as(usize, 1), rp.read_buf_len);
    try std.testing.expectEqual(@as(u8, 0xE2), rp.read_buf.?[rp.read_buf.?.len - 1]);

    // Resume: the retry re-reads the stashed prefix and completes the char.
    try std.testing.expectEqual(@as(isize, 2), th.fdWrite(pair[1], "\x82\xAC"));
    const c = try vm.eval("(fiber-join f)");
    try std.testing.expectEqual(types.makeChar(0x20AC), c);
}

test "yield-retry: a park mid-line stashes the partial line" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    const rp = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");
    try std.testing.expectEqual(@as(isize, 3), th.fdWrite(pair[1], "abc"));

    _ = try vm.eval("(define f (spawn (lambda () (read-line rp))))");
    try settleSpawnedFibers(vm);

    const f = types.toObject(try vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);

    // read-line accumulates into a Zig ArrayList; propagateReadErr moves it
    // to read_buf before the park propagates.
    try std.testing.expect(rp.read_buf != null);
    try std.testing.expectEqual(@as(usize, 3), rp.read_buf_len);
    const live = rp.read_buf.?[rp.read_buf.?.len - rp.read_buf_len ..];
    try std.testing.expectEqualStrings("abc", live);

    try std.testing.expectEqual(@as(isize, 4), th.fdWrite(pair[1], "def\n"));
    const s = try vm.eval("(fiber-join f)");
    const str = types.toObject(s).as(types.SchemeString);
    try std.testing.expectEqualStrings("abcdef", str.data[0..str.len]);
}

test "yield-retry: a park mid-CRLF stashes the bare carriage return" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // read-line's CR lookahead consumes a byte it has not appended. If the
    // lookahead parks and the CR is not re-stashed, the retry never reaches
    // the same decision point and the line boundary silently moves.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    const rp = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");
    try std.testing.expectEqual(@as(isize, 3), th.fdWrite(pair[1], "hi\r"));

    _ = try vm.eval("(define f (spawn (lambda () (read-line rp))))");
    try settleSpawnedFibers(vm);

    const f = types.toObject(try vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
    try std.testing.expect(rp.read_buf != null);
    const live = rp.read_buf.?[rp.read_buf.?.len - rp.read_buf_len ..];
    try std.testing.expectEqualStrings("hi\r", live);

    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "\n"));
    const s = try vm.eval("(fiber-join f)");
    const str = types.toObject(s).as(types.SchemeString);
    try std.testing.expectEqualStrings("hi", str.data[0..str.len]);
}

test "yield-retry: a park mid-datum stashes the partial datum for (read)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    const rp = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");
    try std.testing.expectEqual(@as(isize, 5), th.fdWrite(pair[1], "(1 2 "));

    _ = try vm.eval("(define f (spawn (lambda () (read rp))))");
    try settleSpawnedFibers(vm);

    const f = types.toObject(try vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
    const live = rp.read_buf.?[rp.read_buf.?.len - rp.read_buf_len ..];
    try std.testing.expectEqualStrings("(1 2 ", live);

    try std.testing.expectEqual(@as(isize, 2), th.fdWrite(pair[1], "3)"));
    const got = try vm.eval("(equal? (fiber-join f) '(1 2 3))");
    try std.testing.expectEqual(types.TRUE, got);
}

test "yield-retry: a park at an item boundary stashes nothing" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // The control for the four tests above: with no partial progress to
    // preserve, the park must leave read_buf empty. A stash-everything
    // implementation would pass those and fail this.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    const rp = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");
    _ = try vm.eval("(define f (spawn (lambda () (read-char rp))))");
    try settleSpawnedFibers(vm);

    const f = types.toObject(try vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
    try std.testing.expectEqual(@as(usize, 0), rp.read_buf_len);
    try std.testing.expect(rp.read_buf == null);

    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "z"));
    try std.testing.expectEqual(types.makeChar('z'), try vm.eval("(fiber-join f)"));
}

test "yield-retry: a write-side park resumes from write_buf_start without duplicating" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // The write half of the contract takes a different route from the read
    // half: portWriteBytes drains BEFORE appending, and drainWriteBuffer
    // records how far it got in the port's own `write_buf_start`. Nothing is
    // ever held in a Zig local across the park, so no stash is needed — but
    // the durable cursor must survive the re-execution, and the resumed
    // write must not re-emit what it already sent.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Tiny kernel buffers so a 20 KB drain must EAGAIN — the same idiom
    // tests_port_io uses, and the reason the drainer below is a sibling
    // FIBER rather than a test-side read loop: a blocking read on the OS
    // thread wedges the whole test, and the scheduler cannot rescue a
    // thread stuck inside read(2) rather than inside the reactor.
    const fds = th.makeBidiFdPair();
    th.setSockBufSize(fds[0], .snd, 4096);
    th.setSockBufSize(fds[1], .rcv, 4096);
    _ = try definePortGlobal(vm, "sp", fds[0], true, true);
    _ = try definePortGlobal(vm, "peer", fds[1], true, true);

    _ = try vm.eval("(import (kaappi fibers))");
    // write-string appends the whole 20 KB to the port's buffer (the
    // high-water drain only flushes *prior* pending bytes), so the flush is
    // where the EAGAIN — and the park — happens.
    _ = try vm.eval(
        \\(define f (spawn (lambda ()
        \\  (write-string (make-string 20000 #\x) sp)
        \\  (flush-output-port sp)
        \\  'wrote)))
    );
    try settleSpawnedFibers(vm);

    // Confirmed parked on WRITE readiness — the write half of the selector,
    // reached through the port layer rather than set up by hand.
    //
    // POSIX only. On Windows CI the fiber reaches `.completed` here instead:
    // the 20 KB write is accepted outright, so the flush never EAGAINs and
    // there is nothing to park on. Whether that is because a reduced
    // SO_SNDBUF is not honoured, or because the socket layer buffers past
    // it, is NOT established here — only the observed outcome is.
    //
    // The gate is deliberately narrow: it covers the three parking
    // assertions, not the lossless-resume assertions below. Those are the
    // property the test exists for and they run on every platform, whether
    // or not a park happened to occur.
    const f = types.toObject(try vm.eval("f")).as(fiber_mod.Fiber);
    if (comptime !platform.is_windows) {
        try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
        try std.testing.expectEqual(reactor_mod.Interest.write, f.io_interest);
        try std.testing.expectEqual(@as(?platform.fd_t, fds[0]), f.io_fd);
    }

    // The drainer runs as a fiber, so writer and reader ping-pong through
    // the reactor across many parks and re-executions of the flush.
    _ = try vm.eval("(define g (spawn (lambda () (read-string 20000 peer))))");
    const wrote = try vm.eval("(eq? (fiber-join f) 'wrote)");
    try std.testing.expectEqual(types.TRUE, wrote);

    // Exactly the payload arrived: nothing lost to a park, and — the point
    // of draining BEFORE appending — nothing duplicated by a re-execution.
    const ok = try vm.eval(
        \\(let ((s (fiber-join g)))
        \\  (and (= (string-length s) 20000)
        \\       (string=? s (make-string 20000 #\x))))
    );
    try std.testing.expectEqual(types.TRUE, ok);
}

// ===========================================================================
// Group D — interactions
// ===========================================================================

test "which frames force the drive branch: guard does; map and dynamic-wind do not" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // waitForFd's doc comment names "guard, dynamic-wind, callbacks" as the
    // re-entrant native frames that make a spawned fiber drive rather than
    // park, and vm.in_custom_port_callback's own comment lists
    // "with-exception-handler thunks, map/for-each callbacks, apply" as
    // reentrant calls. The mechanism is `runUntil` clearing
    // dispatched_from_scheduler on every NESTED entry (vm_dispatch.zig:83).
    //
    // Two of those names no longer create a nested runUntil at all: `map`
    // (and for-each) and `dynamic-wind` are bootstrapped in *Scheme*
    // (vm_bootstrap.zig definitions[]), so their thunk call is an ordinary
    // Scheme call in the SAME runUntil. All four fibers below run the
    // identical `(read-char rp)`; only the frames around it differ, so the
    // parked/drove split is attributable to the wrapper and nothing else.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");
    // FIFO order matters: in-guard is dispatched first and drives in place;
    // its drive runs the other three (which park) and then the settle fiber,
    // whose completion resolves the enclosing join — at which point
    // in-guard's now-idle drive sees the resolved ancestor and unwinds.
    _ = try vm.eval(
        \\(define in-guard (spawn (lambda ()
        \\  (guard (e (#t (list 'caught (error-object-message e)))) (read-char rp)))))
        \\(define in-map   (spawn (lambda () (map (lambda (x) (read-char rp)) '(1)))))
        \\(define in-wind  (spawn (lambda ()
        \\  (dynamic-wind (lambda () #f) (lambda () (read-char rp)) (lambda () #f)))))
        \\(define in-tail  (spawn (lambda () (read-char rp))))
    );
    try settleSpawnedFibers(vm);

    const in_guard = types.toObject(try vm.eval("in-guard")).as(fiber_mod.Fiber);
    const in_map = types.toObject(try vm.eval("in-map")).as(fiber_mod.Fiber);
    const in_wind = types.toObject(try vm.eval("in-wind")).as(fiber_mod.Fiber);
    const in_tail = types.toObject(try vm.eval("in-tail")).as(fiber_mod.Fiber);

    // Parked: the bare read, the read one Scheme-level `map` deep, and the
    // read inside a Scheme-level `dynamic-wind` thunk.
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, in_tail.status);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, in_map.status);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, in_wind.status);
    // Drove, then abandoned — the whole difference is the `guard`.
    try std.testing.expectEqual(fiber_mod.FiberStatus.completed, in_guard.status);

    const msg_val = try vm.eval("(cadr (fiber-join in-guard))");
    const msg = types.toObject(msg_val).as(types.SchemeString);
    try std.testing.expect(std.mem.startsWith(u8, msg.data[0..msg.len], "port I/O abandoned"));

    // Release the still-parked siblings so teardown finds no listed waiter.
    _ = try vm.eval("(close-port rp)");
    _ = try vm.eval("(guard (e (#t 'caught)) (fiber-join in-tail))");
    _ = try vm.eval("(guard (e (#t 'caught)) (fiber-join in-map))");
    _ = try vm.eval("(guard (e (#t 'caught)) (fiber-join in-wind))");
}

test "close-port on a parked fd wakes the waiter and its retry raises cleanly" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // wakeIoWaitersOnFd's contract on the PARK path (the existing
    // tests_port_io close test covers the drive path, where the wait
    // returns into waitPortFd's own is_open re-check). Here the retry is
    // what must notice: the whole primitive re-executes, getInputPort sees
    // a closed port, and a catchable error replaces a sleep on an fd that
    // will never fire.
    //
    // The reader deliberately carries NO `guard`. A guard would put it
    // under re-entrant native frames, which clears dispatched_from_scheduler
    // and sends it down the DRIVE branch instead — it would never park at
    // all, and the settle pump below would unwind it via #1625.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");
    _ = try vm.eval("(define f (spawn (lambda () (read-char rp))))");
    try settleSpawnedFibers(vm);

    const f = types.toObject(try vm.eval("f")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f.status);
    const ctx = try fiber_mod.ensureScheduler(vm);
    try std.testing.expectEqual(@as(usize, 1), waiterCount(ctx.reactor, pair[0]));

    _ = try vm.eval("(close-port rp)");

    // Woken off io_waiting and unregistered: no fiber may remain listed on
    // an fd the reactor no longer knows about.
    try std.testing.expect(f.status != .io_waiting);
    try std.testing.expectEqual(@as(?platform.fd_t, null), f.io_fd);
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));

    // The join dispatches the woken fiber; its retry raises, the fiber
    // errors, and fiber-join re-raises into this guard. "Cleanly" means an
    // error object, not a hang and not a bogus value.
    const r = try vm.eval(
        \\(guard (e (#t (list 'caught (error-object? e))))
        \\  (fiber-join f)
        \\  'not-reached)
    );
    const s = try printer.valueToString(std.testing.allocator, r, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(caught #t)", s);
}

test "a custom-port callback is refused before the drive, even on a ready fd" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // vm.in_custom_port_callback is checked BEFORE runSchedulerStep, so the
    // rejection does not depend on the fd being unready — a callback that
    // would have succeeded by luck still gets the documented error rather
    // than an unbounded recursive drive. The early return sits after
    // waitForFd's cleanup defer is armed, so the fd wait must still be
    // unregistered.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "x"));

    vm.in_custom_port_callback += 1;
    const r = fiber_mod.waitForFd(vm, pair[0], .read);
    vm.in_custom_port_callback -= 1;

    try std.testing.expectError(vm_mod.VMError.ExceptionRaised, r);
    const exc = vm.current_exception.?;
    const msg_val = types.toObject(exc).as(types.ErrorObject).message;
    const msg = types.toObject(msg_val).as(types.SchemeString);
    try std.testing.expect(std.mem.startsWith(u8, msg.data[0..msg.len], "custom port callback blocked"));
    // The armed defer ran: nothing left on the reactor.
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));

    // Discriminating control: the identical call with the counter clear
    // drives and returns normally.
    vm.current_exception = null;
    try fiber_mod.waitForFd(vm, pair[0], .read);
}

test "a stale timed_out does not degrade an fd wait into an abandonment" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // waitForFd clears me.timed_out before driving. Without that, an fd
    // wait inheriting a leftover deadline flag from an earlier timed wait
    // exits runSchedulerStep's loop immediately with done == false — which
    // waitForFd turns into the #1625 "port I/O abandoned" raise, on a wait
    // that was about to succeed. Mutation control: deleting `me.timed_out
    // = false` from waitForFd makes this test raise instead of return.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const me = ctx.sched.fibers.items[0].?;
    me.timed_out = true; // the stale flag an earlier timed wait would leave

    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "x"));
    try fiber_mod.waitForFd(vm, pair[0], .read);
    try std.testing.expect(!me.timed_out);
}

test "#1625 unwind leaves the fd unregistered and the port usable" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // The abandonment path's cleanup half, which the existing single #1625
    // test does not assert: the raise happens after waitForFd's defer, so
    // the reactor must hold no waiter for the fd afterwards — otherwise
    // register()'s staleness assertion would fire on the next wait.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    _ = try definePortGlobal(vm, "wp", pair[1], false, true);

    _ = try vm.eval("(import (kaappi fibers))");
    _ = try vm.eval(
        \\(define f (spawn (lambda ()
        \\  (guard (e (#t (list 'caught (error-object-message e))))
        \\    (read-char rp)
        \\    'not-reached))))
    );
    // FIFO: this join dispatches f first. Under guard's re-entrant frames f
    // cannot park, so it drives in place; that drive resolves THIS join,
    // and f's idle drive then unwinds rather than pinning it.
    const joined = try vm.eval("(fiber-join (spawn (lambda () 7)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(joined));

    const msg_val = try vm.eval("(cadr (fiber-join f))");
    const msg = types.toObject(msg_val).as(types.SchemeString);
    try std.testing.expect(std.mem.startsWith(u8, msg.data[0..msg.len], "port I/O abandoned"));

    const ctx = try fiber_mod.ensureScheduler(vm);
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));

    // The port survived: a fresh read on the same fd still works, which it
    // could not if a stale waiter were still listed.
    try std.testing.expectEqual(@as(isize, 1), th.fdWrite(pair[1], "q"));
    try std.testing.expectEqual(types.makeChar('q'), try vm.eval("(read-char rp)"));
}

test "two fibers parked on the same fd are both listed and both woken by close" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // waitForFd registers per-fiber, not per-fd, and wakeIoWaitersOnFd
    // iterates every fiber rather than the reactor's list — the two must
    // agree, or a second waiter is silently stranded.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pair = th.makeBidiFdPair();
    _ = try definePortGlobal(vm, "rp", pair[0], true, false);
    defer th.closeFd(pair[1]);

    _ = try vm.eval("(import (kaappi fibers))");
    // No `guard` inside, for the same reason as the test above: it would
    // send the reader down the drive branch and it would never park.
    _ = try vm.eval(
        \\(define f1 (spawn (lambda () (read-char rp))))
        \\(define f2 (spawn (lambda () (read-char rp))))
    );
    try settleSpawnedFibers(vm);

    const ctx = try fiber_mod.ensureScheduler(vm);
    const f1 = types.toObject(try vm.eval("f1")).as(fiber_mod.Fiber);
    const f2 = types.toObject(try vm.eval("f2")).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f1.status);
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, f2.status);
    try std.testing.expectEqual(@as(usize, 2), waiterCount(ctx.reactor, pair[0]));

    _ = try vm.eval("(close-port rp)");
    try std.testing.expect(f1.status != .io_waiting);
    try std.testing.expect(f2.status != .io_waiting);
    try std.testing.expectEqual(@as(?platform.fd_t, null), f1.io_fd);
    try std.testing.expectEqual(@as(?platform.fd_t, null), f2.io_fd);
    try std.testing.expectEqual(@as(usize, 0), waiterCount(ctx.reactor, pair[0]));

    // Both retries raise rather than hang — the second waiter is the one a
    // per-fd (rather than per-fiber) wake would have stranded.
    const r = try vm.eval(
        \\(list (guard (e (#t 'caught)) (fiber-join f1))
        \\      (guard (e (#t 'caught)) (fiber-join f2)))
    );
    const s = try printer.valueToString(std.testing.allocator, r, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(caught caught)", s);
}
