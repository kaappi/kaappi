const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const toF64 = primitives.toF64;
const anyFlonum = primitives.anyFlonum;
const makeFlonumVal = primitives.makeFlonumVal;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

/// Raise a division-by-zero error through the exception system so that
/// (guard ...) can catch it.
fn raiseDivByZero() PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return raiseDivByZero();
    const gc = primitives.gc_instance orelse return raiseDivByZero();
    const msg = gc.allocString("division by zero") catch return raiseDivByZero();
    const err_obj = gc.allocErrorObject(msg, types.NIL) catch return raiseDivByZero();
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

pub fn registerArithmetic(vm: *vm_mod.VM) !void {
    // Arithmetic
    try reg(vm, "+", &add, .{ .variadic = 0 });
    try reg(vm, "-", &sub, .{ .variadic = 1 });
    try reg(vm, "*", &mul, .{ .variadic = 0 });
    try reg(vm, "/", &divFn, .{ .variadic = 1 });
    try reg(vm, "quotient", &quotient, .{ .exact = 2 });
    try reg(vm, "remainder", &remainder, .{ .exact = 2 });
    try reg(vm, "modulo", &modulo, .{ .exact = 2 });
    try reg(vm, "=", &numEq, .{ .variadic = 2 });
    try reg(vm, "<", &numLt, .{ .variadic = 2 });
    try reg(vm, ">", &numGt, .{ .variadic = 2 });
    try reg(vm, "<=", &numLe, .{ .variadic = 2 });
    try reg(vm, ">=", &numGe, .{ .variadic = 2 });
    try reg(vm, "zero?", &zeroP, .{ .exact = 1 });
    try reg(vm, "positive?", &positiveP, .{ .exact = 1 });
    try reg(vm, "negative?", &negativeP, .{ .exact = 1 });
    try reg(vm, "abs", &absVal, .{ .exact = 1 });
    try reg(vm, "min", &minVal, .{ .variadic = 1 });
    try reg(vm, "max", &maxVal, .{ .variadic = 1 });
    try reg(vm, "even?", &evenP, .{ .exact = 1 });
    try reg(vm, "odd?", &oddP, .{ .exact = 1 });
    try reg(vm, "gcd", &gcdFn, .{ .variadic = 0 });
    try reg(vm, "lcm", &lcmFn, .{ .variadic = 0 });

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
    try reg(vm, "number->string", &numberToString, .{ .exact = 1 });
    try reg(vm, "string->number", &stringToNumber, .{ .variadic = 1 });

    // Complex numbers (R7RS 6.2.6)
    try reg(vm, "make-rectangular", &makeRectangular, .{ .exact = 2 });
    try reg(vm, "make-polar", &makePolar, .{ .exact = 2 });
    try reg(vm, "real-part", &realPart, .{ .exact = 1 });
    try reg(vm, "imag-part", &imagPart, .{ .exact = 1 });
    try reg(vm, "magnitude", &magnitudeFn, .{ .exact = 1 });
    try reg(vm, "angle", &angleFn, .{ .exact = 1 });

    // Integer division (R7RS 6.2.6)
    try reg(vm, "floor-quotient", &floorQuotient, .{ .exact = 2 });
    try reg(vm, "floor-remainder", &floorRemainder, .{ .exact = 2 });
    try reg(vm, "floor/", &floorDivide, .{ .exact = 2 });
    try reg(vm, "truncate-quotient", &truncateQuotient, .{ .exact = 2 });
    try reg(vm, "truncate-remainder", &truncateRemainder, .{ .exact = 2 });
    try reg(vm, "truncate/", &truncateDivide, .{ .exact = 2 });

    // Rational (R7RS 6.2.6)
    try reg(vm, "numerator", &numeratorFn, .{ .exact = 1 });
    try reg(vm, "denominator", &denominatorFn, .{ .exact = 1 });
    try reg(vm, "rationalize", &rationalizeFn, .{ .exact = 2 });

    // Aliases
    try reg(vm, "exact->inexact", &inexactFn, .{ .exact = 1 });
    try reg(vm, "inexact->exact", &exactFn, .{ .exact = 1 });
}

// ---------------------------------------------------------------------------
// Arithmetic
// ---------------------------------------------------------------------------

fn add(args: []const Value) PrimitiveError!Value {
    if (isAnyComplex(args)) {
        var real: f64 = 0;
        var imag: f64 = 0;
        for (args) |a| {
            const c = try toComplexParts(a);
            real += c.real;
            imag += c.imag;
        }
        return makeComplexOrReal(real, imag);
    }
    if (anyFlonum(args)) {
        var sum: f64 = 0;
        for (args) |a| {
            sum += try toF64(a);
        }
        return makeFlonumVal(sum);
    }
    var sum: i64 = 0;
    for (args) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        sum += types.toFixnum(a);
    }
    return types.makeFixnum(sum);
}

