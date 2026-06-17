const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const bignum_mod = @import("bignum.zig");
const arith = @import("primitives_arithmetic.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const toF64 = primitives.toF64;
const anyFlonum = primitives.anyFlonum;
const makeFlonumVal = primitives.makeFlonumVal;
const toF64Ext = arith.toF64Ext;
const gcdTwo = arith.gcdTwo;
const raiseDivByZero = arith.raiseDivByZero;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerNumeric(vm: *vm_mod.VM) !void {
    // Rounding
    try reg(vm, "floor", &floorFn, .{ .exact = 1 });
    try reg(vm, "ceiling", &ceilingFn, .{ .exact = 1 });
    try reg(vm, "truncate", &truncateFn, .{ .exact = 1 });
    try reg(vm, "round", &roundFn, .{ .exact = 1 });

    // Exactness
    try reg(vm, "exact?", &exactP, .{ .exact = 1 });
    try reg(vm, "inexact?", &inexactP, .{ .exact = 1 });
    try reg(vm, "exact-integer?", &exactIntegerP, .{ .exact = 1 });
    try reg(vm, "exact", &exactFn, .{ .exact = 1 });
    try reg(vm, "inexact", &inexactFn, .{ .exact = 1 });

    // Powers and roots
    try reg(vm, "expt", &exptFn, .{ .exact = 2 });
    try reg(vm, "square", &squareFn, .{ .exact = 1 });
    try reg(vm, "sqrt", &sqrtFn, .{ .exact = 1 });
    try reg(vm, "exact-integer-sqrt", &exactIntegerSqrt, .{ .exact = 1 });

    // Trigonometry
    try reg(vm, "sin", &sinFn, .{ .exact = 1 });
    try reg(vm, "cos", &cosFn, .{ .exact = 1 });
    try reg(vm, "tan", &tanFn, .{ .exact = 1 });
    try reg(vm, "asin", &asinFn, .{ .exact = 1 });
    try reg(vm, "acos", &acosFn, .{ .exact = 1 });
    try reg(vm, "atan", &atanFn, .{ .variadic = 1 });

    // Exp/Log
    try reg(vm, "exp", &expFn, .{ .exact = 1 });
    try reg(vm, "log", &logFn, .{ .variadic = 1 });

    // Float predicates
    try reg(vm, "finite?", &finiteP, .{ .exact = 1 });
    try reg(vm, "infinite?", &infiniteP, .{ .exact = 1 });
    try reg(vm, "nan?", &nanP, .{ .exact = 1 });

    // Number/string conversion
    try reg(vm, "number->string", &numberToString, .{ .variadic = 1 });
    try reg(vm, "string->number", &stringToNumber, .{ .variadic = 1 });

    // Complex numbers
    try reg(vm, "make-rectangular", &makeRectangular, .{ .exact = 2 });
    try reg(vm, "make-polar", &makePolar, .{ .exact = 2 });
    try reg(vm, "real-part", &realPart, .{ .exact = 1 });
    try reg(vm, "imag-part", &imagPart, .{ .exact = 1 });
    try reg(vm, "magnitude", &magnitudeFn, .{ .exact = 1 });
    try reg(vm, "angle", &angleFn, .{ .exact = 1 });

    // Integer division
    try reg(vm, "floor-quotient", &floorQuotient, .{ .exact = 2 });
    try reg(vm, "floor-remainder", &floorRemainder, .{ .exact = 2 });
    try reg(vm, "floor/", &floorDivide, .{ .exact = 2 });
    try reg(vm, "truncate-quotient", &truncateQuotient, .{ .exact = 2 });
    try reg(vm, "truncate-remainder", &truncateRemainder, .{ .exact = 2 });
    try reg(vm, "truncate/", &truncateDivide, .{ .exact = 2 });

    // Rational
    try reg(vm, "numerator", &numeratorFn, .{ .exact = 1 });
    try reg(vm, "denominator", &denominatorFn, .{ .exact = 1 });
    try reg(vm, "rationalize", &rationalizeFn, .{ .exact = 2 });

    // Aliases
    try reg(vm, "exact->inexact", &inexactFn, .{ .exact = 1 });
    try reg(vm, "inexact->exact", &exactFn, .{ .exact = 1 });
}
// ---------------------------------------------------------------------------
// Rounding
// ---------------------------------------------------------------------------

fn floorFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) {
        const f = try toF64Ext(args[0]);
        return types.makeFixnum(@intFromFloat(@floor(f)));
    }
    if (types.isFlonum(args[0])) return makeFlonumVal(@floor(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

fn ceilingFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) {
        const f = try toF64Ext(args[0]);
        return types.makeFixnum(@intFromFloat(@ceil(f)));
    }
    if (types.isFlonum(args[0])) return makeFlonumVal(@ceil(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

fn truncateFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) {
        const f = try toF64Ext(args[0]);
        return types.makeFixnum(@intFromFloat(@trunc(f)));
    }
    if (types.isFlonum(args[0])) return makeFlonumVal(@trunc(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

fn roundFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) {
        const f = try toF64Ext(args[0]);
        return types.makeFixnum(@intFromFloat(@round(f)));
    }
    if (types.isFlonum(args[0])) return makeFlonumVal(@round(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// Exactness
// ---------------------------------------------------------------------------

fn exactP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) types.TRUE else types.FALSE;
}

fn inexactP(args: []const Value) PrimitiveError!Value {
    return if (types.isFlonum(args[0])) types.TRUE else types.FALSE;
}

fn exactIntegerP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0]) or types.isBignum(args[0])) types.TRUE else types.FALSE;
}

