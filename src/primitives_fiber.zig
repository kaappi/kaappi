const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
const shared_channel = @import("shared_channel.zig");
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
        return raiseChannelError("channel belongs to another thread; pass it through the thread thunk to share it");
    const ch = ch_obj.as(types.Channel);

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        const outcome = shared_channel.send(sc, args[1], null) catch |err| {
            return translateSharedChannelError(err, "channel-send");
        };
        return switch (outcome) {
            .sent => types.VOID,
            // Phase 1 channels are always unbounded and open -- no
            // Scheme-level API sets capacity or closed yet (KEP-0002
            // Phase 4) -- so these branches are unreachable through
            // make-channel's output.
            .would_park, .closed => unreachable,
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

fn channelReceiveFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-receive", "channel", args[0]);

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ch_obj = types.toObject(args[0]);
    if (ch_obj.owner != gc.id)
        return raiseChannelError("channel belongs to another thread; pass it through the thread thunk to share it");
    const ch = ch_obj.as(types.Channel);

    if (ch.shared) |raw| {
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        const outcome = shared_channel.receive(sc, gc, null) catch |err| {
            return translateSharedChannelError(err, "channel-receive");
        };
        return switch (outcome) {
            .value => |v| v,
            // Phase 1 channels are always open (channel-close! is Phase 4)
            // and fiber-parking isn't wired to the shared path yet (Phase
            // 3) -- unreachable through make-channel's output.
            .would_park, .eof => unreachable,
        };
    }

    if (ch.head != types.NIL and types.isPair(ch.head)) {
        return dequeueChannel(ch, args[0]);
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    if (vm.scheduler == null) {
        // No fibers exist, so nothing can ever send: blocking would hang.
        return raiseDeadlockError("channel-receive: deadlock — channel is empty and no fibers are running");
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
    return raiseDeadlockError(deadlock_msg);
}

fn raiseDeadlockError(msg: []const u8) PrimitiveError {
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

/// Same shape as raiseDeadlockError, kept separate since the message isn't
/// about deadlocks: the foreign-owner check (KEP-0002 §2) and a shared-path
/// uncopyable payload both need this.
fn raiseChannelError(msg: []const u8) PrimitiveError {
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
        return raiseChannelError(msg);
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
