const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const fiber_mod = @import("fiber.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

const ChildThreadResources = struct {
    child_gc: *memory.GC,
    child_vm: *vm_mod.VM,
    result: Value = types.VOID,
    exception: ?Value = null,
};

var child_resources: std.AutoHashMap(usize, ChildThreadResources) = std.AutoHashMap(usize, ChildThreadResources).init(std.heap.page_allocator);
var child_resources_mutex = std.atomic.Mutex.unlocked;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerSrfi18(vm: *vm_mod.VM) !void {
    // Thread
    try reg(vm, "current-thread", &currentThreadFn, .{ .exact = 0 });
    try reg(vm, "thread?", &threadPredFn, .{ .exact = 1 });
    try reg(vm, "make-thread", &makeThreadFn, .{ .variadic = 1 });
    try reg(vm, "thread-name", &threadNameFn, .{ .exact = 1 });
    try reg(vm, "thread-specific", &threadSpecificFn, .{ .exact = 1 });
    try reg(vm, "thread-specific-set!", &threadSpecificSetFn, .{ .exact = 2 });
    try reg(vm, "thread-start!", &threadStartFn, .{ .exact = 1 });
    try reg(vm, "thread-yield!", &threadYieldFn, .{ .exact = 0 });
    try reg(vm, "thread-sleep!", &threadSleepFn, .{ .exact = 1 });
    try reg(vm, "thread-terminate!", &threadTerminateFn, .{ .exact = 1 });
    try reg(vm, "thread-join!", &threadJoinFn, .{ .variadic = 1 });

    // Mutex
    try reg(vm, "mutex?", &mutexPredFn, .{ .exact = 1 });
    try reg(vm, "make-mutex", &makeMutexFn, .{ .variadic = 0 });
    try reg(vm, "mutex-name", &mutexNameFn, .{ .exact = 1 });
    try reg(vm, "mutex-specific", &mutexSpecificFn, .{ .exact = 1 });
    try reg(vm, "mutex-specific-set!", &mutexSpecificSetFn, .{ .exact = 2 });
    try reg(vm, "mutex-state", &mutexStateFn, .{ .exact = 1 });
    try reg(vm, "mutex-lock!", &mutexLockFn, .{ .variadic = 1 });
    try reg(vm, "mutex-unlock!", &mutexUnlockFn, .{ .variadic = 1 });

    // Condition variable
    try reg(vm, "condition-variable?", &condvarPredFn, .{ .exact = 1 });
    try reg(vm, "make-condition-variable", &makeCondvarFn, .{ .variadic = 0 });
    try reg(vm, "condition-variable-name", &condvarNameFn, .{ .exact = 1 });
    try reg(vm, "condition-variable-specific", &condvarSpecificFn, .{ .exact = 1 });
    try reg(vm, "condition-variable-specific-set!", &condvarSpecificSetFn, .{ .exact = 2 });
    try reg(vm, "condition-variable-signal!", &condvarSignalFn, .{ .exact = 1 });
    try reg(vm, "condition-variable-broadcast!", &condvarBroadcastFn, .{ .exact = 1 });

    // Time
    try reg(vm, "current-time", &currentTimeFn, .{ .exact = 0 });
    try reg(vm, "time?", &timePredFn, .{ .exact = 1 });
    try reg(vm, "time->seconds", &timeToSecondsFn, .{ .exact = 1 });
    try reg(vm, "seconds->time", &secondsToTimeFn, .{ .exact = 1 });

    // Exception predicates
    try reg(vm, "join-timeout-exception?", &joinTimeoutPredFn, .{ .exact = 1 });
    try reg(vm, "abandoned-mutex-exception?", &abandonedMutexPredFn, .{ .exact = 1 });
    try reg(vm, "terminated-thread-exception?", &terminatedThreadPredFn, .{ .exact = 1 });
    try reg(vm, "uncaught-exception?", &uncaughtExceptionPredFn, .{ .exact = 1 });
    try reg(vm, "uncaught-exception-reason", &uncaughtExceptionReasonFn, .{ .exact = 1 });
}

fn ensureScheduler() PrimitiveError!struct { vm: *vm_mod.VM, sched: *fiber_mod.FiberScheduler } {
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
    return .{ .vm = vm, .sched = vm.scheduler.? };
}

fn timeoutToDeadlineNs(timeout: Value) PrimitiveError!?u64 {
    if (timeout == types.FALSE) return null;
    if (types.isSrfi18Time(timeout)) {
        const t = types.toSrfi18Time(timeout);
        const sec_ns: u64 = @intFromFloat(@max(0.0, t.seconds) * 1_000_000_000.0);
        var now_ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(.REALTIME, &now_ts);
        const now_ns = @as(u64, @intCast(now_ts.sec)) * 1_000_000_000 + @as(u64, @intCast(now_ts.nsec));
        if (sec_ns <= now_ns) return 0;
        const mono_now = fiber_mod.clockNs();
        return mono_now + (sec_ns - now_ns);
    }
    const secs = primitives.toF64(timeout) catch
        return primitives.typeError("thread", "time object or number", timeout);
    const mono_now = fiber_mod.clockNs();
    const delta_ns: u64 = @intFromFloat(@max(0.0, secs) * 1_000_000_000.0);
    return mono_now + delta_ns;
}

fn makeErrorWithType(error_type: types.ErrorObject.ErrorType, msg: []const u8, reason: Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const message = gc.allocString(msg) catch return PrimitiveError.OutOfMemory;
    var msg_root = message;
    gc.pushRoot(&msg_root) catch return PrimitiveError.OutOfMemory;
    const err_val = gc.allocErrorObject(msg_root, types.NIL) catch {
        gc.popRoot();
        return PrimitiveError.OutOfMemory;
    };
    gc.popRoot();
    const err = types.toObject(err_val).as(types.ErrorObject);
    err.error_type = error_type;
    err.uncaught_reason = reason;
    return err_val;
}

fn raiseError(error_type: types.ErrorObject.ErrorType, msg: []const u8, reason: Value) PrimitiveError!Value {
    const err_val = try makeErrorWithType(error_type, msg, reason);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    vm.current_exception = err_val;
    return PrimitiveError.ExceptionRaised;
}

pub fn abandonFiberMutexes(gc: *memory.GC, fiber: *fiber_mod.Fiber, sched: ?*fiber_mod.FiberScheduler) void {
    const fiber_val = types.makePointer(@ptrCast(fiber));
    var lists = [_]?*types.Object{ gc.objects, gc.old_objects };
    for (&lists) |*head| {
        var obj = head.*;
        while (obj) |o| : (obj = o.next) {
            if (o.tag == .mutex) {
                const m = o.as(types.Mutex);
                if (m.locked and m.owner == fiber_val) {
                    m.abandoned = true;
                    m.locked = false;
                    m.owner = types.VOID;
                    if (sched) |s| s.wakeMutexWaiters(types.makePointer(@ptrCast(o)));
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Thread primitives
// ---------------------------------------------------------------------------

fn currentThreadFn(_: []const Value) PrimitiveError!Value {
    const ctx = try ensureScheduler();
    const fiber = ctx.vm.current_fiber orelse return types.VOID;
    return types.makePointer(@ptrCast(fiber));
}

fn threadPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isFiber(args[0])) types.TRUE else types.FALSE;
}

fn makeThreadFn(args: []const Value) PrimitiveError!Value {
    const thunk = args[0];
    if (!types.isClosure(thunk))
        return primitives.typeError("make-thread", "procedure", thunk);

    const ctx = try ensureScheduler();
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    const fiber = gc.allocFiber(thunk, ctx.sched.next_id) catch return PrimitiveError.OutOfMemory;
    ctx.sched.next_id += 1;

    const closure = types.toObject(thunk).as(types.Closure);
    @memset(fiber.registers, types.UNDEFINED);
    fiber.registers[0] = thunk;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    fiber.frames[0] = .{
        .closure = closure,
        .code = closure.func.code.items,
        .ip = 0,
        .base = 0,
        .dst = 0,
        .saved_wind_count = 0,
        .seq = vm.nextFrameSeq(),
    };
    fiber.frame_count = 1;
    fiber.status = .created;

    if (args.len > 1) fiber.name = args[1];

    return types.makePointer(@ptrCast(fiber));
}

fn threadNameFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-name", "thread", args[0]);
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);
    return fiber.name;
}

fn threadSpecificFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-specific", "thread", args[0]);
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);
    return fiber.specific;
}

