const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const Function = types.Function;
const OpCode = types.OpCode;
const GC = memory.GC;

// File format constants
const MAGIC = [4]u8{ 'K', 'P', 'B', 'C' };
const VERSION: u16 = 4;
const MAX_FUNCTIONS: u32 = 16_384;
const MAX_TOP_LEVEL_FUNCTIONS: u32 = 4_096;
const MAX_CODE_BYTES: u32 = 4_194_304;
const MAX_CONSTANTS_PER_FUNCTION: u32 = 65_535;
const MAX_SYMBOL_BYTES: u16 = 4_096;
const MAX_STRING_BYTES: u32 = 1_048_576;
const MAX_VECTOR_LEN: u32 = 262_144;
const MAX_BYTEVECTOR_LEN: u32 = 1_048_576;
const MAX_BIGNUM_LIMBS: u32 = 262_144;
const MAX_CONSTANT_DEPTH: u32 = 256;

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
const TAG_BIGNUM: u8 = 12;
const TAG_RATIONAL: u8 = 13;
const TAG_COMPLEX: u8 = 14;

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
        const bits: u64 = @bitCast(v);
        const bytes: [8]u8 = @bitCast(std.mem.nativeToLittle(u64, bits));
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
        const bits = std.mem.littleToNative(u64, @bitCast(bytes.*));
        return @bitCast(bits);
    }

    fn readBytes(self: *Reader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return BytecodeError.CorruptedFile;
        const result = self.data[self.pos..][0..len];
        self.pos += len;
        return result;
    }
};

fn freeBundledFiles(allocator: std.mem.Allocator, bf: *std.StringHashMap([]const u8)) void {
    var it = bf.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    bf.deinit();
}

fn freePreambleEntries(allocator: std.mem.Allocator, entries: [][]const u8, count: usize) void {
    for (0..count) |j| {
        allocator.free(entries[j]);
    }
    allocator.free(entries);
}

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

