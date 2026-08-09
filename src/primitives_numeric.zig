const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const bignum_mod = @import("bignum.zig");
const arith = @import("primitives_arithmetic.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;
const toF64 = primitives.toF64;
const anyFlonum = primitives.anyFlonum;
fn anyBignum(args: []const Value) bool {
    for (args) |a| {
        if (types.isBignum(a)) return true;
    }
    return false;
}
const makeFlonumVal = primitives.makeFlonumVal;
const toF64Ext = arith.toF64Ext;
const gcdTwo = arith.gcdTwo;

fn safeFloatToExactInt(f: f64) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return safeFloatToExactIntGc(gc, f);
}

fn safeFloatToExactIntGc(gc: *memory.GC, f: f64) PrimitiveError!Value {
    const min_i64: f64 = @floatFromInt(std.math.minInt(i64));
    const max_i64_f: f64 = @floatFromInt(std.math.maxInt(i64));
    if (f >= min_i64 and f < max_i64_f) {
        return try arith.makeFixnumCheckedGc(gc, @intFromFloat(f));
    }
    return floatToBignumGc(gc, f);
}

fn floatToBignum(f: f64) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return floatToBignumGc(gc, f);
}

fn floatToBignumGc(gc: *memory.GC, f: f64) PrimitiveError!Value {
    const positive = f >= 0;
    const abs_f = @abs(f);
    const bits: u64 = @bitCast(abs_f);
    const raw_exp = @as(u11, @intCast((bits >> 52) & 0x7FF));
    if (raw_exp == 0 or raw_exp == 0x7FF) return PrimitiveError.TypeError; // bare-ok: subnormal/inf guard
    const mantissa: u64 = (bits & 0x000FFFFFFFFFFFFF) | 0x0010000000000000;
    const exp: i16 = @as(i16, @intCast(raw_exp)) - 1023 - 52;
    if (exp < 0) {
        const shift: u6 = @intCast(-exp);
        const result = mantissa >> shift;
        if (result <= @as(u64, @intCast(std.math.maxInt(i48)))) {
            const signed: i64 = if (positive) @intCast(result) else -@as(i64, @intCast(result));
            return types.makeFixnum(signed);
        }
        const limbs = [1]u64{result};
        return gc.allocBignumFromLimbs(&limbs, 1, positive) catch return PrimitiveError.OutOfMemory;
    }
    const shift: u6 = @intCast(@min(exp, 63));
    if (exp <= 10) {
        const result = mantissa << shift;
        const limbs = [1]u64{result};
        return gc.allocBignumFromLimbs(&limbs, 1, positive) catch return PrimitiveError.OutOfMemory;
    }
    const uexp: u16 = @intCast(exp);
    const word_shift = uexp / 64;
    const bit_shift: u6 = @intCast(uexp % 64);
    const total_limbs = word_shift + 1 + @as(u16, if (bit_shift > 10) 1 else 0);
    var limbs = gc.allocator.alloc(u64, total_limbs) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(limbs);
    @memset(limbs, 0);
    limbs[word_shift] = mantissa << bit_shift;
    if (bit_shift > 10 and word_shift + 1 < total_limbs) {
        const complement: u6 = @intCast(64 - @as(u7, bit_shift));
        limbs[word_shift + 1] = mantissa >> complement;
    }
    var len = total_limbs;
    while (len > 0 and limbs[len - 1] == 0) len -= 1;
    return gc.allocBignumFromLimbs(limbs[0..total_limbs], len, positive) catch return PrimitiveError.OutOfMemory;
}
const raiseDivByZero = arith.raiseDivByZero;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "floor", .func = &floorFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "ceiling", .func = &ceilingFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "truncate", .func = &truncateFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "round", .func = &roundFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "exact?", .func = &exactP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "inexact?", .func = &inexactP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "exact-integer?", .func = &exactIntegerP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "exact", .func = &exactFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "inexact", .func = &inexactFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "expt", .func = &exptFn, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "square", .func = &squareFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "sqrt", .func = &sqrtFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "exact-integer-sqrt", .func = &exactIntegerSqrt, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "sin", .func = &sinFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "cos", .func = &cosFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "tan", .func = &tanFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "asin", .func = &asinFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "acos", .func = &acosFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "atan", .func = &atanFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "exp", .func = &expFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "log", .func = &logFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_inexact, .scheme_r5rs }) },
    .{ .name = "finite?", .func = &finiteP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_inexact) },
    .{ .name = "infinite?", .func = &infiniteP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_inexact) },
    .{ .name = "nan?", .func = &nanP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_inexact) },
    .{ .name = "number->string", .func = &numberToString, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "string->number", .func = &stringToNumber, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "make-rectangular", .func = &makeRectangular, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_complex, .scheme_r5rs }) },
    .{ .name = "make-polar", .func = &makePolar, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_complex, .scheme_r5rs }) },
    .{ .name = "real-part", .func = &realPart, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_complex, .scheme_r5rs }) },
    .{ .name = "imag-part", .func = &imagPart, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_complex, .scheme_r5rs }) },
    .{ .name = "magnitude", .func = &magnitudeFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_complex, .scheme_r5rs }) },
    .{ .name = "angle", .func = &angleFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_complex, .scheme_r5rs }) },
    .{ .name = "floor-quotient", .func = &floorQuotient, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "floor-remainder", .func = &floorRemainder, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "floor/", .func = &floorDivide, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "truncate-quotient", .func = &truncateQuotient, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "truncate-remainder", .func = &truncateRemainder, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "truncate/", .func = &truncateDivide, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "numerator", .func = &numeratorFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "denominator", .func = &denominatorFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "rationalize", .func = &rationalizeFn, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "exact->inexact", .func = &inexactFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "inexact->exact", .func = &exactFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
};

// ---------------------------------------------------------------------------
// Rounding
// ---------------------------------------------------------------------------

fn rationalFloor(r: *types.Rational) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const q = bignum_mod.quotient(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
    var slot = gc.rootedSlot(q) catch return PrimitiveError.OutOfMemory;
    defer slot.release();
    const rem = bignum_mod.remainder(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
    if (bignum_mod.isZero(rem)) return bignum_mod.demote(slot.get());
    if (bignum_mod.isNegative(r.numerator)) {
        return bignum_mod.demote(bignum_mod.sub(gc, slot.get(), types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory);
    }
    return bignum_mod.demote(slot.get());
}

fn rationalCeiling(r: *types.Rational) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const q = bignum_mod.quotient(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
    var slot = gc.rootedSlot(q) catch return PrimitiveError.OutOfMemory;
    defer slot.release();
    const rem = bignum_mod.remainder(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
    if (bignum_mod.isZero(rem)) return bignum_mod.demote(slot.get());
    if (bignum_mod.isPositive(r.numerator) or bignum_mod.isZero(r.numerator)) {
        return bignum_mod.demote(bignum_mod.add(gc, slot.get(), types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory);
    }
    return bignum_mod.demote(slot.get());
}

fn rationalTruncate(r: *types.Rational) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return bignum_mod.demote(bignum_mod.quotient(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory);
}

fn rationalRound(r: *types.Rational) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const q = bignum_mod.quotient(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
    var slot_q = gc.rootedSlot(q) catch return PrimitiveError.OutOfMemory;
    defer slot_q.release();
    const rem = bignum_mod.remainder(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
    if (bignum_mod.isZero(rem)) return bignum_mod.demote(slot_q.get());
    var slot_rem = gc.rootedSlot(rem) catch return PrimitiveError.OutOfMemory;
    defer slot_rem.release();
    const abs_rem = bignum_mod.absVal(gc, rem) catch return PrimitiveError.OutOfMemory;
    const double_rem = bignum_mod.mul(gc, abs_rem, types.makeFixnum(2)) catch return PrimitiveError.OutOfMemory;
    const cmp = bignum_mod.compare(double_rem, r.denominator);
    if (cmp < 0) {
        return bignum_mod.demote(q);
    }
    if (cmp > 0) {
        return bignum_mod.demote(if (bignum_mod.isNegative(rem))
            bignum_mod.sub(gc, q, types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory
        else
            bignum_mod.add(gc, q, types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory);
    }
    // Exact half — ties to even
    if (bignum_mod.isEven(q)) return bignum_mod.demote(q);
    return bignum_mod.demote(if (bignum_mod.isNegative(rem))
        bignum_mod.sub(gc, q, types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory
    else
        bignum_mod.add(gc, q, types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory);
}

fn floorFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) return rationalFloor(types.toRational(args[0]));
    if (types.isFlonum(args[0])) return makeFlonumVal(@floor(types.toFlonum(args[0])));
    return primitives.typeError("floor", "number", args[0]);
}

fn ceilingFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) return rationalCeiling(types.toRational(args[0]));
    if (types.isFlonum(args[0])) return makeFlonumVal(@ceil(types.toFlonum(args[0])));
    return primitives.typeError("ceiling", "number", args[0]);
}

fn truncateFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) return rationalTruncate(types.toRational(args[0]));
    if (types.isFlonum(args[0])) return makeFlonumVal(@trunc(types.toFlonum(args[0])));
    return primitives.typeError("truncate", "number", args[0]);
}

fn bankersRound(f: f64) f64 {
    const floored = @floor(f);
    const frac = @abs(f - floored);
    if (frac == 0.5) {
        const min_i64: f64 = @floatFromInt(std.math.minInt(i64));
        const max_i64_f: f64 = @floatFromInt(std.math.maxInt(i64));
        if (floored >= min_i64 and floored < max_i64_f) {
            const i: i64 = @intFromFloat(floored);
            return if (@mod(i, @as(i64, 2)) != 0) @ceil(f) else floored;
        }
        return @round(f);
    }
    return @round(f);
}

fn roundFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) return rationalRound(types.toRational(args[0]));
    if (types.isFlonum(args[0])) return makeFlonumVal(bankersRound(types.toFlonum(args[0])));
    return primitives.typeError("round", "number", args[0]);
}

// ---------------------------------------------------------------------------
// Exactness
// ---------------------------------------------------------------------------

fn exactP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.TRUE;
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        // A complex is exact iff both components are exact (their own
        // types carry the exactness — kaappi#2166).
        return if (types.isExactNumber(c.real) and types.isExactNumber(c.imag)) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn inexactP(args: []const Value) PrimitiveError!Value {
    if (types.isFlonum(args[0])) return types.TRUE;
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return if (!types.isExactNumber(c.real) or !types.isExactNumber(c.imag)) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn exactIntegerP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0]) or types.isBignum(args[0])) types.TRUE else types.FALSE;
}

