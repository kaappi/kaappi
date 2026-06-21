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

fn marshalCStringReturn(cstr: [*:0]const u8, gc: *memory.GC) !Value {
    const len = std.mem.len(cstr);
    return gc.allocString(cstr[0..len]) catch return error.OutOfMemory;
}

fn marshalPointerReturn(ptr: ?*anyopaque) Value {
    const addr: usize = if (ptr) |p| @intFromPtr(p) else 0;
    return types.makeFixnum(@intCast(addr));
}

fn marshalToPointer(v: Value) ?*anyopaque {
    if (types.isFfiCallback(v)) {
        const cb = types.toObject(v).as(types.FfiCallback);
        if (cb.active) return cb.fn_ptr;
        return null;
    }
    if (types.isFixnum(v)) {
        const n = types.toFixnum(v);
        if (n == 0) return null;
        return @ptrFromInt(@as(usize, @intCast(n)));
    }
    if (types.isBytevector(v)) {
        const bv = types.toObject(v).as(types.Bytevector);
        if (bv.data.len == 0) return null;
        return @ptrCast(bv.data.ptr);
    }
    return null;
}

fn normalizeType(t: FfiType) FfiType {
    return switch (t) {
        .int8, .int16, .int32, .char_type, .bool_type, .uint8, .uint16, .uint32 => .int,
        .int64, .uint64, .size_type => .long,
        else => t,
    };
}

/// Main FFI call dispatcher. Routes to arity-specific handlers.
pub fn callFfi(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    return switch (ffi_fn.param_count) {
        0 => callFfi0(ffi_fn, gc),
        1 => callFfi1(ffi_fn, args, gc),
        2 => callFfi2(ffi_fn, args, gc),
        3 => callFfi3(ffi_fn, args, gc),
        4 => callFfi4(ffi_fn, args, gc),
        else => error.TypeError,
    };
}

