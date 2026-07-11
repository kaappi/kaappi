const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const memory = @import("memory.zig");
const reactor_mod = @import("reactor.zig");
const Reactor = reactor_mod.Reactor;
const Value = types.Value;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const CallFrame = types.CallFrame;

pub fn clockNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

pub const FiberStatus = enum(u8) {
    created,
    running,
    suspended,
    completed,
    errored,
    waiting,
    io_waiting,
};

pub const Fiber = struct {
    header: types.Object,
    registers: []Value,
    frames: []CallFrame,
    frame_count: usize,
    handler_stack: [types.MAX_HANDLERS]types.ExceptionHandler,
    handler_count: usize,
    wind_stack: [types.MAX_WINDS]types.WindRecord,
    wind_count: usize,
    current_exception: ?Value,
    continuation_invoked: bool,
    continuation_value: Value,
    status: FiberStatus,
    thunk: Value,
    result: Value,
    waiting_on: Value,
    id: u32,
    name: Value = types.VOID,
    specific: Value = types.VOID,
    param_overrides: std.AutoHashMap(usize, Value),
    deadline_ns: ?u64 = null,
    timed_out: bool = false,
    terminated: bool = false,
    os_thread: ?std.Thread = null,
    /// Set together with `.io_waiting` when a blocking I/O primitive parks
    /// on the reactor (KEP-0001 Phase 3). Unused by anything shipped in
    /// Phase 2, but the fields must exist now so the scheduler/GC plumbing
    /// can be built and tested ahead of the port-layer primitives.
    io_fd: ?std.posix.fd_t = null,
    io_interest: reactor_mod.Interest = .read,
    /// Pins an in-flight read/write buffer across GC while a primitive is
    /// parked on the reactor. Traced by markFiberState/referencesYoung.
    io_buffer: Value = types.VOID,
};

