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
    try reg(vm, "number->string", &numberToStringFn, .{ .exact = 1 });
    try reg(vm, "string->number", &stringToNumberFn, .{ .variadic = 1 });

    // Char operations
    try reg(vm, "char->integer", &charToIntegerFn, .{ .exact = 1 });
    try reg(vm, "integer->char", &integerToCharFn, .{ .exact = 1 });
    try reg(vm, "char<?", &charLtFn, .{ .variadic = 2 });
    try reg(vm, "char<=?", &charLeFn, .{ .variadic = 2 });
    try reg(vm, "char=?", &charEqFn, .{ .variadic = 2 });
    try reg(vm, "char>=?", &charGeFn, .{ .variadic = 2 });
    try reg(vm, "char>?", &charGtFn, .{ .variadic = 2 });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn getStringData(v: Value) PrimitiveError![]u8 {
    if (!types.isString(v)) return PrimitiveError.TypeError;
    const str = types.toObject(v).as(types.SchemeString);
    return str.data[0..str.len];
}

fn getStringSlice(v: Value) PrimitiveError![]const u8 {
    if (!types.isString(v)) return PrimitiveError.TypeError;
    const str = types.toObject(v).as(types.SchemeString);
    return str.data[0..str.len];
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
    const size: usize = @intCast(k);
    const fill_char: u8 = if (args.len > 1) blk: {
        if (!types.isChar(args[1])) return PrimitiveError.TypeError;
        const cp = types.toChar(args[1]);
        if (cp > 127) return PrimitiveError.TypeError; // ASCII only for fill
        break :blk @intCast(cp);
    } else ' ';
    const buf = gc.allocator.alloc(u8, size) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    @memset(buf, fill_char);
    return gc.allocString(buf) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-ref str k) — char at byte index
// ---------------------------------------------------------------------------

fn stringRefFn(args: []const Value) PrimitiveError!Value {
    const data = try getStringSlice(args[0]);
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0 or @as(usize, @intCast(k)) >= data.len) return PrimitiveError.TypeError;
    return types.makeChar(@intCast(data[@intCast(k)]));
}

// ---------------------------------------------------------------------------
// (string-set! str k ch) — mutate char at byte index
// ---------------------------------------------------------------------------

fn stringSetFn(args: []const Value) PrimitiveError!Value {
    const data = try getStringData(args[0]);
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    if (!types.isChar(args[2])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0 or @as(usize, @intCast(k)) >= data.len) return PrimitiveError.TypeError;
    const cp = types.toChar(args[2]);
    if (cp > 127) return PrimitiveError.TypeError; // ASCII only for mutation
    data[@intCast(k)] = @intCast(cp);
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
    const start: usize = @intCast(start_i);
    const end: usize = @intCast(end_i);
    if (start > end or end > data.len) return PrimitiveError.TypeError;
    return gc.allocString(data[start..end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-copy str) or (string-copy str start) or (string-copy str start end)
// ---------------------------------------------------------------------------

fn stringCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    var start: usize = 0;
    var end: usize = data.len;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[1]);
        if (s < 0 or @as(usize, @intCast(s)) > data.len) return PrimitiveError.TypeError;
        start = @intCast(s);
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[2]);
        if (e < 0 or @as(usize, @intCast(e)) > data.len) return PrimitiveError.TypeError;
        end = @intCast(e);
    }
    if (start > end) return PrimitiveError.TypeError;
    return gc.allocString(data[start..end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (string-copy! to at from) or with start/end
// ---------------------------------------------------------------------------

fn stringCopyBangFn(args: []const Value) PrimitiveError!Value {
    const to_data = try getStringData(args[0]);
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const at_val = types.toFixnum(args[1]);
    if (at_val < 0) return PrimitiveError.TypeError;
    const at: usize = @intCast(at_val);
    const from_data = try getStringSlice(args[2]);

    var start: usize = 0;
    var end: usize = from_data.len;
    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[3]);
        if (s < 0 or @as(usize, @intCast(s)) > from_data.len) return PrimitiveError.TypeError;
        start = @intCast(s);
    }
    if (args.len > 4) {
        if (!types.isFixnum(args[4])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[4]);
        if (e < 0 or @as(usize, @intCast(e)) > from_data.len) return PrimitiveError.TypeError;
        end = @intCast(e);
    }
    if (start > end) return PrimitiveError.TypeError;
    const count = end - start;
    if (at + count > to_data.len) return PrimitiveError.TypeError;

    // Copy bytes (handle overlapping)
    if (at <= start) {
        for (0..count) |i| {
            to_data[at + i] = from_data[start + i];
        }
    } else {
        var i = count;
        while (i > 0) {
            i -= 1;
            to_data[at + i] = from_data[start + i];
        }
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (string-fill! str ch)
// ---------------------------------------------------------------------------

fn stringFillFn(args: []const Value) PrimitiveError!Value {
    const data = try getStringData(args[0]);
    if (!types.isChar(args[1])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[1]);
    if (cp > 127) return PrimitiveError.TypeError; // ASCII only
    @memset(data, @intCast(cp));
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (string->list str) or (string->list str start end)
// ---------------------------------------------------------------------------

fn stringToListFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    var start: usize = 0;
    var end: usize = data.len;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[1]);
        if (s < 0 or @as(usize, @intCast(s)) > data.len) return PrimitiveError.TypeError;
        start = @intCast(s);
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[2]);
        if (e < 0 or @as(usize, @intCast(e)) > data.len) return PrimitiveError.TypeError;
        end = @intCast(e);
    }
    if (start > end) return PrimitiveError.TypeError;
    var result: Value = types.NIL;
    var i = end;
    while (i > start) {
        i -= 1;
        result = gc.allocPair(types.makeChar(@intCast(data[i])), result) catch return PrimitiveError.OutOfMemory;
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

    // Find minimum length
    var min_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        const data = try getStringSlice(a);
        if (data.len < min_len) min_len = data.len;
    }

    var call_args: [256]Value = undefined;
    for (0..min_len) |i| {
        for (0..str_count) |si| {
            const data = try getStringSlice(args[1 + si]);
            call_args[si] = types.makeChar(@intCast(data[i]));
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

    // Find minimum length
    var min_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        const data = try getStringSlice(a);
        if (data.len < min_len) min_len = data.len;
    }

    // Collect result chars
    var result_buf: std.ArrayList(u8) = .empty;
    defer result_buf.deinit(gc.allocator);

    var call_args: [256]Value = undefined;
    for (0..min_len) |i| {
        for (0..str_count) |si| {
            const data = try getStringSlice(args[1 + si]);
            call_args[si] = types.makeChar(@intCast(data[i]));
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
