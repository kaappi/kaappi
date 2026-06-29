const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const bignum_mod = @import("bignum.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const toF64 = primitives.toF64;
const anyFlonum = primitives.anyFlonum;
const makeFlonumVal = primitives.makeFlonumVal;
const numeric = @import("primitives_numeric.zig");
const isAnyComplex = numeric.isAnyComplex;
const toComplexParts = numeric.toComplexParts;
const makeComplexOrReal = numeric.makeComplexOrReal;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn makeFixnumChecked(n: i64) PrimitiveError!Value {
    if (n >= std.math.minInt(i48) and n <= std.math.maxInt(i48))
        return types.makeFixnum(n);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocBignumFromI64(n) catch return PrimitiveError.OutOfMemory;
}

/// Extended toF64 that also handles bignums and rationals.
pub fn toF64Ext(v: Value) PrimitiveError!f64 {
    if (types.isFixnum(v)) return @floatFromInt(types.toFixnum(v));
    if (types.isFlonum(v)) return types.toFlonum(v);
    if (types.isBignum(v)) return bignum_mod.toF64(v);
    if (types.isRationalObj(v)) {
        const r = types.toRational(v);
        const n = try toF64Ext(r.numerator);
        const d = try toF64Ext(r.denominator);
        return n / d;
    }
    return numberTypeError(v);
}

fn numberTypeError(v: Value) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const p = @import("printer.zig");
    const s = p.valueToString(vm.gc.allocator, v, .write) catch "";
    defer if (s.len > 0) vm.gc.allocator.free(s);
    vm.setErrorDetail("expected number, got {s}", .{s});
    return PrimitiveError.TypeError; // bare-ok: helper fallback
}

// ---------------------------------------------------------------------------
// Rational helpers
// ---------------------------------------------------------------------------

fn anyRational(args: []const Value) bool {
    for (args) |a| {
        if (types.isRationalObj(a)) return true;
    }
    return false;
}

const RatParts = struct { num: i64, den: i64 };

/// Extract numerator/denominator from any exact number.
fn toRationalParts(v: Value) RatParts {
    if (types.isFixnum(v)) return .{ .num = types.toFixnum(v), .den = 1 };
    if (types.isRationalObj(v)) {
        const r = types.toRational(v);
        return .{ .num = types.toFixnum(r.numerator), .den = types.toFixnum(r.denominator) };
    }
    return .{ .num = 0, .den = 1 };
}

/// Construct a reduced rational (or integer if den divides num).
/// Always ensures: denominator > 0, gcd(|num|,den) == 1, den==1 => fixnum.
pub fn makeRationalReduced(gc: *@import("memory.zig").GC, num_val: Value, den_val: Value) PrimitiveError!Value {
    if (types.isFixnum(num_val) and types.isFixnum(den_val)) {
        var n = types.toFixnum(num_val);
        var d = types.toFixnum(den_val);
        if (d == 0) return raiseDivByZero();
        if (n == 0) return types.makeFixnum(0);
        // Ensure positive denominator
        if (d < 0) {
            // Handle overflow of negation
            if (n == std.math.minInt(i64) or d == std.math.minInt(i64)) {
                // Fall back to float for these extreme cases
                const fn_val: f64 = @floatFromInt(n);
                const fd_val: f64 = @floatFromInt(d);
                return makeFlonumVal(fn_val / fd_val);
            }
            n = -n;
            d = -d;
        }
        const g = gcdTwo(if (n < 0) -n else n, d);
        n = @divExact(n, g);
        d = @divExact(d, g);
        if (d == 1) return try makeFixnumChecked(n);
        const num = try makeFixnumChecked(n);
        const den = try makeFixnumChecked(d);
        return gc.allocRational(num, den) catch return PrimitiveError.OutOfMemory;
    }
    // Bignum-containing case: check for zero denominator
    if (bignum_mod.isZero(den_val)) return raiseDivByZero();
    return gc.allocRational(num_val, den_val) catch return PrimitiveError.OutOfMemory;
}

/// Raise a division-by-zero error through the exception system so that
/// (guard ...) can catch it.
pub fn raiseDivByZero() PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.DivisionByZero;
    const gc = primitives.gc_instance orelse return PrimitiveError.DivisionByZero;
    var msg = gc.allocString("division by zero") catch return PrimitiveError.DivisionByZero;
    gc.pushRoot(&msg) catch return PrimitiveError.DivisionByZero;
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, types.NIL) catch return PrimitiveError.DivisionByZero;
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

    // Rounding, exactness, trig, complex, division, rationals
    const primitives_numeric = @import("primitives_numeric.zig");
    try primitives_numeric.registerNumeric(vm);
}

