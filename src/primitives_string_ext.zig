const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const pstr = @import("primitives_string.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const getStringSlice = pstr.getStringSlice;
const utf8CodepointCount = pstr.utf8CodepointCount;
const utf8DecodeAt = pstr.utf8DecodeAt;
const utf8ByteLenAt = pstr.utf8ByteLenAt;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerStringExt(vm: *vm_mod.VM) !void {
    try reg(vm, "string-contains", &stringContainsFn, .{ .variadic = 2 });
    try reg(vm, "string-prefix?", &stringPrefixPFn, .{ .variadic = 2 });
    try reg(vm, "string-suffix?", &stringSuffixPFn, .{ .variadic = 2 });
    try reg(vm, "string-trim", &stringTrimFn, .{ .variadic = 1 });
    try reg(vm, "string-trim-right", &stringTrimRightFn, .{ .variadic = 1 });
    try reg(vm, "string-trim-both", &stringTrimBothFn, .{ .variadic = 1 });
    try reg(vm, "string-index", &stringIndexFn, .{ .variadic = 2 });
    try reg(vm, "string-count", &stringCountFn, .{ .variadic = 2 });
    try reg(vm, "string-split", &stringSplitFn, .{ .exact = 2 });
    try reg(vm, "string-join", &stringJoinFn, .{ .variadic = 1 });
    try reg(vm, "string-concatenate", &stringConcatenateFn, .{ .exact = 1 });
    // SRFI 13 additions
    try reg(vm, "string-take", &stringTakeFn, .{ .exact = 2 });
    try reg(vm, "string-drop", &stringDropFn, .{ .exact = 2 });
    try reg(vm, "string-take-right", &stringTakeRightFn, .{ .exact = 2 });
    try reg(vm, "string-drop-right", &stringDropRightFn, .{ .exact = 2 });
    try reg(vm, "string-pad", &stringPadFn, .{ .variadic = 2 });
    try reg(vm, "string-pad-right", &stringPadRightFn, .{ .variadic = 2 });
    try reg(vm, "string-reverse", &stringReverseFn, .{ .variadic = 1 });
    try reg(vm, "string-filter", &stringFilterFn, .{ .variadic = 2 });
    try reg(vm, "string-delete", &stringDeleteFn, .{ .variadic = 2 });
    try reg(vm, "string-replace", &stringReplaceFn, .{ .exact = 4 });
    try reg(vm, "string-titlecase", &stringTitlecaseFn, .{ .variadic = 1 });
    try reg(vm, "string-every", &stringEveryFn, .{ .variadic = 2 });
    try reg(vm, "string-any", &stringAnyFn, .{ .variadic = 2 });
    try reg(vm, "string-tabulate", &stringTabulateFn, .{ .exact = 2 });
    try reg(vm, "string-unfold", &stringUnfoldFn, .{ .variadic = 4 });
    try reg(vm, "string-unfold-right", &stringUnfoldRightFn, .{ .variadic = 4 });
    try reg(vm, "string-index-right", &stringIndexRightFn, .{ .variadic = 2 });
    try reg(vm, "string-skip", &stringSkipFn, .{ .variadic = 2 });
    try reg(vm, "string-skip-right", &stringSkipRightFn, .{ .variadic = 2 });
}
// ---------------------------------------------------------------------------
// SRFI-13 String Library
// ---------------------------------------------------------------------------

// (string-contains s1 s2 [start1 end1])
fn stringContainsFn(args: []const Value) PrimitiveError!Value {
    const full_s1 = try getStringSlice(args[0]);
    const s2 = try getStringSlice(args[1]);
    const range = try parseStartEnd(full_s1, args, 2);
    const s1 = range.data;
    if (s2.len == 0) return types.makeFixnum(@intCast(range.cp_offset));
    if (s2.len > s1.len) return types.FALSE;

    if (std.mem.indexOf(u8, s1, s2)) |byte_pos| {
        var cp_idx: usize = range.cp_offset;
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

// (string-prefix? prefix s [start end])
fn stringPrefixPFn(args: []const Value) PrimitiveError!Value {
    const prefix = try getStringSlice(args[0]);
    const full_s = try getStringSlice(args[1]);
    const range = try parseStartEnd(full_s, args, 2);
    return if (std.mem.startsWith(u8, range.data, prefix)) types.TRUE else types.FALSE;
}

// (string-suffix? suffix s [start end])
fn stringSuffixPFn(args: []const Value) PrimitiveError!Value {
    const suffix = try getStringSlice(args[0]);
    const full_s = try getStringSlice(args[1]);
    const range = try parseStartEnd(full_s, args, 2);
    return if (std.mem.endsWith(u8, range.data, suffix)) types.TRUE else types.FALSE;
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

/// Call a predicate or char-set-contains? with a character.
/// Handles both procedure arguments and SRFI-14 char-set record arguments.
fn callPredOrCharset(pred: Value, cp: u21) PrimitiveError!bool {
    if (types.isChar(pred)) {
        return types.toChar(pred) == cp;
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const char_val = types.makeChar(cp);

    // If pred is a procedure, call it directly
    if (types.isProcedure(pred)) {
        const result = vm.callWithArgs(pred, &[_]Value{char_val}) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError, // bare-ok: catch fallback
            };
        };
        return types.isTruthy(result);
    }

    // If pred is a record instance, try char-set-contains?
    if (types.isRecordInstance(pred)) {
        const cs_contains = vm.globals.get("char-set-contains?") orelse return PrimitiveError.TypeError;
        const result = vm.callWithArgs(cs_contains, &[_]Value{ pred, char_val }) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError, // bare-ok: catch fallback
            };
        };
        return types.isTruthy(result);
    }

    return primitives.typeError("string operation", "procedure or char-set", pred);
}

const Range = struct {
    data: []const u8,
    byte_start: usize,
    byte_end: usize,
    cp_offset: usize,
};

fn parseStartEnd(data: []const u8, args: []const Value, start_arg_idx: usize) PrimitiveError!Range {
    var byte_start: usize = 0;
    var byte_end: usize = data.len;
    var cp_offset: usize = 0;

    if (args.len > start_arg_idx) {
        if (!types.isFixnum(args[start_arg_idx])) return PrimitiveError.TypeError;
        const sv = types.toFixnum(args[start_arg_idx]);
        if (sv < 0) return PrimitiveError.TypeError; // bare-ok: generic helper, no proc name
        const start_cp: usize = @intCast(sv);
        byte_start = pstr.utf8IndexToByteOffset(data, start_cp) orelse return PrimitiveError.IndexOutOfBounds;
        cp_offset = start_cp;
    }
    if (args.len > start_arg_idx + 1) {
        if (!types.isFixnum(args[start_arg_idx + 1])) return PrimitiveError.TypeError;
        const ev = types.toFixnum(args[start_arg_idx + 1]);
        if (ev < 0) return PrimitiveError.TypeError; // bare-ok: generic helper, no proc name
        const end_cp: usize = @intCast(ev);
        byte_end = pstr.utf8IndexToByteOffset(data, end_cp) orelse return PrimitiveError.IndexOutOfBounds;
    }
    if (byte_start > byte_end) return PrimitiveError.TypeError;
    return .{ .data = data[byte_start..byte_end], .byte_start = byte_start, .byte_end = byte_end, .cp_offset = cp_offset };
}

fn decodeForward(data: []const u8, pos: usize) struct { cp: u21, len: usize } {
    if (pos >= data.len) return .{ .cp = 0, .len = 0 };
    const seq_len = std.unicode.utf8ByteSequenceLength(data[pos]) catch return .{ .cp = data[pos], .len = 1 };
    if (pos + seq_len > data.len) return .{ .cp = data[pos], .len = 1 };
    const cp = std.unicode.utf8Decode(data[pos .. pos + seq_len]) catch return .{ .cp = data[pos], .len = 1 };
    return .{ .cp = cp, .len = seq_len };
}

fn findPrevCpStart(data: []const u8, pos: usize) usize {
    var p = pos;
    while (p > 0) {
        p -= 1;
        if (data[p] & 0xC0 != 0x80) return p;
    }
    return 0;
}

// (string-trim s [pred [start end]])
fn stringTrimFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const full_data = try getStringSlice(args[0]);
    if (args.len <= 1) {
        var start: usize = 0;
        while (start < full_data.len and isWhitespace(full_data[start])) start += 1;
        return gc.allocString(full_data[start..]) catch return PrimitiveError.OutOfMemory;
    }
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);
    const data = range.data;
    var start: usize = 0;
    while (start < data.len) {
        const d = decodeForward(data, start);
        if (d.len == 0) break;
        if (!try callPredOrCharset(pred, d.cp)) break;
        start += d.len;
    }
    return gc.allocString(data[start..]) catch return PrimitiveError.OutOfMemory;
}

