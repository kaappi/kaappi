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

fn spinLock(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) std.atomic.spinLoopHint();
}
fn spinUnlock(m: *std.atomic.Mutex) void {
    m.unlock();
}

pub const GC = struct {
    allocator: std.mem.Allocator,
    objects: ?*Object = null,
    old_objects: ?*Object = null,
    object_count: usize = 0,
    gc_threshold: usize = GC_THRESHOLD,
    symbols: std.StringHashMap(Value),
    shared_symbols: ?*std.StringHashMap(Value) = null,
    roots: std.ArrayList(*Value),
    extra_roots: std.ArrayList(Value),
    remembered_set: std.ArrayList(*Object),
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
            .roots = .empty,
            .extra_roots = .empty,
            .remembered_set = .empty,
            .source_lines = std.AutoHashMap(Value, u32).init(allocator),
        };
    }

    pub fn initForThread(allocator: std.mem.Allocator, parent: *GC) GC {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Value).init(allocator),
            .shared_symbols = &parent.symbols,
            .roots = .empty,
            .extra_roots = .empty,
            .remembered_set = .empty,
            .source_lines = std.AutoHashMap(Value, u32).init(allocator),
            .gc_threshold = GC_THRESHOLD,
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
        self.symbols.deinit();
        self.roots.deinit(self.allocator);
        self.extra_roots.deinit(self.allocator);
        self.remembered_set.deinit(self.allocator);
        self.source_lines.deinit();
    }

    pub fn writeBarrier(self: *GC, container: *Object, new_val: Value) void {
        if (container.generation == 1 and types.isPointer(new_val)) {
            const child = types.toObject(new_val);
            if (child.generation == 0) {
                self.remembered_set.append(self.allocator, container) catch {};
            }
        }
    }

    inline fn profileAlloc(self: *GC, size: usize) void {
        if (self.profile_alloc_target) |t| t.* += size;
    }

    pub fn trackObject(self: *GC, obj: *Object) void {
        obj.next = self.objects;
        self.objects = obj;
        self.object_count += 1;
        self.stats.allocs_by_type[@intFromEnum(obj.tag)] += 1;
        if (self.object_count > self.stats.peak_object_count)
            self.stats.peak_object_count = self.object_count;
        if (self.bytes_allocated > self.stats.peak_bytes_allocated)
            self.stats.peak_bytes_allocated = self.bytes_allocated;
    }

    pub fn allocPair(self: *GC, car_val: Value, cdr_val: Value) !Value {
        try self.maybeCollect();
        const pair = try self.allocator.create(Pair);
        pair.* = .{
            .header = .{ .tag = .pair },
            .car = car_val,
            .cdr = cdr_val,
        };
        self.bytes_allocated += @sizeOf(Pair);

        self.profileAlloc(@sizeOf(Pair));
        self.trackObject(&pair.header);
        return types.makePointer(@ptrCast(pair));
    }

    pub fn allocSymbol(self: *GC, name: []const u8) !Value {
        const sym_table = self.shared_symbols orelse &self.symbols;
        const shared = self.shared_symbols != null;

        if (shared) spinLock(&symbol_mutex);
        defer if (shared) spinUnlock(&symbol_mutex);

        if (sym_table.get(name)) |existing| return existing;

        const owned_name = try self.allocator.dupe(u8, name);
        const sym = try self.allocator.create(Symbol);
        sym.* = .{
            .header = .{ .tag = .symbol },
            .name = owned_name,
        };
        self.bytes_allocated += @sizeOf(Symbol) + name.len;
        self.profileAlloc(@sizeOf(Symbol) + name.len);

        if (!shared) self.trackObject(&sym.header);

        const val = types.makePointer(@ptrCast(sym));
        try sym_table.put(owned_name, val);
        return val;
    }

    pub fn allocString(self: *GC, data: []const u8) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
        const str = try self.allocator.create(SchemeString);
        str.* = .{
            .header = .{ .tag = .string },
            .data = owned,
            .len = data.len,
        };
        self.bytes_allocated += @sizeOf(SchemeString) + data.len;

        self.profileAlloc(@sizeOf(SchemeString) + data.len);
        self.trackObject(&str.header);
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
        self.bytes_allocated += @sizeOf(Function);

        self.profileAlloc(@sizeOf(Function));
        self.trackObject(&func.header);
        return func;
    }

    pub fn allocClosure(self: *GC, func: *Function) !Value {
        try self.maybeCollect();
        const upvalue_count = func.upvalue_count;
        const upvalues = try self.allocator.alloc(Value, upvalue_count);
        @memset(upvalues, types.UNDEFINED);

        const cls = try self.allocator.create(Closure);
        cls.* = .{
            .header = .{ .tag = .closure },
            .func = func,
            .upvalues = upvalues,
        };
        self.bytes_allocated += @sizeOf(Closure) + upvalue_count * @sizeOf(Value);

        self.profileAlloc(@sizeOf(Closure) + upvalue_count * @sizeOf(Value));
        self.trackObject(&cls.header);
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
        self.bytes_allocated += @sizeOf(NativeFn);

        self.profileAlloc(@sizeOf(NativeFn));
        self.trackObject(&nf.header);
        return types.makePointer(@ptrCast(nf));
    }

    pub fn allocNativeClosure(self: *GC, fn_ptr: types.NativeClosureFnType, upvalues: []const Value, arity: u8, name: []const u8) !Value {
        try self.maybeCollect();
        const uv_copy = try self.allocator.alloc(Value, upvalues.len);
        @memcpy(uv_copy, upvalues);
        const nc = try self.allocator.create(types.NativeClosure);
        nc.* = .{
            .header = .{ .tag = .native_closure },
            .fn_ptr = fn_ptr,
            .upvalues = uv_copy,
            .arity = arity,
            .name = name,
        };
        self.bytes_allocated += @sizeOf(types.NativeClosure) + upvalues.len * @sizeOf(Value);
        self.profileAlloc(@sizeOf(types.NativeClosure));
        self.trackObject(&nc.header);
        return types.makePointer(@ptrCast(nc));
    }

    pub fn allocFlonum(self: *GC, value: f64) !Value {
        _ = self;
        return types.makeFlonum(value);
    }

    pub fn allocVector(self: *GC, data: []const Value) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.alloc(Value, data.len);
        @memcpy(owned, data);
        const vec = try self.allocator.create(Vector);
        vec.* = .{
            .header = .{ .tag = .vector },
            .data = owned,
        };
        self.bytes_allocated += @sizeOf(Vector) + data.len * @sizeOf(Value);

        self.profileAlloc(@sizeOf(Vector) + data.len * @sizeOf(Value));
        self.trackObject(&vec.header);
        return types.makePointer(@ptrCast(vec));
    }

    pub fn allocVectorFill(self: *GC, size: usize, fill: Value) !Value {
        try self.maybeCollect();
        const data = try self.allocator.alloc(Value, size);
        @memset(data, fill);
        const vec = try self.allocator.create(Vector);
        vec.* = .{
            .header = .{ .tag = .vector },
            .data = data,
        };
        self.bytes_allocated += @sizeOf(Vector) + size * @sizeOf(Value);

        self.profileAlloc(@sizeOf(Vector) + size * @sizeOf(Value));
        self.trackObject(&vec.header);
        return types.makePointer(@ptrCast(vec));
    }

    pub fn allocErrorObject(self: *GC, message: Value, irritants: Value) !Value {
        try self.maybeCollect();
        const err = try self.allocator.create(types.ErrorObject);
        err.* = .{
            .header = .{ .tag = .error_object },
            .message = message,
            .irritants = irritants,
        };
        self.bytes_allocated += @sizeOf(types.ErrorObject);

        self.profileAlloc(@sizeOf(types.ErrorObject));
        self.trackObject(&err.header);
        return types.makePointer(@ptrCast(err));
    }

    pub fn allocTransformer(self: *GC, literals: []const Value, patterns: []const Value, templates: []const Value) !Value {
        const num_rules: u16 = @intCast(patterns.len);
        const owned_lits = try self.allocator.dupe(Value, literals);
        const owned_pats = try self.allocator.dupe(Value, patterns);
        const owned_tmps = try self.allocator.dupe(Value, templates);

        const tx = try self.allocator.create(Transformer);
        tx.* = .{
            .header = .{ .tag = .transformer },
            .literals = owned_lits,
            .patterns = owned_pats,
            .templates = owned_tmps,
            .num_rules = num_rules,
        };
        self.bytes_allocated += @sizeOf(Transformer) + (literals.len + patterns.len + templates.len) * @sizeOf(Value);

        self.profileAlloc(@sizeOf(Transformer) + (literals.len + patterns.len + templates.len) * @sizeOf(Value));
        self.trackObject(&tx.header);
        return types.makePointer(@ptrCast(tx));
    }

    pub fn allocRecordType(self: *GC, name: []const u8, num_fields: u8) !Value {
        try self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        const rt = try self.allocator.create(RecordType);
        rt.* = .{
            .header = .{ .tag = .record_type },
            .name = owned_name,
            .num_fields = num_fields,
        };
        self.bytes_allocated += @sizeOf(RecordType) + name.len;

        self.profileAlloc(@sizeOf(RecordType) + name.len);
        self.trackObject(&rt.header);
        return types.makePointer(@ptrCast(rt));
    }

    pub fn allocRecordInstance(self: *GC, record_type: *RecordType, field_values: []const Value) !Value {
        try self.maybeCollect();
        const fields = try self.allocator.alloc(Value, record_type.num_fields);
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
        self.bytes_allocated += @sizeOf(RecordInstance) + record_type.num_fields * @sizeOf(Value);

        self.profileAlloc(@sizeOf(RecordInstance) + record_type.num_fields * @sizeOf(Value));
        self.trackObject(&ri.header);
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
        self.bytes_allocated += @sizeOf(Port);

        self.profileAlloc(@sizeOf(Port));
        self.trackObject(&port.header);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocStringInputPort(self: *GC, data: []const u8) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
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
        self.bytes_allocated += @sizeOf(Port) + data.len;

        self.profileAlloc(@sizeOf(Port) + data.len);
        self.trackObject(&port.header);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocStringOutputPort(self: *GC) !Value {
        try self.maybeCollect();
        const initial_cap: usize = 64;
        const buf = try self.allocator.alloc(u8, initial_cap);
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
        self.bytes_allocated += @sizeOf(Port) + initial_cap;

        self.profileAlloc(@sizeOf(Port) + initial_cap);
        self.trackObject(&port.header);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocBytevector(self: *GC, data: []const u8) !Value {
        try self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
        const bv = try self.allocator.create(Bytevector);
        bv.* = .{
            .header = .{ .tag = .bytevector },
            .data = owned,
        };
        self.bytes_allocated += @sizeOf(Bytevector) + data.len;

        self.profileAlloc(@sizeOf(Bytevector) + data.len);
        self.trackObject(&bv.header);
        return types.makePointer(@ptrCast(bv));
    }

    pub fn allocBytevectorFill(self: *GC, size: usize, fill: u8) !Value {
        try self.maybeCollect();
        const data = try self.allocator.alloc(u8, size);
        @memset(data, fill);
        const bv = try self.allocator.create(Bytevector);
        bv.* = .{
            .header = .{ .tag = .bytevector },
            .data = data,
        };
        self.bytes_allocated += @sizeOf(Bytevector) + size;

        self.profileAlloc(@sizeOf(Bytevector) + size);
        self.trackObject(&bv.header);
        return types.makePointer(@ptrCast(bv));
    }

    pub fn allocPromise(self: *GC, forced: bool, value: Value) !Value {
        try self.maybeCollect();
        const p = try self.allocator.create(Promise);
        p.* = .{
            .header = .{ .tag = .promise },
            .forced = forced,
            .value = value,
        };
        self.bytes_allocated += @sizeOf(Promise);

        self.profileAlloc(@sizeOf(Promise));
        self.trackObject(&p.header);
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
        dst_base: u16,
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
        self.bytes_allocated += @sizeOf(Continuation) +
            registers.len * @sizeOf(Value) +
            frames.len * @sizeOf(SavedFrame) +
            handlers.len * @sizeOf(SavedHandler) +
            wind_records.len * @sizeOf(WindRecord);
        self.trackObject(&cont.header);
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
        dst_base: u16,
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
        self.bytes_allocated += @sizeOf(Continuation);

        self.profileAlloc(@sizeOf(Continuation));
        self.trackObject(&cont.header);
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
        self.bytes_allocated += @sizeOf(types.Complex);

        self.profileAlloc(@sizeOf(types.Complex));
        self.trackObject(&c.header);
        return types.makePointer(@ptrCast(c));
    }

    pub fn allocParameter(self: *GC, init_value: Value, converter: Value) !Value {
        try self.maybeCollect();
        const p = try self.allocator.create(types.ParameterObject);
        p.* = .{
            .header = .{ .tag = .parameter },
            .value = init_value,
            .converter = converter,
        };
        self.bytes_allocated += @sizeOf(types.ParameterObject);

        self.profileAlloc(@sizeOf(types.ParameterObject));
        self.trackObject(&p.header);
        return types.makePointer(@ptrCast(p));
    }

    pub fn allocFfiLibrary(self: *GC, handle: ?*anyopaque, name: []const u8) !Value {
        try self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        const lib = try self.allocator.create(FfiLibrary);
        lib.* = .{
            .header = .{ .tag = .ffi_library },
            .handle = handle,
            .name = owned_name,
        };
        self.bytes_allocated += @sizeOf(FfiLibrary) + name.len;

        self.profileAlloc(@sizeOf(FfiLibrary) + name.len);
        self.trackObject(&lib.header);
        return types.makePointer(@ptrCast(lib));
    }

    pub fn allocFfiFunction(self: *GC, symbol: *anyopaque, library: Value, name: []const u8, param_types: []const FfiType, return_type: FfiType) !Value {
        try self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_params = try self.allocator.dupe(FfiType, param_types);
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
        self.bytes_allocated += @sizeOf(FfiFunction) + name.len + param_types.len * @sizeOf(FfiType);

        self.profileAlloc(@sizeOf(FfiFunction) + name.len + param_types.len * @sizeOf(FfiType));
        self.trackObject(&ffi_fn.header);
        return types.makePointer(@ptrCast(ffi_fn));
    }

    pub fn allocFfiCallback(self: *GC, closure: Value, slot_index: u8, fn_ptr: *anyopaque) !Value {
        try self.maybeCollect();
        const cb = try self.allocator.create(FfiCallback);
        cb.* = .{
            .header = .{ .tag = .ffi_callback },
            .closure = closure,
            .slot_index = slot_index,
            .fn_ptr = fn_ptr,
            .active = true,
        };
        self.bytes_allocated += @sizeOf(FfiCallback);

        self.profileAlloc(@sizeOf(FfiCallback));
        self.trackObject(&cb.header);
        return types.makePointer(@ptrCast(cb));
    }

    pub fn allocRandomSource(self: *GC, seed: u64) !Value {
        try self.maybeCollect();
        const rs = try self.allocator.create(RandomSource);
        rs.* = .{
            .header = .{ .tag = .random_source },
            .prng = std.Random.DefaultPrng.init(seed),
        };
        self.bytes_allocated += @sizeOf(RandomSource);

        self.profileAlloc(@sizeOf(RandomSource));
        self.trackObject(&rs.header);
        return types.makePointer(@ptrCast(rs));
    }

    pub fn allocFiber(self: *GC, thunk: Value, id: u32) !*@import("fiber.zig").Fiber {
        try self.maybeCollect();
        const fiber_mod = @import("fiber.zig");
        const fiber = try self.allocator.create(fiber_mod.Fiber);
        fiber.* = .{
            .header = .{ .tag = .fiber },
            .registers = undefined,
            .frames = undefined,
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
        @memset(&fiber.registers, types.UNDEFINED);
        self.bytes_allocated += @sizeOf(fiber_mod.Fiber);

        self.profileAlloc(@sizeOf(fiber_mod.Fiber));
        self.trackObject(&fiber.header);
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
        self.bytes_allocated += @sizeOf(types.Channel);

        self.profileAlloc(@sizeOf(types.Channel));
        self.trackObject(&ch.header);
        return types.makePointer(@ptrCast(ch));
    }

    pub fn allocMutex(self: *GC, name: Value) !Value {
        try self.maybeCollect();
        const m = try self.allocator.create(types.Mutex);
        m.* = .{
            .header = .{ .tag = .mutex },
            .name = name,
            .owner = types.VOID,
            .locked = false,
            .abandoned = false,
            .specific = types.VOID,
        };
        self.bytes_allocated += @sizeOf(types.Mutex);

        self.profileAlloc(@sizeOf(types.Mutex));
        self.trackObject(&m.header);
        return types.makePointer(@ptrCast(m));
    }

    pub fn allocConditionVariable(self: *GC, name: Value) !Value {
        try self.maybeCollect();
        const cv = try self.allocator.create(types.ConditionVariable);
        cv.* = .{
            .header = .{ .tag = .condition_variable },
            .name = name,
            .specific = types.VOID,
        };
        self.bytes_allocated += @sizeOf(types.ConditionVariable);

        self.profileAlloc(@sizeOf(types.ConditionVariable));
        self.trackObject(&cv.header);
        return types.makePointer(@ptrCast(cv));
    }

    pub fn allocSrfi18Time(self: *GC, seconds: f64) !Value {
        try self.maybeCollect();
        const t = try self.allocator.create(types.Srfi18Time);
        t.* = .{
            .header = .{ .tag = .srfi18_time },
            .seconds = seconds,
        };
        self.bytes_allocated += @sizeOf(types.Srfi18Time);

        self.profileAlloc(@sizeOf(types.Srfi18Time));
        self.trackObject(&t.header);
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
        // Initialize all entries as empty (key=VOID sentinel)
        for (entries) |*e| {
            e.key = types.VOID;
            e.value = types.VOID;
        }
        const ht = try self.allocator.create(HashTable);
        ht.* = .{
            .header = .{ .tag = .hash_table },
            .entries = entries,
            .count = 0,
            .capacity = cap,
        };
        self.bytes_allocated += @sizeOf(HashTable) + cap * @sizeOf(HashEntry);

        self.profileAlloc(@sizeOf(HashTable) + initial_capacity * @sizeOf(HashEntry));
        self.trackObject(&ht.header);
        return types.makePointer(@ptrCast(ht));
    }

    pub fn allocBignumFromI64(self: *GC, n: i64) !Value {
        try self.maybeCollect();
        const bn = try self.allocator.create(Bignum);
        const limbs = try self.allocator.alloc(u64, 1);
        const mag: u64 = if (n < 0) @intCast(-@as(i128, n)) else @intCast(n);
        limbs[0] = mag;
        bn.* = .{
            .header = .{ .tag = .bignum },
            .limbs = limbs,
            .len = if (mag == 0) 0 else 1,
            .positive = n >= 0,
        };
        self.bytes_allocated += @sizeOf(Bignum) + @sizeOf(u64);

        self.profileAlloc(@sizeOf(Bignum) + @sizeOf(u64));
        self.trackObject(&bn.header);
        return types.makePointer(@ptrCast(bn));
    }

    pub fn allocBignumFromLimbs(self: *GC, limbs: []const u64, len: usize, positive: bool) !Value {
        try self.maybeCollect();
        const bn = try self.allocator.create(Bignum);
        const owned = try self.allocator.alloc(u64, limbs.len);
        @memcpy(owned, limbs);
        bn.* = .{
            .header = .{ .tag = .bignum },
            .limbs = owned,
            .len = len,
            .positive = positive,
        };
        self.bytes_allocated += @sizeOf(Bignum) + limbs.len * @sizeOf(u64);

        self.profileAlloc(@sizeOf(Bignum) + limbs.len * @sizeOf(u64));
        self.trackObject(&bn.header);
        return types.makePointer(@ptrCast(bn));
    }

    pub fn allocRational(self: *GC, num: Value, den: Value) !Value {
        try self.maybeCollect();
        const rat = try self.allocator.create(Rational);
        rat.* = .{
            .header = .{ .tag = .rational },
            .numerator = num,
            .denominator = den,
        };
        self.bytes_allocated += @sizeOf(Rational);

        self.profileAlloc(@sizeOf(Rational));
        self.trackObject(&rat.header);
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
        self.bytes_allocated += @sizeOf(types.FileInfo);

        self.profileAlloc(@sizeOf(types.FileInfo));
        self.trackObject(&fi.header);
        return types.makePointer(@ptrCast(fi));
    }

    pub fn allocUserInfo(self: *GC, name: []const u8, uid: u32, gid: u32, home_dir: []const u8, shell: []const u8, full_name: []const u8) !Value {
        try self.maybeCollect();
        const name_copy = try self.allocator.dupe(u8, name);
        const home_copy = try self.allocator.dupe(u8, home_dir);
        const shell_copy = try self.allocator.dupe(u8, shell);
        const gecos_copy = try self.allocator.dupe(u8, full_name);
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
        self.bytes_allocated += @sizeOf(types.UserInfo) + name.len + home_dir.len + shell.len + full_name.len;

        self.profileAlloc(@sizeOf(types.UserInfo) + name.len + home_dir.len + shell.len + full_name.len);
        self.trackObject(&ui.header);
        return types.makePointer(@ptrCast(ui));
    }

    pub fn allocGroupInfo(self: *GC, name: []const u8, gid: u32) !Value {
        try self.maybeCollect();
        const name_copy = try self.allocator.dupe(u8, name);
        const gi = try self.allocator.create(types.GroupInfo);
        gi.* = .{
            .header = .{ .tag = .group_info },
            .name = name_copy,
            .gid = gid,
        };
        self.bytes_allocated += @sizeOf(types.GroupInfo) + name.len;

        self.profileAlloc(@sizeOf(types.GroupInfo) + name.len);
        self.trackObject(&gi.header);
        return types.makePointer(@ptrCast(gi));
    }

    pub fn allocDirectoryObject(self: *GC, dir: *anyopaque, include_dotfiles: bool) !Value {
        try self.maybeCollect();
        const d = try self.allocator.create(types.DirectoryObject);
        d.* = .{
            .header = .{ .tag = .directory_object },
            .dir = dir,
            .include_dotfiles = include_dotfiles,
        };
        self.bytes_allocated += @sizeOf(types.DirectoryObject);

        self.profileAlloc(@sizeOf(types.DirectoryObject));
        self.trackObject(&d.header);
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
        self.bytes_allocated += @sizeOf(MultipleValues) + values.len * @sizeOf(Value);

        self.profileAlloc(@sizeOf(MultipleValues) + values.len * @sizeOf(Value));
        self.trackObject(&mv.header);
        return types.makePointer(@ptrCast(mv));
    }

    // -- Convenience: build a proper list from a slice
    pub fn makeList(self: *GC, items: []const Value) !Value {
        var result: Value = types.NIL;
        try self.pushRoot(&result);
        defer self.popRoot();
        var i = items.len;
        while (i > 0) {
            i -= 1;
            result = try self.allocPair(items[i], result);
        }
        return result;
    }

    // -- Deep copy (cross-thread value transfer) --

    pub fn deepCopy(self: *GC, src: Value) !Value {
        if (!types.isPointer(src)) return src;
        var visited = std.AutoHashMap(usize, Value).init(self.allocator);
        defer visited.deinit();
        return self.deepCopyValue(src, &visited);
    }

    fn deepCopyValue(self: *GC, src: Value, visited: *std.AutoHashMap(usize, Value)) !Value {
        if (!types.isPointer(src)) return src;

        const src_ptr = @intFromPtr(types.toObject(src));
        if (visited.get(src_ptr)) |already| return already;

        self.no_collect += 1;
        defer self.no_collect -= 1;

        const obj = types.toObject(src);
        return switch (obj.tag) {
            .pair => {
                const pair = obj.as(types.Pair);
                const new_val = try self.allocPair(types.NIL, types.NIL);
                try visited.put(src_ptr, new_val);
                const new_pair = types.toObject(new_val).as(types.Pair);
                new_pair.car = try self.deepCopyValue(pair.car, visited);
                new_pair.cdr = try self.deepCopyValue(pair.cdr, visited);
                return new_val;
            },
            .symbol => try self.allocSymbol(obj.as(types.Symbol).name),
            .string => {
                const s = obj.as(types.SchemeString);
                return try self.allocString(s.data[0..s.len]);
            },
            .vector => {
                const vec = obj.as(types.Vector);
                const new_val = try self.allocVectorFill(vec.data.len, types.VOID);
                try visited.put(src_ptr, new_val);
                const new_vec = types.toObject(new_val).as(types.Vector);
                for (vec.data, 0..) |elem, i| {
                    new_vec.data[i] = try self.deepCopyValue(elem, visited);
                }
                return new_val;
            },
            .bytevector => try self.allocBytevector(obj.as(types.Bytevector).data),
            .flonum => try self.allocFlonum(obj.as(types.Flonum).value),
            .complex => {
                const c = obj.as(types.Complex);
                return try self.allocComplexEx(c.real, c.imag, c.exact_real, c.exact_imag);
            },
            .bignum => {
                const bn = obj.as(types.Bignum);
                return try self.allocBignumFromLimbs(bn.limbs[0..bn.len], bn.len, bn.positive);
            },
            .rational => {
                const r = obj.as(types.Rational);
                const num = try self.deepCopyValue(r.numerator, visited);
                const den = try self.deepCopyValue(r.denominator, visited);
                return try self.allocRational(num, den);
            },
            .closure => {
                const cl = obj.as(types.Closure);
                const func_val = types.makePointer(@ptrCast(cl.func));
                const new_func_val = try self.deepCopyValue(func_val, visited);
                const new_func = types.toObject(new_func_val).as(types.Function);
                const new_val = try self.allocClosure(new_func);
                try visited.put(src_ptr, new_val);
                const new_cl = types.toObject(new_val).as(types.Closure);
                for (cl.upvalues, 0..) |uv, i| {
                    new_cl.upvalues[i] = try self.deepCopyValue(uv, visited);
                }
                return new_val;
            },
            .function => {
                const func = obj.as(types.Function);
                const new_func = try self.allocFunction();
                const new_val = types.makePointer(@ptrCast(new_func));
                try visited.put(src_ptr, new_val);
                new_func.arity = func.arity;
                new_func.locals_count = func.locals_count;
                new_func.upvalue_count = func.upvalue_count;
                new_func.is_variadic = func.is_variadic;
                new_func.source_line = func.source_line;
                new_func.source_name = func.source_name;
                new_func.global_cache = null;
                new_func.env = null;
                if (func.name) |name| {
                    if (func.owns_name) {
                        const dup = try self.allocator.alloc(u8, name.len);
                        @memcpy(dup, name);
                        new_func.name = dup;
                        new_func.owns_name = true;
                    } else {
                        new_func.name = name;
                    }
                }
                new_func.code.appendSlice(self.allocator, func.code.items) catch return error.OutOfMemory;
                for (func.constants.items) |c| {
                    const nc = try self.deepCopyValue(c, visited);
                    new_func.constants.append(self.allocator, nc) catch return error.OutOfMemory;
                }
                if (func.debug_locals.len > 0) {
                    const dl = try self.allocator.alloc(types.DebugLocal, func.debug_locals.len);
                    @memcpy(dl, func.debug_locals);
                    new_func.debug_locals = dl;
                }
                for (func.line_table.items) |entry| {
                    new_func.line_table.append(self.allocator, entry) catch {};
                }
                return new_val;
            },
            .hash_table => {
                const ht = obj.as(types.HashTable);
                const new_val = try self.allocHashTable(ht.capacity);
                try visited.put(src_ptr, new_val);
                const new_ht = types.toObject(new_val).as(types.HashTable);
                for (ht.entries[0..ht.capacity]) |entry| {
                    if (entry.key != types.VOID and entry.key != types.EOF) {
                        const nk = try self.deepCopyValue(entry.key, visited);
                        const nv = try self.deepCopyValue(entry.value, visited);
                        const hash = std.hash.Wyhash.hash(0, std.mem.asBytes(&nk));
                        var idx = hash & (new_ht.capacity - 1);
                        while (new_ht.entries[idx].key != types.VOID) {
                            idx = (idx + 1) & (new_ht.capacity - 1);
                        }
                        new_ht.entries[idx] = .{ .key = nk, .value = nv };
                        new_ht.count += 1;
                    }
                }
                return new_val;
            },
            .promise => {
                const p = obj.as(types.Promise);
                const nv = try self.deepCopyValue(p.value, visited);
                return try self.allocPromise(p.forced, nv);
            },
            .parameter => {
                const p = obj.as(types.ParameterObject);
                const val = try self.deepCopyValue(p.value, visited);
                const conv = try self.deepCopyValue(p.converter, visited);
                return try self.allocParameter(val, conv);
            },
            .error_object => {
                const e = obj.as(types.ErrorObject);
                const msg = try self.deepCopyValue(e.message, visited);
                const irr = try self.deepCopyValue(e.irritants, visited);
                const new_val = try self.allocErrorObject(msg, irr);
                const new_e = types.toObject(new_val).as(types.ErrorObject);
                new_e.error_type = e.error_type;
                new_e.uncaught_reason = try self.deepCopyValue(e.uncaught_reason, visited);
                return new_val;
            },
            .record_type => {
                const rt = obj.as(types.RecordType);
                const new_val = try self.allocRecordType(rt.name, rt.num_fields);
                try visited.put(src_ptr, new_val);
                return new_val;
            },
            .record_instance => {
                const ri = obj.as(types.RecordInstance);
                const rt_val = types.makePointer(@ptrCast(ri.record_type));
                const new_rt_val = try self.deepCopyValue(rt_val, visited);
                const new_rt = types.toObject(new_rt_val).as(types.RecordType);
                const tmp_fields = try self.allocator.alloc(Value, ri.fields.len);
                defer self.allocator.free(tmp_fields);
                for (ri.fields, 0..) |f, i| {
                    tmp_fields[i] = try self.deepCopyValue(f, visited);
                }
                return try self.allocRecordInstance(new_rt, tmp_fields);
            },
            .multiple_values => {
                const mv = obj.as(types.MultipleValues);
                const vals = try self.allocator.alloc(Value, mv.values.len);
                for (mv.values, 0..) |v, i| {
                    vals[i] = try self.deepCopyValue(v, visited);
                }
                const new_mv = try self.allocator.create(types.MultipleValues);
                new_mv.* = .{ .header = .{ .tag = .multiple_values }, .values = vals };
                self.trackObject(&new_mv.header);
                return types.makePointer(@ptrCast(new_mv));
            },
            .transformer => {
                const t = obj.as(types.Transformer);
                const tmp_lits = try self.allocator.alloc(Value, t.literals.len);
                defer self.allocator.free(tmp_lits);
                for (t.literals, 0..) |v, i| tmp_lits[i] = try self.deepCopyValue(v, visited);
                const tmp_pats = try self.allocator.alloc(Value, t.patterns.len);
                defer self.allocator.free(tmp_pats);
                for (t.patterns, 0..) |v, i| tmp_pats[i] = try self.deepCopyValue(v, visited);
                const tmp_tmpls = try self.allocator.alloc(Value, t.templates.len);
                defer self.allocator.free(tmp_tmpls);
                for (t.templates, 0..) |v, i| tmp_tmpls[i] = try self.deepCopyValue(v, visited);
                const new_val = try self.allocTransformer(tmp_lits, tmp_pats, tmp_tmpls);
                try visited.put(src_ptr, new_val);
                return new_val;
            },
            .native_fn, .native_closure, .ffi_library, .ffi_function => src,
            .srfi18_time => try self.allocSrfi18Time(obj.as(types.Srfi18Time).seconds),
            .random_source => {
                const rs = obj.as(types.RandomSource);
                const new_val = try self.allocRandomSource(0);
                const new_rs = types.toObject(new_val).as(types.RandomSource);
                new_rs.prng = rs.prng;
                return new_val;
            },
            .port,
            .continuation,
            .fiber,
            .channel,
            .mutex,
            .condition_variable,
            .ffi_callback,
            .file_info,
            .user_info,
            .group_info,
            .directory_object,
            => return error.UncopyableType,
        };
    }

    // -- GC (delegated to gc_collect.zig) --

    const gc_collect = @import("gc_collect.zig");

    fn maybeCollect(self: *GC) !void {
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

    pub fn pushRoot(self: *GC, root: *Value) !void {
        try self.roots.append(self.allocator, root);
    }

    pub fn popRoot(self: *GC) void {
        _ = self.roots.pop();
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
    try gc.pushRoot(&rooted);

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
