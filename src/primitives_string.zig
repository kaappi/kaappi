const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "string", .func = &stringFn, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "make-string", .func = &makeStringFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "string-ref", .func = &stringRefFn, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string-set!", .func = &stringSetFn, .arity = .{ .exact = 3 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "substring", .func = &substringFn, .arity = .{ .exact = 3 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string-copy", .func = &stringCopyFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string-copy!", .func = &stringCopyBangFn, .arity = .{ .variadic = 3 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "string-fill!", .func = &stringFillFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "string->list", .func = &stringToListFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "list->string", .func = &listToStringFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "string->vector", .func = &stringToVectorFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .srfi_133 }) },
    .{ .name = "string-for-each", .func = &stringForEachFn, .arity = .{ .variadic = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "string-map", .func = &stringMapFn, .arity = .{ .variadic = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "string<?", .func = &stringLtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string<=?", .func = &stringLeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string=?", .func = &stringEqFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string>=?", .func = &stringGeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string>?", .func = &stringGtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "char->integer", .func = &charToIntegerFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "integer->char", .func = &integerToCharFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "char<?", .func = &charLtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "char<=?", .func = &charLeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "char=?", .func = &charEqFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "char>=?", .func = &charGeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "char>?", .func = &charGtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

pub fn getStringSlice(v: Value) PrimitiveError![]const u8 {
    if (!types.isString(v)) return primitives.typeError("string operation", "string", v);
    const str = types.toObject(v).as(types.SchemeString);
    return str.data[0..str.len];
}

// ---------------------------------------------------------------------------
// UTF-8 Helpers for codepoint-based indexing
// ---------------------------------------------------------------------------

/// Count the number of Unicode codepoints in a UTF-8 byte sequence.
pub fn utf8CodepointCount(data: []const u8) usize {
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
pub fn utf8IndexToByteOffset(data: []const u8, char_index: usize) ?usize {
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
pub fn utf8DecodeAt(data: []const u8, byte_offset: usize) ?u21 {
    if (byte_offset >= data.len) return null;
    const len = std.unicode.utf8ByteSequenceLength(data[byte_offset]) catch return null;
    if (byte_offset + len > data.len) return null;
    return std.unicode.utf8Decode(data[byte_offset .. byte_offset + len]) catch null;
}

/// Get the byte length of the codepoint at the given byte offset.
pub fn utf8ByteLenAt(data: []const u8, byte_offset: usize) usize {
    if (byte_offset >= data.len) return 0;
    return std.unicode.utf8ByteSequenceLength(data[byte_offset]) catch 1;
}

// ---------------------------------------------------------------------------
// (string ch1 ch2 ...) — create string from chars
// ---------------------------------------------------------------------------

fn stringFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    // Calculate total UTF-8 length
    var total: usize = 0;
    for (args) |a| {
        if (!types.isChar(a)) return primitives.typeError("string", "character", a);
        const cp = types.toChar(a);
        total += std.unicode.utf8CodepointSequenceLength(cp) catch return primitives.typeError("string", "valid character", a);
    }
    const buf = gc.allocator.alloc(u8, total) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    for (args) |a| {
        const cp = types.toChar(a);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return primitives.typeError("string", "valid character", a);
        @memcpy(buf[pos .. pos + n], tmp[0..n]);
        pos += n;
    }
    return gc.allocString(buf[0..pos]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (make-string k) or (make-string k ch)
// ---------------------------------------------------------------------------

fn makeStringFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return primitives.typeError("make-string", "exact integer", args[0]);
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("make-string", "non-negative integer", args[0]);
    const count: usize = @intCast(k);
    const fill_cp: u21 = if (args.len > 1) blk: {
        if (!types.isChar(args[1])) return primitives.typeError("make-string", "character", args[1]);
        break :blk types.toChar(args[1]);
    } else ' ';
    // Encode the fill character to UTF-8
    var fill_buf: [4]u8 = undefined;
    const fill_len = std.unicode.utf8Encode(fill_cp, &fill_buf) catch return primitives.typeError("make-string", "valid character", args[1]);
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
    if (!types.isFixnum(args[1])) return primitives.typeError("string-ref", "exact integer", args[1]);
    const k = types.toFixnum(args[1]);
    const str_len = utf8CodepointCount(data);
    if (k < 0 or @as(usize, @intCast(k)) >= str_len) return primitives.indexError("string-ref", k, str_len);
    const byte_off = utf8IndexToByteOffset(data, @intCast(k)) orelse return primitives.indexError("string-ref", k, str_len);
    const cp = utf8DecodeAt(data, byte_off) orelse return primitives.typeError("string-ref", "valid UTF-8 string", args[0]);
    return types.makeChar(cp);
}

// ---------------------------------------------------------------------------
// (string-set! str k ch) — mutate char at byte index
// ---------------------------------------------------------------------------

fn stringSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string-set!", "string", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-set!", "exact integer", args[1]);
    if (!types.isChar(args[2])) return primitives.typeError("string-set!", "character", args[2]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    if (str.immutable) return primitives.typeError("string-set!", "mutable string", args[0]);
    const data = str.data[0..str.len];
    const k = types.toFixnum(args[1]);
    const str_len = utf8CodepointCount(data);
    if (k < 0 or @as(usize, @intCast(k)) >= str_len) return primitives.indexError("string-set!", k, str_len);
    const char_idx: usize = @intCast(k);
    const byte_start = utf8IndexToByteOffset(data, char_idx) orelse return primitives.indexError("string-set!", k, str_len);
    const old_cp_len = utf8ByteLenAt(data, byte_start);
    if (old_cp_len == 0) return primitives.indexError("string-set!", k, str_len);
    if (byte_start + old_cp_len > data.len) return primitives.typeError("string-set!", "valid UTF-8 string", args[0]);

    const new_cp = types.toChar(args[2]);
    var new_cp_buf: [4]u8 = undefined;
    const new_cp_len = std.unicode.utf8Encode(new_cp, &new_cp_buf) catch return primitives.typeError("string-set!", "valid character", args[2]);

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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("substring", "exact integer", args[1]);
    if (!types.isFixnum(args[2])) return primitives.typeError("substring", "exact integer", args[2]);
    const start_i = types.toFixnum(args[1]);
    const end_i = types.toFixnum(args[2]);
    const str_len = utf8CodepointCount(data);
    if (start_i < 0) return primitives.indexError("substring", start_i, str_len);
    if (end_i < 0) return primitives.indexError("substring", end_i, str_len);
    const start_cp: usize = @intCast(start_i);
    const end_cp: usize = @intCast(end_i);
    if (start_cp > end_cp) return primitives.indexError("substring", end_i, str_len);
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return primitives.indexError("substring", start_i, str_len);
    const byte_end = utf8IndexToByteOffset(data, end_cp) orelse return primitives.indexError("substring", end_i, str_len);
    return gc.allocString(data[byte_start..byte_end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-copy str) or (string-copy str start) or (string-copy str start end)
// ---------------------------------------------------------------------------

fn stringCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    const cp_count = utf8CodepointCount(data);
    const range = try primitives.parseOptionalRange(args, 1, cp_count, "string-copy");
    const start_cp = range.start;
    const end_cp = range.end;
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return primitives.typeError("string-copy", "valid index", args[1]);
    const byte_end = utf8IndexToByteOffset(data, end_cp) orelse return primitives.typeError("string-copy", "valid index", args[2]);
    return gc.allocString(data[byte_start..byte_end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-copy! to at from) or with start/end
// ---------------------------------------------------------------------------

fn stringCopyBangFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string-copy!", "string", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-copy!", "exact integer", args[1]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const to_str = types.toObject(args[0]).as(types.SchemeString);
    if (to_str.immutable) return primitives.typeError("string-copy!", "mutable string", args[0]);
    const to_data = to_str.data[0..to_str.len];
    const to_cp_count = utf8CodepointCount(to_data);
    const at_val = types.toFixnum(args[1]);
    if (at_val < 0) return primitives.typeError("string-copy!", "non-negative integer", args[1]);
    const at_cp: usize = @intCast(at_val);
    const from_data = try getStringSlice(args[2]);
    const from_cp_count = utf8CodepointCount(from_data);

    const range = try primitives.parseOptionalRange(args, 3, from_cp_count, "string-copy!");
    const start_cp = range.start;
    const end_cp = range.end;
    const copy_cp_count = end_cp - start_cp;
    if (at_cp + copy_cp_count > to_cp_count) return primitives.typeError("string-copy!", "valid range", args[1]);

    // Convert codepoint indices to byte offsets
    const from_byte_start = utf8IndexToByteOffset(from_data, start_cp) orelse return primitives.typeError("string-copy!", "valid index", args[2]);
    const from_byte_end = utf8IndexToByteOffset(from_data, end_cp) orelse return primitives.typeError("string-copy!", "valid index", args[2]);
    const to_byte_start = utf8IndexToByteOffset(to_data, at_cp) orelse return primitives.typeError("string-copy!", "valid index", args[1]);
    const to_byte_end = utf8IndexToByteOffset(to_data, at_cp + copy_cp_count) orelse return primitives.typeError("string-copy!", "valid index", args[1]);

    const src_bytes = from_data[from_byte_start..from_byte_end];
    const dst_old_len = to_byte_end - to_byte_start;

    if (src_bytes.len == dst_old_len) {
        // Same byte length: copy in-place. `to` and `from` may be the same
        // string with overlapping ranges, so use overlap-safe (memmove-style)
        // copies rather than @memcpy, which traps on aliasing arguments.
        const dst = to_str.data[to_byte_start..to_byte_end];
        if (@intFromPtr(dst.ptr) < @intFromPtr(src_bytes.ptr)) {
            std.mem.copyForwards(u8, dst, src_bytes);
        } else {
            std.mem.copyBackwards(u8, dst, src_bytes);
        }
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
    if (!types.isString(args[0])) return primitives.typeError("string-fill!", "string", args[0]);
    if (!types.isChar(args[1])) return primitives.typeError("string-fill!", "character", args[1]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    if (str.immutable) return primitives.typeError("string-fill!", "mutable string", args[0]);
    const data = str.data[0..str.len];
    const cp = types.toChar(args[1]);
    const char_count = utf8CodepointCount(data);
    const range = try primitives.parseOptionalRange(args, 2, char_count, "string-fill!");
    const start = range.start;
    const end = range.end;
    var fill_buf: [4]u8 = undefined;
    const fill_len = std.unicode.utf8Encode(cp, &fill_buf) catch return primitives.typeError("string-fill!", "valid character", args[1]);
    // Build new string: [0..start] unchanged, [start..end] filled, [end..] unchanged
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);
    var cp_idx: usize = 0;
    var byte_idx: usize = 0;
    while (byte_idx < data.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(data[byte_idx]) catch 1;
        if (cp_idx >= start and cp_idx < end) {
            result.appendSlice(gc.allocator, fill_buf[0..fill_len]) catch return PrimitiveError.OutOfMemory;
        } else {
            result.appendSlice(gc.allocator, data[byte_idx .. byte_idx + cp_len]) catch return PrimitiveError.OutOfMemory;
        }
        byte_idx += cp_len;
        cp_idx += 1;
    }
    const new_data = gc.allocator.alloc(u8, result.items.len) catch return PrimitiveError.OutOfMemory;
    @memcpy(new_data, result.items);
    gc.allocator.free(str.data);
    str.data = new_data;
    str.len = new_data.len;
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (string->list str) or (string->list str start end)
// ---------------------------------------------------------------------------

fn stringToListFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    const cp_count = utf8CodepointCount(data);
    const range = try primitives.parseOptionalRange(args, 1, cp_count, "string->list");
    const start_cp = range.start;
    const end_cp = range.end;
    // Collect codepoints in the range
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return primitives.typeError("string->list", "valid index", args[1]);
    const range_count = end_cp - start_cp;
    // Build list from back to front; first collect codepoints
    var cps_buf: [4096]u21 = undefined;
    var cps = if (range_count <= 4096) cps_buf[0..range_count] else (gc.allocator.alloc(u21, range_count) catch return PrimitiveError.OutOfMemory);
    defer if (range_count > 4096) gc.allocator.free(cps);
    var byte_i = byte_start;
    for (0..range_count) |idx| {
        cps[idx] = utf8DecodeAt(data, byte_i) orelse return primitives.typeError("string->list", "valid UTF-8 string", args[0]);
        byte_i += utf8ByteLenAt(data, byte_i);
    }
    // Build list from back
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    // Count chars and calculate utf8 length
    var total: usize = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("list->string", "proper list", args[0]);
        const elem = types.car(current);
        if (!types.isChar(elem)) return primitives.typeError("list->string", "character", elem);
        const cp = types.toChar(elem);
        total += std.unicode.utf8CodepointSequenceLength(cp) catch return primitives.typeError("list->string", "valid character", elem);
        current = types.cdr(current);
    }
    const buf = gc.allocator.alloc(u8, total) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    current = args[0];
    while (current != types.NIL) {
        const cp = types.toChar(types.car(current));
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return primitives.typeError("list->string", "valid character", types.car(current));
        @memcpy(buf[pos .. pos + n], tmp[0..n]);
        pos += n;
        current = types.cdr(current);
    }
    return gc.allocString(buf[0..pos]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string->vector str) or (string->vector str start) or (string->vector str start end)
// ---------------------------------------------------------------------------

fn stringToVectorFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string->vector", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const data = str.data[0..str.len];
    const cp_count = utf8CodepointCount(data);
    const range = try primitives.parseOptionalRange(args, 1, cp_count, "string->vector");
    const start_cp = range.start;
    const end_cp = range.end;
    const range_count = end_cp - start_cp;
    const byte_start = utf8IndexToByteOffset(data, start_cp) orelse return primitives.typeError("string->vector", "valid index", args[1]);
    const vec_data = gc.allocator.alloc(Value, range_count) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(vec_data);
    var byte_i = byte_start;
    for (0..range_count) |idx| {
        const cp = utf8DecodeAt(data, byte_i) orelse return primitives.typeError("string->vector", "valid UTF-8 string", args[0]);
        vec_data[idx] = types.makeChar(cp);
        byte_i += utf8ByteLenAt(data, byte_i);
    }
    return gc.allocVector(vec_data[0..range_count]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-for-each proc str1 ...)
// ---------------------------------------------------------------------------

fn stringForEachFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return primitives.typeError("string-for-each", "procedure", proc);

    const str_count = args.len - 1;
    if (str_count == 0) return PrimitiveError.ArityMismatch;
    if (str_count > 256) return PrimitiveError.ArityMismatch;

    // Find minimum codepoint length
    var min_cp_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        const data = try getStringSlice(a);
        const cp_len = utf8CodepointCount(data);
        if (cp_len < min_cp_len) min_cp_len = cp_len;
    }

    var call_args: [256]Value = undefined;
    for (0..min_cp_len) |cp_idx| {
        for (0..str_count) |si| {
            const data = try getStringSlice(args[1 + si]);
            const byte_off = utf8IndexToByteOffset(data, cp_idx) orelse return primitives.typeError("string-for-each", "valid UTF-8 string", args[1 + si]);
            const cp = utf8DecodeAt(data, byte_off) orelse return primitives.typeError("string-for-each", "valid UTF-8 string", args[1 + si]);
            call_args[si] = types.makeChar(cp);
        }
        _ = vm.callWithArgs(proc, call_args[0..str_count]) catch |err| {
            return err;
        };
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (string-map proc str1 ...)
// ---------------------------------------------------------------------------

fn stringMapFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return primitives.typeError("string-map", "procedure", proc);

    const str_count = args.len - 1;
    if (str_count == 0) return PrimitiveError.ArityMismatch;
    if (str_count > 256) return PrimitiveError.ArityMismatch;

    // Find minimum codepoint length
    var min_cp_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        const data = try getStringSlice(a);
        const cp_len = utf8CodepointCount(data);
        if (cp_len < min_cp_len) min_cp_len = cp_len;
    }

    // Collect result chars
    var result_buf: std.ArrayList(u8) = .empty;
    defer result_buf.deinit(gc.allocator);

    var call_args: [256]Value = undefined;
    for (0..min_cp_len) |cp_idx| {
        for (0..str_count) |si| {
            const data = try getStringSlice(args[1 + si]);
            const byte_off = utf8IndexToByteOffset(data, cp_idx) orelse return primitives.typeError("string-map", "valid UTF-8 string", args[1 + si]);
            const cp = utf8DecodeAt(data, byte_off) orelse return primitives.typeError("string-map", "valid UTF-8 string", args[1 + si]);
            call_args[si] = types.makeChar(cp);
        }
        const result = vm.callWithArgs(proc, call_args[0..str_count]) catch |err| {
            return err;
        };
        if (!types.isChar(result)) return primitives.typeError("string-map", "character", result);
        const cp = types.toChar(result);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return primitives.typeError("string-map", "valid character", result);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (types.isFixnum(args[0])) {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(args[0])}) catch return PrimitiveError.OutOfMemory;
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isFlonum(args[0])) {
        const printer = @import("printer.zig");
        var buf: [64]u8 = undefined;
        const s = printer.formatFlonum(&buf, types.toFlonum(args[0]));
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    return primitives.typeError("number->string", "number", args[0]);
}

fn stringToNumberFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string->number", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const s = try getStringSlice(args[0]);

    if (std.mem.eql(u8, s, "+inf.0")) return types.makeFlonum(std.math.inf(f64));
    if (std.mem.eql(u8, s, "-inf.0")) return types.makeFlonum(-std.math.inf(f64));
    if (std.mem.eql(u8, s, "+nan.0")) return types.makeFlonum(std.math.nan(f64));
    if (std.mem.eql(u8, s, "-nan.0")) return types.makeFlonum(std.math.nan(f64));

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
        return types.makeFlonum(f);
    } else |_| {}

    return types.FALSE;
}

// ---------------------------------------------------------------------------
// Char operations
// ---------------------------------------------------------------------------

fn charToIntegerFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char->integer", "character", args[0]);
    return types.makeFixnum(@intCast(types.toChar(args[0])));
}

fn integerToCharFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("integer->char", "exact integer", args[0]);
    const n = types.toFixnum(args[0]);
    if (n < 0 or n > 0x10FFFF or (n >= 0xD800 and n <= 0xDFFF)) return primitives.typeError("integer->char", "valid Unicode scalar value (0..#xD7FF, #xE000..#x10FFFF)", args[0]);
    return types.makeChar(@intCast(n));
}

fn compareChars(args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    const name = comptime switch (cmp) {
        .lt => "char<?",
        .le => "char<=?",
        .eq => "char=?",
        .ge => "char>=?",
        .gt => "char>?",
    };
    for (0..args.len - 1) |i| {
        if (!types.isChar(args[i])) return primitives.typeError(name, "character", args[i]);
        if (!types.isChar(args[i + 1])) return primitives.typeError(name, "character", args[i + 1]);
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
