const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const VM = @import("vm.zig").VM;
const Value = types.Value;
const FfiType = types.FfiType;

fn ffiTypeName(t: FfiType) []const u8 {
    return switch (t) {
        .int => "int",
        .long => "long",
        .double => "double",
        .float => "float",
        .string => "string",
        .pointer => "pointer",
        .void_type => "void",
        .bool_type => "bool",
        .uint8 => "uint8",
        .int8 => "int8",
        .int16 => "int16",
        .int32 => "int32",
        .int64 => "int64",
        .uint16 => "uint16",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .size_type => "size_t",
        .char_type => "char",
    };
}

fn schemeTypeName(v: Value) []const u8 {
    if (types.isFixnum(v)) return "integer";
    if (types.isFlonum(v)) return "flonum";
    if (types.isString(v)) return "string";
    if (types.isBignum(v)) return "integer";
    if (v == types.TRUE or v == types.FALSE) return "boolean";
    if (types.isChar(v)) return "character";
    if (types.isBytevector(v)) return "bytevector";
    if (types.isFfiCallback(v)) return "ffi-callback";
    if (types.isRationalObj(v)) return "rational";
    if (types.isNil(v)) return "nil";
    if (types.isPair(v)) return "pair";
    if (types.isSymbol(v)) return "symbol";
    return "object";
}

fn toIntArgOpt(v: Value) ?i64 {
    if (v == types.TRUE) return 1;
    if (v == types.FALSE) return 0;
    if (types.isChar(v)) return @intCast(types.toChar(v));
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

fn toCheckedInt(comptime T: type, v: Value) error{TypeError}!T {
    const wide = toIntArgOpt(v) orelse return error.TypeError;
    return std.math.cast(T, wide) orelse return error.TypeError;
}

fn toUnsignedArgOpt(v: Value) ?u64 {
    if (v == types.TRUE) return 1;
    if (v == types.FALSE) return 0;
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        if (bn.len == 0) return 0;
        if (bn.len > 1) return null;
        if (!bn.positive) return null;
        return bn.limbs[0];
    }
    const fixnum = types.toFixnum(v);
    if (fixnum < 0) return null;
    return @intCast(fixnum);
}

fn toLongArg(v: Value, declared: FfiType) error{TypeError}!c_long {
    if (declared == .uint64 or declared == .size_type) {
        const unsigned = toUnsignedArgOpt(v) orelse return error.TypeError;
        const narrowed = std.math.cast(c_ulong, unsigned) orelse return error.TypeError;
        return @bitCast(narrowed);
    }
    return toCheckedInt(c_long, v);
}

/// C-truthiness of a value bound to a `bool` FFI parameter. `validateArg`
/// guarantees such a value is #t, #f, a fixnum, or a bignum, so any nonzero
/// integer is true and zero is false.
fn boolArgIsTrue(v: Value) bool {
    if (v == types.TRUE) return true;
    if (v == types.FALSE) return false;
    if (types.isFixnum(v)) return types.toFixnum(v) != 0;
    if (types.isBignum(v)) return types.toBignum(v).len != 0;
    return false;
}