/// Digit-exact conversion of a flonum to its exact value, using an explicit
/// GC (gc_instance may be unset in reader-only contexts, kaappi#2166).
fn exactFlonumGc(gc: *memory.GC, f: f64) PrimitiveError!Value {
    if (std.math.isNan(f) or std.math.isInf(f)) return primitives.typeError("exact", "finite number", types.makeFlonum(f));
    if (f == 0.0) return types.makeFixnum(0);
    if (f == @trunc(f)) return try safeFloatToExactIntGc(gc, f);
    const positive = f >= 0;
    const bits: u64 = @bitCast(@abs(f));
    const raw_exp = @as(u11, @intCast((bits >> 52) & 0x7FF));
    const mantissa: u64 = if (raw_exp == 0)
        bits & 0x000FFFFFFFFFFFFF
    else
        (bits & 0x000FFFFFFFFFFFFF) | 0x0010000000000000;
    const exp: i16 = if (raw_exp == 0)
        1 - 1023 - 52
    else
        @as(i16, @intCast(raw_exp)) - 1023 - 52;
    if (exp >= 0) return try safeFloatToExactIntGc(gc, f);
    // Rational mantissa / 2^(-exp). Reduce by trailing zeros in mantissa.
    var m = mantissa;
    var neg_exp: u16 = @intCast(-exp);
    while (m != 0 and m & 1 == 0 and neg_exp > 0) {
        m >>= 1;
        neg_exp -= 1;
    }
    const num_val = blk: {
        if (m <= @as(u64, @intCast(std.math.maxInt(i48)))) {
            const signed: i64 = if (positive) @intCast(m) else -@as(i64, @intCast(m));
            break :blk types.makeFixnum(signed);
        }
        break :blk gc.allocBignumFromLimbs(&[1]u64{m}, 1, positive) catch return PrimitiveError.OutOfMemory;
    };
    if (neg_exp == 0) return num_val;
    var slot_num = gc.rootedSlot(num_val) catch return PrimitiveError.OutOfMemory;
    defer slot_num.release();
    // Build denominator 2^neg_exp
    const den_val = blk: {
        if (neg_exp < 47) {
            break :blk types.makeFixnum(@as(i64, 1) << @intCast(neg_exp));
        }
        const word_shift = neg_exp / 64;
        const bit_shift: u6 = @intCast(neg_exp % 64);
        const total: usize = @as(usize, word_shift) + 1;
        var limbs = gc.allocator.alloc(u64, total) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(limbs);
        @memset(limbs, 0);
        limbs[word_shift] = @as(u64, 1) << bit_shift;
        break :blk gc.allocBignumFromLimbs(limbs, total, true) catch return PrimitiveError.OutOfMemory;
    };
    var slot_den = gc.rootedSlot(den_val) catch return PrimitiveError.OutOfMemory;
    defer slot_den.release();
    return gc.allocRational(slot_num.get(), slot_den.get()) catch return PrimitiveError.OutOfMemory;
}

/// Digit-exact conversion of a component Value to exact, using an explicit
/// GC — exactFn relies on the global gc_instance, which is unset in
/// reader-only contexts (kaappi#2166).
pub fn exactComponentGc(gc: *memory.GC, v: Value) PrimitiveError!Value {
    if (types.isFixnum(v) or types.isBignum(v) or types.isRationalObj(v)) return v;
    if (types.isFlonum(v)) return exactFlonumGc(gc, types.toFlonum(v));
    return primitives.typeError("exact", "number", v);
}

pub fn exactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) return args[0]; // already exact
    if (types.isFlonum(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return exactFlonumGc(gc, types.toFlonum(args[0]));
    }
    if (types.isComplex(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        // Convert each component digit-exactly (exactFlonumGc on a flonum
        // yields the exact rational it actually holds); both components are
        // finite, so the conversion cannot refuse them (kaappi#2166).
        if (types.isExactNumber(c.real) and types.isExactNumber(c.imag)) return args[0];
        const real_exact = try exactComponentGc(gc, c.real);
        var slot = gc.rootedSlot(real_exact) catch return PrimitiveError.OutOfMemory;
        defer slot.release();
        const imag_exact = try exactComponentGc(gc, c.imag);
        return makeComplexOrRealV(gc, slot.get(), imag_exact) catch return PrimitiveError.OutOfMemory;
    }
    return primitives.typeError("exact", "number", args[0]);
}

pub fn inexactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFlonum(args[0])) return args[0];
    if (types.isFixnum(args[0])) return makeFlonumVal(@floatFromInt(types.toFixnum(args[0])));
    if (types.isBignum(args[0])) return makeFlonumVal(bignum_mod.toF64(args[0]));
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        return makeFlonumVal(types.rationalToF64(r.numerator, r.denominator));
    }
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        // Already all-inexact: return unchanged. Rebuilding through
        // makeComplexOrRealV would demote a stored inexact zero imag
        // (-2.5+0.0i) to the real -2.5, losing the complexness the reader
        // deliberately keeps ((real? -2.5+0.0i) => #f, kaappi#2166).
        if (!types.isExactNumber(c.real)) return args[0];
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const real_i = try inexactFn(&[1]Value{c.real});
        var slot = gc.rootedSlot(real_i) catch return PrimitiveError.OutOfMemory;
        defer slot.release();
        const imag_i = try inexactFn(&[1]Value{c.imag});
        return makeComplexOrRealV(gc, slot.get(), imag_i) catch return PrimitiveError.OutOfMemory;
    }
    return primitives.typeError("inexact", "number", args[0]);
}

// ---------------------------------------------------------------------------
// Powers and roots
// ---------------------------------------------------------------------------

