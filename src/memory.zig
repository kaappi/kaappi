const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const types = @import("types.zig");
const diagnostics = @import("diagnostics.zig");
const shared_buffer = @import("shared_buffer.zig");
const instrument = @import("channel_instrument.zig");
const Value = types.Value;
const Object = types.Object;
const ObjectTag = types.ObjectTag;
const Pair = types.Pair;
const Symbol = types.Symbol;
const SchemeString = types.SchemeString;
const Closure = types.Closure;
const Function = types.Function;
const NativeFn = types.NativeFn;
const Flonum = types.Flonum;
const Transformer = types.Transformer;

const Vector = types.Vector;
const Bytevector = types.Bytevector;
const Promise = types.Promise;
const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const Port = types.Port;
const Continuation = types.Continuation;
const MultipleValues = types.MultipleValues;
const SavedFrame = types.SavedFrame;
const SavedHandler = types.SavedHandler;
const WindRecord = types.WindRecord;

const FfiLibrary = types.FfiLibrary;
const FfiFunction = types.FfiFunction;
const FfiCallback = types.FfiCallback;
const FfiType = types.FfiType;
const HashTable = types.HashTable;
const HashEntry = types.HashEntry;
const Bignum = types.Bignum;
const Rational = types.Rational;
const RandomSource = types.RandomSource;

const build_options = @import("build_options");
const GC_THRESHOLD: usize = build_options.gc_initial_threshold;

pub const GcStats = struct {
    collections: usize = 0,
    total_mark_ns: u64 = 0,
    total_sweep_ns: u64 = 0,
    objects_freed: usize = 0,
    bytes_freed: usize = 0,
    peak_object_count: usize = 0,
    peak_bytes_allocated: usize = 0,
    allocs_by_type: [64]usize = .{0} ** 64,
    no_collect_deferred: usize = 0,
    /// #1961: times a minor collection's mark phase stopped at an old object
    /// (the generational boundary). Watching this stay > 0 while a large old
    /// heap exists is how tests pin that a minor mark really is generational.
    minor_old_skips: usize = 0,
};

pub var symbol_mutex: std.atomic.Mutex = .unlocked;

/// Sentinel stamped into `Object.owner` when the object's header slot is
/// freed (#1687). `nextGcId` never returns it, so a mark-phase read of this
/// value is proof of use-after-free: the #958 foreign-owner skip would
/// otherwise silently absorb the dangling reference (a Debug-poisoned owner
/// byte reads as some other GC's id). Stamped and checked only when
/// `uaf_detection` is set; release builds never see it.
pub const FREED_OWNER: u32 = 0xFFFF_FFFF;

/// Gate for the freed-owner sentinel (#1687): stamp freed headers and panic
/// when marking reaches one. Debug and gc-stress builds only, so release
/// builds pay nothing on the mark hot path.
pub const uaf_detection: bool = builtin.mode == .Debug or build_options.gc_stress;

/// Gate for the free-quarantine (#1687): under `-Dgc-stress=true`, freed
/// header slots are withheld from the allocator until after a later
/// collection's mark phase, so a dangling root marked one collection later
/// still reads the FREED_OWNER sentinel instead of a recycled live object
/// (the silent-aliasing mode that hid #1682 for twelve nightly runs).
pub const free_quarantine: bool = build_options.gc_stress;

/// Monotonic source of unique GC ids (see `GC.id`). Never reused, so a live
/// GC can never collide with a dead thread's id. Starts at 1 so 0 is never a
/// valid id, and skips FREED_OWNER so a freed header can never masquerade as
/// a live GC's object.
var next_gc_id: u32 = 0;

fn nextGcId() u32 {
    while (true) {
        const id = @atomicRmw(u32, &next_gc_id, .Add, 1, .monotonic) +% 1;
        if (id != 0 and id != FREED_OWNER) return id;
    }
}

pub fn spinLock(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) std.atomic.spinLoopHint();
}
pub fn spinUnlock(m: *std.atomic.Mutex) void {
    m.unlock();
}

pub threadlocal var gc_instance: ?*GC = null;

pub fn setGCInstance(gc: *GC) void {
    gc_instance = gc;
}

/// Allocate a slice of `n` `T` without paying Zig's ReleaseSafe-only
/// alloc-fill. `std.mem.Allocator.alloc`/`.create`/`.dupe` unconditionally
/// `@memset(..., undefined)` (a real 0xAA fill in ReleaseSafe) inside their
/// own generic bodies before returning — not in the vtable `rawAlloc` they
/// call into, so no backing allocator or `@setRuntimeSafety(false)` at the
/// call site can suppress it (#1809; confirmed by disassembly). Every call
/// site here immediately overwrites the memory anyway (a dupe, a fill-value
/// pass, or a struct literal), so the fill is pure waste on the hot,
/// size-proportional buffers this is used for (vector/string/bytevector
/// data, bignum limbs, register/frame arrays, ...). Debug/gc-stress
/// poisoning is unaffected: `gc_sweep.poisonAndDestroy` does its own
/// explicit content poisoning, `FREED_OWNER` stamping, and quarantine,
/// entirely independent of whatever the underlying allocator does.
///
/// The `byte_count == 0` guard (not `n == 0`) matters: `std.testing.
/// allocator` is a `DebugAllocator`, whose size-class math underflows on a
/// zero-length `rawAlloc`/`rawFree` call, and Kaappi routinely allocates
/// zero-length vectors/strings/bytevectors.
pub fn allocSliceNoFill(allocator: std.mem.Allocator, comptime T: type, n: usize) ![]T {
    const byte_count = std.math.mul(usize, @sizeOf(T), n) catch return error.OutOfMemory;
    if (byte_count == 0) {
        const ptr: [*]T = @ptrFromInt(comptime std.mem.Alignment.of(T).backward(std.math.maxInt(usize)));
        return ptr[0..n];
    }
    const raw = allocator.rawAlloc(byte_count, .of(T), @returnAddress()) orelse return error.OutOfMemory;
    const ptr: [*]T = @ptrCast(@alignCast(raw));
    return ptr[0..n];
}

/// Free a slice allocated by `allocSliceNoFill`/`dupeSliceNoFill` (or
/// anything else with the same address/length/alignment contract) without
/// paying the matching ReleaseSafe free-fill. See `allocSliceNoFill`.
pub fn freeSliceNoFill(allocator: std.mem.Allocator, comptime T: type, slice: []T) void {
    const byte_count = slice.len * @sizeOf(T);
    if (byte_count == 0) return;
    const bytes: []u8 = @as([*]u8, @ptrCast(slice.ptr))[0..byte_count];
    allocator.rawFree(bytes, .of(T), @returnAddress());
}

/// Copy `data` into a freshly `allocSliceNoFill`d buffer.
pub fn dupeSliceNoFill(allocator: std.mem.Allocator, comptime T: type, data: []const T) ![]T {
    const buf = try allocSliceNoFill(allocator, T, data.len);
    @memcpy(buf, data);
    return buf;
}

