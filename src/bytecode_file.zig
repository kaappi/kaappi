const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const Function = types.Function;
const GC = memory.GC;

// File format constants
const MAGIC = [4]u8{ 'K', 'P', 'B', 'C' };
const VERSION: u16 = 1;

// Constant type tags
const TAG_FIXNUM: u8 = 0;
const TAG_FLONUM: u8 = 1;
const TAG_SYMBOL: u8 = 2;
const TAG_STRING: u8 = 3;
const TAG_BOOLEAN: u8 = 4;
const TAG_NIL: u8 = 5;
const TAG_VOID: u8 = 6;
const TAG_CHAR: u8 = 7;
const TAG_FUNCTION: u8 = 8;
const TAG_PAIR: u8 = 9;
const TAG_VECTOR: u8 = 10;
const TAG_BYTEVECTOR: u8 = 11;

pub const BytecodeError = error{
    InvalidMagic,
    UnsupportedVersion,
    HashMismatch,
    InvalidConstantTag,
    CorruptedFile,
    OutOfMemory,
    FileNotFound,
    ReadError,
    WriteError,
};

// ---------------------------------------------------------------------------
// Write helpers
// ---------------------------------------------------------------------------

const Writer = struct {
    buf: std.ArrayList(u8),

    fn init() Writer {
        return .{ .buf = .empty };
    }

    fn writeU8(self: *Writer, allocator: std.mem.Allocator, v: u8) !void {
        self.buf.append(allocator, v) catch return BytecodeError.OutOfMemory;
    }

    fn writeU16(self: *Writer, allocator: std.mem.Allocator, v: u16) !void {
        const bytes: [2]u8 = @bitCast(std.mem.nativeToLittle(u16, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    fn writeU32(self: *Writer, allocator: std.mem.Allocator, v: u32) !void {
        const bytes: [4]u8 = @bitCast(std.mem.nativeToLittle(u32, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    fn writeU64(self: *Writer, allocator: std.mem.Allocator, v: u64) !void {
        const bytes: [8]u8 = @bitCast(std.mem.nativeToLittle(u64, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    fn writeI64(self: *Writer, allocator: std.mem.Allocator, v: i64) !void {
        const bytes: [8]u8 = @bitCast(std.mem.nativeToLittle(i64, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    fn writeF64(self: *Writer, allocator: std.mem.Allocator, v: f64) !void {
        const bytes: [8]u8 = @bitCast(v);
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    fn writeBytes(self: *Writer, allocator: std.mem.Allocator, data: []const u8) !void {
        self.buf.appendSlice(allocator, data) catch return BytecodeError.OutOfMemory;
    }

    fn deinit(self: *Writer, allocator: std.mem.Allocator) void {
        self.buf.deinit(allocator);
    }
};

// ---------------------------------------------------------------------------
// Read helpers
// ---------------------------------------------------------------------------

const Reader = struct {
    data: []const u8,
    pos: usize,

    fn readU8(self: *Reader) !u8 {
        if (self.pos >= self.data.len) return BytecodeError.CorruptedFile;
        const v = self.data[self.pos];
        self.pos += 1;
        return v;
    }

    fn readU16(self: *Reader) !u16 {
        if (self.pos + 2 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..2];
        self.pos += 2;
        return std.mem.littleToNative(u16, @bitCast(bytes.*));
    }

    fn readU32(self: *Reader) !u32 {
        if (self.pos + 4 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..4];
        self.pos += 4;
        return std.mem.littleToNative(u32, @bitCast(bytes.*));
    }

    fn readU64(self: *Reader) !u64 {
        if (self.pos + 8 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..8];
        self.pos += 8;
        return std.mem.littleToNative(u64, @bitCast(bytes.*));
    }

    fn readI64(self: *Reader) !i64 {
        if (self.pos + 8 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..8];
        self.pos += 8;
        return std.mem.littleToNative(i64, @bitCast(bytes.*));
    }

    fn readF64(self: *Reader) !f64 {
        if (self.pos + 8 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..8];
        self.pos += 8;
        return @bitCast(bytes.*);
    }

    fn readBytes(self: *Reader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return BytecodeError.CorruptedFile;
        const result = self.data[self.pos..][0..len];
        self.pos += len;
        return result;
    }
};

// ---------------------------------------------------------------------------
// Function collection (flatten nested functions depth-first)
// ---------------------------------------------------------------------------

/// Collect all functions into a flat array with top-level functions first,
/// followed by their nested functions. This ensures that when deserializing,
/// the first top_level_count entries in the array are the top-level functions.
fn collectFunctions(allocator: std.mem.Allocator, top_level_funcs: []*Function) !std.ArrayList(*Function) {
    var result: std.ArrayList(*Function) = .empty;

    // First pass: add all top-level functions
    for (top_level_funcs) |func| {
        result.append(allocator, func) catch return BytecodeError.OutOfMemory;
    }

    // Second pass: add nested functions (DFS through each top-level function's constants)
    for (top_level_funcs) |func| {
        try collectNestedFunctions(allocator, func, &result);
    }

    return result;
}

fn collectNestedFunctions(allocator: std.mem.Allocator, func: *Function, result: *std.ArrayList(*Function)) !void {
    for (func.constants.items) |constant| {
        if (types.isPointer(constant) and types.toObject(constant).tag == .function) {
            const child_func = types.toObject(constant).as(Function);
            // Check if already collected
            var already = false;
            for (result.items) |existing| {
                if (existing == child_func) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                result.append(allocator, child_func) catch return BytecodeError.OutOfMemory;
                try collectNestedFunctions(allocator, child_func, result);
            }
        }
    }
}

fn findFunctionIndex(all_funcs: []*Function, func: *Function) ?u32 {
    for (all_funcs, 0..) |f, i| {
        if (f == func) return @intCast(i);
    }
    return null;
}

// ---------------------------------------------------------------------------
// Write constant
// ---------------------------------------------------------------------------

fn writeConstant(w: *Writer, allocator: std.mem.Allocator, val: Value, all_funcs: []*Function) !void {
    if (types.isFixnum(val)) {
        try w.writeU8(allocator, TAG_FIXNUM);
        try w.writeI64(allocator, types.toFixnum(val));
        return;
    }

    if (val == types.NIL) {
        try w.writeU8(allocator, TAG_NIL);
        return;
    }

    if (val == types.TRUE) {
        try w.writeU8(allocator, TAG_BOOLEAN);
        try w.writeU8(allocator, 1);
        return;
    }

    if (val == types.FALSE) {
        try w.writeU8(allocator, TAG_BOOLEAN);
        try w.writeU8(allocator, 0);
        return;
    }

    if (val == types.VOID) {
        try w.writeU8(allocator, TAG_VOID);
        return;
    }

    if (types.isChar(val)) {
        try w.writeU8(allocator, TAG_CHAR);
        try w.writeU32(allocator, @as(u32, types.toChar(val)));
        return;
    }

    if (types.isPointer(val)) {
        const obj = types.toObject(val);
        switch (obj.tag) {
            .flonum => {
                const flo = obj.as(types.Flonum);
                try w.writeU8(allocator, TAG_FLONUM);
                try w.writeF64(allocator, flo.value);
            },
            .symbol => {
                const sym = obj.as(types.Symbol);
                try w.writeU8(allocator, TAG_SYMBOL);
                try w.writeU16(allocator, @intCast(sym.name.len));
                try w.writeBytes(allocator, sym.name);
            },
            .string => {
                const str = obj.as(types.SchemeString);
                try w.writeU8(allocator, TAG_STRING);
                try w.writeU32(allocator, @intCast(str.data.len));
                try w.writeBytes(allocator, str.data);
            },
            .function => {
                const func = obj.as(Function);
                const idx = findFunctionIndex(all_funcs, func) orelse return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, TAG_FUNCTION);
                try w.writeU32(allocator, idx);
            },
            .pair => {
                try w.writeU8(allocator, TAG_PAIR);
                try writeConstant(w, allocator, types.car(val), all_funcs);
                try writeConstant(w, allocator, types.cdr(val), all_funcs);
            },
            .vector => {
                const vec = obj.as(types.Vector);
                try w.writeU8(allocator, TAG_VECTOR);
                try w.writeU32(allocator, @intCast(vec.data.len));
                for (vec.data) |elem| {
                    try writeConstant(w, allocator, elem, all_funcs);
                }
            },
            .bytevector => {
                const bv = obj.as(types.Bytevector);
                try w.writeU8(allocator, TAG_BYTEVECTOR);
                try w.writeU32(allocator, @intCast(bv.data.len));
                try w.writeBytes(allocator, bv.data);
            },
            else => {
                // Unsupported constant type — skip by writing nil as placeholder
                try w.writeU8(allocator, TAG_NIL);
            },
        }
        return;
    }

    // Fallback for unrecognized values
    try w.writeU8(allocator, TAG_NIL);
}

// ---------------------------------------------------------------------------
// Read constant
// ---------------------------------------------------------------------------

fn readConstant(r: *Reader, gc: *GC, all_funcs: []*Function) !Value {
    const tag = try r.readU8();
    switch (tag) {
        TAG_FIXNUM => {
            const n = try r.readI64();
            return types.makeFixnum(n);
        },
        TAG_FLONUM => {
            const f = try r.readF64();
            return gc.allocFlonum(f) catch return BytecodeError.OutOfMemory;
        },
        TAG_SYMBOL => {
            const name_len = try r.readU16();
            const name = try r.readBytes(name_len);
            return gc.allocSymbol(name) catch return BytecodeError.OutOfMemory;
        },
        TAG_STRING => {
            const data_len = try r.readU32();
            const data = try r.readBytes(data_len);
            return gc.allocString(data) catch return BytecodeError.OutOfMemory;
        },
        TAG_BOOLEAN => {
            const v = try r.readU8();
            return if (v != 0) types.TRUE else types.FALSE;
        },
        TAG_NIL => return types.NIL,
        TAG_VOID => return types.VOID,
        TAG_CHAR => {
            const cp = try r.readU32();
            return types.makeChar(@intCast(cp));
        },
        TAG_FUNCTION => {
            const idx = try r.readU32();
            if (idx >= all_funcs.len) return BytecodeError.CorruptedFile;
            return types.makePointer(@ptrCast(all_funcs[idx]));
        },
        TAG_PAIR => {
            const car_val = try readConstant(r, gc, all_funcs);
            // Root car to protect from GC during cdr read
            var car_root = car_val;
            gc.pushRoot(&car_root);
            const cdr_val = try readConstant(r, gc, all_funcs);
            gc.popRoot();
            return gc.allocPair(car_root, cdr_val) catch return BytecodeError.OutOfMemory;
        },
        TAG_VECTOR => {
            const len = try r.readU32();
            const allocator = gc.allocator;
            const elems = allocator.alloc(Value, len) catch return BytecodeError.OutOfMemory;
            defer allocator.free(elems);
            for (0..len) |i| {
                elems[i] = try readConstant(r, gc, all_funcs);
            }
            return gc.allocVector(elems) catch return BytecodeError.OutOfMemory;
        },
        TAG_BYTEVECTOR => {
            const len = try r.readU32();
            const data = try r.readBytes(len);
            return gc.allocBytevector(data) catch return BytecodeError.OutOfMemory;
        },
        else => return BytecodeError.InvalidConstantTag,
    }
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch {
        return error.FileNotFound;
    };
    defer _ = std.posix.system.close(fd);

    const max_size: usize = 4 * 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const bytes_read = std.posix.read(fd, &tmp) catch {
            return error.ReadError;
        };
        if (bytes_read == 0) break;
        if (result.items.len + bytes_read > max_size) {
            return error.ReadError;
        }
        result.appendSlice(allocator, tmp[0..bytes_read]) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Enhanced writeFile that records the top-level function count
// ---------------------------------------------------------------------------

pub fn writeFileWithTopLevel(allocator: std.mem.Allocator, top_level_funcs: []*Function, source_hash: u64, path: []const u8) !void {
    // Collect all functions depth-first
    var all_funcs_list = try collectFunctions(allocator, top_level_funcs);
    defer all_funcs_list.deinit(allocator);
    const all_funcs = all_funcs_list.items;

    var w = Writer.init();
    defer w.deinit(allocator);

    // Write header
    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, source_hash);
    try w.writeU32(allocator, @intCast(all_funcs.len));
    // Write top-level function count so reader knows which are top-level
    try w.writeU32(allocator, @intCast(top_level_funcs.len));

    // Write each function
    for (all_funcs) |func| {
        try w.writeU8(allocator, func.arity);
        try w.writeU8(allocator, func.locals_count);
        try w.writeU8(allocator, func.upvalue_count);
        try w.writeU8(allocator, if (func.is_variadic) @as(u8, 1) else @as(u8, 0));

        // Name
        if (func.name) |name| {
            try w.writeU16(allocator, @intCast(name.len));
            try w.writeBytes(allocator, name);
        } else {
            try w.writeU16(allocator, 0);
        }

        // Code
        try w.writeU32(allocator, @intCast(func.code.items.len));
        try w.writeBytes(allocator, func.code.items);

        // Constants
        try w.writeU32(allocator, @intCast(func.constants.items.len));
        for (func.constants.items) |constant| {
            try writeConstant(&w, allocator, constant, all_funcs);
        }
    }

    // Write buffer to file
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch return BytecodeError.WriteError;
    defer _ = std.posix.system.close(fd);

    var total: usize = 0;
    while (total < w.buf.items.len) {
        const result = std.posix.system.write(fd, w.buf.items.ptr + total, w.buf.items.len - total);
        const written: usize = @intCast(result);
        if (written == 0) return BytecodeError.WriteError;
        total += written;
    }
}

pub fn readFileWithTopLevel(gc: *GC, source_hash: u64, path: []const u8) !?struct { funcs: []*Function, top_level_count: u32 } {
    const allocator = gc.allocator;

    // Read file contents
    const data = readFileContents(allocator, path) catch return null;
    defer allocator.free(data);

    if (data.len < 22) return null; // minimum header size with top_level_count

    var r = Reader{ .data = data, .pos = 0 };

    // Verify magic
    const magic = r.readBytes(4) catch return null;
    if (!std.mem.eql(u8, magic, &MAGIC)) return null;

    // Verify version
    const version = r.readU16() catch return null;
    if (version != VERSION) return null;

    // Verify source hash
    const file_hash = r.readU64() catch return null;
    if (file_hash != source_hash) return null;

    // Read function count
    const func_count = r.readU32() catch return null;
    if (func_count == 0) return null;

    // Read top-level count
    const top_level_count = r.readU32() catch return null;

    // Allocate all function objects first (so constants can reference by index)
    const all_funcs = allocator.alloc(*Function, func_count) catch return BytecodeError.OutOfMemory;
    defer allocator.free(all_funcs);

    for (0..func_count) |i| {
        all_funcs[i] = gc.allocFunction() catch return BytecodeError.OutOfMemory;
        // Root to protect from GC
        gc.extra_roots.append(allocator, types.makePointer(@ptrCast(all_funcs[i]))) catch {};
    }

    // Now read each function's data
    for (0..func_count) |i| {
        const func = all_funcs[i];

        func.arity = r.readU8() catch return null;
        func.locals_count = r.readU8() catch return null;
        func.upvalue_count = r.readU8() catch return null;
        const variadic_byte = r.readU8() catch return null;
        func.is_variadic = variadic_byte != 0;

        // Name
        const name_len = r.readU16() catch return null;
        if (name_len > 0) {
            const name_bytes = r.readBytes(name_len) catch return null;
            func.name = allocator.dupe(u8, name_bytes) catch return BytecodeError.OutOfMemory;
            func.owns_name = true;
        }

        // Code
        const code_len = r.readU32() catch return null;
        const code_bytes = r.readBytes(code_len) catch return null;
        func.code.appendSlice(allocator, code_bytes) catch return BytecodeError.OutOfMemory;

        // Constants
        const const_count = r.readU32() catch return null;
        for (0..const_count) |_| {
            const val = readConstant(&r, gc, all_funcs) catch return null;
            func.constants.append(allocator, val) catch return BytecodeError.OutOfMemory;
        }
    }

    const result = allocator.alloc(*Function, func_count) catch return BytecodeError.OutOfMemory;
    @memcpy(result, all_funcs);
    return .{ .funcs = result, .top_level_count = top_level_count };
}

// ---------------------------------------------------------------------------
// Utility: compute source hash
// ---------------------------------------------------------------------------

pub fn sourceHash(source: []const u8) u64 {
    return std.hash.Wyhash.hash(0, source);
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Derive a .sbc cache path from a source path (.scm or .sld).
/// Replaces the extension with .sbc, or appends .sbc if no known extension.
pub fn getSbcPath(allocator: std.mem.Allocator, src_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, src_path, ".scm")) {
        return std.fmt.allocPrint(allocator, "{s}.sbc", .{src_path[0 .. src_path.len - 4]});
    }
    if (std.mem.endsWith(u8, src_path, ".sld")) {
        return std.fmt.allocPrint(allocator, "{s}.sbc", .{src_path[0 .. src_path.len - 4]});
    }
    return std.fmt.allocPrint(allocator, "{s}.sbc", .{src_path});
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bytecode round-trip: simple function" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    // Create a simple function with some constants
    const func = try gc.allocFunction();
    // Add some bytecode
    func.code.append(allocator, @intFromEnum(types.OpCode.load_const)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // dst
    func.code.append(allocator, 0) catch unreachable; // idx high
    func.code.append(allocator, 0) catch unreachable; // idx low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src

    // Add a fixnum constant
    func.constants.append(allocator, types.makeFixnum(42)) catch unreachable;
    func.arity = 0;
    func.locals_count = 1;

    // Serialize
    var funcs_arr = [_]*Function{func};
    const hash: u64 = 12345;
    const path = "/tmp/kaappi_test_roundtrip.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, path);
    defer {
        // Clean up test file
        _ = std.posix.system.unlink(@ptrCast(path));
    }

    // Deserialize
    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    try std.testing.expectEqual(@as(u32, 1), loaded.top_level_count);
    try std.testing.expect(loaded.funcs.len >= 1);

    const loaded_func = loaded.funcs[0];
    try std.testing.expectEqual(@as(u8, 0), loaded_func.arity);
    try std.testing.expectEqual(@as(u8, 1), loaded_func.locals_count);
    try std.testing.expectEqual(@as(usize, 6), loaded_func.code.items.len);
    try std.testing.expectEqual(@as(usize, 1), loaded_func.constants.items.len);
    try std.testing.expect(types.isFixnum(loaded_func.constants.items[0]));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(loaded_func.constants.items[0]));
}

test "bytecode round-trip: hash mismatch returns null" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;

    var funcs_arr = [_]*Function{func};
    const path = "/tmp/kaappi_test_mismatch.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, 12345, path);
    defer {
        _ = std.posix.system.unlink(@ptrCast(path));
    }

    // Try reading with different hash
    const result = try readFileWithTopLevel(&gc, 99999, path);
    try std.testing.expect(result == null);
}

test "bytecode round-trip: various constant types" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;

    // Add various constant types
    func.constants.append(allocator, types.makeFixnum(-100)) catch unreachable;
    func.constants.append(allocator, types.TRUE) catch unreachable;
    func.constants.append(allocator, types.FALSE) catch unreachable;
    func.constants.append(allocator, types.NIL) catch unreachable;
    func.constants.append(allocator, types.VOID) catch unreachable;
    func.constants.append(allocator, types.makeChar('Z')) catch unreachable;

    const sym = try gc.allocSymbol("hello");
    func.constants.append(allocator, sym) catch unreachable;

    const str = try gc.allocString("world");
    func.constants.append(allocator, str) catch unreachable;

    const flo = try gc.allocFlonum(3.14);
    func.constants.append(allocator, flo) catch unreachable;

    const bv_data = [_]u8{ 1, 2, 3 };
    const bv = try gc.allocBytevector(&bv_data);
    func.constants.append(allocator, bv) catch unreachable;

    func.arity = 0;
    func.locals_count = 1;

    var funcs_arr = [_]*Function{func};
    const hash: u64 = 54321;
    const path = "/tmp/kaappi_test_constants.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, path);
    defer {
        _ = std.posix.system.unlink(@ptrCast(path));
    }

    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    const consts = loaded.funcs[0].constants.items;
    try std.testing.expectEqual(@as(usize, 10), consts.len);
    try std.testing.expectEqual(@as(i64, -100), types.toFixnum(consts[0]));
    try std.testing.expectEqual(types.TRUE, consts[1]);
    try std.testing.expectEqual(types.FALSE, consts[2]);
    try std.testing.expectEqual(types.NIL, consts[3]);
    try std.testing.expectEqual(types.VOID, consts[4]);
    try std.testing.expect(types.isChar(consts[5]));
    try std.testing.expectEqual(@as(u21, 'Z'), types.toChar(consts[5]));
    try std.testing.expect(types.isSymbol(consts[6]));
    try std.testing.expectEqualStrings("hello", types.symbolName(consts[6]));
    try std.testing.expect(types.isString(consts[7]));
    try std.testing.expectEqualStrings("world", types.toObject(consts[7]).as(types.SchemeString).data);
    try std.testing.expect(types.isFlonum(consts[8]));
    try std.testing.expectEqual(@as(f64, 3.14), types.toFlonum(consts[8]));
    try std.testing.expect(types.isBytevector(consts[9]));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3 }, types.toBytevector(consts[9]).data);
}

test "bytecode round-trip: nested functions" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    // Create a child function
    const child_func = try gc.allocFunction();
    child_func.code.append(allocator, @intFromEnum(types.OpCode.load_const)) catch unreachable;
    child_func.code.append(allocator, 0) catch unreachable;
    child_func.code.append(allocator, 0) catch unreachable;
    child_func.code.append(allocator, 0) catch unreachable;
    child_func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    child_func.code.append(allocator, 0) catch unreachable;
    child_func.constants.append(allocator, types.makeFixnum(99)) catch unreachable;
    child_func.arity = 1;
    child_func.locals_count = 1;

    // Create parent function that references child
    const parent_func = try gc.allocFunction();
    parent_func.code.append(allocator, @intFromEnum(types.OpCode.closure)) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable;
    parent_func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable;
    parent_func.constants.append(allocator, types.makePointer(@ptrCast(child_func))) catch unreachable;
    parent_func.arity = 0;
    parent_func.locals_count = 1;

    var funcs_arr = [_]*Function{parent_func};
    const hash: u64 = 77777;
    const path = "/tmp/kaappi_test_nested.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, path);
    defer {
        _ = std.posix.system.unlink(@ptrCast(path));
    }

    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    try std.testing.expectEqual(@as(u32, 1), loaded.top_level_count);
    try std.testing.expect(loaded.funcs.len >= 2);

    // Check parent references child correctly
    const loaded_parent = loaded.funcs[0];
    try std.testing.expectEqual(@as(usize, 1), loaded_parent.constants.items.len);
    try std.testing.expect(types.isFunction(loaded_parent.constants.items[0]));

    const loaded_child = types.toObject(loaded_parent.constants.items[0]).as(Function);
    try std.testing.expectEqual(@as(u8, 1), loaded_child.arity);
    try std.testing.expectEqual(@as(usize, 1), loaded_child.constants.items.len);
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(loaded_child.constants.items[0]));
}

test "source hash computation" {
    const h1 = sourceHash("(+ 1 2)");
    const h2 = sourceHash("(+ 1 2)");
    const h3 = sourceHash("(+ 1 3)");

    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != h3);
}
