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

pub fn registerChar(vm: *vm_mod.VM) !void {
    // Character classification
    try reg(vm, "char-alphabetic?", &charAlphabeticP, .{ .exact = 1 });
    try reg(vm, "char-numeric?", &charNumericP, .{ .exact = 1 });
    try reg(vm, "char-whitespace?", &charWhitespaceP, .{ .exact = 1 });
    try reg(vm, "char-upper-case?", &charUpperCaseP, .{ .exact = 1 });
    try reg(vm, "char-lower-case?", &charLowerCaseP, .{ .exact = 1 });

    // Case operations
    try reg(vm, "char-upcase", &charUpcaseFn, .{ .exact = 1 });
    try reg(vm, "char-downcase", &charDowncaseFn, .{ .exact = 1 });
    try reg(vm, "char-foldcase", &charFoldcaseFn, .{ .exact = 1 });

    // Digit value
    try reg(vm, "digit-value", &digitValueFn, .{ .exact = 1 });

    // Case-insensitive char comparison
    try reg(vm, "char-ci<?", &charCiLtFn, .{ .variadic = 2 });
    try reg(vm, "char-ci<=?", &charCiLeFn, .{ .variadic = 2 });
    try reg(vm, "char-ci=?", &charCiEqFn, .{ .variadic = 2 });
    try reg(vm, "char-ci>=?", &charCiGeFn, .{ .variadic = 2 });
    try reg(vm, "char-ci>?", &charCiGtFn, .{ .variadic = 2 });

    // Case-insensitive string comparison
    try reg(vm, "string-ci<?", &stringCiLtFn, .{ .variadic = 2 });
    try reg(vm, "string-ci<=?", &stringCiLeFn, .{ .variadic = 2 });
    try reg(vm, "string-ci=?", &stringCiEqFn, .{ .variadic = 2 });
    try reg(vm, "string-ci>=?", &stringCiGeFn, .{ .variadic = 2 });
    try reg(vm, "string-ci>?", &stringCiGtFn, .{ .variadic = 2 });

    // String case operations
    try reg(vm, "string-upcase", &stringUpcaseFn, .{ .exact = 1 });
    try reg(vm, "string-downcase", &stringDowncaseFn, .{ .exact = 1 });
    try reg(vm, "string-foldcase", &stringFoldcaseFn, .{ .exact = 1 });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn charToAscii(v: Value) PrimitiveError!u8 {
    if (!types.isChar(v)) return PrimitiveError.TypeError;
    const cp = types.toChar(v);
    if (cp > 127) return @intCast(cp & 0xFF); // Truncate for non-ASCII
    return @intCast(cp);
}

fn getStringSlice(v: Value) PrimitiveError![]const u8 {
    if (!types.isString(v)) return PrimitiveError.TypeError;
    const str = types.toObject(v).as(types.SchemeString);
    return str.data[0..str.len];
}

// ---------------------------------------------------------------------------
// Character classification
// ---------------------------------------------------------------------------

fn charAlphabeticP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp > 127) return types.FALSE;
    return if (std.ascii.isAlphabetic(@intCast(cp))) types.TRUE else types.FALSE;
}

fn charNumericP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp > 127) return types.FALSE;
    return if (std.ascii.isDigit(@intCast(cp))) types.TRUE else types.FALSE;
}

fn charWhitespaceP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp > 127) return types.FALSE;
    return if (std.ascii.isWhitespace(@intCast(cp))) types.TRUE else types.FALSE;
}

fn charUpperCaseP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp > 127) return types.FALSE;
    return if (std.ascii.isUpper(@intCast(cp))) types.TRUE else types.FALSE;
}

fn charLowerCaseP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp > 127) return types.FALSE;
    return if (std.ascii.isLower(@intCast(cp))) types.TRUE else types.FALSE;
}

// ---------------------------------------------------------------------------
// Case operations
// ---------------------------------------------------------------------------

fn charUpcaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp > 127) return args[0];
    return types.makeChar(@intCast(std.ascii.toUpper(@intCast(cp))));
}

fn charDowncaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp > 127) return args[0];
    return types.makeChar(@intCast(std.ascii.toLower(@intCast(cp))));
}

fn charFoldcaseFn(args: []const Value) PrimitiveError!Value {
    // For ASCII, foldcase == downcase
    return charDowncaseFn(args);
}

// ---------------------------------------------------------------------------
// digit-value
// ---------------------------------------------------------------------------

fn digitValueFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    if (cp >= '0' and cp <= '9') {
        return types.makeFixnum(@as(i64, cp) - '0');
    }
    return types.FALSE;
}

// ---------------------------------------------------------------------------
// Case-insensitive char comparison
// ---------------------------------------------------------------------------

fn foldChar(cp: u21) u21 {
    if (cp <= 127) {
        return @intCast(std.ascii.toLower(@intCast(cp)));
    }
    return cp;
}

fn compareCiChars(args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isChar(args[i]) or !types.isChar(args[i + 1])) return PrimitiveError.TypeError;
        const a = foldChar(types.toChar(args[i]));
        const b = foldChar(types.toChar(args[i + 1]));
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

fn charCiLtFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .lt);
}

fn charCiLeFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .le);
}

fn charCiEqFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .eq);
}

fn charCiGeFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .ge);
}

fn charCiGtFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .gt);
}

// ---------------------------------------------------------------------------
// Case-insensitive string comparison
// ---------------------------------------------------------------------------

fn foldCompareStrings(a: []const u8, b: []const u8) std.math.Order {
    const min_len = @min(a.len, b.len);
    for (0..min_len) |i| {
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[i]);
        if (ca < cb) return .lt;
        if (ca > cb) return .gt;
    }
    if (a.len < b.len) return .lt;
    if (a.len > b.len) return .gt;
    return .eq;
}

fn compareCiStrings(args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try getStringSlice(args[i]);
        const b = try getStringSlice(args[i + 1]);
        const order = foldCompareStrings(a, b);
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

fn stringCiLtFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .lt);
}

fn stringCiLeFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .le);
}

fn stringCiEqFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .eq);
}

fn stringCiGeFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .ge);
}

fn stringCiGtFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .gt);
}

// ---------------------------------------------------------------------------
// String case operations
// ---------------------------------------------------------------------------

fn stringUpcaseFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    const buf = gc.allocator.alloc(u8, data.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    for (data, 0..) |c, i| {
        buf[i] = std.ascii.toUpper(c);
    }
    return gc.allocString(buf) catch return PrimitiveError.OutOfMemory;
}

fn stringDowncaseFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = try getStringSlice(args[0]);
    const buf = gc.allocator.alloc(u8, data.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    for (data, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return gc.allocString(buf) catch return PrimitiveError.OutOfMemory;
}

fn stringFoldcaseFn(args: []const Value) PrimitiveError!Value {
    // For ASCII, foldcase == downcase
    return stringDowncaseFn(args);
}
