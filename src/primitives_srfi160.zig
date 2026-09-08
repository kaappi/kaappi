//! SRFI 160 — Homogeneous numeric vector libraries.
//!
//! A single native heap type (`types.NumericVector`, discriminated by
//! `types.NumericElementKind`) backs all 11 non-u8 element kinds -- u8
//! stays a plain R7RS bytevector (SRFI 160 explicitly recommends
//! u8vector/bytevector identity, and this codebase's pre-existing SRFI 4
//! port already relies on it). This mirrors SRFI 237's own RecordType
//! extension: one struct with a discriminator beats 11 parallel ObjectTags
//! and 11x the GC-touch-point duplication.
//!
//! This file supplies exactly six generic, `%`-prefixed primitives.
//! Everything else -- every SRFI-4-shaped constructor/predicate/accessor
//! and SRFI 160's much larger SRFI-133-shaped extended surface
//! (map/fold/filter/unfold/copy!/append/generator/comparator/etc.) -- is
//! portable Scheme in lib/srfi/160/*.sld, generated once per element kind
//! from a shared syntax-rules pattern, built entirely on these six.
//!
//! Registered under `.srfi_160_primitives`, not a bare `.srfi_160`: the
//! public `(srfi 160 <tag>)` libraries are `.sld` files, and the registry
//! shadows a same-named `.sld` outright (see `.srfi_237_primitives`/
//! `.srfi_181_primitives`/`.srfi_248_primitives` for the identical,
//! already-solved problem).
//!
//! Nothing here touches platform.zig, threads, or FFI -- every operation
//! is plain heap/Value manipulation, so this library needs no
//! sandboxAllowed/wasmAvailable exclusion (falls into Lib's `else => true`
//! default for both).
//!
//! Multi-byte elements are stored in host-native byte order (matching
//! printer.zig's own numeric-vector display arm) -- the #TAG( literal syntax
//! and the .sbc constant codec both carry kind-tagged raw bytes, and both
//! halves live in the same binary reading its own output, so native order
//! avoids needless byte-swaps on big-endian hosts (s390x, ppc64le).

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NumericVector = types.NumericVector;
const NumericElementKind = types.NumericElementKind;
const PrimitiveError = primitives.PrimitiveError;
const typeError = primitives.typeError;
const indexError = primitives.indexError;
const argError = primitives.argError;
const LS = primitives.LibSet;

const SRFI160 = LS.initOne(.srfi_160_primitives);
const native_endian = builtin.cpu.arch.endian();

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "%make-numeric-vector", .func = &makeNumericVectorFn, .arity = .{ .exact = 3 }, .libs = SRFI160 },
    .{ .name = "%numeric-vector?", .func = &numericVectorCheckFn, .arity = .{ .exact = 1 }, .libs = SRFI160 },
    .{ .name = "%numeric-vector-kind", .func = &numericVectorKindFn, .arity = .{ .exact = 1 }, .libs = SRFI160 },
    .{ .name = "%numeric-vector-length", .func = &numericVectorLengthFn, .arity = .{ .exact = 1 }, .libs = SRFI160 },
    .{ .name = "%numeric-vector-ref", .func = &numericVectorRefFn, .arity = .{ .exact = 2 }, .libs = SRFI160 },
    .{ .name = "%numeric-vector-set!", .func = &numericVectorSetFn, .arity = .{ .exact = 3 }, .libs = SRFI160 },
};

fn asNumericVector(v: Value) *NumericVector {
    return types.toObject(v).as(NumericVector);
}

fn parseKind(name: []const u8) ?NumericElementKind {
    inline for (@typeInfo(NumericElementKind).@"enum".fields) |f| {
        if (std.mem.eql(u8, name, f.name)) return @enumFromInt(f.value);
    }
    return null;
}

// ---------------------------------------------------------------------------
// Exact-integer extraction (fixnum or single/zero-limb bignum -- anything
// wider genuinely can't fit any of s8..u64, so it's rejected up front).
// ---------------------------------------------------------------------------

