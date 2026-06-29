const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const FfiType = types.FfiType;

fn toIntArgOpt(v: Value) ?i64 {
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        if (bn.len == 0) return 0;
        if (bn.len > 1) return null;
        const limb = bn.limbs[0];
        if (bn.positive) {
            if (limb > @as(u64, @intCast(std.math.maxInt(i64))))
                return null;
            return @intCast(limb);
        } else {
            if (limb > @as(u64, @intCast(std.math.maxInt(i64))) + 1)
                return null;
            if (limb == @as(u64, @intCast(std.math.maxInt(i64))) + 1)
                return std.math.minInt(i64);
            const mag: i64 = @intCast(limb);
            return -mag;
        }
    }
    return types.toFixnum(v);
}

fn toIntArg(v: Value) error{TypeError}!i64 {
    return toIntArgOpt(v) orelse return error.TypeError;
}

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

const MAX_FIXNUM: i64 = 0x7FFF_FFFF_FFFF; // 2^47 - 1
const MIN_FIXNUM: i64 = -0x8000_0000_0000; // -2^47

fn marshalLongReturn(result: c_long, gc: *memory.GC) !Value {
    if (result >= MIN_FIXNUM and result <= MAX_FIXNUM)
        return types.makeFixnum(@intCast(result));
    return gc.allocBignumFromI64(result) catch return error.OutOfMemory;
}

/// Convert a C return value to a Scheme Value based on return type.
fn marshalReturn(comptime T: type, result: T, rt: FfiType, gc: *memory.GC) !Value {
    _ = rt;
    if (T == f64) {
        return types.makeFlonum(result);
    } else if (T == c_int) {
        return types.makeFixnum(@intCast(result));
    } else if (T == c_long) {
        return marshalLongReturn(result, gc);
    } else if (T == void) {
        return types.VOID;
    }
    return error.TypeError;
}

fn marshalCStringReturn(cstr: [*:0]const u8, gc: *memory.GC) !Value {
    const len = std.mem.len(cstr);
    return gc.allocString(cstr[0..len]) catch return error.OutOfMemory;
}

fn marshalPointerReturn(ptr: ?*anyopaque, gc: *memory.GC) !Value {
    const addr: usize = if (ptr) |p| @intFromPtr(p) else 0;
    const signed: i64 = @bitCast(@as(u64, addr));
    if (signed >= 0 and signed <= MAX_FIXNUM)
        return types.makeFixnum(signed);
    const limbs_buf = [1]u64{addr};
    return gc.allocBignumFromLimbs(&limbs_buf, 1, true) catch return error.OutOfMemory;
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
        if (n < 0) return null;
        return @ptrFromInt(@as(usize, @intCast(n)));
    }
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        if (bn.len == 0) return null;
        if (bn.len > 1) return null;
        if (!bn.positive) return null;
        const limb = bn.limbs[0];
        if (limb > std.math.maxInt(usize)) return null;
        return @ptrFromInt(@as(usize, @intCast(limb)));
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
        .int8, .int16, .int32, .char_type, .bool_type, .uint8, .uint16 => .int,
        .int64, .uint32, .uint64, .size_type => .long,
        else => t,
    };
}

fn validateArg(v: Value, t: FfiType) bool {
    const nt = normalizeType(t);
    return switch (nt) {
        .int, .long => types.isFixnum(v) or types.isBignum(v),
        .double, .float => types.isFixnum(v) or types.isFlonum(v) or types.isRationalObj(v),
        .string => types.isString(v),
        .pointer => types.isFixnum(v) or types.isBignum(v) or types.isFfiCallback(v) or types.isBytevector(v),
        .void_type => true,
        else => false,
    };
}

fn validateArgs(ffi_fn: *types.FfiFunction, args: []const Value) !void {
    for (0..ffi_fn.param_count) |i| {
        if (!validateArg(args[i], ffi_fn.param_types[i])) {
            return error.TypeError;
        }
    }
}

