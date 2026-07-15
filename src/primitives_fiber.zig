const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
const shared_channel = @import("shared_channel.zig");
const srfi18 = @import("primitives_srfi18.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "spawn", .func = &spawnFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "yield", .func = &yieldFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "fiber-join", .func = &fiberJoinFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "fiber?", .func = &fiberPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    // KEP-0002 §6 (#1469): optional capacity, [timeout [timeout-val]] on
    // both send/receive, close!/closed?.
    .{ .name = "make-channel", .func = &makeChannelFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel-send", .func = &channelSendFn, .arity = .{ .variadic = 2 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel-receive", .func = &channelReceiveFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel?", .func = &channelPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel-close!", .func = &channelCloseFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel-closed?", .func = &channelClosedFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel-timeout-exception?", .func = &channelTimeoutPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
};

fn getScheduler() ?*fiber_mod.FiberScheduler {
    const vm = vm_mod.vm_instance orelse return null;
    return vm.scheduler;
}

fn spawnFn(args: []const Value) PrimitiveError!Value {
    const proc = args[0];
    if (!types.isProcedure(proc))
        return primitives.typeError("spawn", "procedure", proc);

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ctx = try fiber_mod.ensureScheduler(vm);

    const fiber = ctx.sched.spawnFiber(proc) catch return PrimitiveError.OutOfMemory;
    return types.makePointer(@ptrCast(&fiber.header));
}

fn yieldFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const sched = vm.scheduler orelse return types.VOID;
    // Yield is advisory: it may only arm the Yielded unwind when the signal
    // can reach a scheduler dispatch loop. Under a re-entrant native frame
    // (guard/with-exception-handler thunks, handler calls) the unwind is
    // intercepted by the native's generic error conversion and surfaces as a
    // contentless "error" — and the fiber could not be resumed across the
    // returned native call anyway (#1184). No-op instead.
    if (vm.native_reentry_depth > 0) return types.VOID;
    // Advisory, non-consuming, O(1): only arm the unwind if some other fiber
    // is actually runnable (else this yield would just no-op after a dispatch
    // round anyway). anyRunnable, unlike the old schedule() call, doesn't scan
    // every fiber or perturb round-robin order (#1477).
    if (!sched.anyRunnable()) return types.VOID;
    vm.yielded = true;
    return types.VOID;
}

fn fiberJoinFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("fiber-join", "fiber", args[0]);

    const target = types.toObject(args[0]).as(fiber_mod.Fiber);

    if (target.status == .completed) return target.result;
    if (target.status == .errored) return reraiseFiberError(target);

    // Capture before the recursive dispatch below: args is a slice into
    // vm.registers, which runSchedulerStep can reallocate out from under
    // it while running other fibers (ensureRegisterCapacity). Reading
    // args[0] after that point would be a use-after-free.
    const target_val = args[0];

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ctx = try fiber_mod.ensureScheduler(vm);
    const my_idx = ctx.sched.current_idx;
    const me = ctx.sched.fibers.items[my_idx].?;

    _ = try fiber_mod.runSchedulerStep(fiber_mod.TargetWait, .{ .target = target }, ctx.vm, ctx.sched, me);

    if (target.status == .completed) return target.result;
    if (target.status == .errored) return reraiseFiberError(target);
    return blockOrDeadlock(ctx.vm, me, my_idx, target_val, "fiber-join: deadlock — joined fiber can never complete (all fibers blocked)");
}

fn reraiseFiberError(fiber: *fiber_mod.Fiber) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.ExceptionRaised;
    if (fiber.current_exception) |exc| {
        vm.current_exception = exc;
        return PrimitiveError.ExceptionRaised;
    }
    vm.setErrorDetail("fiber error (no exception value)", .{});
    return PrimitiveError.InvalidArgument;
}

fn fiberPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isFiber(args[0])) types.TRUE else types.FALSE;
}

fn makeChannelFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 0) return gc.allocChannel() catch return PrimitiveError.OutOfMemory;

    if (!types.isFixnum(args[0])) return primitives.typeError("make-channel", "non-negative exact integer", args[0]);
    const fx = types.toFixnum(args[0]);
    if (fx < 0 or fx > std.math.maxInt(u32))
        return primitives.typeError("make-channel", "non-negative exact integer", args[0]);
    const capacity: u32 = @intCast(fx);
    return gc.allocChannelBounded(capacity) catch return PrimitiveError.OutOfMemory;
}