pub const FiberScheduler = struct {
    /// Growable — no fiber-count ceiling (KEP-0001 Phase 2). Slots are
    /// reused before growing (see addFiber), so long-running spawn/join
    /// churn doesn't grow this unboundedly; concurrently-live fiber count
    /// is bounded only by memory.
    fibers: std.ArrayList(?*Fiber),
    current_idx: usize,
    next_id: u32,
    vm: *VM,

    pub fn init(vm: *VM) FiberScheduler {
        return .{
            .fibers = .empty,
            .current_idx = 0,
            .next_id = 0,
            .vm = vm,
        };
    }

    pub fn deinit(self: *FiberScheduler, allocator: std.mem.Allocator) void {
        self.fibers.deinit(allocator);
    }

    pub fn addFiber(self: *FiberScheduler, fiber: *Fiber) !void {
        for (self.fibers.items, 0..) |f, i| {
            if (f) |existing| {
                if (existing.status == .completed or existing.status == .errored) {
                    self.fibers.items[i] = fiber;
                    return;
                }
            } else {
                self.fibers.items[i] = fiber;
                return;
            }
        }
        try self.fibers.append(self.vm.gc.allocator, fiber);
    }

    pub fn spawnFiber(self: *FiberScheduler, thunk: Value) !*Fiber {
        var thunk_val = thunk;
        self.vm.gc.pushRoot(&thunk_val);
        const fiber = try self.vm.gc.allocFiber(thunk_val, self.next_id);
        self.vm.gc.popRoot();
        self.next_id += 1;

        if (!types.isProcedure(thunk_val)) return VMError.NotAProcedure;

        var closure: *types.Closure = undefined;
        if (types.isClosure(thunk_val)) {
            closure = types.toObject(thunk_val).as(types.Closure);
        } else {
            var fiber_root = types.makePointer(@ptrCast(&fiber.header));
            self.vm.gc.pushRoot(&fiber_root);
            const trampoline = try wrapInTrampoline(self.vm.gc, thunk_val);
            self.vm.gc.popRoot();
            fiber.thunk = trampoline;
            self.vm.gc.writeBarrier(&fiber.header, trampoline);
            closure = types.toObject(trampoline).as(types.Closure);
        }

        @memset(fiber.registers, types.UNDEFINED);
        fiber.registers[0] = types.makePointer(@ptrCast(closure));
        fiber.frames[0] = .{
            .closure = closure,
            .code = closure.func.code.items,
            .ip = 0,
            .base = 0,
            .dst = 0,
            .saved_wind_count = 0,
            .seq = self.vm.nextFrameSeq(),
        };
        fiber.frame_count = 1;
        fiber.status = .created;

        // Inherit parent's parameter bindings
        const source = if (self.vm.current_fiber) |f| &f.param_overrides else &self.vm.param_overrides;
        var it = source.iterator();
        while (it.next()) |entry| {
            fiber.param_overrides.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }

        try self.addFiber(fiber);
        return fiber;
    }

    // Build a closure whose bytecode does: get_upvalue 1,0 ; call 1,0 ; return 1
    // Operand widths must match fixed_operand_bytes in vm_dispatch.zig.
    fn wrapInTrampoline(gc: *memory.GC, proc: Value) !Value {
        const OpCode = types.OpCode;
        const func = try gc.allocFunction();
        func.upvalue_count = 1;
        func.locals_count = 2;

        const code = &func.code;
        const alloc = gc.allocator;
        try code.append(alloc, @intFromEnum(OpCode.get_upvalue));
        try code.append(alloc, 0x00); // dst hi
        try code.append(alloc, 0x01); // dst lo = 1
        try code.append(alloc, 0x00); // idx hi
        try code.append(alloc, 0x00); // idx lo = 0

        try code.append(alloc, @intFromEnum(OpCode.call));
        try code.append(alloc, 0x00); // base hi
        try code.append(alloc, 0x01); // base lo = 1
        try code.append(alloc, 0x00); // nargs = 0

        try code.append(alloc, @intFromEnum(OpCode.@"return"));
        try code.append(alloc, 0x00); // src hi
        try code.append(alloc, 0x01); // src lo = 1

        var proc_root = proc;
        gc.pushRoot(&proc_root);
        const closure_val = try gc.allocClosure(func);
        gc.popRoot();
        const closure = types.toObject(closure_val).as(types.Closure);
        closure.upvalues[0] = proc_root;
        gc.writeBarrier(&closure.header, proc_root);
        return closure_val;
    }

    /// Upper bound (exclusive) of registers actually reachable from any
    /// currently active frame: max over `frames` of `base + frameWindow()`,
    /// clamped to `cap`. Shared by markFiberState (GC-marking bounds) and
    /// saveCurrentFiber/restoreFiber (memcpy bounds) — a register beyond
    /// every active frame's window can never be read again by the fiber
    /// that owns `frames`, so it's neither live for GC nor worth copying.
    fn liveRegisterSpan(frames: []const CallFrame, cap: usize) usize {
        var span: usize = 0;
        for (frames) |f| {
            const end: usize = @min(@as(usize, f.base) + f.frameWindow(), cap);
            if (end > span) span = end;
        }
        return span;
    }

    fn growFiberRegisters(allocator: std.mem.Allocator, fiber: *Fiber, needed: usize) VMError!void {
        if (needed <= fiber.registers.len) return;
        var new_cap = fiber.registers.len;
        while (new_cap < needed) new_cap *= 2;
        const new_regs = try allocator.alloc(Value, new_cap);
        allocator.free(fiber.registers);
        fiber.registers = new_regs;
    }

    fn growFiberFrames(allocator: std.mem.Allocator, fiber: *Fiber, needed: usize) VMError!void {
        if (needed <= fiber.frames.len) return;
        var new_cap = fiber.frames.len;
        while (new_cap < needed) new_cap *= 2;
        const new_frames = try allocator.alloc(CallFrame, new_cap);
        allocator.free(fiber.frames);
        fiber.frames = new_frames;
    }

    /// Copies only the live register/frame window (see liveRegisterSpan)
    /// instead of the VM's entire register file — fiber switch cost no
    /// longer scales with the VM's peak register-file capacity (KEP-0001
    /// Phase 2, resolved question 5).
    ///
    /// Propagates OOM instead of swallowing it: growFiberRegisters/Frames
    /// must actually succeed before the memcpy below runs at the new
    /// (larger) span, or the memcpy would read/write past a buffer that
    /// silently stayed its old, smaller size.
    pub fn saveCurrentFiber(self: *FiberScheduler) VMError!void {
        const fiber = self.fibers.items[self.current_idx] orelse return;
        const vm = self.vm;
        const span = liveRegisterSpan(vm.frames[0..vm.frame_count], vm.registers.len);
        try growFiberRegisters(vm.gc.allocator, fiber, span);
        try growFiberFrames(vm.gc.allocator, fiber, vm.frame_count);
        @memcpy(fiber.registers[0..span], vm.registers[0..span]);
        fiber.frame_count = vm.frame_count;
        @memcpy(fiber.frames[0..vm.frame_count], vm.frames[0..vm.frame_count]);
        @memcpy(fiber.handler_stack[0..vm.handler_count], vm.handler_stack[0..vm.handler_count]);
        fiber.handler_count = vm.handler_count;
        @memcpy(fiber.wind_stack[0..vm.wind_count], vm.wind_stack[0..vm.wind_count]);
        fiber.wind_count = vm.wind_count;
        fiber.current_exception = vm.current_exception;
        fiber.continuation_invoked = vm.continuation_invoked;
        fiber.continuation_value = vm.continuation_value;
    }

    pub fn restoreFiber(self: *FiberScheduler, idx: usize) VMError!void {
        const fiber = self.fibers.items[idx] orelse return;
        const vm = self.vm;
        const span = liveRegisterSpan(fiber.frames[0..fiber.frame_count], fiber.registers.len);
        try vm.ensureRegisterCapacity(span);
        try vm.ensureFrameCapacity(fiber.frame_count);
        @memcpy(vm.registers[0..span], fiber.registers[0..span]);
        @memcpy(vm.frames[0..fiber.frame_count], fiber.frames[0..fiber.frame_count]);
        vm.frame_count = fiber.frame_count;
        @memcpy(vm.handler_stack[0..fiber.handler_count], fiber.handler_stack[0..fiber.handler_count]);
        vm.handler_count = fiber.handler_count;
        @memcpy(vm.wind_stack[0..fiber.wind_count], fiber.wind_stack[0..fiber.wind_count]);
        vm.wind_count = fiber.wind_count;
        vm.current_exception = fiber.current_exception;
        vm.continuation_invoked = fiber.continuation_invoked;
        vm.continuation_value = fiber.continuation_value;
    }

    pub fn switchTo(self: *FiberScheduler, next_idx: usize) VMError!void {
        if (next_idx == self.current_idx) return;
        const current = self.fibers.items[self.current_idx] orelse return;

        try self.saveCurrentFiber();
        if (current.status == .running) current.status = .suspended;

        try self.restoreFiber(next_idx);
        const next = self.fibers.items[next_idx] orelse return;
        next.status = .running;
        self.current_idx = next_idx;
        self.vm.current_fiber = next;
    }

    /// Round-robins over `created`/`suspended` fibers. Before selecting,
    /// pops any already-expired timers off the reactor's heap and flips
    /// their fibers to `.suspended` — checked on *every* call, not just
    /// when the scheduler goes idle (parkOnReactor), so a timed wait
    /// resolves promptly even while a busy/yielding sibling keeps this
    /// loop from ever going idle (KEP-0001 Phase 2, resolved question 5:
    /// the old per-fiber sweep folds into the shared timer heap, but the
    /// heap must still be checked every tick — a heap peek/pop is cheaper
    /// than the old O(fiber count) sweep it replaces, not less prompt).
    pub fn schedule(self: *FiberScheduler) ?usize {
        if (self.vm.reactor) |reactor| {
            var expired: std.ArrayList(*Fiber) = .empty;
            defer expired.deinit(self.vm.gc.allocator);
            reactor.popExpiredTimers(&expired) catch {};
            for (expired.items) |f| wakeReadyFiber(f);
        }

        const n = self.fibers.items.len;
        if (n == 0) return null;
        var i: usize = 1;
        while (i <= n) : (i += 1) {
            const idx = (self.current_idx + i) % n;
            if (self.fibers.items[idx]) |f| {
                if (f.status == .created or f.status == .suspended) return idx;
            }
        }
        return null;
    }

    /// Used only by parkOnReactor's deadlock check, which runs after
    /// schedule() has already found nothing .created/.suspended — so this
    /// deliberately does NOT count .running: under recursive dispatch
    /// (runSchedulerStep calling runSchedulerStep), every fiber on the
    /// current call chain back to main is still .running (none flip to
    /// .waiting until they themselves decide to park), so treating .running
    /// as "other progress possible" would make a genuine deadlock loop
    /// forever in reactor.poll() instead of ever detecting it.
    pub fn hasRunnableFibers(self: *FiberScheduler) bool {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if (fiber.status == .created or fiber.status == .suspended)
                    return true;
                if (fiber.status == .waiting and fiber.deadline_ns != null)
                    return true;
                if (fiber.status == .io_waiting)
                    return true;
            }
        }
        return false;
    }

    fn cancelPendingTimer(self: *FiberScheduler, fiber: *Fiber) void {
        if (self.vm.reactor) |r| r.removeTimer(fiber);
    }

    pub fn wakeWaiters(self: *FiberScheduler, completed_fiber: *Fiber) void {
        const completed_val = types.makePointer(@ptrCast(&completed_fiber.header));
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == completed_val) {
                    fiber.status = .suspended;
                    fiber.result = completed_fiber.result;
                    self.vm.gc.writeBarrier(&fiber.header, completed_fiber.result);
                    self.cancelPendingTimer(fiber);
                }
            }
        }
    }

    /// Wake every fiber parked on this channel (status .waiting via the
    /// channel-receive retry protocol). Waking all is safe: each re-executes
    /// channel-receive and re-parks if the channel is empty again.
    pub fn wakeChannelWaiters(self: *FiberScheduler, ch_val: Value) void {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == ch_val) {
                    fiber.status = .suspended;
                    fiber.waiting_on = types.VOID;
                    self.cancelPendingTimer(fiber);
                }
            }
        }
    }

    pub fn wakeMutexWaiters(self: *FiberScheduler, mutex_val: Value) void {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == mutex_val) {
                    fiber.status = .suspended;
                    self.cancelPendingTimer(fiber);
                    return;
                }
            }
        }
    }

    pub fn wakeOneCondVarWaiter(self: *FiberScheduler, cv_val: Value) void {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == cv_val) {
                    fiber.status = .suspended;
                    self.cancelPendingTimer(fiber);
                    return;
                }
            }
        }
    }

    pub fn wakeAllCondVarWaiters(self: *FiberScheduler, cv_val: Value) void {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == cv_val) {
                    fiber.status = .suspended;
                    self.cancelPendingTimer(fiber);
                }
            }
        }
    }

    pub fn markRoots(self: *FiberScheduler, gc: *memory.GC) void {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                gc.markValue(types.makePointer(@ptrCast(&fiber.header)));
                if (fiber.status == .running) continue;
                markFiberState(gc, fiber);
            }
        }
    }
};