fn exptFn(args: []const Value) PrimitiveError!Value {
    if ((types.isFixnum(args[0]) or types.isBignum(args[0])) and types.isFixnum(args[1])) {
        const exp = types.toFixnum(args[1]);
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (exp >= 0) {
            return bignum_mod.expt(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
        }
        const pos_exp = types.makeFixnum(-exp);
        const denom = bignum_mod.expt(gc, args[0], pos_exp) catch return PrimitiveError.OutOfMemory;
        return arith.makeRationalReduced(gc, types.makeFixnum(1), denom);
    }
    if (types.isRationalObj(args[0]) and types.isFixnum(args[1])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const r = types.toRational(args[0]);
        const exp = types.toFixnum(args[1]);
        if (exp == 0) return types.makeFixnum(1);
        const abs_exp = types.makeFixnum(if (exp < 0) -exp else exp);
        const num_pow = bignum_mod.expt(gc, r.numerator, abs_exp) catch return PrimitiveError.OutOfMemory;
        var slot = gc.rootedSlot(num_pow) catch return PrimitiveError.OutOfMemory;
        defer slot.release();
        const den_pow = bignum_mod.expt(gc, r.denominator, abs_exp) catch return PrimitiveError.OutOfMemory;
        if (exp > 0) {
            return arith.makeRationalReduced(gc, num_pow, den_pow);
        }
        return arith.makeRationalReduced(gc, den_pow, num_pow);
    }
    // Complex exponentiation: z^w = e^(w * ln(z))
    if (types.isComplex(args[0]) or types.isComplex(args[1])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        // Exact base with an exact integer exponent: repeated complex
        // multiplication over the exact tower, which is exact-closed
        // (kaappi#2166). Everything else falls to the f64 paths below.
        if (types.isComplex(args[0]) and types.isFixnum(args[1])) {
            const n = types.toFixnum(args[1]);
            const c = types.toComplex(args[0]);
            if (types.isExactNumber(c.real) and types.isExactNumber(c.imag)) {
                return complexExptExact(gc, args[0], n);
            }
        }
        var zr: f64 = undefined;
        var zi: f64 = undefined;
        var wr: f64 = undefined;
        var wi: f64 = undefined;
        if (types.isComplex(args[0])) {
            const c = types.toComplex(args[0]);
            zr = try toF64Ext(c.real);
            zi = try toF64Ext(c.imag);
        } else {
            zr = toF64Ext(args[0]) catch return primitives.typeError("expt", "number", args[0]);
            zi = 0.0;
        }
        if (types.isComplex(args[1])) {
            const c = types.toComplex(args[1]);
            wr = try toF64Ext(c.real);
            wi = try toF64Ext(c.imag);
        } else {
            wr = toF64Ext(args[1]) catch return primitives.typeError("expt", "number", args[1]);
            wi = 0.0;
        }
        // Special case: integer exponent with complex base — use repeated multiplication
        if (wi == 0.0 and wr == @trunc(wr) and @abs(wr) < 100) {
            const n: i64 = @intFromFloat(wr);
            if (n == 0) return makeComplexOrReal(1.0, 0.0);
            var rr: f64 = 1.0;
            var ri: f64 = 0.0;
            var count = if (n < 0) -n else n;
            while (count > 0) : (count -= 1) {
                const new_r = rr * zr - ri * zi;
                const new_i = rr * zi + ri * zr;
                rr = new_r;
                ri = new_i;
            }
            if (n < 0) {
                const mag_sq = rr * rr + ri * ri;
                rr = rr / mag_sq;
                ri = -ri / mag_sq;
            }
            if (@abs(ri) < 1e-15) ri = 0.0;
            if (@abs(rr) < 1e-15) rr = 0.0;
            return makeComplexOrReal(rr, ri);
        }
        // General: z^w = e^(w * ln(z))
        return complexPowGeneral(zr, zi, wr, wi);
    }
    const base_f = try toF64Ext(args[0]);
    const exp_f = try toF64Ext(args[1]);
    // A negative real base raised to a non-integer real exponent has no real
    // result (e.g. (-8)^(1/3)) — promote to complex, matching sqrt's handling
    // of negative reals. Integer exponents are excluded since std.math.pow
    // already handles those correctly for a negative base.
    if (std.math.isFinite(base_f) and base_f < 0.0 and
        std.math.isFinite(exp_f) and exp_f != @trunc(exp_f))
    {
        return complexPowGeneral(base_f, 0.0, exp_f, 0.0);
    }
    return makeFlonumVal(std.math.pow(f64, base_f, exp_f));
}

// z^w = e^(w * ln(z)), where ln(z) = ln|z| + i*arg(z).
fn complexPowGeneral(zr: f64, zi: f64, wr: f64, wi: f64) PrimitiveError!Value {
    const mag = @sqrt(zr * zr + zi * zi);
    const arg = std.math.atan2(zi, zr);
    const ln_r = @log(mag);
    const ln_i = arg;
    // w * ln(z)
    const prod_r = wr * ln_r - wi * ln_i;
    const prod_i = wr * ln_i + wi * ln_r;
    // e^(prod_r + i*prod_i)
    const exp_r = @exp(prod_r);
    const result_r = exp_r * @cos(prod_i);
    const result_i = exp_r * @sin(prod_i);
    return makeComplexOrReal(result_r, result_i);
}

/// Exact complex exponentiation: (a+bi)^n for an exact complex base and an
/// exact integer exponent, by square-and-multiply over the exact tower
/// (which is exact-closed, R7RS 6.2.2 / kaappi#2166). A negative exponent
/// reciprocates the base-first power; a zero exponent yields exact 1. O(log
/// n), so a large exponent like (expt +i 1000000000) => 1 cannot hang
/// (review).
fn complexExptExact(gc: *memory.GC, base_in: Value, n: i64) PrimitiveError!Value {
    var result: Value = types.makeFixnum(1);
    var slot_r = gc.rootedSlot(result) catch return PrimitiveError.OutOfMemory;
    defer slot_r.release();
    var slot_b = gc.rootedSlot(base_in) catch return PrimitiveError.OutOfMemory;
    defer slot_b.release();
    var m: u64 = @intCast(if (n < 0) -n else n);
    while (m > 0) {
        if (m & 1 == 1) {
            result = try arith.mul(&.{ slot_r.get(), slot_b.get() });
            slot_r.set(result);
        }
        m >>= 1;
        if (m > 0) {
            const sq = try arith.mul(&.{ slot_b.get(), slot_b.get() });
            slot_b.set(sq);
        }
    }
    if (n < 0) {
        result = try arith.divFn(&[1]Value{slot_r.get()});
        slot_r.set(result);
    }
    return slot_r.get();
}

fn squareFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) {
        const n = types.toFixnum(args[0]);
        const r = @mulWithOverflow(n, n);
        if (r[1] != 0) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            return bignum_mod.mul(gc, args[0], args[0]) catch return PrimitiveError.OutOfMemory;
        }
        return types.makeFixnum(r[0]);
    }
    if (types.isBignum(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return bignum_mod.mul(gc, args[0], args[0]) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        return makeFlonumVal(f * f);
    }
    if (types.isRationalObj(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const rat = types.toRational(args[0]);
        const num_sq = bignum_mod.mul(gc, rat.numerator, rat.numerator) catch return PrimitiveError.OutOfMemory;
        var slot = gc.rootedSlot(num_sq) catch return PrimitiveError.OutOfMemory;
        defer slot.release();
        const den_sq = bignum_mod.mul(gc, rat.denominator, rat.denominator) catch return PrimitiveError.OutOfMemory;
        return @import("primitives_arithmetic.zig").makeRationalReduced(gc, num_sq, den_sq);
    }
    return primitives.typeError("square", "number", args[0]);
}

fn sqrtFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const re = try toF64Ext(c.real);
        const im = try toF64Ext(c.imag);
        const mag = @sqrt(re * re + im * im);
        const r = @sqrt((mag + re) / 2.0);
        const i_sign: f64 = if (im < 0.0) -1.0 else 1.0;
        const i = i_sign * @sqrt((mag - re) / 2.0);
        return makeComplexOrReal(r, i);
    }
    if (types.isBignum(args[0]) and !bignum_mod.isNegative(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const r = try isqrtNonNegative(gc, args[0]);
        if (bignum_mod.isZero(r.rem)) return r.root;
    }
    if (types.isRationalObj(args[0])) {
        const rat = types.toRational(args[0]);
        if (!bignum_mod.isNegative(rat.numerator)) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            const num_r = try isqrtNonNegative(gc, rat.numerator);
            if (bignum_mod.isZero(num_r.rem)) {
                var slot_root = gc.rootedSlot(num_r.root) catch return PrimitiveError.OutOfMemory;
                defer slot_root.release();
                const den_r = try isqrtNonNegative(gc, rat.denominator);
                if (bignum_mod.isZero(den_r.rem)) {
                    return arith.makeRationalReduced(gc, num_r.root, den_r.root);
                }
            }
        }
    }
    const f = try toF64(args[0]);
    if (f < 0.0) {
        const imag = @sqrt(-f);
        return makeComplexOrReal(0.0, imag);
    }
    const result = @sqrt(f);
    if (types.isFixnum(args[0])) {
        const ri: i64 = @intFromFloat(result);
        if (ri * ri == types.toFixnum(args[0])) return types.makeFixnum(ri);
    }
    return makeFlonumVal(result);
}

const IsqrtResult = struct { root: Value, rem: Value };

/// Floor integer square root of a non-negative exact integer (fixnum or
/// bignum). Returns the root and remainder n - root*root, demoted to fixnums
/// when they fit. The results are unrooted: callers must root them before
/// allocating.
fn isqrtNonNegative(gc: *memory.GC, n_val: Value) PrimitiveError!IsqrtResult {
    if (types.isFixnum(n_val)) {
        const n = types.toFixnum(n_val);
        const f: f64 = @floatFromInt(n);
        var s: i64 = @intFromFloat(@sqrt(f));
        while (s * s > n) s -= 1;
        while ((s + 1) * (s + 1) <= n) s += 1;
        return .{ .root = types.makeFixnum(s), .rem = types.makeFixnum(n - s * s) };
    }
    {
        const n = n_val;
        // Use f64 sqrt as initial guess. When the number is too large
        // for f64, compute bit-length and use (n >> shift) for the
        // approximation, then shift the result back.
        const f64_val = bignum_mod.toF64(n);
        var s: Value = undefined;
        if (std.math.isInf(f64_val)) {
            // Estimate bit length from limb count, use n >> (bits-52)
            // rounded to even, then sqrt, then shift result back.
            const bn = types.toBignum(n);
            const bit_len: u32 = @intCast(bn.len * 64);
            const shift: u32 = ((bit_len - 52) + 1) & ~@as(u32, 1);
            // Divide by 2^shift using bignum quotient with a power of 2
            var pow2 = types.makeFixnum(1);
            var i: u32 = 0;
            while (i < shift) : (i += 1) {
                pow2 = bignum_mod.mul(gc, pow2, types.makeFixnum(2)) catch return PrimitiveError.OutOfMemory;
            }
            const shifted = bignum_mod.quotient(gc, n, pow2) catch return PrimitiveError.OutOfMemory;
            const approx = @sqrt(bignum_mod.toF64(shifted));
            const approx_i: i64 = if (approx < 1.0) 1 else @intFromFloat(approx);
            var approx_val = try arith.makeFixnumChecked(approx_i);
            // Multiply by 2^(shift/2) to get back
            var j: u32 = 0;
            while (j < shift / 2) : (j += 1) {
                approx_val = bignum_mod.mul(gc, approx_val, types.makeFixnum(2)) catch return PrimitiveError.OutOfMemory;
            }
            s = approx_val;
        } else {
            const approx = @sqrt(f64_val);
            const approx_i: i64 = if (approx < 1.0) 1 else if (approx >= @as(f64, @floatFromInt(std.math.maxInt(i48)))) std.math.maxInt(i48) else @intFromFloat(approx);
            s = try arith.makeFixnumChecked(approx_i);
        }
        var slot_s = gc.rootedSlot(s) catch return PrimitiveError.OutOfMemory;
        defer slot_s.release();
        // Newton iterations: s = (s + n/s) / 2
        const two = types.makeFixnum(2);
        var iters: usize = 0;
        while (iters < 500) : (iters += 1) {
            if (bignum_mod.isZero(s)) break;
            const q = bignum_mod.quotient(gc, n, s) catch return PrimitiveError.OutOfMemory;
            const sum = bignum_mod.add(gc, s, q) catch return PrimitiveError.OutOfMemory;
            const next = bignum_mod.quotient(gc, sum, two) catch return PrimitiveError.OutOfMemory;
            if (bignum_mod.compare(next, s) == 0) break;
            s = next;
            slot_s.set(s);
        }
        // Adjust downward: ensure s*s <= n
        var s2 = bignum_mod.mul(gc, s, s) catch return PrimitiveError.OutOfMemory;
        var slot_s2 = gc.rootedSlot(s2) catch return PrimitiveError.OutOfMemory;
        defer slot_s2.release();
        while (bignum_mod.compare(s2, n) > 0) {
            s = bignum_mod.sub(gc, s, types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory;
            slot_s.set(s);
            s2 = bignum_mod.mul(gc, s, s) catch return PrimitiveError.OutOfMemory;
            slot_s2.set(s2);
        }
        // Adjust upward: ensure (s+1)^2 > n
        var s1 = bignum_mod.add(gc, s, types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory;
        var slot_s1 = gc.rootedSlot(s1) catch return PrimitiveError.OutOfMemory;
        defer slot_s1.release();
        var s1_sq = bignum_mod.mul(gc, s1, s1) catch return PrimitiveError.OutOfMemory;
        while (bignum_mod.compare(s1_sq, n) <= 0) {
            s = s1;
            slot_s.set(s);
            s2 = s1_sq;
            slot_s2.set(s2);
            s1 = bignum_mod.add(gc, s, types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory;
            slot_s1.set(s1);
            s1_sq = bignum_mod.mul(gc, s1, s1) catch return PrimitiveError.OutOfMemory;
        }
        const rem = bignum_mod.sub(gc, n, s2) catch return PrimitiveError.OutOfMemory;
        return .{ .root = bignum_mod.demote(s), .rem = bignum_mod.demote(rem) };
    }
}

fn exactIntegerSqrt(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0]) and !types.isBignum(args[0])) {
        return primitives.typeError("exact-integer-sqrt", "exact integer", args[0]);
    }
    if (bignum_mod.isNegative(args[0])) {
        return primitives.typeError("exact-integer-sqrt", "non-negative integer", args[0]);
    }
    const r = try isqrtNonNegative(gc, args[0]);
    var slot_root = gc.rootedSlot(r.root) catch return PrimitiveError.OutOfMemory;
    defer slot_root.release();
    var slot_rem = gc.rootedSlot(r.rem) catch return PrimitiveError.OutOfMemory;
    defer slot_rem.release();
    const vals = [_]Value{ r.root, r.rem };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Trigonometry
// ---------------------------------------------------------------------------

fn sinFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const re_c = try toF64Ext(c.real);
        const im_c = try toF64Ext(c.imag);
        const re = @sin(re_c) * std.math.cosh(im_c);
        const im = @cos(re_c) * std.math.sinh(im_c);
        return makeComplexOrReal(re, im);
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@sin(f));
}