/// Main FFI call dispatcher. Routes to arity-specific handlers.
pub fn callFfi(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    if (types.isFfiLibrary(ffi_fn.library)) {
        const lib = types.toObject(ffi_fn.library).as(types.FfiLibrary);
        if (lib.handle == null) return error.TypeError;
    }
    try validateArgs(ffi_fn, args);
    return switch (ffi_fn.param_count) {
        0 => callFfi0(ffi_fn, gc),
        1 => callFfi1(ffi_fn, args, gc),
        2 => callFfi2(ffi_fn, args, gc),
        3 => callFfi3(ffi_fn, args, gc),
        4 => callFfi4(ffi_fn, args, gc),
        5 => callFfi5(ffi_fn, args, gc),
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
        return marshalLongReturn(result, gc);
    }
    if (rt == .double) {
        const f: *const fn () callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return types.makeFlonum(result);
    }
    if (rt == .float) {
        const f: *const fn () callconv(.c) f32 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return types.makeFlonum(@floatCast(result));
    }
    if (rt == .pointer) {
        const f: *const fn () callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f();
        return marshalPointerReturn(result, gc);
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
        return types.makeFlonum(result);
    }

    // double -> float
    if (p0 == .double and rt == .float) {
        const f: *const fn (f64) callconv(.c) f32 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]));
        return types.makeFlonum(@floatCast(result));
    }

    // float -> float
    if (p0 == .float and rt == .float) {
        const f: *const fn (f32) callconv(.c) f32 = @ptrCast(@alignCast(ffi_fn.symbol));
        const arg: f32 = @floatCast(types.toF64(args[0]));
        const result = f(arg);
        return types.makeFlonum(@floatCast(result));
    }

    // int -> int (abs, etc.)
    if (p0 == .int and rt == .int) {
        const f: *const fn (c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])));
        return types.makeFixnum(@intCast(result));
    }

    // int -> long
    if (p0 == .int and rt == .long) {
        const f: *const fn (c_int) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])));
        return marshalLongReturn(result, gc);
    }

    // long -> long
    if (p0 == .long and rt == .long) {
        const f: *const fn (c_long) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])));
        return marshalLongReturn(result, gc);
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
        return marshalLongReturn(result, gc);
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
        return types.makeFlonum(result);
    }

    // int -> void
    if (p0 == .int and rt == .void_type) {
        const f: *const fn (c_int) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(try toIntArg(args[0])));
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
        return marshalLongReturn(result, gc);
    }

    // pointer -> pointer
    if (p0 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]));
        return marshalPointerReturn(result, gc);
    }

    // pointer -> double
    if (p0 == .pointer and rt == .double) {
        const f: *const fn (?*anyopaque) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]));
        return types.makeFlonum(result);
    }

    // int -> pointer (malloc, etc.)
    if (p0 == .int and rt == .pointer) {
        const f: *const fn (c_int) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])));
        return marshalPointerReturn(result, gc);
    }

    // long -> pointer
    if (p0 == .long and rt == .pointer) {
        const f: *const fn (c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])));
        return marshalPointerReturn(result, gc);
    }

    // long -> void
    if (p0 == .long and rt == .void_type) {
        const f: *const fn (c_long) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(try toIntArg(args[0])));
        return types.VOID;
    }

    // string -> pointer
    if (p0 == .string and rt == .pointer) {
        const f: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf: [4096]u8 = undefined;
        const cstr = toCString(args[0], &buf) orelse return error.TypeError;
        const result = f(cstr);
        return marshalPointerReturn(result, gc);
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
        return types.makeFlonum(result);
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
        const result = f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (int, int) -> long
    if (p0 == .int and p1 == .int and rt == .long) {
        const f: *const fn (c_int, c_int) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])));
        return marshalLongReturn(result, gc);
    }

    // (long, long) -> long
    if (p0 == .long and p1 == .long and rt == .long) {
        const f: *const fn (c_long, c_long) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])));
        return marshalLongReturn(result, gc);
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
        return marshalLongReturn(result, gc);
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
        f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])));
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
        return marshalPointerReturn(result, gc);
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
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, int) -> void
    if (p0 == .pointer and p1 == .int and rt == .void_type) {
        const f: *const fn (?*anyopaque, c_int) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])));
        return types.VOID;
    }

    // (pointer, int) -> pointer
    if (p0 == .pointer and p1 == .int and rt == .pointer) {
        const f: *const fn (?*anyopaque, c_int) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])));
        return marshalPointerReturn(result, gc);
    }

    // (pointer, long) -> pointer (realloc, etc.)
    if (p0 == .pointer and p1 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])));
        return marshalPointerReturn(result, gc);
    }

    // (pointer, long) -> int
    if (p0 == .pointer and p1 == .long and rt == .int) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, long) -> void
    if (p0 == .pointer and p1 == .long and rt == .void_type) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])));
        return types.VOID;
    }

    // (pointer, long) -> long
    if (p0 == .pointer and p1 == .long and rt == .long) {
        const f: *const fn (?*anyopaque, c_long) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])));
        return marshalLongReturn(result, gc);
    }

    // (int, pointer) -> int
    if (p0 == .int and p1 == .pointer and rt == .int) {
        const f: *const fn (c_int, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])), marshalToPointer(args[1]));
        return types.makeFixnum(@intCast(result));
    }

    // (int, pointer) -> void
    if (p0 == .int and p1 == .pointer and rt == .void_type) {
        const f: *const fn (c_int, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(try toIntArg(args[0])), marshalToPointer(args[1]));
        return types.VOID;
    }

    // (string, int) -> pointer
    if (p0 == .string and p1 == .int and rt == .pointer) {
        const f: *const fn ([*:0]const u8, c_int) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const result = f(cs0, @intCast(try toIntArg(args[1])));
        return marshalPointerReturn(result, gc);
    }

    // (string, string) -> pointer
    if (p0 == .string and p1 == .string and rt == .pointer) {
        const f: *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const result = f(cs0, cs1);
        return marshalPointerReturn(result, gc);
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
        const result = f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])));
        return marshalPointerReturn(result, gc);
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
        const result = f(cstr, @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    // (double, double, double) -> double (fma, etc.)
    if (p0 == .double and p1 == .double and p2 == .double and rt == .double) {
        const f: *const fn (f64, f64, f64) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]), types.toF64(args[1]), types.toF64(args[2]));
        return types.makeFlonum(result);
    }

    // (int, int, int) -> int
    if (p0 == .int and p1 == .int and p2 == .int and rt == .int) {
        const f: *const fn (c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    // (string, string, int) -> int
    if (p0 == .string and p1 == .string and p2 == .int and rt == .int) {
        const f: *const fn ([*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        const cs0 = toCString(args[0], &buf0) orelse return error.TypeError;
        const cs1 = toCString(args[1], &buf1) orelse return error.TypeError;
        const result = f(cs0, cs1, @intCast(try toIntArg(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, long) -> pointer (memcpy, memmove, etc.)
    if (p0 == .pointer and p1 == .pointer and p2 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(try toIntArg(args[2])));
        return marshalPointerReturn(result, gc);
    }

    // (pointer, int, long) -> pointer (memset, etc.)
    if (p0 == .pointer and p1 == .int and p2 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, c_int, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])));
        return marshalPointerReturn(result, gc);
    }

    // (pointer, long, pointer) -> long (fread/fwrite patterns)
    if (p0 == .pointer and p1 == .long and p2 == .pointer and rt == .long) {
        const f: *const fn (?*anyopaque, c_long, ?*anyopaque) callconv(.c) c_long = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])), marshalToPointer(args[2]));
        return marshalLongReturn(result, gc);
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
        return marshalPointerReturn(result, gc);
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
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(try toIntArg(args[2])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, long) -> void
    if (p0 == .pointer and p1 == .pointer and p2 == .long and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(try toIntArg(args[2])));
        return types.VOID;
    }

    // (int, pointer, pointer) -> int
    if (p0 == .int and p1 == .pointer and p2 == .pointer and rt == .int) {
        const f: *const fn (c_int, ?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])), marshalToPointer(args[1]), marshalToPointer(args[2]));
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

    // (pointer, long, long, pointer) -> void
    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, c_long, c_long, ?*anyopaque) callconv(.c) void =
            @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), marshalToPointer(args[3]));
        return types.VOID;
    }

    // (pointer, long, long, pointer) -> int
    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, c_long, c_long, ?*anyopaque) callconv(.c) c_int =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const ptr0 = marshalToPointer(args[0]) orelse return error.TypeError;
        const ptr3 = marshalToPointer(args[3]) orelse return error.TypeError;
        const result = f(ptr0, @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), ptr3);
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
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(try toIntArg(args[2])), @intCast(try toIntArg(args[3])));
        return marshalPointerReturn(result, gc);
    }

    // (pointer, long, long, long) -> int
    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .long and rt == .int) {
        const f: *const fn (?*anyopaque, c_long, c_long, c_long) callconv(.c) c_int =
            @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), @intCast(try toIntArg(args[3])));
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
        return marshalPointerReturn(result, gc);
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 5-arg dispatcher
// ---------------------------------------------------------------------------

