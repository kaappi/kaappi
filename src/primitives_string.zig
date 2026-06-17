const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerString(vm: *vm_mod.VM) !void {
    // String construction
    try reg(vm, "string", &stringFn, .{ .variadic = 0 });
    try reg(vm, "make-string", &makeStringFn, .{ .variadic = 1 });

    // String access
    try reg(vm, "string-ref", &stringRefFn, .{ .exact = 2 });
    try reg(vm, "string-set!", &stringSetFn, .{ .exact = 3 });
    try reg(vm, "substring", &substringFn, .{ .exact = 3 });
    try reg(vm, "string-copy", &stringCopyFn, .{ .variadic = 1 });
    try reg(vm, "string-copy!", &stringCopyBangFn, .{ .variadic = 3 });
    try reg(vm, "string-fill!", &stringFillFn, .{ .exact = 2 });

    // Conversion
    try reg(vm, "string->list", &stringToListFn, .{ .variadic = 1 });
    try reg(vm, "list->string", &listToStringFn, .{ .exact = 1 });
    try reg(vm, "string->symbol", &stringToSymbolFn, .{ .exact = 1 });
    try reg(vm, "string->utf8", &stringToUtf8Fn, .{ .exact = 1 });
    try reg(vm, "utf8->string", &utf8ToStringFn, .{ .exact = 1 });
    try reg(vm, "string->vector", &stringToVectorFn, .{ .variadic = 1 });

    // Higher-order
    try reg(vm, "string-for-each", &stringForEachFn, .{ .variadic = 2 });
    try reg(vm, "string-map", &stringMapFn, .{ .variadic = 2 });

    // Comparison
    try reg(vm, "string<?", &stringLtFn, .{ .variadic = 2 });
    try reg(vm, "string<=?", &stringLeFn, .{ .variadic = 2 });
    try reg(vm, "string=?", &stringEqFn, .{ .variadic = 2 });
    try reg(vm, "string>=?", &stringGeFn, .{ .variadic = 2 });
    try reg(vm, "string>?", &stringGtFn, .{ .variadic = 2 });

    // Number/string conversion (also in arithmetic, but base library needs these)
    // number->string is registered in primitives_arithmetic.zig (handles bignums)
    // string->number registered in primitives_numeric.zig (supports radix parameter)

    // Char operations
    try reg(vm, "char->integer", &charToIntegerFn, .{ .exact = 1 });
    try reg(vm, "integer->char", &integerToCharFn, .{ .exact = 1 });
    try reg(vm, "char<?", &charLtFn, .{ .variadic = 2 });
    try reg(vm, "char<=?", &charLeFn, .{ .variadic = 2 });
    try reg(vm, "char=?", &charEqFn, .{ .variadic = 2 });
    try reg(vm, "char>=?", &charGeFn, .{ .variadic = 2 });
    try reg(vm, "char>?", &charGtFn, .{ .variadic = 2 });

    // SRFI-13 string library
    try reg(vm, "string-contains", &stringContainsFn, .{ .exact = 2 });
    try reg(vm, "string-prefix?", &stringPrefixPFn, .{ .exact = 2 });
    try reg(vm, "string-suffix?", &stringSuffixPFn, .{ .exact = 2 });
    try reg(vm, "string-trim", &stringTrimFn, .{ .variadic = 1 });
    try reg(vm, "string-trim-right", &stringTrimRightFn, .{ .variadic = 1 });
    try reg(vm, "string-trim-both", &stringTrimBothFn, .{ .variadic = 1 });
    try reg(vm, "string-index", &stringIndexFn, .{ .exact = 2 });
    try reg(vm, "string-count", &stringCountFn, .{ .exact = 2 });
    try reg(vm, "string-split", &stringSplitFn, .{ .exact = 2 });
    try reg(vm, "string-join", &stringJoinFn, .{ .variadic = 1 });
    try reg(vm, "string-concatenate", &stringConcatenateFn, .{ .exact = 1 });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn getStringSlice(v: Value) PrimitiveError![]const u8 {
    if (!types.isString(v)) return PrimitiveError.TypeError;
    const str = types.toObject(v).as(types.SchemeString);
    return str.data[0..str.len];
}

// ---------------------------------------------------------------------------
// UTF-8 Helpers for codepoint-based indexing
// ---------------------------------------------------------------------------

/// Count the number of Unicode codepoints in a UTF-8 byte sequence.
fn utf8CodepointCount(data: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        const len = std.unicode.utf8ByteSequenceLength(data[i]) catch 1;
        i += len;
        count += 1;
    }
    return count;
}