fn writeConstant(w: *Writer, allocator: std.mem.Allocator, val: Value, all_funcs: []*Function, depth: u32) !void {
    if (depth > 256) {
        try w.writeU8(allocator, TAG_NIL);
        return;
    }
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

    if (types.isFlonum(val)) {
        try w.writeU8(allocator, TAG_FLONUM);
        try w.writeF64(allocator, types.toFlonum(val));
        return;
    }

    if (types.isPointer(val)) {
        const obj = types.toObject(val);
        switch (obj.tag) {
            .symbol => {
                const sym = obj.as(types.Symbol);
                if (sym.name.len > MAX_SYMBOL_BYTES) return BytecodeError.CorruptedFile;
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
                try writeConstant(w, allocator, types.car(val), all_funcs, depth + 1);
                try writeConstant(w, allocator, types.cdr(val), all_funcs, depth + 1);
            },
            .vector => {
                const vec = obj.as(types.Vector);
                try w.writeU8(allocator, TAG_VECTOR);
                try w.writeU32(allocator, @intCast(vec.data.len));
                for (vec.data) |elem| {
                    try writeConstant(w, allocator, elem, all_funcs, depth + 1);
                }
            },
            .bytevector => {
                const bv = obj.as(types.Bytevector);
                try w.writeU8(allocator, TAG_BYTEVECTOR);
                try w.writeU32(allocator, @intCast(bv.data.len));
                try w.writeBytes(allocator, bv.data);
            },
            .bignum => {
                const bn = obj.as(types.Bignum);
                try w.writeU8(allocator, TAG_BIGNUM);
                try w.writeU8(allocator, if (bn.positive) @as(u8, 1) else @as(u8, 0));
                try w.writeU32(allocator, @intCast(bn.len));
                for (bn.limbs[0..bn.len]) |limb| {
                    try w.writeU64(allocator, limb);
                }
            },
            .rational => {
                const rat = obj.as(types.Rational);
                try w.writeU8(allocator, TAG_RATIONAL);
                try writeConstant(w, allocator, rat.numerator, all_funcs, depth + 1);
                try writeConstant(w, allocator, rat.denominator, all_funcs, depth + 1);
            },
            .complex => {
                const cx = obj.as(types.Complex);
                try w.writeU8(allocator, TAG_COMPLEX);
                try w.writeF64(allocator, cx.real);
                try w.writeF64(allocator, cx.imag);
                try w.writeU8(allocator, if (cx.exact_real) @as(u8, 1) else @as(u8, 0));
                try w.writeU8(allocator, if (cx.exact_imag) @as(u8, 1) else @as(u8, 0));
            },
            else => {
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

fn readConstant(r: *Reader, gc: *GC, all_funcs: []*Function, depth: u32) !Value {
    if (depth > MAX_CONSTANT_DEPTH) return BytecodeError.CorruptedFile;
    const tag = try r.readU8();
    switch (tag) {
        TAG_FIXNUM => {
            const n = try r.readI64();
            if (n < -(1 << 47) or n >= (1 << 47)) return BytecodeError.CorruptedFile;
            return types.makeFixnum(n);
        },
        TAG_FLONUM => {
            const f = try r.readF64();
            return types.makeFlonum(f);
        },
        TAG_SYMBOL => {
            const name_len = try r.readU16();
            if (name_len > MAX_SYMBOL_BYTES) return BytecodeError.CorruptedFile;
            const name = try r.readBytes(name_len);
            return gc.allocSymbol(name) catch return BytecodeError.OutOfMemory;
        },
        TAG_STRING => {
            const data_len = try r.readU32();
            if (data_len > MAX_STRING_BYTES) return BytecodeError.CorruptedFile;
            const data = try r.readBytes(data_len);
            return gc.allocString(data) catch return BytecodeError.OutOfMemory;
        },
        TAG_BOOLEAN => {
            const v = try r.readU8();
            if (v > 1) return BytecodeError.CorruptedFile;
            return if (v != 0) types.TRUE else types.FALSE;
        },
        TAG_NIL => return types.NIL,
        TAG_VOID => return types.VOID,
        TAG_CHAR => {
            const cp = try r.readU32();
            if (cp > 0x10FFFF) return BytecodeError.CorruptedFile;
            if (cp >= 0xD800 and cp <= 0xDFFF) return BytecodeError.CorruptedFile;
            return types.makeChar(@intCast(cp));
        },
        TAG_FUNCTION => {
            const idx = try r.readU32();
            if (idx >= all_funcs.len) return BytecodeError.CorruptedFile;
            return types.makePointer(@ptrCast(all_funcs[idx]));
        },
        TAG_PAIR => {
            const car_val = try readConstant(r, gc, all_funcs, depth + 1);
            // Root car to protect from GC during cdr read
            var car_root = car_val;
            try gc.pushRoot(&car_root);
            defer gc.popRoot();
            const cdr_val = try readConstant(r, gc, all_funcs, depth + 1);
            return gc.allocPair(car_root, cdr_val) catch return BytecodeError.OutOfMemory;
        },
        TAG_VECTOR => {
            const len = try r.readU32();
            if (len > MAX_VECTOR_LEN) return BytecodeError.CorruptedFile;
            var vec_val = gc.allocVectorFill(len, types.NIL) catch return BytecodeError.OutOfMemory;
            try gc.pushRoot(&vec_val);
            defer gc.popRoot();
            const vec = types.toVector(vec_val);
            for (0..len) |i| {
                vec.data[i] = try readConstant(r, gc, all_funcs, depth + 1);
            }
            return vec_val;
        },
        TAG_BYTEVECTOR => {
            const len = try r.readU32();
            if (len > MAX_BYTEVECTOR_LEN) return BytecodeError.CorruptedFile;
            const data = try r.readBytes(len);
            return gc.allocBytevector(data) catch return BytecodeError.OutOfMemory;
        },
        TAG_BIGNUM => {
            const positive = (try r.readU8()) != 0;
            const len = try r.readU32();
            if (len == 0 or len > MAX_BIGNUM_LIMBS) return BytecodeError.CorruptedFile;
            const allocator = gc.allocator;
            const limbs = allocator.alloc(u64, len) catch return BytecodeError.OutOfMemory;
            defer allocator.free(limbs);
            for (0..len) |i| {
                limbs[i] = try r.readU64();
            }
            if (limbs[len - 1] == 0) return BytecodeError.CorruptedFile;
            return gc.allocBignumFromLimbs(limbs, len, positive) catch return BytecodeError.OutOfMemory;
        },
        TAG_RATIONAL => {
            const num = try readConstant(r, gc, all_funcs, depth + 1);
            if (!types.isFixnum(num) and !types.isBignum(num)) return BytecodeError.CorruptedFile;
            var num_root = num;
            try gc.pushRoot(&num_root);
            defer gc.popRoot();
            const den = try readConstant(r, gc, all_funcs, depth + 1);
            if (!types.isFixnum(den) and !types.isBignum(den)) return BytecodeError.CorruptedFile;
            if (types.isFixnum(den) and types.toFixnum(den) == 0) return BytecodeError.CorruptedFile;
            if (types.isBignum(den) and types.toBignum(den).len == 0) return BytecodeError.CorruptedFile;
            return gc.allocRational(num_root, den) catch return BytecodeError.OutOfMemory;
        },
        TAG_COMPLEX => {
            const real = try r.readF64();
            const imag = try r.readF64();
            const exact_real = (try r.readU8()) != 0;
            const exact_imag = (try r.readU8()) != 0;
            return gc.allocComplexEx(real, imag, exact_real, exact_imag) catch return BytecodeError.OutOfMemory;
        },
        else => return BytecodeError.InvalidConstantTag,
    }
}

fn readU16FromCode(code: []const u8, ip: *usize) BytecodeError!u16 {
    if (ip.* + 2 > code.len) return BytecodeError.CorruptedFile;
    const hi: u16 = code[ip.*];
    const lo: u16 = code[ip.* + 1];
    ip.* += 2;
    return (hi << 8) | lo;
}

fn readI16FromCode(code: []const u8, ip: *usize) BytecodeError!i16 {
    return @bitCast(try readU16FromCode(code, ip));
}

fn validateSymbolConstant(func: *Function, idx: u16) BytecodeError!void {
    if (idx >= func.constants.items.len) return BytecodeError.CorruptedFile;
    if (!types.isSymbol(func.constants.items[idx])) return BytecodeError.CorruptedFile;
}

fn validateFunctionBytecode(func: *Function) BytecodeError!void {
    const code = func.code.items;
    var ip: usize = 0;
    while (ip < code.len) {
        const raw = code[ip];
        if (raw > @intFromEnum(OpCode.self_tail_call)) return BytecodeError.CorruptedFile;
        const op: OpCode = @enumFromInt(raw);
        ip += 1;

        switch (op) {
            .load_const => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // dst
                const idx = try readU16FromCode(code, &ip);
                if (idx >= func.constants.items.len) return BytecodeError.CorruptedFile;
            },
            .load_nil, .load_true, .load_false, .load_void, .@"return", .close_upvalue, .push_handler, .box_local => {
                if (ip + 2 > code.len) return BytecodeError.CorruptedFile;
                ip += 2;
            },
            .move, .get_upvalue, .set_upvalue, .get_box_local, .set_box_local => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 4;
            },
            .call, .tail_call, .tail_apply, .self_tail_call => {
                if (ip + 3 > code.len) return BytecodeError.CorruptedFile;
                ip += 3;
            },
            .get_local, .set_local => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 4;
            },
            .get_global => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // dst
                const idx = try readU16FromCode(code, &ip);
                try validateSymbolConstant(func, idx);
            },
            .set_global, .define_global => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                const idx = try readU16FromCode(code, &ip);
                try validateSymbolConstant(func, idx);
                ip += 2; // src
            },
            .jump => {
                if (ip + 2 > code.len) return BytecodeError.CorruptedFile;
                const off = try readI16FromCode(code, &ip);
                const target = @as(i64, @intCast(ip)) + @as(i64, off);
                if (target < 0 or target > code.len) return BytecodeError.CorruptedFile;
            },
            .jump_false, .jump_true => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // test register
                const off = try readI16FromCode(code, &ip);
                const target = @as(i64, @intCast(ip)) + @as(i64, off);
                if (target < 0 or target > code.len) return BytecodeError.CorruptedFile;
            },
            .closure => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // dst
                const idx = try readU16FromCode(code, &ip);
                if (idx >= func.constants.items.len) return BytecodeError.CorruptedFile;
                const func_val = func.constants.items[idx];
                if (!types.isFunction(func_val)) return BytecodeError.CorruptedFile;
                const inner = types.toObject(func_val).as(Function);
                const capture_bytes = @as(usize, inner.upvalue_count) * 3;
                if (ip + capture_bytes > code.len) return BytecodeError.CorruptedFile;
                ip += capture_bytes;
            },
            .cons => {
                if (ip + 6 > code.len) return BytecodeError.CorruptedFile;
                ip += 6;
            },
            .pop_handler, .halt => {},
            .call_global, .tail_call_global => {
                if (ip + 5 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // base register
                const idx = try readU16FromCode(code, &ip);
                try validateSymbolConstant(func, idx);
                ip += 1; // nargs
            },
        }
    }
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (comptime is_wasm) return error.FileNotFound;
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