fn threadSpecificSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-specific-set!", "thread", args[0]);
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);
    fiber.specific = args[1];
    if (primitives.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    return types.VOID;
}

fn threadStartFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-start!", "thread", args[0]);

    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);

    if (fiber.status != .created)
        return primitives.typeError("thread-start!", "new thread", args[0]);

    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;

    gc.extra_roots.append(gc.allocator, fiber.thunk) catch return PrimitiveError.OutOfMemory;

    fiber.status = .running;
    fiber.os_thread = std.Thread.spawn(.{}, threadEntryFn, .{
        fiber, gc.allocator, gc, vm,
    }) catch return PrimitiveError.OutOfMemory;

    return args[0];
}

fn threadEntryFn(fiber: *fiber_mod.Fiber, allocator: std.mem.Allocator, parent_gc: *memory.GC, parent_vm: *vm_mod.VM) void {
    _ = parent_gc;
    const child_gc = allocator.create(memory.GC) catch {
        fiber.status = .errored;
        return;
    };
    child_gc.* = memory.GC.initForThread(allocator, parent_vm.gc);

    const child_vm = allocator.create(vm_mod.VM) catch {
        child_gc.deinit();
        allocator.destroy(child_gc);
        fiber.status = .errored;
        return;
    };
    @memset(std.mem.asBytes(child_vm), 0);
    child_vm.* = vm_mod.VM.initForThread(child_gc, parent_vm) catch {
        allocator.destroy(child_vm);
        child_gc.deinit();
        allocator.destroy(child_gc);
        fiber.status = .errored;
        return;
    };

    vm_mod.vm_instance = child_vm;
    primitives.gc_instance = child_gc;

    {
        while (!child_resources_mutex.tryLock()) {}
        defer child_resources_mutex.unlock();
        child_resources.put(@intFromPtr(fiber), .{ .child_gc = child_gc, .child_vm = child_vm }) catch {
            fiber.status = .errored;
            fiber.result = types.VOID;
            child_vm.deinit();
            allocator.destroy(child_vm);
            child_gc.deinit();
            allocator.destroy(child_gc);
            return;
        };
    }

    const child_thunk = child_gc.deepCopy(fiber.thunk) catch |err| {
        fiber.status = .errored;
        if (err == error.UncopyableType) {
            const exc = child_gc.allocErrorObject(
                child_gc.allocString("thread thunk contains uncopyable type (port, continuation, etc.)") catch types.VOID,
                types.NIL,
            ) catch null;
            storeChildResult(@intFromPtr(fiber), types.VOID, exc);
        }
        return;
    };

    const result = child_vm.callWithArgs(child_thunk, &.{}) catch {
        if (child_vm.current_fiber) |cf| abandonFiberMutexes(child_gc, cf, child_vm.scheduler);
        fiber.status = .errored;
        storeChildResult(@intFromPtr(fiber), types.VOID, child_vm.current_exception);
        return;
    };

    if (child_vm.current_fiber) |cf| abandonFiberMutexes(child_gc, cf, child_vm.scheduler);

    // Store result in child_resources (not on the fiber) so the parent
    // GC never traverses a child-heap pointer (Race C).
    storeChildResult(@intFromPtr(fiber), result, null);
    fiber.status = .completed;
}