fn cosFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const re_c = try toF64Ext(c.real);
        const im_c = try toF64Ext(c.imag);
        const re = @cos(re_c) * std.math.cosh(im_c);
        const im = -@sin(re_c) * std.math.sinh(im_c);
        return makeComplexOrReal(re, im);
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@cos(f));
}

fn tanFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const re_c = try toF64Ext(c.real);
        const im_c = try toF64Ext(c.imag);
        const sin_re = @sin(re_c) * std.math.cosh(im_c);
        const sin_im = @cos(re_c) * std.math.sinh(im_c);
        const cos_re = @cos(re_c) * std.math.cosh(im_c);
        const cos_im = -@sin(re_c) * std.math.sinh(im_c);
        const denom = cos_re * cos_re + cos_im * cos_im;
        const re = (sin_re * cos_re + sin_im * cos_im) / denom;
        const im = (sin_im * cos_re - sin_re * cos_im) / denom;
        return makeComplexOrReal(re, im);
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@tan(f));
}

fn complexAsin(re: f64, im: f64) PrimitiveError!Value {
    // asin(z) = -i * log(iz + sqrt(1 - z^2))
    const one_minus_z2_re = 1.0 - (re * re - im * im);
    const one_minus_z2_im = -(2.0 * re * im);
    const sqrt_mag = @sqrt(@sqrt(one_minus_z2_re * one_minus_z2_re + one_minus_z2_im * one_minus_z2_im));
    const sqrt_arg = std.math.atan2(one_minus_z2_im, one_minus_z2_re) / 2.0;
    const sqrt_re = sqrt_mag * @cos(sqrt_arg);
    const sqrt_im = sqrt_mag * @sin(sqrt_arg);
    const log_arg_re = -im + sqrt_re;
    const log_arg_im = re + sqrt_im;
    const log_re = @log(@sqrt(log_arg_re * log_arg_re + log_arg_im * log_arg_im));
    const log_im = std.math.atan2(log_arg_im, log_arg_re);
    const result_re = log_im;
    const result_im = -log_re;
    if (@abs(result_im) < 1e-15) return makeFlonumVal(result_re);
    return makeComplexOrReal(result_re, result_im);
}

fn asinFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return complexAsin(try toF64Ext(c.real), try toF64Ext(c.imag));
    }
    const f = try toF64(args[0]);
    if (f < -1.0 or f > 1.0) {
        return complexAsin(f, 0.0);
    }
    return makeFlonumVal(std.math.asin(f));
}

fn acosFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const asin_val = try complexAsin(try toF64Ext(c.real), try toF64Ext(c.imag));
        const pi_half = std.math.pi / 2.0;
        if (types.isFlonum(asin_val)) return makeFlonumVal(pi_half - types.toFlonum(asin_val));
        const ac = types.toComplex(asin_val);
        const re = pi_half - (try toF64Ext(ac.real));
        const im = -(try toF64Ext(ac.imag));
        if (@abs(im) < 1e-15) return makeFlonumVal(re);
        return makeComplexOrReal(re, im);
    }
    const f = try toF64(args[0]);
    if (f < -1.0 or f > 1.0) {
        const asin_val = try complexAsin(f, 0.0);
        const pi_half = std.math.pi / 2.0;
        if (types.isFlonum(asin_val)) return makeFlonumVal(pi_half - types.toFlonum(asin_val));
        const ac = types.toComplex(asin_val);
        const re = pi_half - (try toF64Ext(ac.real));
        const im = -(try toF64Ext(ac.imag));
        if (@abs(im) < 1e-15) return makeFlonumVal(re);
        return makeComplexOrReal(re, im);
    }
    return makeFlonumVal(std.math.acos(f));
}

fn atanFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 1) {
        const f = try toF64(args[0]);
        return makeFlonumVal(std.math.atan(f));
    }
    // (atan y x)
    const y = try toF64(args[0]);
    const x = try toF64(args[1]);
    return makeFlonumVal(std.math.atan2(y, x));
}

// ---------------------------------------------------------------------------
// Exp/Log
// ---------------------------------------------------------------------------

fn expFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const exp_r = @exp(try toF64Ext(c.real));
        const re = exp_r * @cos(try toF64Ext(c.imag));
        const im = exp_r * @sin(try toF64Ext(c.imag));
        if (@abs(im) < 1e-15) return makeFlonumVal(re);
        return makeComplexOrReal(re, im);
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@exp(f));
}

fn complexLog(re: f64, im: f64) PrimitiveError!Value {
    const mag = @sqrt(re * re + im * im);
    const result_re = @log(mag);
    const result_im = std.math.atan2(im, re);
    if (@abs(result_im) < 1e-15) return makeFlonumVal(result_re);
    return makeComplexOrReal(result_re, result_im);
}

fn logFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 1) {
        if (types.isComplex(args[0])) {
            const c = types.toComplex(args[0]);
            return complexLog(try toF64Ext(c.real), try toF64Ext(c.imag));
        }
        const f = try toF64(args[0]);
        if (f < 0.0) {
            return complexLog(f, 0.0);
        }
        return makeFlonumVal(@log(f));
    }
    // (log z base)
    const z = try toF64(args[0]);
    const base = try toF64(args[1]);
    if (z < 0.0) {
        const mag = @sqrt(z * z);
        const log_re = @log(mag) / @log(base);
        const log_im = std.math.pi / @log(base);
        if (@abs(log_im) < 1e-15) return makeFlonumVal(log_re);
        return makeComplexOrReal(log_re, log_im);
    }
    return makeFlonumVal(@log(z) / @log(base));
}

// ---------------------------------------------------------------------------
// Float predicates
// ---------------------------------------------------------------------------

fn finiteP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.TRUE;
    if (types.isFlonum(args[0])) {
        return if (std.math.isFinite(types.toFlonum(args[0]))) types.TRUE else types.FALSE;
    }
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        // Only flonum components can be non-finite; exact components are
        // finite by construction.
        const re_ok = if (types.isFlonum(c.real)) std.math.isFinite(types.toFlonum(c.real)) else true;
        const im_ok = if (types.isFlonum(c.imag)) std.math.isFinite(types.toFlonum(c.imag)) else true;
        return if (re_ok and im_ok) types.TRUE else types.FALSE;
    }
    return primitives.typeError("finite?", "number", args[0]);
}

fn infiniteP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.FALSE;
    if (types.isFlonum(args[0])) {
        return if (std.math.isInf(types.toFlonum(args[0]))) types.TRUE else types.FALSE;
    }
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const re_inf = types.isFlonum(c.real) and std.math.isInf(types.toFlonum(c.real));
        const im_inf = types.isFlonum(c.imag) and std.math.isInf(types.toFlonum(c.imag));
        return if (re_inf or im_inf) types.TRUE else types.FALSE;
    }
    return primitives.typeError("infinite?", "number", args[0]);
}

fn nanP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.FALSE;
    if (types.isFlonum(args[0])) {
        return if (std.math.isNan(types.toFlonum(args[0]))) types.TRUE else types.FALSE;
    }
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const re_nan = types.isFlonum(c.real) and std.math.isNan(types.toFlonum(c.real));
        const im_nan = types.isFlonum(c.imag) and std.math.isNan(types.toFlonum(c.imag));
        return if (re_nan or im_nan) types.TRUE else types.FALSE;
    }
    return primitives.typeError("nan?", "number", args[0]);
}

// ---------------------------------------------------------------------------
// Number/string conversion
// ---------------------------------------------------------------------------