fn writeFunctionsToBuffer(w: *Writer, allocator: std.mem.Allocator, top_level_funcs: []*Function, source_hash: u64) !std.ArrayList(*Function) {
    const all_funcs_list = try collectFunctions(allocator, top_level_funcs);
    const all_funcs = all_funcs_list.items;

    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, source_hash);
    try w.writeU32(allocator, @intCast(all_funcs.len));
    try w.writeU32(allocator, @intCast(top_level_funcs.len));

    for (all_funcs) |func| {
        try w.writeU8(allocator, func.arity);
        try w.writeU16(allocator, func.locals_count);
        try w.writeU8(allocator, func.upvalue_count);
        try w.writeU8(allocator, if (func.is_variadic) @as(u8, 1) else @as(u8, 0));

        if (func.name) |name| {
            if (name.len > MAX_SYMBOL_BYTES) return BytecodeError.CorruptedFile;
            try w.writeU16(allocator, @intCast(name.len));
            try w.writeBytes(allocator, name);
        } else {
            try w.writeU16(allocator, 0);
        }

        try w.writeU32(allocator, @intCast(func.code.items.len));
        try w.writeBytes(allocator, func.code.items);

        try w.writeU32(allocator, @intCast(func.constants.items.len));
        for (func.constants.items) |constant| {
            try writeConstant(w, allocator, constant, all_funcs, 0);
        }
    }

    return all_funcs_list;
}