// (string-trim-right s [pred [start end]])
fn stringTrimRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const full_data = try getStringSlice(args[0]);
    if (args.len <= 1) {
        var end: usize = full_data.len;
        while (end > 0 and isWhitespace(full_data[end - 1])) end -= 1;
        return gc.allocString(full_data[0..end]) catch return PrimitiveError.OutOfMemory;
    }
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);
    const data = range.data;
    var end: usize = data.len;
    while (end > 0) {
        const cp_start = findPrevCpStart(data, end);
        const d = decodeForward(data, cp_start);
        if (d.len == 0) break;
        if (!try callPredOrCharset(pred, d.cp)) break;
        end = cp_start;
    }
    return gc.allocString(data[0..end]) catch return PrimitiveError.OutOfMemory;
}

// (string-trim-both s [pred [start end]])
fn stringTrimBothFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const full_data = try getStringSlice(args[0]);
    if (args.len <= 1) {
        var start: usize = 0;
        while (start < full_data.len and isWhitespace(full_data[start])) start += 1;
        var end: usize = full_data.len;
        while (end > start and isWhitespace(full_data[end - 1])) end -= 1;
        return gc.allocString(full_data[start..end]) catch return PrimitiveError.OutOfMemory;
    }
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);
    const data = range.data;
    var start: usize = 0;
    while (start < data.len) {
        const d = decodeForward(data, start);
        if (d.len == 0) break;
        if (!try callPredOrCharset(pred, d.cp)) break;
        start += d.len;
    }
    var end: usize = data.len;
    while (end > start) {
        const cp_start = findPrevCpStart(data, end);
        const d = decodeForward(data, cp_start);
        if (d.len == 0) break;
        if (!try callPredOrCharset(pred, d.cp)) break;
        end = cp_start;
    }
    return gc.allocString(data[start..end]) catch return PrimitiveError.OutOfMemory;
}