/// Convert a codepoint index to a byte offset in a UTF-8 string.
/// Returns null if the index is out of range.
fn utf8IndexToByteOffset(data: []const u8, char_index: usize) ?usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < data.len and count < char_index) {
        const len = std.unicode.utf8ByteSequenceLength(data[i]) catch 1;
        i += len;
        count += 1;
    }
    if (count == char_index) return i;
    return null;
}

/// Decode the UTF-8 codepoint at the given byte offset.
fn utf8DecodeAt(data: []const u8, byte_offset: usize) ?u21 {
    if (byte_offset >= data.len) return null;
    const len = std.unicode.utf8ByteSequenceLength(data[byte_offset]) catch return null;
    if (byte_offset + len > data.len) return null;
    return std.unicode.utf8Decode(data[byte_offset .. byte_offset + len]) catch null;
}

/// Get the byte length of the codepoint at the given byte offset.
fn utf8ByteLenAt(data: []const u8, byte_offset: usize) usize {
    if (byte_offset >= data.len) return 0;
    return std.unicode.utf8ByteSequenceLength(data[byte_offset]) catch 1;
}

// ---------------------------------------------------------------------------
// (string ch1 ch2 ...) — create string from chars
// ---------------------------------------------------------------------------

fn stringFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    // Calculate total UTF-8 length
    var total: usize = 0;
    for (args) |a| {
        if (!types.isChar(a)) return PrimitiveError.TypeError;
        const cp = types.toChar(a);
        total += std.unicode.utf8CodepointSequenceLength(cp) catch return PrimitiveError.TypeError;
    }
    const buf = gc.allocator.alloc(u8, total) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    for (args) |a| {
        const cp = types.toChar(a);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return PrimitiveError.TypeError;
        @memcpy(buf[pos .. pos + n], tmp[0..n]);
        pos += n;
    }
    return gc.allocString(buf[0..pos]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (make-string k) or (make-string k ch)
// ---------------------------------------------------------------------------

fn makeStringFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[0]);
    if (k < 0) return PrimitiveError.TypeError;
    const count: usize = @intCast(k);
    const fill_cp: u21 = if (args.len > 1) blk: {
        if (!types.isChar(args[1])) return PrimitiveError.TypeError;
        break :blk types.toChar(args[1]);
    } else ' ';
    // Encode the fill character to UTF-8
    var fill_buf: [4]u8 = undefined;
    const fill_len = std.unicode.utf8Encode(fill_cp, &fill_buf) catch return PrimitiveError.TypeError;
    const total_bytes = count * fill_len;
    const buf = gc.allocator.alloc(u8, total_bytes) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    for (0..count) |i| {
        @memcpy(buf[i * fill_len .. (i + 1) * fill_len], fill_buf[0..fill_len]);
    }
    return gc.allocString(buf) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-ref str k) — char at byte index
// ---------------------------------------------------------------------------

fn stringRefFn(args: []const Value) PrimitiveError!Value {
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0) return PrimitiveError.TypeError;
    const byte_off = utf8IndexToByteOffset(data, @intCast(k)) orelse return PrimitiveError.TypeError;
    const cp = utf8DecodeAt(data, byte_off) orelse return PrimitiveError.TypeError;
    return types.makeChar(cp);
}

// ---------------------------------------------------------------------------
// (string-set! str k ch) — mutate char at byte index
// ---------------------------------------------------------------------------