fn writeBufferToFile(w: *Writer, path: []const u8) !void {
    if (comptime is_wasm) return BytecodeError.WriteError;
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch return BytecodeError.WriteError;
    defer _ = std.posix.system.close(fd);

    var total: usize = 0;
    while (total < w.buf.items.len) {
        const result = std.posix.system.write(fd, w.buf.items.ptr + total, w.buf.items.len - total);
        if (result < 0) {
            if (std.posix.errno(result) == .INTR) continue;
            return BytecodeError.WriteError;
        }
        if (result == 0) return BytecodeError.WriteError;
        total += @as(usize, @intCast(result));
    }
}

pub fn writeFileWithTopLevel(allocator: std.mem.Allocator, top_level_funcs: []*Function, source_hash: u64, path: []const u8) !void {
    var w = Writer.init();
    defer w.deinit(allocator);

    var all_funcs_list = try writeFunctionsToBuffer(&w, allocator, top_level_funcs, source_hash);
    defer all_funcs_list.deinit(allocator);

    // Empty bundled files and preamble sections (regular cache files)
    try w.writeU32(allocator, 0);
    try w.writeU32(allocator, 0);

    try writeBufferToFile(&w, path);
}

/// Write a standalone .sbc with bundled library sources and preamble forms.
pub fn writeFileWithBundle(
    allocator: std.mem.Allocator,
    top_level_funcs: []*Function,
    source_hash: u64,
    bundled_files: *const std.StringHashMap([]const u8),
    preamble: []const []const u8,
    path: []const u8,
) !void {
    var w = Writer.init();
    defer w.deinit(allocator);

    var all_funcs_list = try writeFunctionsToBuffer(&w, allocator, top_level_funcs, source_hash);
    defer all_funcs_list.deinit(allocator);

    // Bundled files section
    try w.writeU32(allocator, @intCast(bundled_files.count()));
    var it = bundled_files.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;
        try w.writeU16(allocator, @intCast(key.len));
        try w.writeBytes(allocator, key);
        try w.writeU32(allocator, @intCast(val.len));
        try w.writeBytes(allocator, val);
    }

    // Preamble section (top-level forms to replay at runtime)
    try w.writeU32(allocator, @intCast(preamble.len));
    for (preamble) |src| {
        try w.writeU32(allocator, @intCast(src.len));
        try w.writeBytes(allocator, src);
    }

    try writeBufferToFile(&w, path);
}