fn numberToString(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var radix: u8 = 10;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("number->string", "integer", args[1]);
        const r = types.toFixnum(args[1]);
        if (r < 2 or r > 36) return primitives.typeError("number->string", "radix between 2 and 36", args[1]);
        radix = @intCast(@as(u64, @bitCast(r)));
    }
    if (types.isFixnum(args[0])) {
        if (radix != 10) {
            var buf: [68]u8 = undefined;
            var n = types.toFixnum(args[0]);
            const neg = n < 0;
            if (neg) n = -n;
            var pos: usize = buf.len;
            if (n == 0) {
                pos -= 1;
                buf[pos] = '0';
            } else {
                while (n > 0) {
                    pos -= 1;
                    const digit: u8 = @intCast(@as(u64, @bitCast(@rem(n, @as(i64, radix)))));
                    buf[pos] = if (digit < 10) '0' + digit else 'a' + digit - 10;
                    n = @divTrunc(n, @as(i64, radix));
                }
            }
            if (neg) {
                pos -= 1;
                buf[pos] = '-';
            }
            return gc.allocString(buf[pos..]) catch return PrimitiveError.OutOfMemory;
        }
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(args[0])}) catch return PrimitiveError.OutOfMemory;
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isBignum(args[0])) {
        const s = bignum_mod.toStringRadix(gc.allocator, args[0], radix) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(s);
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isRationalObj(args[0])) {
        if (radix != 10) {
            const r = types.toRational(args[0]);
            const num_s = bignum_mod.toStringRadix(gc.allocator, r.numerator, radix) catch return PrimitiveError.OutOfMemory;
            defer gc.allocator.free(num_s);
            const den_s = bignum_mod.toStringRadix(gc.allocator, r.denominator, radix) catch return PrimitiveError.OutOfMemory;
            defer gc.allocator.free(den_s);
            var result: std.ArrayList(u8) = .empty;
            defer result.deinit(gc.allocator);
            result.appendSlice(gc.allocator, num_s) catch return PrimitiveError.OutOfMemory;
            result.append(gc.allocator, '/') catch return PrimitiveError.OutOfMemory;
            result.appendSlice(gc.allocator, den_s) catch return PrimitiveError.OutOfMemory;
            const s = result.items;
            return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
        }
        const printer = @import("printer.zig");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(s);
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isFlonum(args[0])) {
        const printer = @import("printer.zig");
        var buf: [64]u8 = undefined;
        const s = printer.formatFlonum(&buf, types.toFlonum(args[0]));
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isComplex(args[0])) {
        const printer = @import("printer.zig");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(s);
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    return primitives.typeError("number->string", "number", args[0]);
}

pub fn isAnyComplex(args: []const Value) bool {
    for (args) |a| {
        if (types.isComplex(a)) return true;
    }
    return false;
}

/// True when `v` is a real number that may be a complex component (never a
/// complex itself).
fn isComponentValue(v: Value) bool {
    return types.isFixnum(v) or types.isBignum(v) or types.isRationalObj(v) or types.isFlonum(v);
}

/// Numeric zero test for a component value: fixnum 0, bignum zero, rational
/// with zero numerator, or flonum ±0.0.
pub fn isZeroValue(v: Value) bool {
    if (types.isFixnum(v)) return types.toFixnum(v) == 0;
    if (types.isBignum(v)) return bignum_mod.isZero(v);
    if (types.isRationalObj(v)) return isZeroValue(types.toRational(v).numerator);
    if (types.isFlonum(v)) return types.toFlonum(v) == 0.0;
    return false;
}

/// Build a complex number from two real component Values, applying the
/// R7RS 6.2.2 inexactness rule — if either component is inexact both become
/// inexact, so a stored complex is never mixed-exactness (kaappi#2166) — and
/// demoting to the real component when the imaginary part is zero, so every
/// complex constructed here has a nonzero imaginary part. The construction
/// site behind exact/inexact conversions and the arithmetic tower
/// (kaappi#2269 moved make-rectangular to makeComplexOrRealLiteral so an
/// inexact zero imag stays complex there).
pub fn makeComplexOrRealV(gc: *memory.GC, real_in: Value, imag_in: Value) PrimitiveError!Value {
    var real = real_in;
    var imag = imag_in;
    if (!types.isExactNumber(real) or !types.isExactNumber(imag)) {
        real = try inexactFn(&[1]Value{real});
        imag = try inexactFn(&[1]Value{imag});
    }
    if (isZeroValue(imag)) return real;
    return gc.allocComplex(real, imag) catch return PrimitiveError.OutOfMemory;
}

/// Reader/string->number complex construction: like makeComplexOrRealV, but
/// only an EXACT zero imaginary part demotes to the real component. The R7RS
/// conformance suite pins both sides: (real? -2.5+0.0i) => #f (an inexact
/// zero imag written in a literal stays a complex) and (integer? 3+0i) => #t
/// (an exact zero imag demotes). Inexactness still propagates whole-number
/// (R7RS 6.2.2), so the two parsers agree (R7RS 6.2.7, kaappi#2166).
pub fn makeComplexOrRealLiteral(gc: *memory.GC, real_in: Value, imag_in: Value) PrimitiveError!Value {
    var real = real_in;
    var imag = imag_in;
    const imag_exact_zero = types.isExactNumber(imag) and isZeroValue(imag);
    if (!types.isExactNumber(real) or !types.isExactNumber(imag)) {
        real = try inexactFn(&[1]Value{real});
        imag = try inexactFn(&[1]Value{imag});
    }
    if (imag_exact_zero) return real;
    return gc.allocComplex(real, imag) catch return PrimitiveError.OutOfMemory;
}

/// Inexact complex constructor for the f64-based transcendental paths, which
/// legitimately stay inexact-producing (kaappi#2166 out of scope). Demotes a
/// zero imaginary part, honoring the invariant that a complex constructed
/// through the numeric tower has a nonzero imaginary part.
pub fn makeComplexOrReal(real: f64, imag: f64) PrimitiveError!Value {
    if (imag == 0.0) return types.makeFlonum(real);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocComplex(types.makeFlonum(real), types.makeFlonum(imag)) catch return PrimitiveError.OutOfMemory;
}

pub const Exactness = enum { unspecified, exact, inexact };

fn applyExactness(gc: *@import("memory.zig").GC, val: Value, exactness: Exactness) PrimitiveError!Value {
    switch (exactness) {
        .unspecified => return val,
        .inexact => {
            if (types.isFixnum(val)) return types.makeFlonum(@floatFromInt(types.toFixnum(val)));
            if (types.isBignum(val)) {
                const bn = types.toBignum(val);
                var result: f64 = 0;
                var base: f64 = 1;
                for (bn.limbs[0..bn.len]) |limb| {
                    result += @as(f64, @floatFromInt(limb)) * base;
                    base *= 18446744073709551616.0; // 2^64
                }
                return types.makeFlonum(if (bn.positive) result else -result);
            }
            if (types.isRationalObj(val)) {
                const rat = types.toRational(val);
                return types.makeFlonum(types.rationalToF64(rat.numerator, rat.denominator));
            }
            if (types.isComplex(val)) {
                const c = types.toComplex(val);
                // With component values the complex is all-exact or
                // all-inexact; only an all-exact complex needs converting.
                if (!types.isExactNumber(c.real)) return val;
                const real_i = try inexactFn(&[1]Value{c.real});
                var slot = gc.rootedSlot(real_i) catch return PrimitiveError.OutOfMemory;
                defer slot.release();
                const imag_i = try inexactFn(&[1]Value{c.imag});
                return makeComplexOrRealV(gc, slot.get(), imag_i) catch return PrimitiveError.OutOfMemory;
            }
            return val;
        },
        .exact => {
            if (types.isFlonum(val)) {
                const f = types.toFlonum(val);
                if (std.math.isNan(f) or std.math.isInf(f)) return types.FALSE;
                return exactComponentGc(gc, val);
            }
            if (types.isComplex(val)) {
                // Convert each component digit-exactly. A non-finite flonum
                // part has no exact representation (same rule as the flonum
                // arm above -- #f, per #419).
                const c = types.toComplex(val);
                const re_nan = types.isFlonum(c.real) and !std.math.isFinite(types.toFlonum(c.real));
                const im_nan = types.isFlonum(c.imag) and !std.math.isFinite(types.toFlonum(c.imag));
                if (re_nan or im_nan) return types.FALSE;
                if (types.isExactNumber(c.real)) return val;
                const real_e = try exactComponentGc(gc, c.real);
                var slot = gc.rootedSlot(real_e) catch return PrimitiveError.OutOfMemory;
                defer slot.release();
                const imag_e = try exactComponentGc(gc, c.imag);
                return makeComplexOrRealV(gc, slot.get(), imag_e) catch return PrimitiveError.OutOfMemory;
            }
            return val;
        },
    }
}

fn parseExactDecimal(gc: *@import("memory.zig").GC, s: []const u8) PrimitiveError!?Value {
    var pos: usize = 0;
    var negative = false;

    if (pos < s.len and (s[pos] == '+' or s[pos] == '-')) {
        negative = s[pos] == '-';
        pos += 1;
    }

    const int_start = pos;
    while (pos < s.len and s[pos] >= '0' and s[pos] <= '9') pos += 1;
    const int_part = s[int_start..pos];

    var frac_part: []const u8 = &.{};
    if (pos < s.len and s[pos] == '.') {
        pos += 1;
        const frac_start = pos;
        while (pos < s.len and s[pos] >= '0' and s[pos] <= '9') pos += 1;
        frac_part = s[frac_start..pos];
    }

    if (int_part.len == 0 and frac_part.len == 0) return null;

    var exponent: i64 = 0;
    if (pos < s.len and (s[pos] == 'e' or s[pos] == 'E')) {
        pos += 1;
        if (pos >= s.len) return null;
        var exp_neg = false;
        if (s[pos] == '+' or s[pos] == '-') {
            exp_neg = s[pos] == '-';
            pos += 1;
        }
        const exp_start = pos;
        while (pos < s.len and s[pos] >= '0' and s[pos] <= '9') pos += 1;
        if (pos == exp_start) return null;
        exponent = std.fmt.parseInt(i64, s[exp_start..pos], 10) catch return null;
        if (exp_neg) exponent = -exponent;
    }

    if (pos != s.len) return null;

    const scale = @as(i64, @intCast(frac_part.len)) - exponent;

    // Build mantissa digit string: [sign] int_part ++ frac_part
    const sign_len: usize = if (negative) 1 else 0;
    const mantissa_len = sign_len + int_part.len + frac_part.len;
    if (mantissa_len == 0) return types.makeFixnum(0);

    const buf = gc.allocator.alloc(u8, mantissa_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var off: usize = 0;
    if (negative) {
        buf[0] = '-';
        off = 1;
    }
    @memcpy(buf[off .. off + int_part.len], int_part);
    @memcpy(buf[off + int_part.len ..], frac_part);

    // Parse mantissa as exact integer
    var mantissa_val: Value = undefined;
    if (std.fmt.parseInt(i64, buf, 10)) |n| {
        if (n == 0) return types.makeFixnum(0);
        mantissa_val = try arith.makeFixnumChecked(n);
    } else |err| {
        if (err == error.Overflow) {
            mantissa_val = bignum_mod.parseBignumString(gc, buf, 10) catch return PrimitiveError.OutOfMemory;
            if (bignum_mod.isZero(mantissa_val)) return types.makeFixnum(0);
        } else return null;
    }

    if (scale == 0) return mantissa_val;

    var slot_m = gc.rootedSlot(mantissa_val) catch return PrimitiveError.OutOfMemory;
    defer slot_m.release();

    const abs_scale: i64 = if (scale < 0) -scale else scale;
    const pow10 = bignum_mod.expt(gc, types.makeFixnum(10), types.makeFixnum(abs_scale)) catch return PrimitiveError.OutOfMemory;
    mantissa_val = slot_m.get();

    if (scale < 0) {
        var slot_p = gc.rootedSlot(pow10) catch return PrimitiveError.OutOfMemory;
        defer slot_p.release();
        return bignum_mod.mul(gc, mantissa_val, pow10) catch return PrimitiveError.OutOfMemory;
    }

    return @as(?Value, try arith.makeRationalReduced(gc, mantissa_val, pow10));
}

fn stringToNumber(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string->number", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);

    var radix: u8 = 10;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("string->number", "integer", args[1]);
        const r = types.toFixnum(args[1]);
        if (r < 2 or r > 36) return types.FALSE;
        radix = @intCast(@as(u64, @bitCast(r)));
    }

    return parseNumberText(gc, str.data[0..str.len], radix, .unspecified);
}