// (string-index s pred [start end])
fn stringIndexFn(args: []const Value) PrimitiveError!Value {
    const full_data = try getStringSlice(args[0]);
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);

    var byte_i: usize = 0;
    var cp_idx: usize = range.cp_offset;
    while (byte_i < range.data.len) {
        const cp = utf8DecodeAt(range.data, byte_i) orelse return PrimitiveError.TypeError;
        if (try callPredOrCharset(pred, cp)) return types.makeFixnum(@intCast(cp_idx));
        byte_i += utf8ByteLenAt(range.data, byte_i);
        cp_idx += 1;
    }
    return types.FALSE;
}

// (string-count s pred [start end])
fn stringCountFn(args: []const Value) PrimitiveError!Value {
    const full_data = try getStringSlice(args[0]);
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);

    var byte_i: usize = 0;
    var count: i64 = 0;
    while (byte_i < range.data.len) {
        const cp = utf8DecodeAt(range.data, byte_i) orelse return PrimitiveError.TypeError;
        if (try callPredOrCharset(pred, cp)) count += 1;
        byte_i += utf8ByteLenAt(range.data, byte_i);
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
        gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        var byte_i = data.len;
        while (byte_i > 0) {
            // Find start of previous codepoint
            var start = byte_i - 1;
            while (start > 0 and (data[start] & 0xC0) == 0x80) {
                start -= 1;
            }
            var str_val = gc.allocString(data[start..byte_i]) catch return PrimitiveError.OutOfMemory;
            gc.pushRoot(&str_val) catch return PrimitiveError.OutOfMemory;
            result = gc.allocPair(str_val, result) catch {
                gc.popRoot();
                return PrimitiveError.OutOfMemory;
            };
            gc.popRoot();
            byte_i = start;
        }
        return result;
    }

    var splits: std.ArrayList([2]usize) = .empty;
    defer splits.deinit(gc.allocator);

    var pos: usize = 0;
    while (pos <= data.len) {
        if (std.mem.indexOfPos(u8, data, pos, delim)) |found| {
            splits.append(gc.allocator, .{ pos, found }) catch return PrimitiveError.OutOfMemory;
            pos = found + delim.len;
        } else {
            splits.append(gc.allocator, .{ pos, data.len }) catch return PrimitiveError.OutOfMemory;
            break;
        }
    }

    var str_val: Value = types.NIL;
    gc.pushRoot(&str_val) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i = splits.items.len;
    while (i > 0) {
        i -= 1;
        str_val = gc.allocString(data[splits.items[i][0]..splits.items[i][1]]) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(str_val, result) catch return PrimitiveError.OutOfMemory;
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
        if (!types.isPair(current)) return primitives.typeError("string-join", "list", args[0]);
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
    var total: usize = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("string-concatenate", "list", args[0]);
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

// ---------------------------------------------------------------------------
// SRFI 13 additions
// ---------------------------------------------------------------------------

fn callVM(proc: Value, call_args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    return vm.callWithArgs(proc, call_args) catch |err| switch (err) {
        vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
        vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
        vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
        else => PrimitiveError.TypeError, // bare-ok: catch fallback
    };
}

fn stringTakeFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-take", "integer", args[1]);
    const nv = types.toFixnum(args[1]);
    if (nv < 0) return primitives.typeError("string-take", "non-negative integer", args[1]);
    const n: usize = @intCast(nv);
    const byte_end = pstr.utf8IndexToByteOffset(data, n) orelse return PrimitiveError.IndexOutOfBounds;
    return gc.allocString(data[0..byte_end]) catch return PrimitiveError.OutOfMemory;
}

