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
    const min_i64: f64 = @floatFromInt(std.math.minInt(i64));
    const max_i64_f: f64 = @floatFromInt(std.math.maxInt(i64));
    if (f >= min_i64 and f < max_i64_f) {
        return try arith.makeFixnumChecked(@intFromFloat(f));
    }
    return floatToBignum(f);
}

fn floatToBignum(f: f64) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
        return if (c.exact_real and c.exact_imag) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn inexactP(args: []const Value) PrimitiveError!Value {
    if (types.isFlonum(args[0])) return types.TRUE;
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return if (!c.exact_real or !c.exact_imag) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn exactIntegerP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0]) or types.isBignum(args[0])) types.TRUE else types.FALSE;
}

pub fn exactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) return args[0]; // already exact
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (std.math.isNan(f) or std.math.isInf(f)) return primitives.typeError("exact", "finite number", args[0]);
        if (f == 0.0) return types.makeFixnum(0);
        if (f == @trunc(f)) return try safeFloatToExactInt(f);
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
        if (exp >= 0) return try safeFloatToExactInt(f);
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
    if (types.isComplex(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        const real_flo = types.makeFlonum(c.real);
        const real_exact = try exactFn(&[1]Value{real_flo});
        var slot = gc.rootedSlot(real_exact) catch return PrimitiveError.OutOfMemory;
        defer slot.release();
        const imag_flo = types.makeFlonum(c.imag);
        const imag_exact = try exactFn(&[1]Value{imag_flo});
        if (types.isFixnum(imag_exact) and types.toFixnum(imag_exact) == 0) return real_exact;
        const real_f = try toF64Ext(real_exact);
        const imag_f = try toF64Ext(imag_exact);
        return gc.allocComplexEx(real_f, imag_f, true, true) catch return PrimitiveError.OutOfMemory;
    }
    return primitives.typeError("exact", "number", args[0]);
}

fn inexactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFlonum(args[0])) return args[0];
    if (types.isFixnum(args[0])) return makeFlonumVal(@floatFromInt(types.toFixnum(args[0])));
    if (types.isBignum(args[0])) return makeFlonumVal(bignum_mod.toF64(args[0]));
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        const n = try toF64Ext(r.numerator);
        const d = try toF64Ext(r.denominator);
        const result = n / d;
        if (!std.math.isNan(result)) return makeFlonumVal(result);
        // Both overflow to inf — use bignum division for the integer part
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const q = bignum_mod.quotient(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
        const q_f = try toF64Ext(q);
        const rem = bignum_mod.remainder(gc, r.numerator, r.denominator) catch return PrimitiveError.OutOfMemory;
        const rem_f = try toF64Ext(rem);
        return makeFlonumVal(q_f + rem_f / d);
    }
    if (types.isComplex(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        return gc.allocComplex(c.real, c.imag) catch return PrimitiveError.OutOfMemory;
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
        var zr: f64 = undefined;
        var zi: f64 = undefined;
        var wr: f64 = undefined;
        var wi: f64 = undefined;
        if (types.isComplex(args[0])) {
            const c = types.toComplex(args[0]);
            zr = c.real;
            zi = c.imag;
        } else {
            zr = toF64Ext(args[0]) catch return primitives.typeError("expt", "number", args[0]);
            zi = 0.0;
        }
        if (types.isComplex(args[1])) {
            const c = types.toComplex(args[1]);
            wr = c.real;
            wi = c.imag;
        } else {
            wr = toF64Ext(args[1]) catch return primitives.typeError("expt", "number", args[1]);
            wi = 0.0;
        }
        // Special case: integer exponent with complex base — use repeated multiplication
        if (wi == 0.0 and wr == @trunc(wr) and @abs(wr) < 100) {
            const n: i64 = @intFromFloat(wr);
            if (n == 0) return gc.allocComplex(1.0, 0.0) catch return PrimitiveError.OutOfMemory;
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
            if (ri == 0.0) return types.makeFlonum(rr);
            return gc.allocComplex(rr, ri) catch return PrimitiveError.OutOfMemory;
        }
        // General: z^w = e^(w * ln(z))
        // ln(z) = ln|z| + i*arg(z)
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
        return gc.allocComplex(result_r, result_i) catch return PrimitiveError.OutOfMemory;
    }
    const base_f = try toF64Ext(args[0]);
    const exp_f = try toF64Ext(args[1]);
    return makeFlonumVal(std.math.pow(f64, base_f, exp_f));
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
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        const mag = @sqrt(c.real * c.real + c.imag * c.imag);
        const r = @sqrt((mag + c.real) / 2.0);
        const i_sign: f64 = if (c.imag < 0.0) -1.0 else 1.0;
        const i = i_sign * @sqrt((mag - c.real) / 2.0);
        return gc.allocComplex(r, i) catch return PrimitiveError.OutOfMemory;
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
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const imag = @sqrt(-f);
        return gc.allocComplex(0.0, imag) catch return PrimitiveError.OutOfMemory;
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
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        const re = @sin(c.real) * std.math.cosh(c.imag);
        const im = @cos(c.real) * std.math.sinh(c.imag);
        return gc.allocComplex(re, im) catch return PrimitiveError.OutOfMemory;
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@sin(f));
}