fn channelSendFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-send", "channel", args[0]);

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ch_obj = types.toObject(args[0]);
    // KEP-0002 §2: the only legal cross-thread handle is a locally owned
    // stub created by deepCopy. A foreign object -- reached through a
    // shared global, promoted or not -- is what silently corrupted memory
    // before this check existed (Motivation Path 2); now it's a diagnosis.
    if (ch_obj.owner != gc.id)
        return raiseFiberError("channel belongs to another thread; pass it through the thread thunk to share it");
    const ch = ch_obj.as(types.Channel);

    // KEP-0002 §6: the one backward-compat carve-out. Checked before any
    // dispatch (both representations, no lock): a *sent* eof-object would
    // be indistinguishable from channel-close!'s end-of-stream at the
    // receiver.
    if (args[1] == types.EOF)
        return raiseFiberError("channel-send: cannot send an eof-object on a channel; use channel-close! to end the stream");

    var deadline_ns: ?u64 = null;
    var has_timeout_val = false;
    var timeout_val: Value = types.VOID;
    if (args.len > 2) {
        deadline_ns = try srfi18.timeoutToDeadlineNs(args[2]);
        if (args.len > 3) {
            has_timeout_val = true;
            timeout_val = args[3];
        }
    }

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        return channelSendShared(sc, args[1], args[0], deadline_ns, has_timeout_val, timeout_val);
    }

    return channelSendLocal(ch, args[0], args[1], deadline_ns, has_timeout_val, timeout_val);
}

/// KEP-0002 §6: appends `payload` to the local (unpromoted) queue. Split out
/// of channelSendLocal so both the immediate fast path and the post-park
/// retry share one enqueue implementation.
fn enqueueChannel(gc: *memory.GC, ch: *types.Channel, ch_val: Value, payload: Value) PrimitiveError!void {
    const new_pair = gc.allocPair(payload, types.NIL) catch return PrimitiveError.OutOfMemory;
    const ch_obj = types.toObject(ch_val);

    if (ch.tail != types.NIL and types.isPair(ch.tail)) {
        const tail_obj = types.toObject(ch.tail);
        tail_obj.as(types.Pair).cdr = new_pair;
        gc.writeBarrier(tail_obj, new_pair);
    }
    ch.tail = new_pair;
    gc.writeBarrier(ch_obj, new_pair);
    if (ch.head == types.NIL) {
        ch.head = new_pair;
        gc.writeBarrier(ch_obj, new_pair);
    }
    ch.queue_len += 1;
    if (vm_mod.vm_instance) |vm| {
        if (vm.scheduler) |sched| sched.wakeChannelWaiters(ch_val);
    }
}

/// A fiber parked waiting for room on a *local* bounded channel (KEP-0002
/// §6). Mirrors ChannelWait's shape exactly; isDone is satisfied by either
/// a freed slot or the channel becoming closed (channel-close! wakes both
/// waiter roles via the same wakeChannelWaiters call).
const ChannelSendWait = struct {
    ch: *types.Channel,
    pub fn isDone(self: ChannelSendWait) bool {
        return self.ch.closed or self.ch.capacity == null or self.ch.queue_len < self.ch.capacity.?;
    }
};

