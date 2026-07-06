const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const fiber_mod = @import("fiber.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "current-thread", .func = &currentThreadFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread?", .func = &threadPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "make-thread", .func = &makeThreadFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-name", .func = &threadNameFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-specific", .func = &threadSpecificFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-specific-set!", .func = &threadSpecificSetFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-start!", .func = &threadStartFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-yield!", .func = &threadYieldFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-sleep!", .func = &threadSleepFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-terminate!", .func = &threadTerminateFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "thread-join!", .func = &threadJoinFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "mutex?", .func = &mutexPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "make-mutex", .func = &makeMutexFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "mutex-name", .func = &mutexNameFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "mutex-specific", .func = &mutexSpecificFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "mutex-specific-set!", .func = &mutexSpecificSetFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "mutex-state", .func = &mutexStateFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "mutex-lock!", .func = &mutexLockFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "mutex-unlock!", .func = &mutexUnlockFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "condition-variable?", .func = &condvarPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "make-condition-variable", .func = &makeCondvarFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "condition-variable-name", .func = &condvarNameFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "condition-variable-specific", .func = &condvarSpecificFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "condition-variable-specific-set!", .func = &condvarSpecificSetFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "condition-variable-signal!", .func = &condvarSignalFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "condition-variable-broadcast!", .func = &condvarBroadcastFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "current-time", .func = &currentTimeFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "time?", .func = &timePredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "time->seconds", .func = &timeToSecondsFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "seconds->time", .func = &secondsToTimeFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "join-timeout-exception?", .func = &joinTimeoutPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "abandoned-mutex-exception?", .func = &abandonedMutexPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "terminated-thread-exception?", .func = &terminatedThreadPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "uncaught-exception?", .func = &uncaughtExceptionPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "uncaught-exception-reason", .func = &uncaughtExceptionReasonFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
};

const ChildThreadResources = struct {
    child_gc: *memory.GC,
    child_vm: *vm_mod.VM,
    result: Value = types.VOID,
    exception: ?Value = null,
};

// Entries are freed only when a thread is joined (freeChildResources called
// from reapOsThread). Threads that complete but are never joined leak their
// child VM and GC — the result must survive until the parent deep-copies it,
// and automatic cleanup would race with that copy.
const ChildRegistry = struct {
    map: std.AutoHashMap(usize, ChildThreadResources),
    mutex: std.atomic.Mutex,

    fn put(self: *ChildRegistry, key: usize, res: ChildThreadResources) !void {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        try self.map.put(key, res);
    }

    fn storeResult(self: *ChildRegistry, key: usize, result: Value, exception: ?Value) void {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.getPtr(key)) |entry| {
            entry.result = result;
            entry.exception = exception;
        }
    }

    fn get(self: *ChildRegistry, key: usize) ?ChildThreadResources {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        return self.map.get(key);
    }

    fn fetchRemove(self: *ChildRegistry, key: usize) ?ChildThreadResources {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.fetchRemove(key)) |kv| return kv.value;
        return null;
    }
};

var child_registry: ChildRegistry = .{
    .map = std.AutoHashMap(usize, ChildThreadResources).init(std.heap.page_allocator),
    .mutex = .unlocked,
};

fn ensureScheduler() PrimitiveError!struct { vm: *vm_mod.VM, sched: *fiber_mod.FiberScheduler } {
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const message = gc.allocString(msg) catch return PrimitiveError.OutOfMemory;
    var msg_root = message;
    gc.pushRoot(&msg_root);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    const fiber = gc.allocFiber(thunk, ctx.sched.next_id) catch return PrimitiveError.OutOfMemory;
    ctx.sched.next_id += 1;

    @memset(fiber.registers, types.UNDEFINED);
    fiber.status = .created;

    if (args.len > 1) {
        fiber.name = args[1];
        gc.writeBarrier(&fiber.header, args[1]);
    }

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
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    return types.VOID;
}

fn threadStartFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-start!", "thread", args[0]);

    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);

    if (fiber.status != .created)
        return primitives.typeError("thread-start!", "new thread", args[0]);

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;

    // Root the thunk (the child deep-copies it from the parent heap) and the
    // fiber itself (the child writes fiber.status / reads fiber.terminated
    // for the whole run, so it must survive even if the program drops its
    // last reference). Both are removed at thread-join!.
    gc.extra_roots.append(gc.allocator, fiber.thunk) catch return PrimitiveError.OutOfMemory;
    gc.extra_roots.append(gc.allocator, args[0]) catch return PrimitiveError.OutOfMemory;

    fiber.status = .running;
    fiber.os_thread = std.Thread.spawn(.{}, threadEntryFn, .{
        fiber, gc.allocator, gc, vm,
    }) catch return PrimitiveError.OutOfMemory;

    return args[0];
}

