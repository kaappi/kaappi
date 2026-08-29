const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const primitives_fiber = @import("primitives_fiber.zig");
const fiber_mod = @import("fiber.zig");
const reactor_mod = @import("reactor.zig");
const memory = @import("memory.zig");
const shared_channel = @import("shared_channel.zig");
const gc_deep_copy = @import("gc_deep_copy.zig");
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

/// KEP-0002 Phase 2: what a completed thunk produced, crossing the thread
/// boundary the same way the thunk itself crossed at thread-start! -- via an
/// Envelope built on the *owning* thread (the child, for a result), not
/// deep-copied directly out of the child's still-allocated heap by the
/// parent at join time. This is what makes a channel created and returned
/// by the child legally promotable (promotion requires gc_instance to be
/// the channel's owner, which only holds true while the child itself is
/// still running). `.failed` records why building the envelope itself
/// failed (UncopyableType or OutOfMemory) so reapOsThread can raise the
/// exact same errors the old direct-deepCopy-at-join path did.
const JoinResult = union(enum) {
    none, // thunk returned void; nothing to copy out
    envelope: *shared_channel.Envelope,
    failed: gc_deep_copy.DeepCopyError,
};

const ChildThreadResources = struct {
    child_gc: *memory.GC,
    child_vm: *vm_mod.VM,
    result: JoinResult = .none,
    // Same shape as `result` (not a bare `?*Envelope`): an exception whose
    // payload is itself uncopyable (R7RS `raise` permits raising an
    // arbitrary value, including a port or a foreign-owned channel) or
    // whose envelope build hits OOM needs to surface as *something*
    // diagnostic at thread-join!, not silently collapse into a void
    // reason -- see reapOsThread's `.failed` arm for the synthesized error.
    exception: JoinResult = .none,
    // #2129 (handle half): set by retireOrFreeChild when a join leaves the
    // entry in place because the thread still has live descendants. Only a
    // retired entry may be freed by a descendant's threadEntryFn defer
    // (fetchRemoveIfRetired): an un-retired entry's thread may still be
    // running, and its result/exception envelopes must survive for a future
    // join while its GC/VM are still in use.
    retired: bool = false,
    // #1933: set (under the registry lock) by threadEntryFn's outermost
    // defer, just before the thread exits. A dead child's VM still sits in
    // the registry until its join, but its registers/frames hold stale
    // pointers to objects its own GC freed during its life -- the parent's
    // collector must never mark those (a mark would read a freed header;
    // a hard panic under -Dgc-stress). markLiveChildRoots skips any entry
    // with this flag, and re-checks it after its stop-the-world wait.
    thread_exited: bool = false,
};

// Entries are freed when a thread is joined (freeChildResources called from
// reapOsThread) or, when the join retires the entry because the thread still
// has live descendants, by the last descendant's threadEntryFn defer once the
// subtree drains (#2129). Threads that complete but are never joined leak
// their child VM and GC — the result must survive until the parent copies it
// out of its envelope, and automatic cleanup would race with that copy.
const ChildRegistry = struct {
    map: std.AutoHashMap(usize, ChildThreadResources),
    mutex: std.atomic.Mutex,

    fn put(self: *ChildRegistry, key: usize, res: ChildThreadResources) !void {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        try self.map.put(key, res);
    }

    fn storeResult(self: *ChildRegistry, key: usize, result: JoinResult, exception: JoinResult) void {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.getPtr(key)) |entry| {
            entry.result = result;
            entry.exception = exception;
        }
    }

    // Atomically reads AND clears result/exception (leaving child_gc/child_vm
    // in place for freeChildResources' own fetchRemove). A plain get() would
    // let two racing reapOsThread calls for the same fiber_key -- reachable
    // today only through a fiber value reached via a shared global, since
    // fiber ownership is otherwise unchecked -- both retrieve the SAME
    // *Envelope pointer and both call env.deinit() on it: a double-free.
    // Clearing under the lock means at most one caller ever sees a non-.none
    // result/non-.none exception to consume.
    const TakenResult = struct { result: JoinResult, exception: JoinResult };

    fn takeResult(self: *ChildRegistry, key: usize) TakenResult {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.getPtr(key)) |entry| {
            const taken: TakenResult = .{ .result = entry.result, .exception = entry.exception };
            entry.result = .none;
            entry.exception = .none;
            return taken;
        }
        return .{ .result = .none, .exception = .none };
    }

    fn fetchRemove(self: *ChildRegistry, key: usize) ?ChildThreadResources {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.fetchRemove(key)) |kv| return kv.value;
        return null;
    }

    // #2129 (handle half): flags the entry as retired (see the field doc).
    // Called by retireOrFreeChild from the joining parent, under the same
    // lock fetchRemoveIfRetired takes, so a descendant's defer either sees
    // the flag or not atomically with its own remove.
    fn markRetired(self: *ChildRegistry, key: usize) void {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.getPtr(key)) |entry| entry.retired = true;
    }

    // #1933: record that a child's OS thread has exited, so the parent's
    // collector stops marking its (now stale) VM. Called by threadEntryFn's
    // outermost defer, before the live_child_threads decrement.
    fn markExited(self: *ChildRegistry, key: usize) void {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.getPtr(key)) |entry| entry.thread_exited = true;
    }

    // #2129 (handle half): removes the entry only if it has been retired.
    // A descendant's threadEntryFn defer calls this with its spawner's key
    // when its decrement brings the spawner's live-descendant count to
    // zero; the spawner's join may concurrently fetchRemove the same entry
    // (retireOrFreeChild's re-read path), and the lock makes exactly one of
    // them win, so the GC/VM are freed exactly once.
    fn fetchRemoveIfRetired(self: *ChildRegistry, key: usize) ?ChildThreadResources {
        memory.spinLock(&self.mutex);
        defer memory.spinUnlock(&self.mutex);
        if (self.map.getPtr(key)) |entry| {
            if (!entry.retired) return null;
        }
        if (self.map.fetchRemove(key)) |kv| return kv.value;
        return null;
    }
};

var child_registry: ChildRegistry = .{
    .map = std.AutoHashMap(usize, ChildThreadResources).init(std.heap.page_allocator),
    .mutex = .unlocked,
};

/// #1933: set by the root thread's first thread-start! (threadStartImpl) as
/// the root gc's `child_marker`, so every root collection runs
/// markLiveChildRoots while live children exist. A child spawned mid-
/// collection spins on this flag before its first shared-globals read
/// (threadEntryFn), so a collector whose snapshot cannot know it exists is
/// never racing its registers.
var collection_in_progress: std.atomic.Value(bool) = .init(false);

/// #1933: the parent's collector keeps alive every parent-heap object a live
/// child thread still references. A child's registers are invisible to the
/// parent's own root marker (markVMRoots marks only the VM owning the gc),
/// and the child's own marker skips foreign-owner objects (#958) — so a
/// parent-heap object referenced ONLY from a live child's registers is
/// unreachable to both markers and the parent's collection frees it under
/// the running child (use-after-free, hard panic under -Dgc-stress).
///
/// Registered on the ROOT gc only. Each live child is stopped at a
/// dispatch-loop safepoint (or found already parked / in an FFI call — all
/// quiescent states, see vm.CollectionState), its roots are marked with
/// THIS gc (markVmRoots; the foreign-owner skip keeps the parent's collector
/// off the child's own heap objects), and it is released. Children spawned
/// while this runs are caught by re-snapshotting the registry until it stops
/// gaining entries; a mid-init child holds no parent-heap values yet and
/// spins on `collection_in_progress` before its first globals read.
///
/// The wait is bounded: a child at a safepoint parks within 1024
/// instructions, a parked child reports `.parked` immediately, and a child
/// inside a blocking FFI call reports `.in_native` (callFfi) — the only
/// states that never reach the safepoint. A child inside a bounded native
/// call (a long primitive, its own GC) makes the wait wait it out, then
/// parks.
///
/// Scope note: this keeps alive parent-heap objects referenced from a live
/// child's REGISTERS/frames — the issue's shape. A parent-heap object nested
/// inside a child-OWNED container (the child copied a shared global into a
/// local vector) is still invisible to the parent's collector, which cannot
/// traverse the foreign container without pausing the child's own GC; that
/// remains a documented residual of the same family (the parent must not
/// drop its last reference to an object a child holds), distinct from the
/// store rejection of kaappi#1924, which governs the writes that install
/// such references.
pub fn markLiveChildRoots(gc: *memory.GC) void {
    if (@atomicLoad(usize, &live_child_threads, .acquire) == 0) return;
    collection_in_progress.store(true, .release);
    defer collection_in_progress.store(false, .release);

    var marked: std.ArrayList(?*vm_mod.VM) = .empty;
    defer marked.deinit(gc.allocator);
    // Every VM whose `collection_stop` is armed, exited or not. The release
    // loop below iterates THIS list (never the nulled `marked`), so an
    // exited child's flag is always cleared and never left poisoned.
    var armed: std.ArrayList(*vm_mod.VM) = .empty;
    defer armed.deinit(gc.allocator);

    while (true) {
        // Snapshot the registry under its lock and arm the stop flag on any
        // live child not yet armed. Children whose OS thread has already
        // exited (thread_exited) are skipped: their VM is still in the
        // registry until the join, but its registers/frames are stale and
        // must never be marked. The lock is held only for the snapshot: the
        // mark below must not run while a descendant-side free holds it, but
        // no registry entry can be freed during this collection anyway (both
        // removal paths run on the collecting thread — a join, or a
        // descendant free gated on a join's retirement).
        var added = false;
        memory.spinLock(&child_registry.mutex);
        var it = child_registry.map.valueIterator();
        while (it.next()) |res| {
            if (res.thread_exited) continue;
            const cv = res.child_vm;
            var already = false;
            for (marked.items) |m| {
                if (m == cv) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                marked.append(gc.allocator, cv) catch @panic("GC: child-root marking OOM");
                armed.append(gc.allocator, cv) catch @panic("GC: child-root marking OOM");
                cv.collection_stop.store(true, .release);
                added = true;
            }
        }
        memory.spinUnlock(&child_registry.mutex);
        // Once a full pass adds no child, every live child is armed; wait for
        // each to leave `.running` (safepoint stop, park, FFI, or a raw
        // thread join). A running child reaches its next safepoint within
        // 1024 instructions, so spin-yield rather than sleep: a fixed 1ms
        // poll would cost ~1ms per parent collection with a live child —
        // pathological under -Dgc-stress, where collections run per
        // allocation.
        if (!added) break;
        for (armed.items) |vm| {
            var spins: u32 = 0;
            while (vm.collection_state.load(.acquire) == .running) {
                spins +%= 1;
                if (spins & 0xFF == 0) std.Thread.yield() catch {};
            }
        }
    }

    // A child may have exited during the wait (thread-terminate!, or its
    // thunk completing on its own). Its registers are stale now — the parent
    // must not mark them. Null its entry for the MARK loop only; `armed`
    // still releases its stop flag below.
    memory.spinLock(&child_registry.mutex);
    var it2 = child_registry.map.valueIterator();
    while (it2.next()) |res| {
        if (res.thread_exited) {
            for (marked.items, 0..) |cv, i| {
                if (cv == res.child_vm) marked.items[i] = null;
            }
        }
    }
    memory.spinUnlock(&child_registry.mutex);

    // All remaining children are quiescent. Mark their roots with this (the
    // parent's) gc; the child's own heap objects are skipped as foreign.
    for (marked.items) |cv| {
        if (cv) |vm| vm_mod.markVmRoots(gc, vm);
    }
    // Release every child — exited or not. They resume inside the parent's
    // sweep; any shared object they read from now on is reachable from the
    // parent's roots at mark time, so it was marked, and the sweep cannot
    // free it (the globals-route argument of the sharing model).
    for (armed.items) |vm| vm.collection_stop.store(false, .release);
}