/// Test-only OOM injector for *raw-allocator* allocations — the counterpart
/// to `GC.oom_countdown`, which only ever sees GC (`allocXxx`) allocations
/// because it fires from `maybeCollect`. Wrap the backing allocator with this
/// and hand `allocator()` to `GC.init`, and every allocation that goes
/// straight to the raw allocator becomes injectable: the VM's growable
/// register/frame/handler/wind stacks (`ensureRegisterCapacity` and siblings,
/// via `allocSliceNoFill`), the fiber snapshot buffers (`growFiberRegisters`/
/// `Frames`/`Handlers`/`Winds`), the reactor timer heap (`addTimer`), the
/// scheduler's `driving_waits` list, bignum limb scratch, and the
/// bytecode/IR/constant pools. `GC.oom_countdown` reaches none of these —
/// which is what blocked the OOM regression tests for the fiber scheduler's
/// error paths (#2435, #2429, #2433).
///
/// `countdown` is deliberately independent of `GC.oom_countdown`: a form's raw
/// and GC allocation sequences are unrelated, so the two are armed and swept
/// separately. When set to `n`, the next `n` buffer acquisitions succeed and
/// every one after fails with `OutOfMemory` — sticky, exactly like
/// `oom_countdown`, so a sweep over `0..N` drives a failure at each raw
/// allocation a form makes. `null` (the default) forwards everything
/// untouched, so a VM constructed on it runs normally until a test arms it —
/// which is why, unlike `std.testing.FailingAllocator`, it can be handed to
/// `GC.init` without failing construction indiscriminately.
///
/// The counter ticks on `alloc` (a new buffer). `remap` may move-and-copy, so
/// it is failed once the budget is exhausted but does not itself tick (it
/// acquires no buffer the fallback `alloc` won't); `resize` is a pure in-place
/// change that acquires nothing, so it forwards untouched. Together this means
/// an `ArrayList`/timer-heap growth (`driving_waits.append`, `addTimer`)
/// cannot slip past an armed injector: `ensureTotalCapacityPrecise` tries
/// `remap` first and falls back to `alloc`, and both refuse once spent.
pub const OomAllocator = struct {
    backing: std.mem.Allocator,
    countdown: ?usize = null,

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = oomAlloc,
        .resize = oomResize,
        .remap = oomRemap,
        .free = oomFree,
    };

    pub fn init(backing: std.mem.Allocator) OomAllocator {
        // Test-only, like `GC.oom_countdown`: a production reference is a
        // compile error, so no non-test build can install the wrapper. Fires
        // only when `init` is analyzed in a non-test build; unreferenced in
        // production, it costs nothing.
        comptime if (!builtin.is_test) @compileError("OomAllocator is test-only");
        return .{ .backing = backing };
    }

    pub fn allocator(self: *OomAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    /// Consume one unit of budget on a new-buffer allocation. Returns true if
    /// the budget is spent and this allocation must fail.
    fn tick(self: *OomAllocator) bool {
        if (self.countdown) |n| {
            if (n == 0) return true;
            self.countdown = n - 1;
        }
        return false;
    }

    /// True once the budget is fully spent. Used by `remap`, which acquires no
    /// new buffer (so must not consume budget) but must still fail an armed,
    /// exhausted injector rather than let a growth through.
    fn spent(self: *const OomAllocator) bool {
        return if (self.countdown) |n| n == 0 else false;
    }

    fn oomAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *OomAllocator = @ptrCast(@alignCast(ctx));
        if (self.tick()) return null;
        return self.backing.vtable.alloc(self.backing.ptr, len, alignment, ret_addr);
    }
    fn oomResize(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        // A resize is a pure in-place change — it acquires no new backing
        // memory, so it is never an OOM injection point: forward untouched.
        const self: *OomAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.vtable.resize(self.backing.ptr, mem, alignment, new_len, ret_addr);
    }
    fn oomRemap(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *OomAllocator = @ptrCast(@alignCast(ctx));
        if (self.spent()) return null;
        return self.backing.vtable.remap(self.backing.ptr, mem, alignment, new_len, ret_addr);
    }
    fn oomFree(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *OomAllocator = @ptrCast(@alignCast(ctx));
        self.backing.vtable.free(self.backing.ptr, mem, alignment, ret_addr);
    }
};

