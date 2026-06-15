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
            .symbol, .string, .native_fn => {},
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