pub const DeserializeResult = struct {
    funcs: []*Function,
    top_level_count: u32,
    bundled_files: ?std.StringHashMap([]const u8) = null,
    preamble: ?[][]const u8 = null,
};

fn deserializeFromBuffer(gc: *GC, data: []const u8, expected_hash: ?u64) !?DeserializeResult {
    const allocator = gc.allocator;

    if (data.len < 22) return null;

    var r = Reader{ .data = data, .pos = 0 };

    const magic = r.readBytes(4) catch return null;
    if (!std.mem.eql(u8, magic, &MAGIC)) return null;

    const version = r.readU16() catch return null;
    if (version != VERSION) return null;

    const file_hash = r.readU64() catch return null;
    if (expected_hash) |eh| {
        if (file_hash != eh) return null;
    }

    const func_count = r.readU32() catch return null;
    if (func_count == 0 or func_count > MAX_FUNCTIONS) return null;

    const top_level_count = r.readU32() catch return null;
    if (top_level_count > func_count or top_level_count > MAX_TOP_LEVEL_FUNCTIONS) return null;

    const all_funcs = allocator.alloc(*Function, func_count) catch return BytecodeError.OutOfMemory;
    defer allocator.free(all_funcs);

    const roots_base = gc.extra_roots.items.len;
    defer gc.extra_roots.shrinkRetainingCapacity(roots_base);
    for (0..func_count) |i| {
        all_funcs[i] = gc.allocFunction() catch return BytecodeError.OutOfMemory;
        gc.extra_roots.append(allocator, types.makePointer(@ptrCast(all_funcs[i]))) catch return BytecodeError.OutOfMemory;
    }

    for (0..func_count) |i| {
        const func = all_funcs[i];

        func.arity = r.readU8() catch return null;
        func.locals_count = r.readU16() catch return null;
        func.upvalue_count = r.readU8() catch return null;
        const variadic_byte = r.readU8() catch return null;
        func.is_variadic = variadic_byte != 0;

        const name_len = r.readU16() catch return null;
        if (name_len > MAX_SYMBOL_BYTES) return null;
        if (name_len > 0) {
            const name_bytes = r.readBytes(name_len) catch return null;
            func.name = allocator.dupe(u8, name_bytes) catch return BytecodeError.OutOfMemory;
            func.owns_name = true;
        }

        const code_len = r.readU32() catch return null;
        if (code_len > MAX_CODE_BYTES) {
            var buf: [128]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buf);
            w.print("error: bytecode too large ({d} bytes, max {d})\n", .{ code_len, MAX_CODE_BYTES }) catch {};
            const msg = w.buffered();
            _ = std.posix.system.write(2, msg.ptr, msg.len);
            return null;
        }
        const code_bytes = r.readBytes(code_len) catch return null;
        func.code.appendSlice(allocator, code_bytes) catch return BytecodeError.OutOfMemory;

        const const_count = r.readU32() catch return null;
        if (const_count > MAX_CONSTANTS_PER_FUNCTION) return null;
        for (0..const_count) |_| {
            const val = readConstant(&r, gc, all_funcs, 0) catch return null;
            func.constants.append(allocator, val) catch return BytecodeError.OutOfMemory;
        }
    }

    for (all_funcs) |func| {
        validateFunctionBytecode(func) catch return null;
    }

    // Read bundled files section
    const bf_count = r.readU32() catch return null;
    var bundled_files: ?std.StringHashMap([]const u8) = null;
    if (bf_count > 0) {
        if (bf_count > 4096) return null;
        var bf = std.StringHashMap([]const u8).init(allocator);
        for (0..bf_count) |_| {
            const path_len = r.readU16() catch {
                freeBundledFiles(allocator, &bf);
                return null;
            };
            const path_bytes = r.readBytes(path_len) catch {
                freeBundledFiles(allocator, &bf);
                return null;
            };
            const content_len = r.readU32() catch {
                freeBundledFiles(allocator, &bf);
                return null;
            };
            if (content_len > MAX_STRING_BYTES) {
                freeBundledFiles(allocator, &bf);
                return null;
            }
            const content = r.readBytes(content_len) catch {
                freeBundledFiles(allocator, &bf);
                return null;
            };
            const key = allocator.dupe(u8, path_bytes) catch {
                freeBundledFiles(allocator, &bf);
                return BytecodeError.OutOfMemory;
            };
            const val = allocator.dupe(u8, content) catch {
                allocator.free(key);
                freeBundledFiles(allocator, &bf);
                return BytecodeError.OutOfMemory;
            };
            bf.put(key, val) catch {
                allocator.free(key);
                allocator.free(val);
                freeBundledFiles(allocator, &bf);
                return BytecodeError.OutOfMemory;
            };
        }
        bundled_files = bf;
    }

    // Read preamble section
    const preamble_count = r.readU32() catch {
        if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
        return null;
    };
    var preamble: ?[][]const u8 = null;
    if (preamble_count > 0) {
        if (preamble_count > 4096) {
            if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
            return null;
        }
        const entries = allocator.alloc([]const u8, preamble_count) catch {
            if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
            return BytecodeError.OutOfMemory;
        };
        for (0..preamble_count) |i| {
            const src_len = r.readU32() catch {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
                return null;
            };
            if (src_len > MAX_STRING_BYTES) {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
                return null;
            }
            const src = r.readBytes(src_len) catch {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
                return null;
            };
            entries[i] = allocator.dupe(u8, src) catch {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
                return BytecodeError.OutOfMemory;
            };
        }
        preamble = entries;
    }

    if (r.pos != data.len) {
        if (bundled_files) |*bf| freeBundledFiles(allocator, bf);
        if (preamble) |p| freePreambleEntries(allocator, p, p.len);
        return null;
    }

    const result = allocator.alloc(*Function, func_count) catch return BytecodeError.OutOfMemory;
    @memcpy(result, all_funcs);
    return .{ .funcs = result, .top_level_count = top_level_count, .bundled_files = bundled_files, .preamble = preamble };
}