pub const GC = struct {
    allocator: std.mem.Allocator,
    objects: ?*Object = null,
    old_objects: ?*Object = null,
    object_count: usize = 0,
    gc_threshold: usize = GC_THRESHOLD,
    symbols: std.StringHashMap(Value),
    shared_symbols: ?*std.StringHashMap(Value) = null,
    // Symbols interned into THIS gc's `symbols` table by *other* (child)
    // threads. A child thread aliases this table via `shared_symbols` but must
    // not track such a Symbol on its own object list — the child frees that
    // list at thread teardown while this table (and this gc) still reference
    // the symbol (use-after-free). Nor can it push onto this gc's `objects`
    // list, which this thread mutates without a lock. Instead the child
    // appends here under `symbol_mutex`, and this gc frees them at deinit.
    // Interned symbols are permanent (marked as roots every GC, never swept),
    // so this list needs no sweep interaction — only teardown ownership.
    foreign_symbols: std.ArrayList(*Object) = .empty,
    // For a child gc, points at the owning (parent) gc's `foreign_symbols`;
    // set alongside `shared_symbols` in `initForThread`.
    shared_foreign_symbols: ?*std.ArrayList(*Object) = null,
    /// Unique id of this GC, stamped into `Object.owner` of every object it
    /// tracks. Marking only touches objects whose owner matches the marking
    /// GC (see gc_collect.zig); foreign objects are the owner's job to keep
    /// alive. This is what stops an SRFI-18 child thread's collections from
    /// racing the parent's mark/sweep on shared parent-heap objects (#958).
    id: u32 = 0,
    /// For a child gc: the id of the gc that OWNS the shared symbol table
    /// (the root), stamped on symbols the child interns into it (the owner
    /// owns and frees those). With root chaining (see initForThread) this is
    /// the root's id for every descendant, whatever the immediate parent.
    shared_owner_id: u32 = 0,
    root_buffer: []*Value,
    root_count: u32 = 0,
    extra_roots: std.ArrayList(Value),
    arg_roots: [4]Value = .{ 0, 0, 0, 0 },
    arg_root_count: u3 = 0,
    remembered_set: std.ArrayList(*Object),
    /// Like `arg_roots`, but for a caller-provided slice of Values: allocators
    /// that receive `[]const Value` (allocVector, allocNativeClosure, ...)
    /// point this at the (raw, non-GC) buffer before maybeCollect() so the
    /// values survive the collection without the caller having to root each
    /// element. Always save/restore rather than assign/null so nested
    /// allocations (makeList → allocPair) compose.
    slice_roots: ?[]const Value = null,
    stress: bool = build_options.gc_stress,
    enabled: bool = true,
    no_collect: u32 = 0,
    bytes_allocated: usize = 0,
    memory_limit: ?usize = null,
    /// Test-only OOM injector: when set, the next `oom_countdown` heap
    /// allocations succeed and the one after that fails with OutOfMemory.
    /// Counted per `maybeCollect` call, so it fires only for allocations that
    /// go through the *GC* — every `allocXxx`. A raw-allocator allocation is
    /// invisible to it: `allocFunction` (which skips `maybeCollect`), and,
    /// more widely, the VM's growable register/frame/handler/wind stacks, the
    /// fiber snapshot buffers, the reactor timer heap, the scheduler's
    /// `driving_waits` list, and the bytecode/IR/constant pools — which is why
    /// a compile with no macro use in it never fails here. Reach those with
    /// `OomAllocator` instead (#2435), whose independent countdown sits in a
    /// wrapper over the raw allocator.
    /// Sweeping it over 0..N drives a failure at every *GC* allocation the
    /// pipeline performs, which is what reaches the deep expander/compiler
    /// push/pop sites (#1855). `memory_limit` cannot: it is an absolute
    /// watermark that only trips once one form *retains* more than the
    /// headroom, so it only ever fails within the first few allocations, and
    /// FailingAllocator has its own documented deep-pipeline limitation.
    /// Compiled out entirely outside test binaries (`builtin.is_test` is
    /// comptime), so the allocation path pays nothing for it.
    oom_countdown: ?usize = null,
    profile_alloc_target: ?*u64 = null,
    root_marker: ?*const fn (*GC) void = null,
    /// #1933: called by markRoots after `root_marker` when live SRFI-18
    /// child threads exist. Set by the first thread-start! (primitives_srfi18
    /// threadStartImpl) to markLiveChildRoots on the ROOT gc; the root's
    /// collector stops every live child at a safepoint and marks its
    /// registers/frames with this gc, keeping parent-heap objects reachable
    /// only from a live child's registers alive. Null on every child gc (and
    /// on the root before any thread has ever been started), so a gc that
    /// never coordinates pays nothing.
    child_marker: ?*const fn (*GC) void = null,
    source_spans: std.AutoHashMap(Value, types.Span) = undefined,
    stats: GcStats = .{},
    minor_cycle_count: u32 = 0,
    /// #1961: set for the duration of a minor collection's mark phase. While
    /// set, `markValueInner` treats the old generation as opaque — an old
    /// object is never marked or traced, because `sweepYoung` never frees it —
    /// so the minor mark costs O(live young) plus the remembered containers'
    /// scanned fields, not O(live heap). Every live
    /// old→young edge is supplied by the remembered-set walk instead (the
    /// `writeBarrier` calls at each mutation site plus the promotion scan in
    /// `sweepYoung`). False outside a collection and during every full
    /// collection. The weak-reference probes (`keptAlive`/`weakReachable`)
    /// also read it: an old object trivially survives a minor collection, so
    /// it must answer "alive" there and defer its weak fate to the next full
    /// collection.
    minor_marking: bool = false,
    mark_worklist: std.ArrayList(Value) = .empty,
    marking: bool = false,
    /// SRFI-254 weak references reached during the current mark phase. Filled
    /// by markValueInner as reachable ephemerons/guardians are marked, drained
    /// to a fixpoint by gc_collect.processWeakRefs after marking, then cleared.
    /// Live only within a single collection.
    pending_ephemerons: std.ArrayList(Value) = .empty,
    pending_guardians: std.ArrayList(Value) = .empty,
    /// Reachable transport cells awaiting key resolution (SRFI-254: the key
    /// field is weakly holding). Filled by the mark arms like the two lists
    /// above and resolved by processWeakRefs after the fixpoint. Live only
    /// within a single collection.
    pending_transport_cells: std.ArrayList(Value) = .empty,
    /// SRFI-254 weak resurrections of the current collection: objects held in
    /// an object guardian's ready queue, freshly resurrected elements, and
    /// retained representatives. These locations are *kept alive* without
    /// being reachable, so guardian probes deliberately ignore the set (#2011)
    /// while ephemeron and transport-cell key probes consult it via
    /// gc_collect.keptAlive. Materialized into real marks by processWeakRefs
    /// once every weak decision is made, then cleared. Live only within a
    /// single collection.
    weak_resurrected: std.AutoHashMap(*Object, void) = undefined,
    /// #1687 free-quarantine (gc-stress builds only; see `free_quarantine`).
    /// FIFO of freed header slots withheld from the allocator: entries before
    /// `quarantine_head` are already released. Slots are appended by
    /// gc_sweep's poisonAndDestroy and released oldest-first — only once
    /// the held bytes exceed `quarantine_max_bytes`, and only after a mark
    /// phase — so every entry survives at least one full mark after its free
    /// and a dangling value marked then still reads the FREED_OWNER sentinel.
    quarantine: std.ArrayList(QuarantineEntry) = .empty,
    quarantine_head: usize = 0,
    quarantine_bytes: usize = 0,
    /// Cap on withheld bytes. A field (not a const) so tests can shrink it to
    /// exercise eviction without freeing megabytes.
    quarantine_max_bytes: usize = 4 << 20,
    /// GC that inherits this one's still-withheld slots at `deinit` instead of
    /// the allocator getting them back (#2127). Set — via `setQuarantineHeir`,
    /// from the thread that is doing the tearing down — whenever this GC dies
    /// while a *longer-lived* GC may still hold a value pointing into its
    /// heap: a joined SRFI-18 child is the case that matters, since every
    /// cross-heap dangling reference is born there. Without an heir the drain
    /// hands every slot straight back, the next parent allocation recycles it,
    /// and the FREED_OWNER sentinel the whole #1687 machinery rests on is
    /// overwritten before the parent's next mark can read it.
    quarantine_heir: ?*GC = null,

    pub const QuarantineEntry = struct {
        ptr: [*]u8,
        len: usize,
        alignment: std.mem.Alignment,
    };

    pub const INITIAL_ROOT_CAPACITY: usize = 1024;
    pub const MAX_ROOT_CAPACITY: usize = 65536;

    pub fn init(allocator: std.mem.Allocator) GC {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Value).init(allocator),
            .root_buffer = allocator.alloc(*Value, INITIAL_ROOT_CAPACITY) catch
                @panic("GC: cannot allocate root buffer"),
            .extra_roots = .empty,
            .remembered_set = .empty,
            .source_spans = std.AutoHashMap(Value, types.Span).init(allocator),
            .weak_resurrected = std.AutoHashMap(*Object, void).init(allocator),
            .id = nextGcId(),
        };
    }

    pub fn initForThread(allocator: std.mem.Allocator, parent: *GC) GC {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Value).init(allocator),
            // #1935: chain to the ROOT's symbol table, not the immediate
            // parent's. A child GC's own `symbols` field is never populated
            // -- its own internings go to `shared_symbols` -- so a grandchild
            // pointed at `parent.symbols` would intern into a table nothing
            // else consults: identity diverges ((string->symbol "x") not eq?
            // to the root's 'x, an R7RS 6.5 violation) and the root's mark
            // phase never sees the symbol. Same for `shared_owner_id`: the
            // table's owner is the root, so every descendant must stamp its
            // interned symbols with the ROOT's id, and append them to the
            // ROOT's foreign_symbols -- the root owns and frees them all at
            // deinit, however deep the thread chain.
            .shared_symbols = parent.shared_symbols orelse &parent.symbols,
            .shared_foreign_symbols = parent.shared_foreign_symbols orelse &parent.foreign_symbols,
            .root_buffer = allocator.alloc(*Value, INITIAL_ROOT_CAPACITY) catch
                @panic("GC: cannot allocate root buffer"),
            .extra_roots = .empty,
            .remembered_set = .empty,
            .source_spans = std.AutoHashMap(Value, types.Span).init(allocator),
            .weak_resurrected = std.AutoHashMap(*Object, void).init(allocator),
            .gc_threshold = GC_THRESHOLD,
            .id = nextGcId(),
            .shared_owner_id = if (parent.shared_symbols != null) parent.shared_owner_id else parent.id,
        };
    }

    pub fn deinit(self: *GC) void {
        var obj = self.objects;
        while (obj) |o| {
            const next = o.next;
            gc_collect.freeObject(self, o);
            obj = next;
        }
        obj = self.old_objects;
        while (obj) |o| {
            const next = o.next;
            gc_collect.freeObject(self, o);
            obj = next;
        }
        // Free symbols that child threads interned into our shared table but
        // could not track themselves (see `foreign_symbols`). No other thread
        // is running at deinit — main.zig's only caller checks
        // primitives_srfi18.hasLiveChildThreads() and skips this call
        // entirely while any thread-start!ed child is still alive (kaappi#1792)
        // — so this needs no lock.
        for (self.foreign_symbols.items) |o| gc_collect.freeObject(self, o);
        // Every freeObject above appends to the quarantine in gc-stress
        // builds, and this GC will never reach another release point — so the
        // slots go somewhere now or leak. To an heir if one was named (a
        // joined child hands them to the parent, which still has marks to run
        // over any value dangling into this heap — #2127), otherwise back to
        // the allocator.
        if (self.quarantine_heir) |heir| self.quarantineHandOff(heir) else self.quarantineDrain();
        self.quarantine.deinit(self.allocator);
        self.foreign_symbols.deinit(self.allocator);
        self.symbols.deinit();
        self.allocator.free(self.root_buffer);
        self.extra_roots.deinit(self.allocator);
        self.remembered_set.deinit(self.allocator);
        self.mark_worklist.deinit(self.allocator);
        self.pending_ephemerons.deinit(self.allocator);
        self.pending_guardians.deinit(self.allocator);
        self.pending_transport_cells.deinit(self.allocator);
        self.weak_resurrected.deinit();
        self.source_spans.deinit();
    }

    /// #1961: enroll an OWNED container in the remembered set, idempotently
    /// (the #2196 dedup flag is the in-set mark for owned objects: set iff
    /// present, cleared by pruneRememberedSet/drainRememberedSet on exit).
    /// Shared by writeBarrier's owned path, the promotion scan and
    /// full-collect re-scan in gc_sweep, and saveCurrentFiber's bulk
    /// snapshot — every site that creates or re-creates an old→young edge
    /// outside the ordinary store+barrier pattern. Callers must have
    /// established `obj.owner == self.id`; foreign containers carry no flag
    /// and stay in writeBarrier's unconditional-append branch.
    pub fn rememberObject(self: *GC, obj: *Object) void {
        if (obj.flags.in_remembered_set) return;
        obj.flags.in_remembered_set = true;
        self.remembered_set.append(self.allocator, obj) catch
            @panic("GC rememberObject: remembered set OOM");
    }

    /// #1961: barrier a store into a mutable SchemeEnvironment's map (the
    /// eval/environment objects) — an old→young edge on the wrapper once it
    /// promotes. The interaction-environment wrapper (.owned == false) is
    /// excluded: its map IS the root-marked globals map, and enrolling it
    /// would re-walk every global once per minor, forever. Shared by the
    /// set_global/define_global handlers and the compiler's define-syntax
    /// env stores, so the exclusion rule lives in exactly one place.
    pub fn envStoreBarrier(self: *GC, env_val: Value, val: Value) void {
        if (types.isEnvironment(env_val) and types.toEnvironment(env_val).owned)
            self.writeBarrier(types.toObject(env_val), val);
    }

    pub fn writeBarrier(self: *GC, container: *Object, new_val: Value) void {
        if (container.flags.generation == 1 and types.isPointer(new_val)) {
            const child = types.toObject(new_val);
            // A foreign new_val (another GC's object) is never traced by this
            // GC, so it needs no remembered-set entry — and reading its
            // generation bit would race the owner's collection cycle.
            if (child.owner == self.id and child.flags.generation == 0) {
                // #2196: dedup. A container mutated n times must appear in the
                // remembered_set at most once — otherwise the minor mark phase
                // marks it n times, and marking a large container is O(capacity),
                // making a fill quadratic in writes. The in_remembered_set flag
                // is cleared when the container leaves the set (pruneRememberedSet
                // or a full-collect drain), so a container re-added after being
                // dropped queues exactly one fresh entry.
                //
                // The flag belongs to the container's *owning* GC. Only dedup a
                // container we own; a foreign container (a shared global mutated
                // across threads — the #1924 hazard) keeps the pre-#2196
                // unconditional append, so its owner's flag is never observed or
                // written here and no reference this GC must track is dropped.
                if (container.owner != self.id) {
                    self.remembered_set.append(self.allocator, container) catch @panic("GC writeBarrier: remembered set OOM");
                } else {
                    self.rememberObject(container);
                }
            }
        }
    }

    // The four inline helpers below are pub for gc_alloc.zig (the allocXxx
    // constructors); nothing else should call them.
    pub inline fn profileAlloc(self: *GC, size: usize) void {
        if (self.profile_alloc_target) |t| t.* += size;
    }

    pub fn trackObject(self: *GC, obj: *Object) void {
        obj.owner = self.id;
        obj.next = self.objects;
        self.objects = obj;
        self.object_count += 1;
        self.stats.allocs_by_type[@intFromEnum(obj.tag)] += 1;
        if (self.object_count > self.stats.peak_object_count)
            self.stats.peak_object_count = self.object_count;
        if (self.bytes_allocated > self.stats.peak_bytes_allocated)
            self.stats.peak_bytes_allocated = self.bytes_allocated;
    }

    pub inline fn rootArgs1(self: *GC, a: Value) void {
        self.arg_roots[0] = a;
        self.arg_root_count = 1;
    }

    pub inline fn rootArgs2(self: *GC, a: Value, b: Value) void {
        self.arg_roots[0] = a;
        self.arg_roots[1] = b;
        self.arg_root_count = 2;
    }

    pub inline fn clearArgRoots(self: *GC) void {
        self.arg_root_count = 0;
    }

    pub inline fn finishAlloc(self: *GC, obj: *Object, size: usize) void {
        self.bytes_allocated += size;
        self.profileAlloc(size);
        self.trackObject(obj);
    }

    // -- Object allocators (delegated to gc_alloc.zig) --
    //
    // Every allocXxx constructor lives in gc_alloc.zig; the aliases below
    // keep `gc.allocXxx(...)` method call sites working unchanged.

    const gc_alloc = @import("gc_alloc.zig");

    pub const max_payload_bytes = gc_alloc.max_payload_bytes;

    pub const allocPair = gc_alloc.allocPair;
    pub const allocSymbol = gc_alloc.allocSymbol;
    pub const allocUninternedSymbol = gc_alloc.allocUninternedSymbol;
    pub const allocString = gc_alloc.allocString;
    pub const allocFunction = gc_alloc.allocFunction;
    pub const appendFunctionConstant = gc_alloc.appendFunctionConstant;
    pub const allocClosure = gc_alloc.allocClosure;
    pub const allocNativeFn = gc_alloc.allocNativeFn;
    pub const allocNativeClosure = gc_alloc.allocNativeClosure;
    pub const allocFlonum = gc_alloc.allocFlonum;
    pub const allocVector = gc_alloc.allocVector;
    pub const allocVectorFill = gc_alloc.allocVectorFill;
    pub const allocErrorObject = gc_alloc.allocErrorObject;
    pub const allocErrorObjectCoded = gc_alloc.allocErrorObjectCoded;
    pub const allocTransformer = gc_alloc.allocTransformer;
    pub const allocProceduralTransformer = gc_alloc.allocProceduralTransformer;
    pub const allocRecordType = gc_alloc.allocRecordType;
    pub const allocRecordTypeExtended = gc_alloc.allocRecordTypeExtended;
    pub const allocRecordInstance = gc_alloc.allocRecordInstance;
    pub const allocPort = gc_alloc.allocPort;
    pub const allocStringInputPort = gc_alloc.allocStringInputPort;
    pub const allocStringOutputPort = gc_alloc.allocStringOutputPort;
    pub const allocCustomPort = gc_alloc.allocCustomPort;
    pub const allocTranscodedPort = gc_alloc.allocTranscodedPort;
    pub const allocRandomPort = gc_alloc.allocRandomPort;
    pub const allocBytevector = gc_alloc.allocBytevector;
    pub const allocBytevectorFill = gc_alloc.allocBytevectorFill;
    pub const allocNumericVector = gc_alloc.allocNumericVector;
    pub const allocNumericVectorFill = gc_alloc.allocNumericVectorFill;
    pub const allocBytevectorShared = gc_alloc.allocBytevectorShared;
    pub const unshareBytevector = gc_alloc.unshareBytevector;
    pub const allocPromise = gc_alloc.allocPromise;
    pub const allocContinuation = gc_alloc.allocContinuation;
    pub const allocEscapeContinuation = gc_alloc.allocEscapeContinuation;
    pub const allocComplex = gc_alloc.allocComplex;
    pub const allocParameter = gc_alloc.allocParameter;
    pub const allocFfiLibrary = gc_alloc.allocFfiLibrary;
    pub const allocFfiFunction = gc_alloc.allocFfiFunction;
    pub const allocFfiCallback = gc_alloc.allocFfiCallback;
    pub const allocRandomSource = gc_alloc.allocRandomSource;
    pub const allocFiber = gc_alloc.allocFiber;
    pub const allocChannel = gc_alloc.allocChannel;
    pub const allocChannelBounded = gc_alloc.allocChannelBounded;
    pub const allocChannelStub = gc_alloc.allocChannelStub;
    pub const allocMutex = gc_alloc.allocMutex;
    pub const allocConditionVariable = gc_alloc.allocConditionVariable;
    pub const allocSrfi18Time = gc_alloc.allocSrfi18Time;
    pub const allocHashTable = gc_alloc.allocHashTable;
    pub const allocBignumFromI64 = gc_alloc.allocBignumFromI64;
    pub const allocBignumFromLimbs = gc_alloc.allocBignumFromLimbs;
    pub const allocRational = gc_alloc.allocRational;
    pub const allocFileInfo = gc_alloc.allocFileInfo;
    pub const allocUserInfo = gc_alloc.allocUserInfo;
    pub const allocGroupInfo = gc_alloc.allocGroupInfo;
    pub const allocEnvironment = gc_alloc.allocEnvironment;
    pub const allocEphemeron = gc_alloc.allocEphemeron;
    pub const allocGuardian = gc_alloc.allocGuardian;
    pub const allocTransportCell = gc_alloc.allocTransportCell;
    pub const allocDirectoryObject = gc_alloc.allocDirectoryObject;
    pub const allocMultipleValues = gc_alloc.allocMultipleValues;
    pub const makeList = gc_alloc.makeList;

    // -- Deep copy (delegated to gc_deep_copy.zig) --

    const gc_deep_copy = @import("gc_deep_copy.zig");

    pub fn deepCopy(self: *GC, src: Value) !Value {
        return gc_deep_copy.deepCopy(self, src);
    }

    // -- GC (delegated to gc_collect.zig) --

    const gc_collect = @import("gc_collect.zig");

    // pub for gc_alloc.zig; not part of the public GC API.
    pub fn maybeCollect(self: *GC) !void {
        if (comptime builtin.is_test) {
            if (self.oom_countdown) |n| {
                if (n == 0) return error.OutOfMemory;
                self.oom_countdown = n - 1;
            }
        }
        // Stress mode only changes *when* a collection is due (every call
        // instead of at the threshold); the no_collect and memory_limit
        // semantics must match the normal path, or stress builds would
        // OOM inside no_collect sections that normal builds merely defer.
        if (self.enabled and (self.stress or self.object_count >= self.gc_threshold)) {
            if (self.no_collect > 0) {
                self.stats.no_collect_deferred += 1;
            } else {
                self.collect();
            }
        }
        if (self.memory_limit) |limit| {
            if (self.bytes_allocated > limit) {
                if (!self.enabled or self.no_collect > 0) {
                    self.stats.no_collect_deferred += 1;
                } else {
                    self.collect();
                    if (self.bytes_allocated > limit) return error.OutOfMemory;
                }
            }
        }
    }

    pub fn collect(self: *GC) void {
        gc_collect.collect(self);
    }

    /// Force a full (both-generation) collection regardless of the
    /// minor-cycle schedule. Used to reclaim OS descriptors held by
    /// unreachable objects — abandoned file ports and directory streams —
    /// before reporting descriptor exhaustion to a program (kaappi#1993).
    /// A plain `collect()` usually runs a minor sweep, which misses any
    /// fd-holder already promoted to the old generation.
    pub fn collectFull(self: *GC) void {
        self.stats.collections += 1;
        gc_collect.fullCollect(self);
    }

    pub fn markValue(self: *GC, v: Value) void {
        gc_collect.markValue(self, v);
    }

    pub fn pushRoot(self: *GC, root: *Value) void {
        if (self.root_count >= self.root_buffer.len)
            self.growRootBuffer();
        self.root_buffer[self.root_count] = root;
        self.root_count += 1;
    }

    fn growRootBuffer(self: *GC) void {
        var new_len = self.root_buffer.len * 2;
        if (new_len > MAX_ROOT_CAPACITY) new_len = MAX_ROOT_CAPACITY;
        if (new_len <= self.root_buffer.len)
            @panic("GC root stack overflow");
        self.root_buffer = self.allocator.realloc(self.root_buffer, new_len) catch
            @panic("GC root stack overflow (out of memory)");
    }

    pub fn popRoot(self: *GC) void {
        self.root_count -= 1;
    }

    /// Unwind the root stack back to a depth snapshotted from `root_count`
    /// on entry to a pipeline boundary (#1855).
    ///
    /// The canonical `pushRoot` / `try` / `popRoot` pattern leaks its root
    /// when the protected call fails: the error unwinds past the `popRoot`,
    /// leaving the stack holding a pointer into a frame that no longer
    /// exists. Nothing else ever lowers `root_count`, so the next collection
    /// dereferences it, and the leaked entry also misaligns LIFO pairing for
    /// every `defer popRoot()` still to fire above it. The boundaries that
    /// hand a pipeline error back to a caller which keeps running — the
    /// `compileExpression*` entry points (compiler.zig), `vm_eval.eval`, and
    /// `vm_calls.execute` — therefore snapshot the depth and truncate to it,
    /// instead of an errdefer at each of the ~340 push sites, where `defer`
    /// near a loop is itself the LIFO footgun gc-safety.md warns about.
    /// Recovery *within* a running form (a primitive error a Scheme `guard`
    /// catches) is deliberately not covered at that granularity: see
    /// docs/dev/gc-safety-and-error-handling.md.
    ///
    /// Only ever shrinks. `root_count` *below* the snapshot means an
    /// over-pop, which re-rooting cannot repair: those slots may already
    /// have been overwritten by an inner frame that has since returned, so
    /// restoring them would re-root exactly the kind of dangling pointer
    /// this is meant to eliminate. Leave the depth alone and let the
    /// over-pop surface on its own terms.
    pub fn truncateRoots(self: *GC, depth: u32) void {
        if (self.root_count > depth) self.root_count = depth;
    }

    // -- #1687 free-quarantine (see the `quarantine` field) --

    /// Withhold a freed header slot from the allocator. Called by
    /// poisonAndDestroy in place of `destroy` when `free_quarantine` is set;
    /// the slot's Object.owner has already been stamped FREED_OWNER. If the
    /// entry can't be recorded, release the slot immediately rather than
    /// aborting the sweep — detection degrades, correctness doesn't.
    pub fn quarantinePut(self: *GC, ptr: [*]u8, len: usize, alignment: std.mem.Alignment) void {
        self.quarantine.append(self.allocator, .{ .ptr = ptr, .len = len, .alignment = alignment }) catch {
            self.allocator.rawFree(ptr[0..len], alignment, @returnAddress());
            return;
        };
        self.quarantine_bytes += len;
    }

    fn quarantineReleaseOldest(self: *GC) void {
        const e = self.quarantine.items[self.quarantine_head];
        self.quarantine_head += 1;
        self.quarantine_bytes -= e.len;
        self.allocator.rawFree(e.ptr[0..e.len], e.alignment, @returnAddress());
        if (self.quarantine_head == self.quarantine.items.len) {
            self.quarantine.clearRetainingCapacity();
            self.quarantine_head = 0;
        }
    }

    /// Release quarantined slots oldest-first until at most
    /// `quarantine_max_bytes` remain. Called between a collection's mark and
    /// sweep phases (gc_collect.zig), so slots freed by the upcoming sweep are
    /// never eviction candidates before the *next* mark has had a chance to
    /// trip the FREED_OWNER sentinel on them.
    pub fn quarantineReleaseToCap(self: *GC) void {
        if (comptime !free_quarantine) return;
        while (self.quarantine_bytes > self.quarantine_max_bytes)
            self.quarantineReleaseOldest();
        // Compact once the released prefix dominates so the list doesn't
        // grow by its own dead entries.
        const items = self.quarantine.items;
        if (self.quarantine_head > 0 and self.quarantine_head >= items.len / 2) {
            const remaining = items.len - self.quarantine_head;
            std.mem.copyForwards(QuarantineEntry, items[0..remaining], items[self.quarantine_head..]);
            self.quarantine.shrinkRetainingCapacity(remaining);
            self.quarantine_head = 0;
        }
    }

    /// Release every quarantined slot. Used at GC teardown and by the arena
    /// resets (shared_channel.zig, bench_channel.zig) that free objects on a
    /// GC which never collects.
    pub fn quarantineDrain(self: *GC) void {
        while (self.quarantine.items.len > 0) self.quarantineReleaseOldest();
    }

    /// Name the GC that inherits this one's withheld slots at `deinit`
    /// (#2127). Call it from the thread performing the teardown, and only
    /// once that thread knows no other thread can still be freeing objects on
    /// either GC — `heir.quarantine` is a plain ArrayList with no lock of its
    /// own, and the handoff appends to it. The SRFI-18 join path qualifies:
    /// it runs on the parent thread after the child's OS thread has been
    /// joined.
    pub fn setQuarantineHeir(self: *GC, heir: *GC) void {
        self.quarantine_heir = heir;
    }

    /// Move every still-withheld slot to `heir`'s quarantine, so the slots
    /// stay out of the allocator's hands until `heir` has run at least one
    /// more mark phase over its own roots — which is exactly what turns a
    /// parent value dangling into a dead child heap into the deterministic
    /// FREED_OWNER panic (#2127) instead of a silently recycled object.
    ///
    /// `heir` releases them with *its* allocator, so an heir that does not
    /// share this GC's allocator is refused and the slots are drained here
    /// instead: weaker detection, never a mismatched free. Every real caller
    /// shares one (a child GC is built with the parent's allocator).
    fn quarantineHandOff(self: *GC, heir: *GC) void {
        if (comptime !free_quarantine) return;
        const a = self.allocator;
        const b = heir.allocator;
        if (a.ptr != b.ptr or a.vtable != b.vtable) {
            self.quarantineDrain();
            return;
        }
        const pending = self.quarantine.items[self.quarantine_head..];
        heir.quarantine.appendSlice(heir.allocator, pending) catch {
            // Same degradation as quarantinePut's: detection is best-effort,
            // memory accounting is not.
            self.quarantineDrain();
            return;
        };
        for (pending) |e| heir.quarantine_bytes += e.len;
        self.quarantine.clearRetainingCapacity();
        self.quarantine_head = 0;
        self.quarantine_bytes = 0;
    }

    pub const RootedSlot = struct {
        gc: *GC,
        idx: usize,

        pub fn set(self: RootedSlot, val: Value) void {
            self.gc.extra_roots.items[self.idx] = val;
        }

        pub fn get(self: RootedSlot) Value {
            return self.gc.extra_roots.items[self.idx];
        }

        pub fn release(self: RootedSlot) void {
            if (self.idx == self.gc.extra_roots.items.len - 1) {
                _ = self.gc.extra_roots.pop();
            }
        }
    };

    pub fn rootedSlot(self: *GC, val: Value) error{OutOfMemory}!RootedSlot {
        self.extra_roots.append(self.allocator, val) catch return error.OutOfMemory;
        return .{ .gc = self, .idx = self.extra_roots.items.len - 1 };
    }

    pub const RootedScope = struct {
        gc: *GC,
        base: usize,

        pub fn release(self: RootedScope) void {
            self.gc.extra_roots.shrinkRetainingCapacity(self.base);
        }
    };

    pub fn rootedScope(self: *GC) RootedScope {
        return .{ .gc = self, .base = self.extra_roots.items.len };
    }
};