/// Convert a Scheme string Value to a null-terminated C string using a stack buffer.
/// Returns null if the value is not a string or the string is too long.
fn toCString(v: Value, buf: *[4096]u8) ?[*:0]const u8 {
    if (!types.isString(v)) return null;
    const str = types.toObject(v).as(types.SchemeString);
    if (str.len >= buf.len) return null;
    if (std.mem.indexOfScalar(u8, str.data[0..str.len], 0) != null) return null;
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

fn marshalLongOrUlong(result: c_long, orig_type: FfiType, gc: *memory.GC) !Value {
    if (orig_type == .uint32 or orig_type == .uint64 or orig_type == .size_type) {
        const unsigned: u64 = @bitCast(@as(i64, result));
        if (orig_type == .uint32) {
            const val: u64 = unsigned & 0xFFFFFFFF;
            return types.makeFixnum(@intCast(val));
        }
        if (unsigned <= @as(u64, @intCast(MAX_FIXNUM)))
            return types.makeFixnum(@intCast(unsigned));
        const limbs_buf = [1]u64{unsigned};
        return gc.allocBignumFromLimbs(&limbs_buf, 1, true) catch return error.OutOfMemory;
    }
    return marshalLongReturn(result, gc);
}

/// Convert a C return value to a Scheme Value based on return type.
fn marshalReturn(comptime T: type, result: T, rt: FfiType, gc: *memory.GC) !Value {
    if (T == f64) {
        return types.makeFlonum(result);
    } else if (T == c_int) {
        return types.makeFixnum(@intCast(result));
    } else if (T == c_long) {
        return marshalLongOrUlong(result, rt, gc);
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
    if (t == .bool_type and (v == types.TRUE or v == types.FALSE)) return true;
    if (t == .char_type and types.isChar(v)) return true;
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

fn checkNarrowIntRange(v: Value, declared: FfiType) error{TypeError}!void {
    if (declared == .uint64 or declared == .size_type) {
        if (toUnsignedArgOpt(v) == null) return error.TypeError;
        return;
    }
    const wide = switch (declared) {
        .int8, .uint8, .int16, .uint16, .char_type, .uint32 => toIntArgOpt(v) orelse return error.TypeError,
        else => return,
    };
    switch (declared) {
        .int8 => {
            if (wide < std.math.minInt(i8) or wide > std.math.maxInt(i8)) return error.TypeError;
        },
        .uint8, .char_type => {
            if (wide < 0 or wide > std.math.maxInt(u8)) return error.TypeError;
        },
        .int16 => {
            if (wide < std.math.minInt(i16) or wide > std.math.maxInt(i16)) return error.TypeError;
        },
        .uint16 => {
            if (wide < 0 or wide > std.math.maxInt(u16)) return error.TypeError;
        },
        .uint32 => {
            if (wide < 0 or wide > std.math.maxInt(u32)) return error.TypeError;
        },
        else => {},
    }
}

fn validateArgsDetailed(ffi_fn: *types.FfiFunction, args: []const Value, vm: *VM) !void {
    for (0..ffi_fn.param_count) |i| {
        if (!validateArg(args[i], ffi_fn.param_types[i])) {
            vm.setErrorDetail("'{s}': argument {d} must be {s}, got {s}", .{
                ffi_fn.name, i + 1, ffiTypeName(ffi_fn.param_types[i]), schemeTypeName(args[i]),
            });
            return error.TypeError;
        }
        checkNarrowIntRange(args[i], ffi_fn.param_types[i]) catch {
            vm.setErrorDetail("'{s}': argument {d} out of range for {s}", .{
                ffi_fn.name, i + 1, ffiTypeName(ffi_fn.param_types[i]),
            });
            return error.TypeError;
        };
        const nt = normalizeType(ffi_fn.param_types[i]);
        if (nt == .int and ffi_fn.param_types[i] != .bool_type) {
            if (toIntArgOpt(args[i])) |wide| {
                if (std.math.cast(c_int, wide) == null) {
                    vm.setErrorDetail("'{s}': argument {d} out of range for {s}", .{
                        ffi_fn.name, i + 1, ffiTypeName(ffi_fn.param_types[i]),
                    });
                    return error.TypeError;
                }
            }
        }
        if (nt == .string) {
            const str = types.toObject(args[i]).as(types.SchemeString);
            if (str.len >= 4096) {
                vm.setErrorDetail("'{s}': argument {d} string too long ({d} bytes, max 4095)", .{
                    ffi_fn.name, i + 1, str.len,
                });
                return error.TypeError;
            }
            if (std.mem.indexOfScalar(u8, str.data[0..str.len], 0) != null) {
                vm.setErrorDetail("'{s}': argument {d} string contains NUL byte", .{
                    ffi_fn.name, i + 1,
                });
                return error.TypeError;
            }
        }
    }
}

/// Coerce every `bool` argument to exactly #t/#f before dispatch so that only
/// 0 or 1 is loaded into the C `_Bool` trampoline parameter. Passing any other
/// integer is undefined behavior at the C ABI level and traps under
/// UBSan-instrumented libraries (e.g. those built with `zig cc`). This mirrors
/// the return direction, which normalizes any nonzero result to #t. `args.len`
/// equals `param_count` (arity is checked by every caller); over-arity calls
/// pass through untouched because the dispatch `switch` rejects them.
fn normalizeBoolArgs(ffi_fn: *types.FfiFunction, args: []const Value, buf: *[5]Value) []const Value {
    if (args.len > buf.len) return args;
    var has_bool = false;
    for (ffi_fn.param_types[0..args.len]) |t| {
        if (t == .bool_type) has_bool = true;
    }
    if (!has_bool) return args;
    for (args, 0..) |v, i| {
        buf[i] = if (ffi_fn.param_types[i] == .bool_type)
            (if (boolArgIsTrue(v)) types.TRUE else types.FALSE)
        else
            v;
    }
    return buf[0..args.len];
}

const canonical_types = [_]FfiType{ .int, .long, .double, .float, .string, .pointer, .void_type };

fn CParamType(comptime t: FfiType) type {
    return switch (t) {
        .int => c_int,
        .long => c_long,
        .double => f64,
        .float => f32,
        .string => [*:0]const u8,
        .pointer => ?*anyopaque,
        else => unreachable,
    };
}

fn CReturnType(comptime t: FfiType) type {
    return switch (t) {
        .int => c_int,
        .long => c_long,
        .double => f64,
        .float => f32,
        .string => ?[*:0]const u8,
        .pointer => ?*anyopaque,
        .void_type => void,
        else => unreachable,
    };
}

fn marshalArg(comptime t: FfiType, v: Value, buf: *[4096]u8, declared: FfiType) !CParamType(t) {
    return switch (t) {
        .int => toCheckedInt(c_int, v),
        .long => toLongArg(v, declared),
        .double => types.toF64(v),
        .float => @floatCast(types.toF64(v)),
        .string => toCString(v, buf) orelse return error.TypeError,
        .pointer => marshalToPointer(v),
        else => unreachable,
    };
}

fn marshalRetValue(comptime t: FfiType, result: CReturnType(t), orig_type: FfiType, gc: *memory.GC) !Value {
    return switch (t) {
        .int => types.makeFixnum(@intCast(result)),
        .long => marshalLongOrUlong(result, orig_type, gc),
        .double => types.makeFlonum(result),
        .float => types.makeFlonum(@floatCast(result)),
        .string => if (result) |cstr| marshalCStringReturn(cstr, gc) else types.FALSE,
        .pointer => marshalPointerReturn(result, gc),
        .void_type => types.VOID,
        else => unreachable,
    };
}

fn callFfiGeneric(comptime N: u4, ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    @setEvalBranchQuota(50_000);
    const rt = normalizeType(ffi_fn.return_type);

    var string_bufs: [N][4096]u8 = undefined;

    inline for (canonical_types) |ct_ret| {
        if (rt == ct_ret) {
            if (N == 0) {
                const f: *const fn () callconv(.c) CReturnType(ct_ret) = @ptrCast(@alignCast(ffi_fn.symbol));
                const result = f();
                return marshalRetValue(ct_ret, result, ffi_fn.return_type, gc);
            }

            const p0 = normalizeType(ffi_fn.param_types[0]);
            inline for (canonical_types[0 .. canonical_types.len - 1]) |ct0| {
                if (p0 == ct0) {
                    if (N == 1) {
                        const f: *const fn (CParamType(ct0)) callconv(.c) CReturnType(ct_ret) = @ptrCast(@alignCast(ffi_fn.symbol));
                        const a0 = try marshalArg(ct0, args[0], &string_bufs[0], ffi_fn.param_types[0]);
                        const result = f(a0);
                        return marshalRetValue(ct_ret, result, ffi_fn.return_type, gc);
                    }

                    const p1 = normalizeType(ffi_fn.param_types[1]);
                    inline for (canonical_types[0 .. canonical_types.len - 1]) |ct1| {
                        if (p1 == ct1) {
                            if (N == 2) {
                                const f: *const fn (CParamType(ct0), CParamType(ct1)) callconv(.c) CReturnType(ct_ret) = @ptrCast(@alignCast(ffi_fn.symbol));
                                const a0 = try marshalArg(ct0, args[0], &string_bufs[0], ffi_fn.param_types[0]);
                                const a1 = try marshalArg(ct1, args[1], &string_bufs[1], ffi_fn.param_types[1]);
                                const result = f(a0, a1);
                                return marshalRetValue(ct_ret, result, ffi_fn.return_type, gc);
                            }

                            if (N >= 3) {
                                const p2 = normalizeType(ffi_fn.param_types[2]);
                                inline for (canonical_types[0 .. canonical_types.len - 1]) |ct2| {
                                    if (p2 == ct2) {
                                        if (N == 3) {
                                            const f: *const fn (CParamType(ct0), CParamType(ct1), CParamType(ct2)) callconv(.c) CReturnType(ct_ret) = @ptrCast(@alignCast(ffi_fn.symbol));
                                            const a0 = try marshalArg(ct0, args[0], &string_bufs[0], ffi_fn.param_types[0]);
                                            const a1 = try marshalArg(ct1, args[1], &string_bufs[1], ffi_fn.param_types[1]);
                                            const a2 = try marshalArg(ct2, args[2], &string_bufs[2], ffi_fn.param_types[2]);
                                            const result = f(a0, a1, a2);
                                            return marshalRetValue(ct_ret, result, ffi_fn.return_type, gc);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return error.TypeError;
}

/// Main FFI call dispatcher. Routes to arity-specific handlers.
pub fn callFfi(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC, vm: *VM) !Value {
    if (types.isFfiLibrary(ffi_fn.library)) {
        const lib = types.toObject(ffi_fn.library).as(types.FfiLibrary);
        if (lib.handle == null) {
            vm.setErrorDetail("'{s}': FFI library is closed", .{ffi_fn.name});
            return error.TypeError;
        }
    }
    try validateArgsDetailed(ffi_fn, args, vm);
    var bool_buf: [5]Value = undefined;
    const call_args = normalizeBoolArgs(ffi_fn, args, &bool_buf);
    const result = switch (ffi_fn.param_count) {
        0 => callFfiGeneric(0, ffi_fn, call_args, gc),
        1 => callFfiGeneric(1, ffi_fn, call_args, gc),
        2 => callFfiGeneric(2, ffi_fn, call_args, gc),
        3 => callFfiGeneric(3, ffi_fn, call_args, gc),
        4 => callFfi4(ffi_fn, call_args, gc),
        5 => callFfi5(ffi_fn, call_args, gc),
        else => {
            vm.setErrorDetail("'{s}': unsupported parameter count ({d})", .{ ffi_fn.name, ffi_fn.param_count });
            return error.TypeError;
        },
    } catch {
        if (vm.last_error_detail_len == 0)
            vm.setErrorDetail("'{s}': unsupported FFI signature", .{ffi_fn.name});
        return error.TypeError;
    };
    if (ffi_fn.return_type == .bool_type) {
        if (types.isFixnum(result))
            return if (types.toFixnum(result) != 0) types.TRUE else types.FALSE;
    }
    if (ffi_fn.return_type == .char_type) {
        if (types.isFixnum(result)) {
            const code = types.toFixnum(result);
            if (code >= 0 and code <= 255)
                return types.makeChar(@intCast(code));
        }
    }
    return result;
}

// ---------------------------------------------------------------------------
// 4-arg dispatcher (curated — comptime would exceed eval branch quota)
// ---------------------------------------------------------------------------

fn callFfi4(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = normalizeType(ffi_fn.param_types[0]);
    const p1 = normalizeType(ffi_fn.param_types[1]);
    const p2 = normalizeType(ffi_fn.param_types[2]);
    const p3 = normalizeType(ffi_fn.param_types[3]);
    const rt = normalizeType(ffi_fn.return_type);

    var bufs: [4][4096]u8 = undefined;

    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, c_long, c_long, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.long, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.long, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]));
        return types.VOID;
    }

    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, c_long, c_long, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.long, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.long, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.pointer, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .long and p3 == .long and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long, c_long) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.long, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.long, args[3], &bufs[3], ffi_fn.param_types[3]));
        return marshalRetValue(.pointer, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .long and p2 == .long and p3 == .long and rt == .int) {
        const f: *const fn (?*anyopaque, c_long, c_long, c_long) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.long, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.long, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.long, args[3], &bufs[3], ffi_fn.param_types[3]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.pointer, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]));
        return types.VOID;
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.pointer, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]));
        return marshalRetValue(.pointer, result, ffi_fn.return_type, gc);
    }

    return error.TypeError;
}

