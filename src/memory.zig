const std = @import("std");
const types = @import("types.zig");
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
};

pub var symbol_mutex: std.atomic.Mutex = .unlocked;

/// Monotonic source of unique GC ids (see `GC.id`). Never reused, so a live
/// GC can never collide with a dead thread's id. Starts at 1 so 0 is never a
/// valid id.
var next_gc_id: u32 = 0;

fn nextGcId() u32 {
    return @atomicRmw(u32, &next_gc_id, .Add, 1, .monotonic) + 1;
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
    /// For a child gc: the parent gc's id, stamped on symbols the child
    /// interns into the shared table (the parent owns and frees those).
    shared_owner_id: u32 = 0,
    root_buffer: [1024]*Value = undefined,
    root_count: u16 = 0,
    extra_roots: std.ArrayList(Value),
    arg_roots: [4]Value = .{ 0, 0, 0, 0 },
    arg_root_count: u3 = 0,
    remembered_set: std.ArrayList(*Object),
    stress: bool = build_options.gc_stress,
    enabled: bool = true,
    no_collect: u32 = 0,
    bytes_allocated: usize = 0,
    memory_limit: ?usize = null,
    profile_alloc_target: ?*u64 = null,
    root_marker: ?*const fn (*GC) void = null,
    source_lines: std.AutoHashMap(Value, u32) = undefined,
    stats: GcStats = .{},
    minor_cycle_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) GC {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Value).init(allocator),
            .extra_roots = .empty,
            .remembered_set = .empty,
            .source_lines = std.AutoHashMap(Value, u32).init(allocator),
            .id = nextGcId(),
        };
    }

    pub fn initForThread(allocator: std.mem.Allocator, parent: *GC) GC {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Value).init(allocator),
            .shared_symbols = &parent.symbols,
            .shared_foreign_symbols = &parent.foreign_symbols,
            .extra_roots = .empty,
            .remembered_set = .empty,
            .source_lines = std.AutoHashMap(Value, u32).init(allocator),
            .gc_threshold = GC_THRESHOLD,
            .id = nextGcId(),
            .shared_owner_id = parent.id,
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
        // runs at deinit — every child has joined — so this needs no lock.
        for (self.foreign_symbols.items) |o| gc_collect.freeObject(self, o);
        self.foreign_symbols.deinit(self.allocator);
        self.symbols.deinit();
        self.extra_roots.deinit(self.allocator);
        self.remembered_set.deinit(self.allocator);
        self.source_lines.deinit();
    }

    pub fn writeBarrier(self: *GC, container: *Object, new_val: Value) void {
        if (container.generation == 1 and types.isPointer(new_val)) {
            const child = types.toObject(new_val);
            // A foreign new_val (another GC's object) is never traced by this
            // GC, so it needs no remembered-set entry — and reading its
            // generation bit would race the owner's collection cycle.
            if (child.owner == self.id and child.generation == 0) {
                self.remembered_set.append(self.allocator, container) catch @panic("GC writeBarrier: remembered set OOM");
            }
        }
    }

    inline fn profileAlloc(self: *GC, size: usize) void {
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

    inline fn rootArgs1(self: *GC, a: Value) void {
        self.arg_roots[0] = a;
        self.arg_root_count = 1;
    }

    inline fn rootArgs2(self: *GC, a: Value, b: Value) void {
        self.arg_roots[0] = a;
        self.arg_roots[1] = b;
        self.arg_root_count = 2;
    }

    inline fn clearArgRoots(self: *GC) void {
        self.arg_root_count = 0;
    }

    pub inline fn finishAlloc(self: *GC, obj: *Object, size: usize) void {
        self.bytes_allocated += size;
        self.profileAlloc(size);
        self.trackObject(obj);
    }

    pub fn allocPair(self: *GC, car_val: Value, cdr_val: Value) !Value {
        self.rootArgs2(car_val, cdr_val);
        try self.maybeCollect();
        self.clearArgRoots();
        const pair = try self.allocator.create(Pair);
        pair.* = .{
            .header = .{ .tag = .pair },
            .car = car_val,
            .cdr = cdr_val,
        };
        self.finishAlloc(&pair.header, @sizeOf(Pair));
        return types.makePointer(@ptrCast(pair));
    }

    pub fn allocSymbol(self: *GC, name: []const u8) !Value {
        // `is_child` means this GC aliases the parent's symbol table via
        // `shared_symbols`; the parent GC (shared_symbols == null) owns that
        // very table as its own `symbols` field. Both sides are therefore
        // concurrent readers/writers of one StringHashMap whenever an SRFI-18
        // child thread is alive, so the lock must be taken *unconditionally* —
        // not just by children. `StringHashMap.put` can rehash (realloc + free
        // of the bucket array), and an unlocked parent-side get/put racing a
        // child's locked access corrupts the map (issue #797).
        //
        // Deadlock-free by the same argument as gc_collect.zig markRoots (which
        // also takes symbol_mutex while iterating the table): allocSymbol never
        // calls maybeCollect, so a thread can never re-enter GC marking — which
        // acquires this same non-reentrant lock — while holding it here.
        const is_child = self.shared_symbols != null;
        const sym_table = self.shared_symbols orelse &self.symbols;

        spinLock(&symbol_mutex);
        defer spinUnlock(&symbol_mutex);

        if (sym_table.get(name)) |existing| return existing;

        const owned_name = try self.allocator.dupe(u8, name);
        const sym = try self.allocator.create(Symbol);
        sym.* = .{
            .header = .{ .tag = .symbol },
            .name = owned_name,
        };
        const size = @sizeOf(Symbol) + name.len;
        self.bytes_allocated += size;
        self.profileAlloc(size);

        if (is_child) {
            // The symbol lives in the parent's shared table and must outlive
            // this child thread, so hand ownership to the parent (freed at the
            // parent's deinit). Appended under `symbol_mutex`, held here.
            // `shared_foreign_symbols` is set whenever `shared_symbols` is.
            // Stamp the parent's id: the parent owns it, and the parent's
            // markRoots pass over the shared table must not skip it.
            sym.header.owner = self.shared_owner_id;
            self.shared_foreign_symbols.?.append(self.allocator, &sym.header) catch {
                self.allocator.destroy(sym);
                self.allocator.free(owned_name);
                return error.OutOfMemory;
            };
        } else {
            self.trackObject(&sym.header);
        }

        const val = types.makePointer(@ptrCast(sym));
        try sym_table.put(owned_name, val);
        return val;
    }

    pub fn allocString(self: *GC, data: []const u8) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(owned);
        const str = try self.allocator.create(SchemeString);
        str.* = .{
            .header = .{ .tag = .string },
            .data = owned,
            .len = data.len,
        };
        self.finishAlloc(&str.header, @sizeOf(SchemeString) + data.len);
        return types.makePointer(@ptrCast(str));
    }

    pub fn allocFunction(self: *GC) !*Function {
        const func = try self.allocator.create(Function);
        func.* = .{
            .header = .{ .tag = .function },
            .code = .empty,
            .constants = .empty,
            .arity = 0,
        };
        self.finishAlloc(&func.header, @sizeOf(Function));
        return func;
    }

    pub fn allocClosure(self: *GC, func: *Function) !Value {
        self.rootArgs1(types.makePointer(@ptrCast(func)));
        try self.maybeCollect();
        self.clearArgRoots();
        const upvalue_count = func.upvalue_count;
        const upvalues = try self.allocator.alloc(Value, upvalue_count);
        errdefer self.allocator.free(upvalues);
        @memset(upvalues, types.UNDEFINED);

        const cls = try self.allocator.create(Closure);
        cls.* = .{
            .header = .{ .tag = .closure },
            .func = func,
            .upvalues = upvalues,
        };
        self.finishAlloc(&cls.header, @sizeOf(Closure) + @as(usize, upvalue_count) * @sizeOf(Value));
        return types.makePointer(@ptrCast(cls));
    }

    pub fn allocNativeFn(self: *GC, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !Value {
        const nf = try self.allocator.create(NativeFn);
        nf.* = .{
            .header = .{ .tag = .native_fn },
            .func = func,
            .name = name,
            .arity = arity,
        };
        self.finishAlloc(&nf.header, @sizeOf(NativeFn));
        return types.makePointer(@ptrCast(nf));
    }

    pub fn allocNativeClosure(self: *GC, fn_ptr: types.NativeClosureFnType, upvalues: []const Value, arity: u8, name: []const u8) !Value {
        try self.maybeCollect();
        const uv_copy = try self.allocator.alloc(Value, upvalues.len);
        errdefer self.allocator.free(uv_copy);
        @memcpy(uv_copy, upvalues);
        const nc = try self.allocator.create(types.NativeClosure);
        nc.* = .{
            .header = .{ .tag = .native_closure },
            .fn_ptr = fn_ptr,
            .upvalues = uv_copy,
            .arity = arity,
            .name = name,
        };
        self.finishAlloc(&nc.header, @sizeOf(types.NativeClosure) + upvalues.len * @sizeOf(Value));
        return types.makePointer(@ptrCast(nc));
    }

    pub fn allocFlonum(self: *GC, value: f64) !Value {
        _ = self;
        return types.makeFlonum(value);
    }

    pub fn allocVector(self: *GC, data: []const Value) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.alloc(Value, data.len);
        errdefer self.allocator.free(owned);
        @memcpy(owned, data);
        const vec = try self.allocator.create(Vector);
        vec.* = .{
            .header = .{ .tag = .vector },
            .data = owned,
        };
        self.finishAlloc(&vec.header, @sizeOf(Vector) + data.len * @sizeOf(Value));
        return types.makePointer(@ptrCast(vec));
    }

    pub fn allocVectorFill(self: *GC, size: usize, fill: Value) !Value {
        self.rootArgs1(fill);
        try self.maybeCollect();
        self.clearArgRoots();
        const data = try self.allocator.alloc(Value, size);
        errdefer self.allocator.free(data);
        @memset(data, fill);
        const vec = try self.allocator.create(Vector);
        vec.* = .{
            .header = .{ .tag = .vector },
            .data = data,
        };
        self.finishAlloc(&vec.header, @sizeOf(Vector) + size * @sizeOf(Value));
        return types.makePointer(@ptrCast(vec));
    }

    pub fn allocErrorObject(self: *GC, message: Value, irritants: Value) !Value {
        self.rootArgs2(message, irritants);
        try self.maybeCollect();
        self.clearArgRoots();
        const err = try self.allocator.create(types.ErrorObject);
        err.* = .{
            .header = .{ .tag = .error_object },
            .message = message,
            .irritants = irritants,
        };
        self.finishAlloc(&err.header, @sizeOf(types.ErrorObject));
        return types.makePointer(@ptrCast(err));
    }

    pub fn allocTransformer(self: *GC, literals: []const Value, patterns: []const Value, templates: []const Value) !Value {
        const num_rules: u16 = @intCast(patterns.len);
        const owned_lits = try self.allocator.dupe(Value, literals);
        errdefer self.allocator.free(owned_lits);
        const owned_pats = try self.allocator.dupe(Value, patterns);
        errdefer self.allocator.free(owned_pats);
        const owned_tmps = try self.allocator.dupe(Value, templates);
        errdefer self.allocator.free(owned_tmps);

        const tx = try self.allocator.create(Transformer);
        tx.* = .{
            .header = .{ .tag = .transformer },
            .literals = owned_lits,
            .patterns = owned_pats,
            .templates = owned_tmps,
            .num_rules = num_rules,
        };
        self.finishAlloc(&tx.header, @sizeOf(Transformer) + (literals.len + patterns.len + templates.len) * @sizeOf(Value));
        return types.makePointer(@ptrCast(tx));
    }

    pub fn allocRecordType(self: *GC, name: []const u8, num_fields: u8) !Value {
        try self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const rt = try self.allocator.create(RecordType);
        rt.* = .{
            .header = .{ .tag = .record_type },
            .name = owned_name,
            .num_fields = num_fields,
        };
        self.finishAlloc(&rt.header, @sizeOf(RecordType) + name.len);
        return types.makePointer(@ptrCast(rt));
    }

    pub fn allocRecordInstance(self: *GC, record_type: *RecordType, field_values: []const Value) !Value {
        try self.maybeCollect();
        const fields = try self.allocator.alloc(Value, record_type.num_fields);
        errdefer self.allocator.free(fields);
        for (0..record_type.num_fields) |i| {
            if (i < field_values.len) {
                fields[i] = field_values[i];
            } else {
                fields[i] = types.UNDEFINED;
            }
        }
        const ri = try self.allocator.create(RecordInstance);
        ri.* = .{
            .header = .{ .tag = .record_instance },
            .record_type = record_type,
            .fields = fields,
        };
        self.finishAlloc(&ri.header, @sizeOf(RecordInstance) + record_type.num_fields * @sizeOf(Value));
        return types.makePointer(@ptrCast(ri));
    }

    pub fn allocPort(self: *GC, fd: std.posix.fd_t, is_input: bool, is_output: bool, name: []const u8, owns_name: bool) !Value {
        try self.maybeCollect();
        const port = try self.allocator.create(Port);
        port.* = .{
            .header = .{ .tag = .port },
            .fd = fd,
            .is_input = is_input,
            .is_output = is_output,
            .is_open = true,
            .name = name,
            .owns_name = owns_name,
            .peek_byte = null,
            .is_string_port = false,
            .string_data = null,
            .string_pos = 0,
            .string_out_buf = null,
            .string_out_len = 0,
            .string_out_cap = 0,
        };
        self.finishAlloc(&port.header, @sizeOf(Port));
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocStringInputPort(self: *GC, data: []const u8) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(owned);
        const port = try self.allocator.create(Port);
        port.* = .{
            .header = .{ .tag = .port },
            .fd = -1,
            .is_input = true,
            .is_output = false,
            .is_open = true,
            .name = "string",
            .owns_name = false,
            .peek_byte = null,
            .is_string_port = true,
            .string_data = owned,
            .string_pos = 0,
        };
        self.finishAlloc(&port.header, @sizeOf(Port) + data.len);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocStringOutputPort(self: *GC) !Value {
        try self.maybeCollect();
        const initial_cap: usize = 64;
        const buf = try self.allocator.alloc(u8, initial_cap);
        errdefer self.allocator.free(buf);
        const port = try self.allocator.create(Port);
        port.* = .{
            .header = .{ .tag = .port },
            .fd = -1,
            .is_input = false,
            .is_output = true,
            .is_open = true,
            .name = "string",
            .owns_name = false,
            .peek_byte = null,
            .is_string_port = true,
            .string_out_buf = buf,
            .string_out_len = 0,
            .string_out_cap = initial_cap,
        };
        self.finishAlloc(&port.header, @sizeOf(Port) + initial_cap);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocBytevector(self: *GC, data: []const u8) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(owned);
        const bv = try self.allocator.create(Bytevector);
        bv.* = .{
            .header = .{ .tag = .bytevector },
            .data = owned,
        };
        self.finishAlloc(&bv.header, @sizeOf(Bytevector) + data.len);
        return types.makePointer(@ptrCast(bv));
    }

    pub fn allocBytevectorFill(self: *GC, size: usize, fill: u8) !Value {
        try self.maybeCollect();
        const data = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(data);
        @memset(data, fill);
        const bv = try self.allocator.create(Bytevector);
        bv.* = .{
            .header = .{ .tag = .bytevector },
            .data = data,
        };
        self.finishAlloc(&bv.header, @sizeOf(Bytevector) + size);
        return types.makePointer(@ptrCast(bv));
    }

    pub fn allocPromise(self: *GC, forced: bool, value: Value) !Value {
        self.rootArgs1(value);
        try self.maybeCollect();
        self.clearArgRoots();
        const p = try self.allocator.create(Promise);
        p.* = .{
            .header = .{ .tag = .promise },
            .forced = forced,
            .value = value,
        };
        self.finishAlloc(&p.header, @sizeOf(Promise));
        return types.makePointer(@ptrCast(p));
    }

    pub fn allocContinuation(
        self: *GC,
        registers: []const Value,
        frames: []const SavedFrame,
        frame_count: usize,
        handlers: []const SavedHandler,
        handler_count: usize,
        wind_records: []const WindRecord,
        wind_count: usize,
        dst_reg: u16,
        dst_base: u32,
    ) !Value {
        try self.maybeCollect();

        // Pack the four saved arrays into one backing allocation. Every element
        // type is a multiple of Value's size and no more strictly aligned than
        // Value, so a []Value buffer is correctly aligned for each section and
        // each section begins on a Value boundary.
        comptime {
            std.debug.assert(@sizeOf(SavedFrame) % @sizeOf(Value) == 0);
            std.debug.assert(@sizeOf(SavedHandler) % @sizeOf(Value) == 0);
            std.debug.assert(@sizeOf(WindRecord) % @sizeOf(Value) == 0);
            std.debug.assert(@alignOf(SavedFrame) <= @alignOf(Value));
            std.debug.assert(@alignOf(SavedHandler) <= @alignOf(Value));
            std.debug.assert(@alignOf(WindRecord) <= @alignOf(Value));
        }
        const frame_words = frames.len * (@sizeOf(SavedFrame) / @sizeOf(Value));
        const handler_words = handlers.len * (@sizeOf(SavedHandler) / @sizeOf(Value));
        const wind_words = wind_records.len * (@sizeOf(WindRecord) / @sizeOf(Value));
        const total_words = registers.len + frame_words + handler_words + wind_words;

        const backing = try self.allocator.alloc(Value, total_words);
        errdefer self.allocator.free(backing);

        var off: usize = 0;
        const saved_regs = backing[off..][0..registers.len];
        off += registers.len;
        const frames_ptr: [*]SavedFrame = @ptrCast(@alignCast(backing.ptr + off));
        const saved_frames = frames_ptr[0..frames.len];
        off += frame_words;
        const handlers_ptr: [*]SavedHandler = @ptrCast(@alignCast(backing.ptr + off));
        const saved_handlers = handlers_ptr[0..handlers.len];
        off += handler_words;
        const winds_ptr: [*]WindRecord = @ptrCast(@alignCast(backing.ptr + off));
        const saved_winds = winds_ptr[0..wind_records.len];

        @memcpy(saved_regs, registers);
        @memcpy(saved_frames, frames);
        @memcpy(saved_handlers, handlers);
        @memcpy(saved_winds, wind_records);

        const cont = try self.allocator.create(Continuation);
        cont.* = .{
            .header = .{ .tag = .continuation },
            .registers = saved_regs,
            .frames = saved_frames,
            .frame_count = frame_count,
            .handlers = saved_handlers,
            .handler_count = handler_count,
            .wind_records = saved_winds,
            .wind_count = wind_count,
            .dst_reg = dst_reg,
            .dst_base = dst_base,
            .backing = backing,
        };
        self.finishAlloc(&cont.header, @sizeOf(Continuation) +
            registers.len * @sizeOf(Value) +
            frames.len * @sizeOf(SavedFrame) +
            handlers.len * @sizeOf(SavedHandler) +
            wind_records.len * @sizeOf(WindRecord));
        return types.makePointer(@ptrCast(cont));
    }

    /// Allocate an escape continuation (call/ec). Unlike a full continuation,
    /// this copies nothing: it records only the stack depths to unwind back to.
    /// Capture is therefore O(1) with a single allocation and no backing buffer.
    pub fn allocEscapeContinuation(
        self: *GC,
        target_frame_count: usize,
        target_wind_count: usize,
        target_handler_count: usize,
        dst_reg: u16,
        dst_base: u32,
    ) !Value {
        try self.maybeCollect();
        const cont = try self.allocator.create(Continuation);
        cont.* = .{
            .header = .{ .tag = .continuation },
            // No snapshot: empty slices keep GC mark loops no-ops.
            .registers = &.{},
            .frames = &.{},
            .frame_count = 0,
            .handlers = &.{},
            .handler_count = 0,
            .wind_records = &.{},
            .wind_count = 0,
            .dst_reg = dst_reg,
            .dst_base = dst_base,
            .backing = &.{},
            .is_escape = true,
            .valid = true,
            .target_frame_count = target_frame_count,
            .target_wind_count = target_wind_count,
            .target_handler_count = target_handler_count,
        };
        self.finishAlloc(&cont.header, @sizeOf(Continuation));
        return types.makePointer(@ptrCast(cont));
    }

    pub fn allocComplex(self: *GC, real: f64, imag: f64) !Value {
        return self.allocComplexEx(real, imag, false, false);
    }

    pub fn allocComplexEx(self: *GC, real: f64, imag: f64, exact_real: bool, exact_imag: bool) !Value {
        try self.maybeCollect();
        const c = try self.allocator.create(types.Complex);
        c.* = .{
            .header = .{ .tag = .complex },
            .real = real,
            .imag = imag,
            .exact_real = exact_real,
            .exact_imag = exact_imag,
        };
        self.finishAlloc(&c.header, @sizeOf(types.Complex));
        return types.makePointer(@ptrCast(c));
    }

    pub fn allocParameter(self: *GC, init_value: Value, converter: Value) !Value {
        self.rootArgs2(init_value, converter);
        try self.maybeCollect();
        self.clearArgRoots();
        const p = try self.allocator.create(types.ParameterObject);
        p.* = .{
            .header = .{ .tag = .parameter },
            .value = init_value,
            .converter = converter,
        };
        self.finishAlloc(&p.header, @sizeOf(types.ParameterObject));
        return types.makePointer(@ptrCast(p));
    }

    pub fn allocFfiLibrary(self: *GC, handle: ?*anyopaque, name: []const u8) !Value {
        try self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const lib = try self.allocator.create(FfiLibrary);
        lib.* = .{
            .header = .{ .tag = .ffi_library },
            .handle = handle,
            .name = owned_name,
        };
        self.finishAlloc(&lib.header, @sizeOf(FfiLibrary) + name.len);
        return types.makePointer(@ptrCast(lib));
    }

    pub fn allocFfiFunction(self: *GC, symbol: *anyopaque, library: Value, name: []const u8, param_types: []const FfiType, return_type: FfiType) !Value {
        self.rootArgs1(library);
        try self.maybeCollect();
        self.clearArgRoots();
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_params = try self.allocator.dupe(FfiType, param_types);
        errdefer self.allocator.free(owned_params);
        const ffi_fn = try self.allocator.create(FfiFunction);
        ffi_fn.* = .{
            .header = .{ .tag = .ffi_function },
            .symbol = symbol,
            .library = library,
            .name = owned_name,
            .param_types = owned_params,
            .return_type = return_type,
            .param_count = @intCast(param_types.len),
        };
        self.finishAlloc(&ffi_fn.header, @sizeOf(FfiFunction) + name.len + param_types.len * @sizeOf(FfiType));
        return types.makePointer(@ptrCast(ffi_fn));
    }

    pub fn allocFfiCallback(self: *GC, closure: Value, slot_index: u8, fn_ptr: *anyopaque) !Value {
        self.rootArgs1(closure);
        try self.maybeCollect();
        self.clearArgRoots();
        const cb = try self.allocator.create(FfiCallback);
        cb.* = .{
            .header = .{ .tag = .ffi_callback },
            .closure = closure,
            .slot_index = slot_index,
            .fn_ptr = fn_ptr,
            .active = true,
        };
        self.finishAlloc(&cb.header, @sizeOf(FfiCallback));
        return types.makePointer(@ptrCast(cb));
    }

    pub fn allocRandomSource(self: *GC, seed: u64) !Value {
        try self.maybeCollect();
        const rs = try self.allocator.create(RandomSource);
        rs.* = .{
            .header = .{ .tag = .random_source },
            .prng = std.Random.DefaultPrng.init(seed),
        };
        self.finishAlloc(&rs.header, @sizeOf(RandomSource));
        return types.makePointer(@ptrCast(rs));
    }

    pub fn allocFiber(self: *GC, thunk: Value, id: u32) !*@import("fiber.zig").Fiber {
        self.rootArgs1(thunk);
        try self.maybeCollect();
        self.clearArgRoots();
        const fiber_mod = @import("fiber.zig");
        const registers = try self.allocator.alloc(Value, types.INITIAL_REGISTER_CAPACITY);
        errdefer self.allocator.free(registers);
        const frames = try self.allocator.alloc(types.CallFrame, types.INITIAL_FRAME_CAPACITY);
        errdefer self.allocator.free(frames);
        const fiber = try self.allocator.create(fiber_mod.Fiber);
        fiber.* = .{
            .header = .{ .tag = .fiber },
            .registers = registers,
            .frames = frames,
            .frame_count = 0,
            .handler_stack = undefined,
            .handler_count = 0,
            .wind_stack = undefined,
            .wind_count = 0,
            .current_exception = null,
            .continuation_invoked = false,
            .continuation_value = types.VOID,
            .status = .created,
            .thunk = thunk,
            .result = types.VOID,
            .waiting_on = types.VOID,
            .id = id,
            .name = types.VOID,
            .specific = types.VOID,
            .deadline_ns = null,
            .timed_out = false,
            .terminated = false,
            .param_overrides = std.AutoHashMap(usize, Value).init(self.allocator),
        };
        @memset(fiber.registers, types.UNDEFINED);
        self.finishAlloc(&fiber.header, @sizeOf(fiber_mod.Fiber) +
            registers.len * @sizeOf(Value) +
            frames.len * @sizeOf(types.CallFrame));
        return fiber;
    }

    pub fn allocChannel(self: *GC) !Value {
        try self.maybeCollect();
        const ch = try self.allocator.create(types.Channel);
        ch.* = .{
            .header = .{ .tag = .channel },
            .head = types.NIL,
            .tail = types.NIL,
        };
        self.finishAlloc(&ch.header, @sizeOf(types.Channel));
        return types.makePointer(@ptrCast(ch));
    }

    pub fn allocMutex(self: *GC, name: Value) !Value {
        self.rootArgs1(name);
        try self.maybeCollect();
        self.clearArgRoots();
        const m = try self.allocator.create(types.Mutex);
        m.* = .{
            .header = .{ .tag = .mutex },
            .name = name,
            .owner = types.VOID,
            .locked = false,
            .abandoned = false,
            .specific = types.VOID,
        };
        self.finishAlloc(&m.header, @sizeOf(types.Mutex));
        return types.makePointer(@ptrCast(m));
    }

    pub fn allocConditionVariable(self: *GC, name: Value) !Value {
        self.rootArgs1(name);
        try self.maybeCollect();
        self.clearArgRoots();
        const cv = try self.allocator.create(types.ConditionVariable);
        cv.* = .{
            .header = .{ .tag = .condition_variable },
            .name = name,
            .specific = types.VOID,
        };
        self.finishAlloc(&cv.header, @sizeOf(types.ConditionVariable));
        return types.makePointer(@ptrCast(cv));
    }

    pub fn allocSrfi18Time(self: *GC, seconds: f64) !Value {
        try self.maybeCollect();
        const t = try self.allocator.create(types.Srfi18Time);
        t.* = .{
            .header = .{ .tag = .srfi18_time },
            .seconds = seconds,
        };
        self.finishAlloc(&t.header, @sizeOf(types.Srfi18Time));
        return types.makePointer(@ptrCast(t));
    }

    pub fn allocHashTable(self: *GC, initial_capacity: usize) !Value {
        try self.maybeCollect();
        // Ensure capacity is a power of 2 (minimum 8)
        var cap = if (initial_capacity < 8) @as(usize, 8) else initial_capacity;
        if (cap & (cap - 1) != 0) {
            cap = @as(usize, 1) << @intCast(@as(std.math.Log2Int(usize), @intCast(@bitSizeOf(usize) - @clz(cap))));
        }
        const entries = try self.allocator.alloc(HashEntry, cap);
        errdefer self.allocator.free(entries);
        for (entries) |*e| {
            e.* = .{ .key = 0, .value = 0, .state = .empty };
        }
        const ht = try self.allocator.create(HashTable);
        ht.* = .{
            .header = .{ .tag = .hash_table },
            .entries = entries,
            .count = 0,
            .capacity = cap,
        };
        self.finishAlloc(&ht.header, @sizeOf(HashTable) + cap * @sizeOf(HashEntry));
        return types.makePointer(@ptrCast(ht));
    }

    pub fn allocBignumFromI64(self: *GC, n: i64) !Value {
        try self.maybeCollect();
        const limbs = try self.allocator.alloc(u64, 1);
        errdefer self.allocator.free(limbs);
        const bn = try self.allocator.create(Bignum);
        const mag: u64 = if (n < 0) @intCast(-@as(i128, n)) else @intCast(n);
        limbs[0] = mag;
        bn.* = .{
            .header = .{ .tag = .bignum },
            .limbs = limbs,
            .len = if (mag == 0) 0 else 1,
            .positive = n >= 0,
        };
        self.finishAlloc(&bn.header, @sizeOf(Bignum) + @sizeOf(u64));
        return types.makePointer(@ptrCast(bn));
    }

    pub fn allocBignumFromLimbs(self: *GC, limbs: []const u64, len: usize, positive: bool) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.alloc(u64, limbs.len);
        errdefer self.allocator.free(owned);
        const bn = try self.allocator.create(Bignum);
        @memcpy(owned, limbs);
        bn.* = .{
            .header = .{ .tag = .bignum },
            .limbs = owned,
            .len = len,
            .positive = positive,
        };
        self.finishAlloc(&bn.header, @sizeOf(Bignum) + limbs.len * @sizeOf(u64));
        return types.makePointer(@ptrCast(bn));
    }

    pub fn allocRational(self: *GC, num: Value, den: Value) !Value {
        self.rootArgs2(num, den);
        try self.maybeCollect();
        self.clearArgRoots();
        const rat = try self.allocator.create(Rational);
        rat.* = .{
            .header = .{ .tag = .rational },
            .numerator = num,
            .denominator = den,
        };
        self.finishAlloc(&rat.header, @sizeOf(Rational));
        return types.makePointer(@ptrCast(rat));
    }

    pub fn allocFileInfo(self: *GC, info: struct {
        size: i64,
        mtime: i64,
        atime: i64,
        ctime: i64,
        dev: i64,
        ino: i64,
        nlinks: i64,
        rdev: i64,
        blksize: i64,
        blocks: i64,
        mode: u32,
        uid: u32,
        gid: u32,
        file_type: types.FileInfo.FileType,
    }) !Value {
        try self.maybeCollect();
        const fi = try self.allocator.create(types.FileInfo);
        fi.* = .{
            .header = .{ .tag = .file_info },
            .size = info.size,
            .mtime = info.mtime,
            .atime = info.atime,
            .ctime = info.ctime,
            .dev = info.dev,
            .ino = info.ino,
            .nlinks = info.nlinks,
            .rdev = info.rdev,
            .blksize = info.blksize,
            .blocks = info.blocks,
            .mode = info.mode,
            .uid = info.uid,
            .gid = info.gid,
            .file_type = info.file_type,
        };
        self.finishAlloc(&fi.header, @sizeOf(types.FileInfo));
        return types.makePointer(@ptrCast(fi));
    }

    pub fn allocUserInfo(self: *GC, name: []const u8, uid: u32, gid: u32, home_dir: []const u8, shell: []const u8, full_name: []const u8) !Value {
        try self.maybeCollect();
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const home_copy = try self.allocator.dupe(u8, home_dir);
        errdefer self.allocator.free(home_copy);
        const shell_copy = try self.allocator.dupe(u8, shell);
        errdefer self.allocator.free(shell_copy);
        const gecos_copy = try self.allocator.dupe(u8, full_name);
        errdefer self.allocator.free(gecos_copy);
        const ui = try self.allocator.create(types.UserInfo);
        ui.* = .{
            .header = .{ .tag = .user_info },
            .name = name_copy,
            .uid = uid,
            .gid = gid,
            .home_dir = home_copy,
            .shell = shell_copy,
            .full_name = gecos_copy,
        };
        self.finishAlloc(&ui.header, @sizeOf(types.UserInfo) + name.len + home_dir.len + shell.len + full_name.len);
        return types.makePointer(@ptrCast(ui));
    }

    pub fn allocGroupInfo(self: *GC, name: []const u8, gid: u32) !Value {
        try self.maybeCollect();
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const gi = try self.allocator.create(types.GroupInfo);
        gi.* = .{
            .header = .{ .tag = .group_info },
            .name = name_copy,
            .gid = gid,
        };
        self.finishAlloc(&gi.header, @sizeOf(types.GroupInfo) + name.len);
        return types.makePointer(@ptrCast(gi));
    }

    pub fn allocEnvironment(self: *GC, env_map: *std.StringHashMap(Value), owned: bool) !Value {
        try self.maybeCollect();
        const se = try self.allocator.create(types.SchemeEnvironment);
        se.* = .{
            .header = .{ .tag = .scheme_environment },
            .env = env_map,
            .owned = owned,
        };
        self.finishAlloc(&se.header, @sizeOf(types.SchemeEnvironment));
        return types.makePointer(@ptrCast(se));
    }

    pub fn allocDirectoryObject(self: *GC, dir: *anyopaque, include_dotfiles: bool) !Value {
        try self.maybeCollect();
        const d = try self.allocator.create(types.DirectoryObject);
        d.* = .{
            .header = .{ .tag = .directory_object },
            .dir = dir,
            .include_dotfiles = include_dotfiles,
        };
        self.finishAlloc(&d.header, @sizeOf(types.DirectoryObject));
        return types.makePointer(@ptrCast(d));
    }

    pub fn allocMultipleValues(self: *GC, values: []const Value) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.dupe(Value, values);
        const mv = try self.allocator.create(MultipleValues);
        mv.* = .{
            .header = .{ .tag = .multiple_values },
            .values = owned,
        };
        self.finishAlloc(&mv.header, @sizeOf(MultipleValues) + values.len * @sizeOf(Value));
        return types.makePointer(@ptrCast(mv));
    }

    // -- Convenience: build a proper list from a slice
    pub fn makeList(self: *GC, items: []const Value) !Value {
        var result: Value = types.NIL;
        self.pushRoot(&result);
        defer self.popRoot();
        var i = items.len;
        while (i > 0) {
            i -= 1;
            result = try self.allocPair(items[i], result);
        }
        return result;
    }

    // -- Deep copy (delegated to gc_deep_copy.zig) --

    const gc_deep_copy = @import("gc_deep_copy.zig");

    pub fn deepCopy(self: *GC, src: Value) !Value {
        return gc_deep_copy.deepCopy(self, src);
    }

    // -- GC (delegated to gc_collect.zig) --

    const gc_collect = @import("gc_collect.zig");

    fn maybeCollect(self: *GC) !void {
        if (self.stress and self.enabled) {
            if (self.no_collect == 0) self.collect();
            if (self.memory_limit) |limit| {
                if (self.bytes_allocated > limit) return error.OutOfMemory;
            }
            return;
        }
        if (self.enabled and self.object_count >= self.gc_threshold) {
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

    pub fn markValue(self: *GC, v: Value) void {
        gc_collect.markValue(self, v);
    }

    pub fn pushRoot(self: *GC, root: *Value) void {
        if (self.root_count >= self.root_buffer.len)
            @panic("GC root stack overflow (1024)");
        self.root_buffer[self.root_count] = root;
        self.root_count += 1;
    }

    pub fn popRoot(self: *GC) void {
        self.root_count -= 1;
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