// -- #1924: cross-heap store rejection --
//
// A thread may store into a heap object it owns values from any heap
// (storing a shared parent-heap object into a child-local structure is the
// ordinary "copy a global into a local" pattern). But a store into an
// object the running thread does NOT own -- a shared parent-heap
// record/vector/pair reached through the globals map -- is rejected outright:
// the container's collector skips foreign values, the value's own collector
// cannot see the container, and the value is freed either by its own GC (the
// only reference is invisible to it) or when its thread's heap is reclaimed
// at thread-join! (kaappi#1924, deterministic and not a race).
//
// Rejecting every foreign-container store -- not just stores of a foreign-
// heap value -- is deliberate: a store of a value owned by the container's
// own (foreign) heap would still need the OWNER's write barrier when the
// value is young and the container old, and the running thread's own barrier
// records nothing for a foreign container, so the parent's remembered set
// would miss the edge and its next minor collection could reclaim the value.
// The owner's remembered set cannot be touched cross-thread, so the one
// sound rule is: no stores into foreign containers at all. The one
// deliberate engine-level exception is the mutex owner pair
// (primitives_srfi18.mutexLockFn): a child locking a shared parent-heap
// mutex must record its own heap's fiber as owner so a dying fiber can
// abandon the mutex. The mutex site simply does not call this check (it is
// a per-site decision, like every other sanctioned cross-thread idiom --
// see docs/dev/thread-value-sharing.md).
pub inline fn crossHeapStoreViolation(container: *const Object, value: Value) bool {
    if (!types.isPointer(value)) return false; // immediates have no lifetime
    // An interned symbol is permanent: the shared intern table roots it for
    // the process lifetime, so it can never dangle, and it is marked as a
    // root every collection, so it is promoted to old and no remembered-set
    // edge is needed when stored into an old container. Storing one into any
    // container — foreign included — is safe, which keeps symbol-keyed
    // hash-table writes working across threads.
    if (types.isSymbol(value)) {
        if (types.symbolInterned(value)) return false;
    }
    const gc = gc_instance orelse return false;
    return container.owner != gc.id;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "allocate and access pair" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();

    const pair = try gc.allocPair(types.makeFixnum(1), types.makeFixnum(2));
    try std.testing.expect(types.isPair(pair));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(pair)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.cdr(pair)));
}