// ---------------------------------------------------------------------------
// 5-arg dispatcher (curated — comptime would exceed eval branch quota)
// ---------------------------------------------------------------------------

fn callFfi5(ffi_fn: *types.FfiFunction, args: []const Value, gc: *memory.GC) !Value {
    const p0 = normalizeType(ffi_fn.param_types[0]);
    const p1 = normalizeType(ffi_fn.param_types[1]);
    const p2 = normalizeType(ffi_fn.param_types[2]);
    const p3 = normalizeType(ffi_fn.param_types[3]);
    const p4 = normalizeType(ffi_fn.param_types[4]);
    const rt = normalizeType(ffi_fn.return_type);

    var bufs: [5][4096]u8 = undefined;

    if (p0 == .double and p1 == .double and p2 == .double and p3 == .double and p4 == .double and rt == .double) {
        const f: *const fn (f64, f64, f64, f64, f64) callconv(.c) f64 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.double, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.double, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.double, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.double, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.double, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.double, result, ffi_fn.return_type, gc);
    }

    if (p0 == .double and p1 == .double and p2 == .double and p3 == .double and p4 == .double and rt == .void_type) {
        const f: *const fn (f64, f64, f64, f64, f64) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(try marshalArg(.double, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.double, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.double, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.double, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.double, args[4], &bufs[4], ffi_fn.param_types[4]));
        return types.VOID;
    }

    if (p0 == .int and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .int) {
        const f: *const fn (c_int, c_int, c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.int, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.int, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.int, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.int, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.int, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .int and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .void_type) {
        const f: *const fn (c_int, c_int, c_int, c_int, c_int) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(try marshalArg(.int, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.int, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.int, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.int, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.int, args[4], &bufs[4], ffi_fn.param_types[4]));
        return types.VOID;
    }

    if (p0 == .int and p1 == .int and p2 == .int and p3 == .pointer and p4 == .int and rt == .int) {
        const f: *const fn (c_int, c_int, c_int, ?*anyopaque, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.int, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.int, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.int, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.int, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .long and p3 == .int and p4 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, c_long, c_int, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.long, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.int, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.pointer, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .int) {
        const f: *const fn (?*anyopaque, c_int, c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.int, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.int, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.int, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.int, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .string and p1 == .string and p2 == .string and p3 == .string and p4 == .string and rt == .int) {
        const f: *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.string, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.string, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.string, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.string, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.string, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .string and p1 == .string and p2 == .string and p3 == .string and p4 == .string and rt == .string) {
        const f: *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.string, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.string, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.string, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.string, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.string, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.string, result, ffi_fn.return_type, gc);
    }

    if (p0 == .string and p1 == .int and p2 == .int and p3 == .int and p4 == .int and rt == .int) {
        const f: *const fn ([*:0]const u8, c_int, c_int, c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.string, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.int, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.int, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.int, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.int, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and p4 == .pointer and rt == .int) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.pointer, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.pointer, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.int, result, ffi_fn.return_type, gc);
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and p4 == .pointer and rt == .void_type) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(ffi_fn.symbol));
        f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.pointer, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.pointer, args[4], &bufs[4], ffi_fn.param_types[4]));
        return types.VOID;
    }

    if (p0 == .pointer and p1 == .pointer and p2 == .pointer and p3 == .pointer and p4 == .pointer and rt == .pointer) {
        const f: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(ffi_fn.symbol));
        const result = f(try marshalArg(.pointer, args[0], &bufs[0], ffi_fn.param_types[0]), try marshalArg(.pointer, args[1], &bufs[1], ffi_fn.param_types[1]), try marshalArg(.pointer, args[2], &bufs[2], ffi_fn.param_types[2]), try marshalArg(.pointer, args[3], &bufs[3], ffi_fn.param_types[3]), try marshalArg(.pointer, args[4], &bufs[4], ffi_fn.param_types[4]));
        return marshalRetValue(.pointer, result, ffi_fn.return_type, gc);
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