const MagSign = struct { mag: u64, positive: bool };

/// Keeping `.too_wide` distinct from `.not_exact` is what stops a multi-limb
/// bignum from being reported as the wrong *type*: it genuinely is an exact
/// integer, so collapsing the two (as a plain `?MagSign` did) answered
/// "expected exact integer, got #<bignum>" and pointed the reader at a problem
/// that isn't there -- the value's only fault is not fitting s8..u64
/// (kaappi#1916). `.too_wide` carries the sign because the unsigned case
/// distinguishes "negative" from "too large", exactly as it does for a fixnum.
const ExactMag = union(enum) {
    fits: MagSign,
    too_wide: struct { positive: bool },
    not_exact,
};

fn magnitudeAndSign(val: Value) ExactMag {
    if (types.isFixnum(val)) {
        const n = types.toFixnum(val);
        return .{ .fits = .{ .mag = if (n < 0) @intCast(-n) else @intCast(n), .positive = n >= 0 } };
    }
    if (types.isBignum(val)) {
        const bn = types.toBignum(val);
        if (bn.len == 0) return .{ .fits = .{ .mag = 0, .positive = true } };
        if (bn.len > 1) return .{ .too_wide = .{ .positive = bn.positive } };
        return .{ .fits = .{ .mag = bn.limbs[0], .positive = bn.positive } };
    }
    return .not_exact;
}

fn makeExactFromI64(gc: *memory.GC, n: i64) PrimitiveError!Value {
    const fixnum_min: i64 = -(@as(i64, 1) << 47);
    const fixnum_max: i64 = (@as(i64, 1) << 47) - 1;
    if (n >= fixnum_min and n <= fixnum_max) return types.makeFixnum(n);
    return gc.allocBignumFromI64(n) catch PrimitiveError.OutOfMemory;
}