fn threadEntryFn(fiber: *fiber_mod.Fiber, allocator: std.mem.Allocator, parent_gc: *memory.GC, parent_vm: *vm_mod.VM) void {
    _ = parent_gc;
    const child_gc = allocator.create(memory.GC) catch {
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };
    child_gc.* = memory.GC.initForThread(allocator, parent_vm.gc);

    const child_vm = allocator.create(vm_mod.VM) catch {
        child_gc.deinit();
        allocator.destroy(child_gc);
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };
    @memset(std.mem.asBytes(child_vm), 0);
    child_vm.* = vm_mod.VM.initForThread(child_gc, parent_vm) catch {
        allocator.destroy(child_vm);
        child_gc.deinit();
        allocator.destroy(child_gc);
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };

    vm_mod.vm_instance = child_vm;
    memory.gc_instance = child_gc;

    // Let thread-terminate! from the parent stop this thread: the dispatch
    // loop safepoint polls this flag and unwinds with VMError.Terminated.
    child_vm.terminate_flag = &fiber.terminated;

    child_registry.put(@intFromPtr(fiber), .{ .child_gc = child_gc, .child_vm = child_vm }) catch {
        fiber.result = types.VOID;
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        child_vm.deinit();
        allocator.destroy(child_vm);
        child_gc.deinit();
        allocator.destroy(child_gc);
        return;
    };

    const child_thunk = child_gc.deepCopy(fiber.thunk) catch |err| {
        if (err == error.UncopyableType) {
            const exc = child_gc.allocErrorObject(
                child_gc.allocString("thread thunk contains uncopyable type (port, continuation, etc.)") catch types.VOID,
                types.NIL,
            ) catch null;
            child_registry.storeResult(@intFromPtr(fiber), types.VOID, exc);
        }
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };

    const result = child_vm.callWithArgs(child_thunk, &.{}) catch {
        if (child_vm.current_fiber) |cf| abandonFiberMutexes(child_gc, cf, child_vm.scheduler);
        child_registry.storeResult(@intFromPtr(fiber), types.VOID, child_vm.current_exception);
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };

    if (child_vm.current_fiber) |cf| abandonFiberMutexes(child_gc, cf, child_vm.scheduler);

    // Store result in child_resources (not on the fiber) so the parent
    // GC never traverses a child-heap pointer (Race C).
    child_registry.storeResult(@intFromPtr(fiber), result, null);
    @atomicStore(fiber_mod.FiberStatus, &fiber.status, .completed, .release);
}

fn threadYieldFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    if (vm.scheduler == null) {
        std.Thread.yield() catch {};
        return types.VOID;
    }
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

    // Atomic: for OS threads the child VM polls this flag concurrently.
    @atomicStore(bool, &fiber.terminated, true, .monotonic);

    if (memory.gc_instance) |gc| abandonFiberMutexes(gc, fiber, ctx.sched);

    const status = @atomicLoad(fiber_mod.FiberStatus, &fiber.status, .acquire);
    if (status != .completed and status != .errored) {
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        ctx.sched.wakeWaiters(fiber);
    }

    if (fiber == ctx.vm.current_fiber) {
        ctx.vm.yielded = true;
    }
    return types.VOID;
}

fn sleepNs(ns: u64) void {
    var ts: std.c.timespec = .{
        .sec = @intCast(ns / 1_000_000_000),
        .nsec = @intCast(ns % 1_000_000_000),
    };
    while (true) {
        const ret = std.c.nanosleep(&ts, &ts);
        if (ret == 0) break;
        if (std.posix.errno(ret) != .INTR) break;
    }
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

    // Parse timeout/timeout-val for all paths (OS thread, never-started, fiber)
    var deadline_ns: ?u64 = null;
    var has_timeout_val = false;
    var timeout_val: Value = types.VOID;
    if (args.len > 1) {
        deadline_ns = try timeoutToDeadlineNs(args[1]);
        if (args.len > 2) {
            has_timeout_val = true;
            timeout_val = args[2];
        }
    }

    // OS thread path
    if (target.os_thread != null) {
        if (deadline_ns) |deadline| {
            while (@atomicLoad(fiber_mod.FiberStatus, &target.status, .acquire) != .completed and
                @atomicLoad(fiber_mod.FiberStatus, &target.status, .acquire) != .errored)
            {
                if (fiber_mod.clockNs() >= deadline) {
                    if (has_timeout_val) return timeout_val;
                    return raiseError(.join_timeout, "thread-join! timed out", types.VOID);
                }
                sleepNs(1_000_000);
            }
        }
        return reapOsThread(target, args[0]);
    }

    // Never-started thread: poll until started+finished or timeout
    if (@atomicLoad(fiber_mod.FiberStatus, &target.status, .acquire) == .created) {
        while (@atomicLoad(fiber_mod.FiberStatus, &target.status, .acquire) != .completed and
            @atomicLoad(fiber_mod.FiberStatus, &target.status, .acquire) != .errored)
        {
            if (deadline_ns) |deadline| {
                if (fiber_mod.clockNs() >= deadline) {
                    if (has_timeout_val) return timeout_val;
                    return raiseError(.join_timeout, "thread-join! timed out", types.VOID);
                }
            }
            sleepNs(1_000_000);
        }
        if (target.os_thread != null)
            return reapOsThread(target, args[0]);
        return threadJoinResult(target);
    }

    // Fiber path (cooperative scheduling)
    const join_status = @atomicLoad(fiber_mod.FiberStatus, &target.status, .acquire);
    if (join_status != .completed and join_status != .errored) {
        const ctx = try ensureScheduler();
        const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;

        me.waiting_on = args[0];
        me.status = .waiting;
        me.timed_out = false;
        if (deadline_ns) |d| me.deadline_ns = d;

        try runSchedulerUntilDone(target);

        if (me.timed_out) {
            me.timed_out = false;
            if (has_timeout_val) return timeout_val;
            return raiseError(.join_timeout, "thread-join! timed out", types.VOID);
        }
    }

    return threadJoinResult(target);
}