fn callFfi5(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = normalizeType(ffi_fn.param_types[0]);
    const p1 = normalizeType(ffi_fn.param_types[1]);
    const p2 = normalizeType(ffi_fn.param_types[2]);
    const p3 = normalizeType(ffi_fn.param_types[3]);
    const p4 = normalizeType(ffi_fn.param_types[4]);
    const rt = normalizeType(ffi_fn.return_type);

    // (double, double, double, double, double) -> double
    if (p0 == .double and p1 == .double and p2 == .double and p3 == .double and p4 == .double and rt == .double) {
        const f: *const fn (f64, f64, f64, f64, f64) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(types.toF64(args[0]), types.toF64(args[1]), types.toF64(args[2]), types.toF64(args[3]), types.toF64(args[4]));
        return types.makeFlonum(result);
    }

    // (double, double, double, double, double) -> void
    if (p0 == .double and p1 == .double and p2 == .double and p3 == .double and p4 == .double and rt == .void_type) {
        const f: *const fn (f64, f64, f64, f64, f64) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(types.toF64(args[0]), types.toF64(args[1]), types.toF64(args[2]), types.toF64(args[3]), types.toF64(args[4]));
        return types.VOID;
    }

    // (int, int, int, int, int) -> int
    if (p0 == .int and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .int) {
        const f: *const fn (c_int, c_int, c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), @intCast(try toIntArg(args[3])), @intCast(try toIntArg(args[4])));
        return types.makeFixnum(@intCast(result));
    }

    // (int, int, int, int, int) -> void
    if (p0 == .int and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .void_type) {
        const f: *const fn (c_int, c_int, c_int, c_int, c_int) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), @intCast(try toIntArg(args[3])), @intCast(try toIntArg(args[4])));
        return types.VOID;
    }

    // (int, int, int, pointer, int) -> int — setsockopt
    if (p0 == .int and p1 == .int and p2 == .int and p3 == .pointer and p4 == .int and rt == .int) {
        const f: *const fn (c_int, c_int, c_int, ?*anyopaque, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(@intCast(try toIntArg(args[0])), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), marshalToPointer(args[3]), @intCast(try toIntArg(args[4])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, long, int, pointer) -> int — sendto
    if (p0 == .pointer and p1 == .pointer and p2 == .long and p3 == .int and p4 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long, c_int, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), @intCast(try toIntArg(args[2])), @intCast(try toIntArg(args[3])), marshalToPointer(args[4]));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, int, int, int, int) -> int — socket/IO ops
    if (p0 == .pointer and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .int) {
        const f: *const fn (?*anyopaque, c_int, c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), @intCast(try toIntArg(args[3])), @intCast(try toIntArg(args[4])));
        return types.makeFixnum(@intCast(result));
    }

    // (string, string, string, string, string) -> int
    if (p0 == .string and p1 == .string and p2 == .string and p3 == .string and p4 == .string and rt == .int) {
        const f: *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        var buf2: [4096]u8 = undefined;
        var buf3: [4096]u8 = undefined;
        var buf4: [4096]u8 = undefined;
        const result = f(toCString(args[0], &buf0) orelse return error.TypeError, toCString(args[1], &buf1) orelse return error.TypeError, toCString(args[2], &buf2) orelse return error.TypeError, toCString(args[3], &buf3) orelse return error.TypeError, toCString(args[4], &buf4) orelse return error.TypeError);
        return types.makeFixnum(@intCast(result));
    }

    // (string, string, string, string, string) -> string
    if (p0 == .string and p1 == .string and p2 == .string and p3 == .string and p4 == .string and rt == .string) {
        const f: *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        var buf1: [4096]u8 = undefined;
        var buf2: [4096]u8 = undefined;
        var buf3: [4096]u8 = undefined;
        var buf4: [4096]u8 = undefined;
        const result = f(toCString(args[0], &buf0) orelse return error.TypeError, toCString(args[1], &buf1) orelse return error.TypeError, toCString(args[2], &buf2) orelse return error.TypeError, toCString(args[3], &buf3) orelse return error.TypeError, toCString(args[4], &buf4) orelse return error.TypeError) orelse return types.FALSE;
        return marshalCStringReturn(result, gc);
    }

    // (string, int, int, int, int) -> int
    if (p0 == .string and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .int) {
        const f: *const fn ([*:0]const u8, c_int, c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        var buf0: [4096]u8 = undefined;
        const result = f(toCString(args[0], &buf0) orelse return error.TypeError, @intCast(try toIntArg(args[1])), @intCast(try toIntArg(args[2])), @intCast(try toIntArg(args[3])), @intCast(try toIntArg(args[4])));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, pointer, pointer, pointer) -> int
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and p4 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]), marshalToPointer(args[3]), marshalToPointer(args[4]));
        return types.makeFixnum(@intCast(result));
    }

    // (pointer, pointer, pointer, pointer, pointer) -> void
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and p4 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]), marshalToPointer(args[3]), marshalToPointer(args[4]));
        return types.VOID;
    }

    // (pointer, pointer, pointer, pointer, pointer) -> pointer
    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and p4 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(marshalToPointer(args[0]), marshalToPointer(args[1]), marshalToPointer(args[2]), marshalToPointer(args[3]), marshalToPointer(args[4]));
        return marshalPointerReturn(result, gc);
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "marshalLongReturn: fixnum range preserved" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val = try marshalLongReturn(42, &gc);
    try std.testing.expect(types.isFixnum(val));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(val));

    const neg = try marshalLongReturn(-100, &gc);
    try std.testing.expect(types.isFixnum(neg));
    try std.testing.expectEqual(@as(i64, -100), types.toFixnum(neg));

    const zero = try marshalLongReturn(0, &gc);
    try std.testing.expect(types.isFixnum(zero));
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(zero));
}