/// Thin per-file convenience wrapper: fetches vm_instance and delegates to
/// fiber.ensureScheduler, which now lazily creates the reactor alongside
/// the scheduler (KEP-0001 Phase 2) — the actual setup logic lives in one
/// place instead of being duplicated per call site.
fn ensureScheduler() @TypeOf(fiber_mod.ensureScheduler(undefined)) {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant
    return fiber_mod.ensureScheduler(vm);
}

// 1ms. Since kaappi#2395 the blocking waits (thread-join!, mutex-lock!,
// condvar, thread-sleep!) are woken by notifier rings instead of polling at
// this cadence; the two remaining users are threadEntryFn's exit-path spins
// (the descendant drain and the mid-collection startup hold), which run off
// any wait Ctx and whose rare, bounded polling was left as-is.
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
// self-deadlock (e.g. waits on a mutex only it could ever unlock) blocks
// forever rather than raising the deadlock error runSchedulerStep's "not
// done" normally produces, since it always assumes the main thread might
// still help -- indefinite blocking here is conformant with SRFI-18, but the
// same shape of deadlock hangs on a child thread and errors on the main
// thread, which is worth knowing when debugging one. (Before kaappi#2395
// that hang burned a 1 ms poll loop; it now parks silently on the child's
// reactor, woken only by a ring that in this scenario never comes.)
//
// `pub` since KEP-0002 Phase 3 (#1468): primitives_fiber.zig's shared-channel
// deadlock heuristic (§5, "wakeup possible whenever ... other live OS threads
// exist") reuses this exact same disjunct rather than duplicating it.
pub fn crossThreadWaitPossible() bool {
    const vm = vm_mod.vm_instance orelse return false;
    if (!vm.owns_globals) return true;
    return @atomicLoad(usize, &live_child_threads, .acquire) > 0;
}

/// `pub` for main.zig (kaappi#1792): true while at least one `thread-start!`-
/// spawned OS thread has not yet finished `threadEntryFn` — including its
/// child-heap teardown, since the decrement is the outermost `defer` there
/// and so fires only after every access to shared parent state (the symbol
/// table, the globals map) is done. main.zig must not free either while this
/// is true; see the call site for why.
pub fn hasLiveChildThreads() bool {
    return @atomicLoad(usize, &live_child_threads, .acquire) > 0;
}

/// Relative seconds -> saturated nanoseconds, shared by
/// timeoutToDeadlineNs's number branch and threadSleepFn (#1983). One
/// implementation on purpose: the bug existed as three diverged copies of
/// this exact conversion, so any future policy change (say, to NaN
/// handling) must have a single edit point. lossyCast saturates where the
/// old @intFromFloat panicked: +inf.0 and any product >= 2^64 become
/// maxInt(u64) ("never times out"), NaN becomes 0 (the old @max treatment
/// of it -- @max(0.0, secs) before the multiply and @max on the product
/// are equivalent here, since scaling by a positive constant is monotone
/// and NaN propagates either way), negatives clamp to 0.
fn saturatedNsFromSeconds(secs: f64) u64 {
    return std.math.lossyCast(u64, @max(0.0, secs) * 1_000_000_000.0);
}

/// `pub` since KEP-0002 Phase 4 (#1469): primitives_fiber.zig's
/// channel-send/channel-receive timeouts reuse this exact SRFI-18-shaped
/// number-or-time-object-or-#f parsing rather than duplicating it.
///
/// `proc` is the calling procedure's name, used verbatim in the timeout's
/// type error (#2002). It used to be hardcoded 'thread', so
/// `(channel-receive ch 'bad)` reported `type error in 'thread'` — a
/// procedure that does not exist, in a library the caller never imported.
pub fn timeoutToDeadlineNs(proc: []const u8, timeout: Value) PrimitiveError!?u64 {
    if (timeout == types.FALSE) return null;
    if (types.isSrfi18Time(timeout)) {
        const t = types.toSrfi18Time(timeout);
        if (t.seconds < 0) return 0;
        const ns_clamped: u64 = if (t.nanoseconds > 0) @intCast(t.nanoseconds) else 0;
        // Saturating arithmetic throughout (#1983): a deadline past what the
        // u64 nanosecond clock can express (wall time beyond ~year 2554) is a
        // perfectly legal time object, and "so far out it never fires" is the
        // correct reading of it -- the SRFI-18 timeout convention treats
        // +inf.0 as "never time out" (Gambit). The old unchecked multiply
        // aborted the whole process instead, uncatchably, and through this
        // pub function took (kaappi fibers) channel timeouts down too.
        const sec_ns: u64 = @as(u64, @intCast(t.seconds)) *| 1_000_000_000 +| ns_clamped;
        const now_rt = platform.realTime();
        const now_ns = @as(u64, @intCast(now_rt.sec)) * 1_000_000_000 + @as(u64, @intCast(now_rt.nsec));
        if (sec_ns <= now_ns) return 0;
        const mono_now = fiber_mod.clockNs();
        return mono_now +| (sec_ns - now_ns);
    }
    const secs = primitives.toF64(timeout) catch
        return primitives.typeError(proc, "time object or number", timeout);
    const mono_now = fiber_mod.clockNs();
    // The saturating add keeps a saturated delta pinned at "never" instead
    // of wrapping around into the past (#1983).
    return mono_now +| saturatedNsFromSeconds(secs);
}

pub fn makeErrorWithType(error_type: types.ErrorObject.ErrorType, msg: []const u8, reason: Value) PrimitiveError!Value {
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

/// `pub` since KEP-0002 Phase 4 (#1469): primitives_fiber.zig's
/// channel-timeout-exception? path reuses this instead of duplicating the
/// typed-error-object construction.
pub fn raiseError(error_type: types.ErrorObject.ErrorType, msg: []const u8, reason: Value) PrimitiveError!Value {
    const err_val = try makeErrorWithType(error_type, msg, reason);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant
    vm.current_exception = err_val;
    return PrimitiveError.ExceptionRaised;
}

/// KEP-0002 §2 / invariant 4: a fiber (thread) value can only reach another OS
/// thread through a shared global. Fibers sit on gc_deep_copy's uncopyable
/// list, so they never ride a thread thunk or a channel message -- a thunk
/// that captures a thread handle is rejected at thread-start! before any child
/// spawns, and a child's own `(current-thread)` is a distinct fiber that
/// ensureScheduler allocated on the child heap. So a fiber whose `owner` is not
/// this GC is exactly the shared-global situation behind #1484: two threads
/// clearing the same `os_thread` and double-`thread.join()`ing it (pthread-level
/// UB), a losing joiner reading `target.result` before the winner has stored
/// it, or a foreign thread-terminate! mutating another scheduler's fiber. Refuse
/// it up front -- the same total treatment channel-send/-receive/-close!/-closed?
/// give a foreign channel (only the `thread?` predicate is exempt, mirroring
/// `channel?`) -- so the whole class is unreachable instead of patched case by
/// case inside reapOsThread. The reason irritant is VOID, never the fiber
/// itself: storing a foreign-heap object in an error the owner's GC may free
/// would just re-open the dangling-pointer hazard this check exists to close.
fn checkThreadOwner(fiber_val: Value, comptime proc: []const u8) PrimitiveError!void {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (types.toObject(fiber_val).owner == gc.id) return;
    const msg = std.fmt.comptimePrint(
        "{s}: thread belongs to another OS thread; a thread handle may only be used by the thread that created it",
        .{proc},
    );
    _ = try raiseError(.general, msg, types.VOID);
}

// ---------------------------------------------------------------------------
// Thread primitives
// ---------------------------------------------------------------------------

fn currentThreadFn(_: []const Value) PrimitiveError!Value {
    const ctx = try ensureScheduler();
    const fiber = ctx.vm.current_fiber orelse return types.VOID;
    return types.makePointer(&fiber.header);
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

    return types.makePointer(&fiber.header);
}

fn threadNameFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-name", "thread", args[0]);
    try checkThreadOwner(args[0], "thread-name");
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);
    return fiber.name;
}