test "validateArg: accepts Scheme booleans for bool_type" {
    try std.testing.expect(validateArg(types.TRUE, .bool_type));
    try std.testing.expect(validateArg(types.FALSE, .bool_type));
    try std.testing.expect(validateArg(types.makeFixnum(1), .bool_type));
    try std.testing.expect(validateArg(types.makeFixnum(0), .bool_type));
}

test "toIntArgOpt: converts Scheme booleans to 0/1" {
    try std.testing.expectEqual(@as(?i64, 1), toIntArgOpt(types.TRUE));
    try std.testing.expectEqual(@as(?i64, 0), toIntArgOpt(types.FALSE));
}

test "validateArg: accepts bignum for pointer type" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const big = try gc.allocBignumFromI64(0x1000);
    try std.testing.expect(validateArg(big, .pointer));
}

test "checkNarrowIntRange: int8 accepts [-128, 127]" {
    try checkNarrowIntRange(types.makeFixnum(-128), .int8);
    try checkNarrowIntRange(types.makeFixnum(127), .int8);
    try checkNarrowIntRange(types.makeFixnum(0), .int8);
}

test "checkNarrowIntRange: int8 rejects out of range" {
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(128), .int8));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-129), .int8));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(200), .int8));
}

test "checkNarrowIntRange: uint8 accepts [0, 255]" {
    try checkNarrowIntRange(types.makeFixnum(0), .uint8);
    try checkNarrowIntRange(types.makeFixnum(255), .uint8);
    try checkNarrowIntRange(types.makeFixnum(100), .uint8);
}