fn sub(args: []const Value) PrimitiveError!Value {
    if (args.len == 0) return PrimitiveError.ArityMismatch;
    if (isAnyComplex(args)) {
        const first = try toComplexParts(args[0]);
        if (args.len == 1) return makeComplexOrReal(-first.real, -first.imag);
        var real = first.real;
        var imag = first.imag;
        for (args[1..]) |a| {
            const c = try toComplexParts(a);
            real -= c.real;
            imag -= c.imag;
        }
        return makeComplexOrReal(real, imag);
    }
    if (anyFlonum(args)) {
        if (args.len == 1) return makeFlonumVal(-(try toF64(args[0])));
        var result = try toF64(args[0]);
        for (args[1..]) |a| {
            result -= try toF64(a);
        }
        return makeFlonumVal(result);
    }
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    if (args.len == 1) return types.makeFixnum(-types.toFixnum(args[0]));
    var result = types.toFixnum(args[0]);
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        result -= types.toFixnum(a);
    }
    return types.makeFixnum(result);
}

fn mul(args: []const Value) PrimitiveError!Value {
    if (isAnyComplex(args)) {
        var real: f64 = 1;
        var imag: f64 = 0;
        for (args) |a| {
            const c = try toComplexParts(a);
            // (real + imag*i) * (c.real + c.imag*i)
            const new_real = real * c.real - imag * c.imag;
            const new_imag = real * c.imag + imag * c.real;
            real = new_real;
            imag = new_imag;
        }
        return makeComplexOrReal(real, imag);
    }
    if (anyFlonum(args)) {
        var product: f64 = 1;
        for (args) |a| {
            product *= try toF64(a);
        }
        return makeFlonumVal(product);
    }
    var product: i64 = 1;
    for (args) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        product *= types.toFixnum(a);
    }
    return types.makeFixnum(product);
}

fn divFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 0) return PrimitiveError.ArityMismatch;
    if (isAnyComplex(args)) {
        const first = try toComplexParts(args[0]);
        if (args.len == 1) {
            // 1/(a+bi) = (a-bi)/(a^2+b^2)
            const denom = first.real * first.real + first.imag * first.imag;
            if (denom == 0.0) return raiseDivByZero();
            return makeComplexOrReal(first.real / denom, -first.imag / denom);
        }
        var real = first.real;
        var imag = first.imag;
        for (args[1..]) |a| {
            const c = try toComplexParts(a);
            const denom = c.real * c.real + c.imag * c.imag;
            if (denom == 0.0) return raiseDivByZero();
            const new_real = (real * c.real + imag * c.imag) / denom;
            const new_imag = (imag * c.real - real * c.imag) / denom;
            real = new_real;
            imag = new_imag;
        }
        return makeComplexOrReal(real, imag);
    }
    if (args.len == 1) {
        // (/ z) = 1/z
        const a = try toF64(args[0]);
        if (a == 0) return raiseDivByZero();
        return makeFlonumVal(1.0 / a);
    }
    // All fixnums — try exact division
    if (!anyFlonum(args)) {
        var result = types.toFixnum(args[0]);
        for (args[1..]) |a| {
            if (!types.isFixnum(a)) return PrimitiveError.TypeError;
            const b = types.toFixnum(a);
            if (b == 0) return raiseDivByZero();
            if (@rem(result, b) == 0) {
                result = @divExact(result, b);
            } else {
                // Fall back to float for all
                var fr: f64 = @floatFromInt(types.toFixnum(args[0]));
                for (args[1..]) |a2| {
                    const bf: f64 = @floatFromInt(types.toFixnum(a2));
                    fr /= bf;
                }
                return makeFlonumVal(fr);
            }
        }
        return types.makeFixnum(result);
    }
    // At least one flonum
    var result = try toF64(args[0]);
    for (args[1..]) |a| {
        const b = try toF64(a);
        if (b == 0) return raiseDivByZero();
        result /= b;
    }
    return makeFlonumVal(result);
}

fn quotient(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@divTrunc(types.toFixnum(args[0]), b));
}

fn remainder(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@rem(types.toFixnum(args[0]), b));
}

fn modulo(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@mod(types.toFixnum(args[0]), b));
}

fn numEq(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try toF64(args[i]);
        const b = try toF64(args[i + 1]);
        if (a != b) return types.FALSE;
    }
    return types.TRUE;
}

fn numLt(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try toF64(args[i]);
        const b = try toF64(args[i + 1]);
        if (a >= b) return types.FALSE;
    }
    return types.TRUE;
}