fn reapOsThread(target: *fiber_mod.Fiber, fiber_val: Value) PrimitiveError!Value {
    if (target.os_thread) |thread| {
        thread.join();
        target.os_thread = null;
    }

    target.frame_count = 0;

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const fiber_obj = types.toObject(fiber_val);

    // Remove the thunk and fiber from extra_roots (added by thread-start!
    // to keep them alive while the child runs; the child is done now).
    for (gc.extra_roots.items, 0..) |v, idx| {
        if (v == target.thunk) {
            _ = gc.extra_roots.swapRemove(idx);
            break;
        }
    }
    for (gc.extra_roots.items, 0..) |v, idx| {
        if (v == fiber_val) {
            _ = gc.extra_roots.swapRemove(idx);
            break;
        }
    }
    const fiber_key = @intFromPtr(target);

    // Retrieve result/exception from child_registry (stored there to
    // avoid the parent GC traversing child-heap pointers via the fiber).
    if (child_registry.get(fiber_key)) |res| {
        if (target.status == .completed and res.result != types.VOID) {
            target.result = gc.deepCopy(res.result) catch |err| {
                target.result = types.VOID;
                freeChildResources(fiber_key);
                if (err == error.UncopyableType) {
                    return raiseError(.general, "thread-join!: result contains uncopyable type (port, continuation, etc.)", types.VOID);
                }
                return PrimitiveError.OutOfMemory;
            };
            gc.writeBarrier(fiber_obj, target.result);
        }
        if (target.status == .errored) {
            if (res.exception) |exc| {
                target.current_exception = gc.deepCopy(exc) catch null;
                if (target.current_exception) |cv|
                    gc.writeBarrier(fiber_obj, cv);
            }
        }
    }
    freeChildResources(fiber_key);
    return threadJoinResult(target);
}

fn freeChildResources(fiber_key: usize) void {
    if (child_registry.fetchRemove(fiber_key)) |res| {
        const allocator = res.child_gc.allocator;
        res.child_vm.deinit();
        allocator.destroy(res.child_vm);
        res.child_gc.deinit();
        allocator.destroy(res.child_gc);
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
            // Fiber 0 is the main fiber: finishing or aborting one top-level
            // form is not thread death, so its mutexes stay valid.
            if (next_idx != 0) {
                if (memory.gc_instance) |gc| abandonFiberMutexes(gc, fiber, sched);
            }
            sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        if (memory.gc_instance) |gc| {
            gc.writeBarrier(&fiber.header, result);
            if (next_idx != 0) abandonFiberMutexes(gc, fiber, sched);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    return types.VOID;
}

fn mutexStateFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-state", "mutex", args[0]);
    const m = types.toMutex(args[0]);
    if (!m.locked) {
        if (m.abandoned) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            return gc.allocSymbol("abandoned") catch return PrimitiveError.OutOfMemory;
        }
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return gc.allocSymbol("not-abandoned") catch return PrimitiveError.OutOfMemory;
    }
    if (m.owner != types.VOID) return m.owner;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
            // Fiber 0 is the main fiber: finishing or aborting one top-level
            // form is not thread death, so its mutexes stay valid.
            if (next_idx != 0) {
                if (memory.gc_instance) |gc| abandonFiberMutexes(gc, fiber, sched);
            }
            sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        if (memory.gc_instance) |gc| {
            gc.writeBarrier(&fiber.header, result);
            if (next_idx != 0) abandonFiberMutexes(gc, fiber, sched);
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
            // Fiber 0 is the main fiber: finishing or aborting one top-level
            // form is not thread death, so its mutexes stay valid.
            if (next_idx != 0) {
                if (memory.gc_instance) |gc| abandonFiberMutexes(gc, fiber, sched);
            }
            sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        if (memory.gc_instance) |gc| {
            gc.writeBarrier(&fiber.header, result);
            if (next_idx != 0) abandonFiberMutexes(gc, fiber, sched);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