test "checkNarrowIntRange: uint8 rejects out of range" {
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(256), .uint8));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-1), .uint8));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(300), .uint8));
}

test "checkNarrowIntRange: int16 accepts [-32768, 32767]" {
    try checkNarrowIntRange(types.makeFixnum(-32768), .int16);
    try checkNarrowIntRange(types.makeFixnum(32767), .int16);
    try checkNarrowIntRange(types.makeFixnum(0), .int16);
}

test "checkNarrowIntRange: int16 rejects out of range" {
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(32768), .int16));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-32769), .int16));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(40000), .int16));
}

test "checkNarrowIntRange: uint16 accepts [0, 65535]" {
    try checkNarrowIntRange(types.makeFixnum(0), .uint16);
    try checkNarrowIntRange(types.makeFixnum(65535), .uint16);
    try checkNarrowIntRange(types.makeFixnum(1000), .uint16);
}

test "checkNarrowIntRange: uint16 rejects out of range" {
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(65536), .uint16));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-1), .uint16));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(70000), .uint16));
}

test "checkNarrowIntRange: uint32 accepts [0, 4294967295]" {
    try checkNarrowIntRange(types.makeFixnum(0), .uint32);
    try checkNarrowIntRange(types.makeFixnum(4294967295), .uint32);
    try checkNarrowIntRange(types.makeFixnum(2147483648), .uint32);
}