fn numGt(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try toF64(args[i]);
        const b = try toF64(args[i + 1]);
        if (a <= b) return types.FALSE;
    }
    return types.TRUE;
}

fn numLe(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try toF64(args[i]);
        const b = try toF64(args[i + 1]);
        if (a > b) return types.FALSE;
    }
    return types.TRUE;
}

fn numGe(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try toF64(args[i]);
        const b = try toF64(args[i + 1]);
        if (a < b) return types.FALSE;
    }
    return types.TRUE;
}

fn zeroP(args: []const Value) PrimitiveError!Value {
    const v = try toF64(args[0]);
    return if (v == 0) types.TRUE else types.FALSE;
}

fn positiveP(args: []const Value) PrimitiveError!Value {
    const v = try toF64(args[0]);
    return if (v > 0) types.TRUE else types.FALSE;
}

fn negativeP(args: []const Value) PrimitiveError!Value {
    const v = try toF64(args[0]);
    return if (v < 0) types.TRUE else types.FALSE;
}

fn absVal(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) {
        const n = types.toFixnum(args[0]);
        return types.makeFixnum(if (n < 0) -n else n);
    }
    if (types.isFlonum(args[0])) {
        return makeFlonumVal(@abs(types.toFlonum(args[0])));
    }
    return PrimitiveError.TypeError;
}

fn minVal(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        var result = try toF64(args[0]);
        for (args[1..]) |a| {
            const n = try toF64(a);
            if (n < result) result = n;
        }
        return makeFlonumVal(result);
    }
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    var result = types.toFixnum(args[0]);
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        const n = types.toFixnum(a);
        if (n < result) result = n;
    }
    return types.makeFixnum(result);
}

fn maxVal(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        var result = try toF64(args[0]);
        for (args[1..]) |a| {
            const n = try toF64(a);
            if (n > result) result = n;
        }
        return makeFlonumVal(result);
    }
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    var result = types.toFixnum(args[0]);
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        const n = types.toFixnum(a);
        if (n > result) result = n;
    }
    return types.makeFixnum(result);
}

fn evenP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) {
        return if (@rem(types.toFixnum(args[0]), 2) == 0) types.TRUE else types.FALSE;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        return if (@rem(f, 2.0) == 0.0) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
}

fn oddP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) {
        return if (@rem(types.toFixnum(args[0]), 2) != 0) types.TRUE else types.FALSE;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        return if (@rem(f, 2.0) != 0.0) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
}

fn gcdTwo(a_in: i64, b_in: i64) i64 {
    var a = if (a_in < 0) -a_in else a_in;
    var b = if (b_in < 0) -b_in else b_in;
    while (b != 0) {
        const t = b;
        b = @mod(a, b);
        a = t;
    }
    return a;
}

fn gcdFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 0) return types.makeFixnum(0);
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    var result = types.toFixnum(args[0]);
    if (result < 0) result = -result;
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        result = gcdTwo(result, types.toFixnum(a));
    }
    return types.makeFixnum(result);
}

fn lcmFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 0) return types.makeFixnum(1);
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    var result = types.toFixnum(args[0]);
    if (result < 0) result = -result;
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        const b = types.toFixnum(a);
        const g = gcdTwo(result, b);
        if (g == 0) {
            result = 0;
        } else {
            result = @divExact(result, g) * (if (b < 0) -b else b);
        }
    }
    return types.makeFixnum(result);
}

// ---------------------------------------------------------------------------
// Rounding
// ---------------------------------------------------------------------------

fn floorFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isFlonum(args[0])) return makeFlonumVal(@floor(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

fn ceilingFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isFlonum(args[0])) return makeFlonumVal(@ceil(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

fn truncateFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isFlonum(args[0])) return makeFlonumVal(@trunc(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

fn roundFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isFlonum(args[0])) return makeFlonumVal(@round(types.toFlonum(args[0])));
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// Exactness
// ---------------------------------------------------------------------------

fn exactP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0])) types.TRUE else types.FALSE;
}

fn inexactP(args: []const Value) PrimitiveError!Value {
    return if (types.isFlonum(args[0])) types.TRUE else types.FALSE;
}

fn exactIntegerP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0])) types.TRUE else types.FALSE;
}

fn exactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (std.math.isNan(f) or std.math.isInf(f)) return PrimitiveError.TypeError;
        return types.makeFixnum(@intFromFloat(f));
    }
    return PrimitiveError.TypeError;
}