/// Public entry point for creating reduced rationals from the reader.
/// Does not use raiseDivByZero (returns error instead).
pub fn makeRationalFromReader(gc: *@import("memory.zig").GC, num: i64, den: i64) !Value {
    if (den == 0) return error.OutOfMemory;
    var n = num;
    var d = den;
    if (n == 0) return types.makeFixnum(0);
    // Ensure positive denominator
    if (d < 0) {
        if (n == std.math.minInt(i64) or d == std.math.minInt(i64)) {
            // Overflow on negation — fall back to float
            const fn_val: f64 = @floatFromInt(n);
            const fd_val: f64 = @floatFromInt(d);
            return makeFlonumVal(fn_val / fd_val);
        }
        n = -n;
        d = -d;
    }
    // Safe to negate n for GCD since we handled minInt above for d < 0,
    // but n could still be minInt with positive d
    if (n == std.math.minInt(i64)) {
        const fn_val: f64 = @floatFromInt(n);
        const fd_val: f64 = @floatFromInt(d);
        return makeFlonumVal(fn_val / fd_val);
    }
    const abs_n = if (n < 0) -n else n;
    const g = gcdTwo(abs_n, d);
    n = @divExact(n, g);
    d = @divExact(d, g);
    if (d == 1) return types.makeFixnum(n);
    return gc.allocRational(types.makeFixnum(n), types.makeFixnum(d));
}

// ---------------------------------------------------------------------------
// Arithmetic
// ---------------------------------------------------------------------------

fn anyBignum(args: []const Value) bool {
    for (args) |a| {
        if (types.isBignum(a)) return true;
    }
    return false;
}

fn bignumAddAll(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var result: Value = types.makeFixnum(0);
    gc.extra_roots.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
    defer {
        if (gc.extra_roots.items.len > 0) _ = gc.extra_roots.pop();
    }
    for (args) |a| {
        if (!types.isFixnum(a) and !types.isBignum(a)) return PrimitiveError.TypeError;
        result = bignum_mod.add(gc, result, a) catch return PrimitiveError.OutOfMemory;
        gc.extra_roots.items[gc.extra_roots.items.len - 1] = result;
    }
    return result;
}

fn bignumSubAll(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 1) {
        if (!types.isFixnum(args[0]) and !types.isBignum(args[0])) return PrimitiveError.TypeError;
        return bignum_mod.negate(gc, args[0]) catch return PrimitiveError.OutOfMemory;
    }
    var result = args[0];
    if (!types.isFixnum(result) and !types.isBignum(result)) return PrimitiveError.TypeError;
    gc.extra_roots.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
    defer {
        if (gc.extra_roots.items.len > 0) _ = gc.extra_roots.pop();
    }
    for (args[1..]) |a| {
        if (!types.isFixnum(a) and !types.isBignum(a)) return PrimitiveError.TypeError;
        result = bignum_mod.sub(gc, result, a) catch return PrimitiveError.OutOfMemory;
        gc.extra_roots.items[gc.extra_roots.items.len - 1] = result;
    }
    return result;
}