fn threadSpecificFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-specific", "thread", args[0]);
    try checkThreadOwner(args[0], "thread-specific");
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);
    return fiber.specific;
}

fn threadSpecificSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-specific-set!", "thread", args[0]);
    try checkThreadOwner(args[0], "thread-specific-set!");
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);
    fiber.specific = args[1];
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    return types.VOID;
}

fn threadStartFn(args: []const Value) PrimitiveError!Value {
    // Unregistered on WASM (spec .wasm = false) but the body must still
    // compile there: the comptime spec-table filter (wasm_specs) evaluates
    // the full `specs` array, which analyzes every referenced function --
    // this one included (a `@compileError` here does fire on `zig build wasm`).
    // What keeps threadStartImpl's std.Thread.spawn out of that build is the
    // comptime-true branch returning unconditionally, so nothing after it is
    // analyzed. Measured, because the `else` looks load-bearing and is not:
    // a `@compileError` in threadStartImpl fires on neither `if/else` nor a
    // plain early return. Keep the guard; the spelling is free (kaappi#1868).
    if (comptime is_wasm) {
        return PrimitiveError.TypeError; // bare-ok: unregistered on WASM, so unreachable
    } else return threadStartImpl(args);
}

fn threadStartImpl(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-start!", "thread", args[0]);
    try checkThreadOwner(args[0], "thread-start!");

    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);

    if (fiber.status != .created)
        return primitives.argError("thread-start!", "thread has already been started", .{});

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant

    // KEP-0002 Phase 2: copy the thunk into an envelope on THIS (the owning)
    // thread, before ever spawning the child. This closes the old
    // concurrent-copy race (the child used to deepCopy fiber.thunk directly
    // out of the still-running parent heap) and is the only place a channel
    // captured by the thunk can legally promote -- promotion requires
    // gc_instance to be the channel's owner, which is only true here, now,
    // on the parent thread.
    const envelope = shared_channel.Envelope.create(fiber.thunk) catch |err| {
        if (err != error.UncopyableType) return PrimitiveError.OutOfMemory;
        // Mirror the old error shape exactly: thread-start! itself never
        // raises -- the fiber is left .errored (no OS thread ever spawned)
        // and thread-join! surfaces this as "uncaught exception in thread",
        // matching a thunk that fails mid-flight instead of at the boundary.
        // No child_gc/child_vm exists yet for this failure (nothing was ever
        // spawned), so child_registry.storeResult -- which every *post-spawn*
        // failure in threadEntryFn goes through instead -- doesn't apply
        // here: this is the one place a fiber's error state is set directly.
        fiber.current_exception = try makeErrorWithType(.general, "thread thunk contains an uncopyable type (port, continuation, fiber, mutex, condition variable, FFI callback, directory object, environment, ephemeron, guardian, or transport cell), or a channel owned by another thread", types.NIL);
        gc.writeBarrier(&fiber.header, fiber.current_exception.?);
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return args[0];
    };

    // Root the fiber itself: the child writes fiber.status / reads
    // fiber.terminated for the whole run, so it must survive even if the
    // program drops its last reference. Removed at thread-join!. (The
    // thunk needs no separate root -- its envelope snapshot is independent
    // of the parent heap, and fiber.thunk itself is already traced by
    // markFiberState whenever the fiber is.)
    gc.extra_roots.append(gc.allocator, args[0]) catch {
        envelope.deinit();
        return PrimitiveError.OutOfMemory;
    };

    fiber.status = .running;
    // Increment *before* spawning: if the child ran to completion before an
    // increment placed after std.Thread.spawn executed, the decrement in
    // threadEntryFn's defer could fire first and wrap the counter (or drop
    // it one below the true count with other children alive), letting
    // crossThreadWaitPossible wrongly conclude no other thread exists.
    _ = @atomicRmw(usize, &live_child_threads, .Add, 1, .release);
    // #2129 (handle half): count this spawn on the SPAWNING thread's own
    // handle, so a join of the spawner can tell a live descendant apart.
    // The spawner's own fiber is vm.thread_handle (set unconditionally by
    // threadEntryFn; null on the main thread, whose heap is never freed and
    // never joined). Released by the child's threadEntryFn defer once the
    // child's own subtree has drained; a nonzero count means a join of the
    // spawner must retire (not free) its GC/VM, because this child's fiber
    // lives in the spawner's heap and is still dereferenced (terminate
    // flag, status, live-descendant count) for its whole life.
    const spawner: ?*fiber_mod.Fiber = if (vm.thread_handle) |h|
        types.toObject(h).as(fiber_mod.Fiber)
    else
        null;
    if (spawner) |s| {
        _ = @atomicRmw(u32, &s.live_descendants, .Add, 1, .release);
    }
    // Pass the ROOT VM, not this thread's own: threadEntryFn's prologue
    // dereferences it (GC.initForThread's shared symbol tables, and the
    // shared maps), and a middle thread's VM/GC are freed when *it* is
    // joined -- a grandchild still starting (or interning symbols) would
    // then read freed memory (#2129). The root VM lives for the whole
    // process, so every descendant chains its shared state to it.
    const root_vm = vm.root_vm orelse vm;
    // kaappi#2394: (srfi 128) must be registered before ANY child VM
    // struct-copies vm.libraries (threadEntryFn's VM.initForThread) — the
    // copy shares bucket storage with the owner's map, so an off-root lazy
    // load would race it, and off-root exports would be unmarked by every
    // collector. Loading at the process's first thread-start! is always
    // pre-children (the first spawn is necessarily the root: children exist
    // only inside this function) and a read-only no-op for every later one
    // whose registry copy postdates the root's load. Best-effort by design:
    // on failure the loader's detail is cleared so it cannot leak into the
    // next unrelated error — channel-comparator then reports the load
    // failure with its own described message when actually used.
    if (!primitives_fiber.ensureComparatorLibraryLoaded(vm)) {
        vm.last_error_detail_len = 0;
    }
    // #1933: from here on, the root's collector must stop-and-mark live
    // children so a parent-heap object referenced only from a running
    // child's registers is not freed under it. Atomic: threadStartImpl can
    // run on any thread (a child spawning a grandchild) while the root's
    // markRoots reads the field; the stored value is always the same
    // function pointer, but the write must not be a plain store.
    @atomicStore(?*const fn (*memory.GC) void, &root_vm.gc.child_marker, &markLiveChildRoots, .release);
    fiber.os_thread = std.Thread.spawn(.{}, threadEntryFn, .{
        fiber, spawner, gc.allocator, root_vm, envelope,
    }) catch {
        _ = @atomicRmw(usize, &live_child_threads, .Sub, 1, .release);
        // kaappi#2395: every live_child_threads decrement is followed by a
        // ring-all (see threadEntryFn's exit defer for why), this
        // spawn-failure one included, so no parked crossThreadWaitPossible
        // verdict can outlive the count it was computed from.
        reactor_mod.ringAllNotifiers();
        if (spawner) |s| {
            _ = @atomicRmw(u32, &s.live_descendants, .Sub, 1, .release);
        }
        envelope.deinit();
        return PrimitiveError.OutOfMemory;
    };

    return args[0];
}