/// Parse a signed radix-R complex component (integer, N/D rational, or --
/// radix 10 only -- a decimal) into a component Value: fixnum/bignum/
/// rational for exact components, flonum for decimals, exponents, and
/// inf/nan spellings. Mirrors the reader's complex-component grammar so
/// `string->number` and `read` agree on `#x1+2i`, `#x1/2+3i` and friends
/// (kaappi#2243). With components stored as Values there is no round-trip
/// gate: an exact component is built digit-exactly at any size
/// (kaappi#2166, dissolving the #2182/#2183 f64 gates).
fn parseComplexComponent(gc: *@import("memory.zig").GC, part: []const u8, radix: u8) ?Value {
    if (std.mem.indexOfScalar(u8, part, '/')) |sp| {
        // Rational N/D (any radix): R7RS <ureal R>. The numerator carries
        // any sign; a zero denominator is invalid.
        if (sp == 0 or sp + 1 >= part.len) return null;
        const num = bignum_mod.parseBignumString(gc, part[0..sp], radix) catch return null;
        var slot = gc.rootedSlot(num) catch return null;
        defer slot.release();
        const den = bignum_mod.parseBignumString(gc, part[sp + 1 ..], radix) catch return null;
        if (types.isFixnum(den) and types.toFixnum(den) == 0) return null;
        if (types.isBignum(den) and bignum_mod.isZero(den)) return null;
        return arith.makeRationalReduced(gc, slot.get(), den) catch return null;
    }
    if (radix == 10) {
        // Decimal parts (1.5+2i, 1e5+2i) and inf/nan spellings: parseFloat
        // accepts them with the sign included. Integer text builds an exact
        // fixnum, or a digit-exact bignum past i64 (#2166).
        var i: usize = 0;
        if (part.len > 0 and (part[0] == '+' or part[0] == '-')) i = 1;
        var is_integer = true;
        while (i < part.len) : (i += 1) {
            if (!std.ascii.isDigit(part[i]) and part[i] != '_') {
                is_integer = false;
                break;
            }
        }
        if (is_integer) {
            var b: [256]u8 = undefined;
            const clean = bignum_mod.stripUnderscores(part, radix, &b) orelse return null;
            if (std.fmt.parseInt(i64, clean, radix)) |n| {
                // Fixnum is i48; larger i64 values must become bignums, not
                // silently truncate (kaappi#2166). Build through `gc`, since
                // gc_instance may be unset in reader-only contexts.
                if (n >= std.math.minInt(i48) and n <= std.math.maxInt(i48))
                    return types.makeFixnum(n);
                return gc.allocBignumFromI64(n) catch return null;
            } else |err| {
                if (err != error.Overflow) return null;
                return bignum_mod.parseBignumString(gc, clean, radix) catch return null;
            }
        }
        // Special floats (+inf.0, -inf.0, +nan.0, -nan.0, case-insensitive)
        // match the reader's complex-component grammar -- 3.0+inf.0i and
        // +inf.0i read there -- but Zig's parseFloat does not accept them
        // (#2243 review).
        if (std.ascii.eqlIgnoreCase(part, "+inf.0")) return types.makeFlonum(std.math.inf(f64));
        if (std.ascii.eqlIgnoreCase(part, "-inf.0")) return types.makeFlonum(-std.math.inf(f64));
        if (std.ascii.eqlIgnoreCase(part, "+nan.0")) return types.makeFlonum(std.math.nan(f64));
        if (std.ascii.eqlIgnoreCase(part, "-nan.0")) return types.makeFlonum(std.math.nan(f64));
        const f = std.fmt.parseFloat(f64, part) catch return null;
        return types.makeFlonum(f);
    }
    // Radix 2/8/16: integer part only -- <decimal R> does not exist there.
    var b: [256]u8 = undefined;
    const clean = bignum_mod.stripUnderscores(part, radix, &b) orelse return null;
    if (std.fmt.parseInt(i64, clean, radix)) |n| {
        if (n >= std.math.minInt(i48) and n <= std.math.maxInt(i48))
            return types.makeFixnum(n);
        return gc.allocBignumFromI64(n) catch return null;
    } else |err| {
        if (err != error.Overflow) return null;
        return bignum_mod.parseBignumString(gc, clean, radix) catch return null;
    }
}