fn bignumMulAll(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var result: Value = types.makeFixnum(1);
    gc.extra_roots.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
    defer {
        if (gc.extra_roots.items.len > 0) _ = gc.extra_roots.pop();
    }
    for (args) |a| {
        if (!types.isFixnum(a) and !types.isBignum(a)) return PrimitiveError.TypeError;
        result = bignum_mod.mul(gc, result, a) catch return PrimitiveError.OutOfMemory;
        gc.extra_roots.items[gc.extra_roots.items.len - 1] = result;
    }
    return result;
}

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
            sum += try toF64Ext(a);
        }
        return makeFlonumVal(sum);
    }
    if (anyRational(args)) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        // Rational addition: accumulate as n/d
        var n: i64 = 0;
        var d: i64 = 1;
        for (args) |a| {
            if (types.isFlonum(a)) {
                // Mixed: convert accumulator to float
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f += types.toFlonum(a);
                return makeFlonumVal(f);
            }
            if (types.isBignum(a)) {
                // Fall back to float for bignum + rational
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f += bignum_mod.toF64(a);
                return makeFlonumVal(f);
            }
            const parts = toRationalParts(a);
            // n/d + parts.num/parts.den = (n*parts.den + parts.num*d) / (d*parts.den)
            const r1 = @mulWithOverflow(n, parts.den);
            const r2 = @mulWithOverflow(parts.num, d);
            const r3 = @mulWithOverflow(d, parts.den);
            if (r1[1] != 0 or r2[1] != 0 or r3[1] != 0) {
                // Overflow: fall back to float
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f += @as(f64, @floatFromInt(parts.num)) / @as(f64, @floatFromInt(parts.den));
                return makeFlonumVal(f);
            }
            const r4 = @addWithOverflow(r1[0], r2[0]);
            if (r4[1] != 0) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f += @as(f64, @floatFromInt(parts.num)) / @as(f64, @floatFromInt(parts.den));
                return makeFlonumVal(f);
            }
            n = r4[0];
            d = r3[0];
            // Reduce periodically to prevent overflow
            const g = gcdTwo(if (n < 0) -n else n, d);
            if (g != 0) {
                n = @divExact(n, g);
                d = @divExact(d, g);
            }
        }
        if (d == 1) return try makeFixnumChecked(n);
        if (d < 0) {
            n = -n;
            d = -d;
        }
        const num = try makeFixnumChecked(n);
        const den = try makeFixnumChecked(d);
        return gc.allocRational(num, den) catch return PrimitiveError.OutOfMemory;
    }
    if (anyBignum(args)) return bignumAddAll(args);
    // Fixnum path with overflow detection
    var sum: i64 = 0;
    for (args) |a| {
        if (!types.isFixnum(a)) return numberTypeError(a);
        const r = @addWithOverflow(sum, types.toFixnum(a));
        if (r[1] != 0) return bignumAddAll(args);
        sum = r[0];
    }
    return makeFixnumChecked(sum);
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
        if (args.len == 1) return makeFlonumVal(-(try toF64Ext(args[0])));
        var result = try toF64Ext(args[0]);
        for (args[1..]) |a| {
            result -= try toF64Ext(a);
        }
        return makeFlonumVal(result);
    }
    if (anyRational(args)) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        const first_parts = toRationalParts(args[0]);
        var n = first_parts.num;
        var d = first_parts.den;
        if (args.len == 1) {
            // Negate
            if (d == 1) return types.makeFixnum(-n);
            return gc.allocRational(types.makeFixnum(-n), types.makeFixnum(d)) catch return PrimitiveError.OutOfMemory;
        }
        for (args[1..]) |a| {
            if (types.isFlonum(a)) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f -= types.toFlonum(a);
                return makeFlonumVal(f);
            }
            if (types.isBignum(a)) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f -= bignum_mod.toF64(a);
                return makeFlonumVal(f);
            }
            const parts = toRationalParts(a);
            // n/d - parts.num/parts.den = (n*parts.den - parts.num*d) / (d*parts.den)
            const r1 = @mulWithOverflow(n, parts.den);
            const r2 = @mulWithOverflow(parts.num, d);
            const r3 = @mulWithOverflow(d, parts.den);
            if (r1[1] != 0 or r2[1] != 0 or r3[1] != 0) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f -= @as(f64, @floatFromInt(parts.num)) / @as(f64, @floatFromInt(parts.den));
                return makeFlonumVal(f);
            }
            const r4 = @subWithOverflow(r1[0], r2[0]);
            if (r4[1] != 0) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f -= @as(f64, @floatFromInt(parts.num)) / @as(f64, @floatFromInt(parts.den));
                return makeFlonumVal(f);
            }
            n = r4[0];
            d = r3[0];
            const g = gcdTwo(if (n < 0) -n else n, d);
            if (g != 0) {
                n = @divExact(n, g);
                d = @divExact(d, g);
            }
        }
        if (n == 0) return types.makeFixnum(0);
        if (d == 1) return try makeFixnumChecked(n);
        if (d < 0) {
            n = -n;
            d = -d;
        }
        const num = try makeFixnumChecked(n);
        const den = try makeFixnumChecked(d);
        return gc.allocRational(num, den) catch return PrimitiveError.OutOfMemory;
    }
    if (anyBignum(args)) return bignumSubAll(args);
    if (!types.isFixnum(args[0]) and !types.isRationalObj(args[0])) return numberTypeError(args[0]);
    if (!types.isFixnum(args[0])) return numberTypeError(args[0]);
    if (args.len == 1) {
        const n = types.toFixnum(args[0]);
        // Negation overflow: -minInt(i64) overflows
        const r = @subWithOverflow(@as(i64, 0), n);
        if (r[1] != 0) return bignumSubAll(args);
        return makeFixnumChecked(r[0]);
    }
    var result = types.toFixnum(args[0]);
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return numberTypeError(a);
        const r = @subWithOverflow(result, types.toFixnum(a));
        if (r[1] != 0) return bignumSubAll(args);
        result = r[0];
    }
    return makeFixnumChecked(result);
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
            product *= try toF64Ext(a);
        }
        return makeFlonumVal(product);
    }
    if (anyRational(args)) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        var n: i64 = 1;
        var d: i64 = 1;
        for (args) |a| {
            if (types.isFlonum(a)) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f *= types.toFlonum(a);
                return makeFlonumVal(f);
            }
            if (types.isBignum(a)) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f *= bignum_mod.toF64(a);
                return makeFlonumVal(f);
            }
            const parts = toRationalParts(a);
            // n/d * parts.num/parts.den = (n*parts.num) / (d*parts.den)
            const r1 = @mulWithOverflow(n, parts.num);
            const r2 = @mulWithOverflow(d, parts.den);
            if (r1[1] != 0 or r2[1] != 0) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f *= @as(f64, @floatFromInt(parts.num)) / @as(f64, @floatFromInt(parts.den));
                return makeFlonumVal(f);
            }
            n = r1[0];
            d = r2[0];
            // Reduce to prevent overflow
            if (n == 0) return types.makeFixnum(0);
            const g = gcdTwo(if (n < 0) -n else n, if (d < 0) -d else d);
            if (g != 0) {
                n = @divExact(n, g);
                d = @divExact(d, g);
            }
        }
        if (n == 0) return types.makeFixnum(0);
        if (d < 0) {
            n = -n;
            d = -d;
        }
        if (d == 1) return try makeFixnumChecked(n);
        const num = try makeFixnumChecked(n);
        const den = try makeFixnumChecked(d);
        return gc.allocRational(num, den) catch return PrimitiveError.OutOfMemory;
    }
    if (anyBignum(args)) return bignumMulAll(args);
    var product: i64 = 1;
    for (args) |a| {
        if (!types.isFixnum(a)) return numberTypeError(a);
        const r = @mulWithOverflow(product, types.toFixnum(a));
        if (r[1] != 0) return bignumMulAll(args);
        product = r[0];
    }
    return makeFixnumChecked(product);
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
        if (types.isFixnum(args[0])) {
            const a_val = types.toFixnum(args[0]);
            if (a_val == 0) return raiseDivByZero();
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            return makeRationalReduced(gc, types.makeFixnum(1), types.makeFixnum(a_val));
        }
        if (types.isRationalObj(args[0])) {
            // 1 / (n/d) = d/n
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            const r = types.toRational(args[0]);
            return makeRationalReduced(gc, r.denominator, r.numerator);
        }
        const a = try toF64Ext(args[0]);
        if (a == 0) return raiseDivByZero();
        return makeFlonumVal(1.0 / a);
    }
    // Handle rational division: any rational arg means rational result
    if (anyRational(args) and !anyFlonum(args)) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        const first_parts = toRationalParts(args[0]);
        var n = first_parts.num;
        var d = first_parts.den;
        for (args[1..]) |a| {
            if (types.isBignum(a)) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f /= bignum_mod.toF64(a);
                return makeFlonumVal(f);
            }
            const parts = toRationalParts(a);
            if (parts.num == 0) return raiseDivByZero();
            // (n/d) / (parts.num/parts.den) = (n*parts.den) / (d*parts.num)
            const r1 = @mulWithOverflow(n, parts.den);
            const r2 = @mulWithOverflow(d, parts.num);
            if (r1[1] != 0 or r2[1] != 0) {
                var f: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(d));
                f /= @as(f64, @floatFromInt(parts.num)) / @as(f64, @floatFromInt(parts.den));
                return makeFlonumVal(f);
            }
            n = r1[0];
            d = r2[0];
            if (d < 0) {
                n = -n;
                d = -d;
            }
            const g = gcdTwo(if (n < 0) -n else n, d);
            if (g != 0) {
                n = @divExact(n, g);
                d = @divExact(d, g);
            }
        }
        if (n == 0) return types.makeFixnum(0);
        if (d == 1) return try makeFixnumChecked(n);
        const num = try makeFixnumChecked(n);
        const den = try makeFixnumChecked(d);
        return gc.allocRational(num, den) catch return PrimitiveError.OutOfMemory;
    }
    // All exact integers (fixnum or bignum) — try exact division, produce rational if needed
    if (!anyFlonum(args) and !anyBignum(args) and !anyRational(args)) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        var n = types.toFixnum(args[0]);
        var d: i64 = 1;
        for (args[1..]) |a| {
            if (!types.isFixnum(a)) return PrimitiveError.TypeError;
            const b = types.toFixnum(a);
            if (b == 0) return raiseDivByZero();
            // n/d / b = n / (d*b)
            const r1 = @mulWithOverflow(d, b);
            if (r1[1] != 0) {
                // Overflow: fall back to float
                var fr: f64 = @floatFromInt(types.toFixnum(args[0]));
                for (args[1..]) |a2| {
                    const bf: f64 = @floatFromInt(types.toFixnum(a2));
                    fr /= bf;
                }
                return makeFlonumVal(fr);
            }
            d = r1[0];
            // Reduce to prevent overflow
            if (d < 0) {
                n = -n;
                d = -d;
            }
            const g = gcdTwo(if (n < 0) -n else n, d);
            if (g != 0) {
                n = @divExact(n, g);
                d = @divExact(d, g);
            }
        }
        if (n == 0) return types.makeFixnum(0);
        if (d == 1) return makeFixnumChecked(n);
        return gc.allocRational(try makeFixnumChecked(n), try makeFixnumChecked(d)) catch return PrimitiveError.OutOfMemory;
    }
    // Exact integer division with bignums: try quotient to preserve exactness
    if (anyBignum(args) and !anyFlonum(args) and !anyRational(args) and args.len == 2) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        const rem = bignum_mod.remainder(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(rem)) {
            const q = bignum_mod.quotient(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
            return bignum_mod.demote(q);
        }
    }
    // At least one flonum or bignum — convert to float
    var result = try toF64Ext(args[0]);
    for (args[1..]) |a| {
        const b = try toF64Ext(a);
        if (b == 0) return raiseDivByZero();
        result /= b;
    }
    return makeFlonumVal(result);
}