fn stringDropFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-drop", "integer", args[1]);
    const nv = types.toFixnum(args[1]);
    if (nv < 0) return primitives.typeError("string-drop", "non-negative integer", args[1]);
    const n: usize = @intCast(nv);
    const byte_start = pstr.utf8IndexToByteOffset(data, n) orelse return PrimitiveError.IndexOutOfBounds;
    return gc.allocString(data[byte_start..]) catch return PrimitiveError.OutOfMemory;
}

fn stringTakeRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-take-right", "integer", args[1]);
    const nv = types.toFixnum(args[1]);
    if (nv < 0) return primitives.typeError("string-take-right", "non-negative integer", args[1]);
    const n: usize = @intCast(nv);
    const total_cp = utf8CodepointCount(data);
    if (n > total_cp) return PrimitiveError.IndexOutOfBounds;
    if (n == total_cp) return gc.allocString(data) catch return PrimitiveError.OutOfMemory;
    const byte_start = pstr.utf8IndexToByteOffset(data, total_cp - n) orelse return PrimitiveError.IndexOutOfBounds;
    return gc.allocString(data[byte_start..]) catch return PrimitiveError.OutOfMemory;
}

fn stringDropRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-drop-right", "integer", args[1]);
    const nv = types.toFixnum(args[1]);
    if (nv < 0) return primitives.typeError("string-drop-right", "non-negative integer", args[1]);
    const n: usize = @intCast(nv);
    const total_cp = utf8CodepointCount(data);
    if (n > total_cp) return PrimitiveError.IndexOutOfBounds;
    if (n == total_cp) return gc.allocString("") catch return PrimitiveError.OutOfMemory;
    const byte_end = pstr.utf8IndexToByteOffset(data, total_cp - n) orelse return PrimitiveError.IndexOutOfBounds;
    return gc.allocString(data[0..byte_end]) catch return PrimitiveError.OutOfMemory;
}