fn exactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isBignum(args[0])) return args[0];
    if (types.isRationalObj(args[0])) return args[0]; // already exact
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (std.math.isNan(f) or std.math.isInf(f)) return PrimitiveError.TypeError;
        // Check if it's an integer-valued float
        if (f == @trunc(f)) {
            return types.makeFixnum(@intFromFloat(f));
        }
        // Convert float to exact rational using 2^52 scaling
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        const scale: f64 = 4503599627370496.0; // 2^52
        const n_f = f * scale;
        if (n_f > @as(f64, @floatFromInt(std.math.maxInt(i63))) or n_f < @as(f64, @floatFromInt(std.math.minInt(i63)))) {
            // Too large for fixnum rational, just truncate
            return types.makeFixnum(@intFromFloat(f));
        }
        var n: i64 = @intFromFloat(n_f);
        var d: i64 = @intFromFloat(scale);
        const g = gcdTwo(if (n < 0) -n else n, d);
        if (g != 0) {
            n = @divExact(n, g);
            d = @divExact(d, g);
        }
        if (d == 1) return types.makeFixnum(n);
        return gc.allocRational(types.makeFixnum(n), types.makeFixnum(d)) catch return PrimitiveError.OutOfMemory;
    }
    return PrimitiveError.TypeError;
}

fn inexactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFlonum(args[0])) return args[0];
    if (types.isFixnum(args[0])) return makeFlonumVal(@floatFromInt(types.toFixnum(args[0])));
    if (types.isBignum(args[0])) return makeFlonumVal(bignum_mod.toF64(args[0]));
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        const n = try toF64Ext(r.numerator);
        const d = try toF64Ext(r.denominator);
        return makeFlonumVal(n / d);
    }
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// Powers and roots
// ---------------------------------------------------------------------------

fn exptFn(args: []const Value) PrimitiveError!Value {
    // If both are exact integers and exponent is non-negative, use bignum expt
    if ((types.isFixnum(args[0]) or types.isBignum(args[0])) and types.isFixnum(args[1])) {
        const exp = types.toFixnum(args[1]);
        if (exp >= 0) {
            // Use bignum exponentiation (handles overflow automatically)
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            return bignum_mod.expt(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
        }
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
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            return bignum_mod.mul(gc, args[0], args[0]) catch return PrimitiveError.OutOfMemory;
        }
        return types.makeFixnum(r[0]);
    }
    if (types.isBignum(args[0])) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        return bignum_mod.mul(gc, args[0], args[0]) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        return makeFlonumVal(f * f);
    }
    return PrimitiveError.TypeError;
}

fn sqrtFn(args: []const Value) PrimitiveError!Value {
    const f = try toF64(args[0]);
    const result = @sqrt(f);
    // If input was fixnum and result is exact integer, return fixnum
    if (types.isFixnum(args[0]) and f >= 0) {
        const ri: i64 = @intFromFloat(result);
        if (ri * ri == types.toFixnum(args[0])) return types.makeFixnum(ri);
    }
    return makeFlonumVal(result);
}