pub fn readFromBuffer(gc: *GC, data: []const u8) !?DeserializeResult {
    return deserializeFromBuffer(gc, data, null);
}

pub fn readFileWithTopLevel(gc: *GC, source_hash: u64, path: []const u8) !?DeserializeResult {
    const allocator = gc.allocator;
    const data = readFileContents(allocator, path) catch return null;
    defer allocator.free(data);
    return deserializeFromBuffer(gc, data, source_hash);
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
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, 0) catch unreachable; // idx high
    func.code.append(allocator, 0) catch unreachable; // idx low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

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
    try std.testing.expectEqual(@as(u16, 1), loaded_func.locals_count);
    try std.testing.expectEqual(@as(usize, 8), loaded_func.code.items.len);
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
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

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
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

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

    const flo = types.makeFlonum(3.14);
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
    child_func.code.append(allocator, 0) catch unreachable; // dst high
    child_func.code.append(allocator, 0) catch unreachable; // dst low
    child_func.code.append(allocator, 0) catch unreachable; // idx high
    child_func.code.append(allocator, 0) catch unreachable; // idx low
    child_func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    child_func.code.append(allocator, 0) catch unreachable; // src high
    child_func.code.append(allocator, 0) catch unreachable; // src low
    child_func.constants.append(allocator, types.makeFixnum(99)) catch unreachable;
    child_func.arity = 1;
    child_func.locals_count = 1;

    // Create parent function that references child
    const parent_func = try gc.allocFunction();
    parent_func.code.append(allocator, @intFromEnum(types.OpCode.closure)) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable; // dst high
    parent_func.code.append(allocator, 0) catch unreachable; // dst low
    parent_func.code.append(allocator, 0) catch unreachable; // idx high
    parent_func.code.append(allocator, 0) catch unreachable; // idx low
    parent_func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable; // src high
    parent_func.code.append(allocator, 0) catch unreachable; // src low
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