/// KEP-0002 §6 send, local (unpromoted) representation. No reservation
/// concept is needed here (unlike the shared path): cooperative scheduling
/// means nothing can run between the admission check and the enqueue, so
/// the check-then-act sequence is already atomic with respect to every
/// other fiber.
fn channelSendLocal(ch: *types.Channel, ch_val: Value, payload: Value, deadline_ns: ?u64, has_timeout_val: bool, timeout_val: Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Admission order matches §4 step 2 then step 3: closed is checked
    // before capacity, unconditionally, no scheduler touch needed.
    if (ch.closed) return raiseFiberError("channel-send: send on closed channel");

    const cap = ch.capacity orelse {
        try enqueueChannel(gc, ch, ch_val, payload);
        return types.VOID;
    };
    if (ch.queue_len < cap) {
        try enqueueChannel(gc, ch, ch_val, payload);
        return types.VOID;
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    // See channelReceiveFn's matching check: a timeout resolves this wait
    // via the reactor timer alone, so "no fibers exist" is only a genuine
    // deadlock when there is also no deadline to bound the wait.
    if (vm.scheduler == null and deadline_ns == null) {
        return raiseFiberError("channel-send: deadlock — channel is full and no fibers are running");
    }

    const ctx = try fiber_mod.ensureScheduler(vm);
    const my_idx = ctx.sched.current_idx;
    const me = ctx.sched.fibers.items[my_idx].?;

    // A local channel wait always resolves within this one call:
    // runSchedulerStep drives siblings and, if nothing else is runnable,
    // blocks in parkOnReactor -- which never mis-detects deadlock while
    // `me`'s own timer is pending (reactor.isEmpty() is false whenever the
    // timer heap is non-empty). No redispatch/yield-retry guard is needed
    // here the way channelSendShared needs one: contrast that function's
    // doc comment.
    me.timed_out = false;
    if (deadline_ns) |d| {
        // .waiting is required for the timer to actually resolve the wait
        // -- see channelReceiveFn's matching comment for why this is safe.
        me.status = .waiting;
        me.waiting_on = ch_val;
        vm.gc.writeBarrier(&me.header, ch_val);
        ctx.sched.enrollWaiter(me); // #1530: O(1) wake on a freed slot / close
        me.deadline_ns = d;
        try ctx.reactor.addTimer(d, me);
    }
    _ = try fiber_mod.runSchedulerStep(ChannelSendWait, .{ .ch = ch }, ctx.vm, ctx.sched, me);
    if (deadline_ns != null) {
        ctx.reactor.removeTimer(me);
        me.deadline_ns = null;
    }
    if (me.timed_out) {
        me.timed_out = false;
        return if (has_timeout_val) timeout_val else srfi18.raiseError(.channel_timeout, "channel-send: timed out", types.VOID);
    }

    if (ch.closed) return raiseFiberError("channel-send: send on closed channel");
    if (ch.queue_len < cap) {
        try enqueueChannel(gc, ch, ch_val, payload);
        return types.VOID;
    }
    return blockOrDeadlock(ctx.vm, me, my_idx, ch_val, "channel-send: deadlock — channel is full and no fibers can receive");
}

const ChannelWait = struct {
    ch: *types.Channel,
    pub fn isDone(self: ChannelWait) bool {
        return self.ch.head != types.NIL;
    }
};

const SharedChannelWait = struct {
    me: *fiber_mod.Fiber,
    pub fn isDone(self: SharedChannelWait) bool {
        return self.me.status != .waiting;
    }
};

/// Drives OTHER local fibers without ever touching `me`'s own status --
/// `me` stays .running for the whole call, so schedule()'s round-robin can
/// never independently re-pick it while its own native call (this one) is
/// still live on the Zig stack. Isolating this into its own Ctx type keeps
/// that invariant visually obvious at every call site: nothing here sets
/// `me.status`, unlike SharedChannelWait/ChannelWait's actual park.
const SharedChannelPoll = struct {
    sc: *shared_channel.SharedChannel,
    pub fn isDone(self: SharedChannelPoll) bool {
        return self.sc.peekReady();
    }
};

/// Send-side counterpart to SharedChannelPoll, used by channelSendShared's
/// local-sibling drive: "ready" means a slot opened up, the channel is
/// unbounded, or it became closed (a closed channel's send() call raises
/// immediately rather than parking, which is exactly what driving toward
/// here is meant to unblock).
const SharedChannelSendPoll = struct {
    sc: *shared_channel.SharedChannel,
    pub fn isDone(self: SharedChannelSendPoll) bool {
        return self.sc.peekSendReady();
    }
};

/// KEP-0002 §5's deadlock-heuristic disjunct: block (park, waiting for a
/// remote send/receive) rather than raise a local deadlock whenever another
/// thread could plausibly still act on this channel -- either it still
/// holds another counted reference (an envelope in flight counts too, via
/// its own stub, per §1), or some other OS thread is alive at all. Reuses
/// primitives_srfi18.zig's existing crossThreadWaitPossible rather than
/// duplicating its live-thread-count logic.
///
/// Accepted liveness gap, KEP-0002 §5: this is checked once, right before
/// parking -- not re-evaluated while parked. If the peer that made this
/// return `true` (the only other stub holder, or the only other live
/// thread) exits afterward without ever sending, the parked receiver hangs
/// forever: a stub's release doesn't ring anything, and the parked fiber
/// staying enrolled in the shared-waiter registry keeps hasRunnableFibers()
/// true, so the deadlock detector never fires either. This is the same
/// Go-style "send on a channel nobody will ever receive from" hang as an
/// unbuffered channel with no reader; §5 accepts it deliberately, and §6's
/// `(channel-receive ch [timeout [timeout-val]])` / `(channel-send ch v
/// [timeout [timeout-val]])` (KEP-0002 Phase 4) are the intended escape
/// hatch.
fn sharedWakeupPossible(sc: *shared_channel.SharedChannel) bool {
    return sc.refCount() > 1 or srfi18.crossThreadWaitPossible();
}

/// KEP-0002 §4/§6 send on the shared representation. Structural mirror of
/// channelReceiveShared (see that function's extensive doc comment for why
/// the is_dispatched/main-fiber split is asymmetric and load-bearing) --
/// this is the send-side instantiation of the exact same shape, with
/// SharedChannelSendPoll/peekSendReady in place of
/// SharedChannelPoll/peekReady.
///
/// Timeout handling mirrors thread-sleep!'s documented `me.deadline_ns ==
/// null` fresh-vs-redispatch discriminator (primitives_srfi18.zig): a
/// dispatched fiber's parked wait resolves via yield_retry, which
/// re-executes this entire function from Scheme bytecode on wake, so a
/// relative timeout argument re-parsed on every redispatch would silently
/// extend itself forever. `me.timed_out` is therefore checked once at
/// entry (a fired timer means this call is a post-timeout redispatch, and
/// no other work should run), and `me.deadline_ns`/the reactor timer are
/// armed only the first time this wait actually parks (guarded by
/// `me.deadline_ns == null`), never re-armed on a later loop iteration or
/// redispatch of the same call.
fn channelSendShared(sc: *shared_channel.SharedChannel, payload: Value, ch_val: Value, deadline_ns: ?u64, has_timeout_val: bool, timeout_val: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ctx = try fiber_mod.ensureScheduler(vm);
    const my_idx = ctx.sched.current_idx;
    const me = ctx.sched.fibers.items[my_idx].?;
    const notifier = ctx.reactor.notifyHandle();
    const is_dispatched = my_idx != 0 and vm.dispatched_from_scheduler;

    if (me.deadline_ns != null and me.timed_out) {
        me.timed_out = false;
        me.deadline_ns = null;
        return if (has_timeout_val) timeout_val else srfi18.raiseError(.channel_timeout, "channel-send: timed out", types.VOID);
    }

    while (true) {
        const outcome = shared_channel.send(sc, payload, notifier) catch |err|
            return translateSharedChannelError(err, "channel-send");
        switch (outcome) {
            .sent => {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return types.VOID;
            },
            .closed => {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return raiseFiberError("channel-send: send on closed channel");
            },
            .would_park => {},
        }

        // A prior loop iteration may have parked, armed a timer, and then
        // woken *spuriously* -- sweepSharedWaiters (fiber.zig) flips a
        // .waiting fiber to .suspended unconditionally on any notify, with
        // no notion of "was this really my event", and does not touch
        // deadline_ns or cancel the reactor timer. Left armed, that timer
        // is still live while the drive below runs with `me` .running --
        // and wakeReadyFiber only ever sets `timed_out` for a .waiting (or
        // io_waiting) fiber, so a fiber pop while `me` is .running is
        // silently dropped (schedule()'s per-tick popExpiredTimers, or
        // parkOnReactor's own poll, both call wakeReadyFiber the same way),
        // permanently losing the timeout for the rest of this wait.
        //
        // Detach it from the *reactor's* heap only -- `me.deadline_ns`
        // itself is deliberately left set, as the sole authoritative record
        // of the original absolute deadline. The park step below always
        // re-adds a timer if it doesn't resolve things, preferring this
        // preserved value over a freshly re-parsed `deadline_ns` argument
        // (`me.deadline_ns orelse deadline_ns`) -- clearing the field here
        // instead would make every re-arm fall through to `deadline_ns`,
        // which is recomputed as "now + relative seconds" on every fresh
        // native call (see channelSendFn), silently extending the timeout
        // on every spurious wake instead of honoring the original one.
        if (me.deadline_ns != null) ctx.reactor.removeTimer(me);

        // Drive local siblings once. See SharedChannelPoll's doc comment
        // (channelReceiveShared) for why `me` must stay .running throughout.
        me.timed_out = false;
        _ = try fiber_mod.runSchedulerStep(SharedChannelSendPoll, .{ .sc = sc }, ctx.vm, ctx.sched, me);

        // Re-derive readiness THROUGH send(), never a bare peekSendReady():
        // symmetric to channelReceiveShared's re-receive (kaappi#1489). The
        // drive can consume this fiber's one-shot send_waiters registration -- a
        // sibling receive frees a slot, clearing+ringing it, and a sibling send
        // refills it -- leaving the channel full AND this fiber unregistered, so
        // peekSendReady() would fall through to a park no later remote receive
        // can ring. Re-calling send() re-registers under the channel lock when
        // the channel is still full (the full path enqueues nothing, so there is
        // no double-send), and enqueues + returns .sent if the drive opened a
        // slot.
        const redo = shared_channel.send(sc, payload, notifier) catch |err|
            return translateSharedChannelError(err, "channel-send");
        switch (redo) {
            .sent => {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return types.VOID;
            },
            .closed => {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return raiseFiberError("channel-send: send on closed channel");
            },
            .would_park => {},
        }

        if (is_dispatched) {
            me.status = .waiting;
            me.waiting_on = ch_val;
            vm.gc.writeBarrier(&me.header, ch_val);
            if (me.deadline_ns orelse deadline_ns) |d| {
                me.deadline_ns = d;
                try ctx.reactor.addTimer(d, me);
            }
            ctx.sched.enrollSharedWaiter(me) catch |err| {
                me.status = .running;
                me.waiting_on = types.VOID;
                return err;
            };
            vm.yield_retry = true;
            return PrimitiveError.Yielded;
        }

        if (!sharedWakeupPossible(sc) and deadline_ns == null)
            return raiseFiberError("channel-send: deadlock — channel is full and no other thread can receive");

        me.status = .waiting;
        me.waiting_on = ch_val;
        vm.gc.writeBarrier(&me.header, ch_val);
        if (me.deadline_ns orelse deadline_ns) |d| {
            me.deadline_ns = d;
            try ctx.reactor.addTimer(d, me);
        }
        ctx.sched.enrollSharedWaiter(me) catch |err| {
            me.status = .running;
            me.waiting_on = types.VOID;
            return err;
        };
        _ = fiber_mod.runSchedulerStep(SharedChannelWait, .{ .me = me }, ctx.vm, ctx.sched, me) catch |err| {
            ctx.sched.removeSharedWaiter(me);
            me.status = .running;
            me.waiting_on = types.VOID;
            return err;
        };
        ctx.sched.removeSharedWaiter(me);

        if (me.timed_out) {
            me.timed_out = false;
            me.deadline_ns = null;
            return if (has_timeout_val) timeout_val else srfi18.raiseError(.channel_timeout, "channel-send: timed out", types.VOID);
        }
        // Loop back to 1: re-registers if still full, sends if a slot
        // opened (or the channel closed) while parked.
    }
}

/// KEP-0002 §4/§5 receive on the shared representation, replacing Phase 1's
/// `@panic` on `.would_park` -- a real, already-reachable SIGABRT before
/// this fix (a channel captured by a thread-start! thunk promotes in place
/// on both sides; either side calling channel-receive on the empty promoted
/// channel before the other sends crashed the process).
///
/// Per loop iteration:
///  1. Call shared_channel.receive() -- the notifier is registered
///     unconditionally (not gated on sharedWakeupPossible), because a purely
///     LOCAL sibling fiber's channel-send on this channel also rings via the
///     same recv_waiters/notifier path (self-ring): a channel can be
///     promoted (e.g. transiently, by a thread that captured it and exited)
///     while every actual sender/receiver stays on this thread the whole
///     time, and that must keep working exactly like it did before
///     promotion.
///  2. If empty, drive OTHER local fibers once (SharedChannelPoll) -- `me`
///     stays .running throughout, mirroring channelReceiveFn's local-channel
///     path (ChannelWait). Loop back to 1 if driving made the channel ready.
///  3. Otherwise park. The two branches are NOT symmetric, and the asymmetry
///     is load-bearing, not an oversight:
///       - A fiber dispatched directly by a scheduler loop (my_idx != 0 and
///         vm.dispatched_from_scheduler) ALWAYS parks via the flat
///         yield_retry unwind (KEP-0002 §4 receive step 8: ".waiting on the
///         stub, yield_retry rewind"), unconditionally -- exactly like
///         blockOrDeadlock's existing behavior for every non-main fiber.
///         Whether this is a genuine, permanent deadlock is not this
///         fiber's call to make (the existing local-channel path doesn't
///         make that call either): that's detected wherever something else
///         -- typically the main fiber, via fiber-join or another
///         blockOrDeadlock call -- eventually finds nothing progressing.
///         Gating this branch on sharedWakeupPossible() was an earlier,
///         confirmed-buggy version of this function: it raised a false
///         deadlock the instant a channel was ever transiently promoted
///         and then the "remote" side exited, even though a purely local
///         sibling fiber was one form away from sending (verified via a
///         concrete repro). This branch must also never nest another
///         drive after setting `.waiting` -- see SharedChannelPoll's and
///         runSchedulerStep's own doc comments: doing so would make `me`
///         visible to schedule()'s round-robin while `me`'s own call is
///         still live on the Zig stack, letting an unrelated fiber's own
///         nested runSchedulerStep dispatch `me`'s mid-call snapshot and
///         resume bytecode past the in-flight receive() call with the
///         destination register never written (confirmed via a second,
///         separate repro: two spawned fibers each parked on their own
///         promoted channel, the second one woken "received" the stale
///         callee register instead of its real value). yield_retry instead
///         unwinds this whole native call via error.Yielded before `me`
///         ever becomes independently dispatchable, and a later redispatch
///         re-executes this entire function from the top (re-registering
///         via step 1's receive() call).
///       - The main fiber (or a fiber blocked under re-entrant native
///         frames that cannot be safely rewound) CANNOT yield_retry, so it
///         drives in place instead (waitForFd's precedent) via a genuine
///         park + SharedChannelWait, then loops back to 1. Here
///         sharedWakeupPossible() is load-bearing: self-enrolling in
///         shared_waiters makes hasRunnableFibers() (and therefore
///         parkOnReactor's own "nothing can ever happen" detection) always
///         see this fiber's own entry, so parkOnReactor can never
///         independently conclude "genuine deadlock" the way it does for
///         purely local waits -- something has to decide "no local or
///         remote path could ever help" before parking, or a truly
///         deadlocked main fiber would block in reactor.poll() forever
///         instead of raising a clean error.
///
/// Timeout handling (KEP-0002 Phase 4) follows channelSendShared's exact
/// discriminator -- see that function's doc comment for why a dispatched
/// fiber's redispatch cannot simply re-parse `deadline_ns` from Scheme
/// arguments.
fn channelReceiveShared(sc: *shared_channel.SharedChannel, gc: *memory.GC, ch_val: Value, deadline_ns: ?u64, has_timeout_val: bool, timeout_val: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ctx = try fiber_mod.ensureScheduler(vm);
    const my_idx = ctx.sched.current_idx;
    const me = ctx.sched.fibers.items[my_idx].?;
    const notifier = ctx.reactor.notifyHandle();
    const is_dispatched = my_idx != 0 and vm.dispatched_from_scheduler;

    if (me.deadline_ns != null and me.timed_out) {
        me.timed_out = false;
        me.deadline_ns = null;
        return if (has_timeout_val) timeout_val else srfi18.raiseError(.channel_timeout, "channel-receive: timed out", types.VOID);
    }

    while (true) {
        const outcome = shared_channel.receive(sc, gc, notifier) catch |err|
            return translateSharedChannelError(err, "channel-receive");
        switch (outcome) {
            .value => |v| {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return v;
            },
            .eof => {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return types.EOF;
            },
            .would_park => {},
        }

        // A prior loop iteration may have parked, armed a timer, and then
        // woken *spuriously* -- see channelSendShared's matching comment for
        // the full reasoning. Detach any still-live timer from the
        // *reactor's* heap only (never `me.deadline_ns` itself, which stays
        // the authoritative record of the original absolute deadline) so a
        // pop while this drive runs with `me` .running can't be silently
        // dropped by wakeReadyFiber -- and the park step below can still
        // re-arm using the preserved value instead of a freshly re-parsed
        // (and wrongly extended) `deadline_ns` argument.
        if (me.deadline_ns != null) ctx.reactor.removeTimer(me);

        // Drive local siblings once. `me` stays .running -- see
        // SharedChannelPoll's doc comment for why that's load-bearing.
        // Reset first: runSchedulerStep's generic loop bails whenever
        // `me.timed_out` is true, regardless of Ctx, so a stale flag left
        // by an unrelated earlier timed wait would silently skip this
        // drive entirely and let the park decision below run with the
        // world still active -- quiescence-before-park is what makes that
        // decision safe.
        me.timed_out = false;
        _ = try fiber_mod.runSchedulerStep(SharedChannelPoll, .{ .sc = sc }, ctx.vm, ctx.sched, me);

        // Re-derive readiness THROUGH receive(), never a bare peekReady(): the
        // drive above can consume this fiber's one-shot recv_waiters
        // registration -- a local sibling's channel-send clears+rings it and a
        // sibling channel-receive drains the value -- leaving the channel empty
        // AND this fiber unregistered. peekReady() sees "empty" and falls
        // through to a park no later remote send can ever ring (kaappi#1489):
        // the send finds recv_waiters empty and rings nothing, while the
        // shared-waiter registry entry keeps hasRunnableFibers() true so the
        // deadlock detector stays suppressed, and the fiber hangs forever. A
        // second receive() re-registers the notifier under the channel lock
        // whenever it returns .would_park, so the park below is always armed;
        // if the drive instead produced a value (or EOF), it is returned here
        // and the fiber never parks.
        const redo = shared_channel.receive(sc, gc, notifier) catch |err|
            return translateSharedChannelError(err, "channel-receive");
        switch (redo) {
            .value => |v| {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return v;
            },
            .eof => {
                if (me.deadline_ns != null) {
                    ctx.reactor.removeTimer(me);
                    me.deadline_ns = null;
                }
                return types.EOF;
            },
            .would_park => {},
        }

        if (is_dispatched) {
            me.status = .waiting;
            me.waiting_on = ch_val;
            vm.gc.writeBarrier(&me.header, ch_val);
            if (me.deadline_ns orelse deadline_ns) |d| {
                me.deadline_ns = d;
                try ctx.reactor.addTimer(d, me);
            }
            ctx.sched.enrollSharedWaiter(me) catch |err| {
                me.status = .running;
                me.waiting_on = types.VOID;
                return err;
            };
            vm.yield_retry = true;
            return PrimitiveError.Yielded;
        }

        if (!sharedWakeupPossible(sc) and deadline_ns == null)
            return raiseFiberError("channel-receive: deadlock — channel is empty and no other thread can send");

        me.status = .waiting;
        me.waiting_on = ch_val;
        vm.gc.writeBarrier(&me.header, ch_val);
        // Already reset above, before the SharedChannelPoll drive -- nothing
        // between there and here can set it true again (`me` stays .running
        // for that whole drive, and wakeReadyFiber only flips `.waiting`
        // fibers).
        if (me.deadline_ns orelse deadline_ns) |d| {
            me.deadline_ns = d;
            try ctx.reactor.addTimer(d, me);
        }
        ctx.sched.enrollSharedWaiter(me) catch |err| {
            me.status = .running;
            me.waiting_on = types.VOID;
            return err;
        };
        _ = fiber_mod.runSchedulerStep(SharedChannelWait, .{ .me = me }, ctx.vm, ctx.sched, me) catch |err| {
            ctx.sched.removeSharedWaiter(me);
            me.status = .running;
            me.waiting_on = types.VOID;
            return err;
        };
        ctx.sched.removeSharedWaiter(me);

        if (me.timed_out) {
            me.timed_out = false;
            me.deadline_ns = null;
            return if (has_timeout_val) timeout_val else srfi18.raiseError(.channel_timeout, "channel-receive: timed out", types.VOID);
        }
        // Loop back to 1: re-registers if still empty, picks up a value if
        // one arrived while parked.
    }
}

fn channelReceiveFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-receive", "channel", args[0]);

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ch_obj = types.toObject(args[0]);
    if (ch_obj.owner != gc.id)
        return raiseFiberError("channel belongs to another thread; pass it through the thread thunk to share it");
    const ch = ch_obj.as(types.Channel);

    var deadline_ns: ?u64 = null;
    var has_timeout_val = false;
    var timeout_val: Value = types.VOID;
    if (args.len > 1) {
        deadline_ns = try srfi18.timeoutToDeadlineNs(args[1]);
        if (args.len > 2) {
            has_timeout_val = true;
            timeout_val = args[2];
        }
    }

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        return channelReceiveShared(sc, gc, args[0], deadline_ns, has_timeout_val, timeout_val);
    }

    if (ch.head != types.NIL and types.isPair(ch.head)) {
        return dequeueChannel(ch, args[0]);
    }

    // Closed and drained is permanently terminal on the local
    // representation (no more sends can land once closed): short-circuit
    // before ever touching the scheduler.
    if (ch.closed) return types.EOF;

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    // No timeout means a timer can never resolve this wait, so "no fibers
    // exist" really is unrecoverable; with a timeout, ensureScheduler below
    // lazily creates a scheduler+reactor and the wait resolves via the
    // timer alone, with or without any other fiber ever existing.
    if (vm.scheduler == null and deadline_ns == null) {
        return raiseFiberError("channel-receive: deadlock — channel is empty and no fibers are running");
    }

    // Capture before the recursive dispatch below: args is a slice into
    // vm.registers, which runSchedulerStep can reallocate out from under
    // it while running other fibers (ensureRegisterCapacity). Reading
    // args[0] after that point would be a use-after-free.
    const ch_val = args[0];

    const ctx = try fiber_mod.ensureScheduler(vm);
    const my_idx = ctx.sched.current_idx;
    const me = ctx.sched.fibers.items[my_idx].?;

    // A local channel wait always resolves within this one call -- see
    // channelSendLocal's doc comment for why no redispatch guard is needed.
    me.timed_out = false;
    if (deadline_ns) |d| {
        // .waiting (not .running) is required here: wakeReadyFiber only
        // flips timed_out for .waiting/.io_waiting fibers, so without this
        // the timer would pop silently and the wait would fall through to
        // blockOrDeadlock instead of timing out. schedule()'s round-robin
        // still never re-picks `me` (it only picks .created/.suspended),
        // and runSchedulerStep's epilogue unconditionally restores
        // me.status = .running before returning, so this is safe exactly
        // like every other timed wait in primitives_srfi18.zig (MutexWait,
        // CondVarWait, thread-join!'s fiber path) that sets .waiting
        // whether or not a deadline was actually given.
        me.status = .waiting;
        me.waiting_on = ch_val;
        vm.gc.writeBarrier(&me.header, ch_val);
        ctx.sched.enrollWaiter(me); // #1530: O(1) wake on a channel send / close
        me.deadline_ns = d;
        try ctx.reactor.addTimer(d, me);
    }
    _ = try fiber_mod.runSchedulerStep(ChannelWait, .{ .ch = ch }, ctx.vm, ctx.sched, me);
    if (deadline_ns != null) {
        ctx.reactor.removeTimer(me);
        me.deadline_ns = null;
    }
    if (me.timed_out) {
        me.timed_out = false;
        return if (has_timeout_val) timeout_val else srfi18.raiseError(.channel_timeout, "channel-receive: timed out", types.VOID);
    }

    if (ch.head != types.NIL) return dequeueChannel(ch, ch_val);
    if (ch.closed) return types.EOF;
    return blockOrDeadlock(ctx.vm, me, my_idx, ch_val, "channel-receive: deadlock — channel is empty and all fibers are blocked");
}