/// Lazily creates the scheduler and reactor together (one reactor per OS
/// thread, matching the share-nothing model — each SRFI-18 child thread
/// gets its own VM+GC+scheduler+reactor). All fiber/SRFI-18 entry points
/// that need a scheduler call this instead of duplicating the setup.
pub fn ensureScheduler(vm: *VM) VMError!struct { vm: *VM, sched: *FiberScheduler, reactor: *Reactor } {
    if (vm.scheduler == null) {
        const sched = vm.gc.allocator.create(FiberScheduler) catch return VMError.OutOfMemory;
        sched.* = FiberScheduler.init(vm);
        const main_fiber = vm.gc.allocFiber(types.VOID, sched.next_id) catch return VMError.OutOfMemory;
        sched.next_id += 1;
        main_fiber.status = .running;
        sched.addFiber(main_fiber) catch return VMError.OutOfMemory;
        vm.scheduler = sched;
        vm.current_fiber = main_fiber;
    }
    if (vm.reactor == null) {
        const r = vm.gc.allocator.create(Reactor) catch return VMError.OutOfMemory;
        r.* = Reactor.init(vm.gc.allocator) catch {
            vm.gc.allocator.destroy(r);
            return VMError.OutOfMemory;
        };
        vm.reactor = r;
    }
    return .{ .vm = vm, .sched = vm.scheduler.?, .reactor = vm.reactor.? };
}