fn stringSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    if (!types.isChar(args[2])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    if (str.immutable) return PrimitiveError.TypeError;
    const data = str.data[0..str.len];
    const k = types.toFixnum(args[1]);
    if (k < 0) return PrimitiveError.TypeError;
    const char_idx: usize = @intCast(k);
    const byte_start = utf8IndexToByteOffset(data, char_idx) orelse return PrimitiveError.TypeError;
    const old_cp_len = utf8ByteLenAt(data, byte_start);
    if (byte_start + old_cp_len > data.len) return PrimitiveError.TypeError;

    const new_cp = types.toChar(args[2]);
    var new_cp_buf: [4]u8 = undefined;
    const new_cp_len = std.unicode.utf8Encode(new_cp, &new_cp_buf) catch return PrimitiveError.TypeError;

    if (new_cp_len == old_cp_len) {
        // Same byte width: replace in-place
        @memcpy(str.data[byte_start .. byte_start + new_cp_len], new_cp_buf[0..new_cp_len]);
    } else {
        // Different byte width: rebuild the string buffer
        const new_total = data.len - old_cp_len + new_cp_len;
        const new_data = gc.allocator.alloc(u8, new_total) catch return PrimitiveError.OutOfMemory;
        @memcpy(new_data[0..byte_start], data[0..byte_start]);
        @memcpy(new_data[byte_start .. byte_start + new_cp_len], new_cp_buf[0..new_cp_len]);
        @memcpy(new_data[byte_start + new_cp_len .. new_total], data[byte_start + old_cp_len .. data.len]);
        gc.allocator.free(str.data);
        str.data = new_data;
        str.len = new_total;
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (substring str start end)
// ---------------------------------------------------------------------------

fn substringFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1]) or !types.isFixnum(args[2])) return PrimitiveError.TypeError;
    const start_i = types.toFixnum(args[1]);
    const end_i = types.toFixnum(args[2]);
    if (start_i < 0 or end_i < 0) return PrimitiveError.TypeError;
    const start_cp: usize = @intCast(start_i);
    const end_cp: usize = @intCast(end_i);
    if (start_cp > end_cp) return PrimitiveError.TypeError;
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return PrimitiveError.TypeError;
    const byte_end = utf8IndexToByteOffset(data, end_cp) orelse return PrimitiveError.TypeError;
    return gc.allocString(data[byte_start..byte_end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-copy str) or (string-copy str start) or (string-copy str start end)
// ---------------------------------------------------------------------------

fn stringCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    const cp_count = utf8CodepointCount(data);
    var start_cp: usize = 0;
    var end_cp: usize = cp_count;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[1]);
        if (s < 0 or @as(usize, @intCast(s)) > cp_count) return PrimitiveError.TypeError;
        start_cp = @intCast(s);
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[2]);
        if (e < 0 or @as(usize, @intCast(e)) > cp_count) return PrimitiveError.TypeError;
        end_cp = @intCast(e);
    }
    if (start_cp > end_cp) return PrimitiveError.TypeError;
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return PrimitiveError.TypeError;
    const byte_end = utf8IndexToByteOffset(data, end_cp) orelse return PrimitiveError.TypeError;
    return gc.allocString(data[byte_start..byte_end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-copy! to at from) or with start/end
// ---------------------------------------------------------------------------

fn stringCopyBangFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const to_str = types.toObject(args[0]).as(types.SchemeString);
    if (to_str.immutable) return PrimitiveError.TypeError;
    const to_data = to_str.data[0..to_str.len];
    const to_cp_count = utf8CodepointCount(to_data);
    const at_val = types.toFixnum(args[1]);
    if (at_val < 0) return PrimitiveError.TypeError;
    const at_cp: usize = @intCast(at_val);
    const from_data = try getStringSlice(args[2]);
    const from_cp_count = utf8CodepointCount(from_data);

    var start_cp: usize = 0;
    var end_cp: usize = from_cp_count;
    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[3]);
        if (s < 0 or @as(usize, @intCast(s)) > from_cp_count) return PrimitiveError.TypeError;
        start_cp = @intCast(s);
    }
    if (args.len > 4) {
        if (!types.isFixnum(args[4])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[4]);
        if (e < 0 or @as(usize, @intCast(e)) > from_cp_count) return PrimitiveError.TypeError;
        end_cp = @intCast(e);
    }
    if (start_cp > end_cp) return PrimitiveError.TypeError;
    const copy_cp_count = end_cp - start_cp;
    if (at_cp + copy_cp_count > to_cp_count) return PrimitiveError.TypeError;

    // Convert codepoint indices to byte offsets
    const from_byte_start = utf8IndexToByteOffset(from_data, start_cp) orelse return PrimitiveError.TypeError;
    const from_byte_end = utf8IndexToByteOffset(from_data, end_cp) orelse return PrimitiveError.TypeError;
    const to_byte_start = utf8IndexToByteOffset(to_data, at_cp) orelse return PrimitiveError.TypeError;
    const to_byte_end = utf8IndexToByteOffset(to_data, at_cp + copy_cp_count) orelse return PrimitiveError.TypeError;

    const src_bytes = from_data[from_byte_start..from_byte_end];
    const dst_old_len = to_byte_end - to_byte_start;

    if (src_bytes.len == dst_old_len) {
        // Same byte length: copy in-place
        @memcpy(to_str.data[to_byte_start..to_byte_end], src_bytes);
    } else {
        // Different byte lengths: rebuild target string
        const new_total = to_data.len - dst_old_len + src_bytes.len;
        const new_data = gc.allocator.alloc(u8, new_total) catch return PrimitiveError.OutOfMemory;
        @memcpy(new_data[0..to_byte_start], to_data[0..to_byte_start]);
        @memcpy(new_data[to_byte_start .. to_byte_start + src_bytes.len], src_bytes);
        @memcpy(new_data[to_byte_start + src_bytes.len .. new_total], to_data[to_byte_end..to_data.len]);
        gc.allocator.free(to_str.data);
        to_str.data = new_data;
        to_str.len = new_total;
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (string-fill! str ch)
// ---------------------------------------------------------------------------

fn stringFillFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    if (!types.isChar(args[1])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    if (str.immutable) return PrimitiveError.TypeError;
    const data = str.data[0..str.len];
    const cp = types.toChar(args[1]);
    var fill_buf: [4]u8 = undefined;
    const fill_len = std.unicode.utf8Encode(cp, &fill_buf) catch return PrimitiveError.TypeError;
    const char_count = utf8CodepointCount(data);
    const new_total = char_count * fill_len;
    const new_data = gc.allocator.alloc(u8, new_total) catch return PrimitiveError.OutOfMemory;
    for (0..char_count) |i| {
        @memcpy(new_data[i * fill_len .. (i + 1) * fill_len], fill_buf[0..fill_len]);
    }
    gc.allocator.free(str.data);
    str.data = new_data;
    str.len = new_total;
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (string->list str) or (string->list str start end)
// ---------------------------------------------------------------------------

fn stringToListFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    const cp_count = utf8CodepointCount(data);
    var start_cp: usize = 0;
    var end_cp: usize = cp_count;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[1]);
        if (s < 0 or @as(usize, @intCast(s)) > cp_count) return PrimitiveError.TypeError;
        start_cp = @intCast(s);
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[2]);
        if (e < 0 or @as(usize, @intCast(e)) > cp_count) return PrimitiveError.TypeError;
        end_cp = @intCast(e);
    }
    if (start_cp > end_cp) return PrimitiveError.TypeError;
    // Collect codepoints in the range
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return PrimitiveError.TypeError;
    const range_count = end_cp - start_cp;
    // Build list from back to front; first collect codepoints
    var cps_buf: [4096]u21 = undefined;
    var cps = if (range_count <= 4096) cps_buf[0..range_count] else (gc.allocator.alloc(u21, range_count) catch return PrimitiveError.OutOfMemory);
    defer if (range_count > 4096) gc.allocator.free(cps);
    var byte_i = byte_start;
    for (0..range_count) |idx| {
        cps[idx] = utf8DecodeAt(data, byte_i) orelse return PrimitiveError.TypeError;
        byte_i += utf8ByteLenAt(data, byte_i);
    }
    // Build list from back
    var result: Value = types.NIL;
    var idx = range_count;
    while (idx > 0) {
        idx -= 1;
        result = gc.allocPair(types.makeChar(cps[idx]), result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// ---------------------------------------------------------------------------
// (list->string lst)
// ---------------------------------------------------------------------------

fn listToStringFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    // Count chars and calculate utf8 length
    var total: usize = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        if (!types.isChar(elem)) return PrimitiveError.TypeError;
        const cp = types.toChar(elem);
        total += std.unicode.utf8CodepointSequenceLength(cp) catch return PrimitiveError.TypeError;
        current = types.cdr(current);
    }
    const buf = gc.allocator.alloc(u8, total) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    current = args[0];
    while (current != types.NIL) {
        const cp = types.toChar(types.car(current));
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return PrimitiveError.TypeError;
        @memcpy(buf[pos .. pos + n], tmp[0..n]);
        pos += n;
        current = types.cdr(current);
    }
    return gc.allocString(buf[0..pos]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string->symbol str)
// ---------------------------------------------------------------------------

fn stringToSymbolFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    return gc.allocSymbol(data) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string->vector str) or (string->vector str start) or (string->vector str start end)
// ---------------------------------------------------------------------------