test "checkNarrowIntRange: uint32 rejects out of range" {
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-1), .uint32));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(4294967296), .uint32));
}

test "checkNarrowIntRange: char_type same as uint8" {
    try checkNarrowIntRange(types.makeFixnum(0), .char_type);
    try checkNarrowIntRange(types.makeFixnum(255), .char_type);
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(256), .char_type));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-1), .char_type));
}

test "toIntArgOpt: extracts codepoint from Scheme character" {
    try std.testing.expectEqual(@as(?i64, 65), toIntArgOpt(types.makeChar('A')));
    try std.testing.expectEqual(@as(?i64, 0), toIntArgOpt(types.makeChar(0)));
    try std.testing.expectEqual(@as(?i64, 255), toIntArgOpt(types.makeChar(255)));
    try std.testing.expectEqual(@as(?i64, 0x03BB), toIntArgOpt(types.makeChar(0x03BB)));
}

test "validateArg: accepts Scheme characters for char_type" {
    try std.testing.expect(validateArg(types.makeChar('A'), .char_type));
    try std.testing.expect(validateArg(types.makeChar(0), .char_type));
    try std.testing.expect(validateArg(types.makeFixnum(65), .char_type));
}

test "checkNarrowIntRange: char_type accepts Scheme characters in 0-255" {
    try checkNarrowIntRange(types.makeChar('A'), .char_type);
    try checkNarrowIntRange(types.makeChar(0), .char_type);
    try checkNarrowIntRange(types.makeChar(255), .char_type);
}

test "checkNarrowIntRange: char_type rejects codepoint > 255" {
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeChar(256), .char_type));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeChar(0x03BB), .char_type));
}

test "checkNarrowIntRange: uint64 rejects negative" {
    try checkNarrowIntRange(types.makeFixnum(0), .uint64);
    try checkNarrowIntRange(types.makeFixnum(1000000), .uint64);
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-1), .uint64));
}