/// Releases every mutex `fiber` holds, marking it abandoned and waking any
/// waiters — called whenever a dispatched (non-main) fiber errors out
/// mid-turn, so a lock it held doesn't hang every other fiber waiting on it
/// forever. Fiber 0 (main) is exempt at call sites: finishing or aborting
/// one top-level form is not thread death, so its mutexes stay valid.
pub fn abandonFiberMutexes(gc: *memory.GC, fiber: *Fiber, sched: ?*FiberScheduler) void {
    const fiber_val = types.makePointer(@ptrCast(&fiber.header));
    var lists = [_]?*types.Object{ gc.objects, gc.old_objects };
    for (&lists) |*head| {
        var obj = head.*;
        while (obj) |o| : (obj = o.next) {
            if (o.tag == .mutex) {
                const m = o.as(types.Mutex);
                if (@atomicLoad(bool, &m.locked, .acquire) and m.owner == fiber_val) {
                    // Order matters: abandoned and owner must both be
                    // published *before* the release-store below, so a
                    // cross-thread acquirer that wins the locked CAS is
                    // guaranteed to see them already updated (not stomp a
                    // fresh owner write with VOID, or miss the abandonment).
                    @atomicStore(bool, &m.abandoned, true, .release);
                    m.owner = types.VOID;
                    @atomicStore(bool, &m.locked, false, .release);
                    if (sched) |s| s.wakeMutexWaiters(types.makePointer(@ptrCast(o)));
                }
            }
        }
    }
}