fn cosFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        const re = @cos(c.real) * std.math.cosh(c.imag);
        const im = -@sin(c.real) * std.math.sinh(c.imag);
        return gc.allocComplex(re, im) catch return PrimitiveError.OutOfMemory;
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@cos(f));
}

fn tanFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        const sin_re = @sin(c.real) * std.math.cosh(c.imag);
        const sin_im = @cos(c.real) * std.math.sinh(c.imag);
        const cos_re = @cos(c.real) * std.math.cosh(c.imag);
        const cos_im = -@sin(c.real) * std.math.sinh(c.imag);
        const denom = cos_re * cos_re + cos_im * cos_im;
        const re = (sin_re * cos_re + sin_im * cos_im) / denom;
        const im = (sin_im * cos_re - sin_re * cos_im) / denom;
        return gc.allocComplex(re, im) catch return PrimitiveError.OutOfMemory;
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@tan(f));
}

fn complexAsin(gc: anytype, re: f64, im: f64) PrimitiveError!Value {
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
    return gc.allocComplex(result_re, result_im) catch return PrimitiveError.OutOfMemory;
}

fn asinFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        return complexAsin(gc, c.real, c.imag);
    }
    const f = try toF64(args[0]);
    if (f < -1.0 or f > 1.0) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return complexAsin(gc, f, 0.0);
    }
    return makeFlonumVal(std.math.asin(f));
}

fn acosFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        const asin_val = try complexAsin(gc, c.real, c.imag);
        const pi_half = std.math.pi / 2.0;
        if (types.isFlonum(asin_val)) return makeFlonumVal(pi_half - types.toFlonum(asin_val));
        const ac = types.toComplex(asin_val);
        const re = pi_half - ac.real;
        const im = -ac.imag;
        if (@abs(im) < 1e-15) return makeFlonumVal(re);
        return gc.allocComplex(re, im) catch return PrimitiveError.OutOfMemory;
    }
    const f = try toF64(args[0]);
    if (f < -1.0 or f > 1.0) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const asin_val = try complexAsin(gc, f, 0.0);
        const pi_half = std.math.pi / 2.0;
        if (types.isFlonum(asin_val)) return makeFlonumVal(pi_half - types.toFlonum(asin_val));
        const ac = types.toComplex(asin_val);
        const re = pi_half - ac.real;
        const im = -ac.imag;
        if (@abs(im) < 1e-15) return makeFlonumVal(re);
        return gc.allocComplex(re, im) catch return PrimitiveError.OutOfMemory;
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
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const c = types.toComplex(args[0]);
        const exp_r = @exp(c.real);
        const re = exp_r * @cos(c.imag);
        const im = exp_r * @sin(c.imag);
        if (@abs(im) < 1e-15) return makeFlonumVal(re);
        return gc.allocComplex(re, im) catch return PrimitiveError.OutOfMemory;
    }
    const f = try toF64(args[0]);
    return makeFlonumVal(@exp(f));
}

fn complexLog(gc: anytype, re: f64, im: f64) PrimitiveError!Value {
    const mag = @sqrt(re * re + im * im);
    const result_re = @log(mag);
    const result_im = std.math.atan2(im, re);
    if (@abs(result_im) < 1e-15) return makeFlonumVal(result_re);
    return gc.allocComplex(result_re, result_im) catch return PrimitiveError.OutOfMemory;
}