fn stringToVectorFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const data = str.data[0..str.len];
    const cp_count = utf8CodepointCount(data);
    var start_cp: usize = 0;
    var end_cp: usize = cp_count;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[1]);
        if (s < 0 or @as(usize, @intCast(s)) > cp_count) return PrimitiveError.TypeError;
        start_cp = @intCast(s);
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[2]);
        if (e < 0 or @as(usize, @intCast(e)) > cp_count) return PrimitiveError.TypeError;
        end_cp = @intCast(e);
    }
    if (start_cp > end_cp) return PrimitiveError.TypeError;
    const range_count = end_cp - start_cp;
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return PrimitiveError.TypeError;
    const vec_data = gc.allocator.alloc(Value, range_count) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(vec_data);
    var byte_i = byte_start;
    for (0..range_count) |idx| {
        const cp = utf8DecodeAt(data, byte_i) orelse return PrimitiveError.TypeError;
        vec_data[idx] = types.makeChar(cp);
        byte_i += utf8ByteLenAt(data, byte_i);
    }
    return gc.allocVector(vec_data[0..range_count]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string->utf8 str)
// ---------------------------------------------------------------------------

fn stringToUtf8Fn(args: []const Value) PrimitiveError!Value {
    // Bytevector not fully supported yet — return error
    _ = try getStringSlice(args[0]);
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// (utf8->string bv)
// ---------------------------------------------------------------------------

fn utf8ToStringFn(args: []const Value) PrimitiveError!Value {
    // Bytevector not fully supported yet — return error
    _ = args;
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// (string-for-each proc str1 ...)
// ---------------------------------------------------------------------------

fn stringForEachFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    const str_count = args.len - 1;
    if (str_count == 0) return PrimitiveError.ArityMismatch;

    // Find minimum codepoint length
    var min_cp_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        const data = try getStringSlice(a);
        const cp_len = utf8CodepointCount(data);
        if (cp_len < min_cp_len) min_cp_len = cp_len;
    }

    // Track byte offsets for each string
    var byte_offsets: [256]usize = undefined;
    for (0..str_count) |si| {
        byte_offsets[si] = 0;
    }

    var call_args: [256]Value = undefined;
    for (0..min_cp_len) |_| {
        for (0..str_count) |si| {
            const data = try getStringSlice(args[1 + si]);
            const cp = utf8DecodeAt(data, byte_offsets[si]) orelse return PrimitiveError.TypeError;
            call_args[si] = types.makeChar(cp);
            byte_offsets[si] += utf8ByteLenAt(data, byte_offsets[si]);
        }
        _ = vm.callWithArgs(proc, call_args[0..str_count]) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (string-map proc str1 ...)
// ---------------------------------------------------------------------------

fn stringMapFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    const str_count = args.len - 1;
    if (str_count == 0) return PrimitiveError.ArityMismatch;

    // Find minimum codepoint length
    var min_cp_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        const data = try getStringSlice(a);
        const cp_len = utf8CodepointCount(data);
        if (cp_len < min_cp_len) min_cp_len = cp_len;
    }

    // Track byte offsets for each string
    var byte_offsets: [256]usize = undefined;
    for (0..str_count) |si| {
        byte_offsets[si] = 0;
    }

    // Collect result chars
    var result_buf: std.ArrayList(u8) = .empty;
    defer result_buf.deinit(gc.allocator);

    var call_args: [256]Value = undefined;
    for (0..min_cp_len) |_| {
        for (0..str_count) |si| {
            const data = try getStringSlice(args[1 + si]);
            const cp = utf8DecodeAt(data, byte_offsets[si]) orelse return PrimitiveError.TypeError;
            call_args[si] = types.makeChar(cp);
            byte_offsets[si] += utf8ByteLenAt(data, byte_offsets[si]);
        }
        const result = vm.callWithArgs(proc, call_args[0..str_count]) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        if (!types.isChar(result)) return PrimitiveError.TypeError;
        const cp = types.toChar(result);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return PrimitiveError.TypeError;
        result_buf.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    return gc.allocString(result_buf.items) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// String comparison
// ---------------------------------------------------------------------------

fn compareStrings(args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try getStringSlice(args[i]);
        const b = try getStringSlice(args[i + 1]);
        const order = std.mem.order(u8, a, b);
        const pass = switch (cmp) {
            .lt => order == .lt,
            .le => order != .gt,
            .eq => order == .eq,
            .ge => order != .lt,
            .gt => order == .gt,
        };
        if (!pass) return types.FALSE;
    }
    return types.TRUE;
}

fn stringLtFn(args: []const Value) PrimitiveError!Value {
    return compareStrings(args, .lt);
}

fn stringLeFn(args: []const Value) PrimitiveError!Value {
    return compareStrings(args, .le);
}

fn stringEqFn(args: []const Value) PrimitiveError!Value {
    return compareStrings(args, .eq);
}

fn stringGeFn(args: []const Value) PrimitiveError!Value {
    return compareStrings(args, .ge);
}

fn stringGtFn(args: []const Value) PrimitiveError!Value {
    return compareStrings(args, .gt);
}

// ---------------------------------------------------------------------------
// Number/string conversion (duplicated here for the string module registration)
// These delegate to primitives_arithmetic but we need them accessible
// ---------------------------------------------------------------------------

fn numberToStringFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (types.isFixnum(args[0])) {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(args[0])}) catch return PrimitiveError.OutOfMemory;
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (std.math.isNan(f)) return gc.allocString("+nan.0") catch return PrimitiveError.OutOfMemory;
        if (std.math.isInf(f)) {
            if (f > 0) return gc.allocString("+inf.0") catch return PrimitiveError.OutOfMemory;
            return gc.allocString("-inf.0") catch return PrimitiveError.OutOfMemory;
        }
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return PrimitiveError.OutOfMemory;
        var needs_dot = true;
        for (s) |c| {
            if (c == '.' or c == 'e' or c == 'E') {
                needs_dot = false;
                break;
            }
        }
        if (needs_dot) {
            const s2 = std.fmt.bufPrint(buf[s.len..], ".0", .{}) catch return PrimitiveError.OutOfMemory;
            return gc.allocString(buf[0 .. s.len + s2.len]) catch return PrimitiveError.OutOfMemory;
        }
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    return PrimitiveError.TypeError;
}