test "symbol interning" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();

    const a1 = try gc.allocSymbol("hello");
    const a2 = try gc.allocSymbol("hello");
    const b = try gc.allocSymbol("world");

    try std.testing.expectEqual(a1, a2);
    try std.testing.expect(a1 != b);
    try std.testing.expect(types.isSymbol(a1));
    try std.testing.expectEqualStrings("hello", types.symbolName(a1));
}

test "make list" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();

    const items = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    const list = try gc.makeList(&items);

    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(list)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(list))));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(types.cdr(types.cdr(list)))));
    try std.testing.expect(types.isNil(types.cdr(types.cdr(types.cdr(list)))));
    try std.testing.expectEqual(@as(?usize, 3), types.listLength(list));
}

test "gc collects unreachable objects" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    _ = try gc.allocPair(types.makeFixnum(1), types.NIL);
    _ = try gc.allocPair(types.makeFixnum(2), types.NIL);
    try std.testing.expectEqual(@as(usize, 2), gc.object_count);

    gc.collect();
    // No roots → both pairs should be collected (symbols survive via intern table)
    try std.testing.expectEqual(@as(usize, 0), gc.object_count);
}

test "gc preserves rooted objects" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var rooted = try gc.allocPair(types.makeFixnum(42), types.NIL);
    _ = try gc.allocPair(types.makeFixnum(99), types.NIL);
    gc.pushRoot(&rooted);

    gc.collect();
    try std.testing.expectEqual(@as(usize, 1), gc.object_count);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(types.car(rooted)));

    gc.popRoot();
}