fn quotient(args: []const Value) PrimitiveError!Value {
    if (types.isBignum(args[0]) or types.isBignum(args[1])) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        return bignum_mod.quotient(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isFlonum(args[0]) or types.isFlonum(args[1])) {
        const a = try toF64Ext(args[0]);
        const b = try toF64Ext(args[1]);
        if (b == 0) return raiseDivByZero();
        return makeFlonumVal(@trunc(a / b));
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return makeFixnumChecked(@divTrunc(types.toFixnum(args[0]), b));
}

fn remainder(args: []const Value) PrimitiveError!Value {
    if (types.isBignum(args[0]) or types.isBignum(args[1])) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        return bignum_mod.remainder(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isFlonum(args[0]) or types.isFlonum(args[1])) {
        const a = try toF64Ext(args[0]);
        const b = try toF64Ext(args[1]);
        if (b == 0) return raiseDivByZero();
        return makeFlonumVal(@rem(a, b));
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@rem(types.toFixnum(args[0]), b));
}

fn modulo(args: []const Value) PrimitiveError!Value {
    if (types.isBignum(args[0]) or types.isBignum(args[1])) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(args[1])) return raiseDivByZero();
        const rem = bignum_mod.remainder(gc, args[0], args[1]) catch return PrimitiveError.OutOfMemory;
        if (bignum_mod.isZero(rem)) return types.makeFixnum(0);
        if (bignum_mod.isNegative(rem) != bignum_mod.isNegative(args[1])) {
            return bignum_mod.add(gc, rem, args[1]) catch return PrimitiveError.OutOfMemory;
        }
        return rem;
    }
    if (types.isFlonum(args[0]) or types.isFlonum(args[1])) {
        const a = try toF64Ext(args[0]);
        const b = try toF64Ext(args[1]);
        if (b == 0) return raiseDivByZero();
        var r = @rem(a, b);
        if (r != 0 and (r < 0) != (b < 0)) r += b;
        return makeFlonumVal(r);
    }
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return raiseDivByZero();
    return types.makeFixnum(@mod(types.toFixnum(args[0]), b));
}