fn stringToNumberFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const s = try getStringSlice(args[0]);

    if (std.mem.eql(u8, s, "+inf.0")) return gc.allocFlonum(std.math.inf(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "-inf.0")) return gc.allocFlonum(-std.math.inf(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "+nan.0")) return gc.allocFlonum(std.math.nan(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "-nan.0")) return gc.allocFlonum(std.math.nan(f64)) catch return PrimitiveError.OutOfMemory;

    // Try rational N/D
    if (std.mem.indexOfScalar(u8, s, '/')) |slash_pos| {
        if (slash_pos > 0 and slash_pos + 1 < s.len) {
            const num_str = s[0..slash_pos];
            const den_str = s[slash_pos + 1 ..];
            if (std.fmt.parseInt(i64, num_str, 10)) |num| {
                if (std.fmt.parseInt(i64, den_str, 10)) |den| {
                    if (den == 0) return types.FALSE;
                    const arith = @import("primitives_arithmetic.zig");
                    return arith.makeRationalFromReader(gc, num, den) catch return PrimitiveError.OutOfMemory;
                } else |_| {}
            } else |_| {}
        }
    }

    if (std.fmt.parseInt(i64, s, 10)) |n| {
        return types.makeFixnum(n);
    } else |_| {}

    if (std.fmt.parseFloat(f64, s)) |f| {
        return gc.allocFlonum(f) catch return PrimitiveError.OutOfMemory;
    } else |_| {}

    return types.FALSE;
}

