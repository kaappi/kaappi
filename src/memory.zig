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

const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const Port = types.Port;
const Continuation = types.Continuation;
const MultipleValues = types.MultipleValues;
const SavedFrame = types.SavedFrame;
const SavedHandler = types.SavedHandler;
const WindRecord = types.WindRecord;

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
        const saved_regs = try self.allocator.dupe(Value, registers);
        const saved_frames = try self.allocator.dupe(SavedFrame, frames);
        const saved_handlers = try self.allocator.dupe(SavedHandler, handlers);
        const saved_winds = try self.allocator.dupe(WindRecord, wind_records);

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
        };
        self.bytes_allocated += @sizeOf(Continuation) +
            registers.len * @sizeOf(Value) +
            frames.len * @sizeOf(SavedFrame) +
            handlers.len * @sizeOf(SavedHandler) +
            wind_records.len * @sizeOf(WindRecord);
        self.trackObject(&cont.header);
        return types.makePointer(@ptrCast(cont));
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
            .symbol, .string, .native_fn, .flonum, .port => {},
            else => {},
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
            .port => {
                const port = obj.as(Port);
                // Close the fd if still open and not stdin/stdout/stderr
                if (port.is_open and port.fd > 2) {
                    _ = std.posix.system.close(port.fd);
                }
                if (port.owns_name) {
                    self.allocator.free(port.name);
                }
                self.allocator.destroy(port);
            },
            .continuation => {
                const cont = obj.as(Continuation);
                self.allocator.free(cont.registers);
                self.allocator.free(cont.frames);
                self.allocator.free(cont.handlers);
                self.allocator.free(cont.wind_records);
                self.allocator.destroy(cont);
            },
            .multiple_values => {
                const mv = obj.as(MultipleValues);
                self.allocator.free(mv.values);
                self.allocator.destroy(mv);
            },
            else => {},
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