fn makeExactFromU64(gc: *memory.GC, n: u64) PrimitiveError!Value {
    const fixnum_max: u64 = (@as(u64, 1) << 47) - 1;
    if (n <= fixnum_max) return types.makeFixnum(@intCast(n));
    if (n <= @as(u64, std.math.maxInt(i64))) return gc.allocBignumFromI64(@intCast(n)) catch PrimitiveError.OutOfMemory;
    var limbs = [_]u64{n};
    return gc.allocBignumFromLimbs(&limbs, 1, true) catch PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Encode (Value -> element bytes) / decode (element bytes -> Value)
// ---------------------------------------------------------------------------

/// The typed failure reasons of element coercion. The pure core
/// (`encodeElementRaw`) answers only with these -- the reader's #TAG(
/// literal syntax shares it and must not touch the VM error-detail channel
/// a primitive failure would write (a stale detail set during reading
/// would otherwise leak into an unrelated runtime error's report). The
/// primitive-shaped wrapper (`encodeElement`) maps the same reasons onto
/// typeError/argError. ONE range/exactness table serves both callers, so a
/// literal and a constructor can never disagree about what an element is.
pub const ElementCoerceError = error{
    not_a_number,
    not_exact_integer,
    not_real,
    out_of_range,
    negative_unsigned,
};

fn signedElement(val: Value, comptime bits: u7) ElementCoerceError!i64 {
    const ms = switch (magnitudeAndSign(val)) {
        .fits => |m| m,
        .too_wide => return error.out_of_range,
        .not_exact => return error.not_exact_integer,
    };
    const shift: u6 = bits - 1;
    const max_mag_pos: u64 = (@as(u64, 1) << shift) - 1;
    const max_mag_neg: u64 = @as(u64, 1) << shift;
    if (ms.positive) {
        if (ms.mag > max_mag_pos) return error.out_of_range;
        return @intCast(ms.mag);
    }
    if (ms.mag > max_mag_neg) return error.out_of_range;
    if (ms.mag == max_mag_neg) {
        // Only reachable when bits == 64 and mag == 2^63 (i64::MIN) -- for
        // bits < 64, max_mag_neg fits comfortably in a positive i64 already,
        // so the general path below would work too; this keeps it exact.
        if (bits == 64) return std.math.minInt(i64);
        return -@as(i64, @intCast(ms.mag));
    }
    return -@as(i64, @intCast(ms.mag));
}

fn unsignedElement(val: Value, comptime bits: u7) ElementCoerceError!u64 {
    const ms = switch (magnitudeAndSign(val)) {
        .fits => |m| m,
        // A negative multi-limb bignum is rejected for being negative, not
        // for being wide -- the same reason, and the same mapped failure, a
        // negative fixnum gets below.
        .too_wide => |w| return if (w.positive) error.out_of_range else error.negative_unsigned,
        .not_exact => return error.not_exact_integer,
    };
    if (!ms.positive and ms.mag != 0) return error.negative_unsigned;
    const max_mag: u64 = if (bits == 64) std.math.maxInt(u64) else blk: {
        const shift: u6 = bits;
        break :blk (@as(u64, 1) << shift) - 1;
    };
    if (ms.mag > max_mag) return error.out_of_range;
    return ms.mag;
}

fn realElement(val: Value) ElementCoerceError!f64 {
    if (types.isComplex(val)) return error.not_real;
    if (types.isFixnum(val) or types.isFlonum(val) or types.isBignum(val) or types.isRationalObj(val)) {
        return types.toF64(val);
    }
    return error.not_a_number;
}

const ComplexParts = struct { re: f64, im: f64 };

fn complexElementParts(val: Value) ElementCoerceError!ComplexParts {
    if (types.isComplex(val)) {
        const c = types.toComplex(val);
        return .{ .re = try realElement(c.real), .im = try realElement(c.imag) };
    }
    return .{ .re = try realElement(val), .im = 0.0 };
}

/// Pure Value -> element bytes: no VM state, no error details. Shared by
/// `%numeric-vector-set!` (through `encodeElement`) and the reader's #TAG(
/// literal syntax (reader_datum.zig's readNumericVector), so a literal and a
/// constructor call can never disagree about what an element may be.
pub fn encodeElementRaw(kind: NumericElementKind, val: Value, out: []u8) ElementCoerceError!void {
    switch (kind) {
        .s8 => out[0] = @bitCast(@as(i8, @intCast(try signedElement(val, 8)))),
        .u16 => std.mem.writeInt(u16, out[0..2], @intCast(try unsignedElement(val, 16)), native_endian),
        .s16 => std.mem.writeInt(i16, out[0..2], @intCast(try signedElement(val, 16)), native_endian),
        .u32 => std.mem.writeInt(u32, out[0..4], @intCast(try unsignedElement(val, 32)), native_endian),
        .s32 => std.mem.writeInt(i32, out[0..4], @intCast(try signedElement(val, 32)), native_endian),
        .u64 => std.mem.writeInt(u64, out[0..8], try unsignedElement(val, 64), native_endian),
        .s64 => std.mem.writeInt(i64, out[0..8], try signedElement(val, 64), native_endian),
        .f32 => {
            const f = try realElement(val);
            std.mem.writeInt(u32, out[0..4], @bitCast(@as(f32, @floatCast(f))), native_endian);
        },
        .f64 => {
            const f = try realElement(val);
            std.mem.writeInt(u64, out[0..8], @bitCast(f), native_endian);
        },
        .c64 => {
            const parts = try complexElementParts(val);
            std.mem.writeInt(u32, out[0..4], @bitCast(@as(f32, @floatCast(parts.re))), native_endian);
            std.mem.writeInt(u32, out[4..8], @bitCast(@as(f32, @floatCast(parts.im))), native_endian);
        },
        .c128 => {
            const parts = try complexElementParts(val);
            std.mem.writeInt(u64, out[0..8], @bitCast(parts.re), native_endian);
            std.mem.writeInt(u64, out[8..16], @bitCast(parts.im), native_endian);
        },
    }
}

fn kindIsUnsigned(kind: NumericElementKind) bool {
    return switch (kind) {
        .u16, .u32, .u64 => true,
        else => false,
    };
}

fn kindIntegerBits(kind: NumericElementKind) u7 {
    return switch (kind) {
        .s8 => 8,
        .u16, .s16 => 16,
        .u32, .s32, .f32, .c64 => 32,
        .u64, .s64, .f64, .c128 => 64,
    };
}

/// The primitive-shaped wrapper: same coercion as `encodeElementRaw`, with
/// the typed failure reasons mapped onto the typeError/argError reports a
/// `%`-primitive caller expects. The messages match the pre-refactor ones
/// exactly, including kaappi#1916's too-wide-vs-not-exact distinction.
pub fn encodeElement(proc: []const u8, kind: NumericElementKind, val: Value, out: []u8) PrimitiveError!void {
    encodeElementRaw(kind, val, out) catch |err| switch (err) {
        error.not_a_number, error.not_exact_integer => switch (kind) {
            .f32, .f64, .c64, .c128 => return typeError(proc, "real number", val),
            else => return typeError(proc, "exact integer", val),
        },
        error.not_real => return typeError(proc, "real number", val),
        error.negative_unsigned => return argError(proc, "negative integer for an unsigned {d}-bit element", .{kindIntegerBits(kind)}),
        error.out_of_range => {
            if (kindIsUnsigned(kind)) {
                return argError(proc, "integer does not fit an unsigned {d}-bit element", .{kindIntegerBits(kind)});
            }
            return argError(proc, "integer does not fit a signed {d}-bit element", .{kindIntegerBits(kind)});
        },
    };
}

fn decodeElement(gc: *memory.GC, kind: NumericElementKind, bytes: []const u8) PrimitiveError!Value {
    return switch (kind) {
        .s8 => types.makeFixnum(@as(i8, @bitCast(bytes[0]))),
        .u16 => types.makeFixnum(std.mem.readInt(u16, bytes[0..2], native_endian)),
        .s16 => types.makeFixnum(std.mem.readInt(i16, bytes[0..2], native_endian)),
        .u32 => types.makeFixnum(std.mem.readInt(u32, bytes[0..4], native_endian)),
        .s32 => types.makeFixnum(std.mem.readInt(i32, bytes[0..4], native_endian)),
        .u64 => try makeExactFromU64(gc, std.mem.readInt(u64, bytes[0..8], native_endian)),
        .s64 => try makeExactFromI64(gc, std.mem.readInt(i64, bytes[0..8], native_endian)),
        .f32 => types.makeFlonum(@as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], native_endian)))),
        .f64 => types.makeFlonum(@bitCast(std.mem.readInt(u64, bytes[0..8], native_endian))),
        .c64 => blk: {
            const re: f32 = @bitCast(std.mem.readInt(u32, bytes[0..4], native_endian));
            const im: f32 = @bitCast(std.mem.readInt(u32, bytes[4..8], native_endian));
            // Both components are preserved, including a +0.0 imaginary part:
            // the element decodes to the complex 1.5+0.0i, matching the
            // reader and make-rectangular, where an inexact zero imag keeps
            // the value complex (R7RS 6.2.6, kaappi#2269). -0.0 keeps its
            // sign -- real information the printer preserves as "1.5-0.0i".
            break :blk gc.allocComplex(types.makeFlonum(re), types.makeFlonum(im)) catch PrimitiveError.OutOfMemory;
        },
        .c128 => blk: {
            const re: f64 = @bitCast(std.mem.readInt(u64, bytes[0..8], native_endian));
            const im: f64 = @bitCast(std.mem.readInt(u64, bytes[8..16], native_endian));
            // Same component-preserving decode as .c64 (kaappi#2269).
            break :blk gc.allocComplex(types.makeFlonum(re), types.makeFlonum(im)) catch PrimitiveError.OutOfMemory;
        },
    };
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