/// Parse a complete number text into a Value, or `types.FALSE` when the text
/// is not a number. This is the single number grammar behind BOTH
/// `string->number` and the reader's `#e`/`#i` literals: R7RS 6.2.7 requires
/// the two to agree, and until kaappi#1911 they were separate parsers whose
/// divergence produced #1891/#1907/#1908/#1909. The reader hands the token
/// body over with `exactness_in` set (its own prefixes already consumed)
/// instead of re-implementing exactness at the token level.
pub fn parseNumberText(gc: *@import("memory.zig").GC, text: []const u8, radix_in: u8, exactness_in: Exactness) PrimitiveError!Value {
    var s: []const u8 = text;
    var radix = radix_in;

    // R7RS prefix handling: #b #o #d #x (radix) and #e #i (exactness)
    // Both can appear in either order: #e#xff or #x#eff
    var exactness: Exactness = exactness_in;
    for (0..2) |_| {
        if (s.len >= 2 and s[0] == '#') {
            switch (s[1] | 0x20) { // case-insensitive
                'b' => {
                    radix = 2;
                    s = s[2..];
                },
                'o' => {
                    radix = 8;
                    s = s[2..];
                },
                'd' => {
                    radix = 10;
                    s = s[2..];
                },
                'x' => {
                    radix = 16;
                    s = s[2..];
                },
                'e' => {
                    exactness = .exact;
                    s = s[2..];
                },
                'i' => {
                    exactness = .inexact;
                    s = s[2..];
                },
                else => return types.FALSE,
            }
        }
    }
    if (s.len == 0) return types.FALSE;

    // SRFI 169: `s` may still carry embedded digit-separator underscores at
    // this point. Validate their placement -- strictly between two valid
    // digits of `radix`, matching the reader's own rule (bignum.zig's
    // stripUnderscores doc comment) -- and strip them up front, once, for
    // every shape below (plain integer, rational numerator/denominator,
    // decimal float, complex parts). Without this, the small-integer and
    // rational fast paths call std.fmt.parseInt directly, which has its own
    // more permissive underscore convenience (mirroring Zig's own integer
    // literal syntax) that wrongly accepts e.g. a doubled underscore
    // ("1__2" -> 12) SRFI 169 requires rejecting (#1724). The hex-float and
    // bignum-overflow paths already call stripUnderscores internally, so
    // this is a harmless no-op for them once `s` is already clean.
    var underscore_buf: [4096]u8 = undefined;
    s = bignum_mod.stripUnderscores(s, radix, &underscore_buf) orelse return types.FALSE;

    if (std.mem.eql(u8, s, "+inf.0") or std.mem.eql(u8, s, "-inf.0") or
        std.mem.eql(u8, s, "+nan.0") or std.mem.eql(u8, s, "-nan.0"))
    {
        if (exactness == .exact) return types.FALSE;
        if (std.mem.eql(u8, s, "+inf.0")) return types.makeFlonum(std.math.inf(f64));
        if (std.mem.eql(u8, s, "-inf.0")) return types.makeFlonum(-std.math.inf(f64));
        return types.makeFlonum(std.math.nan(f64));
    }

    // Rational: num/den
    if (std.mem.indexOfScalar(u8, s, '/')) |slash_pos| {
        // A trailing 'i' (any case) means the '/' is a complex-component
        // separator (1/2+3i, 1/2+3/4i, #x1/2+3i): the complex branch below
        // owns those, parsing each component as a <ureal R> (kaappi#2243).
        // Without this guard, 1/2+3i would try "2+3i" as a denominator,
        // fail, and return #f for a valid R7RS complex. 'i' is only the
        // imaginary marker at radix <= 18 -- from radix 19 up it is a plain
        // digit (value 18), so "1/2i" at radix 19 is the rational 1/56.
        const complex_shaped = radix <= 18 and s.len >= 2 and (s[s.len - 1] | 0x20) == 'i';
        if (!complex_shaped and slash_pos > 0 and slash_pos + 1 < s.len) {
            const num_str = s[0..slash_pos];
            const den_str = s[slash_pos + 1 ..];
            const num_val: Value = if (std.fmt.parseInt(i64, num_str, radix)) |num|
                try arith.makeFixnumCheckedGc(gc, num)
            else |err| blk: {
                if (err != error.Overflow) break :blk types.FALSE;
                break :blk bignum_mod.parseBignumString(gc, num_str, radix) catch |e| switch (e) {
                    error.InvalidCharacter => types.FALSE,
                    else => return PrimitiveError.OutOfMemory,
                };
            };
            if (num_val == types.FALSE) return types.FALSE;
            var slot_num = gc.rootedSlot(num_val) catch return PrimitiveError.OutOfMemory;
            defer slot_num.release();
            const den_val: Value = if (std.fmt.parseInt(i64, den_str, radix)) |den| blk: {
                if (den == 0) return types.FALSE;
                break :blk try arith.makeFixnumCheckedGc(gc, den);
            } else |err| blk: {
                if (err != error.Overflow) break :blk types.FALSE;
                break :blk bignum_mod.parseBignumString(gc, den_str, radix) catch |e| switch (e) {
                    error.InvalidCharacter => types.FALSE,
                    else => return PrimitiveError.OutOfMemory,
                };
            };
            if (den_val == types.FALSE) return types.FALSE;
            if (bignum_mod.isZero(den_val)) return types.FALSE;
            const result = arith.makeRationalReduced(gc, num_val, den_val) catch return PrimitiveError.OutOfMemory;
            return applyExactness(gc, result, exactness);
        }
    }

    // SRFI 270: a hex float ('.' or 'p'/'P' present -- neither is ever a
    // valid hex digit, so their presence is unambiguous) must be checked
    // before the plain-integer parse below. That parse's own overflow
    // fallback (parseBignumString) doesn't understand hex-float syntax,
    // so without this a merely-large-mantissa hex float would overflow
    // i64, fail bignum parsing on the first '.'/'p', and wrongly return
    // #f instead of reaching parseHexFloat at all.
    if (radix == 16 and (std.mem.indexOfScalar(u8, s, '.') != null or
        std.mem.indexOfAny(u8, s, "pP") != null))
    {
        if (bignum_mod.parseHexFloat(s)) |f| {
            return applyExactness(gc, types.makeFlonum(f), exactness);
        }
        return types.FALSE;
    }

    if (std.fmt.parseInt(i64, s, radix)) |n| {
        const result = try arith.makeFixnumCheckedGc(gc, n);
        return applyExactness(gc, result, exactness);
    } else |err| {
        if (err == error.Overflow) {
            // A digit run that overflows i64 may still be a valid decimal
            // float rather than a bignum -- "9223372036854775808.0" hits
            // Overflow on its last digit before parseInt ever sees the '.'
            // (#1921). InvalidCharacter therefore falls through to the
            // decimal shapes below instead of rejecting outright.
            if (bignum_mod.parseBignumString(gc, s, radix)) |result| {
                return applyExactness(gc, result, exactness);
            } else |e| switch (e) {
                error.InvalidCharacter => {},
                else => return PrimitiveError.OutOfMemory,
            }
        }
    }

    if (radix == 10) {
        if (exactness == .exact) {
            if (try parseExactDecimal(gc, s)) |v| return v;
        }

        if (std.fmt.parseFloat(f64, s)) |f| {
            return applyExactness(gc, types.makeFlonum(f), exactness);
        } else |_| {}
    }

    // Try parsing as complex: a+bi, a-bi, +bi, -bi, +i, -i (R7RS 7.1.1
    // <complex R>). Radix-prefixed spellings (#x1+2i, #x1/2+3i) are valid
    // R7RS and the reader now accepts them too (kaappi#2243), so this
    // branch is no longer radix-10-only: the split forms and the signed
    // pure-imaginary `+ <ureal R> i` work in every radix, while the
    // signless pure-imaginary extension (2i, 2.5i) stays radix-10-only --
    // exactly mirroring the reader's grammar (which rejects `#x2i` and the
    // signless rational 2/3i). Radix >= 19 treats `i` as a plain digit
    // (value 18), so the imaginary marker only exists at radix <= 18.
    if (radix <= 18 and s.len >= 2 and (s[s.len - 1] | 0x20) == 'i') {
        const body = s[0 .. s.len - 1]; // strip trailing 'i' (any case)

        // Pure imaginary: +i, -i (R7RS <complex R> -> `+ i` | `- i`), every
        // radix; the reader reads `#x+i` as 0+1i too (#2243).
        if (std.mem.eql(u8, body, "+")) {
            const c = gc.allocComplex(types.makeFixnum(0), types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory;
            return applyExactness(gc, c, exactness);
        }
        if (std.mem.eql(u8, body, "-")) {
            const c = gc.allocComplex(types.makeFixnum(0), types.makeFixnum(-1)) catch return PrimitiveError.OutOfMemory;
            return applyExactness(gc, c, exactness);
        }

        // Find the split point: last +/- that isn't at position 0. In radix
        // 10 a +/- right after e/E is an exponent sign (1e+5i reads the
        // exponent into the real part); in radix 2/8/16 letters are digits,
        // so no such skip applies (#x1e+2i is real 1e = 30).
        var split: ?usize = null;
        var j: usize = body.len;
        while (j > 1) {
            j -= 1;
            if (body[j] == '+' or body[j] == '-') {
                if (radix == 10 and (body[j - 1] == 'e' or body[j - 1] == 'E')) continue;
                split = j;
                break;
            }
        }

        if (split) |sp| {
            const real_str = body[0..sp];
            const imag_str = body[sp..];
            // Components are built digit-exactly; exactness is carried by
            // each component's own type (integer/rational parts are exact,
            // decimals and exponents inexact), and makeComplexOrRealLiteral
            // normalizes the pair to a single exactness. `#e`/`#i` still
            // override everything via applyExactness below (#2243 review).
            const real_v = if (real_str.len == 0)
                types.makeFixnum(0)
            else
                parseComplexComponent(gc, real_str, radix) orelse return types.FALSE;
            var slot = gc.rootedSlot(real_v) catch return PrimitiveError.OutOfMemory;
            defer slot.release();
            const imag_v = if (std.mem.eql(u8, imag_str, "+"))
                types.makeFixnum(1)
            else if (std.mem.eql(u8, imag_str, "-"))
                types.makeFixnum(-1)
            else
                parseComplexComponent(gc, imag_str, radix) orelse return types.FALSE;
            const c = makeComplexOrRealLiteral(gc, slot.get(), imag_v) catch return PrimitiveError.OutOfMemory;
            return applyExactness(gc, c, exactness);
        } else {
            // No split found -- pure imaginary with a magnitude: +3i,
            // -2.5i, 2i. A leading sign is the R7RS `+ <ureal R> i`
            // production, valid in every radix (the reader reads `#x+3i`
            // as 0+3i, #2243); the signless `2i`/`2.5i` spellings are a
            // radix-10 extension (the reader rejects `#x2i` and the
            // signless rational 2/3i), so they stay radix-10-only and
            // integer/decimal-only.
            const has_sign = body.len > 0 and (body[0] == '+' or body[0] == '-');
            var imag_v: Value = undefined;
            if (has_sign) {
                imag_v = parseComplexComponent(gc, body, radix) orelse return types.FALSE;
            } else {
                if (radix != 10) return types.FALSE;
                var i: usize = 0;
                var is_integer = true;
                while (i < body.len) : (i += 1) {
                    if (!std.ascii.isDigit(body[i])) {
                        is_integer = false;
                        break;
                    }
                }
                if (is_integer) {
                    var nb: [256]u8 = undefined;
                    const clean = bignum_mod.stripUnderscores(body, 10, &nb) orelse return types.FALSE;
                    if (std.fmt.parseInt(i64, clean, 10)) |n| {
                        if (n >= std.math.minInt(i48) and n <= std.math.maxInt(i48)) {
                            imag_v = types.makeFixnum(n);
                        } else {
                            imag_v = gc.allocBignumFromI64(n) catch return PrimitiveError.OutOfMemory;
                        }
                    } else |err| {
                        if (err != error.Overflow) return types.FALSE;
                        // Beyond i64: a digit-exact bignum magnitude, no
                        // longer gated on f64 round-tripping (#2166).
                        imag_v = bignum_mod.parseBignumString(gc, clean, 10) catch |e| switch (e) {
                            error.InvalidCharacter => types.FALSE,
                            else => return PrimitiveError.OutOfMemory,
                        };
                    }
                } else {
                    const f = std.fmt.parseFloat(f64, body) catch {
                        return types.FALSE;
                    };
                    imag_v = types.makeFlonum(f);
                }
            }
            const c = makeComplexOrRealLiteral(gc, types.makeFixnum(0), imag_v) catch return PrimitiveError.OutOfMemory;
            return applyExactness(gc, c, exactness);
        }
    }

    return types.FALSE;
}

// ---------------------------------------------------------------------------
// Complex numbers (R7RS 6.2.6)
// ---------------------------------------------------------------------------

fn makeRectangular(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    for (args) |a| {
        if (!isComponentValue(a)) return primitives.typeError("make-rectangular", "real number", a);
    }
    // Components are never forced through an f64: 2^53+1 and 10^25 survive
    // digit-exactly (kaappi#2166). The exactness rule (R7RS 6.2.2) and the
    // zero-imag demotion live in makeComplexOrRealLiteral — the same
    // construction the reader uses, so an INEXACT zero imaginary part stays
    // complex ((real? (make-rectangular 1.5 0.0)) => #f, kaappi#2269) and
    // only an exact zero demotes, matching the literal 1.5+0.0i.
    return makeComplexOrRealLiteral(gc, args[0], args[1]);
}

fn makePolar(args: []const Value) PrimitiveError!Value {
    const mag = try toF64(args[0]);
    const ang = try toF64(args[1]);
    const real = mag * @cos(ang);
    const imag = mag * @sin(ang);
    return makeComplexOrReal(real, imag);
}

fn realPart(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        // The component is stored as a Value, so real-part returns it
        // exactly -- 3/2, not 1.5 (kaappi#2166).
        return types.toComplex(args[0]).real;
    }
    if (types.isFixnum(args[0]) or types.isFlonum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return args[0];
    return primitives.typeError("real-part", "number", args[0]);
}

fn imagPart(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        return types.toComplex(args[0]).imag;
    }
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.makeFixnum(0);
    if (types.isFlonum(args[0])) return makeFlonumVal(0.0);
    return primitives.typeError("imag-part", "number", args[0]);
}