fn logFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 1) {
        if (types.isComplex(args[0])) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            const c = types.toComplex(args[0]);
            return complexLog(gc, c.real, c.imag);
        }
        const f = try toF64(args[0]);
        if (f < 0.0) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            return complexLog(gc, f, 0.0);
        }
        return makeFlonumVal(@log(f));
    }
    // (log z base)
    const z = try toF64(args[0]);
    const base = try toF64(args[1]);
    if (z < 0.0) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const mag = @sqrt(z * z);
        const log_re = @log(mag) / @log(base);
        const log_im = std.math.pi / @log(base);
        if (@abs(log_im) < 1e-15) return makeFlonumVal(log_re);
        return gc.allocComplex(log_re, log_im) catch return PrimitiveError.OutOfMemory;
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
        return if (std.math.isFinite(c.real) and std.math.isFinite(c.imag)) types.TRUE else types.FALSE;
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
        return if (std.math.isInf(c.real) or std.math.isInf(c.imag)) types.TRUE else types.FALSE;
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
        return if (std.math.isNan(c.real) or std.math.isNan(c.imag)) types.TRUE else types.FALSE;
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

pub fn toComplexParts(v: Value) PrimitiveError!struct { real: f64, imag: f64 } {
    if (types.isComplex(v)) {
        const c = types.toComplex(v);
        return .{ .real = c.real, .imag = c.imag };
    }
    if (types.isFixnum(v)) return .{ .real = @floatFromInt(types.toFixnum(v)), .imag = 0.0 };
    if (types.isFlonum(v)) return .{ .real = types.toFlonum(v), .imag = 0.0 };
    if (types.isBignum(v)) return .{ .real = bignum_mod.toF64(v), .imag = 0.0 };
    if (types.isRationalObj(v)) return .{ .real = try toF64Ext(v), .imag = 0.0 };
    return primitives.typeError("arithmetic", "number", v);
}

pub fn makeComplexOrReal(real: f64, imag: f64) PrimitiveError!Value {
    return makeComplexOrRealEx(real, imag, false, false);
}

pub fn makeComplexOrRealEx(real: f64, imag: f64, exact_real: bool, exact_imag: bool) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (imag == 0.0) {
        if (exact_real and real == @trunc(real) and @abs(real) < 4.5e18) {
            return try safeFloatToExactInt(real);
        }
        return types.makeFlonum(real);
    }
    return gc.allocComplexEx(real, imag, exact_real, exact_imag) catch return PrimitiveError.OutOfMemory;
}

const Exactness = enum { unspecified, exact, inexact };