// ---------------------------------------------------------------------------
// Char operations
// ---------------------------------------------------------------------------

fn charToIntegerFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return types.makeFixnum(@intCast(types.toChar(args[0])));
}

fn integerToCharFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const n = types.toFixnum(args[0]);
    if (n < 0 or n > 0x10FFFF) return PrimitiveError.TypeError;
    return types.makeChar(@intCast(n));
}

fn compareChars(args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isChar(args[i]) or !types.isChar(args[i + 1])) return PrimitiveError.TypeError;
        const a = types.toChar(args[i]);
        const b = types.toChar(args[i + 1]);
        const pass = switch (cmp) {
            .lt => a < b,
            .le => a <= b,
            .eq => a == b,
            .ge => a >= b,
            .gt => a > b,
        };
        if (!pass) return types.FALSE;
    }
    return types.TRUE;
}

fn charLtFn(args: []const Value) PrimitiveError!Value {
    return compareChars(args, .lt);
}

fn charLeFn(args: []const Value) PrimitiveError!Value {
    return compareChars(args, .le);
}

fn charEqFn(args: []const Value) PrimitiveError!Value {
    return compareChars(args, .eq);
}

fn charGeFn(args: []const Value) PrimitiveError!Value {
    return compareChars(args, .ge);
}

fn charGtFn(args: []const Value) PrimitiveError!Value {
    return compareChars(args, .gt);
}