fn storeChildResult(fiber_key: usize, result: Value, exception: ?Value) void {
    while (!child_resources_mutex.tryLock()) {}
    defer child_resources_mutex.unlock();
    if (child_resources.getPtr(fiber_key)) |entry| {
        entry.result = result;
        entry.exception = exception;
    }
}

fn threadYieldFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    if (vm.scheduler == null) return types.VOID;
    vm.yielded = true;
    return types.VOID;
}

fn threadSleepFn(args: []const Value) PrimitiveError!Value {
    if (args[0] == types.FALSE) return PrimitiveError.TypeError; // bare-ok: type guard
    const seconds = try getSleepSeconds(args[0]);
    if (seconds <= 0) return types.VOID;
    const total_ns: u64 = @intFromFloat(@max(0.0, seconds * 1e9));
    var ts: std.c.timespec = .{
        .sec = @intCast(total_ns / 1_000_000_000),
        .nsec = @intCast(total_ns % 1_000_000_000),
    };
    while (true) {
        const ret = std.c.nanosleep(&ts, &ts);
        if (ret == 0) break;
        if (std.posix.errno(ret) != .INTR) break;
    }
    return types.VOID;
}

fn getSleepSeconds(v: Value) PrimitiveError!f64 {
    if (types.isFixnum(v)) return @floatFromInt(types.toFixnum(v));
    if (types.isFlonum(v)) return types.toFlonum(v);
    if (types.isRationalObj(v)) {
        const r = types.toRational(v);
        const n = primitives.toF64(r.numerator) catch return PrimitiveError.TypeError; // bare-ok: type guard
        const d = primitives.toF64(r.denominator) catch return PrimitiveError.TypeError; // bare-ok: type guard
        return n / d;
    }
    if (types.isPointer(v) and types.toObject(v).tag == .srfi18_time) {
        const t = types.toObject(v).as(types.Srfi18Time);
        var ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(.REALTIME, &ts);
        const now: f64 = @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
        return t.seconds - now;
    }
    return PrimitiveError.TypeError; // bare-ok: type guard
}