fn exactIntegerSqrt(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const n = types.toFixnum(args[0]);
    if (n < 0) return PrimitiveError.TypeError;
    const f: f64 = @floatFromInt(n);
    var s: i64 = @intFromFloat(@sqrt(f));
    // Adjust for floating-point imprecision
    while (s * s > n) s -= 1;
    while ((s + 1) * (s + 1) <= n) s += 1;
    const rem = n - s * s;
    const vals = [_]Value{ types.makeFixnum(s), types.makeFixnum(rem) };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Trigonometry
// ---------------------------------------------------------------------------

fn sinFn(args: []const Value) PrimitiveError!Value {
    const f = try toF64(args[0]);
    return makeFlonumVal(@sin(f));
}

fn cosFn(args: []const Value) PrimitiveError!Value {
    const f = try toF64(args[0]);
    return makeFlonumVal(@cos(f));
}

fn tanFn(args: []const Value) PrimitiveError!Value {
    const f = try toF64(args[0]);
    return makeFlonumVal(@tan(f));
}

fn asinFn(args: []const Value) PrimitiveError!Value {
    const f = try toF64(args[0]);
    return makeFlonumVal(std.math.asin(f));
}

fn acosFn(args: []const Value) PrimitiveError!Value {
    const f = try toF64(args[0]);
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
    const f = try toF64(args[0]);
    return makeFlonumVal(@exp(f));
}

fn logFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 1) {
        const f = try toF64(args[0]);
        return makeFlonumVal(@log(f));
    }
    // (log z base)
    const z = try toF64(args[0]);
    const base = try toF64(args[1]);
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
    return PrimitiveError.TypeError;
}

fn infiniteP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.FALSE;
    if (types.isFlonum(args[0])) {
        return if (std.math.isInf(types.toFlonum(args[0]))) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
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
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// Number/string conversion
// ---------------------------------------------------------------------------

fn numberToString(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var radix: u8 = 10;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const r = types.toFixnum(args[1]);
        if (r < 2 or r > 36) return PrimitiveError.TypeError;
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
            if (neg) { pos -= 1; buf[pos] = '-'; }
            return gc.allocString(buf[pos..]) catch return PrimitiveError.OutOfMemory;
        }
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(args[0])}) catch return PrimitiveError.OutOfMemory;
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isBignum(args[0])) {
        const s = bignum_mod.toString(gc.allocator, args[0]) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(s);
        return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isRationalObj(args[0])) {
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
    return PrimitiveError.TypeError;
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
    return PrimitiveError.TypeError;
}

pub fn makeComplexOrReal(real: f64, imag: f64) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (imag == 0.0) {
        return gc.allocFlonum(real) catch return PrimitiveError.OutOfMemory;
    }
    return gc.allocComplex(real, imag) catch return PrimitiveError.OutOfMemory;
}

fn stringToNumber(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const s = str.data[0..str.len];

    var radix: u8 = 10;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const r = types.toFixnum(args[1]);
        if (r < 2 or r > 36) return types.FALSE;
        radix = @intCast(@as(u64, @bitCast(r)));
    }

    if (std.mem.eql(u8, s, "+inf.0")) return gc.allocFlonum(std.math.inf(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "-inf.0")) return gc.allocFlonum(-std.math.inf(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "+nan.0")) return gc.allocFlonum(std.math.nan(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "-nan.0")) return gc.allocFlonum(std.math.nan(f64)) catch return PrimitiveError.OutOfMemory;

    if (radix == 10) {
        if (std.mem.indexOfScalar(u8, s, '/')) |slash_pos| {
            if (slash_pos > 0 and slash_pos + 1 < s.len) {
                const num_str = s[0..slash_pos];
                const den_str = s[slash_pos + 1 ..];
                if (std.fmt.parseInt(i64, num_str, 10)) |num| {
                    if (std.fmt.parseInt(i64, den_str, 10)) |den| {
                        if (den == 0) return types.FALSE;
                        return arith.makeRationalFromReader(gc, num, den) catch return PrimitiveError.OutOfMemory;
                    } else |_| {}
                } else |_| {}
            }
        }
    }

    if (std.fmt.parseInt(i64, s, radix)) |n| {
        return types.makeFixnum(n);
    } else |err| {
        if (err == error.Overflow and radix == 10) {
            return bignum_mod.parseBignumString(gc, s) catch return PrimitiveError.OutOfMemory;
        }
    }

    if (radix == 10) {
        if (std.fmt.parseFloat(f64, s)) |f| {
            return gc.allocFlonum(f) catch return PrimitiveError.OutOfMemory;
        } else |_| {}
    }

    return types.FALSE;
}

