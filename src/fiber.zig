const std = @import("std");
const platform = @import("platform.zig");
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
    return platform.monotonicNs();
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
    /// True for the entire extent of a runSchedulerStep call this fiber
    /// itself invoked (set/cleared there, never by callers) -- i.e. this
    /// fiber's own native frame is still live on the Zig call stack,
    /// mid-nested-dispatch. scheduleForDispatch() and hasRunnableFibers()
    /// must never select/count such a fiber as an actual dispatch target,
    /// even if some wake function flips its `status` to .suspended while
    /// driving is true: since the whole scheduler runs on one OS thread, a
    /// fiber with driving == true is always an ancestor of whichever call
    /// is currently asking (it can only have gotten a nested dispatch by
    /// dispatching *something*, and that something's own call tree is what
    /// is presently executing) -- dispatching it from anywhere but its own
    /// loop would resume its bytecode from a stale, mid-native-call
    /// register snapshot with the destination register never written (see
    /// runSchedulerStep's doc comment; #1487). Ancestors can never make
    /// independent progress while a descendant is active regardless, so
    /// excluding them from dispatch changes no genuine liveness outcome --
    /// only the parked fiber's own loop ever consumes its wake. Plain
    /// schedule() (yieldFn/threadYieldFn's advisory check; vm_calls.zig's
    /// non-nested switchTo dispatch) deliberately does NOT exclude driving
    /// fibers -- see scheduleForDispatch's doc comment for why excluding
    /// them there too reproduces #1440's symptom by a different path.
    driving: bool = false,
    terminated: bool = false,
    os_thread: ?std.Thread = null,
    /// Set together with `.io_waiting` when a blocking I/O primitive parks
    /// on the reactor (KEP-0001 Phase 3). Unused by anything shipped in
    /// Phase 2, but the fields must exist now so the scheduler/GC plumbing
    /// can be built and tested ahead of the port-layer primitives.
    io_fd: ?platform.fd_t = null,
    io_interest: reactor_mod.Interest = .read,
    /// Pins an in-flight read/write buffer across GC while a primitive is
    /// parked on the reactor. Traced by markFiberState/referencesYoung.
    io_buffer: Value = types.VOID,
    /// This fiber's slot index in the owning FiberScheduler's `fibers` array.
    /// Stable for the fiber's whole lifetime — a fiber never migrates slots;
    /// its slot is only reused after it terminates (see addFiber/retireSlot).
    /// Lets the wake paths enqueue a fiber onto the ready ring in O(1) with no
    /// index search, which is the whole point of #1477. Meaningful only once
    /// addFiber has placed the fiber; a not-yet-scheduled fiber (e.g. a
    /// make-thread object) leaves it at the default.
    sched_idx: usize = 0,
    /// True iff this fiber's `sched_idx` is currently sitting in the
    /// scheduler's `ready` ring. Dedups markRunnable so one fiber can't
    /// accumulate duplicate ring entries; cleared when scheduleImpl consumes
    /// or discards the entry (#1477).
    queued: bool = false,
    /// Rendezvous demand token (KEP-0002 §6 as amended, kaappi#1601/#1602):
    /// the capacity-0 channel this fiber's parked receive has committed to,
    /// or VOID. Set (with a write barrier) when the receive's park decision
    /// increments the channel's `rv_demand`; makes that increment idempotent
    /// across the yield_retry re-execution of the whole primitive. Released
    /// — counter decrement + reset to VOID — on every terminal exit of the
    /// wait (value, eof, timeout, error) and on fiber death
    /// (releaseFiberRendezvousToken, the abandonFiberMutexes precedent).
    /// Traced by markFiberState/referencesYoung like `waiting_on`; unlike
    /// `waiting_on` it survives a wake (clear_waiting_on) until the retry
    /// exits, which is exactly why it needs independent tracing.
    rv_demand_on: Value = types.VOID,
    /// Mutexes this fiber currently owns (as `Value`s), maintained by
    /// mutex-lock! (#1458). `abandonFiberMutexes` walks this on fiber death
    /// instead of scanning a GC heap for owned mutexes — the mutex object may
    /// live in *another* thread's heap (shared via a top-level global), where
    /// a heap scan of the dying fiber's own heap would never find it. Only
    /// ever mutated on this fiber's owning thread; traced by markFiberState so
    /// a same-heap mutex held solely through this list stays alive (a foreign
    /// mutex is skipped by markValue's owner check and kept alive by its own
    /// heap's roots). Freed in freeObject's `.fiber` arm.
    owned_mutexes: std.ArrayList(Value) = .empty,
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
    /// KEP-0002 §5's per-scheduler shared-waiter registry -- see
    /// enrollSharedWaiter/sweepSharedWaiters below.
    shared_waiters: std.ArrayList(*Fiber),
    /// #1477: O(1) dispatch. A FIFO of fiber slot indices that are (or
    /// recently became) runnable, so scheduleImpl doesn't rescan the whole
    /// `fibers` array — dominated by parked io_waiting fibers on a busy
    /// server — to find the next runnable one. Purely an accelerator: it may
    /// hold stale or duplicate entries, all validated at pop (popReady);
    /// when it drains without a usable entry, scheduleImpl falls back to the
    /// authoritative O(n) scan, so a missed markRunnable only costs a rescan,
    /// never correctness. Consumed FIFO via a head cursor, compacted lazily.
    ready: std.ArrayList(usize),
    ready_head: usize,
    /// #1477: O(1) spawn. Slot indices vacated by a terminated fiber, pushed
    /// by retireSlot at every non-main .completed/.errored transition, so
    /// addFiber reuses a slot without scanning `fibers` for one. Because that
    /// coverage is comprehensive, an empty free list means no reusable slot
    /// exists and addFiber can append straight away instead of scanning
    /// (which is what made spawning N live fibers O(n^2)). Consumed FIFO
    /// (oldest-freed first, closest to the old scan's lowest-index-first
    /// order) via free_head, compacted lazily. Slot 0 (main) is never pushed.
    free_slots: std.ArrayList(usize),
    free_head: usize,
    /// #1530: O(waiters-on-object) wakes. Secondary index mapping a waited-on
    /// Value (a fiber to join, a channel, a mutex, a condition variable) to the
    /// slot indices of the fibers currently parked (`.waiting`) on it, so the
    /// wake paths (wakeWaiters/wakeChannelWaiters/wakeMutexWaiters/
    /// wakeOneCondVarWaiter/wakeAllCondVarWaiters) touch only the relevant
    /// waiters instead of rescanning every slot. Slot indices (not `*Fiber`)
    /// so a since-reused or since-terminated slot is caught by validation at
    /// wake time (like the ready ring's popReady) rather than dangling — a
    /// terminated waiter therefore needs no explicit de-index, unlike the
    /// pointer-holding shared_waiters registry. Enrolled by enrollWaiter at
    /// every local park site; consulted authoritatively (no fallback scan) by
    /// the wake paths, EXCEPT when degraded (see below). Only ever holds local
    /// waiters: a fiber parked on a *promoted* channel is woken through
    /// sweepSharedWaiters instead and is deliberately never enrolled here.
    waiter_index: std.AutoHashMap(Value, std.ArrayList(usize)),
    /// Sticky fallback switch (#1530). enrollWaiter allocates (a map entry and
    /// a list slot); if that ever OOMs, the just-parked fiber would be absent
    /// from `waiter_index` and an index-only wake could never find it — a
    /// lost-wakeup hang. Rather than fail the park (which would need per-site
    /// rollback of the timer/deadline state), enrollWaiter sets this flag and
    /// the wake paths permanently fall back to the pre-#1530 authoritative
    /// O(fiber count) scan. Post-OOM the VM is usually about to die anyway, so
    /// giving up the accelerator forever (rather than trying to recover it) is
    /// the responsible trade: worst case is exactly the old behavior.
    waiter_index_degraded: bool,
    /// #1625: the stack of runSchedulerStep drives currently live on this OS
    /// thread's Zig call stack, outermost first (each drive pushes on entry,
    /// pops on exit — strict LIFO). Every entry except the innermost belongs
    /// to an *ancestor*: a fiber frozen mid-dispatch whose own wait condition
    /// nothing announces — no wake path fires when a TargetWait's target
    /// completes for a fiber that is `driving` rather than `.waiting` — so
    /// the only way a descendant can learn "the wait pinned beneath me has
    /// resolved and only my unwinding can deliver it" is to evaluate the
    /// ancestor's own isDone through this type-erased view. Entries reference
    /// the drive's stack frame (`ctx` points into it) and are only ever read
    /// while that frame is alive, which the LIFO discipline guarantees.
    driving_waits: std.ArrayList(DrivingWait),

    /// One live runSchedulerStep drive, with its comptime-typed wait context
    /// erased so drives over different Ctx types can share one stack.
    const DrivingWait = struct {
        fiber: *Fiber,
        ctx: *const anyopaque,
        is_done: *const fn (*const anyopaque) bool,
    };

    pub fn init(vm: *VM) FiberScheduler {
        return .{
            .fibers = .empty,
            .current_idx = 0,
            .next_id = 0,
            .vm = vm,
            .shared_waiters = .empty,
            .ready = .empty,
            .ready_head = 0,
            .free_slots = .empty,
            .free_head = 0,
            .waiter_index = std.AutoHashMap(Value, std.ArrayList(usize)).init(vm.gc.allocator),
            .waiter_index_degraded = false,
            .driving_waits = .empty,
        };
    }

    pub fn deinit(self: *FiberScheduler, allocator: std.mem.Allocator) void {
        self.fibers.deinit(allocator);
        self.shared_waiters.deinit(allocator);
        self.ready.deinit(allocator);
        self.free_slots.deinit(allocator);
        var it = self.waiter_index.valueIterator();
        while (it.next()) |list| list.deinit(allocator);
        self.waiter_index.deinit();
        self.driving_waits.deinit(allocator);
    }

    /// True iff some *other* live drive on this OS thread — always an
    /// ancestor of the caller's, since drives nest strictly (#1487's
    /// reasoning) — would exit its loop if control returned to it: its wait
    /// condition is satisfied, or its timed wait expired (`timed_out` —
    /// a pure sleep resolves *only* this way, its isDone is constant
    /// false). Such an ancestor can consume its resolution only when the
    /// callers above it unwind: it is excluded from dispatch (`driving`),
    /// its loop is frozen mid-dispatch, and no wake path targets it. A
    /// descendant about to block unboundedly must check this first, or it
    /// wedges the whole thread on an event that may never come while the
    /// ancestor sits ready to proceed (#1625). Matching by fiber identity
    /// (not "skip the top entry") keeps the check independent of the
    /// list's push/pop bookkeeping.
    pub fn anyAncestorWaitResolved(self: *FiberScheduler, me: *Fiber) bool {
        for (self.driving_waits.items) |w| {
            if (w.fiber != me and (w.fiber.timed_out or w.is_done(w.ctx))) return true;
        }
        return false;
    }

    /// Shared lazy-compaction for the FIFO rings (`ready`, `free_slots`):
    /// once the consumed prefix (`head`) is at least as long as what remains,
    /// slide the tail down to the front so the backing array can't grow
    /// without bound under steady enqueue/dequeue churn.
    fn ringCompact(list: *std.ArrayList(usize), head: *usize) void {
        if (head.* == 0) return;
        const remaining = list.items.len - head.*;
        if (remaining == 0) {
            list.clearRetainingCapacity();
            head.* = 0;
        } else if (head.* >= remaining) {
            std.mem.copyForwards(usize, list.items[0..remaining], list.items[head.*..]);
            list.shrinkRetainingCapacity(remaining);
            head.* = 0;
        }
    }

    /// Enqueue `fiber` onto the ready ring if it isn't already there and is
    /// actually runnable. The status guard lets callers fire this right after
    /// any transition without checking (a no-op for non-runnable fibers, e.g.
    /// the main fiber addFiber places as .running). OOM on the accelerator is
    /// swallowed: the fiber stays unqueued and the fallback scan still finds
    /// it, and leaving `queued` false lets a later markRunnable retry.
    ///
    /// Public so the top-level dispatch paths in vm_calls.zig (which suspend
    /// the main fiber and dispatch via switchTo, not runSchedulerStep) can
    /// feed the ring too.
    pub fn markRunnable(self: *FiberScheduler, fiber: *Fiber) void {
        if (fiber.queued) return;
        if (fiber.status != .created and fiber.status != .suspended) return;
        self.ready.append(self.vm.gc.allocator, fiber.sched_idx) catch return;
        fiber.queued = true;
    }

    /// Marks `fiber` terminal and returns its slot to the free list. The one
    /// choke point for .completed/.errored transitions that vacate a slot, so
    /// the free-list invariant (every non-main freed slot enqueued exactly
    /// once — a terminal fiber is never revived, so it can't be pushed twice)
    /// can't drift across call sites.
    pub fn retireSlot(self: *FiberScheduler, fiber: *Fiber, status: FiberStatus) void {
        // Normally a no-op: the channel primitives release the rendezvous
        // demand token on their own exits. Catches a fiber that died
        // between a wake and its retry (e.g. dispatch-loop error paths), so
        // its committed demand can't admit sends nobody will ever collect.
        releaseFiberRendezvousToken(fiber);
        fiber.status = status;
        // Slot 0 is the main fiber; it can be transiently marked .completed at
        // top level (vm_calls.zig) but must never be recycled — ensureScheduler
        // and every fibers.items[0] reader assume slot 0 is always main.
        if (fiber.sched_idx == 0) return;
        self.free_slots.append(self.vm.gc.allocator, fiber.sched_idx) catch {};
    }

    /// Pop the oldest genuinely-reclaimable free slot, or null if none. The
    /// status recheck is defensive: a pushed slot always still holds the
    /// terminal fiber that vacated it (or was cleared), so it should always
    /// pass — but skipping a surprise keeps a stale entry from ever handing
    /// addFiber a live fiber's slot.
    fn popFreeSlot(self: *FiberScheduler) ?usize {
        while (self.free_head < self.free_slots.items.len) {
            const idx = self.free_slots.items[self.free_head];
            self.free_head += 1;
            const reclaimable = idx < self.fibers.items.len and blk: {
                const f = self.fibers.items[idx] orelse break :blk true;
                break :blk f.status == .completed or f.status == .errored;
            };
            if (reclaimable) {
                ringCompact(&self.free_slots, &self.free_head);
                return idx;
            }
        }
        ringCompact(&self.free_slots, &self.free_head);
        return null;
    }

    /// Front validated-runnable slot index in the ready ring, or null if it
    /// drains without one (whereupon a real-dispatch caller does the
    /// authoritative scan). Any front entry that isn't dispatchable —
    /// referencing a reused/absent slot, no longer runnable, or (when
    /// `exclude_driving`) a fiber whose own nested drive is still live
    /// (#1487) — is dropped as it's passed; the fallback scan still finds a
    /// dropped-but-selectable fiber whenever it's genuinely selectable
    /// (plain schedule(), or once driving clears), consistent with "only the
    /// parked fiber's own loop ever consumes its wake."
    ///
    /// `consume` distinguishes the two caller kinds. A real dispatch consumes
    /// the entry (advance past it, clear `queued`) so the fiber re-enqueues at
    /// the tail via markRunnable when it next suspends — that rotation is what
    /// keeps dispatch fair round-robin. The advisory yield check peeks
    /// (`consume=false`): it leaves the runnable entry in place so it can't
    /// starve a sibling, and repeated advisory calls stay idempotent.
    fn popReady(self: *FiberScheduler, exclude_driving: bool, consume: bool) ?usize {
        while (self.ready_head < self.ready.items.len) {
            const idx = self.ready.items[self.ready_head];
            if (idx < self.fibers.items.len) {
                if (self.fibers.items[idx]) |fiber| {
                    // Honor an entry only while it still owns the flag: a stale
                    // duplicate for a since-reused slot (sched_idx mismatch)
                    // must not clear a different fiber's `queued`.
                    if (fiber.sched_idx == idx and
                        (fiber.status == .created or fiber.status == .suspended) and
                        !(exclude_driving and fiber.driving))
                    {
                        if (consume) {
                            self.ready_head += 1;
                            fiber.queued = false;
                            ringCompact(&self.ready, &self.ready_head);
                        }
                        return idx;
                    }
                    if (fiber.sched_idx == idx) fiber.queued = false;
                }
            }
            self.ready_head += 1;
        }
        ringCompact(&self.ready, &self.ready_head);
        return null;
    }

    pub fn addFiber(self: *FiberScheduler, fiber: *Fiber) !void {
        // Reuse a vacated slot if one is on the free list (O(1)); the list is
        // comprehensively fed by retireSlot, so an empty list genuinely means
        // no reusable slot exists — append rather than rescanning the whole
        // array for one, which is what made spawning N live fibers O(n^2)
        // (#1477). markRunnable enqueues the new (.created) fiber for dispatch;
        // it's a no-op for the main fiber ensureScheduler adds as .running.
        if (self.popFreeSlot()) |idx| {
            self.fibers.items[idx] = fiber;
            fiber.sched_idx = idx;
            self.markRunnable(fiber);
            return;
        }
        const idx = self.fibers.items.len;
        try self.fibers.append(self.vm.gc.allocator, fiber);
        fiber.sched_idx = idx;
        self.markRunnable(fiber);
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
            var fiber_root = types.makePointer(&fiber.header);
            self.vm.gc.pushRoot(&fiber_root);
            const trampoline = try wrapInTrampoline(self.vm.gc, thunk_val);
            self.vm.gc.popRoot();
            fiber.thunk = trampoline;
            self.vm.gc.writeBarrier(&fiber.header, trampoline);
            closure = types.toObject(trampoline).as(types.Closure);
        }

        @memset(fiber.registers, types.UNDEFINED);
        fiber.registers[0] = types.makePointer(&closure.header);
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
        // The copy below spans dead gap registers between live frame windows.
        // While this fiber was running it was GC-marked per-frame (markVMRoots),
        // so a gap slot's stale pointer could already have been freed; copying it
        // into fiber.registers would then let markFiberState trace it after the
        // fiber suspends → use-after-free (#1529, sibling of #1464). Scrub the
        // gaps first; no frame reads a gap slot, so this is behavior-preserving.
        vm.clearGapRegisters(span);
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
        if (current.status == .running) {
            current.status = .suspended;
            self.markRunnable(current);
        }

        try self.restoreFiber(next_idx);
        const next = self.fibers.items[next_idx] orelse return;
        next.status = .running;
        self.current_idx = next_idx;
        self.vm.current_fiber = next;
    }

    /// True iff any fiber is parked on fd readiness — gates the per-tick
    /// zero-timeout reactor poll in the scheduler tick. Answered in O(1) off
    /// the reactor's own registration table rather than by rescanning every
    /// fiber (#1477): an fd is registered iff a fiber is parked on it
    /// (waitForFd registers before flipping to `.io_waiting`, and every path
    /// out of `.io_waiting` unregisters or drains the waiter), so an empty
    /// table means no I/O waiters. It may transiently over-count — an entry
    /// can linger with drained waiter lists between a fired ONESHOT and its
    /// re-arm/unregister — which only costs a harmless extra `poll(0)` (the
    /// kernel returns no events), never a missed wakeup. The old O(fiber
    /// count) scan early-exited on the server's common case but degraded to
    /// full length exactly when it was hottest: many non-I/O fibers and no
    /// I/O waiter to short-circuit on.
    fn anyIoWaiting(self: *FiberScheduler) bool {
        const reactor = self.vm.reactor orelse return false;
        return reactor.regs.count() != 0;
    }

    /// Selects the next `created`/`suspended` fiber to dispatch, or null if
    /// none. Consuming round-robin: the returned fiber is rotated out of the
    /// ready ring and re-enqueued at the tail when it next suspends, so
    /// dispatch stays fair. Runs the scheduler tick first (drains the
    /// notifier, pops expired timers, polls ready I/O) so a timed or I/O wait
    /// resolves promptly even while a busy/yielding sibling keeps the loop
    /// from ever going idle (KEP-0001 Phase 2 Q5 / Phase 3). Every one of
    /// those is now O(1) per tick (#1477): ring pop for selection, reactor
    /// registration count for the I/O gate, timer-heap peek for timers.
    ///
    /// Does NOT exclude `driving` fibers — see `scheduleForDispatch`'s doc
    /// comment for why that exclusion must not live here. Used by
    /// vm_calls.zig's top-level scheduleNextAfterYield/runWithScheduler,
    /// which dispatch via switchTo and — unlike runSchedulerStep — never nest
    /// another drive, so they carry none of the corruption risk `driving`
    /// guards against.
    pub fn schedule(self: *FiberScheduler) ?usize {
        return self.scheduleImpl(false);
    }

    /// Like `schedule`, but also excludes `driving` fibers — see that
    /// field's doc comment (#1487). Used only by runSchedulerStep's own
    /// dispatch loop, the sole call site that actually restoreFiber+
    /// vm.runUntil()s whatever index this returns: selecting a `driving`
    /// fiber there would resume its stale, mid-native-call register
    /// snapshot from a different fiber's nested drive. The advisory
    /// `anyRunnable()` must keep *seeing* these fibers (see its doc comment)
    /// — excluding them there instead reproduces #1440's symptom by a
    /// different path: a busy sibling's `(yield)` advisory check would see
    /// nothing runnable (the driving ancestor whose wait *just* resolved is
    /// invisible) and silently no-op instead of actually yielding, starving
    /// that ancestor's own loop of the turn it needs to notice and exit.
    pub fn scheduleForDispatch(self: *FiberScheduler) ?usize {
        return self.scheduleImpl(true);
    }

    /// Advisory "is any other fiber runnable right now" for yield's arm-or-
    /// no-op decision (yieldFn/threadYieldFn) — the returned answer is a
    /// bool, no fiber is dispatched. Runs the scheduler tick (so a wait that
    /// just resolved counts), then *peeks* the ready ring without consuming,
    /// so asking doesn't perturb round-robin order or starve anyone.
    ///
    /// Ring-only, by design no O(fiber count) fallback scan: every production
    /// transition to runnable goes through markRunnable, so an empty ring
    /// genuinely means nothing is runnable — and this must stay O(1) because
    /// a CPU-bound fiber yielding in a loop while thousands of siblings are
    /// parked would otherwise pay a full scan on every single yield (#1477).
    /// A hypothetical missed enqueue costs only a yield that no-ops when it
    /// could have rotated (a fairness nicety); the authoritative fallback
    /// scan the real-dispatch paths keep is what guarantees correctness.
    /// Does NOT exclude driving fibers, matching the old advisory schedule().
    pub fn anyRunnable(self: *FiberScheduler) bool {
        self.runReactorTick();
        return self.popReady(false, false) != null;
    }

    fn scheduleImpl(self: *FiberScheduler, exclude_driving: bool) ?usize {
        self.runReactorTick();

        // Fast path (#1477): the ready ring holds slot indices flagged
        // runnable by markRunnable at the transition sites. When it yields a
        // validated target, skip the scan entirely — the whole point on a busy
        // server whose `fibers` array is mostly parked io_waiting fibers.
        if (self.popReady(exclude_driving, true)) |idx| return idx;

        // Authoritative fallback: the original O(n) round-robin scan. Covers
        // every runnable fiber the ring didn't capture — notably any status
        // set directly without markRunnable (much test code, plus any not-yet-
        // instrumented transition) — so correctness never depends on the
        // accelerator's coverage, only performance does.
        const n = self.fibers.items.len;
        if (n == 0) return null;
        var i: usize = 1;
        while (i <= n) : (i += 1) {
            const idx = (self.current_idx + i) % n;
            if (self.fibers.items[idx]) |f| {
                if ((f.status == .created or f.status == .suspended) and (!exclude_driving or !f.driving)) return idx;
            }
        }
        return null;
    }

    /// The per-tick scheduler housekeeping shared by scheduleImpl and the
    /// advisory anyRunnable: drain the cross-thread notifier (KEP-0002 §5),
    /// then pop expired timers and — only when an fd is actually registered —
    /// poll ready I/O, flipping every woken fiber back to runnable. Checked
    /// on *every* call, not just when idle (parkOnReactor), so a timed or I/O
    /// wait resolves promptly even while a busy/yielding sibling keeps the
    /// loop from ever going idle.
    fn runReactorTick(self: *FiberScheduler) void {
        if (self.vm.reactor) |reactor| {
            // KEP-0002 §5's normative consume protocol, checked every tick
            // (not just when idle) for the same promptness reason as the
            // timer/I/O checks below: a notify arriving after the last swap
            // still rang the notifier's fd, which poll() observes
            // immediately; one arriving before it was swept right here. No
            // interleaving loses a wakeup.
            while (reactor.notifier.wake_pending.swap(false, .acq_rel)) self.sweepSharedWaiters();

            var expired: std.ArrayList(*Fiber) = .empty;
            defer expired.deinit(self.vm.gc.allocator);
            if (self.anyIoWaiting()) {
                // poll(0) also pops expired timers internally.
                reactor.poll(0, &expired) catch {};
            } else {
                reactor.popExpiredTimers(&expired) catch {};
            }
            for (expired.items) |f| {
                wakeReadyFiber(f);
                self.markRunnable(f);
            }
        }
    }

    /// Used only by parkOnReactor's deadlock check, which runs after
    /// scheduleForDispatch() has already found nothing .created/.suspended
    /// — so this deliberately does NOT count .running: under recursive
    /// dispatch (runSchedulerStep calling runSchedulerStep), every fiber on
    /// the current call chain back to main is still .running (none flip to
    /// .waiting until they themselves decide to park), so treating .running
    /// as "other progress possible" would make a genuine deadlock loop
    /// forever in reactor.poll() instead of ever detecting it.
    ///
    /// Must mirror scheduleForDispatch()'s own `!driving` exclusion (NOT
    /// plain schedule()'s, which deliberately omits it — see that
    /// function's doc comment): a fiber that got woken (.suspended) while
    /// its own nested runSchedulerStep call is still live is always an
    /// ancestor of whoever's asking (#1487), and scheduleForDispatch() will
    /// never actually dispatch it — counting it here would make
    /// parkOnReactor proceed to a real, potentially uncapped reactor.poll()
    /// with nothing left to ever wake it: a hang, not just a missed
    /// deadlock error.
    pub fn hasRunnableFibers(self: *FiberScheduler) bool {
        // KEP-0002 §5: a fiber parked on a promoted channel with a live
        // ThreadNotifier registration is "alive, waiting" even though it
        // matches none of the local wait categories below -- another OS
        // thread may still send/receive and wake it via sweepSharedWaiters.
        if (self.shared_waiters.items.len != 0) return true;
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if ((fiber.status == .created or fiber.status == .suspended) and !fiber.driving)
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

    /// What doWake should do to each matched waiter beyond the common
    /// suspend + cancel-timer + markRunnable. `all` distinguishes a broadcast
    /// (wake every matching waiter) from a hand-off (wake the first, leave the
    /// rest parked). `result`, when set, is stored into each woken fiber (the
    /// fiber-join hand-off). `clear_waiting_on` blanks the woken fiber's
    /// `waiting_on` (the channel retry contract; the join/mutex/condvar paths
    /// leave it, matching their pre-#1530 behavior exactly).
    const WakeSpec = struct {
        all: bool,
        result: ?Value = null,
        clear_waiting_on: bool = false,
    };

    /// Enroll `fiber` (already flipped to `.waiting` with its `waiting_on`
    /// set) into waiter_index so the matching wake path finds it without
    /// scanning every slot (#1530). Call at every LOCAL park site; a park on a
    /// promoted channel must NOT call this — it is woken via sweepSharedWaiters
    /// (a stale local-index entry for it would merely be validated away).
    /// A `waiting_on` of VOID (thread-sleep!'s pure timed wait) is never a
    /// wake target, so it is skipped. The tail check makes a re-park on the
    /// same object idempotent: the mutex/condvar retry loops re-enter
    /// `.waiting` without an intervening wake, and dropping the duplicate keeps
    /// the list length ~= concurrent waiters rather than growing with spins.
    /// An allocation failure degrades the whole index to the fallback scan
    /// (waiter_index_degraded) rather than leaving this fiber unfindable.
    pub fn enrollWaiter(self: *FiberScheduler, fiber: *Fiber) void {
        if (self.waiter_index_degraded) return;
        const key = fiber.waiting_on;
        if (key == types.VOID) return;
        const gop = self.waiter_index.getOrPut(key) catch {
            self.waiter_index_degraded = true;
            return;
        };
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        const list = gop.value_ptr;
        // Tail dedup: a re-park on the same object would otherwise append a
        // second copy of this slot every spin. The prior entry is still valid
        // (this fiber is `.waiting` on `key` again), so skipping keeps the
        // list bounded by concurrent waiters, not iterations.
        if (list.items.len != 0 and list.items[list.items.len - 1] == fiber.sched_idx) return;
        list.append(self.vm.gc.allocator, fiber.sched_idx) catch {
            // A brand-new key whose first append failed left an empty list in
            // the map; drop it so an empty entry can't linger.
            if (!gop.found_existing) _ = self.waiter_index.remove(key);
            self.waiter_index_degraded = true;
        };
    }

    /// The common tail of every wake path: move `fiber` from `.waiting` back
    /// to `.suspended`, hand off any join result, cancel a pending timeout
    /// timer, and enqueue it on the ready ring. Factored out so the index and
    /// fallback-scan paths apply byte-identical semantics.
    fn doWake(self: *FiberScheduler, fiber: *Fiber, spec: WakeSpec) void {
        if (spec.result) |r| {
            fiber.result = r;
            self.vm.gc.writeBarrier(&fiber.header, r);
        }
        fiber.status = .suspended;
        if (spec.clear_waiting_on) fiber.waiting_on = types.VOID;
        self.cancelPendingTimer(fiber);
        self.markRunnable(fiber);
    }

    /// Wake fibers parked on `key`, per `spec`. Uses waiter_index when healthy
    /// (O(waiters-on-key)); falls back to the pre-#1530 O(fiber count) scan
    /// only after an enroll OOM degraded the index. The single choke point
    /// behind all five public wake entry points.
    fn wakeOn(self: *FiberScheduler, key: Value, spec: WakeSpec) void {
        if (self.waiter_index_degraded) return self.scanWakeOn(key, spec);
        self.indexWakeOn(key, spec);
    }

    /// Index-driven wake. Walks only the slot indices enrolled under `key`,
    /// validating each exactly as popReady validates a ready-ring entry (slot
    /// still owns its index, still `.waiting`, still on `key`) so a
    /// since-reused or since-woken slot can never wake the wrong fiber. Stale
    /// entries and the woken one are compacted out; a broadcast empties the
    /// list, a hand-off keeps the still-parked tail. An emptied list frees its
    /// key so the map stays bounded by currently-contended objects — essential
    /// for fiber-join keys, which are one-shot (one per completed fiber).
    fn indexWakeOn(self: *FiberScheduler, key: Value, spec: WakeSpec) void {
        const entry = self.waiter_index.getEntry(key) orelse return;
        const list = entry.value_ptr;
        var w: usize = 0; // write cursor: entries to keep, compacted in place
        var woke_one = false;
        for (list.items) |idx| {
            // Hand-off: once the single waiter is woken, keep the rest verbatim
            // (they stay parked; their validity is rechecked at the next wake).
            if (!spec.all and woke_one) {
                list.items[w] = idx;
                w += 1;
                continue;
            }
            const occ: ?*Fiber = if (idx < self.fibers.items.len) self.fibers.items[idx] else null;
            if (occ) |fiber| {
                if (fiber.sched_idx == idx and fiber.status == .waiting and fiber.waiting_on == key) {
                    self.doWake(fiber, spec);
                    woke_one = true;
                    continue; // drop the woken entry
                }
            }
            // stale (reused/absent slot, or no longer waiting on `key`): drop
        }
        if (w == 0) {
            list.deinit(self.vm.gc.allocator);
            _ = self.waiter_index.remove(key);
        } else {
            list.shrinkRetainingCapacity(w);
        }
    }

    /// Pre-#1530 authoritative scan, retained as the enroll-OOM fallback
    /// (waiter_index_degraded). Behaviorally identical to the original wake
    /// loops: every `.waiting` fiber on `key` for a broadcast, the first for a
    /// hand-off.
    fn scanWakeOn(self: *FiberScheduler, key: Value, spec: WakeSpec) void {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == key) {
                    self.doWake(fiber, spec);
                    if (!spec.all) return;
                }
            }
        }
    }

    pub fn wakeWaiters(self: *FiberScheduler, completed_fiber: *Fiber) void {
        const completed_val = types.makePointer(&completed_fiber.header);
        self.wakeOn(completed_val, .{ .all = true, .result = completed_fiber.result });
    }

    /// Wake every fiber parked on this channel (status .waiting via the
    /// channel-receive retry protocol). Waking all is safe: each re-executes
    /// channel-receive and re-parks if the channel is empty again.
    pub fn wakeChannelWaiters(self: *FiberScheduler, ch_val: Value) void {
        self.wakeOn(ch_val, .{ .all = true, .clear_waiting_on = true });
    }

    /// KEP-0002 §5's per-scheduler shared-waiter registry: a fiber joins
    /// when it parks on a promoted channel (channelReceiveShared,
    /// promoteChannel's §2 step 4 migration) and leaves via
    /// removeSharedWaiter or the unconditional sweep below. Owned and
    /// mutated only by this scheduler's own thread -- no lock needed. Holds
    /// fiber pointers, not heap Values, so it adds no GC roots of its own:
    /// it's a secondary index into `fibers`, which markRoots already marks
    /// unconditionally regardless of status.
    pub fn enrollSharedWaiter(self: *FiberScheduler, fiber: *Fiber) !void {
        for (self.shared_waiters.items) |existing| {
            if (existing == fiber) return; // dedup
        }
        try self.shared_waiters.append(self.vm.gc.allocator, fiber);
    }

    /// No-op if `fiber` isn't enrolled. Called after a park attempt resolves
    /// (channelReceiveShared) and by thread-terminate! (which flips a
    /// victim's status directly, bypassing the sweep) -- without this, a
    /// terminated fiber's slot could be reused by addFiber while a stale
    /// pointer to the old fiber object still sits in this registry.
    pub fn removeSharedWaiter(self: *FiberScheduler, fiber: *Fiber) void {
        for (self.shared_waiters.items, 0..) |f, i| {
            if (f == fiber) {
                _ = self.shared_waiters.swapRemove(i);
                return;
            }
        }
    }

    /// KEP-0002 §5, model-checked to be UNCONDITIONAL (kaappi/keps#12,
    /// "model finding 1"): a readiness-filtered sweep is a proven lost
    /// wakeup. Rings snapshot-and-clear the SharedChannel waiter lists
    /// (shared_channel.zig), so a fiber that was rung but lost the retry
    /// race to a faster thread has no registration left -- if the sweep
    /// also declines to flip it, nothing ever will. Flipping every entry
    /// makes the wake-all discipline literal: woken fibers retry their
    /// primitive, and losers re-park and re-register under the channel's
    /// own lock. The cost is spurious retries bounded by the registry
    /// length, which only ever holds shared-channel waiters.
    pub fn sweepSharedWaiters(self: *FiberScheduler) void {
        for (self.shared_waiters.items) |f| {
            // Guards a fiber whose .waiting status was already cleared by
            // another path before this sweep ran (thread-terminate!'s
            // direct removal, or an entry left behind after an OOM unwound
            // channelReceiveShared before its own removeSharedWaiter call) --
            // flipping it again would be harmless but pointless.
            if (f.status == .waiting) {
                f.status = .suspended;
                f.waiting_on = types.VOID;
                self.markRunnable(f);
            }
        }
        self.shared_waiters.clearRetainingCapacity();
    }

    /// Hand the mutex to one parked waiter (mutex unlock / abandonment). The
    /// woken fiber re-races the claim and re-parks on failure, so waking
    /// exactly one is the correct SRFI-18 hand-off.
    pub fn wakeMutexWaiters(self: *FiberScheduler, mutex_val: Value) void {
        self.wakeOn(mutex_val, .{ .all = false });
    }

    /// condition-variable-signal!: wake exactly one waiter.
    pub fn wakeOneCondVarWaiter(self: *FiberScheduler, cv_val: Value) void {
        self.wakeOn(cv_val, .{ .all = false });
    }

    /// condition-variable-broadcast!: wake every waiter.
    pub fn wakeAllCondVarWaiters(self: *FiberScheduler, cv_val: Value) void {
        self.wakeOn(cv_val, .{ .all = true });
    }

    pub fn markRoots(self: *FiberScheduler, gc: *memory.GC) void {
        for (self.fibers.items) |f| {
            if (f) |fiber| {
                gc.markValue(types.makePointer(&fiber.header));
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
///
/// Walks `fiber.owned_mutexes` (maintained by mutex-lock!) rather than
/// scanning a GC heap for owned mutexes: a mutex shared across OS threads
/// via a top-level global lives in whichever heap allocated it — typically
/// the parent's, not the dying child's — so a scan of the child's own heap
/// would never find it (#1458). The list is only ever mutated on `fiber`'s
/// owning thread, and every call site invokes this on that same thread, so
/// the walk/clear here races nothing.
///
/// The `m.locked and m.owner == fiber_val` guard is still required: the list
/// may hold stale entries (a mutex unlocked by another thread, or re-locked
/// by a different owner, is only pruned lazily on the next mutex-lock!), and
/// abandoning one of those would corrupt a lock a live fiber legitimately
/// holds.
pub fn abandonFiberMutexes(fiber: *Fiber, sched: ?*FiberScheduler) void {
    const fiber_val = types.makePointer(&fiber.header);
    for (fiber.owned_mutexes.items) |m_val| {
        const m = types.toMutex(m_val);
        if (@atomicLoad(bool, &m.locked, .acquire) and m.owner == fiber_val) {
            // Order matters: abandoned and owner must both be published
            // *before* the release-store below, so a cross-thread acquirer
            // that wins the locked CAS is guaranteed to see them already
            // updated (not stomp a fresh owner write with VOID, or miss the
            // abandonment).
            @atomicStore(bool, &m.abandoned, true, .release);
            m.owner = types.VOID;
            @atomicStore(bool, &m.locked, false, .release);
            if (sched) |s| s.wakeMutexWaiters(m_val);
        }
    }
    fiber.owned_mutexes.clearRetainingCapacity();
}

/// Release `fiber`'s rendezvous demand token, if it holds one (KEP-0002 §6
/// as amended: every terminal exit of a rendezvous wait releases its token,
/// and fiber death is the terminal exit of last resort — the
/// abandonFiberMutexes precedent). Normally a no-op: the channel primitives
/// release on their own value/eof/timeout/error exits; this catches a fiber
/// killed between a wake and its retry (thread-terminate!, an errored
/// dispatch). The channel stub is always in this thread's heap (the
/// receive path's foreign-owner check gates acquisition), so the local
/// decrement never touches another thread's memory; a promoted channel's
/// counter lives in the SharedChannel and is withdrawn under its lock
/// (#1603), safe from any thread.
pub fn releaseFiberRendezvousToken(fiber: *Fiber) void {
    if (fiber.rv_demand_on == types.VOID) return;
    const ch = types.toObject(fiber.rv_demand_on).as(types.Channel);
    if (ch.shared) |raw| {
        const shared_channel = @import("shared_channel.zig");
        const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(raw));
        shared_channel.withdrawRvDemand(sc);
    } else {
        ch.rv_demand -= 1;
    }
    fiber.rv_demand_on = types.VOID;
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
        .io_waiting => {
            f.status = .suspended;
            f.io_fd = null;
        },
        .waiting => {
            f.status = .suspended;
            f.timed_out = true;
        },
        else => {},
    }
}

/// Wakes every fiber parked on fd readiness for `fd` — close-port's half of
/// the close discipline (KEP-0001 Phase 3, resolved question 4). The woken
/// fibers retry their I/O primitive, observe `is_open == false`, and raise a
/// clean "port closed" error instead of sleeping on an fd that will never
/// fire (the caller unregisters it from the reactor right after this).
/// Mirrors wakeChannelWaiters' iterate-and-flip discipline.
pub fn wakeIoWaitersOnFd(sched: *FiberScheduler, fd: platform.fd_t) void {
    for (sched.fibers.items) |f| {
        if (f) |fiber| {
            if (fiber.status == .io_waiting and fiber.io_fd == fd) {
                fiber.status = .suspended;
                fiber.io_fd = null;
                sched.markRunnable(fiber);
            }
        }
    }
}

/// Wait until the current fiber's own fd readiness resolves: done as soon
/// as something (reactor poll, close-port wake) flips it out of io_waiting.
const IoWait = struct {
    me: *Fiber,
    pub fn isDone(self: IoWait) bool {
        return self.me.status != .io_waiting;
    }
    /// #1625: an fd wait is the one drive whose *own* registration defeats
    /// the generic idle escape — hasRunnableFibers counts this fiber's
    /// `.io_waiting` and the fd keeps the reactor non-empty, so
    /// parkOnReactor never returns false and the poll is unbounded. When an
    /// ancestor drive has already resolved, blocking anyway wedges it
    /// forever on an event that may never come; unwinding (waitForFd turns
    /// the broken-off drive into a catchable error) is the only exit that
    /// lets the thread proceed. Waits that resolve through in-thread wakes
    /// (join/channel/mutex/condvar) don't need this: with no fd of their
    /// own, the same idle state already falls out via parkOnReactor's
    /// deadlock check, and timed sleeps must run their full duration.
    pub const unwind_on_resolved_ancestor = true;
};

/// Blocks the current fiber until `fd` is ready for `interest` (KEP-0001
/// Phase 3). Two modes, chosen by whether the fiber can be safely parked:
///
/// - **Park** (a spawned fiber dispatched directly by a scheduler loop):
///   registers with the reactor, flips to `.io_waiting`, arms the
///   yield-retry ip rewind, and returns `error.Yielded` — the same
///   park-and-retry protocol as blockOrDeadlock. The whole primitive
///   re-executes when the fd fires, so callers with partial progress must
///   stash it (e.g. into `port.read_buf`) before propagating the error.
///
/// - **Drive** (the main fiber, or any fiber under re-entrant native frames
///   that cannot be rewound): registers likewise, then drives the scheduler
///   in place — exactly the thread-sleep! pattern — until the reactor
///   reports the fd ready or a close-port wake intervenes, then returns so
///   the caller retries its syscall. Blocking main on I/O this way keeps
///   sibling fibers running while preserving blocking-read semantics. One
///   exception (#1625): if the drive goes idle while an *enclosing* drive's
///   wait has already resolved (IoWait.unwind_on_resolved_ancestor), it
///   raises a catchable "port I/O abandoned" error instead of blocking,
///   because only this fiber's unwinding can let that enclosing wait
///   proceed.
pub fn waitForFd(vm: *VM, fd: platform.fd_t, interest: reactor_mod.Interest) VMError!void {
    const ctx = try ensureScheduler(vm);
    const me = vm.current_fiber orelse return VMError.InvalidArgument;
    const my_idx = ctx.sched.current_idx;

    me.io_fd = fd;
    me.io_interest = interest;
    // Status must flip before register(): the reactor's debug assertion
    // checks that every registered waiter is .io_waiting.
    const prev_status = me.status;
    me.status = .io_waiting;
    ctx.reactor.register(fd, interest, me) catch |err| {
        me.status = prev_status;
        me.io_fd = null;
        if (err == error.OutOfMemory) return VMError.OutOfMemory;
        // A kernel-level arm failure (EBADF on a raced-away fd, resource
        // limits) is not an OOM; surface it diagnosably.
        vm.setErrorDetail("cannot wait on fd {d}: reactor registration failed", .{fd});
        return VMError.InvalidArgument;
    };

    if (my_idx != 0 and vm.dispatched_from_scheduler) {
        vm.yield_retry = true;
        return VMError.Yielded;
    }

    // An fd wait has no deadline; a stale timed_out left by an earlier
    // timed wait would make runSchedulerStep return before the fd is
    // ready, degrading this wait into an EAGAIN retry spin.
    me.timed_out = false;

    // The normal wake paths (reactor poll, close-port) both remove `me`
    // from the waiter lists before flipping its status; this cleanup only
    // has work to do when an error below unwinds the wait mid-flight —
    // without it, the fiber would linger in the lists in a non-io_waiting
    // status and trip register()'s staleness assertion later.
    defer {
        ctx.reactor.removeWaiter(fd, me);
        me.io_fd = null;
        me.status = .running;
    }
    // SRFI 181: a custom port callback (always running with
    // dispatched_from_scheduler forced false, so the park branch above
    // never triggers for it) that blocks on another port's fd would
    // otherwise fall into the unbounded recursive scheduler drive below —
    // a confirmed native-stack-overflow risk under concurrent fibers, not
    // a catchable error. Reject it here instead, after the defer above is
    // already armed so this early return still unregisters the fd wait.
    if (vm.in_custom_port_callback > 0) {
        return raiseCustomPortCallbackBlocked(vm);
    }
    const done = try runSchedulerStep(IoWait, .{ .me = me }, vm, ctx.sched, me);
    // The drive broke off unresolved: IoWait's unwind_on_resolved_ancestor
    // fired (#1625) — an enclosing dispatch's wait has completed and only
    // this fiber's unwinding lets it proceed. Returning normally would
    // retry the syscall, EAGAIN again, and re-enter the same drive: an
    // unbreakable spin. Raise a catchable error instead; the defer above
    // has already pulled `me` off the reactor, and the re-entrant frames
    // that made parking impossible (guard, dynamic-wind) are exception
    // plumbing — an ordinary raise is exactly the unwind they handle.
    if (!done) return raiseIoWaitAbandoned(vm);
}

/// The catchable error a broken-off in-place I/O drive surfaces as (#1625).
/// A plain ErrorObject like blockOrDeadlock's deadlock errors — this is the
/// I/O drive's analogue of those: "this wait can no longer be serviced
/// without wedging the scheduler."
fn raiseIoWaitAbandoned(vm: *VM) VMError {
    var msg = vm.gc.allocString(
        "port I/O abandoned: fiber cannot suspend under re-entrant native frames " ++
            "(guard, dynamic-wind, callbacks) while an enclosing completed wait needs this thread",
    ) catch return VMError.OutOfMemory;
    vm.gc.pushRoot(&msg);
    defer vm.gc.popRoot();
    const err_obj = vm.gc.allocErrorObject(msg, types.NIL) catch return VMError.OutOfMemory;
    vm.current_exception = err_obj;
    return VMError.ExceptionRaised;
}

/// SRFI 181: a custom port's read!/write!/get-position/set-position!/
/// close/flush callback tried to block -- either on another port's fd
/// (this function is called from waitForFd above) or via thread-sleep!
/// (also called from primitives_srfi18.threadSleepFn's equivalent guard).
/// Every such callback runs through vm.callWithArgs, which always
/// executes with dispatched_from_scheduler forced false — so this fiber
/// could never park here the normal way, only recursively drive the
/// scheduler in place, which is the unbounded-native-stack-growth risk
/// this rejects instead. See vm.in_custom_port_callback's doc comment for
/// the full reasoning.
pub fn raiseCustomPortCallbackBlocked(vm: *VM) VMError {
    var msg = vm.gc.allocString(
        "custom port callback blocked: a SRFI 181 read!/write!/get-position/" ++
            "set-position!/close/flush procedure tried to block (e.g. on " ++
            "another port's I/O, or via thread-sleep!), which is not " ++
            "supported -- custom port callbacks must be effectively " ++
            "synchronous, non-blocking code",
    ) catch return VMError.OutOfMemory;
    vm.gc.pushRoot(&msg);
    defer vm.gc.popRoot();
    const err_obj = vm.gc.allocErrorObject(msg, types.NIL) catch return VMError.OutOfMemory;
    vm.current_exception = err_obj;
    return VMError.ExceptionRaised;
}

/// Called when sched.schedule() finds nothing immediately runnable. Blocks
/// in the reactor — bounded by its own timer heap, so no separate
/// "nearest deadline" computation is needed here — and flips every fiber
/// it reports ready back to `.suspended` (io_waiting) or
/// `.suspended`+`timed_out` (an expired timed `.waiting` wait). Returns
/// `false` only when nothing could ever produce a wakeup: genuine
/// deadlock/done, the same meaning as the bare `break` this replaces.
///
/// `cap_ns`, when given, additionally bounds the blocking wait itself
/// (independent of any registered timer). Needed by waits that might
/// resolve through state no reactor event announces — a mutex/condvar
/// shared with another OS thread's own scheduler, which has no way to
/// signal this one — so a long real timeout registered on `me` doesn't
/// make this call block for that entire duration on the offhand chance a
/// cross-thread resolution arrives sooner; the caller re-checks after each
/// capped return. `null` preserves the original bounded-only-by-registered-
/// timers behavior.
pub fn parkOnReactor(vm: *VM, sched: *FiberScheduler, cap_ns: ?u64) VMError!bool {
    const reactor = vm.reactor orelse return false;
    // Consume protocol (KEP-0002 §5) before the deadlock check: a notify
    // that arrived just before this call must not be missed by
    // hasRunnableFibers() reading a shared_waiters entry the sweep would
    // otherwise have already cleared.
    while (reactor.notifier.wake_pending.swap(false, .acq_rel)) sched.sweepSharedWaiters();
    if (!sched.hasRunnableFibers() and reactor.isEmpty()) return false;

    var ready: std.ArrayList(*Fiber) = .empty;
    defer ready.deinit(vm.gc.allocator);
    reactor.poll(cap_ns, &ready) catch return VMError.OutOfMemory;
    // A notify arriving *during* the blocking poll() above is what actually
    // interrupted it; its wake_pending flag needs consuming here even though
    // poll()'s own ReadyEvent list never surfaces the notifier's own event
    // (reactor.zig's wait() implementations filter it out).
    while (reactor.notifier.wake_pending.swap(false, .acq_rel)) sched.sweepSharedWaiters();

    for (ready.items) |f| {
        wakeReadyFiber(f);
        sched.markRunnable(f);
    }
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
/// typing), e.g. `TargetWait{ .target = f }`. `Ctx` may optionally also
/// define `pollCapNs(self: Ctx) ?u64` (see parkOnReactor) — omitted by
/// every Ctx type except the SRFI-18 mutex/condvar waits, which need it for
/// cross-OS-thread polling.
///
/// `me.driving` brackets the whole call (set here, cleared on every exit
/// via `defer`) regardless of whether the caller also set `me.status =
/// .waiting` first: it marks that `me`'s native frame is live on the Zig
/// call stack for the duration, which scheduleForDispatch()/
/// hasRunnableFibers() must never treat as dispatchable no matter what
/// happens to `status` while this runs (plain schedule() deliberately
/// keeps finding `me` regardless — see its own doc comment for why that
/// half of this split matters just as much as the exclusion does). Without
/// the exclusion, a wake delivered to `me` by something *this* call itself
/// (transitively) dispatches — e.g. a sibling fiber's own nested
/// runSchedulerStep unlocking a mutex `me` is waiting on — flips
/// `me.status` to `.suspended` while `me`'s real, mid-native-call state is
/// this saved snapshot; a scheduleForDispatch() reached through that
/// sibling's own loop (whose `next_idx == my_idx` guard only protects *its
/// own* index, not `me`'s) would then dispatch `me` from the stale
/// snapshot, resuming bytecode past the in-flight primitive call with the
/// destination register never written (#1487; the exact corruption already
/// fixed for channelReceiveShared's dispatched-fiber path in #1485, but
/// reachable here from *any* caller of this function, main fiber included,
/// since a fiber with `driving == true` is always an ancestor of whichever
/// call is currently asking — the whole scheduler runs on one OS thread, so
/// it can only have gotten a nested dispatch by dispatching something whose
/// own call tree is what's presently executing. Ancestors can never make
/// independent progress while a descendant is active regardless, so
/// excluding them from selection changes no genuine liveness outcome —
/// only the parked fiber's own loop, right here, ever consumes its wake).
pub fn runSchedulerStep(comptime Ctx: type, ctx: Ctx, vm: *VM, sched: *FiberScheduler, me: *Fiber) VMError!bool {
    const my_idx = sched.current_idx;
    try sched.saveCurrentFiber();
    const poll_cap_ns: ?u64 = if (@hasDecl(Ctx, "pollCapNs")) ctx.pollCapNs() else null;

    me.driving = true;
    defer me.driving = false;

    // Publish this drive's wait so nested drives can evaluate it (#1625) —
    // see driving_waits' doc comment. `ctx` is this frame's parameter, so
    // the pointer stays valid for exactly the extent the entry is stacked.
    // Unlike the ready ring or waiter_index, this list is a correctness
    // registry with no fallback: an entry silently dropped on OOM would
    // re-open the #1625 wedge for this drive's descendants. Fail the wait
    // loudly instead — callers already handle OutOfMemory from inside the
    // loop (saveCurrentFiber's growth, parkOnReactor's poll), and a clean
    // error beats a silent hang at death's door.
    const erased = struct {
        fn isDone(p: *const anyopaque) bool {
            const c: *const Ctx = @ptrCast(@alignCast(p));
            return c.isDone();
        }
    };
    sched.driving_waits.append(vm.gc.allocator, .{
        .fiber = me,
        .ctx = @ptrCast(&ctx),
        .is_done = &erased.isDone,
    }) catch return VMError.OutOfMemory;
    defer _ = sched.driving_waits.pop();

    while (!ctx.isDone() and !me.timed_out) {
        const next_idx = sched.scheduleForDispatch() orelse {
            // Nothing dispatchable. Before blocking in the reactor, a wait
            // that opted in gives up instead when an ancestor drive's
            // condition has already resolved: that ancestor can only
            // proceed once we unwind, and blocking here — for I/O waits,
            // on this fiber's own fd with no bound — would pin it forever
            // (#1625: a guard-wrapped reader's in-place drive vs. the
            // enclosing fiber-join whose target already completed). Checked
            // only at the idle point so runnable siblings still get
            // dispatched first — one of them may resolve *this* wait, which
            // is always the better outcome.
            if (comptime @hasDecl(Ctx, "unwind_on_resolved_ancestor")) {
                if (sched.anyAncestorWaitResolved(me)) break;
            }
            if (!(try parkOnReactor(vm, sched, poll_cap_ns))) break;
            continue;
        };
        // Unreachable in practice since `driving` (set above) now excludes
        // `me` from scheduleForDispatch() at every index, but kept as
        // defense-in-depth: this is the narrower guard `driving` subsumes
        // (it only ever protected this loop's own re-selection of itself,
        // not the cross-fiber case #1487 fixes).
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
                if (fiber.status == .running) {
                    fiber.status = .suspended;
                    sched.markRunnable(fiber);
                }
                continue;
            }
            // Fiber 0 is the main fiber: finishing or aborting one
            // top-level form is not thread death, so its mutexes stay
            // valid. retireSlot returns the vacated slot to the free list
            // (a no-op for slot 0), keeping addFiber's fast path fed.
            sched.retireSlot(fiber, .errored);
            if (next_idx != 0) abandonFiberMutexes(fiber, sched);
            try sched.saveCurrentFiber();
            sched.wakeWaiters(fiber);
            continue;
        };
        sched.retireSlot(fiber, .completed);
        fiber.result = result;
        vm.gc.writeBarrier(&fiber.header, result);
        if (next_idx != 0) abandonFiberMutexes(fiber, sched);
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
    gc.markValue(fiber.rv_demand_on);
    gc.markValue(fiber.name);
    gc.markValue(fiber.specific);

    for (fiber.frames[0..fiber.frame_count]) |f| {
        if (f.closure) |cls| gc.markValue(types.makePointer(&cls.header));
        if (f.native) |nf| gc.markValue(types.makePointer(&nf.header));
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

    // Keep held mutexes alive while the fiber owns them (#1458). markValue
    // skips any mutex owned by another GC, so a foreign (parent-heap) mutex
    // this child locked is a no-op here — its own heap's roots keep it alive.
    for (fiber.owned_mutexes.items) |m_val| gc.markValue(m_val);
}