test "checkNarrowIntRange: size_type rejects negative" {
    try checkNarrowIntRange(types.makeFixnum(0), .size_type);
    try checkNarrowIntRange(types.makeFixnum(1000000), .size_type);
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(types.makeFixnum(-1), .size_type));
}

test "checkNarrowIntRange: non-narrow types pass through" {
    try checkNarrowIntRange(types.makeFixnum(5000000000), .int);
    try checkNarrowIntRange(types.makeFixnum(-5000000000), .long);
    try checkNarrowIntRange(types.makeFixnum(999999), .int32);
    try checkNarrowIntRange(types.makeFixnum(-999999), .int64);
}

test "toUnsignedArgOpt: fixnum values" {
    try std.testing.expectEqual(@as(?u64, 0), toUnsignedArgOpt(types.makeFixnum(0)));
    try std.testing.expectEqual(@as(?u64, 42), toUnsignedArgOpt(types.makeFixnum(42)));
    try std.testing.expectEqual(@as(?u64, null), toUnsignedArgOpt(types.makeFixnum(-1)));
}

test "toUnsignedArgOpt: booleans" {
    try std.testing.expectEqual(@as(?u64, 1), toUnsignedArgOpt(types.TRUE));
    try std.testing.expectEqual(@as(?u64, 0), toUnsignedArgOpt(types.FALSE));
}

test "toUnsignedArgOpt: bignum full u64 range" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val_2_63: u64 = 1 << 63;
    const limbs_63 = [1]u64{val_2_63};
    const bn_2_63 = try gc.allocBignumFromLimbs(&limbs_63, 1, true);
    try std.testing.expectEqual(@as(?u64, val_2_63), toUnsignedArgOpt(bn_2_63));

    const val_max: u64 = std.math.maxInt(u64);
    const limbs_max = [1]u64{val_max};
    const bn_max = try gc.allocBignumFromLimbs(&limbs_max, 1, true);
    try std.testing.expectEqual(@as(?u64, val_max), toUnsignedArgOpt(bn_max));
}

test "toUnsignedArgOpt: rejects negative and multi-limb bignums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const neg = try gc.allocBignumFromI64(-42);
    try std.testing.expectEqual(@as(?u64, null), toUnsignedArgOpt(neg));

    const limbs_multi = [2]u64{ 1, 1 };
    const multi = try gc.allocBignumFromLimbs(&limbs_multi, 2, true);
    try std.testing.expectEqual(@as(?u64, null), toUnsignedArgOpt(multi));
}

test "toLongArg: signed types use signed path" {
    const v = types.makeFixnum(42);
    try std.testing.expectEqual(@as(c_long, 42), try toLongArg(v, .long));
    try std.testing.expectEqual(@as(c_long, 42), try toLongArg(v, .int64));
}

test "toLongArg: uint64 accepts values >= 2^63" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val: u64 = (1 << 63) + 1;
    const limbs = [1]u64{val};
    const bn = try gc.allocBignumFromLimbs(&limbs, 1, true);
    const result = try toLongArg(bn, .uint64);
    const round_trip: u64 = @bitCast(result);
    try std.testing.expectEqual(val, round_trip);
}

test "toLongArg: size_type accepts values >= 2^63" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val: u64 = std.math.maxInt(u64);
    const limbs = [1]u64{val};
    const bn = try gc.allocBignumFromLimbs(&limbs, 1, true);
    const result = try toLongArg(bn, .size_type);
    const round_trip: u64 = @bitCast(result);
    try std.testing.expectEqual(val, round_trip);
}

test "toLongArg: uint64 rejects negative" {
    try std.testing.expectError(error.TypeError, toLongArg(types.makeFixnum(-1), .uint64));
}

test "checkNarrowIntRange: uint64 accepts bignum >= 2^63" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val: u64 = 1 << 63;
    const limbs = [1]u64{val};
    const bn = try gc.allocBignumFromLimbs(&limbs, 1, true);
    try checkNarrowIntRange(bn, .uint64);
    try checkNarrowIntRange(bn, .size_type);
}

test "checkNarrowIntRange: uint64 rejects negative bignum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const neg = try gc.allocBignumFromI64(-1);
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(neg, .uint64));
    try std.testing.expectError(error.TypeError, checkNarrowIntRange(neg, .size_type));
}