// ---------------------------------------------------------------------------
// Complex numbers (R7RS 6.2.6)
// ---------------------------------------------------------------------------

fn makeRectangular(args: []const Value) PrimitiveError!Value {
    const real = try toF64(args[0]);
    const imag = try toF64(args[1]);
    return makeComplexOrReal(real, imag);
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
        return makeFlonumVal(types.toComplex(args[0]).real);
    }
    if (types.isFixnum(args[0]) or types.isFlonum(args[0])) return args[0];
    return PrimitiveError.TypeError;
}

fn imagPart(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        return makeFlonumVal(types.toComplex(args[0]).imag);
    }
    if (types.isFixnum(args[0])) return types.makeFixnum(0);
    if (types.isFlonum(args[0])) return makeFlonumVal(0.0);
    return PrimitiveError.TypeError;
}

fn magnitudeFn(args: []const Value) PrimitiveError!Value {
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return makeFlonumVal(@sqrt(c.real * c.real + c.imag * c.imag));
    }
    if (types.isFixnum(args[0])) {
        const n = types.toFixnum(args[0]);
        return if (n < 0) types.makeFixnum(-n) else args[0];
    }
    if (types.isFlonum(args[0])) {
        return makeFlonumVal(@abs(types.toFlonum(args[0])));
    }
    return PrimitiveError.TypeError;
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
        return makeFlonumVal(if (f >= 0.0) 0.0 else std.math.pi);
    }
    return PrimitiveError.TypeError;
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
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const a = types.toFixnum(args[0]);
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@divFloor(a, b));
}

fn floorRemainder(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        const a = try toF64(args[0]);
        const b = try toF64(args[1]);
        if (b == 0.0) return raiseDivByZero();
        return makeFlonumVal(a - @floor(a / b) * b);
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const a = types.toFixnum(args[0]);
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@mod(a, b));
}

fn floorDivide(args: []const Value) PrimitiveError!Value {
    // (floor/ n1 n2) returns two values: quotient and remainder
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const q_val = try floorQuotient(args);
    const r_val = try floorRemainder(args);
    const vals = [_]Value{ q_val, r_val };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

fn truncateQuotient(args: []const Value) PrimitiveError!Value {
    // Same as quotient
    if (anyFlonum(args)) {
        const a = try toF64(args[0]);
        const b = try toF64(args[1]);
        if (b == 0.0) return raiseDivByZero();
        return makeFlonumVal(@trunc(a / b));
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@divTrunc(types.toFixnum(args[0]), b));
}

fn truncateRemainder(args: []const Value) PrimitiveError!Value {
    // Same as remainder
    if (anyFlonum(args)) {
        const a = try toF64(args[0]);
        const b = try toF64(args[1]);
        if (b == 0.0) return raiseDivByZero();
        return makeFlonumVal(a - @trunc(a / b) * b);
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@rem(types.toFixnum(args[0]), b));
}

fn truncateDivide(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const q_val = try truncateQuotient(args);
    const r_val = try truncateRemainder(args);
    const vals = [_]Value{ q_val, r_val };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Rational operations (R7RS 6.2.6)
// ---------------------------------------------------------------------------

fn floatToRational(f: f64) struct { num: i64, den: i64 } {
    if (f == @trunc(f)) return .{ .num = @intFromFloat(f), .den = 1 };
    const sign: i64 = if (f < 0) -1 else 1;
    const abs_f = @abs(f);
    var best_num: i64 = @intFromFloat(@round(abs_f));
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
        const rat = floatToRational(f);
        return makeFlonumVal(@floatFromInt(rat.num));
    }
    return PrimitiveError.TypeError;
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
        const rat = floatToRational(f);
        return makeFlonumVal(@floatFromInt(rat.den));
    }
    return PrimitiveError.TypeError;
}

fn rationalizeFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