/// Pops the head of a local (unpromoted) channel's queue. `ch.queue_len`
/// tracking and the capacity-freed wake are guarded on `ch.capacity !=
/// null` so the unbounded hot path (the common case) pays nothing beyond
/// the existing decrement -- no sender can ever be parked waiting for space
/// on an unbounded channel.
fn dequeueChannel(ch: *types.Channel, ch_val: Value) Value {
    const pair = types.toObject(ch.head).as(types.Pair);
    const val = pair.car;
    ch.head = pair.cdr;
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(ch_val), pair.cdr);
    if (ch.head == types.NIL) ch.tail = types.NIL;
    ch.queue_len -= 1;
    if (ch.capacity != null) {
        if (vm_mod.vm_instance) |vm| {
            if (vm.scheduler) |sched| sched.wakeChannelWaiters(ch_val);
        }
    }
    return val;
}

/// The scheduler ran out of runnable fibers while this fiber's blocking
/// condition is still unmet. A spawned fiber dispatched directly by a
/// scheduler loop parks itself: status .waiting on the channel/fiber, and
/// yield_retry makes the dispatch loop rewind ip so the blocking primitive
/// re-executes when a channel-send (or fiber completion) wakes it. The main
/// fiber — or a fiber blocked under re-entrant native frames (map/for-each
/// callbacks, eval), which cannot be safely rewound — raises a deadlock
/// error instead of returning an unspecified value.
fn blockOrDeadlock(vm: *vm_mod.VM, me: *fiber_mod.Fiber, my_idx: usize, wait_on: Value, deadlock_msg: []const u8) PrimitiveError!Value {
    if (my_idx != 0 and vm.dispatched_from_scheduler) {
        me.status = .waiting;
        me.waiting_on = wait_on;
        vm.gc.writeBarrier(&me.header, wait_on);
        // Index this park so fiber completion (wakeWaiters) or a channel
        // send/close (wakeChannelWaiters) finds it in O(1) (#1530).
        if (vm.scheduler) |sched| sched.enrollWaiter(me);
        vm.yield_retry = true;
        return PrimitiveError.Yielded;
    }
    return raiseFiberError(deadlock_msg);
}

