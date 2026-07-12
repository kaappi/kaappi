const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
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
    // wasm: the one SRFI-18 entry point with no OS-thread dependency that
    // KEP-0001 Phase 4 needs Scheme-visible — it parks the current fiber
    // on the reactor's timer heap, which the WASI backend waits out with a
    // poll_oneoff CLOCK subscription. Registered as a global only; the
    // (srfi 18) library itself stays unavailable on WASM.
    .{ .name = "thread-sleep!", .func = &threadSleepFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = true },
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
    .{ .name = "time->seconds", .func = &timeToSecondsFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "seconds->time", .func = &secondsToTimeFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "join-timeout-exception?", .func = &joinTimeoutPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "abandoned-mutex-exception?", .func = &abandonedMutexPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "terminated-thread-exception?", .func = &terminatedThreadPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "uncaught-exception?", .func = &uncaughtExceptionPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
    .{ .name = "uncaught-exception-reason", .func = &uncaughtExceptionReasonFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_18), .sandbox = false, .wasm = false },
};

/// The `.wasm = true` subset of `specs`, what primitives.zig registers on
/// wasm32-wasi (KEP-0001 Phase 4). Filtered at comptime so the WASM
/// build's spec table never references the OS-thread functions: a
/// function pointer in runtime data forces codegen of its body, and
/// std.Thread.spawn (threadStartFn) is a compile error single-threaded.
pub const wasm_specs = blk: {
    var count: usize = 0;
    for (specs) |s| {
        if (s.wasm) count += 1;
    }
    var out: [count]primitives.PrimSpec = undefined;
    var i: usize = 0;
    for (specs) |s| {
        if (s.wasm) {
            out[i] = s;
            i += 1;
        }
    }
    break :blk out;
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

/// Thin per-file convenience wrapper: fetches vm_instance and delegates to
/// fiber.ensureScheduler, which now lazily creates the reactor alongside
/// the scheduler (KEP-0001 Phase 2) — the actual setup logic lives in one
/// place instead of being duplicated per call site.
fn ensureScheduler() @TypeOf(fiber_mod.ensureScheduler(undefined)) {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    return fiber_mod.ensureScheduler(vm);
}

// 1ms, matching thread-join!'s existing OS-thread poll cadence.
const CROSS_THREAD_POLL_NS: u64 = 1_000_000;

// Number of thread-start!-spawned OS threads currently alive (incremented in
// threadStartFn, decremented via defer in threadEntryFn on every exit path).
// Lets crossThreadWaitPossible tell a real cross-OS-thread wait apart from a
// genuine local deadlock -- see its comment.
var live_child_threads: usize = 0;

// True when some *other* OS thread could plausibly still change the mutex/
// condvar state this scheduler is blocked on, so polling (instead of
// accepting runSchedulerStep's "done == false" as a genuine deadlock) might
// eventually pay off:
//   - A spawned child thread's own scheduler (vm.owns_globals == false) may
//     always be waiting on the main thread, which is "alive" for as long as
//     the process runs -- always poll.
//   - The main thread's scheduler only has something to gain from polling
//     if at least one child thread currently exists to possibly unlock/
//     signal from the outside; with none, runSchedulerStep reporting "not
//     done" is a real, unrecoverable local deadlock (fiber.zig's
//     parkOnReactor already found nothing locally runnable and no pending
//     timer/fd event).
//
// Asymmetry this creates: a child thread that manages to genuinely
// self-deadlock (e.g. waits on a mutex only it could ever unlock) now polls
// forever rather than raising the deadlock error runSchedulerStep's "not
// done" normally produces, since it always assumes the main thread might
// still help -- indefinite blocking here is conformant with SRFI-18, but the
// same shape of deadlock hangs on a child thread and errors on the main
// thread, which is worth knowing when debugging one.
fn crossThreadWaitPossible() bool {
    const vm = vm_mod.vm_instance orelse return false;
    if (!vm.owns_globals) return true;
    return @atomicLoad(usize, &live_child_threads, .acquire) > 0;
}

fn timeoutToDeadlineNs(timeout: Value) PrimitiveError!?u64 {
    if (timeout == types.FALSE) return null;
    if (types.isSrfi18Time(timeout)) {
        const t = types.toSrfi18Time(timeout);
        if (t.seconds < 0) return 0;
        const ns_clamped: u64 = if (t.nanoseconds > 0) @intCast(t.nanoseconds) else 0;
        const sec_ns: u64 = @as(u64, @intCast(t.seconds)) * 1_000_000_000 + ns_clamped;
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

// ---------------------------------------------------------------------------
// Thread primitives
// ---------------------------------------------------------------------------

fn currentThreadFn(_: []const Value) PrimitiveError!Value {
    const ctx = try ensureScheduler();
    const fiber = ctx.vm.current_fiber orelse return types.VOID;
    return types.makePointer(@ptrCast(&fiber.header));
}

fn threadPredFn(args: []const Value) PrimitiveError!Value {
    return if (types.isFiber(args[0])) types.TRUE else types.FALSE;
}

fn makeThreadFn(args: []const Value) PrimitiveError!Value {
    const thunk = args[0];
    if (!types.isProcedure(thunk))
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

    return types.makePointer(@ptrCast(&fiber.header));
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
    // Unregistered on WASM (spec .wasm = false) but the body must still
    // compile there: the comptime spec-table filter (wasm_specs) evaluates
    // the full `specs` array, which analyzes every referenced function.
    // The else-branch is what keeps std.Thread.spawn out of the
    // single-threaded wasm32 build — only the taken branch of a
    // comptime-known if is analyzed.
    if (comptime is_wasm) return PrimitiveError.TypeError else return threadStartImpl(args);
}

fn threadStartImpl(args: []const Value) PrimitiveError!Value {
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
    // Increment *before* spawning: if the child ran to completion before an
    // increment placed after std.Thread.spawn executed, the decrement in
    // threadEntryFn's defer could fire first and wrap the counter (or drop
    // it one below the true count with other children alive), letting
    // crossThreadWaitPossible wrongly conclude no other thread exists.
    _ = @atomicRmw(usize, &live_child_threads, .Add, 1, .release);
    fiber.os_thread = std.Thread.spawn(.{}, threadEntryFn, .{
        fiber, gc.allocator, gc, vm,
    }) catch {
        _ = @atomicRmw(usize, &live_child_threads, .Sub, 1, .release);
        return PrimitiveError.OutOfMemory;
    };

    return args[0];
}

fn threadEntryFn(fiber: *fiber_mod.Fiber, allocator: std.mem.Allocator, parent_gc: *memory.GC, parent_vm: *vm_mod.VM) void {
    // Balances the increment in threadStartFn on every exit path (including
    // the early GC/VM-init failures below), so crossThreadWaitPossible's "is
    // another OS thread still alive" check stays accurate.
    defer _ = @atomicRmw(usize, &live_child_threads, .Sub, 1, .release);
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
        if (child_vm.current_fiber) |cf| fiber_mod.abandonFiberMutexes(child_gc, cf, child_vm.scheduler);
        child_registry.storeResult(@intFromPtr(fiber), types.VOID, child_vm.current_exception);
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };

    if (child_vm.current_fiber) |cf| fiber_mod.abandonFiberMutexes(child_gc, cf, child_vm.scheduler);

    // Store result in child_resources (not on the fiber) so the parent
    // GC never traverses a child-heap pointer (Race C).
    child_registry.storeResult(@intFromPtr(fiber), result, null);
    @atomicStore(fiber_mod.FiberStatus, &fiber.status, .completed, .release);
}

fn threadYieldFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const sched = vm.scheduler orelse {
        std.Thread.yield() catch {};
        return types.VOID;
    };
    // Advisory, like yield in primitives_fiber.zig: arming Yielded under a
    // re-entrant native frame corrupts the signal into a bare "error" (#1184),
    // so yield only when the unwind can reach a scheduler dispatch loop and
    // another fiber is actually runnable.
    if (vm.native_reentry_depth > 0) return types.VOID;
    if (sched.schedule() == null) return types.VOID;
    vm.yielded = true;
    return types.VOID;
}

const SleepWait = struct {
    pub fn isDone(_: SleepWait) bool {
        return false; // a pure sleep only ever ends via me.timed_out
    }
};

/// A timed park on the reactor's timer heap instead of a whole-thread
/// nanosleep (KEP-0001 Phase 2): siblings run while this fiber sleeps, and
/// the reactor's blocking wait — not a busy nanosleep loop — is what
/// actually waits out the duration.
///
/// Gives this the same `dispatched_from_scheduler`-aware yield-retry branch
/// `fiber.waitForFd` has (#1463): a fiber dispatched directly by a scheduler
/// loop must unwind flatly (`error.Yielded`) rather than nest a recursive
/// `runSchedulerStep` call, or concurrent fibers each retrying via short
/// `thread-sleep!` calls grow the native stack without bound. Unlike a read
/// primitive, thread-sleep! has no buffer to stash partial progress in —
/// the equivalent state is `me.deadline_ns`/`me.timed_out` on the fiber
/// itself, which (unlike the Scheme-level `seconds` argument) survives the
/// unwind. The `me.deadline_ns != null` check on entry distinguishes a
/// fresh call from a redispatch after yielding, so a retry consumes the
/// existing timer instead of computing a new deadline and restarting the
/// sleep on every redispatch.
fn threadSleepFn(args: []const Value) PrimitiveError!Value {
    if (args[0] == types.FALSE) return PrimitiveError.TypeError; // bare-ok: type guard

    const ctx = try ensureScheduler();
    const me = ctx.vm.current_fiber orelse return types.VOID;
    const my_idx = ctx.sched.current_idx;

    if (me.deadline_ns == null) {
        const seconds = try getSleepSeconds(args[0]);
        if (seconds <= 0) return types.VOID;
        const total_ns: u64 = @intFromFloat(@max(0.0, seconds * 1e9));
        const deadline = fiber_mod.clockNs() + total_ns;

        me.waiting_on = types.VOID;
        me.status = .waiting;
        me.timed_out = false;
        me.deadline_ns = deadline;
        // OOM below (addTimer or runSchedulerStep's own allocations) would
        // otherwise leave deadline_ns set with no timer actually pending --
        // the next thread-sleep! call on this fiber would then misread its
        // fresh call as a redispatch and wait on a stale deadline forever.
        // error.Yielded is not a real error here (it's the intentional
        // flat-unwind signal the deadline_ns discriminator exists to
        // survive), so it must not trip this cleanup.
        errdefer |err| if (err != PrimitiveError.Yielded) {
            me.deadline_ns = null;
            ctx.reactor.removeTimer(me);
        };
        try ctx.reactor.addTimer(deadline, me);
    } else if (me.timed_out) {
        // Redispatched after the timer we armed on a prior entry already
        // fired -- nothing left to wait for.
        me.timed_out = false;
        me.deadline_ns = null;
        return types.VOID;
    }

    if (my_idx != 0 and ctx.vm.dispatched_from_scheduler) {
        ctx.vm.yield_retry = true;
        return PrimitiveError.Yielded;
    }

    _ = try fiber_mod.runSchedulerStep(SleepWait, .{}, ctx.vm, ctx.sched, me);
    me.timed_out = false;
    me.deadline_ns = null;
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
        const target: f64 = @as(f64, @floatFromInt(t.seconds)) + @as(f64, @floatFromInt(t.nanoseconds)) / 1e9;
        return target - now;
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

    if (memory.gc_instance) |gc| fiber_mod.abandonFiberMutexes(gc, fiber, ctx.sched);

    const status = @atomicLoad(fiber_mod.FiberStatus, &fiber.status, .acquire);
    if (status != .completed and status != .errored) {
        // A terminated fiber may have been mid-timed-wait (mutex-lock!,
        // thread-join!, condvar wait, thread-sleep!) with a pending entry
        // on the reactor's timer heap. Cancel it now — otherwise it fires
        // later against whatever fiber ends up reusing this slot. Likewise
        // an io_waiting fiber (a parked port read/write, KEP-0001 Phase 3)
        // still sits in the reactor's fd waiter lists; pull it out so the
        // dead fiber can't linger there as a stale registration.
        ctx.reactor.removeTimer(fiber);
        if (fiber.io_fd) |io_fd| {
            ctx.reactor.removeWaiter(io_fd, fiber);
            fiber.io_fd = null;
        }
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
        if (deadline_ns) |d| {
            me.deadline_ns = d;
            try ctx.reactor.addTimer(d, me);
        }

        const done = try fiber_mod.runSchedulerStep(fiber_mod.TargetWait, .{ .target = target }, ctx.vm, ctx.sched, me);
        me.deadline_ns = null;

        if (me.timed_out) {
            me.timed_out = false;
            if (has_timeout_val) return timeout_val;
            return raiseError(.join_timeout, "thread-join! timed out", types.VOID);
        }
        if (!done) {
            // Genuine deadlock: parkOnReactor gave up because nothing local
            // could ever complete the joined fiber. Must not fall through
            // to threadJoinResult, which would silently return VOID (the
            // target's never-set default result) instead of erroring.
            // me.waiting_on (not args[0]): args is a slice into
            // vm.registers, which runSchedulerStep may have reallocated.
            return raiseError(.general, "thread-join!: deadlock — joined fiber can never complete (all fibers blocked)", me.waiting_on);
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
    if (!@atomicLoad(bool, &m.locked, .acquire)) {
        if (@atomicLoad(bool, &m.abandoned, .acquire)) {
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

// The fiber/thread that resolves to be recorded as a mutex's new owner: an
// explicit fiber (args[2]), explicitly "unowned" (args[2] == #f), or the
// caller's own current fiber.
fn resolveMutexOwner(args: []const Value, fallback: Value) Value {
    if (args.len > 2 and types.isFiber(args[2])) return args[2];
    if (args.len > 2 and args[2] == types.FALSE) return types.VOID;
    return fallback;
}

// Atomically claims the mutex (false -> true). This is the single point of
// arbitration between racing threads -- a plain load-then-store lets two
// threads both observe "unlocked" and both believe they've acquired it,
// corrupting mutual exclusion. Load-bearing now that cross-thread mutex
// contention is a supported, polled-for wait (see crossThreadWaitPossible)
// rather than something that resolved (buggily) on the first check.
fn tryClaimMutex(m: *types.Mutex) bool {
    return @cmpxchgStrong(bool, &m.locked, false, true, .acq_rel, .acquire) == null;
}

// Atomically claims (and clears) an abandoned flag. Only meaningful once
// the caller has already won tryClaimMutex: it decides whether *this*
// acquisition should also raise abandoned-mutex-exception, without letting
// a second racing acquirer also see and report the same abandonment.
fn tryClaimAbandoned(m: *types.Mutex) bool {
    return @cmpxchgStrong(bool, &m.abandoned, true, false, .acq_rel, .acquire) == null;
}

fn mutexLockFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-lock!", "mutex", args[0]);

    const m = types.toMutex(args[0]);

    if (tryClaimMutex(m)) {
        const ctx = try ensureScheduler();
        m.owner = resolveMutexOwner(args, if (ctx.vm.current_fiber) |cf| types.makePointer(@ptrCast(&cf.header)) else types.VOID);
        if (memory.gc_instance) |gc| gc.writeBarrier(&m.header, m.owner);
        if (tryClaimAbandoned(m)) return raiseError(.abandoned_mutex, "mutex was abandoned", types.VOID);
        return types.TRUE;
    }

    var deadline: ?u64 = null;
    if (args.len > 1) {
        deadline = try timeoutToDeadlineNs(args[1]);
        if (deadline != null and deadline.? == 0) return types.FALSE;
    }

    // Capture before the recursive dispatch below: args is a slice into
    // vm.registers, which runSchedulerStep can reallocate out from under
    // it while running other fibers (ensureRegisterCapacity). Reading
    // args[...] after that point would be a use-after-free.
    const mutex_val = args[0];
    const owner_arg: ?Value = if (args.len > 2) args[2] else null;

    const ctx = try ensureScheduler();
    const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;

    me.waiting_on = mutex_val;
    me.status = .waiting;
    me.timed_out = false;
    if (deadline) |d| {
        me.deadline_ns = d;
        try ctx.reactor.addTimer(d, me);
    }

    // runSchedulerStep only returns done once it *observes* m.locked ==
    // false; claiming it is still a race against any other thread making
    // the same observation, so retry the claim and go back to waiting on
    // failure instead of assuming we won. When runSchedulerStep reports
    // "not done" (parkOnReactor found nothing locally runnable and no
    // pending timer/fd event), that's only a genuine deadlock if no other
    // OS thread could plausibly still unlock this mutex from the outside —
    // otherwise poll briefly and retry.
    while (true) {
        const done = try fiber_mod.runSchedulerStep(MutexWait, .{ .m = m }, ctx.vm, ctx.sched, me);
        if (me.timed_out) {
            me.timed_out = false;
            me.deadline_ns = null;
            return types.FALSE;
        }
        if (done) {
            if (tryClaimMutex(m)) break;
            // A local wake (the usual way runSchedulerStep reports "done")
            // cancels me's pending reactor timer via cancelPendingTimer.
            // Losing the claim race here means we're going back to waiting
            // with the timer gone but me.deadline_ns still set -- re-add it
            // (remove-first keeps this idempotent) or a timed mutex-lock!
            // could block past its deadline, in the worst case unboundedly
            // if crossThreadWaitPossible later turns false with no timer
            // left to bound parkOnReactor's blocking wait.
            if (deadline) |d| {
                ctx.reactor.removeTimer(me);
                try ctx.reactor.addTimer(d, me);
            }
            me.status = .waiting;
            continue;
        }
        if (!crossThreadWaitPossible()) {
            if (deadline != null) ctx.reactor.removeTimer(me);
            me.deadline_ns = null;
            return raiseError(.general, "mutex-lock!: deadlock — mutex will never be released (all fibers blocked)", types.VOID);
        }
        sleepNs(CROSS_THREAD_POLL_NS);
        // Same timer restoration as above: a local wake earlier in this
        // loop (see the `done` branch) may have already canceled the
        // timer, and that state persists into this branch too.
        if (deadline) |d| {
            ctx.reactor.removeTimer(me);
            try ctx.reactor.addTimer(d, me);
        }
        me.status = .waiting;
    }
    // A cross-thread resolution never runs local wake bookkeeping (the
    // unlocking thread's scheduler/reactor doesn't even know `me` exists),
    // so any timer registered above may still be pending; a local wake
    // already canceled it (removeTimer is a no-op then), but skipping this
    // for the cross-thread path would leave a stale entry that could later
    // fire against a reused fiber slot.
    if (deadline != null) ctx.reactor.removeTimer(me);
    me.deadline_ns = null;

    m.owner = if (owner_arg) |oa|
        (if (types.isFiber(oa)) oa else if (oa == types.FALSE) types.VOID else types.makePointer(@ptrCast(&me.header)))
    else
        types.makePointer(@ptrCast(&me.header));
    if (memory.gc_instance) |gc| gc.writeBarrier(&m.header, m.owner);

    if (tryClaimAbandoned(m)) return raiseError(.abandoned_mutex, "mutex was abandoned", types.VOID);
    return types.TRUE;
}

const MutexWait = struct {
    m: *types.Mutex,
    pub fn isDone(self: MutexWait) bool {
        return !@atomicLoad(bool, &self.m.locked, .acquire);
    }
    // Caps parkOnReactor's blocking wait so a long real timeout (registered
    // separately on `me`) can't make it block for the whole duration on the
    // offhand chance the mutex is unlocked by another OS thread sooner --
    // that thread's own scheduler has no way to signal this one directly.
    // See crossThreadWaitPossible's doc comment for when this applies.
    pub fn pollCapNs(self: MutexWait) ?u64 {
        _ = self;
        return if (crossThreadWaitPossible()) CROSS_THREAD_POLL_NS else null;
    }
};

fn mutexUnlockFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-unlock!", "mutex", args[0]);

    const m = types.toMutex(args[0]);
    const has_cv = args.len > 1 and types.isConditionVariable(args[1]);

    // Snapshot the condvar's signal generation *before* releasing the mutex,
    // while we still exclusively hold it. Per the SRFI-18 protocol, any
    // signaler must acquire this same mutex before calling
    // condition-variable-signal!/-broadcast!, so it cannot have bumped the
    // generation yet -- snapshotting after the unlock would race a signaler
    // that acquires the mutex in the gap and produce a lost wakeup (the
    // waiter would then wait for a *second* signal that may never come).
    const cv: ?*types.ConditionVariable = if (has_cv) types.toConditionVariable(args[1]) else null;
    const start_gen: u64 = if (cv) |c| loadSignalGeneration(c) else 0;

    // Clear owner *before* the release-store: otherwise a cross-thread
    // acquirer that wins the locked CAS right after the store below could
    // write its own owner, and this line would then stomp it back to VOID.
    m.owner = types.VOID;
    @atomicStore(bool, &m.locked, false, .release);

    const ctx = try ensureScheduler();
    ctx.sched.wakeMutexWaiters(args[0]);

    if (cv) |c| {
        var deadline: ?u64 = null;
        if (args.len > 2) {
            deadline = try timeoutToDeadlineNs(args[2]);
        }

        const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;
        me.waiting_on = args[1];
        me.status = .waiting;
        me.timed_out = false;
        if (deadline) |d| {
            me.deadline_ns = d;
            try ctx.reactor.addTimer(d, me);
        }

        // Each OS thread owns an independent FiberScheduler, so
        // condition-variable-signal!/-broadcast! called on *another*
        // thread only wakes fibers local to that thread's own scheduler
        // (me.status never changes) -- the generation bump in
        // CondVarWait.isDone is what a cross-thread waiter actually relies
        // on. When runSchedulerStep reports "not done", poll and retry
        // instead of treating it as a genuine deadlock whenever another OS
        // thread could plausibly still signal from the outside.
        while (true) {
            const done = try fiber_mod.runSchedulerStep(CondVarWait, .{ .me = me, .cv = c, .start_gen = start_gen }, ctx.vm, ctx.sched, me);
            if (me.timed_out) {
                me.timed_out = false;
                me.deadline_ns = null;
                return types.FALSE;
            }
            if (done) break;
            if (!crossThreadWaitPossible()) {
                if (deadline != null) ctx.reactor.removeTimer(me);
                me.deadline_ns = null;
                return raiseError(.general, "mutex-unlock!: deadlock — condition variable will never be signaled (all fibers blocked)", types.VOID);
            }
            sleepNs(CROSS_THREAD_POLL_NS);
            me.status = .waiting;
        }
        // See the matching comment in mutexLockFn: a cross-thread signal
        // never runs local wake bookkeeping, so any timer registered above
        // may still be pending (a local wake already canceled it --
        // removeTimer is then a no-op).
        if (deadline != null) ctx.reactor.removeTimer(me);
        me.deadline_ns = null;
        return types.TRUE;
    }

    return types.TRUE;
}

/// signal_generation is a u64 and wasm32 has no 64-bit atomics; the WASM
/// build is single-threaded, so a plain load is equivalent there. Only the
/// taken branch of the comptime if is analyzed, keeping @atomicLoad(u64)
/// out of the wasm32 build.
fn loadSignalGeneration(cv: *types.ConditionVariable) u64 {
    if (comptime is_wasm) {
        return cv.signal_generation;
    } else {
        return @atomicLoad(u64, &cv.signal_generation, .acquire);
    }
}

/// See loadSignalGeneration for why WASM takes the plain-access branch.
fn bumpSignalGeneration(cv: *types.ConditionVariable) void {
    if (comptime is_wasm) {
        cv.signal_generation +%= 1;
    } else {
        _ = @atomicRmw(u64, &cv.signal_generation, .Add, 1, .release);
    }
}

const CondVarWait = struct {
    me: *fiber_mod.Fiber,
    cv: *types.ConditionVariable,
    start_gen: u64,
    pub fn isDone(self: CondVarWait) bool {
        return self.me.status != .waiting or
            loadSignalGeneration(self.cv) != self.start_gen;
    }
    // See MutexWait.pollCapNs.
    pub fn pollCapNs(self: CondVarWait) ?u64 {
        _ = self;
        return if (crossThreadWaitPossible()) CROSS_THREAD_POLL_NS else null;
    }
};

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
    // Bump the generation so a waiter parked on a different OS thread's
    // scheduler (which never sees the local wake above) can poll for this.
    bumpSignalGeneration(types.toConditionVariable(args[0]));
    return types.VOID;
}

fn condvarBroadcastFn(args: []const Value) PrimitiveError!Value {
    if (!types.isConditionVariable(args[0]))
        return primitives.typeError("condition-variable-broadcast!", "condition-variable", args[0]);
    const ctx = try ensureScheduler();
    ctx.sched.wakeAllCondVarWaiters(args[0]);
    bumpSignalGeneration(types.toConditionVariable(args[0]));
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Time primitives
// ---------------------------------------------------------------------------

fn currentTimeFn(_: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    return gc.allocSrfi18Time(@intCast(ts.sec), @intCast(ts.nsec), .utc) catch return PrimitiveError.OutOfMemory;
}

fn timeToSecondsFn(args: []const Value) PrimitiveError!Value {
    if (!types.isSrfi18Time(args[0]))
        return primitives.typeError("time->seconds", "time", args[0]);
    const t = types.toSrfi18Time(args[0]);
    return types.makeFlonum(@as(f64, @floatFromInt(t.seconds)) + @as(f64, @floatFromInt(t.nanoseconds)) / 1_000_000_000.0);
}

fn secondsToTimeFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const secs = primitives.toF64(args[0]) catch
        return primitives.typeError("seconds->time", "number", args[0]);
    const int_secs = @as(i64, @intFromFloat(@floor(secs)));
    const frac = secs - @floor(secs);
    const ns = @as(i64, @intFromFloat(@round(frac * 1_000_000_000.0)));
    return gc.allocSrfi18Time(int_secs, ns, .utc) catch return PrimitiveError.OutOfMemory;
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