fn threadEntryFn(fiber: *fiber_mod.Fiber, spawner: ?*fiber_mod.Fiber, allocator: std.mem.Allocator, root_vm: *vm_mod.VM, envelope: *shared_channel.Envelope) void {
    // `root_vm` is the ROOT VM (see threadStartImpl): its struct, GC and
    // shared maps are never freed, so the whole prologue below -- and this
    // thread's later symbol interning into GC.initForThread's shared tables
    // -- cannot race a join of whatever thread spawned this one (#2129).
    // Balances the increment in threadStartFn on every exit path (including
    // the early GC/VM-init failures below), so crossThreadWaitPossible's "is
    // another OS thread still alive" check stays accurate. The ring-all
    // after it (kaappi#2395) is what makes the new count observable without
    // polling: every parked scheduler wakes and re-evaluates its wait — a
    // timed thread-join! on this thread sees the terminal status stored in
    // the body above, and an unrelated cross-thread wait re-runs its
    // crossThreadWaitPossible deadlock verdict against the decremented
    // count. Ordered decrement-then-ring for exactly that second consumer:
    // a ring before the decrement could wake a waiter into re-reading the
    // stale count and re-parking, with no further ring ever coming.
    defer {
        _ = @atomicRmw(usize, &live_child_threads, .Sub, 1, .release);
        reactor_mod.ringAllNotifiers();
    }
    // #1933: tell the parent's collector this thread is gone, so it stops
    // marking this child's (now stale) VM. Runs last, after every other
    // defer -- but the flag is set before the live_child_threads decrement
    // (this defer body runs before that one, which was declared earlier).
    defer child_registry.markExited(@intFromPtr(fiber));
    // #2129 (handle half): release the spawning thread's live-descendant
    // count (incremented in threadStartImpl), but only once this thread's
    // OWN descendant subtree has fully drained. The drain matters: this
    // fiber lives in the spawner's heap, and MY descendants' defers keep
    // dereferencing it (they decrement MY count) -- if I released my
    // spawner's count while a descendant was still running, the spawner's
    // join could read zero and free the heap this fiber lives in under that
    // descendant. Waiting here cannot hang the spawner's join: the join
    // does not join me, and the threads I wait for make progress
    // independently (my thunk has finished, so nothing they need from me
    // will ever come). Runs after envelope.deinit and before the
    // live_child_threads decrement, so main.zig's hasLiveChildThreads still
    // covers the whole wait.
    defer {
        if (spawner) |s| {
            while (@atomicLoad(u32, &fiber.live_descendants, .acquire) > 0) {
                sleepNs(CROSS_THREAD_POLL_NS);
            }
            const old = @atomicRmw(u32, &s.live_descendants, .Sub, 1, .acq_rel);
            if (old == 1) {
                // I was my spawner's last live descendant: if its join has
                // already retired its resources (retireOrFreeChild), free
                // them now -- the subtree has drained, so nothing
                // dereferences the spawner's heap anymore. No quarantine
                // heir from here: the heir handoff appends to the heir's
                // quarantine list from THIS thread, which would race the
                // heir's own concurrent collection; drain instead (weaker
                // #2127 detection under gc-stress, no race).
                if (child_registry.fetchRemoveIfRetired(@intFromPtr(s))) |res| {
                    freeChildResourcesEntry(res, null);
                }
            }
        }
    }
    // envelope is owned solely by this function (unlike the result/exception
    // envelopes built below, which escape into child_registry for the
    // parent to consume) -- every exit path needs it freed exactly once.
    defer envelope.deinit();

    const child_gc = allocator.create(memory.GC) catch {
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };
    child_gc.* = memory.GC.initForThread(allocator, root_vm.gc);

    const child_vm = allocator.create(vm_mod.VM) catch {
        child_gc.deinit();
        allocator.destroy(child_gc);
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };
    @memset(std.mem.asBytes(child_vm), 0);
    child_vm.* = vm_mod.VM.initForThread(child_gc, root_vm) catch {
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

    // The thread handle (the parent-heap fiber make-thread returned) this
    // child runs for, so mutex-state on a mutex this thread locks reports
    // the thread the caller holds -- not the child's internal current
    // fiber, which lives in this child heap (#2125). Set unconditionally,
    // whatever heap the handle lives in: threadStartImpl reads it to
    // maintain this fiber's live-descendant count for EVERY thread, and
    // #2129's retirement protocol keeps the handle's heap alive until this
    // thread's whole descendant subtree has drained, so the handle cannot
    // be freed under us mid-run. mutex-lock!'s owner_thread reporting
    // re-checks root-ownership before publishing the handle (see
    // reportableOwnerHandle), so a middle-heap handle never escapes into a
    // mutex that can outlive the middle's join -- such a child reports its
    // own current fiber instead, the pre-#2125 behaviour. Foreign to this
    // GC either way; the owner roots the handle, and isYoungPointer returns
    // false for it, so no write barrier is needed.
    child_vm.thread_handle = types.makePointer(&fiber.header);

    child_registry.put(@intFromPtr(fiber), .{ .child_gc = child_gc, .child_vm = child_vm }) catch {
        fiber.result = types.VOID;
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        child_vm.deinit();
        allocator.destroy(child_vm);
        child_gc.deinit();
        allocator.destroy(child_gc);
        return;
    };

    // #1933 (half): the child is in the registry from here on, so a
    // collecting parent may stop-and-mark it. Report the quiescent state as
    // soon as callWithArgs returns (or any later path unwinds): the VM is
    // then stable and the parent never waits on a thread that is finishing.
    defer child_vm.setCollectionParked();
    // #1933 (half): a child spawned while the root collector is mid-
    // collection must not read any shared (parent-heap) global until that
    // collection finishes — its snapshot cannot know this child exists, so
    // an object this child reads could be swept. It holds no parent-heap
    // values yet (nothing has executed), so report .parked and wait; the
    // collector's re-snapshot may mark it (a no-op over empty frames), and
    // the wait is what actually closes the race. After it clears, everything
    // read through the shared globals is reachable from the parent's roots
    // at the just-finished mark and therefore alive.
    child_vm.collection_state.store(.parked, .release);
    while (collection_in_progress.load(.acquire)) sleepNs(CROSS_THREAD_POLL_NS);
    // Guarded resume: if the parent armed collection_stop during the wait
    // (its snapshot could include this child even though it is mid-init), the
    // first thing that happens after the handshake is not unread bytecode but
    // a stop at the safepoint.
    child_vm.setCollectionRunning();

    // Copy the thunk out of the envelope into this thread's own fresh heap.
    // thread-start! already ran the forward copy on the parent thread and
    // rejected anything uncopyable before ever spawning this thread, so
    // this copy-out can only fail on OOM.
    const child_thunk = child_gc.deepCopy(envelope.value) catch {
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };

    const result = child_vm.callWithArgs(child_thunk, &.{}) catch {
        if (child_vm.current_fiber) |cf| {
            fiber_mod.abandonFiberMutexes(cf, child_vm.scheduler);
            // A terminated/errored child parked in a rendezvous receive
            // unwinds through here holding its demand token (#1604 review):
            // the parent-side terminate path deliberately never touches an
            // OS thread's fiber, so this child-side release is the only
            // thing standing between thread-terminate! and permanently
            // phantom demand on a channel other threads still use. Runs on
            // the child thread; a promoted channel withdraws under the
            // SharedChannel lock, safe from here.
            fiber_mod.releaseFiberRendezvousToken(cf);
        }
        // Built on this (owning) thread, mirroring thread-start!'s thunk
        // copy: this is the only place a channel raised in the exception
        // can legally promote (gc_instance == child_gc here, not the
        // parent's gc it would be at join time). A `.failed` build (an
        // uncopyable type, or a channel owned by neither this thread nor
        // the parent) still reaches reapOsThread as something diagnostic
        // rather than silently becoming a void join reason.
        const exc_result: JoinResult = if (child_vm.current_exception) |exc|
            if (shared_channel.Envelope.create(exc)) |env|
                .{ .envelope = env }
            else |err|
                .{ .failed = err }
        else
            .none;
        child_registry.storeResult(@intFromPtr(fiber), .none, exc_result);
        @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
        return;
    };

    if (child_vm.current_fiber) |cf| {
        fiber_mod.abandonFiberMutexes(cf, child_vm.scheduler);
        // Normal completion cannot hold a token (the primitives release on
        // their own exits) — symmetric no-op guard, mirroring the unwind
        // path above.
        fiber_mod.releaseFiberRendezvousToken(cf);
    }

    // Store the result in child_resources (not on the fiber) so the parent
    // GC never traverses a child-heap pointer (Race C) -- and, since Phase
    // 2, as an envelope rather than a raw Value, so a channel the thunk
    // created and returned promotes correctly (see the exception path
    // above for why this must run on this thread).
    const join_result: JoinResult = if (result == types.VOID)
        .none
    else if (shared_channel.Envelope.create(result)) |env|
        .{ .envelope = env }
    else |err|
        .{ .failed = err };
    child_registry.storeResult(@intFromPtr(fiber), join_result, .none);
    @atomicStore(fiber_mod.FiberStatus, &fiber.status, .completed, .release);
}

fn threadYieldFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant
    const sched = vm.scheduler orelse {
        std.Thread.yield() catch {};
        return types.VOID;
    };
    // Advisory, like yield in primitives_fiber.zig: arming Yielded under a
    // re-entrant native frame corrupts the signal into a bare "error" (#1184),
    // so yield only when the unwind can reach a scheduler dispatch loop and
    // another fiber is actually runnable.
    if (vm.native_reentry_depth > 0) return types.VOID;
    // Non-consuming O(1) advisory check (see anyRunnable / #1477).
    if (!sched.anyRunnable()) return types.VOID;
    vm.yielded = true;
    return types.VOID;
}

pub const SleepWait = struct {
    pub fn isDone(_: SleepWait) bool {
        return false; // a pure sleep only ever ends via me.timed_out
    }
    // No externalWakePossible and no poll cap: the sleep's own reactor
    // timer bounds every park, and the one cross-thread event that must cut
    // a sleep short -- thread-terminate! from another OS thread (#1982) --
    // rings this thread's notifier directly since kaappi#2395 (the victim's
    // wake handle is published on its thread handle; see Fiber.os_notifier),
    // popping the park so runSchedulerStep's per-iteration waitTerminated
    // check fires immediately. Before that, terminate was observed only by
    // polling, and the 1 ms cap this Ctx carried made a child's
    // (thread-sleep! 60) wake 60,000 times (~5k involuntary context
    // switches and ~0.04s CPU for a pair of 2.5s/3.0s sleeps, vs 33
    // switches and 0.00s for a true block).
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
        // Saturation + saturating add (#1983): a duration too large for the
        // u64 nanosecond clock (+inf.0, 1e300, an overflowed computation)
        // saturates to a deadline that never fires -- an unbounded sleep,
        // per the SRFI-18 "+inf.0 never times out" convention -- where the
        // old @intFromFloat aborted the process uncatchably.
        const deadline = fiber_mod.clockNs() +| saturatedNsFromSeconds(seconds);

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

    // SRFI 181: a custom port callback (dispatched_from_scheduler is
    // always false for it, so the park branch above never triggers) that
    // calls thread-sleep! would otherwise fall into the unbounded
    // recursive scheduler drive below. Reject it instead -- and since this
    // error (unlike Yielded) isn't covered by the errdefer above (that
    // errdefer's watch window already closed once its enclosing if-block
    // was left behind), clean up the just-armed timer ourselves so it
    // can't fire later against a fiber that's no longer expecting it.
    if (ctx.vm.in_custom_port_callback > 0) {
        me.deadline_ns = null;
        ctx.reactor.removeTimer(me);
        return fiber_mod.raiseCustomPortCallbackBlocked(ctx.vm);
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
        return types.rationalToF64(r.numerator, r.denominator);
    }
    if (types.isPointer(v) and types.toObject(v).tag == .srfi18_time) {
        const t = types.toObject(v).as(types.Srfi18Time);
        const rt = platform.realTime();
        const now: f64 = @as(f64, @floatFromInt(rt.sec)) + @as(f64, @floatFromInt(rt.nsec)) / 1e9;
        const target: f64 = @as(f64, @floatFromInt(t.seconds)) + @as(f64, @floatFromInt(t.nanoseconds)) / 1e9;
        return target - now;
    }
    return PrimitiveError.TypeError; // bare-ok: type guard
}