/// Raises a generic ErrorObject carrying `msg`. Named for this file's scope
/// (fiber/channel primitives), not any one caller: deadlocks, the
/// foreign-owner check (KEP-0002 §2), and a shared-path uncopyable payload
/// all just need a message wrapped into a catchable exception -- the
/// function name never reaches the user, only `msg` does.
fn raiseFiberError(msg: []const u8) PrimitiveError {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const message = gc.allocString(msg) catch return PrimitiveError.OutOfMemory;
    var msg_root = message;
    gc.pushRoot(&msg_root);
    const err_val = gc.allocErrorObject(msg_root, types.NIL) catch {
        gc.popRoot();
        return PrimitiveError.OutOfMemory;
    };
    gc.popRoot();
    vm.current_exception = err_val;
    return PrimitiveError.ExceptionRaised;
}

/// shared_channel.send/.receive propagate Envelope.create's deepCopy error
/// verbatim. Mirrors how primitives_srfi18.zig's thread-start!/thread-join!
/// special-case UncopyableType into a descriptive message and otherwise
/// fall back to OutOfMemory.
fn translateSharedChannelError(err: anyerror, proc: []const u8) PrimitiveError {
    if (err == error.UncopyableType) {
        var buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s}: value contains an uncopyable type (port, continuation, etc.)", .{proc}) catch
            return PrimitiveError.OutOfMemory;
        return raiseFiberError(msg);
    }
    return PrimitiveError.OutOfMemory;
}