fn dummyNativeClosureFn(_: ?*@import("vm.zig").VM, _: [*]const Value, _: u64, _: [*]const Value) callconv(.c) u64 {
    return types.NIL;
}

test "allocNativeClosure triggers GC" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();

    gc.gc_threshold = 2;

    // Allocate several unrooted native closures; GC should trigger
    // and collect unreachable ones, keeping object_count bounded.
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = try gc.allocNativeClosure(&dummyNativeClosureFn, &.{}, 0, "x");
    }

    // Without maybeCollect, object_count would be 10.
    // With it, GC runs and collects unrooted closures.
    try std.testing.expect(gc.object_count < 10);
}

test "rootedSlot set/get/release" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();

    const v1 = types.makeFixnum(10);
    const v2 = types.makeFixnum(20);
    const v3 = types.makeFixnum(30);

    var slot_a = try gc.rootedSlot(v1);
    try std.testing.expectEqual(v1, slot_a.get());
    try std.testing.expectEqual(@as(usize, 1), gc.extra_roots.items.len);

    var slot_b = try gc.rootedSlot(v2);
    try std.testing.expectEqual(v2, slot_b.get());
    try std.testing.expectEqual(@as(usize, 2), gc.extra_roots.items.len);

    slot_b.set(v3);
    try std.testing.expectEqual(v3, slot_b.get());
    try std.testing.expectEqual(v1, slot_a.get());

    slot_b.release();
    try std.testing.expectEqual(@as(usize, 1), gc.extra_roots.items.len);
    slot_a.release();
    try std.testing.expectEqual(@as(usize, 0), gc.extra_roots.items.len);
}