fn threadTerminateFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-terminate!", "thread", args[0]);
    try checkThreadOwner(args[0], "thread-terminate!");

    const ctx = try ensureScheduler();
    const fiber = types.toObject(args[0]).as(fiber_mod.Fiber);

    // #1984: "If the _thread_ is not already terminated" (SRFI-18 6.2.3).
    // Terminating a thread that has already finished must be a no-op. The
    // old code stored `terminated` BEFORE this status check, and
    // threadJoinResult tests `terminated` first — so terminating a thread
    // that had already completed retroactively erased the result it returned
    // (and a raising thread's end-exception), and a later thread-join!
    // reported terminated-thread-exception instead of the result. The status
    // load here is acquire and threadEntryFn's completion store is release:
    // a thread whose completion is already visible is skipped; a terminate
    // that lands before that release store is, per the spec, a termination
    // that occurred before the thread finished.
    const status = @atomicLoad(fiber_mod.FiberStatus, &fiber.status, .acquire);
    if (status == .completed or status == .errored) return types.VOID;

    // Atomic: for OS threads the child VM reads this flag concurrently (the
    // bytecode safepoint, and runSchedulerStep's waitTerminated).
    @atomicStore(bool, &fiber.terminated, true, .monotonic);

    // kaappi#2395: ring the victim thread's reactor so a park in a native
    // wait (thread-sleep!, mutex-lock!, condvar or join wait) is cut short
    // NOW -- waitTerminated used to observe the store above only at the 1 ms
    // poll cap the SRFI-18 wait Ctxs carried, and with those caps gone this
    // ring is what keeps #1982 closed. Strictly after the flag store, so
    // the woken wait's re-check sees it (notify's release store pairs with
    // the consume protocol's acquire swap). The probe is a no-op CAS -- an
    // atomic RMW, not a plain load -- which orders it against the victim's
    // publishing Xchg (fiber.ensureScheduler) exactly as NotifierList's
    // protocol note argues: either this sees the handle and rings (a ring
    // outpacing the park still ends it -- the OS-level wake persists until
    // polled), or the victim's publication reads-from this probe and its
    // post-publication checks see the flag. Null for a local fiber, a
    // never-started handle, and a child that has not created its reactor
    // yet -- all of which observe termination through their existing local
    // paths (this function's own status flip, or the bytecode safepoint).
    if (@cmpxchgStrong(?*reactor_mod.ThreadNotifier, &fiber.os_notifier, null, null, .acq_rel, .acquire)) |present| {
        present.?.notify();
    }

    // Abandon a *local* fiber's held mutexes here: it lives in this
    // scheduler on this thread, so walking its owned-mutexes list is
    // race-free, and it will never run again to abandon them itself. An OS
    // thread instead abandons its own mutexes when it observes `terminated`
    // and unwinds (threadEntryFn's self-abandon) — its owned-mutexes list is
    // maintained on *its* thread, so the parent must not touch it from here
    // (#1458).
    if (fiber.os_thread == null) {
        fiber_mod.abandonFiberMutexes(fiber, ctx.sched);
        // Same ownership reasoning for a held rendezvous demand token
        // (KEP-0002 §6 amended, #1602): this path flips the victim's status
        // directly, bypassing retireSlot, and the victim never runs again
        // to release it itself. An OS thread's fiber lives in the child's
        // heap — its own unwind releases the token there.
        fiber_mod.releaseFiberRendezvousToken(fiber);
    }

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
    // Same reasoning, KEP-0002 Phase 3 (#1468): a fiber parked on a
    // promoted channel sits in the scheduler's shared-waiter registry
    // (fiber.zig), not just .waiting -- pull it out so a later sweep
    // never touches a slot addFiber has since reused for another fiber.
    ctx.sched.removeSharedWaiter(fiber);
    @atomicStore(fiber_mod.FiberStatus, &fiber.status, .errored, .release);
    ctx.sched.wakeWaiters(fiber);

    if (fiber == ctx.vm.current_fiber) {
        // #1984: self-termination must end the thread the way the join sees
        // it. The join operates on the HANDLE fiber — a different object
        // from this thread's current fiber (the handle lives in the parent
        // heap, the current fiber in the child's) — and threadJoinResult
        // gates on the handle's `terminated` flag. Mark the handle too, or a
        // thread terminating itself would join as uncaught-exception with a
        // void reason instead of terminated-thread-exception. The store is
        // on the parent-heap handle, exactly like an external terminate's
        // store: the parent's join (thread.join() in reapOsThread)
        // synchronizes with this thread's exit, so threadJoinResult's plain
        // read is safe. Null on the main thread and on local fibers.
        if (ctx.vm.thread_handle) |h| {
            const handle = types.toObject(h).as(fiber_mod.Fiber);
            @atomicStore(bool, &handle.terminated, true, .monotonic);
        }
        ctx.vm.yielded = true;
    }
    return types.VOID;
}

fn sleepNs(ns: u64) void {
    platform.sleepNs(ns);
}

/// Wait Ctx for thread-join! on an OS-thread target (kaappi#2395): a
/// started thread, or a make-thread handle a sibling fiber this drive
/// dispatches may yet start (the isDone shape covers the whole
/// created → running → terminal arc either way). The terminal status is
/// stored by the child with .release; the exit ring-all that follows it
/// (threadEntryFn's outermost defer) is what pops the joiner's park, so no
/// poll cadence is needed.
pub const OsJoinWait = struct {
    target: *fiber_mod.Fiber,
    pub fn isDone(self: OsJoinWait) bool {
        const st = @atomicLoad(fiber_mod.FiberStatus, &self.target.status, .acquire);
        return st == .completed or st == .errored;
    }
    // A live OS thread's exit always rings every reactor, so once the
    // target is started an external wake is guaranteed-possible. A
    // never-started handle can only be resolved by a fiber of THIS thread
    // (thread-start!/thread-terminate! are owner-thread-only per
    // checkThreadOwner), which the drive's local dispatch covers — no
    // external source exists for it, and saying so is what lets
    // parkOnReactor still diagnose the genuinely-stuck case. os_thread is
    // written by this same thread only (threadStartImpl/reapOsThread), so
    // the plain read is race-free.
    pub fn externalWakePossible(self: OsJoinWait) bool {
        return self.target.os_thread != null;
    }
};

/// Parks thread-join! until `target` reaches a terminal status or
/// `deadline_ns` expires — the notifier-woken replacement (kaappi#2395) for
/// the old sleepNs(1ms) status polls, and the piece that lets a timed join
/// dispatch runnable sibling fibers instead of starving them (the
/// never-started half of #2194: a sibling's thread-start! on the joined
/// handle used to be starved forever by the poll loop). Returns true when
/// the target is terminal, false on timeout. Raises the deadlock error
/// when the wait can provably never resolve: an unstarted handle, nothing
/// locally runnable, and no other OS thread left whose exit could change
/// that — the same verdict the fiber path raises, where the old code hung
/// in the poll loop.
fn driveOsJoinWait(target: *fiber_mod.Fiber, deadline_ns: ?u64) PrimitiveError!bool {
    if ((OsJoinWait{ .target = target }).isDone()) return true;
    if (deadline_ns) |d| {
        if (fiber_mod.clockNs() >= d) return false;
    }

    const ctx = try ensureScheduler();
    const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;

    // No enrollWaiter: nothing local ever completes the handle (the child
    // finishes on its own OS thread), so there is no local wake to index
    // for — the resolutions are the deadline timer and the notifier rings.
    // waiting_on is still set for markFiberState's tracing and diagnostics,
    // mirroring the fiber path.
    me.waiting_on = types.makePointer(&target.header);
    me.status = .waiting;
    me.timed_out = false;
    if (deadline_ns) |d| {
        me.deadline_ns = d;
        try ctx.reactor.addTimer(d, me);
    }

    const done = try fiber_mod.runSchedulerStep(OsJoinWait, .{ .target = target }, ctx.vm, ctx.sched, me);
    // No local wake exists to cancel the timer through doWake, so a
    // non-timeout resolution must pull it explicitly (the mutexLockFn
    // pattern) or it later fires against a reused fiber slot.
    if (deadline_ns != null) ctx.reactor.removeTimer(me);
    me.deadline_ns = null;

    if (me.timed_out) {
        me.timed_out = false;
        return false;
    }
    if (!done) {
        // Only the never-started shape can reach here (externalWakePossible
        // is constant-true once os_thread is set, and parkOnReactor never
        // reports deadlock with an external wake declared). me.waiting_on,
        // not a caller slice: registers may have been reallocated by the
        // drive. raiseError always returns an error, so the `try` is the
        // exit; the trailing return only satisfies the type.
        _ = try raiseError(.general, "thread-join!: deadlock — thread was never started and no runnable fiber can start it (all fibers blocked)", me.waiting_on);
        return false;
    }
    return true;
}