// ---------------------------------------------------------------------------
// SRFI-13 String Library
// ---------------------------------------------------------------------------

// (string-contains s1 s2) — index of s2 in s1, or #f
fn stringContainsFn(args: []const Value) PrimitiveError!Value {
    const s1 = try getStringSlice(args[0]);
    const s2 = try getStringSlice(args[1]);
    if (s2.len == 0) return types.makeFixnum(0);
    if (s2.len > s1.len) return types.FALSE;

    // Find byte position, then convert to codepoint index
    if (std.mem.indexOf(u8, s1, s2)) |byte_pos| {
        // Count codepoints up to byte_pos
        var cp_idx: usize = 0;
        var i: usize = 0;
        while (i < byte_pos) {
            const len = std.unicode.utf8ByteSequenceLength(s1[i]) catch 1;
            i += len;
            cp_idx += 1;
        }
        return types.makeFixnum(@intCast(cp_idx));
    }
    return types.FALSE;
}

// (string-prefix? prefix s) — boolean
fn stringPrefixPFn(args: []const Value) PrimitiveError!Value {
    const prefix = try getStringSlice(args[0]);
    const s = try getStringSlice(args[1]);
    return if (std.mem.startsWith(u8, s, prefix)) types.TRUE else types.FALSE;
}

// (string-suffix? suffix s) — boolean
fn stringSuffixPFn(args: []const Value) PrimitiveError!Value {
    const suffix = try getStringSlice(args[0]);
    const s = try getStringSlice(args[1]);
    return if (std.mem.endsWith(u8, s, suffix)) types.TRUE else types.FALSE;
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// (string-trim s) — remove whitespace from start
fn stringTrimFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    var start: usize = 0;
    while (start < data.len and isWhitespace(data[start])) {
        start += 1;
    }
    return gc.allocString(data[start..]) catch return PrimitiveError.OutOfMemory;
}

// (string-trim-right s) — remove whitespace from end
fn stringTrimRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    var end: usize = data.len;
    while (end > 0 and isWhitespace(data[end - 1])) {
        end -= 1;
    }
    return gc.allocString(data[0..end]) catch return PrimitiveError.OutOfMemory;
}

// (string-trim-both s) — both sides
fn stringTrimBothFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    var start: usize = 0;
    while (start < data.len and isWhitespace(data[start])) {
        start += 1;
    }
    var end: usize = data.len;
    while (end > start and isWhitespace(data[end - 1])) {
        end -= 1;
    }
    return gc.allocString(data[start..end]) catch return PrimitiveError.OutOfMemory;
}

// (string-index s pred) — index of first char satisfying pred (needs VM)
fn stringIndexFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const data = try getStringSlice(args[0]);
    const pred = args[1];

    var byte_i: usize = 0;
    var cp_idx: usize = 0;
    while (byte_i < data.len) {
        const cp = utf8DecodeAt(data, byte_i) orelse return PrimitiveError.TypeError;
        const char_val = types.makeChar(cp);
        const call_args = [1]Value{char_val};
        const result = vm.callWithArgs(pred, &call_args) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        if (types.isTruthy(result)) return types.makeFixnum(@intCast(cp_idx));
        byte_i += utf8ByteLenAt(data, byte_i);
        cp_idx += 1;
    }
    return types.FALSE;
}