fn makeNumericVectorFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isSymbol(args[0])) return typeError("%make-numeric-vector", "symbol", args[0]);
    const kind = parseKind(types.symbolName(args[0])) orelse return argError("%make-numeric-vector", "unknown element kind", .{});
    if (!types.isFixnum(args[1])) return typeError("%make-numeric-vector", "exact integer", args[1]);
    const raw_len = types.toFixnum(args[1]);
    if (raw_len < 0) return argError("%make-numeric-vector", "negative length {d}", .{raw_len});
    const width = kind.elementWidth();
    // Compare in u64 (wide enough for any raw_len/usize combination) before
    // narrowing to usize -- on wasm32 (usize = u32) a fixnum-range length
    // (up to 2^47) would otherwise panic @intCast instead of raising a
    // catchable error.
    const max_elements: u64 = @as(u64, memory.GC.max_payload_bytes) / @as(u64, width);
    if (@as(u64, @intCast(raw_len)) > max_elements) {
        return argError("%make-numeric-vector", "length {d} exceeds the maximum of {d} elements", .{ raw_len, max_elements });
    }
    const len: usize = @intCast(raw_len);

    var fill_buf: [16]u8 = undefined;
    try encodeElement("%make-numeric-vector", kind, args[2], fill_buf[0..width]);
    return gc.allocNumericVectorFill(kind, len, fill_buf[0..width]) catch PrimitiveError.OutOfMemory;
}