/// A total predicate over arbitrary values, like every other `foo?` in the
/// codebase -- deliberately NOT given the foreign-owner check (unlike
/// channel-send/channel-receive), so a program defensively guarding with
/// `(channel? x)` gets `#f`-and-skip instead of a raise.
fn channelPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isChannel(args[0])) types.TRUE else types.FALSE;
}

/// KEP-0002 §6 close!. Unlike channel?, this dereferences the channel (its
/// `shared` pointer or local fields), so it needs the same foreign-owner
/// check as send/receive, not channel?'s total-predicate convention.
fn channelCloseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-close!", "channel", args[0]);

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ch_obj = types.toObject(args[0]);
    if (ch_obj.owner != gc.id)
        return raiseFiberError("channel belongs to another thread; pass it through the thread thunk to share it");
    const ch = ch_obj.as(types.Channel);

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        // Local waiters were already migrated into the notifier protocol at
        // promotion time (§2 step 4) -- no separate local wake is needed
        // here, unlike the unpromoted branch below.
        shared_channel.close(sc);
        return types.VOID;
    }

    if (ch.closed) return types.VOID; // idempotent, matches §6 step 2
    ch.closed = true;
    if (vm_mod.vm_instance) |vm| {
        if (vm.scheduler) |sched| sched.wakeChannelWaiters(args[0]);
    }
    return types.VOID;
}

fn channelClosedFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-closed?", "channel", args[0]);

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ch_obj = types.toObject(args[0]);
    if (ch_obj.owner != gc.id)
        return raiseFiberError("channel belongs to another thread; pass it through the thread thunk to share it");
    const ch = ch_obj.as(types.Channel);

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        return if (sc.isClosed()) types.TRUE else types.FALSE;
    }
    return if (ch.closed) types.TRUE else types.FALSE;
}

fn channelTimeoutPredFn(args: []const Value) PrimitiveError!Value {
    return if (srfi18.isErrorOfType(args[0], .channel_timeout)) types.TRUE else types.FALSE;
}