// ---------------------------------------------------------------------------
// 0-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi0(ffi_fn: *types.FfiFunction, gc: *memory.GC) !Value {
    const rt = normalizeType(ffi_fn.return_type);

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
    if (rt == .pointer) {
        const f: *const fn () callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return marshalPointerReturn(result);
    }
    if (rt == .string) {
        const f: *const fn () callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f() orelse return types.FALSE;
        return marshalCStringReturn(result, gc);
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 1-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi1(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = normalizeType(ffi_fn.param_types[0]);
    const rt = normalizeType(ffi_fn.return_type);

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

    // pointer -> void (free, etc.)
    if (p0 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]));
        return types.VOID;
    }

    // pointer -> int
    if (p0 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]));
        return types.makeFixnum(@intCast(result));
    }

    // pointer -> long
    if (p0 == .pointer and rt == .long) {
        const f: *const fn (?*anyopaque) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]));
        return types.makeFixnum(@intCast(result));
    }

    // pointer -> pointer
    if (p0 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]));
        return marshalPointerReturn(result);
    }

    // pointer -> double
    if (p0 == .pointer and rt == .double) {
        const f: *const fn (?*anyopaque) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]));
        return gc.allocFlonum(result);
    }

    // int -> pointer (malloc, etc.)
    if (p0 == .int and rt == .pointer) {
        const f: *const fn (c_int) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])));
        return marshalPointerReturn(result);
    }

    // long -> pointer
    if (p0 == .long and rt == .pointer) {
        const f: *const fn (c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])));
        return marshalPointerReturn(result);
    }

    // long -> void
    if (p0 == .long and rt == .void_type) {
        const f: *const fn (c_long) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(types.toFixnum(args[0])));
        return types.VOID;
    }

    // string -> pointer
    if (p0 == .string and rt == .pointer) {
        const f: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        const result = f(cstr);
        return marshalPointerReturn(result);
    }

    // string -> string
    if (p0 == .string and rt == .string) {
        const f: *const fn ([*:0]const u8) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        const result = f(cstr) orelse return types.FALSE;
        return marshalCStringReturn(result, gc);
    }

    // pointer -> string
    if (p0 == .pointer and rt == .string) {
        const f: *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0])) orelse return types.FALSE;
        return marshalCStringReturn(result, gc);
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 2-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi2(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = normalizeType(ffi_fn.param_types[0]);
    const p1 = normalizeType(ffi_fn.param_types[1]);
    const rt = normalizeType(ffi_fn.return_type);

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

    // (pointer, pointer) -> pointer (memcpy for 2-arg variants, etc.)
    if (p0 == .pointer and p1 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]));
        return marshalPointerReturn(result);
    }

    // (pointer, pointer) -> int
    if (p0 == .pointer and p1 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer) -> void
    if (p0 == .pointer and p1 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), marshalToPointer(args[1]));
        return types.VOID;
    }

    // (pointer, int) -> int
    if (p0 == .pointer and p1 == .int and rt == .int) {
        const f: *const fn (?*anyopaque, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, int) -> void
    if (p0 == .pointer and p1 == .int and rt == .void_type) {
        const f: *const fn (?*anyopaque, c_int) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])));
        return types.VOID;
    }

    // (pointer, int) -> pointer
    if (p0 == .pointer and p1 == .int and rt == .pointer) {
        const f: *const fn (?*anyopaque, c_int) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])));
        return marshalPointerReturn(result);
    }

    // (pointer, long) -> pointer (realloc, etc.)
    if (p0 == .pointer and p1 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])));
        return marshalPointerReturn(result);
    }

    // (pointer, long) -> int
    if (p0 == .pointer and p1 == .long and rt == .int) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, long) -> void
    if (p0 == .pointer and p1 == .long and rt == .void_type) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])));
        return types.VOID;
    }

    // (pointer, long) -> long
    if (p0 == .pointer and p1 == .long and rt == .long) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (int, pointer) -> int
    if (p0 == .int and p1 == .pointer and rt == .int) {
        const f: *const fn (c_int, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])), marshalToPointer(args[1]));
        return types.makeFixnum(@intCast(result));
    }

    // (int, pointer) -> void
    if (p0 == .int and p1 == .pointer and rt == .void_type) {
        const f: *const fn (c_int, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(types.toFixnum(args[0])), marshalToPointer(args[1]));
        return types.VOID;
    }

    // (string, int) -> pointer
    if (p0 == .string and p1 == .int and rt == .pointer) {
        const f: *const fn ([*:0]const u8, c_int) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const result = f(cs0, @intCast(types.toFixnum(args[1])));
        return marshalPointerReturn(result);
    }

    // (string, string) -> pointer
    if (p0 == .string and p1 == .string and rt == .pointer) {
        const f: *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const result = f(cs0, cs1);
        return marshalPointerReturn(result);
    }

    // (string, string) -> string
    if (p0 == .string and p1 == .string and rt == .string) {
        const f: *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const result = f(cs0, cs1) orelse return types.FALSE;
        return marshalCStringReturn(result, gc);
    }

    // (long, long) -> pointer
    if (p0 == .long and p1 == .long and rt == .pointer) {
        const f: *const fn (c_long, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])), @intCast(types.toFixnum(args[1])));
        return marshalPointerReturn(result);
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 3-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi3(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = normalizeType(ffi_fn.param_types[0]);
    const p1 = normalizeType(ffi_fn.param_types[1]);
    const p2 = normalizeType(ffi_fn.param_types[2]);
    const rt = normalizeType(ffi_fn.return_type);

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

    // (pointer, pointer, long) -> pointer (memcpy, memmove, etc.)
    if (p0 == .pointer and p1 == .pointer and p2 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(types.toFixnum(args[2])));
        return marshalPointerReturn(result);
    }

    // (pointer, int, long) -> pointer (memset, etc.)
    if (p0 == .pointer and p1 == .int and p2 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, c_int, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])), @intCast(types.toFixnum(args[2])));
        return marshalPointerReturn(result);
    }

    // (pointer, long, pointer) -> long (fread/fwrite patterns)
    if (p0 == .pointer and p1 == .long and p2 == .pointer and rt == .long) {
        const f: *const fn (?*anyopaque, c_long, ?*anyopaque) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])), marshalToPointer(args[2]));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, pointer) -> int
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, pointer) -> pointer
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]));
        return marshalPointerReturn(result);
    }

    // (pointer, pointer, pointer) -> void
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]));
        return types.VOID;
    }

    // (pointer, pointer, long) -> int
    if (p0 == .pointer and p1 == .pointer and p2 == .long and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(types.toFixnum(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, long) -> void
    if (p0 == .pointer and p1 == .pointer and p2 == .long and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(types.toFixnum(args[2])));
        return types.VOID;
    }

    // (int, pointer, pointer) -> int
    if (p0 == .int and p1 == .pointer and p2 == .pointer and rt == .int) {
        const f: *const fn (c_int, ?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(types.toFixnum(args[0])), marshalToPointer(args[1]), marshalToPointer(args[2]));
        return types.makeFixnum(@intCast(result));
    }

    // (string, string, string) -> int
    if (p0 == .string and p1 == .string and p2 == .string and rt == .int) {
        const f: *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        var buf2: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const cs2 = toCString(args[2], &buf2) orelse return error.TypeError;
        const result = f(cs0, cs1, cs2);
        return types.makeFixnum(@intCast(result));
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 4-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi4(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = normalizeType(ffi_fn.param_types[0]);
    const p1 = normalizeType(ffi_fn.param_types[1]);
    const p2 = normalizeType(ffi_fn.param_types[2]);
    const p3 = normalizeType(ffi_fn.param_types[3]);
    const rt = normalizeType(ffi_fn.return_type);

    // (pointer, long, long, pointer) -> void  — qsort
    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, usize, usize, *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int) callconv(.c) void =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const ptr0 = marshalToPointer(args[0]) orelse return error.TypeError;
        const n: usize = @intCast(types.toFixnum(args[1]));
        const sz: usize = @intCast(types.toFixnum(args[2]));
        const cmp_ptr = marshalToPointer(args[3]) orelse return error.TypeError;
        const cmp: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(cmp_ptr));
        f(ptr0, n, sz, cmp);
        return types.VOID;
    }

    // (pointer, long, long, pointer) -> int
    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, c_long, c_long, ?*anyopaque) callconv(.c) c_int =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const ptr0 = marshalToPointer(args[0]) orelse return error.TypeError;
        const ptr3 = marshalToPointer(args[3]) orelse return error.TypeError;
        const result = f(ptr0, @intCast(types.toFixnum(args[1])), @intCast(types.toFixnum(args[2])), ptr3);
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, pointer, pointer) -> int
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) c_int =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(
            marshalToPointer(args[0]),
            marshalToPointer(args[1]),
            marshalToPointer(args[2]),
            marshalToPointer(args[3]),
        );
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, long, long) -> pointer
    if (p0 == .pointer and p1 == .pointer and p2 == .long and p3 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long, c_long) callconv(.c) ?*anyopaque =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(types.toFixnum(args[2])), @intCast(types.toFixnum(args[3])));
        return marshalPointerReturn(result);
    }

    // (pointer, long, long, long) -> int
    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .long and rt == .int) {
        const f: *const fn (?*anyopaque, c_long, c_long, c_long) callconv(.c) c_int =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(types.toFixnum(args[1])), @intCast(types.toFixnum(args[2])), @intCast(types.toFixnum(args[3])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, pointer, pointer) -> void
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void =
            @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]), marshalToPointer(args[3]));
        return types.VOID;
    }

    // (pointer, pointer, pointer, pointer) -> pointer
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]), marshalToPointer(args[3]));
        return marshalPointerReturn(result);
    }

    _ = gc;
    return error.TypeError;
}