// (string-count s pred) — count chars satisfying pred (needs VM)
fn stringCountFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const data = try getStringSlice(args[0]);
    const pred = args[1];

    var byte_i: usize = 0;
    var count: i64 = 0;
    while (byte_i < data.len) {
        const cp = utf8DecodeAt(data, byte_i) orelse return PrimitiveError.TypeError;
        const char_val = types.makeChar(cp);
        const call_args = [1]Value{char_val};
        const result = vm.callWithArgs(pred, &call_args) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        if (types.isTruthy(result)) count += 1;
        byte_i += utf8ByteLenAt(data, byte_i);
    }
    return types.makeFixnum(count);
}

// (string-split s delimiter) -> list of strings
fn stringSplitFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    const delim = try getStringSlice(args[1]);

    if (delim.len == 0) {
        // Split into individual characters
        var result: Value = types.NIL;
        var byte_i = data.len;
        while (byte_i > 0) {
            // Find start of previous codepoint
            var start = byte_i - 1;
            while (start > 0 and (data[start] & 0xC0) == 0x80) {
                start -= 1;
            }
            const s = gc.allocString(data[start..byte_i]) catch return PrimitiveError.OutOfMemory;
            result = gc.allocPair(s, result) catch return PrimitiveError.OutOfMemory;
            byte_i = start;
        }
        return result;
    }

    // Collect parts
    var parts: std.ArrayList(Value) = .empty;
    defer parts.deinit(gc.allocator);

    var pos: usize = 0;
    while (pos <= data.len) {
        if (std.mem.indexOfPos(u8, data, pos, delim)) |found| {
            const s = gc.allocString(data[pos..found]) catch return PrimitiveError.OutOfMemory;
            parts.append(gc.allocator, s) catch return PrimitiveError.OutOfMemory;
            pos = found + delim.len;
        } else {
            const s = gc.allocString(data[pos..]) catch return PrimitiveError.OutOfMemory;
            parts.append(gc.allocator, s) catch return PrimitiveError.OutOfMemory;
            break;
        }
    }

    // Build result list
    var result: Value = types.NIL;
    var i = parts.items.len;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(parts.items[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// (string-join list-of-strings) or (string-join list-of-strings delimiter)
fn stringJoinFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const delim: []const u8 = if (args.len > 1)
        (try getStringSlice(args[1]))
    else
        "";

    // Calculate total length
    var total: usize = 0;
    var count: usize = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const s = try getStringSlice(types.car(current));
        total += s.len;
        count += 1;
        current = types.cdr(current);
    }
    if (count == 0) return gc.allocString("") catch return PrimitiveError.OutOfMemory;
    total += (count - 1) * delim.len;

    const buf = gc.allocator.alloc(u8, total) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    var first = true;
    current = args[0];
    while (current != types.NIL) {
        if (!first and delim.len > 0) {
            @memcpy(buf[pos .. pos + delim.len], delim);
            pos += delim.len;
        }
        first = false;
        const s = try getStringSlice(types.car(current));
        @memcpy(buf[pos .. pos + s.len], s);
        pos += s.len;
        current = types.cdr(current);
    }
    return gc.allocString(buf) catch return PrimitiveError.OutOfMemory;
}

// (string-concatenate list-of-strings) -> string
fn stringConcatenateFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    // Calculate total length
    var total: usize = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const s = try getStringSlice(types.car(current));
        total += s.len;
        current = types.cdr(current);
    }
    if (total == 0) return gc.allocString("") catch return PrimitiveError.OutOfMemory;

    const buf = gc.allocator.alloc(u8, total) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    current = args[0];
    while (current != types.NIL) {
        const s = try getStringSlice(types.car(current));
        @memcpy(buf[pos .. pos + s.len], s);
        pos += s.len;
        current = types.cdr(current);
    }
    return gc.allocString(buf) catch return PrimitiveError.OutOfMemory;
}