fn cmpPair(a: Value, b: Value) PrimitiveError!i8 {
    // Both exact integers (fixnum or bignum): use exact comparison
    if ((types.isFixnum(a) or types.isBignum(a)) and (types.isFixnum(b) or types.isBignum(b))) {
        return bignum_mod.compare(a, b);
    }
    // Rational comparison: cross-multiply to avoid floating point
    if ((types.isRationalObj(a) or types.isFixnum(a)) and (types.isRationalObj(b) or types.isFixnum(b))) {
        if (types.isRationalObj(a) or types.isRationalObj(b)) {
            const pa = toRationalParts(a);
            const pb = toRationalParts(b);
            // Compare a_num/a_den vs b_num/b_den
            // a_num * b_den vs b_num * a_den (both denominators positive)
            const r1 = @mulWithOverflow(pa.num, pb.den);
            const r2 = @mulWithOverflow(pb.num, pa.den);
            if (r1[1] == 0 and r2[1] == 0) {
                if (r1[0] < r2[0]) return -1;
                if (r1[0] > r2[0]) return 1;
                return 0;
            }
            // Overflow: fall back to float
        }
    }
    // Exact bignum vs inexact flonum: check if bignum is exactly representable
    if (types.isBignum(a) and types.isFlonum(b)) {
        const fb = types.toFlonum(b);
        if (!std.math.isFinite(fb)) {
            if (std.math.isNan(fb)) return 1;
            return if (fb > 0) @as(i8, -1) else @as(i8, 1);
        }
        const fa = bignum_mod.toF64(a);
        if (fa < fb) return -1;
        if (fa > fb) return 1;
        // Same f64 value — check if bignum is exactly representable
        // Convert f64 → bignum → f64 round-trip to detect precision loss
        if (fb == @trunc(fb) and @abs(fb) < 4.5e18) {
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            const b_exact = gc.allocBignumFromI64(@intFromFloat(fb)) catch return PrimitiveError.OutOfMemory;
            return bignum_mod.compare(a, b_exact);
        }
        // For very large integer floats: convert float to exact bignum and compare
        if (fb == @trunc(fb)) {
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            const bits: u64 = @bitCast(fb);
            const biased_exp = @as(i64, @intCast((bits >> 52) & 0x7FF));
            const mantissa_bits = bits & 0x000FFFFFFFFFFFFF;
            const exp = biased_exp - 1023 - 52;
            const mantissa: i64 = @intCast(mantissa_bits | 0x0010000000000000);
            if (exp >= 0) {
                var exact = gc.allocBignumFromI64(mantissa) catch return PrimitiveError.OutOfMemory;
                const two = types.makeFixnum(2);
                const shift = types.makeFixnum(exp);
                const scale = bignum_mod.expt(gc, two, shift) catch return PrimitiveError.OutOfMemory;
                exact = bignum_mod.mul(gc, exact, scale) catch return PrimitiveError.OutOfMemory;
                if (fb < 0) exact = bignum_mod.negate(gc, exact) catch return PrimitiveError.OutOfMemory;
                return bignum_mod.compare(a, exact);
            }
        }
        return 0;
    }
    if (types.isFlonum(a) and types.isBignum(b)) {
        const result = try cmpPair(b, a);
        return -result;
    }
    // Exact fixnum vs inexact flonum: convert float to exact if integer-valued
    if (types.isFixnum(a) and types.isFlonum(b)) {
        const fb = types.toFlonum(b);
        if (!std.math.isFinite(fb)) {
            if (std.math.isNan(fb)) return 1;
            return if (fb > 0) @as(i8, -1) else @as(i8, 1);
        }
        if (fb == @trunc(fb) and @abs(fb) < 4.5e18) {
            const ib: i64 = @intFromFloat(fb);
            const ia = types.toFixnum(a);
            if (ia < ib) return -1;
            if (ia > ib) return 1;
            return 0;
        }
        // Float is non-integer, can't equal an integer
        const ia_f: f64 = @floatFromInt(types.toFixnum(a));
        if (ia_f < fb) return -1;
        return 1;
    }
    if (types.isFlonum(a) and types.isFixnum(b)) {
        const fa = types.toFlonum(a);
        if (!std.math.isFinite(fa)) {
            if (std.math.isNan(fa)) return -1;
            return if (fa > 0) @as(i8, 1) else @as(i8, -1);
        }
        if (fa == @trunc(fa) and @abs(fa) < 4.5e18) {
            const ia: i64 = @intFromFloat(fa);
            const ib = types.toFixnum(b);
            if (ia < ib) return -1;
            if (ia > ib) return 1;
            return 0;
        }
        const ib_f: f64 = @floatFromInt(types.toFixnum(b));
        if (fa < ib_f) return -1;
        return 1;
    }
    // Fall back to float
    const fa = try toF64Ext(a);
    const fb = try toF64Ext(b);
    if (fa < fb) return -1;
    if (fa > fb) return 1;
    return 0;
}