/// Wait for `target` fiber to finish. Shared by fiber-join and
/// thread-join!'s fiber path — the exact same wait condition.
pub const TargetWait = struct {
    target: *Fiber,
    pub fn isDone(self: TargetWait) bool {
        return self.target.status == .completed or self.target.status == .errored;
    }
};

/// Moves a fiber the reactor just reported ready (io fd readiness or an
/// expired timer) from its wait status back to `.suspended` so schedule()
/// can pick it up. Shared by parkOnReactor (blocking wait) and schedule()'s
/// per-tick expired-timer check (non-blocking).
fn wakeReadyFiber(f: *Fiber) void {
    switch (f.status) {
        .io_waiting => f.status = .suspended,
        .waiting => {
            f.status = .suspended;
            f.timed_out = true;
        },
        else => {},
    }
}

/// Called when sched.schedule() finds nothing immediately runnable. Blocks
/// in the reactor — bounded by its own timer heap, so no separate
/// "nearest deadline" computation is needed here — and flips every fiber
/// it reports ready back to `.suspended` (io_waiting) or
/// `.suspended`+`timed_out` (an expired timed `.waiting` wait). Returns
/// `false` only when nothing could ever produce a wakeup: genuine
/// deadlock/done, the same meaning as the bare `break` this replaces.
pub fn parkOnReactor(vm: *VM, sched: *FiberScheduler) VMError!bool {
    const reactor = vm.reactor orelse return false;
    if (!sched.hasRunnableFibers() and reactor.isEmpty()) return false;

    var ready: std.ArrayList(*Fiber) = .empty;
    defer ready.deinit(vm.gc.allocator);
    reactor.poll(null, &ready) catch return VMError.OutOfMemory;

    for (ready.items) |f| wakeReadyFiber(f);
    return true;
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
/// typing), e.g. `TargetWait{ .target = f }`.
pub fn runSchedulerStep(comptime Ctx: type, ctx: Ctx, vm: *VM, sched: *FiberScheduler, me: *Fiber) VMError!bool {
    const my_idx = sched.current_idx;
    try sched.saveCurrentFiber();

    while (!ctx.isDone() and !me.timed_out) {
        const next_idx = sched.schedule() orelse {
            if (!(try parkOnReactor(vm, sched))) break;
            continue;
        };
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
                if (fiber.status == .running) fiber.status = .suspended;
                continue;
            }
            fiber.status = .errored;
            // Fiber 0 is the main fiber: finishing or aborting one
            // top-level form is not thread death, so its mutexes stay
            // valid.
            if (next_idx != 0) abandonFiberMutexes(vm.gc, fiber, sched);
            try sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        fiber.status = .completed;
        fiber.result = result;
        vm.gc.writeBarrier(&fiber.header, result);
        if (next_idx != 0) abandonFiberMutexes(vm.gc, fiber, sched);
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

pub fn markFiberState(gc: *memory.GC, fiber: *Fiber) void {
    gc.markValue(fiber.thunk);
    gc.markValue(fiber.result);
    gc.markValue(fiber.waiting_on);
    gc.markValue(fiber.name);
    gc.markValue(fiber.specific);

    for (fiber.frames[0..fiber.frame_count]) |f| {
        if (f.closure) |cls| gc.markValue(types.makePointer(@ptrCast(cls)));
        if (f.native) |nf| gc.markValue(types.makePointer(@ptrCast(nf)));
    }
    const span = FiberScheduler.liveRegisterSpan(fiber.frames[0..fiber.frame_count], fiber.registers.len);
    for (fiber.registers[0..span]) |r| gc.markValue(r);

    for (fiber.handler_stack[0..fiber.handler_count]) |h| gc.markValue(h.handler);

    for (fiber.wind_stack[0..fiber.wind_count]) |wr| {
        gc.markValue(wr.before);
        gc.markValue(wr.after);
    }

    var pit = fiber.param_overrides.valueIterator();
    while (pit.next()) |v| gc.markValue(v.*);

    if (fiber.current_exception) |exc| gc.markValue(exc);
    gc.markValue(fiber.continuation_value);
    gc.markValue(fiber.io_buffer);
}