fn applyExactness(_: *@import("memory.zig").GC, val: Value, exactness: Exactness) PrimitiveError!Value {
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
                const num_f = types.toF64(rat.numerator);
                const den_f = types.toF64(rat.denominator);
                return types.makeFlonum(num_f / den_f);
            }
            return val;
        },
        .exact => {
            if (types.isFlonum(val)) {
                const f = types.toFlonum(val);
                if (std.math.isNan(f) or std.math.isInf(f)) return types.FALSE;
                return exactFn(&.{val});
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
    var s = str.data[0..str.len];

    var radix: u8 = 10;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("string->number", "integer", args[1]);
        const r = types.toFixnum(args[1]);
        if (r < 2 or r > 36) return types.FALSE;
        radix = @intCast(@as(u64, @bitCast(r)));
    }

    // R7RS prefix handling: #b #o #d #x (radix) and #e #i (exactness)
    // Both can appear in either order: #e#xff or #x#eff
    var exactness: Exactness = .unspecified;
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
        if (slash_pos > 0 and slash_pos + 1 < s.len) {
            const num_str = s[0..slash_pos];
            const den_str = s[slash_pos + 1 ..];
            const num_val: Value = if (std.fmt.parseInt(i64, num_str, radix)) |num|
                try arith.makeFixnumChecked(num)
            else |err| blk: {
                if (err != error.Overflow) break :blk types.FALSE;
                break :blk bignum_mod.parseBignumString(gc, num_str, radix) catch |e| switch (e) {
                    error.InvalidCharacter => types.FALSE,
                    else => return PrimitiveError.OutOfMemory,
                };
            };
            if (num_val == types.FALSE) return types.FALSE;
            const den_val: Value = if (std.fmt.parseInt(i64, den_str, radix)) |den| blk: {
                if (den == 0) return types.FALSE;
                break :blk try arith.makeFixnumChecked(den);
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

    if (std.fmt.parseInt(i64, s, radix)) |n| {
        const result = try arith.makeFixnumChecked(n);
        return applyExactness(gc, result, exactness);
    } else |err| {
        if (err == error.Overflow) {
            const result = bignum_mod.parseBignumString(gc, s, radix) catch |e| switch (e) {
                error.InvalidCharacter => return types.FALSE,
                else => return PrimitiveError.OutOfMemory,
            };
            return applyExactness(gc, result, exactness);
        }
    }

    if (radix == 10) {
        if (exactness == .exact) {
            if (try parseExactDecimal(gc, s)) |v| return v;
        }

        if (std.fmt.parseFloat(f64, s)) |f| {
            return applyExactness(gc, types.makeFlonum(f), exactness);
        } else |_| {}

        // Try parsing as complex: a+bi, a-bi, +bi, -bi, +i, -i
        if (s.len >= 2 and s[s.len - 1] == 'i') {
            const body = s[0 .. s.len - 1]; // strip trailing 'i'

            // Pure imaginary: +i, -i
            if (std.mem.eql(u8, body, "+")) {
                const c = gc.allocComplex(0.0, 1.0) catch return PrimitiveError.OutOfMemory;
                return applyExactness(gc, c, exactness);
            }
            if (std.mem.eql(u8, body, "-")) {
                const c = gc.allocComplex(0.0, -1.0) catch return PrimitiveError.OutOfMemory;
                return applyExactness(gc, c, exactness);
            }

            // Find the split point: last +/- that isn't at position 0 and isn't in an exponent
            var split: ?usize = null;
            var j: usize = body.len;
            while (j > 1) {
                j -= 1;
                if (body[j] == '+' or body[j] == '-') {
                    if (j > 0 and (body[j - 1] == 'e' or body[j - 1] == 'E')) continue;
                    split = j;
                    break;
                }
            }

            if (split) |sp| {
                const real_str = body[0..sp];
                const imag_str = body[sp..];
                const real_val = if (real_str.len == 0) @as(f64, 0.0) else std.fmt.parseFloat(f64, real_str) catch {
                    return types.FALSE;
                };
                var imag_val: f64 = undefined;
                if (std.mem.eql(u8, imag_str, "+")) {
                    imag_val = 1.0;
                } else if (std.mem.eql(u8, imag_str, "-")) {
                    imag_val = -1.0;
                } else {
                    imag_val = std.fmt.parseFloat(f64, imag_str) catch {
                        return types.FALSE;
                    };
                }
                const c = gc.allocComplex(real_val, imag_val) catch return PrimitiveError.OutOfMemory;
                return applyExactness(gc, c, exactness);
            } else {
                // No split found — pure imaginary like +3i or -2.5i
                const imag_val = std.fmt.parseFloat(f64, body) catch {
                    return types.FALSE;
                };
                const c = gc.allocComplex(0.0, imag_val) catch return PrimitiveError.OutOfMemory;
                return applyExactness(gc, c, exactness);
            }
        }
    }

    return types.FALSE;
}

// ---------------------------------------------------------------------------
// Complex numbers (R7RS 6.2.6)
// ---------------------------------------------------------------------------

fn makeRectangular(args: []const Value) PrimitiveError!Value {
    const real = try toF64(args[0]);
    const imag = try toF64(args[1]);
    const er = types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0]);
    const ei = types.isFixnum(args[1]) or types.isBignum(args[1]) or types.isRationalObj(args[1]);
    return makeComplexOrRealEx(real, imag, er, ei);
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
        const c = types.toComplex(args[0]);
        if (c.exact_real and c.real == @trunc(c.real) and @abs(c.real) < 4.5e18) {
            return try safeFloatToExactInt(c.real);
        }
        return makeFlonumVal(c.real);
    }
    if (types.isFixnum(args[0]) or types.isFlonum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return args[0];
    return primitives.typeError("real-part", "number", args[0]);
}

fn imagPart(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        if (c.exact_imag and c.imag == @trunc(c.imag) and @abs(c.imag) < 4.5e18) {
            return try safeFloatToExactInt(c.imag);
        }
        return makeFlonumVal(c.imag);
    }
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.makeFixnum(0);
    if (types.isFlonum(args[0])) return makeFlonumVal(0.0);
    return primitives.typeError("imag-part", "number", args[0]);
}

fn magnitudeFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return makeFlonumVal(@sqrt(c.real * c.real + c.imag * c.imag));
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
        return makeFlonumVal(std.math.atan2(c.imag, c.real));
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
