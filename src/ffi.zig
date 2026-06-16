const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const FfiType = types.FfiType;

/// Convert a Scheme string Value to a null-terminated C string using a stack buffer.
/// Returns null if the value is not a string or the string is too long.
fn toCString(v: Value, buf: *[4096]u8) ?[*:0]const u8 {
    if (!types.isString(v)) return null;
    const str = types.toObject(v).as(types.SchemeString);
    if (str.len >= buf.len) return null;
    @memcpy(buf[0..str.len], str.data[0..str.len]);
    buf[str.len] = 0;
    return @ptrCast(buf[0..str.len :0]);
}

/// Convert a C return value to a Scheme Value based on return type.
fn marshalReturn(comptime T: type, result: T, rt: FfiType, gc: *memory.GC) !Value {
    _ = rt;
    if (T == f64) {
        return gc.allocFlonum(result);
    } else if (T == c_int) {
        return types.makeFixnum(@intCast(result));
    } else if (T == c_long) {
        return types.makeFixnum(@intCast(result));
    } else if (T == void) {
        return types.VOID;
    }
    return error.TypeError;
}

/// Main FFI call dispatcher. Routes to arity-specific handlers.
pub fn callFfi(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    return switch (ffi_fn.param_count) {
        0 => callFfi0(ffi_fn, gc),
        1 => callFfi1(ffi_fn, args, gc),
        2 => callFfi2(ffi_fn, args, gc),
        3 => callFfi3(ffi_fn, args, gc),
        else => error.TypeError,
    };
}