fn stringPadFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const full_data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-pad", "integer", args[1]);
    const tlv = types.toFixnum(args[1]);
    if (tlv < 0) return primitives.typeError("string-pad", "non-negative integer", args[1]);
    const target_len: usize = @intCast(tlv);
    var pad_buf: [4]u8 = undefined;
    const pad_cp: u21 = if (args.len > 2 and types.isChar(args[2])) types.toChar(args[2]) else ' ';
    const pad_len = std.unicode.utf8Encode(pad_cp, &pad_buf) catch
        return primitives.typeError("string-pad", "valid character", args[2]);
    const range = try parseStartEnd(full_data, args, 3);
    const data = range.data;
    const current_len = utf8CodepointCount(data);
    if (current_len >= target_len) {
        const byte_start = pstr.utf8IndexToByteOffset(data, current_len - target_len) orelse return PrimitiveError.IndexOutOfBounds;
        return gc.allocString(data[byte_start..]) catch return PrimitiveError.OutOfMemory;
    }
    const pad_count = target_len - current_len;
    const alloc_buf = gc.allocator.alloc(u8, pad_count * pad_len + data.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(alloc_buf);
    for (0..pad_count) |i| {
        @memcpy(alloc_buf[i * pad_len ..][0..pad_len], pad_buf[0..pad_len]);
    }
    @memcpy(alloc_buf[pad_count * pad_len ..], data);
    return gc.allocString(alloc_buf) catch return PrimitiveError.OutOfMemory;
}

fn stringPadRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const full_data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("string-pad-right", "integer", args[1]);
    const tlv = types.toFixnum(args[1]);
    if (tlv < 0) return primitives.typeError("string-pad-right", "non-negative integer", args[1]);
    const target_len: usize = @intCast(tlv);
    var pad_buf: [4]u8 = undefined;
    const pad_cp: u21 = if (args.len > 2 and types.isChar(args[2])) types.toChar(args[2]) else ' ';
    const pad_len = std.unicode.utf8Encode(pad_cp, &pad_buf) catch
        return primitives.typeError("string-pad-right", "valid character", args[2]);
    const range = try parseStartEnd(full_data, args, 3);
    const data = range.data;
    const current_len = utf8CodepointCount(data);
    if (current_len >= target_len) {
        const byte_end = pstr.utf8IndexToByteOffset(data, target_len) orelse return PrimitiveError.IndexOutOfBounds;
        return gc.allocString(data[0..byte_end]) catch return PrimitiveError.OutOfMemory;
    }
    const pad_count = target_len - current_len;
    const alloc_buf = gc.allocator.alloc(u8, data.len + pad_count * pad_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(alloc_buf);
    @memcpy(alloc_buf[0..data.len], data);
    for (0..pad_count) |i| {
        @memcpy(alloc_buf[data.len + i * pad_len ..][0..pad_len], pad_buf[0..pad_len]);
    }
    return gc.allocString(alloc_buf) catch return PrimitiveError.OutOfMemory;
}

// (string-reverse s [start end])
fn stringReverseFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const full_data = try getStringSlice(args[0]);
    const r = try parseStartEnd(full_data, args, 1);
    const data = r.data;
    if (data.len == 0) return gc.allocString("") catch return PrimitiveError.OutOfMemory;
    var offsets: std.ArrayList([2]usize) = .empty;
    defer offsets.deinit(gc.allocator);
    var i: usize = 0;
    while (i < data.len) {
        const len = std.unicode.utf8ByteSequenceLength(data[i]) catch 1;
        offsets.append(gc.allocator, .{ i, i + len }) catch return PrimitiveError.OutOfMemory;
        i += len;
    }
    const alloc_buf = gc.allocator.alloc(u8, data.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(alloc_buf);
    var pos: usize = 0;
    var j = offsets.items.len;
    while (j > 0) {
        j -= 1;
        const rng = offsets.items[j];
        const cp_len = rng[1] - rng[0];
        @memcpy(alloc_buf[pos .. pos + cp_len], data[rng[0]..rng[1]]);
        pos += cp_len;
    }
    return gc.allocString(alloc_buf) catch return PrimitiveError.OutOfMemory;
}

