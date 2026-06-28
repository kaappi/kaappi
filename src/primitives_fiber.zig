const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const fiber_mod = @import("fiber.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerFiber(vm: *vm_mod.VM) !void {
    try reg(vm, "spawn", &spawnFn, .{ .exact = 1 });
    try reg(vm, "yield", &yieldFn, .{ .exact = 0 });
    try reg(vm, "fiber-join", &fiberJoinFn, .{ .exact = 1 });
    try reg(vm, "fiber?", &fiberPredFn, .{ .exact = 1 });
    try reg(vm, "make-channel", &makeChannelFn, .{ .exact = 0 });
    try reg(vm, "channel-send", &channelSendFn, .{ .exact = 2 });
    try reg(vm, "channel-receive", &channelReceiveFn, .{ .exact = 1 });
    try reg(vm, "channel?", &channelPredFn, .{ .exact = 1 });
}

fn getScheduler() ?*fiber_mod.FiberScheduler {
    const vm = vm_mod.vm_instance orelse return null;
    return vm.scheduler;
}

fn spawnFn(args: []const Value) PrimitiveError!Value {
    const proc = args[0];
    if (!types.isClosure(proc) and !types.isNativeFn(proc))
        return primitives.typeError("spawn", "procedure", proc);

    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;

    if (vm.scheduler == null) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const fiber = sched.spawnFiber(proc) catch return PrimitiveError.OutOfMemory;
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

    if (target.status == .completed or target.status == .errored) return target.result;

    return runSchedulerUntil(target, null, types.VOID);
}

fn fiberPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isFiber(args[0])) types.TRUE else types.FALSE;
}

fn makeChannelFn(_: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocChannel() catch return PrimitiveError.OutOfMemory;
}

fn channelSendFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-send", "channel", args[0]);

    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    return types.VOID;
}

fn channelReceiveFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChannel(args[0]))
        return primitives.typeError("channel-receive", "channel", args[0]);

    const ch = types.toObject(args[0]).as(types.Channel);

    if (ch.head != types.NIL and types.isPair(ch.head)) {
        return dequeueChannel(ch, args[0]);
    }

    return runSchedulerUntil(null, ch, args[0]);
}

fn dequeueChannel(ch: *types.Channel, ch_val: Value) Value {
    const pair = types.toObject(ch.head).as(types.Pair);
    const val = pair.car;
    ch.head = pair.cdr;
    if (primitives.gc_instance) |gc| gc.writeBarrier(types.toObject(ch_val), pair.cdr);
    if (ch.head == types.NIL) ch.tail = types.NIL;
    return val;
}

fn runSchedulerUntil(target: ?*fiber_mod.Fiber, ch: ?*types.Channel, ch_val: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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

        const result = vm.runUntil(0, 0) catch |err| {
            if (err == vm_mod.VMError.Yielded) {
                sched.saveCurrentFiber();
                if (fiber.status == .running) fiber.status = .suspended;
                continue;
            }
            fiber.status = .errored;
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

    if (target) |f| return f.result;
    if (ch) |channel| {
        if (channel.head != types.NIL) return dequeueChannel(channel, ch_val);
    }
    return types.VOID;
}

fn channelPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isChannel(args[0])) types.TRUE else types.FALSE;
}