fn threadTerminateFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-terminate!", "thread", args[0]);

    const ctx = try ensureScheduler();
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);

    fiber.terminated = true;

    if (primitives.gc_instance) |gc| abandonFiberMutexes(gc, fiber, ctx.sched);

    if (fiber.status != .completed and fiber.status != .errored) {
        fiber.status = .errored;
        ctx.sched.wakeWaiters(fiber);
    }

    if (fiber == ctx.vm.current_fiber) {
        ctx.vm.yielded = true;
    }
    return types.VOID;
}

fn threadJoinFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-join!", "thread", args[0]);

    const target = types.toObject(args[0]).as(fiber_mod.Fiber);

    // Self-join detection: a thread cannot join itself (SRFI-18)
    if (vm_mod.vm_instance) |vm| {
        if (vm.current_fiber) |me| {
            if (me == target)
                return raiseError(.general, "thread-join!: thread cannot join itself", args[0]);
        }
    }

    // OS thread path: join, deep-copy result from child heap, free child resources
    if (target.os_thread) |thread| {
        thread.join();
        target.os_thread = null;

        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

        // Remove thunk from extra_roots (added by thread-start! to keep it
        // alive during deep-copy; the child is done now).
        for (gc.extra_roots.items, 0..) |v, idx| {
            if (v == target.thunk) {
                _ = gc.extra_roots.swapRemove(idx);
                break;
            }
        }
        const fiber_key = @intFromPtr(target);

        // Retrieve result/exception from child_resources (stored there to
        // avoid the parent GC traversing child-heap pointers via the fiber).
        {
            while (!child_resources_mutex.tryLock()) {}
            const entry = child_resources.get(fiber_key);
            child_resources_mutex.unlock();

            if (entry) |res| {
                if (target.status == .completed and res.result != types.VOID) {
                    target.result = gc.deepCopy(res.result) catch |err| {
                        target.result = types.VOID;
                        freeChildResources(fiber_key);
                        if (err == error.UncopyableType) {
                            return raiseError(.general, "thread-join!: result contains uncopyable type (port, continuation, etc.)", types.VOID);
                        }
                        return PrimitiveError.OutOfMemory;
                    };
                }
                if (target.status == .errored) {
                    if (res.exception) |exc| {
                        target.current_exception = gc.deepCopy(exc) catch null;
                    }
                }
            }
        }
        freeChildResources(fiber_key);
        return threadJoinResult(target);
    }

    // Fiber path (existing behavior)
    var deadline: ?u64 = null;
    var has_timeout_val = false;
    var timeout_val: Value = types.VOID;
    if (args.len > 1) {
        deadline = try timeoutToDeadlineNs(args[1]);
        if (args.len > 2) {
            has_timeout_val = true;
            timeout_val = args[2];
        }
    }

    if (target.status != .completed and target.status != .errored) {
        const ctx = try ensureScheduler();
        const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;

        me.waiting_on = args[0];
        me.status = .waiting;
        me.timed_out = false;
        if (deadline) |d| me.deadline_ns = d;

        try runSchedulerUntilDone(target);

        if (me.timed_out) {
            me.timed_out = false;
            if (has_timeout_val) return timeout_val;
            return raiseError(.join_timeout, "thread-join! timed out", types.VOID);
        }
    }

    return threadJoinResult(target);
}