// (string-filter pred s [start end])
fn stringFilterFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const full_data = try getStringSlice(args[1]);
    const range = try parseStartEnd(full_data, args, 2);
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);
    var i: usize = 0;
    while (i < range.data.len) {
        const len = std.unicode.utf8ByteSequenceLength(range.data[i]) catch 1;
        const cp = std.unicode.utf8Decode(range.data[i .. i + len]) catch {
            i += len;
            continue;
        };
        const r_cs = try callPredOrCharset(pred, cp);
        if (r_cs) result.appendSlice(gc.allocator, range.data[i .. i + len]) catch return PrimitiveError.OutOfMemory;
        i += len;
    }
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

// (string-delete pred s [start end])
fn stringDeleteFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const full_data = try getStringSlice(args[1]);
    const range = try parseStartEnd(full_data, args, 2);
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);
    var i: usize = 0;
    while (i < range.data.len) {
        const len = std.unicode.utf8ByteSequenceLength(range.data[i]) catch 1;
        const cp = std.unicode.utf8Decode(range.data[i .. i + len]) catch {
            i += len;
            continue;
        };
        const r_cs = try callPredOrCharset(pred, cp);
        if (!r_cs) result.appendSlice(gc.allocator, range.data[i .. i + len]) catch return PrimitiveError.OutOfMemory;
        i += len;
    }
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

fn stringReplaceFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data1 = try getStringSlice(args[0]);
    const data2 = try getStringSlice(args[1]);
    if (!types.isFixnum(args[2]) or !types.isFixnum(args[3])) return primitives.typeError("string-replace", "integer", if (!types.isFixnum(args[2])) args[2] else args[3]);
    const sv = types.toFixnum(args[2]);
    const ev = types.toFixnum(args[3]);
    if (sv < 0) return primitives.typeError("string-replace", "non-negative integer", args[2]);
    if (ev < 0) return primitives.typeError("string-replace", "non-negative integer", args[3]);
    const start: usize = @intCast(sv);
    const end: usize = @intCast(ev);
    if (start > end) return primitives.typeError("string-replace", "valid index range (start <= end)", args[2]);
    const byte_start = pstr.utf8IndexToByteOffset(data1, start) orelse return PrimitiveError.IndexOutOfBounds;
    const byte_end = pstr.utf8IndexToByteOffset(data1, end) orelse return PrimitiveError.IndexOutOfBounds;
    const new_len = byte_start + data2.len + (data1.len - byte_end);
    const alloc_buf = gc.allocator.alloc(u8, new_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(alloc_buf);
    @memcpy(alloc_buf[0..byte_start], data1[0..byte_start]);
    @memcpy(alloc_buf[byte_start .. byte_start + data2.len], data2);
    @memcpy(alloc_buf[byte_start + data2.len ..], data1[byte_end..]);
    return gc.allocString(alloc_buf) catch return PrimitiveError.OutOfMemory;
}

// (string-titlecase s [start end])
fn stringTitlecaseFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const full_data = try getStringSlice(args[0]);
    const range = try parseStartEnd(full_data, args, 1);
    const data = range.data;
    if (data.len == 0) return gc.allocString("") catch return PrimitiveError.OutOfMemory;
    const alloc_buf = gc.allocator.alloc(u8, data.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(alloc_buf);
    @memcpy(alloc_buf, data);
    var word_start = true;
    for (alloc_buf) |*c| {
        if (c.* == ' ' or c.* == '\t' or c.* == '\n' or c.* == '\r') {
            word_start = true;
        } else if (word_start) {
            if (c.* >= 'a' and c.* <= 'z') c.* -= 32;
            word_start = false;
        } else {
            if (c.* >= 'A' and c.* <= 'Z') c.* += 32;
        }
    }
    return gc.allocString(alloc_buf) catch return PrimitiveError.OutOfMemory;
}