test "marshalLongReturn: boundary values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const max = try marshalLongReturn(MAX_FIXNUM, &gc);
    try std.testing.expect(types.isFixnum(max));
    try std.testing.expectEqual(MAX_FIXNUM, types.toFixnum(max));

    const min = try marshalLongReturn(MIN_FIXNUM, &gc);
    try std.testing.expect(types.isFixnum(min));
    try std.testing.expectEqual(MIN_FIXNUM, types.toFixnum(min));
}

test "marshalLongReturn: above fixnum range promotes to bignum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const above = try marshalLongReturn(MAX_FIXNUM + 1, &gc);
    try std.testing.expect(types.isBignum(above));
    const bn = types.toBignum(above);
    try std.testing.expect(bn.positive);
    try std.testing.expectEqual(@as(u64, @intCast(MAX_FIXNUM + 1)), bn.limbs[0]);
}

test "marshalLongReturn: below fixnum range promotes to bignum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const below = try marshalLongReturn(MIN_FIXNUM - 1, &gc);
    try std.testing.expect(types.isBignum(below));
    const bn = types.toBignum(below);
    try std.testing.expect(!bn.positive);
    const expected_mag: u64 = @intCast(-@as(i128, MIN_FIXNUM - 1));
    try std.testing.expectEqual(expected_mag, bn.limbs[0]);
}

