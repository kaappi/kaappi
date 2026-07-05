const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
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
    if (!types.isClosure(proc))
        return primitives.typeError("spawn", "closure", proc);

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;

    if (vm.scheduler == null) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const sched = gc.allocator.create(fiber_mod.FiberScheduler) catch return PrimitiveError.OutOfMemory;
        sched.* = fiber_mod.FiberScheduler.init(vm);

        const main_fiber = gc.allocFiber(types.VOID, sched.next_id) catch return PrimitiveError.OutOfMemory;
        sched.next_id += 1;
        main_fiber.status = .running;
        sched.addFiber(main_fiber) catch return PrimitiveError.OutOfMemory;
        vm.scheduler = sched;
        vm.current_fiber = main_fiber;
    }

    const sched = vm.scheduler.?;
    const fiber = sched.spawnFiber(proc) catch |err| {
        if (err == vm_mod.VMError.StackOverflow) {
            vm.setErrorDetail("spawn: fiber limit exceeded (max {d})", .{fiber_mod.MAX_FIBERS});
            return PrimitiveError.InvalidArgument;
        }
        return PrimitiveError.OutOfMemory;
    };
    return types.makePointer(@ptrCast(fiber));
}

fn yieldFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    if (vm.scheduler == null) return types.VOID;
    vm.yielded = true;
    return types.VOID;
}

fn fiberJoinFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("fiber-join", "fiber", args[0]);

    const target = types.toObject(args[0]).as(fiber_mod.Fiber);

    if (target.status == .completed) return target.result;
    if (target.status == .errored) return reraiseFiberError(target);

    const result = try runSchedulerUntil(target, null, types.VOID);
    if (target.status == .errored) return reraiseFiberError(target);
    return result;
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
    const ch = types.toObject(args[0]).as(types.Channel);
    const new_pair = gc.allocPair(args[1], types.NIL) catch return PrimitiveError.OutOfMemory;

    if (ch.tail != types.NIL and types.isPair(ch.tail)) {
        const tail_obj = types.toObject(ch.tail);
        tail_obj.as(types.Pair).cdr = new_pair;
        gc.writeBarrier(tail_obj, new_pair);
    }
    const ch_obj = types.toObject(args[0]);
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

fn channelReceiveFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-receive", "channel", args[0]);

    const ch = types.toObject(args[0]).as(types.Channel);

    if (ch.head != types.NIL and types.isPair(ch.head)) {
        return dequeueChannel(ch, args[0]);
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    if (vm.scheduler == null) {
        // No fibers exist, so nothing can ever send: blocking would hang.
        return raiseDeadlockError("channel-receive: deadlock — channel is empty and no fibers are running");
    }

    return runSchedulerUntil(null, ch, args[0]);
}

fn dequeueChannel(ch: *types.Channel, ch_val: Value) Value {
    const pair = types.toObject(ch.head).as(types.Pair);
    const val = pair.car;
    ch.head = pair.cdr;
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(ch_val), pair.cdr);
    if (ch.head == types.NIL) ch.tail = types.NIL;
    return val;
}

fn runSchedulerUntil(target: ?*fiber_mod.Fiber, ch: ?*types.Channel, ch_val: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const sched = vm.scheduler orelse return PrimitiveError.OutOfMemory;
    const my_idx = sched.current_idx;
    sched.saveCurrentFiber();

    const done = struct {
        fn check(t: ?*fiber_mod.Fiber, c: ?*types.Channel) bool {
            if (t) |f| return f.status == .completed or f.status == .errored;
            if (c) |channel| return channel.head != types.NIL;
            return true;
        }
    }.check;

    while (!done(target, ch)) {
        const idx = sched.schedule() orelse break;

        sched.restoreFiber(idx);
        sched.current_idx = idx;
        const fiber = sched.fibers[idx].?;
        fiber.status = .running;
        vm.current_fiber = fiber;

        // A dangling yield_retry (a forwarding native converted a park's
        // Yielded into another error) must not survive into this run.
        vm.yield_retry = false;
        vm.sched_dispatch_pending = true;
        const result = vm.runUntil(0, 0) catch |err| {
            if (err == vm_mod.VMError.Yielded) {
                sched.saveCurrentFiber();
                if (fiber.status == .running) fiber.status = .suspended;
                continue;
            }
            fiber.status = .errored;
            fiber.current_exception = vm.current_exception;
            sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        gc.writeBarrier(&fiber.header, result);
        sched.saveCurrentFiber();
        sched.wakeWaiters(fiber);
    }

    sched.restoreFiber(my_idx);
    sched.current_idx = my_idx;
    const me = sched.fibers[my_idx].?;
    me.status = .running;
    vm.current_fiber = me;

    if (target) |f| {
        if (f.status == .completed or f.status == .errored) return f.result;
        return blockOrDeadlock(vm, me, my_idx, types.makePointer(@ptrCast(f)), "fiber-join: deadlock — joined fiber can never complete (all fibers blocked)");
    }
    if (ch) |channel| {
        if (channel.head != types.NIL) return dequeueChannel(channel, ch_val);
        return blockOrDeadlock(vm, me, my_idx, ch_val, "channel-receive: deadlock — channel is empty and all fibers are blocked");
    }
    return types.VOID;
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

fn channelPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isChannel(args[0])) types.TRUE else types.FALSE;
}