fn numEq(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (hasNaN(args[i]) or hasNaN(args[i + 1])) return types.FALSE;
        const a = args[i];
        const b = args[i + 1];
        if (types.isComplex(a) or types.isComplex(b)) {
            const ca = try toComplexParts(a);
            const cb = try toComplexParts(b);
            if (ca.real != cb.real or ca.imag != cb.imag) return types.FALSE;
        } else {
            if ((try cmpPair(a, b)) != 0) return types.FALSE;
        }
    }
    return types.TRUE;
}

fn hasNaN(v: Value) bool {
    if (types.isFlonum(v)) return std.math.isNan(types.toFlonum(v));
    if (types.isComplex(v)) {
        const c = types.toComplex(v);
        return std.math.isNan(c.real) or std.math.isNan(c.imag);
    }
    return false;
}

fn numLt(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (hasNaN(args[i]) or hasNaN(args[i + 1])) return types.FALSE;
        if ((try cmpPair(args[i], args[i + 1])) >= 0) return types.FALSE;
    }
    return types.TRUE;
}

fn numGt(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (hasNaN(args[i]) or hasNaN(args[i + 1])) return types.FALSE;
        if ((try cmpPair(args[i], args[i + 1])) <= 0) return types.FALSE;
    }
    return types.TRUE;
}

fn numLe(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (hasNaN(args[i]) or hasNaN(args[i + 1])) return types.FALSE;
        if ((try cmpPair(args[i], args[i + 1])) > 0) return types.FALSE;
    }
    return types.TRUE;
}