fn inexactFn(args: []const Value) PrimitiveError!Value {
    if (types.isFlonum(args[0])) return args[0];
    if (types.isFixnum(args[0])) return makeFlonumVal(@floatFromInt(types.toFixnum(args[0])));
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// Powers and roots
// ---------------------------------------------------------------------------

fn exptFn(args: []const Value) PrimitiveError!Value {
    // If both are fixnums and exponent is non-negative, try integer exponentiation
    if (types.isFixnum(args[0]) and types.isFixnum(args[1])) {
        const exp = types.toFixnum(args[1]);
        if (exp >= 0 and exp <= 62) {
            const base_val = types.toFixnum(args[0]);
            var result: i64 = 1;
            var b = base_val;
            var e: u6 = @intCast(exp);
            while (e > 0) {
                if (e & 1 == 1) result *= b;
                b *= b;
                e >>= 1;
            }
            return types.makeFixnum(result);
        }
    }
    const base_f = try toF64(args[0]);
    const exp_f = try toF64(args[1]);
    return makeFlonumVal(std.math.pow(f64, base_f, exp_f));
}

fn squareFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) {
        const n = types.toFixnum(args[0]);
        return types.makeFixnum(n * n);
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
    const n = types.toFixnum(args[0]);
    if (n < 0) return PrimitiveError.TypeError;
    const f: f64 = @floatFromInt(n);
    const s: i64 = @intFromFloat(@sqrt(f));
    // R7RS: returns two values (s, n - s*s) but we only support single values for now
    return types.makeFixnum(s);
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
    if (types.isFixnum(args[0])) return types.TRUE;
    if (types.isFlonum(args[0])) {
        return if (std.math.isFinite(types.toFlonum(args[0]))) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
}

fn infiniteP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return types.FALSE;
    if (types.isFlonum(args[0])) {
        return if (std.math.isInf(types.toFlonum(args[0]))) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
}

fn nanP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return types.FALSE;
    if (types.isFlonum(args[0])) {
        return if (std.math.isNan(types.toFlonum(args[0]))) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// Number/string conversion
// ---------------------------------------------------------------------------

fn numberToString(args: []const Value) PrimitiveError!Value {
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
        // Check if we need to append ".0"
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

fn isAnyComplex(args: []const Value) bool {
    for (args) |a| {
        if (types.isComplex(a)) return true;
    }
    return false;
}

fn toComplexParts(v: Value) PrimitiveError!struct { real: f64, imag: f64 } {
    if (types.isComplex(v)) {
        const c = types.toComplex(v);
        return .{ .real = c.real, .imag = c.imag };
    }
    if (types.isFixnum(v)) return .{ .real = @floatFromInt(types.toFixnum(v)), .imag = 0.0 };
    if (types.isFlonum(v)) return .{ .real = types.toFlonum(v), .imag = 0.0 };
    return PrimitiveError.TypeError;
}

fn makeComplexOrReal(real: f64, imag: f64) PrimitiveError!Value {
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

    // Check for special float values
    if (std.mem.eql(u8, s, "+inf.0")) return gc.allocFlonum(std.math.inf(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "-inf.0")) return gc.allocFlonum(-std.math.inf(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "+nan.0")) return gc.allocFlonum(std.math.nan(f64)) catch return PrimitiveError.OutOfMemory;
    if (std.mem.eql(u8, s, "-nan.0")) return gc.allocFlonum(std.math.nan(f64)) catch return PrimitiveError.OutOfMemory;

    // Try integer first
    if (std.fmt.parseInt(i64, s, 10)) |n| {
        return types.makeFixnum(n);
    } else |_| {}

    // Try float
    if (std.fmt.parseFloat(f64, s)) |f| {
        return gc.allocFlonum(f) catch return PrimitiveError.OutOfMemory;
    } else |_| {}

    return types.FALSE; // R7RS: return #f on failure
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

fn numeratorFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return args[0];
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (!std.math.isFinite(f)) return args[0];
        if (f == @trunc(f)) return args[0]; // integer-valued flonum
        // Approximate: find numerator of rational approximation
        // Simple approach: n/d where d is a power of 2
        const t = @trunc(f);
        const frac = f - t;
        const scale: f64 = 1e15;
        const n = @round(frac * scale);
        return makeFlonumVal(t * scale + n);
    }
    return PrimitiveError.TypeError;
}

fn denominatorFn(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return types.makeFixnum(1);
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (!std.math.isFinite(f)) return makeFlonumVal(1.0);
        if (f == @trunc(f)) return makeFlonumVal(1.0);
        return makeFlonumVal(1e15);
    }
    return PrimitiveError.TypeError;
}

fn rationalizeFn(args: []const Value) PrimitiveError!Value {
    // (rationalize x y) — return simplest rational within y of x
    // Simplified: just return x itself
    _ = args[1];
    return args[0];
}