// (string-every pred s [start end])
fn stringEveryFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    const full_data = try getStringSlice(args[1]);
    const range = try parseStartEnd(full_data, args, 2);
    var last: Value = types.TRUE;
    var i: usize = 0;
    while (i < range.data.len) {
        const len = std.unicode.utf8ByteSequenceLength(range.data[i]) catch 1;
        const cp = std.unicode.utf8Decode(range.data[i .. i + len]) catch {
            i += len;
            continue;
        };
        if (types.isChar(pred)) {
            if (types.toChar(pred) != cp) return types.FALSE;
        } else if (types.isRecordInstance(pred)) {
            if (!try callPredOrCharset(pred, cp)) return types.FALSE;
        } else {
            const r = try callVM(pred, &[1]Value{types.makeChar(cp)});
            if (!types.isTruthy(r)) return types.FALSE;
            last = r;
        }
        i += len;
    }
    return last;
}

// (string-any pred s [start end])
fn stringAnyFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    const full_data = try getStringSlice(args[1]);
    const range = try parseStartEnd(full_data, args, 2);
    var i: usize = 0;
    while (i < range.data.len) {
        const len = std.unicode.utf8ByteSequenceLength(range.data[i]) catch 1;
        const cp = std.unicode.utf8Decode(range.data[i .. i + len]) catch {
            i += len;
            continue;
        };
        if (types.isChar(pred)) {
            if (types.toChar(pred) == cp) return types.TRUE;
        } else if (types.isRecordInstance(pred)) {
            if (try callPredOrCharset(pred, cp)) return types.TRUE;
        } else {
            const r = try callVM(pred, &[1]Value{types.makeChar(cp)});
            if (types.isTruthy(r)) return r;
        }
        i += len;
    }
    return types.FALSE;
}

fn stringTabulateFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isFixnum(args[1])) return primitives.typeError("string-tabulate", "integer", args[1]);
    const lv = types.toFixnum(args[1]);
    if (lv < 0) return primitives.typeError("string-tabulate", "non-negative integer", args[1]);
    const length: usize = @intCast(lv);
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);
    for (0..length) |i| {
        const r = try callVM(proc, &[1]Value{types.makeFixnum(@intCast(i))});
        if (!types.isChar(r)) return primitives.typeError("string-tabulate", "char", r);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(types.toChar(r), &tmp) catch return PrimitiveError.TypeError;
        result.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Additional SRFI-13 procedures
// ---------------------------------------------------------------------------

// (string-unfold p f g seed [base [make-final]])
fn stringUnfoldFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const p = args[0];
    const f = args[1];
    const g = args[2];
    var seed = args[3];

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);

    if (args.len > 4 and types.isString(args[4])) {
        const base = types.toObject(args[4]).as(types.SchemeString);
        result.appendSlice(gc.allocator, base.data[0..base.len]) catch return PrimitiveError.OutOfMemory;
    }

    while (true) {
        const stop = try callVM(p, &[1]Value{seed});
        if (types.isTruthy(stop)) break;
        const ch = try callVM(f, &[1]Value{seed});
        if (!types.isChar(ch)) return primitives.typeError("string-unfold", "char", ch);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(types.toChar(ch), &tmp) catch return PrimitiveError.TypeError;
        result.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
        seed = try callVM(g, &[1]Value{seed});
    }

    if (args.len > 5) {
        const final_val = try callVM(args[5], &[1]Value{seed});
        if (types.isString(final_val)) {
            const fs = types.toObject(final_val).as(types.SchemeString);
            result.appendSlice(gc.allocator, fs.data[0..fs.len]) catch return PrimitiveError.OutOfMemory;
        }
    }
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