fn threadJoinFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFiber(args[0]))
        return primitives.typeError("thread-join!", "thread", args[0]);
    // Before anything reads target.os_thread/status/result: a foreign fiber
    // (reached only via a shared global) is the double-join UB and
    // loser-reads-VOID race from #1484. Self-join stays a distinct, friendlier
    // error below -- the current fiber is always this GC's own, so it passes
    // here first.
    try checkThreadOwner(args[0], "thread-join!");

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
        deadline_ns = try timeoutToDeadlineNs("thread-join!", args[1]);
        if (args.len > 2) {
            has_timeout_val = true;
            timeout_val = args[2];
        }
    }

    // Captured before any scheduler drive below: args is a slice into
    // vm.registers, which runSchedulerStep may reallocate while dispatching
    // sibling fibers (the mutexLockFn precedent). timeout_val above is a
    // plain Value copy and stays traced through this fiber's saved
    // registers, so it needs no re-capture.
    const fiber_val = args[0];

    // OS thread path. A timed join drives the scheduler parked on the
    // reactor — woken by the child's exit ring-all or the deadline timer
    // (kaappi#2395), where it used to poll status at 1 ms with every local
    // sibling starved. An untimed join keeps its original shape: straight
    // into reapOsThread's blocking thread.join(), which was always
    // event-driven.
    if (target.os_thread != null) {
        if (deadline_ns != null) {
            if (!try driveOsJoinWait(target, deadline_ns)) {
                if (has_timeout_val) return timeout_val;
                return raiseError(.join_timeout, "thread-join! timed out", types.VOID);
            }
        }
        return reapOsThread(target, fiber_val);
    }

    // Never-started target, in two kinds discriminated by sched_idx (set only
    // by addFiber; a make-thread object is never added to any scheduler and
    // leaves it at 0):
    //
    //  * A make-thread handle awaiting thread-start! (sched_idx == 0): drive
    //    the scheduler via driveOsJoinWait. Only a fiber of this same thread
    //    can start or terminate the handle (checkThreadOwner gates both), so
    //    dispatching siblings is what lets the status change at all — the
    //    1 ms poll this replaces (#878's shape, kaappi#2395) starved exactly
    //    that fiber, so a joined handle a sibling would have started hung
    //    until the timeout (the never-started half of #2194). os_thread
    //    alone is NOT a safe discriminator here -- a handle about to be
    //    started has os_thread == null for the whole window before
    //    thread-start!'s std.Thread.spawn; OsJoinWait's status shape covers
    //    the started-mid-wait continuation either way.
    //
    //  * A (kaappi fibers) spawn'd fiber (sched_idx != 0) still in .created:
    //    only THIS thread's cooperative scheduler can dispatch it (#2194).
    //    Fall through to the fiber path below, which drives the scheduler
    //    with the local-wake machinery (enrollWaiter/TargetWait) a real
    //    fiber needs.
    if (target.sched_idx == 0 and
        @atomicLoad(fiber_mod.FiberStatus, &target.status, .acquire) == .created)
    {
        if (!try driveOsJoinWait(target, deadline_ns)) {
            if (has_timeout_val) return timeout_val;
            return raiseError(.join_timeout, "thread-join! timed out", types.VOID);
        }
        if (target.os_thread != null)
            return reapOsThread(target, fiber_val);
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
        ctx.sched.enrollWaiter(me); // #1530: O(1) wake when the joined fiber completes
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
        // #1933: a CHILD joining its own child blocks in a raw pthread join
        // that never reaches the dispatch-loop safepoint and never reports a
        // quiescent state on its own. Without the in-native report, the
        // parent's collector waits forever for this VM to leave `.running`
        // while the grandchild being joined waits on `collection_in_progress`
        // — a livelock (seen as a multi-minute hang in
        // channel-promoted-owner-1934 under -Dgc-stress). During the join the
        // VM's frames/registers are stable, so it is safe to mark. Function-
        // scope defer: a block-scoped one would fire before thread.join().
        const join_vm: ?*vm_mod.VM = if (vm_mod.vm_instance) |vm|
            if (!vm.owns_globals) vm else null
        else
            null;
        if (join_vm) |vm| vm.setCollectionInNative();
        defer if (join_vm) |vm| vm.setCollectionRunning();
        thread.join();
        target.os_thread = null;
    }

    // kaappi#2395: drop the counted reference the child published for
    // thread-terminate! rings (Fiber.os_notifier). Past thread.join() the
    // child can never publish again, and terminate on a joined thread
    // no-ops at its status check, so nulling here closes the field's
    // lifecycle on the owner thread; a never-joined handle's reference is
    // instead dropped by freeObject's `.fiber` arm at GC teardown.
    if (@atomicRmw(?*reactor_mod.ThreadNotifier, &target.os_notifier, .Xchg, null, .acq_rel)) |n| {
        reactor_mod.releaseNotifier(n);
    }

    target.frame_count = 0;

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const fiber_obj = types.toObject(fiber_val);

    // Remove the fiber from extra_roots (added by thread-start! to keep it
    // alive while the child runs; the child is done now). The thunk itself
    // is no longer separately rooted -- thread-start! consumed it into an
    // envelope before ever spawning the child.
    for (gc.extra_roots.items, 0..) |v, idx| {
        if (v == fiber_val) {
            _ = gc.extra_roots.swapRemove(idx);
            break;
        }
    }
    const fiber_key = @intFromPtr(target);

    // Retrieve the result/exception envelope from child_registry (stored
    // there, not on the fiber, so the parent GC never traverses a
    // child-heap pointer). KEP-0002 Phase 2: both crossed by envelope, built
    // on the child thread that owns them -- the same mechanism thread-start!
    // uses for the thunk, and the only way a channel the thunk created or
    // raised can legally promote. takeResult (not a plain get) atomically
    // clears both fields under the registry lock, so a fiber joined twice
    // concurrently -- reachable via a shared global, since fiber ownership
    // itself is otherwise unchecked -- can't hand the same *Envelope to two
    // callers, which would double-free it.
    const res = child_registry.takeResult(fiber_key);
    if (target.status == .completed) {
        switch (res.result) {
            .none => {},
            .envelope => |env| {
                target.result = gc.deepCopy(env.value) catch {
                    target.result = types.VOID;
                    env.deinit();
                    retireOrFreeChild(target, fiber_key);
                    return PrimitiveError.OutOfMemory;
                };
                gc.writeBarrier(fiber_obj, target.result);
                env.deinit();
            },
            .failed => |err| {
                retireOrFreeChild(target, fiber_key);
                if (err == error.UncopyableType) {
                    // Same DeepCopyError for two different causes: a
                    // genuinely uncopyable type (port, continuation, ...),
                    // or a channel reached by the child through a shared
                    // global rather than the thunk/message it was legally
                    // handed -- gc_deep_copy.zig's `.channel` arm returns
                    // UncopyableType for both, so this message covers both
                    // rather than mis-describing the second as a type error.
                    return raiseError(.general, "thread-join!: result contains an uncopyable type (port, continuation, fiber, mutex, condition variable, FFI callback, directory object, environment, ephemeron, guardian, or transport cell), or a channel owned by another thread", types.VOID);
                }
                return PrimitiveError.OutOfMemory;
            },
        }
    }
    if (target.status == .errored) {
        switch (res.exception) {
            .none => {},
            .envelope => |exc_env| {
                target.current_exception = gc.deepCopy(exc_env.value) catch null;
                if (target.current_exception) |cv|
                    gc.writeBarrier(fiber_obj, cv);
                exc_env.deinit();
            },
            .failed => {
                // The exception itself couldn't cross the boundary (an
                // uncopyable type, or a channel owned by neither the
                // parent nor the child -- e.g. reached via a shared
                // global from inside the raising thunk). Before this a
                // bare `catch null` here silently left the join reason as
                // void; synthesize something diagnostic instead of losing
                // the failure entirely.
                target.current_exception = makeErrorWithType(
                    .general,
                    "uncaught exception in thread: the exception value contains an uncopyable type, or a channel owned by another thread",
                    types.VOID,
                ) catch null;
                if (target.current_exception) |cv|
                    gc.writeBarrier(fiber_obj, cv);
            },
        }
    }
    retireOrFreeChild(target, fiber_key);
    return threadJoinResult(target);
}

/// #2129 (handle half): free a joined thread's GC/VM only when nothing can
/// still dereference its heap. The joined thread's OWN fiber is in the
/// CALLER's heap (checkThreadOwner), but the fibers of any thread it started
/// are in ITS heap -- and a descendant dereferences its own fiber (terminate
/// flag, status, live-descendant count) for its whole life, which can extend
/// past this join. So when the target has live descendants, keep the
/// resources (retire the registry entry) and let the last descendant's
/// threadEntryFn defer free them once the subtree drains; they are otherwise
/// freed at process exit (#1792's pattern). When the count is already zero
/// the whole subtree has drained -- each child's defer waits for its own
/// subtree before releasing the count -- so freeing now is safe.
fn retireOrFreeChild(target: *fiber_mod.Fiber, fiber_key: usize) void {
    if (@atomicLoad(u32, &target.live_descendants, .acquire) == 0) {
        freeChildResources(fiber_key);
        return;
    }
    child_registry.markRetired(fiber_key);
    // Close the race where the last descendant's defer decremented the count
    // (old == 1) and passed its fetchRemoveIfRetired window while the entry
    // was not yet marked retired: re-read; a count of zero means the subtree
    // has drained and nothing dereferences this heap, so free it ourselves.
    // Both free paths take the registry lock (fetchRemove), so exactly one
    // wins and the GC/VM are freed once.
    if (@atomicLoad(u32, &target.live_descendants, .acquire) == 0) {
        freeChildResources(fiber_key);
    }
}

fn freeChildResources(fiber_key: usize) void {
    if (child_registry.fetchRemove(fiber_key)) |res| {
        freeChildResourcesEntry(res, memory.gc_instance);
    }
}