test "bytecode validation rejects oversized function count header" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var w = Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);

    const hash: u64 = 0xA11CE;
    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, hash);
    try w.writeU32(allocator, @as(u32, @intCast(MAX_FUNCTIONS + 1)));
    try w.writeU32(allocator, 1);

    const path = "/tmp/kaappi_test_bad_func_count.sbc";
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch unreachable;
    defer _ = std.posix.system.close(fd);
    defer _ = std.posix.system.unlink(@ptrCast(path));

    var total: usize = 0;
    while (total < w.buf.items.len) {
        const wrote = std.posix.system.write(fd, w.buf.items.ptr + total, w.buf.items.len - total);
        if (wrote < 0) {
            if (std.posix.errno(wrote) == .INTR) continue;
            break;
        }
        if (wrote == 0) break;
        total += @as(usize, @intCast(wrote));
    }

    const loaded = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(loaded == null);
}

test "bytecode round-trip: vector pair bignum rational complex constants" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

    const vec_data = [_]Value{ types.makeFixnum(10), types.makeFixnum(20), types.makeFixnum(30) };
    const vec = try gc.allocVector(&vec_data);
    func.constants.append(allocator, vec) catch unreachable;

    const pair = try gc.allocPair(types.makeFixnum(1), types.makeFixnum(2));
    func.constants.append(allocator, pair) catch unreachable;

    const limbs = [_]u64{ 0xDEADBEEF, 0xCAFEBABE };
    const bn = try gc.allocBignumFromLimbs(&limbs, 2, true);
    func.constants.append(allocator, bn) catch unreachable;

    const rat_num = types.makeFixnum(22);
    const rat_den = types.makeFixnum(7);
    const rat = try gc.allocRational(rat_num, rat_den);
    func.constants.append(allocator, rat) catch unreachable;

    const cx = try gc.allocComplexEx(3.0, 4.0, false, false);
    func.constants.append(allocator, cx) catch unreachable;

    func.arity = 0;
    func.locals_count = 1;

    var funcs_arr = [_]*Function{func};
    const hash: u64 = 88888;
    const path = "/tmp/kaappi_test_advanced_consts.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, path);
    defer {
        _ = std.posix.system.unlink(@ptrCast(path));
    }

    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    const consts = loaded.funcs[0].constants.items;
    try std.testing.expectEqual(@as(usize, 5), consts.len);

    try std.testing.expect(types.isVector(consts[0]));
    const loaded_vec = types.toObject(consts[0]).as(types.Vector);
    try std.testing.expectEqual(@as(usize, 3), loaded_vec.data.len);
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(loaded_vec.data[0]));

    try std.testing.expect(types.isPair(consts[1]));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(consts[1])));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.cdr(consts[1])));

    try std.testing.expect(types.isBignum(consts[2]));

    try std.testing.expect(types.isRational(consts[3]));

    try std.testing.expect(types.isComplex(consts[4]));
    const loaded_cx = types.toObject(consts[4]).as(types.Complex);
    try std.testing.expectEqual(@as(f64, 3.0), loaded_cx.real);
    try std.testing.expectEqual(@as(f64, 4.0), loaded_cx.imag);
}

test "bytecode validation rejects invalid opcode" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var w = Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);

    const hash: u64 = 0xBADC0DE;
    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, hash);
    try w.writeU32(allocator, 1); // function count
    try w.writeU32(allocator, 1); // top-level count

    // Function header
    try w.writeU8(allocator, 0); // arity
    try w.writeU8(allocator, 1); // locals_count
    try w.writeU8(allocator, 0); // upvalue_count
    try w.writeU8(allocator, 0); // is_variadic
    try w.writeU16(allocator, 0); // name_len

    // Body: one invalid opcode byte
    try w.writeU32(allocator, 1); // code_len
    try w.writeU8(allocator, 0xFF);
    try w.writeU32(allocator, 0); // const_count

    const path = "/tmp/kaappi_test_invalid_opcode.sbc";
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch unreachable;
    defer _ = std.posix.system.close(fd);
    defer _ = std.posix.system.unlink(@ptrCast(path));

    var total: usize = 0;
    while (total < w.buf.items.len) {
        const wrote = std.posix.system.write(fd, w.buf.items.ptr + total, w.buf.items.len - total);
        if (wrote < 0) {
            if (std.posix.errno(wrote) == .INTR) continue;
            break;
        }
        if (wrote == 0) break;
        total += @as(usize, @intCast(wrote));
    }

    const loaded = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(loaded == null);
}