// (string-unfold-right p f g seed [base [make-final]])
fn stringUnfoldRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const p = args[0];
    const f = args[1];
    const g = args[2];
    var seed = args[3];

    var chars: std.ArrayList(u21) = .empty;
    defer chars.deinit(gc.allocator);

    while (true) {
        const stop = try callVM(p, &[1]Value{seed});
        if (types.isTruthy(stop)) break;
        const ch = try callVM(f, &[1]Value{seed});
        if (!types.isChar(ch)) return primitives.typeError("string-unfold-right", "char", ch);
        chars.append(gc.allocator, types.toChar(ch)) catch return PrimitiveError.OutOfMemory;
        seed = try callVM(g, &[1]Value{seed});
    }

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);

    if (args.len > 5) {
        const final_val = try callVM(args[5], &[1]Value{seed});
        if (types.isString(final_val)) {
            const fs = types.toObject(final_val).as(types.SchemeString);
            result.appendSlice(gc.allocator, fs.data[0..fs.len]) catch return PrimitiveError.OutOfMemory;
        }
    }

    var i = chars.items.len;
    while (i > 0) {
        i -= 1;
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(chars.items[i], &tmp) catch continue;
        result.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    if (args.len > 4 and types.isString(args[4])) {
        const base = types.toObject(args[4]).as(types.SchemeString);
        result.appendSlice(gc.allocator, base.data[0..base.len]) catch return PrimitiveError.OutOfMemory;
    }

    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

// (string-index-right s pred [start end])
fn stringIndexRightFn(args: []const Value) PrimitiveError!Value {
    const full_data = try getStringSlice(args[0]);
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);
    var last_match: ?usize = null;
    var byte_i: usize = 0;
    var cp_idx: usize = range.cp_offset;
    while (byte_i < range.data.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(range.data[byte_i]) catch 1;
        const end = @min(byte_i + seq_len, range.data.len);
        const cp = std.unicode.utf8Decode(range.data[byte_i..end]) catch {
            byte_i += 1;
            cp_idx += 1;
            continue;
        };
        const r_cs = try callPredOrCharset(pred, cp);
        if (r_cs) last_match = cp_idx;
        byte_i += seq_len;
        cp_idx += 1;
    }
    return if (last_match) |idx| types.makeFixnum(@intCast(idx)) else types.FALSE;
}

// (string-skip s pred [start end])
fn stringSkipFn(args: []const Value) PrimitiveError!Value {
    const full_data = try getStringSlice(args[0]);
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);
    var byte_i: usize = 0;
    var cp_idx: usize = range.cp_offset;
    while (byte_i < range.data.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(range.data[byte_i]) catch 1;
        const end = @min(byte_i + seq_len, range.data.len);
        const cp = std.unicode.utf8Decode(range.data[byte_i..end]) catch {
            byte_i += 1;
            cp_idx += 1;
            continue;
        };
        const r_cs = try callPredOrCharset(pred, cp);
        if (!r_cs) return types.makeFixnum(@intCast(cp_idx));
        byte_i += seq_len;
        cp_idx += 1;
    }
    return types.FALSE;
}

// (string-skip-right s pred [start end])
fn stringSkipRightFn(args: []const Value) PrimitiveError!Value {
    const full_data = try getStringSlice(args[0]);
    const pred = args[1];
    const range = try parseStartEnd(full_data, args, 2);
    var last_match: ?usize = null;
    var byte_i: usize = 0;
    var cp_idx: usize = range.cp_offset;
    while (byte_i < range.data.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(range.data[byte_i]) catch 1;
        const end = @min(byte_i + seq_len, range.data.len);
        const cp = std.unicode.utf8Decode(range.data[byte_i..end]) catch {
            byte_i += 1;
            cp_idx += 1;
            continue;
        };
        const r_cs = try callPredOrCharset(pred, cp);
        if (!r_cs) last_match = cp_idx;
        byte_i += seq_len;
        cp_idx += 1;
    }
    return if (last_match) |idx| types.makeFixnum(@intCast(idx)) else types.FALSE;
}
