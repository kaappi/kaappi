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
const FfiType = types.FfiType;
const HashTable = types.HashTable;
const HashEntry = types.HashEntry;

const GC_THRESHOLD: usize = 1024;

pub const GC = struct {
    allocator: std.mem.Allocator,
    objects: ?*Object = null,
    object_count: usize = 0,
    gc_threshold: usize = GC_THRESHOLD,
    symbols: std.StringHashMap(Value),
    roots: std.ArrayList(*Value),
    extra_roots: std.ArrayList(Value),
    enabled: bool = true,
    bytes_allocated: usize = 0,
    // Optional callback to mark roots held outside the GC's own root lists —
    // notably the VM's live register file and call frames. Set by the VM so a
    // collection triggered mid-execution does not free in-flight objects.
    root_marker: ?*const fn (*GC) void = null,

    pub fn init(allocator: std.mem.Allocator) GC {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Value).init(allocator),
            .roots = .empty,
            .extra_roots = .empty,
        };
    }

    pub fn deinit(self: *GC) void {
        var obj = self.objects;
        while (obj) |o| {
            const next = o.next;
            self.freeObject(o);
            obj = next;
        }
        self.symbols.deinit();
        self.roots.deinit(self.allocator);
        self.extra_roots.deinit(self.allocator);
    }

    fn trackObject(self: *GC, obj: *Object) void {
        obj.next = self.objects;
        self.objects = obj;
        self.object_count += 1;
    }

    pub fn allocPair(self: *GC, car_val: Value, cdr_val: Value) !Value {
        self.maybeCollect();
        const pair = try self.allocator.create(Pair);
        pair.* = .{
            .header = .{ .tag = .pair },
            .car = car_val,
            .cdr = cdr_val,
        };
        self.bytes_allocated += @sizeOf(Pair);
        self.trackObject(&pair.header);
        return types.makePointer(@ptrCast(pair));
    }

    pub fn allocSymbol(self: *GC, name: []const u8) !Value {
        if (self.symbols.get(name)) |existing| return existing;

        const owned_name = try self.allocator.dupe(u8, name);
        const sym = try self.allocator.create(Symbol);
        sym.* = .{
            .header = .{ .tag = .symbol },
            .name = owned_name,
        };
        self.bytes_allocated += @sizeOf(Symbol) + name.len;
        self.trackObject(&sym.header);
        const val = types.makePointer(@ptrCast(sym));
        try self.symbols.put(owned_name, val);
        return val;
    }

    pub fn allocString(self: *GC, data: []const u8) !Value {
        self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
        const str = try self.allocator.create(SchemeString);
        str.* = .{
            .header = .{ .tag = .string },
            .data = owned,
            .len = data.len,
        };
        self.bytes_allocated += @sizeOf(SchemeString) + data.len;
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
        self.trackObject(&func.header);
        return func;
    }

    pub fn allocClosure(self: *GC, func: *Function) !Value {
        self.maybeCollect();
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
        self.trackObject(&nf.header);
        return types.makePointer(@ptrCast(nf));
    }

    pub fn allocFlonum(self: *GC, value: f64) !Value {
        self.maybeCollect();
        const flo = try self.allocator.create(Flonum);
        flo.* = .{
            .header = .{ .tag = .flonum },
            .value = value,
        };
        self.bytes_allocated += @sizeOf(Flonum);
        self.trackObject(&flo.header);
        return types.makePointer(@ptrCast(flo));
    }

    pub fn allocVector(self: *GC, data: []const Value) !Value {
        self.maybeCollect();
        const owned = try self.allocator.alloc(Value, data.len);
        @memcpy(owned, data);
        const vec = try self.allocator.create(Vector);
        vec.* = .{
            .header = .{ .tag = .vector },
            .data = owned,
        };
        self.bytes_allocated += @sizeOf(Vector) + data.len * @sizeOf(Value);
        self.trackObject(&vec.header);
        return types.makePointer(@ptrCast(vec));
    }

    pub fn allocVectorFill(self: *GC, size: usize, fill: Value) !Value {
        self.maybeCollect();
        const data = try self.allocator.alloc(Value, size);
        @memset(data, fill);
        const vec = try self.allocator.create(Vector);
        vec.* = .{
            .header = .{ .tag = .vector },
            .data = data,
        };
        self.bytes_allocated += @sizeOf(Vector) + size * @sizeOf(Value);
        self.trackObject(&vec.header);
        return types.makePointer(@ptrCast(vec));
    }

    pub fn allocErrorObject(self: *GC, message: Value, irritants: Value) !Value {
        self.maybeCollect();
        const err = try self.allocator.create(types.ErrorObject);
        err.* = .{
            .header = .{ .tag = .error_object },
            .message = message,
            .irritants = irritants,
        };
        self.bytes_allocated += @sizeOf(types.ErrorObject);
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
        self.trackObject(&tx.header);
        return types.makePointer(@ptrCast(tx));
    }

    pub fn allocRecordType(self: *GC, name: []const u8, num_fields: u8) !Value {
        self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        const rt = try self.allocator.create(RecordType);
        rt.* = .{
            .header = .{ .tag = .record_type },
            .name = owned_name,
            .num_fields = num_fields,
        };
        self.bytes_allocated += @sizeOf(RecordType) + name.len;
        self.trackObject(&rt.header);
        return types.makePointer(@ptrCast(rt));
    }

    pub fn allocRecordInstance(self: *GC, record_type: *RecordType, field_values: []const Value) !Value {
        self.maybeCollect();
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
        self.trackObject(&ri.header);
        return types.makePointer(@ptrCast(ri));
    }

    pub fn allocPort(self: *GC, fd: std.posix.fd_t, is_input: bool, is_output: bool, name: []const u8, owns_name: bool) !Value {
        self.maybeCollect();
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
        };
        self.bytes_allocated += @sizeOf(Port);
        self.trackObject(&port.header);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocStringInputPort(self: *GC, data: []const u8) !Value {
        self.maybeCollect();
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
        self.trackObject(&port.header);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocStringOutputPort(self: *GC) !Value {
        self.maybeCollect();
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
        self.trackObject(&port.header);
        return types.makePointer(@ptrCast(port));
    }

    pub fn allocBytevector(self: *GC, data: []const u8) !Value {
        self.maybeCollect();
        const owned = try self.allocator.dupe(u8, data);
        const bv = try self.allocator.create(Bytevector);
        bv.* = .{
            .header = .{ .tag = .bytevector },
            .data = owned,
        };
        self.bytes_allocated += @sizeOf(Bytevector) + data.len;
        self.trackObject(&bv.header);
        return types.makePointer(@ptrCast(bv));
    }

    pub fn allocBytevectorFill(self: *GC, size: usize, fill: u8) !Value {
        self.maybeCollect();
        const data = try self.allocator.alloc(u8, size);
        @memset(data, fill);
        const bv = try self.allocator.create(Bytevector);
        bv.* = .{
            .header = .{ .tag = .bytevector },
            .data = data,
        };
        self.bytes_allocated += @sizeOf(Bytevector) + size;
        self.trackObject(&bv.header);
        return types.makePointer(@ptrCast(bv));
    }

    pub fn allocPromise(self: *GC, forced: bool, value: Value) !Value {
        self.maybeCollect();
        const p = try self.allocator.create(Promise);
        p.* = .{
            .header = .{ .tag = .promise },
            .forced = forced,
            .value = value,
        };
        self.bytes_allocated += @sizeOf(Promise);
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
        dst_reg: u8,
        dst_base: u16,
    ) !Value {
        self.maybeCollect();

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
        dst_reg: u8,
        dst_base: u16,
    ) !Value {
        self.maybeCollect();
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
        self.trackObject(&cont.header);
        return types.makePointer(@ptrCast(cont));
    }

    pub fn allocComplex(self: *GC, real: f64, imag: f64) !Value {
        self.maybeCollect();
        const c = try self.allocator.create(types.Complex);
        c.* = .{
            .header = .{ .tag = .complex },
            .real = real,
            .imag = imag,
        };
        self.bytes_allocated += @sizeOf(types.Complex);
        self.trackObject(&c.header);
        return types.makePointer(@ptrCast(c));
    }

    pub fn allocParameter(self: *GC, init_value: Value, converter: Value) !Value {
        self.maybeCollect();
        const p = try self.allocator.create(types.ParameterObject);
        p.* = .{
            .header = .{ .tag = .parameter },
            .value = init_value,
            .converter = converter,
        };
        self.bytes_allocated += @sizeOf(types.ParameterObject);
        self.trackObject(&p.header);
        return types.makePointer(@ptrCast(p));
    }

    pub fn allocFfiLibrary(self: *GC, handle: ?*anyopaque, name: []const u8) !Value {
        self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        const lib = try self.allocator.create(FfiLibrary);
        lib.* = .{
            .header = .{ .tag = .ffi_library },
            .handle = handle,
            .name = owned_name,
        };
        self.bytes_allocated += @sizeOf(FfiLibrary) + name.len;
        self.trackObject(&lib.header);
        return types.makePointer(@ptrCast(lib));
    }

    pub fn allocFfiFunction(self: *GC, symbol: *anyopaque, name: []const u8, param_types: []const FfiType, return_type: FfiType) !Value {
        self.maybeCollect();
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_params = try self.allocator.dupe(FfiType, param_types);
        const ffi_fn = try self.allocator.create(FfiFunction);
        ffi_fn.* = .{
            .header = .{ .tag = .ffi_function },
            .symbol = symbol,
            .name = owned_name,
            .param_types = owned_params,
            .return_type = return_type,
            .param_count = @intCast(param_types.len),
        };
        self.bytes_allocated += @sizeOf(FfiFunction) + name.len + param_types.len * @sizeOf(FfiType);
        self.trackObject(&ffi_fn.header);
        return types.makePointer(@ptrCast(ffi_fn));
    }

    pub fn allocHashTable(self: *GC, initial_capacity: usize) !Value {
        self.maybeCollect();
        const entries = try self.allocator.alloc(HashEntry, initial_capacity);
        // No need to initialize; count starts at 0 so entries[0..0] is empty
        const ht = try self.allocator.create(HashTable);
        ht.* = .{
            .header = .{ .tag = .hash_table },
            .entries = entries,
            .count = 0,
            .capacity = initial_capacity,
        };
        self.bytes_allocated += @sizeOf(HashTable) + initial_capacity * @sizeOf(HashEntry);
        self.trackObject(&ht.header);
        return types.makePointer(@ptrCast(ht));
    }

    pub fn allocMultipleValues(self: *GC, values: []const Value) !Value {
        self.maybeCollect();
        const owned = try self.allocator.dupe(Value, values);
        const mv = try self.allocator.create(MultipleValues);
        mv.* = .{
            .header = .{ .tag = .multiple_values },
            .values = owned,
        };
        self.bytes_allocated += @sizeOf(MultipleValues) + values.len * @sizeOf(Value);
        self.trackObject(&mv.header);
        return types.makePointer(@ptrCast(mv));
    }

    // -- Convenience: build a proper list from a slice
    pub fn makeList(self: *GC, items: []const Value) !Value {
        var result: Value = types.NIL;
        var i = items.len;
        while (i > 0) {
            i -= 1;
            result = try self.allocPair(items[i], result);
        }
        return result;
    }

    // -- GC --

    fn maybeCollect(self: *GC) void {
        if (self.enabled and self.object_count >= self.gc_threshold) {
            self.collect();
        }
    }

    pub fn collect(self: *GC) void {
        self.markRoots();
        self.sweep();
        self.gc_threshold = @max(GC_THRESHOLD, self.object_count * 2);
    }

    fn markRoots(self: *GC) void {
        for (self.roots.items) |root| {
            self.markValue(root.*);
        }
        for (self.extra_roots.items) |v| {
            self.markValue(v);
        }
        // Mark interned symbols
        var it = self.symbols.valueIterator();
        while (it.next()) |v| {
            self.markValue(v.*);
        }
        // Mark VM-owned roots (live registers, call frames, handlers, winds).
        if (self.root_marker) |mark| mark(self);
    }

    pub fn markValue(self: *GC, v: Value) void {
        if (!types.isPointer(v)) return;
        const obj = types.toObject(v);
        if (obj.marked) return;
        obj.marked = true;

        switch (obj.tag) {
            .pair => {
                const pair = obj.as(Pair);
                self.markValue(pair.car);
                self.markValue(pair.cdr);
            },
            .closure => {
                const cls = obj.as(Closure);
                self.markValue(types.makePointer(@ptrCast(cls.func)));
                for (cls.upvalues) |uv| {
                    self.markValue(uv);
                }
            },
            .function => {
                const func = obj.as(Function);
                for (func.constants.items) |c| {
                    self.markValue(c);
                }
            },
            .transformer => {
                const tx = obj.as(Transformer);
                for (tx.literals) |lit| {
                    self.markValue(lit);
                }
                for (tx.patterns) |pat| {
                    self.markValue(pat);
                }
                for (tx.templates) |tmpl| {
                    self.markValue(tmpl);
                }
            },
            .error_object => {
                const err = obj.as(types.ErrorObject);
                self.markValue(err.message);
                self.markValue(err.irritants);
            },
            .record_type => {},
            .record_instance => {
                const ri = obj.as(RecordInstance);
                self.markValue(types.makePointer(@ptrCast(ri.record_type)));
                for (ri.fields) |field| {
                    self.markValue(field);
                }
            },
            .continuation => {
                const cont = obj.as(Continuation);
                for (cont.registers) |reg| {
                    self.markValue(reg);
                }
                // Mark closures referenced in saved frames
                for (cont.frames[0..cont.frame_count]) |frame| {
                    if (frame.closure) |cls| {
                        self.markValue(types.makePointer(@ptrCast(cls)));
                    }
                    if (frame.native) |nf| {
                        self.markValue(types.makePointer(@ptrCast(nf)));
                    }
                }
                // Mark handler procedures
                for (cont.handlers[0..cont.handler_count]) |handler| {
                    self.markValue(handler.handler);
                }
                // Mark wind stack thunks
                for (cont.wind_records[0..cont.wind_count]) |wr| {
                    self.markValue(wr.before);
                    self.markValue(wr.after);
                }
            },
            .multiple_values => {
                const mv = obj.as(MultipleValues);
                for (mv.values) |val| {
                    self.markValue(val);
                }
            },
            .vector => {
                const vec = obj.as(Vector);
                for (vec.data) |elem| {
                    self.markValue(elem);
                }
            },
            .promise => {
                const p = obj.as(Promise);
                self.markValue(p.value);
            },
            .parameter => {
                const param = obj.as(types.ParameterObject);
                self.markValue(param.value);
                self.markValue(param.converter);
            },
            .hash_table => {
                const ht = obj.as(HashTable);
                for (ht.entries[0..ht.count]) |entry| {
                    self.markValue(entry.key);
                    self.markValue(entry.value);
                }
            },
            .ffi_library, .ffi_function => {},
            .symbol, .string, .native_fn, .flonum, .port, .complex, .bytevector => {},
        }
    }

    fn sweep(self: *GC) void {
        var prev: ?*Object = null;
        var obj = self.objects;
        while (obj) |o| {
            if (o.marked) {
                o.marked = false;
                prev = o;
                obj = o.next;
            } else {
                const next = o.next;
                if (prev) |p| {
                    p.next = next;
                } else {
                    self.objects = next;
                }
                self.freeObject(o);
                self.object_count -= 1;
                obj = next;
            }
        }
    }

    fn freeObject(self: *GC, obj: *Object) void {
        switch (obj.tag) {
            .pair => {
                const pair = obj.as(Pair);
                self.allocator.destroy(pair);
            },
            .symbol => {
                const sym = obj.as(Symbol);
                self.allocator.free(sym.name);
                self.allocator.destroy(sym);
            },
            .string => {
                const str = obj.as(SchemeString);
                self.allocator.free(str.data);
                self.allocator.destroy(str);
            },
            .closure => {
                const cls = obj.as(Closure);
                self.allocator.free(cls.upvalues);
                self.allocator.destroy(cls);
            },
            .function => {
                const func = obj.as(Function);
                func.code.deinit(self.allocator);
                func.constants.deinit(self.allocator);
                if (func.debug_locals.len > 0) {
                    self.allocator.free(func.debug_locals);
                }
                self.allocator.destroy(func);
            },
            .native_fn => {
                const nf = obj.as(NativeFn);
                self.allocator.destroy(nf);
            },
            .flonum => {
                const flo = obj.as(Flonum);
                self.allocator.destroy(flo);
            },
            .vector => {
                const vec = obj.as(Vector);
                self.allocator.free(vec.data);
                self.allocator.destroy(vec);
            },
            .transformer => {
                const tx = obj.as(Transformer);
                self.allocator.free(tx.literals);
                self.allocator.free(tx.patterns);
                self.allocator.free(tx.templates);
                self.allocator.destroy(tx);
            },
            .error_object => {
                const err = obj.as(types.ErrorObject);
                self.allocator.destroy(err);
            },
            .record_type => {
                const rt = obj.as(RecordType);
                self.allocator.free(rt.name);
                self.allocator.destroy(rt);
            },
            .record_instance => {
                const ri = obj.as(RecordInstance);
                self.allocator.free(ri.fields);
                self.allocator.destroy(ri);
            },
            .bytevector => {
                const bv = obj.as(Bytevector);
                self.allocator.free(bv.data);
                self.allocator.destroy(bv);
            },
            .promise => {
                const p = obj.as(Promise);
                self.allocator.destroy(p);
            },
            .port => {
                const port = obj.as(Port);
                // Close the fd if still open and not stdin/stdout/stderr
                if (port.is_open and port.fd > 2 and !port.is_string_port) {
                    _ = std.posix.system.close(port.fd);
                }
                if (port.owns_name) {
                    self.allocator.free(port.name);
                }
                // Free string port buffers
                if (port.string_data) |sd| {
                    self.allocator.free(sd);
                }
                if (port.string_out_buf) |sb| {
                    self.allocator.free(sb);
                }
                self.allocator.destroy(port);
            },
            .continuation => {
                const cont = obj.as(Continuation);
                // registers/frames/handlers/wind_records are all views into
                // the single backing allocation; free it once. Escape
                // continuations have no backing (empty slice).
                if (cont.backing.len > 0) self.allocator.free(cont.backing);
                self.allocator.destroy(cont);
            },
            .multiple_values => {
                const mv = obj.as(MultipleValues);
                self.allocator.free(mv.values);
                self.allocator.destroy(mv);
            },
            .complex => {
                const c = obj.as(types.Complex);
                self.allocator.destroy(c);
            },
            .parameter => {
                const p = obj.as(types.ParameterObject);
                self.allocator.destroy(p);
            },
            .hash_table => {
                const ht = obj.as(HashTable);
                self.allocator.free(ht.entries);
                self.allocator.destroy(ht);
            },
            .ffi_library => {
                const lib = obj.as(FfiLibrary);
                // Do NOT dlclose here — let ffi-close handle that explicitly
                self.allocator.free(lib.name);
                self.allocator.destroy(lib);
            },
            .ffi_function => {
                const ffi_fn = obj.as(FfiFunction);
                self.allocator.free(ffi_fn.name);
                self.allocator.free(ffi_fn.param_types);
                self.allocator.destroy(ffi_fn);
            },
        }
    }

    pub fn pushRoot(self: *GC, root: *Value) void {
        self.roots.append(self.allocator, root) catch {};
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
    gc.pushRoot(&rooted);

    gc.collect();
    try std.testing.expectEqual(@as(usize, 1), gc.object_count);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(types.car(rooted)));

    gc.popRoot();
}