fn freeChildResources(fiber_key: usize) void {
    while (!child_resources_mutex.tryLock()) {}
    const entry = child_resources.fetchRemove(fiber_key);
    child_resources_mutex.unlock();

    if (entry) |kv| {
        const allocator = kv.value.child_gc.allocator;
        kv.value.child_vm.deinit();
        allocator.destroy(kv.value.child_vm);
        kv.value.child_gc.deinit();
        allocator.destroy(kv.value.child_gc);
    }
}

fn threadJoinResult(target: *fiber_mod.Fiber) PrimitiveError!Value {
    if (target.terminated)
        return raiseError(.terminated_thread, "thread terminated", types.VOID);

    if (target.status == .errored) {
        const reason = if (target.current_exception) |exc| exc else target.result;
        return raiseError(.uncaught_exception, "uncaught exception in thread", reason);
    }

    return target.result;
}

fn runSchedulerUntilDone(target: *fiber_mod.Fiber) PrimitiveError!void {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const sched = vm.scheduler orelse return PrimitiveError.OutOfMemory;
    const my_idx = sched.current_idx;
    sched.saveCurrentFiber();

    while (target.status != .completed and target.status != .errored) {
        const me = sched.fibers[my_idx].?;
        if (me.timed_out) break;

        const next_idx = sched.schedule() orelse break;
        if (next_idx == my_idx) break;

        sched.restoreFiber(next_idx);
        sched.current_idx = next_idx;
        const fiber = sched.fibers[next_idx].?;
        fiber.status = .running;
        vm.current_fiber = fiber;

        const result = vm.runUntil(0, 0) catch |err| {
            if (err == vm_mod.VMError.Yielded) {
                sched.saveCurrentFiber();
                if (fiber.status == .running) fiber.status = .suspended;
                continue;
            }
            fiber.status = .errored;
            if (primitives.gc_instance) |gc| abandonFiberMutexes(gc, fiber, sched);
            sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        if (primitives.gc_instance) |gc| {
            gc.writeBarrier(&fiber.header, result);
            abandonFiberMutexes(gc, fiber, sched);
        }
        sched.saveCurrentFiber();
        sched.wakeWaiters(fiber);
    }

    sched.restoreFiber(my_idx);
    sched.current_idx = my_idx;
    const me = sched.fibers[my_idx].?;
    me.status = .running;
    vm.current_fiber = me;
}

// ---------------------------------------------------------------------------
// Mutex primitives
// ---------------------------------------------------------------------------

fn mutexPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isMutex(args[0])) types.TRUE else types.FALSE;
}

fn makeMutexFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const name = if (args.len > 0) args[0] else types.VOID;
    return gc.allocMutex(name) catch return PrimitiveError.OutOfMemory;
}

fn mutexNameFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-name", "mutex", args[0]);
    return types.toMutex(args[0]).name;
}

fn mutexSpecificFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-specific", "mutex", args[0]);
    return types.toMutex(args[0]).specific;
}

fn mutexSpecificSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-specific-set!", "mutex", args[0]);
    types.toMutex(args[0]).specific = args[1];
    if (primitives.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    return types.VOID;
}

fn mutexStateFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-state", "mutex", args[0]);
    const m = types.toMutex(args[0]);
    if (!m.locked) {
        if (m.abandoned) {
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            return gc.allocSymbol("abandoned") catch return PrimitiveError.OutOfMemory;
        }
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        return gc.allocSymbol("not-abandoned") catch return PrimitiveError.OutOfMemory;
    }
    if (m.owner != types.VOID) return m.owner;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocSymbol("not-owned") catch return PrimitiveError.OutOfMemory;
}