// ---------------------------------------------------------------------------
// 0-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi0(ffi_fn: *types.FfiFunction, gc: *memory.GC) !Value {
    const rt = ffi_fn.return_type;

    if (rt == .void_type) {
        const f: *const fn () callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f();
        return types.VOID;
    }
    if (rt == .int) {
        const f: *const fn () callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return types.makeFixnum(@intCast(result));
    }
    if (rt == .long) {
        const f: *const fn () callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return types.makeFixnum(@intCast(result));
    }
    if (rt == .double) {
        const f: *const fn () callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return gc.allocFlonum(result);
    }
    if (rt == .float) {
        const f: *const fn () callconv(.c) f32 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return gc.allocFlonum(@floatCast(result));
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 1-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi1(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = ffi_fn.param_types[0];
    const rt = ffi_fn.return_type;

    // double -> double (sqrt, sin, cos, ceil, floor, etc.)
    if (p0 == .double and rt == .double) {
        const f: *const fn (f64) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]));
        return gc.allocFlonum(result);
    }

    // double -> float
    if (p0 == .double and rt == .float) {
        const f: *const fn (f64) callconv(.c) f32 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]));
        return gc.allocFlonum(@floatCast(result));
    }

    // float -> float
    if (p0 == .float and rt == .float) {
        const f: *const fn (f32) callconv(.c) f32 = @ptrCast(@alignCast(ffi_fn.symbol));
        const arg: f32 = @floatCast(types.toF64(args[0]));
        const result = f(arg);
        return gc.allocFlonum(@floatCast(result));
    }

    // int -> int (abs, etc.)
    if (p0 == .int and rt == .int) {
        const f: *const fn (c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])));
        return types.makeFixnum(@intCast(result));
    }

    // int -> long
    if (p0 == .int and rt == .long) {
        const f: *const fn (c_int) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])));
        return types.makeFixnum(@intCast(result));
    }

    // long -> long
    if (p0 == .long and rt == .long) {
        const f: *const fn (c_long) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])));
        return types.makeFixnum(@intCast(result));
    }

    // string -> int (atoi, etc.)
    if (p0 == .string and rt == .int) {
        const f: *const fn ([*:0]const u8) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        const result = f(cstr);
        return types.makeFixnum(@intCast(result));
    }

    // string -> long (strlen, etc.)
    if (p0 == .string and rt == .long) {
        const f: *const fn ([*:0]const u8) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        const result = f(cstr);
        return types.makeFixnum(@intCast(result));
    }

    // string -> void (puts, etc.)
    if (p0 == .string and rt == .void_type) {
        const f: *const fn ([*:0]const u8) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        f(cstr);
        return types.VOID;
    }

    // string -> double
    if (p0 == .string and rt == .double) {
        const f: *const fn ([*:0]const u8) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        const result = f(cstr);
        return gc.allocFlonum(result);
    }

    // int -> void
    if (p0 == .int and rt == .void_type) {
        const f: *const fn (c_int) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(types.toFixnum(args[0])));
        return types.VOID;
    }

    // double -> int
    if (p0 == .double and rt == .int) {
        const f: *const fn (f64) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]));
        return types.makeFixnum(@intCast(result));
    }

    // double -> void
    if (p0 == .double and rt == .void_type) {
        const f: *const fn (f64) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(types.toF64(args[0]));
        return types.VOID;
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 2-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi2(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = ffi_fn.param_types[0];
    const p1 = ffi_fn.param_types[1];
    const rt = ffi_fn.return_type;

    // (double, double) -> double (pow, fmod, atan2, etc.)
    if (p0 == .double and p1 == .double and rt == .double) {
        const f: *const fn (f64, f64) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]), types.toF64(args[1]));
        return gc.allocFlonum(result);
    }

    // (double, double) -> int
    if (p0 == .double and p1 == .double and rt == .int) {
        const f: *const fn (f64, f64) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]), types.toF64(args[1]));
        return types.makeFixnum(@intCast(result));
    }

    // (int, int) -> int
    if (p0 == .int and p1 == .int and rt == .int) {
        const f: *const fn (c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])), @intCast(types.toFixnum(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (int, int) -> long
    if (p0 == .int and p1 == .int and rt == .long) {
        const f: *const fn (c_int, c_int) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])), @intCast(types.toFixnum(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (long, long) -> long
    if (p0 == .long and p1 == .long and rt == .long) {
        const f: *const fn (c_long, c_long) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])), @intCast(types.toFixnum(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (string, string) -> int (strcmp, etc.)
    if (p0 == .string and p1 == .string and rt == .int) {
        const f: *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const result = f(cs0, cs1);
        return types.makeFixnum(@intCast(result));
    }

    // (string, string) -> long
    if (p0 == .string and p1 == .string and rt == .long) {
        const f: *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const result = f(cs0, cs1);
        return types.makeFixnum(@intCast(result));
    }

    // (string, string) -> void
    if (p0 == .string and p1 == .string and rt == .void_type) {
        const f: *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        f(cs0, cs1);
        return types.VOID;
    }

    // (int, int) -> void
    if (p0 == .int and p1 == .int and rt == .void_type) {
        const f: *const fn (c_int, c_int) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(types.toFixnum(args[0])), @intCast(types.toFixnum(args[1])));
        return types.VOID;
    }

    // (double, double) -> void
    if (p0 == .double and p1 == .double and rt == .void_type) {
        const f: *const fn (f64, f64) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(types.toF64(args[0]), types.toF64(args[1]));
        return types.VOID;
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 3-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi3(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = ffi_fn.param_types[0];
    const p1 = ffi_fn.param_types[1];
    const p2 = ffi_fn.param_types[2];
    const rt = ffi_fn.return_type;

    // (string, int, int) -> int
    if (p0 == .string and p1 == .int and p2 == .int and rt == .int) {
        const f: *const fn ([*:0]const u8, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        const result = f(cstr, @intCast(types.toFixnum(args[1])), @intCast(types.toFixnum(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    // (double, double, double) -> double (fma, etc.)
    if (p0 == .double and p1 == .double and p2 == .double and rt == .double) {
        const f: *const fn (f64, f64, f64) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]), types.toF64(args[1]), types.toF64(args[2]));
        return gc.allocFlonum(result);
    }

    // (int, int, int) -> int
    if (p0 == .int and p1 == .int and p2 == .int and rt == .int) {
        const f: *const fn (c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])), @intCast(types.toFixnum(args[1])), @intCast(types.toFixnum(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    // (string, string, int) -> int
    if (p0 == .string and p1 == .string and p2 == .int and rt == .int) {
        const f: *const fn ([*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const result = f(cs0, cs1, @intCast(types.toFixnum(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    return error.TypeError;
}