fn numericVectorCheckFn(args: []const Value) PrimitiveError!Value {
    return if (types.isNumericVector(args[0])) types.TRUE else types.FALSE;
}

fn numericVectorKindFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isNumericVector(args[0])) return typeError("%numeric-vector-kind", "numeric-vector", args[0]);
    const nv = asNumericVector(args[0]);
    return gc.allocSymbol(@tagName(nv.kind)) catch PrimitiveError.OutOfMemory;
}

fn numericVectorLengthFn(args: []const Value) PrimitiveError!Value {
    if (!types.isNumericVector(args[0])) return typeError("%numeric-vector-length", "numeric-vector", args[0]);
    const nv = asNumericVector(args[0]);
    return types.makeFixnum(@intCast(nv.data.len / nv.kind.elementWidth()));
}

fn numericVectorRefFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isNumericVector(args[0])) return typeError("%numeric-vector-ref", "numeric-vector", args[0]);
    const nv = asNumericVector(args[0]);
    if (!types.isFixnum(args[1])) return typeError("%numeric-vector-ref", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    const width = nv.kind.elementWidth();
    const len = nv.data.len / width;
    // u64 comparison before narrowing (kaappi#1912): see fixnumIndexInBounds --
    // the same hazard makeNumericVectorFn guards for the length argument.
    if (raw_idx < 0 or !primitives.fixnumIndexInBounds(raw_idx, len)) return indexError("%numeric-vector-ref", raw_idx, len);
    const idx: usize = @intCast(raw_idx);
    return decodeElement(gc, nv.kind, nv.data[idx * width ..][0..width]);
}

fn numericVectorSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isNumericVector(args[0])) return typeError("%numeric-vector-set!", "numeric-vector", args[0]);
    const nv = asNumericVector(args[0]);
    // A #TAG( literal reads back immutable, exactly like #u8( and #(...)
    // literals — set-car!/bytevector-u8-set! on a literal raise, so
    // TAGvector-set! must too. The message names the kind ("immutable
    // s16vector") so the user knows which literal they hit.
    if (types.toObject(args[0]).flags.immutable)
        return argError("%numeric-vector-set!", "cannot mutate an immutable {s}vector", .{@tagName(nv.kind)});
    if (!types.isFixnum(args[1])) return typeError("%numeric-vector-set!", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    const width = nv.kind.elementWidth();
    const len = nv.data.len / width;
    // u64 comparison before narrowing (kaappi#1912): see fixnumIndexInBounds.
    if (raw_idx < 0 or !primitives.fixnumIndexInBounds(raw_idx, len)) return indexError("%numeric-vector-set!", raw_idx, len);
    const idx: usize = @intCast(raw_idx);
    try encodeElement("%numeric-vector-set!", nv.kind, args[2], nv.data[idx * width ..][0..width]);
    return types.VOID;
}