fn mutexLockFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-lock!", "mutex", args[0]);

    const m = types.toMutex(args[0]);

    if (m.abandoned) {
        m.abandoned = false;
        m.locked = true;
        const ctx = try ensureScheduler();
        m.owner = if (args.len > 2 and types.isFiber(args[2]))
            args[2]
        else if (ctx.vm.current_fiber) |cf|
            types.makePointer(@ptrCast(cf))
        else
            types.VOID;
        return raiseError(.abandoned_mutex, "mutex was abandoned", types.VOID);
    }

    if (!m.locked) {
        m.locked = true;
        const ctx = try ensureScheduler();
        m.owner = if (args.len > 2 and types.isFiber(args[2]))
            args[2]
        else if (ctx.vm.current_fiber) |cf|
            types.makePointer(@ptrCast(cf))
        else
            types.VOID;
        return types.TRUE;
    }

    var deadline: ?u64 = null;
    if (args.len > 1) {
        deadline = try timeoutToDeadlineNs(args[1]);
        if (deadline != null and deadline.? == 0) return types.FALSE;
    }

    const ctx = try ensureScheduler();
    const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;

    me.waiting_on = args[0];
    me.status = .waiting;
    me.timed_out = false;
    if (deadline) |d| me.deadline_ns = d;

    try runSchedulerUntilMutex(m, me);

    if (me.timed_out) {
        me.timed_out = false;
        return types.FALSE;
    }

    m.locked = true;
    m.owner = if (args.len > 2 and types.isFiber(args[2]))
        args[2]
    else
        types.makePointer(@ptrCast(me));

    if (m.abandoned) {
        m.abandoned = false;
        return raiseError(.abandoned_mutex, "mutex was abandoned", types.VOID);
    }
    return types.TRUE;
}

fn runSchedulerUntilMutex(m: *types.Mutex, me: *fiber_mod.Fiber) PrimitiveError!void {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const sched = vm.scheduler orelse return PrimitiveError.OutOfMemory;
    const my_idx = sched.current_idx;
    sched.saveCurrentFiber();

    while (m.locked and !me.timed_out) {
        const next_idx = sched.schedule() orelse break;
        if (next_idx == my_idx) break;

        sched.restoreFiber(next_idx);
        sched.current_idx = next_idx;
        const fiber = sched.fibers[next_idx].?;
        fiber.status = .running;
        vm.current_fiber = fiber;

        const result = vm.runUntil(0, 0) catch |err| {
            if (err == vm_mod.VMError.Yielded) {
                sched.saveCurrentFiber();
                if (fiber.status == .running) fiber.status = .suspended;
                continue;
            }
            fiber.status = .errored;
            if (primitives.gc_instance) |gc| abandonFiberMutexes(gc, fiber, sched);
            sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        if (primitives.gc_instance) |gc| {
            gc.writeBarrier(&fiber.header, result);
            abandonFiberMutexes(gc, fiber, sched);
        }
        sched.saveCurrentFiber();
        sched.wakeWaiters(fiber);
    }

    sched.restoreFiber(my_idx);
    sched.current_idx = my_idx;
    me.status = .running;
    vm.current_fiber = me;
}

fn mutexUnlockFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-unlock!", "mutex", args[0]);

    const m = types.toMutex(args[0]);
    m.locked = false;
    m.owner = types.VOID;

    const ctx = try ensureScheduler();
    ctx.sched.wakeMutexWaiters(args[0]);

    if (args.len > 1 and types.isConditionVariable(args[1])) {
        var deadline: ?u64 = null;
        if (args.len > 2) {
            deadline = try timeoutToDeadlineNs(args[2]);
        }

        const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;
        me.waiting_on = args[1];
        me.status = .waiting;
        me.timed_out = false;
        if (deadline) |d| me.deadline_ns = d;

        try runSchedulerUntilCondVar(me);

        if (me.timed_out) {
            me.timed_out = false;
            return types.FALSE;
        }
        return types.TRUE;
    }

    return types.TRUE;
}

fn runSchedulerUntilCondVar(me: *fiber_mod.Fiber) PrimitiveError!void {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const sched = vm.scheduler orelse return PrimitiveError.OutOfMemory;
    const my_idx = sched.current_idx;
    sched.saveCurrentFiber();

    while (me.status == .waiting and !me.timed_out) {
        const next_idx = sched.schedule() orelse break;
        if (next_idx == my_idx) break;

        sched.restoreFiber(next_idx);
        sched.current_idx = next_idx;
        const fiber = sched.fibers[next_idx].?;
        fiber.status = .running;
        vm.current_fiber = fiber;

        const result = vm.runUntil(0, 0) catch |err| {
            if (err == vm_mod.VMError.Yielded) {
                sched.saveCurrentFiber();
                if (fiber.status == .running) fiber.status = .suspended;
                continue;
            }
            fiber.status = .errored;
            if (primitives.gc_instance) |gc| abandonFiberMutexes(gc, fiber, sched);
            sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        if (primitives.gc_instance) |gc| {
            gc.writeBarrier(&fiber.header, result);
            abandonFiberMutexes(gc, fiber, sched);
        }
        sched.saveCurrentFiber();
        sched.wakeWaiters(fiber);
    }

    sched.restoreFiber(my_idx);
    sched.current_idx = my_idx;
    me.status = .running;
    vm.current_fiber = me;
}

// ---------------------------------------------------------------------------
// Condition variable primitives
// ---------------------------------------------------------------------------

fn condvarPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isConditionVariable(args[0])) types.TRUE else types.FALSE;
}