test "rootedScope release" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();

    gc.extra_roots.append(gc.allocator, types.makeFixnum(1)) catch unreachable;
    const scope = gc.rootedScope();
    gc.extra_roots.append(gc.allocator, types.makeFixnum(2)) catch unreachable;
    gc.extra_roots.append(gc.allocator, types.makeFixnum(3)) catch unreachable;
    try std.testing.expectEqual(@as(usize, 3), gc.extra_roots.items.len);

    scope.release();
    try std.testing.expectEqual(@as(usize, 1), gc.extra_roots.items.len);
    try std.testing.expectEqual(types.makeFixnum(1), gc.extra_roots.items[0]);
}

// The #1687 tests read a freed object's header after the sweep. That read is
// defined ONLY because the quarantine keeps the slot resident (withheld from
// the allocator), which is why every one of them skips unless the
// free-quarantine is compiled in.

test "sweep stamps freed headers with the freed-owner sentinel (gc-stress)" {
    if (comptime !free_quarantine) return error.SkipZigTest;
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    const v = try gc.allocPair(types.makeFixnum(1), types.NIL);
    const obj = types.toObject(v);
    try std.testing.expectEqual(gc.id, obj.owner);

    gc.collect(); // unrooted → swept → slot quarantined, owner stamped
    try std.testing.expectEqual(FREED_OWNER, obj.owner);
    try std.testing.expectEqual(@as(usize, @sizeOf(Pair)), gc.quarantine_bytes);
}

test "quarantined slot survives a later mark phase un-recycled (gc-stress)" {
    if (comptime !free_quarantine) return error.SkipZigTest;
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    const dead = try gc.allocPair(types.makeFixnum(1), types.NIL);
    const dead_obj = types.toObject(dead);
    gc.collect(); // frees `dead`, quarantines its slot

    // A new allocation must not land in the withheld slot (the silent
    // aliasing that hid #1682), and a second collection's release point
    // (after mark, under the byte cap) must keep the sentinel readable.
    var live = try gc.allocPair(types.makeFixnum(2), types.NIL);
    gc.pushRoot(&live);
    defer gc.popRoot();
    try std.testing.expect(types.toObject(live) != dead_obj);
    gc.collect();
    try std.testing.expectEqual(FREED_OWNER, dead_obj.owner);
}

test "quarantine evicts oldest-first once over the byte cap (gc-stress)" {
    if (comptime !free_quarantine) return error.SkipZigTest;
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;
    gc.quarantine_max_bytes = @sizeOf(Pair); // hold at most one pair slot

    _ = try gc.allocPair(types.makeFixnum(1), types.NIL);
    gc.collect(); // slot A quarantined; at the cap, not over it
    try std.testing.expectEqual(@as(usize, @sizeOf(Pair)), gc.quarantine_bytes);

    _ = try gc.allocPair(types.makeFixnum(2), types.NIL);
    gc.collect(); // release point sees only A (≤ cap); sweep adds B
    try std.testing.expectEqual(@as(usize, 2 * @sizeOf(Pair)), gc.quarantine_bytes);

    gc.collect(); // now over the cap: A (oldest) is released, B stays
    try std.testing.expectEqual(@as(usize, @sizeOf(Pair)), gc.quarantine_bytes);
}

// #2127. A child GC dies while the parent is still running, so its withheld
// slots must outlive it — otherwise the drain hands them back, the parent's
// next allocation recycles one, and a parent value dangling into the dead
// child heap reads a live-looking object at the next mark instead of the
// sentinel. That is the whole cross-heap UAF class going undetected by the
// build whose only purpose is to detect it.
test "an heir inherits a dead GC's quarantined slots instead of the allocator (gc-stress)" {
    if (comptime !free_quarantine) return error.SkipZigTest;
    var parent = GC.init(std.testing.allocator);
    defer parent.deinit();
    parent.enabled = false;

    var child = GC.initForThread(std.testing.allocator, &parent);
    const v = try child.allocPair(types.makeFixnum(1), types.NIL);
    const child_obj = types.toObject(v);

    child.setQuarantineHeir(&parent);
    child.deinit();

    try std.testing.expectEqual(@as(usize, @sizeOf(Pair)), parent.quarantine_bytes);
    // Reading the dead header is defined only because the slot is withheld —
    // which is the property under test.
    try std.testing.expectEqual(FREED_OWNER, child_obj.owner);

    // And the parent must not be handed the slot back by its own allocator.
    const fresh = try parent.allocPair(types.makeFixnum(2), types.NIL);
    try std.testing.expect(types.toObject(fresh) != child_obj);
    try std.testing.expectEqual(FREED_OWNER, child_obj.owner);
}

test "a GC with no heir still drains its quarantine at deinit (gc-stress)" {
    if (comptime !free_quarantine) return error.SkipZigTest;
    var parent = GC.init(std.testing.allocator);
    defer parent.deinit();
    parent.enabled = false;

    var child = GC.initForThread(std.testing.allocator, &parent);
    _ = try child.allocPair(types.makeFixnum(1), types.NIL);
    child.deinit(); // no heir named: slots go back to the allocator

    try std.testing.expectEqual(@as(usize, 0), parent.quarantine_bytes);
}

test "handoff is refused across allocators (gc-stress)" {
    if (comptime !free_quarantine) return error.SkipZigTest;
    // An heir releases inherited slots with its OWN allocator, so a mismatch
    // must degrade to a drain rather than free a pointer the heir's allocator
    // never handed out. No production caller can hit this — a child GC is
    // built with the parent's allocator — but nothing in the type system says
    // so, and a wrong free is worse than weaker detection.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parent = GC.init(std.testing.allocator);
    defer parent.deinit();
    parent.enabled = false;

    var child = GC.init(arena.allocator());
    _ = try child.allocPair(types.makeFixnum(1), types.NIL);
    child.setQuarantineHeir(&parent);
    child.deinit();

    try std.testing.expectEqual(@as(usize, 0), parent.quarantine_bytes);
}