fn numGe(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (hasNaN(args[i]) or hasNaN(args[i + 1])) return types.FALSE;
        if ((try cmpPair(args[i], args[i + 1])) < 0) return types.FALSE;
    }
    return types.TRUE;
}

fn zeroP(args: []const Value) PrimitiveError!Value {
    if (types.isBignum(args[0])) return if (bignum_mod.isZero(args[0])) types.TRUE else types.FALSE;
    if (types.isRationalObj(args[0])) return types.FALSE;
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return if (c.real == 0 and c.imag == 0) types.TRUE else types.FALSE;
    }
    const v = try toF64(args[0]);
    return if (v == 0) types.TRUE else types.FALSE;
}

fn positiveP(args: []const Value) PrimitiveError!Value {
    if (types.isBignum(args[0])) return if (bignum_mod.isPositive(args[0])) types.TRUE else types.FALSE;
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        // Denominator always > 0, so sign is determined by numerator
        if (types.isFixnum(r.numerator)) return if (types.toFixnum(r.numerator) > 0) types.TRUE else types.FALSE;
        return types.FALSE;
    }
    const v = try toF64(args[0]);
    return if (v > 0) types.TRUE else types.FALSE;
}

fn negativeP(args: []const Value) PrimitiveError!Value {
    if (types.isBignum(args[0])) return if (bignum_mod.isNegative(args[0])) types.TRUE else types.FALSE;
    if (types.isRationalObj(args[0])) {
        const r = types.toRational(args[0]);
        if (types.isFixnum(r.numerator)) return if (types.toFixnum(r.numerator) < 0) types.TRUE else types.FALSE;
        return types.FALSE;
    }
    const v = try toF64(args[0]);
    return if (v < 0) types.TRUE else types.FALSE;
}

fn absVal(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) {
        const n = types.toFixnum(args[0]);
        if (n == std.math.minInt(i64)) {
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            return bignum_mod.absVal(gc, args[0]) catch return PrimitiveError.OutOfMemory;
        }
        return makeFixnumChecked(if (n < 0) -n else n);
    }
    if (types.isBignum(args[0])) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        return bignum_mod.absVal(gc, args[0]) catch return PrimitiveError.OutOfMemory;
    }
    if (types.isRationalObj(args[0])) {
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        const r = types.toRational(args[0]);
        // Denominator is always positive; just take abs of numerator
        if (types.isFixnum(r.numerator)) {
            const n = types.toFixnum(r.numerator);
            if (n >= 0) return args[0]; // already positive
            return gc.allocRational(types.makeFixnum(-n), r.denominator) catch return PrimitiveError.OutOfMemory;
        }
        return args[0]; // should not happen for fixnum-only rationals
    }
    if (types.isFlonum(args[0])) {
        return makeFlonumVal(@abs(types.toFlonum(args[0])));
    }
    return PrimitiveError.TypeError;
}

fn minVal(args: []const Value) PrimitiveError!Value {
    if (anyFlonum(args)) {
        var result = try toF64Ext(args[0]);
        for (args[1..]) |a| {
            const n = try toF64Ext(a);
            if (n < result) result = n;
        }
        return makeFlonumVal(result);
    }
    if (anyRational(args)) {
        var result_idx: usize = 0;
        for (args[1..], 1..) |_, i| {
            if ((try cmpPair(args[i], args[result_idx])) < 0) result_idx = i;
        }
        return args[result_idx];
    }
    if (anyBignum(args)) {
        var result = args[0];
        for (args[1..]) |a| {
            if (bignum_mod.compare(a, result) < 0) result = a;
        }
        return result;
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
        var result = try toF64Ext(args[0]);
        for (args[1..]) |a| {
            const n = try toF64Ext(a);
            if (n > result) result = n;
        }
        return makeFlonumVal(result);
    }
    if (anyRational(args)) {
        var result_idx: usize = 0;
        for (args[1..], 1..) |_, i| {
            if ((try cmpPair(args[i], args[result_idx])) > 0) result_idx = i;
        }
        return args[result_idx];
    }
    if (anyBignum(args)) {
        var result = args[0];
        for (args[1..]) |a| {
            if (bignum_mod.compare(a, result) > 0) result = a;
        }
        return result;
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
    if (types.isBignum(args[0])) {
        return if (bignum_mod.isEven(args[0])) types.TRUE else types.FALSE;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (f != @trunc(f) or !std.math.isFinite(f))
            return PrimitiveError.TypeError;
        return if (@rem(f, 2.0) == 0.0) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
}

fn oddP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) {
        return if (@rem(types.toFixnum(args[0]), 2) != 0) types.TRUE else types.FALSE;
    }
    if (types.isBignum(args[0])) {
        return if (!bignum_mod.isEven(args[0])) types.TRUE else types.FALSE;
    }
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (f != @trunc(f) or !std.math.isFinite(f))
            return PrimitiveError.TypeError;
        return if (@rem(f, 2.0) != 0.0) types.TRUE else types.FALSE;
    }
    return PrimitiveError.TypeError;
}