/// Frees one joined-or-retired child's GC/VM. `heir` names the GC that
/// inherits the freed heap's #2127 quarantine slots; see the two callers for
/// when a null heir is deliberate.
fn freeChildResourcesEntry(res: ChildThreadResources, heir: ?*memory.GC) void {
    const allocator = res.child_gc.allocator;
    res.child_vm.deinit();
    allocator.destroy(res.child_vm);
    if (heir) |h| {
        // #2127: the joining parent may still hold a value pointing into this
        // child's heap (`mutex-state` hands out the owning *Fiber*). Give the
        // freed header slots to the parent's quarantine rather than the
        // allocator, so the parent's next mark reads FREED_OWNER and panics
        // instead of finding a recycled object. gc-stress only; a no-op
        // elsewhere. Safe here -- the joining parent's thread, past
        // reapOsThread's thread.join() -- because the handoff appends to the
        // heir's quarantine list from this very thread; threadEntryFn's
        // descendant-side free passes null instead, since handing off from
        // THAT thread would race the heir's own concurrent collection.
        if (h != res.child_gc) res.child_gc.setQuarantineHeir(h);
    }
    res.child_gc.deinit();
    allocator.destroy(res.child_gc);
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
    if (m.owner_thread != types.VOID) return m.owner_thread;
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

/// #2129 (handle half): the thread handle mutex-state may report for a mutex
/// this thread locks. Publish the parent-heap handle only when it is
/// ROOT-heap (never freed): a middle-thread handle lives in the creator's
/// heap, which its join frees while a mutex this thread locked -- and any
/// mutex-state on it -- can outlive that join. Fall back to `fallback` (this
/// thread's own current fiber, in its never-freed-if-unjoined heap) in every
/// other case, the pre-#2125 behaviour. Safe to read `h` here: the #2129
/// retirement protocol keeps the handle's heap alive until this thread's
/// whole descendant subtree has drained, and this runs while the thread is
/// still executing.
fn reportableOwnerHandle(vm: *const vm_mod.VM, fallback: Value) Value {
    if (vm.thread_handle) |h| {
        const root_vm = vm.root_vm orelse return fallback;
        if (types.toObject(h).owner == root_vm.gc.id) return h;
    }
    return fallback;
}

// #1984: SRFI-18 6.4.2's "if T is terminated" test for mutex-lock!'s
// owner argument: the owner fiber's terminate flag is set by
// thread-terminate!. Read atomically — the owner may be a fiber on another
// OS thread whose thread-terminate! is concurrent (the same cross-thread
// read the child VM's safepoint does on its own handle).
fn isTerminatedOwner(v: Value) bool {
    if (!types.isFiber(v)) return false;
    const fiber = types.toObject(v).as(fiber_mod.Fiber);
    return @atomicLoad(bool, &fiber.terminated, .acquire);
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

// Records `m_val` on the fiber that just took ownership so
// abandonFiberMutexes can release it if the fiber dies still holding it
// (#1458) — including a mutex from another thread's heap, which the old
// heap-scan could never find. Only ever touches `fiber`'s own list, and is
// only called with the current fiber (the acquirer), so it never races
// another thread mutating this list.
//
// Before appending it first drops entries whose mutex is no longer locked:
// an unlocked mutex is never owned, so this can't drop one we'd need to
// abandon, and it keeps the list bounded to currently-held mutexes even
// when a lock/unlock pair repeats or another thread unlocked one of ours.
// The `== m_val` pass dedups: a mutex we still hold (unlock-then-relock with
// no intervening prune) survives the sweep, so appending again would double
// it.
fn trackOwnedMutex(fiber: *fiber_mod.Fiber, m_val: Value) void {
    const gc = memory.gc_instance orelse return;
    var already = false;
    var i: usize = 0;
    while (i < fiber.owned_mutexes.items.len) {
        const v = fiber.owned_mutexes.items[i];
        if (v == m_val) {
            already = true;
            i += 1;
        } else if (!@atomicLoad(bool, &types.toMutex(v).locked, .acquire)) {
            _ = fiber.owned_mutexes.swapRemove(i);
        } else {
            i += 1;
        }
    }
    if (already) return;
    // Best-effort: an OOM here only means this one mutex won't be abandoned
    // if the fiber dies holding it (reverting to the pre-#1458 gap for it).
    // The lock itself already succeeded, so failing the primitive now would
    // be worse — the caller would believe the lock failed while it is held.
    fiber.owned_mutexes.append(gc.allocator, m_val) catch {};
    // #1961: this list is also an old→young edge when a promoted fiber locks
    // a fresh mutex — FiberScheduler.markRoots' explicit markFiberState pass
    // covers it as a root, and this keeps the remembered set complete for it
    // like every other Value store into an old container.
    gc.writeBarrier(&fiber.header, m_val);
}

fn mutexLockFn(args: []const Value) PrimitiveError!Value {
    if (!types.isMutex(args[0]))
        return primitives.typeError("mutex-lock!", "mutex", args[0]);

    const m = types.toMutex(args[0]);

    if (tryClaimMutex(m)) {
        const ctx = try ensureScheduler();
        if (ctx.vm.current_fiber) |cf| {
            const cf_val = types.makePointer(&cf.header);
            // The owner's thread handle: the explicit owner arg when given,
            // else this thread's handle -- for an OS-thread child that is
            // the parent-heap handle (vm.thread_handle), NOT cf_val, which
            // belongs to the child heap and would dangle past join (#2125).
            // Compute both before publishing either, and publish owner_thread
            // first: mutex-state gates on owner_thread alone, so a concurrent
            // reader can never observe a partially initialized owner pair.
            const owner = resolveMutexOwner(args, cf_val);
            const owner_thread = resolveMutexOwner(args, reportableOwnerHandle(ctx.vm, cf_val));
            // #1984: SRFI-18 6.4.2 -- "if T is terminated the _mutex_
            // becomes unlocked/abandoned". An explicit owner argument naming
            // a terminated thread must not be recorded as owner: the mutex
            // would be locked/owned by a thread that can never unlock it.
            // It becomes unlocked/abandoned instead. Not an
            // abandoned-mutex raise: the mutex was NOT unlocked/abandoned
            // before this state change, so mutex-lock! returns #t per the
            // spec's algorithm (only a mutex abandoned BEFORE the change
            // raises). The claim made above is released back.
            if (owner != types.VOID and isTerminatedOwner(owner)) {
                m.owner_thread = types.VOID;
                m.owner = types.VOID;
                @atomicStore(bool, &m.abandoned, true, .release);
                @atomicStore(bool, &m.locked, false, .release);
                // The claim above released the mutex back into
                // unlocked/abandoned; wake any local waiter enrolled from a
                // previous foreign unlock so it observes the release (and
                // raises abandoned on its re-lock) instead of sitting parked
                // until its deadline or the deadlock error — and ring any
                // waiter parked on another thread's scheduler, which the
                // local wake can never reach (kaappi#2395). Mirrors the
                // slow path's wake below.
                ctx.sched.wakeMutexWaiters(args[0]);
                reactor_mod.ringSlotWaiters(&m.cross_waiters);
                return types.TRUE;
            }
            m.owner_thread = owner_thread;
            m.owner = owner;
            if (memory.gc_instance) |gc| {
                gc.writeBarrier(&m.header, m.owner);
                gc.writeBarrier(&m.header, m.owner_thread);
            }
            // Only track when *this* fiber became the owner: an explicit
            // owner arg naming another fiber (possibly on another thread)
            // must not append to this fiber's list.
            if (m.owner == cf_val) trackOwnedMutex(cf, args[0]);
        } else {
            m.owner = resolveMutexOwner(args, types.VOID);
            m.owner_thread = m.owner;
            if (memory.gc_instance) |gc| gc.writeBarrier(&m.header, m.owner);
        }
        if (tryClaimAbandoned(m)) return raiseError(.abandoned_mutex, "mutex was abandoned", types.VOID);
        return types.TRUE;
    }

    var deadline: ?u64 = null;
    if (args.len > 1) {
        deadline = try timeoutToDeadlineNs("mutex-lock!", args[1]);
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

    // kaappi#2395: register this thread's wake handle on the mutex BEFORE
    // the wait's first state check (runSchedulerStep's isDone), so a
    // cross-thread unlock/abandon that lands after that check finds the
    // registration and rings — registration-before-check on this side,
    // store-before-ring on the unlocker's, is the lost-wakeup protocol
    // NotifierList's doc lays out. Registered once for the whole wait (the
    // list is persistent, unlike a SharedChannel's ring-clears) and
    // dropped via defer on every exit, error unwinds included.
    // Unconditional rather than gated on crossThreadWaitPossible(): a
    // thread that first shares this mutex mid-wait would otherwise park
    // unregistered with nothing re-arming the registration.
    const cross_waiters = reactor_mod.slotWaiterList(&m.cross_waiters) catch return PrimitiveError.OutOfMemory;
    cross_waiters.register(ctx.reactor.notifyHandle()) catch return PrimitiveError.OutOfMemory;
    defer cross_waiters.deregister(ctx.reactor.notifyHandle());

    me.waiting_on = mutex_val;
    me.status = .waiting;
    me.timed_out = false;
    ctx.sched.enrollWaiter(me); // #1530: O(1) wake on mutex unlock / abandonment
    if (deadline) |d| {
        me.deadline_ns = d;
        try ctx.reactor.addTimer(d, me);
    }

    // runSchedulerStep only returns done once it *observes* m.locked ==
    // false; claiming it is still a race against any other thread making
    // the same observation, so retry the claim and go back to waiting on
    // failure instead of assuming we won. When runSchedulerStep reports
    // "not done" (parkOnReactor found nothing locally runnable, no pending
    // timer/fd event, and no external wake declared), that's a genuine
    // deadlock unless another OS thread appeared between the park's
    // crossThreadWaitPossible verdict and the re-check here — then just
    // loop; the next park re-evaluates and blocks on the notifier
    // (kaappi#2395: no polling sleep — the unlock ring is the wakeup).
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
            // A local wake dropped me's index entry; re-enroll so the next
            // unlock finds me again (#1530). No-op via the tail check when a
            // cross-thread resolution left the entry in place.
            ctx.sched.enrollWaiter(me);
            continue;
        }
        if (!crossThreadWaitPossible()) {
            if (deadline != null) ctx.reactor.removeTimer(me);
            me.deadline_ns = null;
            return raiseError(.general, "mutex-lock!: deadlock — mutex will never be released (all fibers blocked)", types.VOID);
        }
        // Same timer restoration as in the `done` branch: a local wake
        // earlier in this loop may have already canceled the timer, and
        // that state persists into this branch too.
        if (deadline) |d| {
            ctx.reactor.removeTimer(me);
            try ctx.reactor.addTimer(d, me);
        }
        me.status = .waiting;
        ctx.sched.enrollWaiter(me); // #1530: re-index before re-parking (see above)
    }
    // A cross-thread resolution never runs local wake bookkeeping (the
    // unlocking thread's scheduler/reactor doesn't even know `me` exists),
    // so any timer registered above may still be pending; a local wake
    // already canceled it (removeTimer is a no-op then), but skipping this
    // for the cross-thread path would leave a stale entry that could later
    // fire against a reused fiber slot.
    if (deadline != null) ctx.reactor.removeTimer(me);
    me.deadline_ns = null;

    const owner_fiber = types.makePointer(&me.header);
    const owner_handle = reportableOwnerHandle(ctx.vm, owner_fiber);
    // Same resolution for the reported owner thread (see the fast path):
    // an OS-thread child reports its parent-heap handle, not me.header
    // (#2125). Computed before publishing either field and owner_thread
    // stored first, as in the fast path.
    const owner = if (owner_arg) |oa|
        (if (types.isFiber(oa)) oa else if (oa == types.FALSE) types.VOID else owner_fiber)
    else
        owner_fiber;
    const owner_thread = if (owner_arg) |oa|
        (if (types.isFiber(oa)) oa else if (oa == types.FALSE) types.VOID else owner_handle)
    else
        owner_handle;
    // #1984: SRFI-18 6.4.2 -- "if T is terminated the _mutex_ becomes
    // unlocked/abandoned" (see the fast path for the full reasoning). `me`
    // claimed the mutex above (the tryClaimMutex after the wait); the
    // terminated-owner case releases it back into unlocked/abandoned instead
    // of recording a dead owner. Not an abandoned-mutex raise: the mutex
    // was locked, not unlocked/abandoned, before this state change. Wake
    // waiters so they observe the release and retry (and hit the abandoned
    // raise the spec prescribes for a subsequent lock).
    if (owner != types.VOID and isTerminatedOwner(owner)) {
        m.owner_thread = types.VOID;
        m.owner = types.VOID;
        @atomicStore(bool, &m.abandoned, true, .release);
        @atomicStore(bool, &m.locked, false, .release);
        ctx.sched.wakeMutexWaiters(mutex_val);
        reactor_mod.ringSlotWaiters(&m.cross_waiters); // kaappi#2395: see the fast path
        return types.TRUE;
    }
    m.owner_thread = owner_thread;
    m.owner = owner;
    if (memory.gc_instance) |gc| {
        gc.writeBarrier(&m.header, m.owner);
        gc.writeBarrier(&m.header, m.owner_thread);
    }
    // Track only when `me` itself became the owner (see the fast path).
    if (m.owner == types.makePointer(&me.header)) trackOwnedMutex(me, mutex_val);

    if (tryClaimAbandoned(m)) return raiseError(.abandoned_mutex, "mutex was abandoned", types.VOID);
    return types.TRUE;
}

pub const MutexWait = struct {
    m: *types.Mutex,
    pub fn isDone(self: MutexWait) bool {
        return !@atomicLoad(bool, &self.m.locked, .acquire);
    }
    // kaappi#2395: a cross-thread resolution arrives as a notifier ring —
    // the unlocker/abandoner rings the mutex's NotifierList (this thread
    // registered before its first state check; see mutexLockFn), a
    // terminate rings this thread's own handle, and a thread exit rings
    // every reactor — so the park blocks until one lands instead of
    // re-checking at the 1 ms cap this Ctx used to carry. The verdict still
    // matters for the deadlock check: with no other OS thread alive nothing
    // external can ever ring, and parkOnReactor's "nothing can wake this"
    // report is what the caller turns into the deadlock error.
    pub fn externalWakePossible(self: MutexWait) bool {
        _ = self;
        return crossThreadWaitPossible();
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
    m.owner_thread = types.VOID;
    // #1984: "Unlocks the mutex by making it unlocked/**not-abandoned**"
    // (SRFI-18 6.4.2). The only other writer of `abandoned` is
    // tryClaimAbandoned inside mutex-lock!; a plain unlock of a mutex whose
    // previous owner died left the flag set, so the next mutex-lock! raised
    // a spurious abandoned-mutex-exception on a properly unlocked mutex.
    // Cleared before the release-store, like owner: an acquirer that wins
    // the locked CAS after it is guaranteed to see not-abandoned.
    @atomicStore(bool, &m.abandoned, false, .release);
    @atomicStore(bool, &m.locked, false, .release);

    const ctx = try ensureScheduler();
    ctx.sched.wakeMutexWaiters(args[0]);
    // kaappi#2395: waiters parked on other OS threads' schedulers never see
    // the local wake above — ring their reactors so they re-race the claim
    // now. Strictly after the locked release-store, per the lost-wakeup
    // protocol (NotifierList's doc).
    reactor_mod.ringSlotWaiters(&m.cross_waiters);

    if (cv) |c| {
        var deadline: ?u64 = null;
        if (args.len > 2) {
            deadline = try timeoutToDeadlineNs("mutex-unlock!", args[2]);
        }

        const me = ctx.vm.current_fiber orelse return PrimitiveError.OutOfMemory;

        // kaappi#2395: same registration-before-first-state-check protocol
        // as mutexLockFn, against the condvar's own waiter list; the ring
        // arrives from condition-variable-signal!/-broadcast! right after
        // the generation bump CondVarWait.isDone re-checks.
        const cross_waiters = reactor_mod.slotWaiterList(&c.cross_waiters) catch return PrimitiveError.OutOfMemory;
        cross_waiters.register(ctx.reactor.notifyHandle()) catch return PrimitiveError.OutOfMemory;
        defer cross_waiters.deregister(ctx.reactor.notifyHandle());

        me.waiting_on = args[1];
        me.status = .waiting;
        me.timed_out = false;
        ctx.sched.enrollWaiter(me); // #1530: O(1) wake on signal / broadcast
        if (deadline) |d| {
            me.deadline_ns = d;
            try ctx.reactor.addTimer(d, me);
        }

        // Each OS thread owns an independent FiberScheduler, so
        // condition-variable-signal!/-broadcast! called on *another*
        // thread only wakes fibers local to that thread's own scheduler
        // (me.status never changes) -- the generation bump in
        // CondVarWait.isDone, re-checked when the signaler's ring pops the
        // park, is what a cross-thread waiter actually relies on
        // (kaappi#2395). "Not done" with another OS thread alive only
        // means the park's crossThreadWaitPossible verdict went stale
        // mid-wait -- loop back and re-park; without one it is a genuine
        // deadlock.
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
            me.status = .waiting;
            ctx.sched.enrollWaiter(me); // #1530: re-index before re-parking (see mutexLockFn)
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

pub const CondVarWait = struct {
    me: *fiber_mod.Fiber,
    cv: *types.ConditionVariable,
    start_gen: u64,
    pub fn isDone(self: CondVarWait) bool {
        return self.me.status != .waiting or
            loadSignalGeneration(self.cv) != self.start_gen;
    }
    // See MutexWait.externalWakePossible; the ring here comes from
    // condition-variable-signal!/-broadcast!, right after the generation
    // bump this isDone re-checks.
    pub fn externalWakePossible(self: CondVarWait) bool {
        _ = self;
        return crossThreadWaitPossible();
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
    // scheduler (which never sees the local wake above) detects the signal,
    // then ring those waiters' reactors so the detection happens now rather
    // than at a poll cadence (kaappi#2395). Bump strictly before ring, per
    // the lost-wakeup protocol. Cross-thread waiters can't be woken singly
    // -- every registered thread re-checks the generation and all of them
    // return -- which is the same wake-them-all semantics the polled
    // generation check always had, and within SRFI-18's "at least one".
    const cv = types.toConditionVariable(args[0]);
    bumpSignalGeneration(cv);
    reactor_mod.ringSlotWaiters(&cv.cross_waiters);
    return types.VOID;
}

fn condvarBroadcastFn(args: []const Value) PrimitiveError!Value {
    if (!types.isConditionVariable(args[0]))
        return primitives.typeError("condition-variable-broadcast!", "condition-variable", args[0]);
    const ctx = try ensureScheduler();
    ctx.sched.wakeAllCondVarWaiters(args[0]);
    const cv = types.toConditionVariable(args[0]);
    bumpSignalGeneration(cv);
    reactor_mod.ringSlotWaiters(&cv.cross_waiters); // kaappi#2395: see signal!
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Time primitives
// ---------------------------------------------------------------------------

fn currentTimeFn(_: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rt = platform.realTime();
    return gc.allocSrfi18Time(@intCast(rt.sec), @intCast(rt.nsec), .utc) catch return PrimitiveError.OutOfMemory;
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
    // A time object stores whole seconds in an i64, so anything outside
    // [-2^63, 2^63) has no representation -- including +inf.0/-inf.0 and
    // +nan.0, which fail both comparisons here. The old unchecked
    // @intFromFloat aborted the process on all of them (#1983). Unlike a
    // timeout, this constructs an observable value, so saturating would
    // silently build a wrong time; raise catchably instead. The upper bound
    // must be 2^63 written exactly, not @floatFromInt(maxInt(i64)): that
    // constant rounds UP to 2^63 and would re-admit the first aborting
    // value -- the same off-by-one-ULP guard bug #1907 was made of.
    if (!(secs >= -0x1p63 and secs < 0x1p63))
        return primitives.argError("seconds->time", "{d} is outside the representable time range", .{secs});
    const int_secs = @as(i64, @intFromFloat(@floor(secs)));
    const frac = secs - @floor(secs);
    const ns = @as(i64, @intFromFloat(@round(frac * 1_000_000_000.0)));
    return gc.allocSrfi18Time(int_secs, ns, .utc) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Exception predicates
// ---------------------------------------------------------------------------

/// `pub` since KEP-0002 Phase 4 (#1469): channel-timeout-exception?.
pub fn isErrorOfType(v: Value, error_type: types.ErrorObject.ErrorType) bool {
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
