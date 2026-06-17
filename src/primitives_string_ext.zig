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