test "marshalLongReturn: large positive 64-bit value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const large: c_long = std.math.maxInt(i64);
    const val = try marshalLongReturn(large, &gc);
    try std.testing.expect(types.isBignum(val));
    const bn = types.toBignum(val);
    try std.testing.expect(bn.positive);
    try std.testing.expectEqual(@as(u64, @intCast(large)), bn.limbs[0]);
}

test "marshalLongReturn: large negative 64-bit value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const large: c_long = std.math.minInt(i64);
    const val = try marshalLongReturn(large, &gc);
    try std.testing.expect(types.isBignum(val));
    const bn = types.toBignum(val);
    try std.testing.expect(!bn.positive);
}

test "marshalPointerReturn: null returns fixnum zero" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val = try marshalPointerReturn(null, &gc);
    try std.testing.expect(types.isFixnum(val));
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(val));
}

test "marshalPointerReturn: small address returns fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    var dummy: u8 = 0;
    const ptr: ?*anyopaque = @ptrCast(&dummy);
    const val = try marshalPointerReturn(ptr, &gc);
    const addr = @intFromPtr(&dummy);
    if (addr <= @as(usize, @intCast(MAX_FIXNUM))) {
        try std.testing.expect(types.isFixnum(val));
    }
}

test "marshalToPointer: round-trips fixnum pointer" {
    const addr: usize = 0x1000;
    const v = types.makeFixnum(@intCast(addr));
    const ptr = marshalToPointer(v);
    try std.testing.expectEqual(addr, @intFromPtr(ptr.?));
}

test "marshalToPointer: round-trips bignum pointer" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const addr: usize = 0x1234_5678_9ABC;
    const limbs_buf = [1]u64{addr};
    const v = try gc.allocBignumFromLimbs(&limbs_buf, 1, true);
    const ptr = marshalToPointer(v);
    try std.testing.expectEqual(addr, @intFromPtr(ptr.?));
}

test "marshalToPointer: negative fixnum returns null" {
    const v = types.makeFixnum(-1);
    try std.testing.expectEqual(@as(?*anyopaque, null), marshalToPointer(v));
}

test "marshalToPointer: negative bignum returns null" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const v = try gc.allocBignumFromI64(-42);
    try std.testing.expectEqual(@as(?*anyopaque, null), marshalToPointer(v));
}

test "validateArg: accepts bignum for long type" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const big = try gc.allocBignumFromI64(std.math.maxInt(i64));
    try std.testing.expect(validateArg(big, .long));
    try std.testing.expect(validateArg(big, .int64));
    try std.testing.expect(validateArg(big, .size_type));
}

test "validateArg: accepts bignum for pointer type" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const big = try gc.allocBignumFromI64(0x1000);
    try std.testing.expect(validateArg(big, .pointer));
}
