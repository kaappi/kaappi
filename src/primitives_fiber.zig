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
    .{ .name = "make-channel", .func = &makeChannelFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel-send", .func = &channelSendFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel-receive", .func = &channelReceiveFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "channel?", .func = &channelPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
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
    if (sched.schedule() == null) return types.VOID;
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

fn makeChannelFn(_: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocChannel() catch return PrimitiveError.OutOfMemory;
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

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        const outcome = shared_channel.send(sc, args[1], null) catch |err| {
            return translateSharedChannelError(err, "channel-send");
        };
        return switch (outcome) {
            .sent => types.VOID,
            // Channels are still always unbounded and open -- no
            // Scheme-level API sets capacity or closed yet (KEP-0002
            // Phase 4) -- so these branches remain unreachable through
            // make-channel's output even after Phase 3 (#1468) wires up
            // channel-receive's own .would_park branch below. @panic (not
            // `unreachable`, which is UB under ReleaseFast) so a Phase 4
            // gap that forgets to wire this switch fails loudly in every
            // build mode instead of silently corrupting execution.
            .would_park, .closed => @panic("channel-send: reached a shared-channel branch Phase 4 doesn't wire up yet (capacity/close)"),
        };
    }

    const new_pair = gc.allocPair(args[1], types.NIL) catch return PrimitiveError.OutOfMemory;

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
    if (vm_mod.vm_instance) |vm| {
        if (vm.scheduler) |sched| sched.wakeChannelWaiters(args[0]);
    }
    return types.VOID;
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

/// KEP-0002 §5's deadlock-heuristic disjunct: block (park, waiting for a
/// remote send/receive) rather than raise a local deadlock whenever another
/// thread could plausibly still act on this channel -- either it still
/// holds another counted reference (an envelope in flight counts too, via
/// its own stub, per §1), or some other OS thread is alive at all. Reuses
/// primitives_srfi18.zig's existing crossThreadWaitPossible rather than
/// duplicating its live-thread-count logic.
fn sharedWakeupPossible(sc: *shared_channel.SharedChannel) bool {
    return sc.refCount() > 1 or srfi18.crossThreadWaitPossible();
}

/// KEP-0002 §4/§5 send/receive on the shared representation, replacing
/// Phase 1's `@panic` on `.would_park` -- a real, already-reachable SIGABRT
/// before this fix (a channel captured by a thread-start! thunk promotes in
/// place on both sides; either side calling channel-receive on the empty
/// promoted channel before the other sends crashed the process).
///
/// Always calls shared_channel.receive() FIRST each loop iteration -- that's
/// what performs the actual sc.recv_waiters registration, as a side effect
/// of returning `.would_park` -- and only *then* decides to park. Parking
/// before registering would leave nothing to ever ring the fiber awake: a
/// permanent hang inside parkOnReactor's blocking poll, strictly worse than
/// today's clean deadlock error. This ordering also directly implements the
/// required "a rung receiver that loses the pop race re-parks, re-registers"
/// regression (§5, model finding 1): losing the race just means another
/// `.would_park` on the next loop iteration, which re-registers via the same
/// receive() call.
///
/// Deliberately does not reuse blockOrDeadlock's yield_retry trick: that
/// helper is sound for a *local* channel because a later local channel-send
/// can still find and flip the fiber via wakeChannelWaiters even after
/// runSchedulerStep reports "not done". For a *promoted* channel nothing
/// ever calls wakeChannelWaiters again -- a yield_retry-parked fiber not
/// enrolled in the shared-waiter registry would never wake. So this always
/// raises immediately when sharedWakeupPossible() is false, uniformly for
/// the main fiber and any spawned fiber (runSchedulerStep is already called
/// unconditionally regardless of dispatched_from_scheduler), which is what
/// satisfies §5's "the main-fiber case follows the same rule" without any
/// special-casing: the main fiber genuinely blocks in parkOnReactor's
/// reactor.poll() exactly like any other fiber.
fn channelReceiveShared(sc: *shared_channel.SharedChannel, gc: *memory.GC, ch_val: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ctx = try fiber_mod.ensureScheduler(vm);
    const me = ctx.sched.fibers.items[ctx.sched.current_idx].?;
    const notifier = ctx.reactor.notifyHandle();

    while (true) {
        const wakeup_possible = sharedWakeupPossible(sc);
        // A null notifier when no wakeup is possible: registering would be
        // pointless (nothing will ever ring it) and would leave a dangling
        // entry for nothing -- matches send()/receive()'s existing
        // null-is-safe convention from Phase 1.
        const outcome = shared_channel.receive(sc, gc, if (wakeup_possible) notifier else null) catch |err|
            return translateSharedChannelError(err, "channel-receive");
        switch (outcome) {
            .value => |v| return v,
            // channel-close! is Phase 4 -- sc.closed is always false, so
            // receive's reserved==0-and-closed eof branch is unreachable.
            .eof => @panic("channel-receive: .eof unreachable before channel-close! (Phase 4)"),
            .would_park => {},
        }
        if (!wakeup_possible)
            return raiseFiberError("channel-receive: deadlock — channel is empty and no other thread can send");

        me.status = .waiting;
        me.waiting_on = ch_val;
        vm.gc.writeBarrier(&me.header, ch_val);
        me.timed_out = false; // defensive: stale flag from an unrelated earlier timed wait
        try ctx.sched.enrollSharedWaiter(me);
        _ = try fiber_mod.runSchedulerStep(SharedChannelWait, .{ .me = me }, ctx.vm, ctx.sched, me);
        ctx.sched.removeSharedWaiter(me);
        // Loop back: re-derive wakeup_possible and re-call receive(), which
        // both re-registers if still empty and picks up a value if one
        // arrived while parked.
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

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        return channelReceiveShared(sc, gc, args[0]);
    }

    if (ch.head != types.NIL and types.isPair(ch.head)) {
        return dequeueChannel(ch, args[0]);
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    if (vm.scheduler == null) {
        // No fibers exist, so nothing can ever send: blocking would hang.
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

    _ = try fiber_mod.runSchedulerStep(ChannelWait, .{ .ch = ch }, ctx.vm, ctx.sched, me);

    if (ch.head != types.NIL) return dequeueChannel(ch, ch_val);
    return blockOrDeadlock(ctx.vm, me, my_idx, ch_val, "channel-receive: deadlock — channel is empty and all fibers are blocked");
}

fn dequeueChannel(ch: *types.Channel, ch_val: Value) Value {
    const pair = types.toObject(ch.head).as(types.Pair);
    const val = pair.car;
    ch.head = pair.cdr;
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(ch_val), pair.cdr);
    if (ch.head == types.NIL) ch.tail = types.NIL;
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