fn makeCondvarFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const name = if (args.len > 0) args[0] else types.VOID;
    return gc.allocConditionVariable(name) catch return PrimitiveError.OutOfMemory;
}

fn condvarNameFn(args: []const Value) PrimitiveError!Value {
    if (!types.isConditionVariable(args[0]))
        return primitives.typeError("condition-variable-name", "condition-variable", args[0]);
    return types.toConditionVariable(args[0]).name;
}

fn condvarSpecificFn(args: []const Value) PrimitiveError!Value {
    if (!types.isConditionVariable(args[0]))
        return primitives.typeError("condition-variable-specific", "condition-variable", args[0]);
    return types.toConditionVariable(args[0]).specific;
}

fn condvarSpecificSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isConditionVariable(args[0]))
        return primitives.typeError("condition-variable-specific-set!", "condition-variable", args[0]);
    types.toConditionVariable(args[0]).specific = args[1];
    if (primitives.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    return types.VOID;
}

fn condvarSignalFn(args: []const Value) PrimitiveError!Value {
    if (!types.isConditionVariable(args[0]))
        return primitives.typeError("condition-variable-signal!", "condition-variable", args[0]);
    const ctx = try ensureScheduler();
    ctx.sched.wakeOneCondVarWaiter(args[0]);
    return types.VOID;
}

fn condvarBroadcastFn(args: []const Value) PrimitiveError!Value {
    if (!types.isConditionVariable(args[0]))
        return primitives.typeError("condition-variable-broadcast!", "condition-variable", args[0]);
    const ctx = try ensureScheduler();
    ctx.sched.wakeAllCondVarWaiters(args[0]);
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Time primitives
// ---------------------------------------------------------------------------

fn currentTimeFn(_: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    const seconds = @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000_000.0;
    return gc.allocSrfi18Time(seconds) catch return PrimitiveError.OutOfMemory;
}

fn timePredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isSrfi18Time(args[0])) types.TRUE else types.FALSE;
}

fn timeToSecondsFn(args: []const Value) PrimitiveError!Value {
    if (!types.isSrfi18Time(args[0]))
        return primitives.typeError("time->seconds", "time", args[0]);
    return types.makeFlonum(types.toSrfi18Time(args[0]).seconds);
}

fn secondsToTimeFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const secs = primitives.toF64(args[0]) catch
        return primitives.typeError("seconds->time", "number", args[0]);
    return gc.allocSrfi18Time(secs) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Exception predicates
// ---------------------------------------------------------------------------

fn isErrorOfType(v: Value, error_type: types.ErrorObject.ErrorType) bool {
    if (!types.isPointer(v)) return false;
    const obj = types.toObject(v);
    if (obj.tag != .error_object) return false;
    return obj.as(types.ErrorObject).error_type == error_type;
}

fn joinTimeoutPredFn(args: []const Value) PrimitiveError!Value {
    return if (isErrorOfType(args[0], .join_timeout)) types.TRUE else types.FALSE;
}

fn abandonedMutexPredFn(args: []const Value) PrimitiveError!Value {
    return if (isErrorOfType(args[0], .abandoned_mutex)) types.TRUE else types.FALSE;
}

fn terminatedThreadPredFn(args: []const Value) PrimitiveError!Value {
    return if (isErrorOfType(args[0], .terminated_thread)) types.TRUE else types.FALSE;
}

fn uncaughtExceptionPredFn(args: []const Value) PrimitiveError!Value {
    return if (isErrorOfType(args[0], .uncaught_exception)) types.TRUE else types.FALSE;
}

fn uncaughtExceptionReasonFn(args: []const Value) PrimitiveError!Value {
    if (!isErrorOfType(args[0], .uncaught_exception))
        return primitives.typeError("uncaught-exception-reason", "uncaught-exception", args[0]);
    return types.toObject(args[0]).as(types.ErrorObject).uncaught_reason;
}