fn magnitudeFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        const re = try toF64Ext(c.real);
        const im = try toF64Ext(c.imag);
        return makeFlonumVal(@sqrt(re * re + im * im));
    }
    if (types.isFixnum(args[0])) {
        const n = types.toFixnum(args[0]);
        return if (n < 0) try arith.makeFixnumChecked(-n) else args[0];
    }
    if (types.isFlonum(args[0])) {
        return makeFlonumVal(@abs(types.toFlonum(args[0])));
    }
    if (types.isBignum(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return bignum_mod.absVal(gc, args[0]) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        if (!bignum_mod.isNegative(r.numerator)) return args[0];
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const neg_num = bignum_mod.negate(gc, r.numerator) catch return PrimitiveError.OutOfMemory;
        return arith.makeRationalReduced(gc, neg_num, r.denominator);
    }
    return primitives.typeError("magnitude", "number", args[0]);
}

fn angleFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return makeFlonumVal(std.math.atan2(try toF64Ext(c.imag), try toF64Ext(c.real)));
    }
    if (types.isFixnum(args[0])) {
        const n = types.toFixnum(args[0]);
        return makeFlonumVal(if (n >= 0) 0.0 else std.math.pi);
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        return makeFlonumVal(std.math.atan2(@as(f64, 0.0), f));
    }
    if (types.isBignum(args[0])) {
        return makeFlonumVal(if (bignum_mod.isNegative(args[0])) std.math.pi else 0.0);
    }
    if (types.isRationalObj(args[0])) {
        const f = try toF64Ext(args[0]);
        return makeFlonumVal(if (f >= 0.0) 0.0 else std.math.pi);
    }
    return primitives.typeError("angle", "number", args[0]);
}

// ---------------------------------------------------------------------------
// Integer division variants (R7RS 6.2.6)
// ---------------------------------------------------------------------------

fn floorQuotient(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        const a = try toF64(args[0]);
        const b = try toF64(args[1]);
        if (b == 0.0) return raiseDivByZero();
        return makeFlonumVal(@floor(a / b));
    }
    if (anyBignum(args)) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        const q = bignum_mod.quotient(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
        var slot = gc.rootedSlot(q) catch return PrimitiveError.OutOfMemory;
        defer slot.release();
        const rem = bignum_mod.remainder(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
        if (!bignum_mod.isZero(rem) and (bignum_mod.isNegative(args[0]) != bignum_mod.isNegative(args[1]))) {
            return bignum_mod.sub(gc, slot.get(), types.makeFixnum(1)) catch return PrimitiveError.OutOfMemory;
        }
        return slot.get();
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return primitives.typeError("floor-quotient", "integer", if (!types.isFixnum(args[0])) args[0] else args[1]);
    const a = types.toFixnum(args[0]);
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return try arith.makeFixnumChecked(@divFloor(a, b));
}

fn floorRemainder(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        const a = try toF64(args[0]);
        const b = try toF64(args[1]);
        if (b == 0.0) return raiseDivByZero();
        return makeFlonumVal(a - @floor(a / b) * b);
    }
    if (anyBignum(args)) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        const rem = bignum_mod.remainder(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(rem)) return types.makeFixnum(0);
        var slot = gc.rootedSlot(rem) catch return PrimitiveError.OutOfMemory;
        defer slot.release();
        if (bignum_mod.isNegative(rem) != bignum_mod.isNegative(args[1])) {
            return bignum_mod.add(gc, rem, args[1]) catch return PrimitiveError.OutOfMemory;
        }
        return rem;
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return primitives.typeError("floor-remainder", "integer", if (!types.isFixnum(args[0])) args[0] else args[1]);
    const a = types.toFixnum(args[0]);
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@mod(a, b));
}

fn floorDivide(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const q_val = try floorQuotient(args);
    var slot_q = gc.rootedSlot(q_val) catch return PrimitiveError.OutOfMemory;
    defer slot_q.release();
    const r_val = try floorRemainder(args);
    var slot_r = gc.rootedSlot(r_val) catch return PrimitiveError.OutOfMemory;
    defer slot_r.release();
    const vals = [_]Value{ q_val, r_val };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

fn truncateQuotient(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        const a = try toF64(args[0]);
        const b = try toF64(args[1]);
        if (b == 0.0) return raiseDivByZero();
        return makeFlonumVal(@trunc(a / b));
    }
    if (anyBignum(args)) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        return bignum_mod.quotient(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return primitives.typeError("truncate-quotient", "integer", if (!types.isFixnum(args[0])) args[0] else args[1]);
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return try arith.makeFixnumChecked(@divTrunc(types.toFixnum(args[0]), b));
}

fn truncateRemainder(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        const a = try toF64(args[0]);
        const b = try toF64(args[1]);
        if (b == 0.0) return raiseDivByZero();
        return makeFlonumVal(a - @trunc(a / b) * b);
    }
    if (anyBignum(args)) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        return bignum_mod.remainder(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return primitives.typeError("truncate-remainder", "integer", if (!types.isFixnum(args[0])) args[0] else args[1]);
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@rem(types.toFixnum(args[0]), b));
}

fn truncateDivide(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const q_val = try truncateQuotient(args);
    var slot_q = gc.rootedSlot(q_val) catch return PrimitiveError.OutOfMemory;
    defer slot_q.release();
    const r_val = try truncateRemainder(args);
    var slot_r = gc.rootedSlot(r_val) catch return PrimitiveError.OutOfMemory;
    defer slot_r.release();
    const vals = [_]Value{ q_val, r_val };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Rational operations (R7RS 6.2.6)
// ---------------------------------------------------------------------------

pub fn floatToRational(f: f64) struct { num: i64, den: i64 } {
    const min_i64: f64 = @floatFromInt(std.math.minInt(i64));
    const max_i64_f: f64 = @floatFromInt(std.math.maxInt(i64));
    if (f == @trunc(f)) {
        if (f >= min_i64 and f < max_i64_f) return .{ .num = @intFromFloat(f), .den = 1 };
        return .{ .num = 0, .den = 0 };
    }
    const sign: i64 = if (f < 0) -1 else 1;
    const abs_f = @abs(f);
    const rounded = @round(abs_f);
    var best_num: i64 = if (rounded >= 0 and rounded <= max_i64_f) @intFromFloat(rounded) else std.math.maxInt(i64);
    var best_den: i64 = 1;
    var best_err: f64 = @abs(abs_f - @as(f64, @floatFromInt(best_num)));
    var den: i64 = 2;
    while (den <= 1000000) : (den += 1) {
        const num: i64 = @intFromFloat(@round(abs_f * @as(f64, @floatFromInt(den))));
        const err = @abs(abs_f - @as(f64, @floatFromInt(num)) / @as(f64, @floatFromInt(den)));
        if (err < best_err) {
            best_num = num;
            best_den = den;
            best_err = err;
            if (err == 0) break;
        }
    }
    const g = @import("primitives_arithmetic.zig").gcdTwo(best_num, best_den);
    if (g > 1) {
        best_num = @divExact(best_num, g);
        best_den = @divExact(best_den, g);
    }
    return .{ .num = sign * best_num, .den = best_den };
}

fn numeratorFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        return r.numerator;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (!std.math.isFinite(f)) return args[0];
        if (f == @trunc(f)) return args[0];
        const exact_val = try exactFn(args);
        if (types.isRationalObj(exact_val)) {
            const r = types.toRational(exact_val);
            return makeFlonumVal(try toF64Ext(r.numerator));
        }
        return makeFlonumVal(try toF64Ext(exact_val));
    }
    return primitives.typeError("numerator", "number", args[0]);
}

fn denominatorFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return types.makeFixnum(1);
    if (types.isBignum(args[0])) return types.makeFixnum(1);
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        return r.denominator;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (!std.math.isFinite(f)) return makeFlonumVal(1.0);
        if (f == @trunc(f)) return makeFlonumVal(1.0);
        const exact_val = try exactFn(args);
        if (types.isRationalObj(exact_val)) {
            const r = types.toRational(exact_val);
            return makeFlonumVal(try toF64Ext(r.denominator));
        }
        return makeFlonumVal(1.0);
    }
    return primitives.typeError("denominator", "number", args[0]);
}

fn rationalizeFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const x = try primitives.toF64(args[0]);
    const y = try primitives.toF64(args[1]);
    if (!std.math.isFinite(x)) return args[0];
    const lo = x - @abs(y);
    const hi = x + @abs(y);
    // Find simplest rational p/q in [lo, hi] (smallest denominator first)
    var best_num: i64 = @intFromFloat(@round(x));
    var best_den: i64 = 1;
    const bv = @as(f64, @floatFromInt(best_num));
    if (bv >= lo and bv <= hi) {
        // Integer in range — simplest possible
    } else {
        var found = false;
        var den: i64 = 2;
        while (den <= 1000000) : (den += 1) {
            const fden = @as(f64, @floatFromInt(den));
            const lo_num = @as(i64, @intFromFloat(@ceil(lo * fden)));
            const hi_num = @as(i64, @intFromFloat(@floor(hi * fden)));
            if (lo_num <= hi_num) {
                best_num = lo_num;
                best_den = den;
                found = true;
                break;
            }
        }
        if (!found) {
            best_num = @intFromFloat(@round(x * 1000000.0));
            best_den = 1000000;
        }
    }
    const g = arith.gcdTwo(if (best_num < 0) -best_num else best_num, best_den);
    if (g > 1) {
        best_num = @divExact(best_num, g);
        best_den = @divExact(best_den, g);
    }
    if (types.isFixnum(args[0]) or types.isRationalObj(args[0])) {
        if (best_den == 1) return types.makeFixnum(best_num);
        return gc.allocRational(types.makeFixnum(best_num), types.makeFixnum(best_den)) catch return PrimitiveError.OutOfMemory;
    }
    return makeFlonumVal(@as(f64, @floatFromInt(best_num)) / @as(f64, @floatFromInt(best_den)));
}