fn gcdF64(a_in: f64, b_in: f64) f64 {
    var a = @abs(a_in);
    var b = @abs(b_in);
    while (b > 0.5) {
        const t = b;
        b = @mod(a, b);
        a = t;
    }
    return a;
}

pub fn gcdTwo(a_in: i64, b_in: i64) i64 {
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
    if (anyBignum(args)) {
        // Bignum GCD: use Euclidean algorithm with bignum ops
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        var result = bignum_mod.absVal(gc, args[0]) catch return PrimitiveError.OutOfMemory;
        for (args[1..]) |a| {
            var b_val = bignum_mod.absVal(gc, a) catch return PrimitiveError.OutOfMemory;
            while (!bignum_mod.isZero(b_val)) {
                const t = b_val;
                b_val = bignum_mod.remainder(gc, result, b_val) catch return PrimitiveError.OutOfMemory;
                b_val = bignum_mod.absVal(gc, b_val) catch return PrimitiveError.OutOfMemory;
                result = t;
            }
        }
        return result;
    }
    if (anyFlonum(args)) {
        var result: f64 = @abs(try toF64Ext(args[0]));
        for (args[1..]) |a| {
            const b = @abs(try toF64Ext(a));
            result = gcdF64(result, b);
        }
        return makeFlonumVal(result);
    }
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    var result = types.toFixnum(args[0]);
    if (result < 0) result = -result;
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        result = gcdTwo(result, types.toFixnum(a));
    }
    return try makeFixnumChecked(result);
}

fn lcmFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 0) return types.makeFixnum(1);
    var has_inexact = false;
    for (args) |a| {
        if (types.isFlonum(a)) has_inexact = true;
    }
    if (has_inexact) {
        var result: f64 = @abs(try toF64Ext(args[0]));
        for (args[1..]) |a| {
            const b = @abs(try toF64Ext(a));
            const g = gcdF64(result, b);
            result = if (g == 0) 0 else (result / g) * b;
        }
        return makeFlonumVal(result);
    }
    if (anyBignum(args)) {
        // Bignum LCM: lcm(a,b) = |a*b| / gcd(a,b)
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        var result = bignum_mod.absVal(gc, args[0]) catch return PrimitiveError.OutOfMemory;
        for (args[1..]) |a| {
            const b_abs = bignum_mod.absVal(gc, a) catch return PrimitiveError.OutOfMemory;
            const gcd_args = [_]Value{ result, b_abs };
            const g = try gcdFn(&gcd_args);
            if (bignum_mod.isZero(g)) {
                result = types.makeFixnum(0);
            } else {
                const q = bignum_mod.quotient(gc, result, g) catch return PrimitiveError.OutOfMemory;
                result = bignum_mod.mul(gc, q, b_abs) catch return PrimitiveError.OutOfMemory;
            }
        }
        return result;
    }
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    var result = types.toFixnum(args[0]);
    if (result < 0) result = -result;
    var idx: usize = 1;
    while (idx < args.len) : (idx += 1) {
        if (!types.isFixnum(args[idx])) return PrimitiveError.TypeError;
        const b = types.toFixnum(args[idx]);
        const g = gcdTwo(result, b);
        if (g == 0) {
            result = 0;
        } else {
            const partial = @divExact(result, g);
            const abs_b: i64 = if (b < 0) -b else b;
            const ov = @mulWithOverflow(partial, abs_b);
            if (ov[1] != 0) {
                const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
                var big_result = bignum_mod.mul(gc, try makeFixnumChecked(partial), try makeFixnumChecked(abs_b)) catch return PrimitiveError.OutOfMemory;
                idx += 1;
                while (idx < args.len) : (idx += 1) {
                    const b_abs = bignum_mod.absVal(gc, args[idx]) catch return PrimitiveError.OutOfMemory;
                    const gcd_pair = [_]Value{ big_result, b_abs };
                    const g2 = try gcdFn(&gcd_pair);
                    if (bignum_mod.isZero(g2)) {
                        big_result = types.makeFixnum(0);
                    } else {
                        const q = bignum_mod.quotient(gc, big_result, g2) catch return PrimitiveError.OutOfMemory;
                        big_result = bignum_mod.mul(gc, q, b_abs) catch return PrimitiveError.OutOfMemory;
                    }
                }
                return big_result;
            }
            result = ov[0];
        }
    }
    return try makeFixnumChecked(result);
}