test "mark worklist retains capacity across collections" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    // Build a nested pair tree so markValueInner pushes onto the worklist.
    var inner = try gc.allocPair(types.makeFixnum(1), types.makeFixnum(2));
    gc.pushRoot(&inner);
    var rooted = try gc.allocPair(inner, inner);
    gc.pushRoot(&rooted);

    gc.collect();
    try std.testing.expect(!gc.marking);
    const cap_after_first = gc.mark_worklist.capacity;
    try std.testing.expect(cap_after_first > 0);

    gc.collect();
    try std.testing.expect(!gc.marking);
    try std.testing.expectEqual(cap_after_first, gc.mark_worklist.capacity);

    gc.popRoot();
    gc.popRoot();
}

// kaappi#1924: the store-rejection predicate. A store into a container the
// running thread owns is always allowed (the value may come from any heap —
// the ordinary "copy a shared global into a child-local structure" pattern);
// a store into a foreign container is rejected outright — even with a value
// owned by that same foreign heap, because routing the generational write
// barrier to the owner's remembered set cannot be done cross-thread.
// Immediates have no lifetime and always pass.
test "crossHeapStoreViolation: foreign containers are never written" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;
    gc_instance = &gc;
    defer gc_instance = null;

    const container = types.toObject(try gc.allocPair(types.NIL, types.NIL));
    const same_val = try gc.allocVectorFill(2, types.NIL);
    try std.testing.expect(!crossHeapStoreViolation(container, types.makeFixnum(1))); // immediate
    try std.testing.expect(!crossHeapStoreViolation(container, same_val)); // own container, any value
    try std.testing.expect(!crossHeapStoreViolation(container, types.NIL)); // non-pointer

    // A container owned by ANOTHER gc is never written, whatever the value's
    // owner: a value from the running thread's own heap would dangle once
    // this heap is freed, and a value from the container's own heap would
    // need the owner's remembered-set barrier for a young value.
    var other = GC.init(std.testing.allocator);
    defer other.deinit();
    other.enabled = false;
    const foreign = types.toObject(try other.allocPair(types.NIL, types.NIL));
    try std.testing.expect(container.owner != foreign.owner);
    try std.testing.expect(crossHeapStoreViolation(foreign, same_val));
    const foreign_val = try other.allocVectorFill(1, types.NIL);
    try std.testing.expect(crossHeapStoreViolation(foreign, foreign_val));
}

test "allocSliceNoFill: write and read back" {
    const buf = try allocSliceNoFill(std.testing.allocator, u8, 16);
    defer freeSliceNoFill(std.testing.allocator, u8, buf);
    for (buf, 0..) |*b, i| b.* = @truncate(i);
    for (buf, 0..) |b, i| try std.testing.expectEqual(@as(u8, @truncate(i)), b);
}

test "allocSliceNoFill: works for non-byte element types" {
    const buf = try allocSliceNoFill(std.testing.allocator, Value, 8);
    defer freeSliceNoFill(std.testing.allocator, Value, buf);
    for (buf) |*v| v.* = types.makeFixnum(42);
    for (buf) |v| try std.testing.expectEqual(@as(i64, 42), types.toFixnum(v));
}

// #1809: a naive `n == 0` (rather than `byte_count == 0`) guard is
// equivalent for every real element type Kaappi uses, but the load-bearing
// behavior this pins down is that a zero-length alloc/free never reaches
// `rawAlloc`/`rawFree` at all. `std.testing.allocator` is a `DebugAllocator`
// whose size-class math does `len - 1`, which panics on overflow for a
// true zero-length call — this must short-circuit before that.
test "allocSliceNoFill/freeSliceNoFill: zero length does not reach the allocator" {
    const buf = try allocSliceNoFill(std.testing.allocator, Value, 0);
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    freeSliceNoFill(std.testing.allocator, Value, buf);

    const empty_u8 = try allocSliceNoFill(std.testing.allocator, u8, 0);
    try std.testing.expectEqual(@as(usize, 0), empty_u8.len);
    freeSliceNoFill(std.testing.allocator, u8, empty_u8);
}

test "dupeSliceNoFill: copies into a distinct buffer" {
    const src = [_]u8{ 1, 2, 3, 4, 5 };
    const copy = try dupeSliceNoFill(std.testing.allocator, u8, &src);
    defer freeSliceNoFill(std.testing.allocator, u8, copy);
    try std.testing.expectEqualSlices(u8, &src, copy);
    try std.testing.expect(@intFromPtr(copy.ptr) != @intFromPtr(&src));
}

test "dupeSliceNoFill: zero length" {
    const src = [_]u8{};
    const copy = try dupeSliceNoFill(std.testing.allocator, u8, &src);
    try std.testing.expectEqual(@as(usize, 0), copy.len);
    freeSliceNoFill(std.testing.allocator, u8, copy);
}

test "allocSliceNoFill: propagates OutOfMemory" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, allocSliceNoFill(failing.allocator(), u8, 64));
}

test "dupeSliceNoFill: propagates OutOfMemory" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const src = [_]u8{ 9, 9, 9 };
    try std.testing.expectError(error.OutOfMemory, dupeSliceNoFill(failing.allocator(), u8, &src));
}

// #2435: the raw-allocator OOM injector. `GC.oom_countdown` cannot reach a
// raw allocation — `allocSliceNoFill` goes straight to `rawAlloc`, never
// through `maybeCollect` — so the injector that CAN must count those calls
// and fail them on demand, independently of the GC counter.
test "OomAllocator: reaches a raw allocSliceNoFill that oom_countdown never sees" {
    var oom = OomAllocator.init(std.testing.allocator);
    const a = oom.allocator();

    // Disarmed: forwards untouched.
    const s0 = try allocSliceNoFill(a, u64, 4);
    freeSliceNoFill(a, u64, s0);

    // Budget of 1: the first acquisition succeeds, the next fails and every
    // one after stays failing (sticky, matching oom_countdown).
    oom.countdown = 1;
    const s1 = try allocSliceNoFill(a, u64, 4);
    freeSliceNoFill(a, u64, s1); // a free is not a tick
    try std.testing.expectError(error.OutOfMemory, allocSliceNoFill(a, u64, 4));
    try std.testing.expectError(error.OutOfMemory, allocSliceNoFill(a, u64, 4));

    // Failing immediately: countdown 0 fails the very first acquisition.
    oom.countdown = 0;
    try std.testing.expectError(error.OutOfMemory, allocSliceNoFill(a, u64, 4));

    // Re-disarm and confirm the backing allocator is intact (no leak, works).
    oom.countdown = null;
    const s2 = try allocSliceNoFill(a, u64, 4);
    freeSliceNoFill(a, u64, s2);
}

// The reactor timer heap (`addTimer`) and the scheduler's `driving_waits`
// grow through `ArrayList`/`PriorityQueue`, whose `ensureTotalCapacityPrecise`
// tries `remap` then falls back to `alloc`. Both must refuse once the budget
// is spent, or a growth would slip past an armed injector — this is the exact
// allocation shape behind the #2429/#2433 scheduler OOM paths.
test "OomAllocator: fails ArrayList growth once the budget is spent" {
    var oom = OomAllocator.init(std.testing.allocator);
    const a = oom.allocator();

    var list: std.ArrayList(u64) = .empty;
    defer list.deinit(a);

    // Fail the first buffer acquisition: append from empty must OOM.
    oom.countdown = 0;
    try std.testing.expectError(error.OutOfMemory, list.append(a, 1));
    try std.testing.expectEqual(@as(usize, 0), list.items.len);

    // Disarm and grow across several reallocations to exercise the remap /
    // alloc fallback while forwarding faithfully.
    oom.countdown = null;
    var i: u64 = 0;
    while (i < 64) : (i += 1) try list.append(a, i);
    try std.testing.expectEqual(@as(usize, 64), list.items.len);
    for (list.items, 0..) |v, idx| try std.testing.expectEqual(@as(u64, @intCast(idx)), v);
}
