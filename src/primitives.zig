const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;

pub const PrimitiveError = error{
    TypeError,
    DivisionByZero,
    ArityMismatch,
    OutOfMemory,
    ExceptionRaised,
};

pub fn registerAll(vm: *vm_mod.VM) !void {
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

    // Pairs and lists
    try reg(vm, "cons", &cons, .{ .exact = 2 });
    try reg(vm, "car", &car, .{ .exact = 1 });
    try reg(vm, "cdr", &cdr, .{ .exact = 1 });
    try reg(vm, "set-car!", &setCar, .{ .exact = 2 });
    try reg(vm, "set-cdr!", &setCdr, .{ .exact = 2 });
    try reg(vm, "list", &list, .{ .variadic = 0 });
    try reg(vm, "length", &length, .{ .exact = 1 });
    try reg(vm, "append", &append, .{ .variadic = 0 });
    try reg(vm, "reverse", &reverse, .{ .exact = 1 });

    // Type predicates
    try reg(vm, "pair?", &pairP, .{ .exact = 1 });
    try reg(vm, "null?", &nullP, .{ .exact = 1 });
    try reg(vm, "number?", &numberP, .{ .exact = 1 });
    try reg(vm, "integer?", &integerP, .{ .exact = 1 });
    try reg(vm, "real?", &realP, .{ .exact = 1 });
    try reg(vm, "complex?", &realP, .{ .exact = 1 });
    try reg(vm, "rational?", &rationalP, .{ .exact = 1 });
    try reg(vm, "symbol?", &symbolP, .{ .exact = 1 });
    try reg(vm, "string?", &stringP, .{ .exact = 1 });
    try reg(vm, "boolean?", &booleanP, .{ .exact = 1 });
    try reg(vm, "char?", &charP, .{ .exact = 1 });
    try reg(vm, "procedure?", &procedureP, .{ .exact = 1 });
    try reg(vm, "list?", &listP, .{ .exact = 1 });

    // Equivalence
    try reg(vm, "eq?", &eqP, .{ .exact = 2 });
    try reg(vm, "eqv?", &eqvP, .{ .exact = 2 });
    try reg(vm, "equal?", &equalP, .{ .exact = 2 });

    // Boolean
    try reg(vm, "not", &notFn, .{ .exact = 1 });

    // I/O
    try reg(vm, "display", &display, .{ .exact = 1 });
    try reg(vm, "write", &write, .{ .exact = 1 });
    try reg(vm, "newline", &newline, .{ .exact = 0 });

    // String
    try reg(vm, "number->string", &numberToString, .{ .exact = 1 });
    try reg(vm, "string->number", &stringToNumber, .{ .variadic = 1 });
    try reg(vm, "string-length", &stringLength, .{ .exact = 1 });
    try reg(vm, "string-append", &stringAppend, .{ .variadic = 0 });
    try reg(vm, "symbol->string", &symbolToString, .{ .exact = 1 });

    // Misc
    try reg(vm, "apply", &applyFn, .{ .variadic = 2 });
    try reg(vm, "error", &errorFn, .{ .variadic = 1 });

    // Exception system (R7RS 6.11)
    try reg(vm, "raise", &raiseFn, .{ .exact = 1 });
    try reg(vm, "raise-continuable", &raiseContinuableFn, .{ .exact = 1 });
    try reg(vm, "with-exception-handler", &withExceptionHandlerFn, .{ .exact = 2 });
    try reg(vm, "error-object?", &errorObjectP, .{ .exact = 1 });
    try reg(vm, "error-object-message", &errorObjectMessage, .{ .exact = 1 });
    try reg(vm, "error-object-irritants", &errorObjectIrritants, .{ .exact = 1 });
    try reg(vm, "file-error?", &fileErrorP, .{ .exact = 1 });
    try reg(vm, "read-error?", &readErrorP, .{ .exact = 1 });
}

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    const val = try vm.gc.allocNativeFn(name, func, arity);
    try vm.defineGlobal(name, val);
}

// ---------------------------------------------------------------------------
// Numeric helpers
// ---------------------------------------------------------------------------

fn anyFlonum(args: []const Value) bool {
    for (args) |a| {
        if (types.isFlonum(a)) return true;
    }
    return false;
}

fn toF64(v: Value) PrimitiveError!f64 {
    if (types.isFixnum(v)) return @floatFromInt(types.toFixnum(v));
    if (types.isFlonum(v)) return types.toFlonum(v);
    return PrimitiveError.TypeError;
}

fn makeFlonumVal(f: f64) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocFlonum(f) catch return PrimitiveError.OutOfMemory;
}

fn isNum(v: Value) bool {
    return types.isFixnum(v) or types.isFlonum(v);
}

// ---------------------------------------------------------------------------
// Arithmetic
// ---------------------------------------------------------------------------

fn add(args: []const Value) PrimitiveError!Value {
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
    if (args.len == 1) {
        // (/ z) = 1/z
        const a = try toF64(args[0]);
        if (a == 0) return PrimitiveError.DivisionByZero;
        return makeFlonumVal(1.0 / a);
    }
    // All fixnums — try exact division
    if (!anyFlonum(args)) {
        var result = types.toFixnum(args[0]);
        for (args[1..]) |a| {
            if (!types.isFixnum(a)) return PrimitiveError.TypeError;
            const b = types.toFixnum(a);
            if (b == 0) return PrimitiveError.DivisionByZero;
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
        if (b == 0) return PrimitiveError.DivisionByZero;
        result /= b;
    }
    return makeFlonumVal(result);
}

fn quotient(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return PrimitiveError.DivisionByZero;
    return types.makeFixnum(@divTrunc(types.toFixnum(args[0]), b));
}

fn remainder(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return PrimitiveError.DivisionByZero;
    return types.makeFixnum(@rem(types.toFixnum(args[0]), b));
}

fn modulo(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0]) or !types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const b = types.toFixnum(args[1]);
    if (b == 0) return PrimitiveError.DivisionByZero;
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
// Pairs and lists
// ---------------------------------------------------------------------------

var gc_instance: ?*@import("memory.zig").GC = null;

pub fn setGCInstance(gc: *@import("memory.zig").GC) void {
    gc_instance = gc;
}

fn cons(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPair(args[0], args[1]) catch return PrimitiveError.OutOfMemory;
}

fn car(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    return types.car(args[0]);
}

fn cdr(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    return types.cdr(args[0]);
}

fn setCar(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    types.setCar(args[0], args[1]);
    return types.VOID;
}

fn setCdr(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    types.setCdr(args[0], args[1]);
    return types.VOID;
}

fn list(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.makeList(args) catch return PrimitiveError.OutOfMemory;
}

fn length(args: []const Value) PrimitiveError!Value {
    var count: i64 = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        count += 1;
        current = types.cdr(current);
    }
    return types.makeFixnum(count);
}

fn append(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 0) return types.NIL;
    if (args.len == 1) return args[0];

    var result = args[args.len - 1];
    var i = args.len - 1;
    while (i > 0) {
        i -= 1;
        var lst = args[i];
        // Collect elements of this list
        var elems: std.ArrayList(Value) = .empty;
        defer elems.deinit(gc.allocator);
        while (lst != types.NIL) {
            if (!types.isPair(lst)) return PrimitiveError.TypeError;
            elems.append(gc.allocator, types.car(lst)) catch return PrimitiveError.OutOfMemory;
            lst = types.cdr(lst);
        }
        var j = elems.items.len;
        while (j > 0) {
            j -= 1;
            result = gc.allocPair(elems.items[j], result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

fn reverse(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    var result: Value = types.NIL;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        result = gc.allocPair(types.car(current), result) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Type predicates
// ---------------------------------------------------------------------------

fn pairP(args: []const Value) PrimitiveError!Value {
    return if (types.isPair(args[0])) types.TRUE else types.FALSE;
}

fn nullP(args: []const Value) PrimitiveError!Value {
    return if (types.isNil(args[0])) types.TRUE else types.FALSE;
}

fn numberP(args: []const Value) PrimitiveError!Value {
    return if (types.isNumber(args[0])) types.TRUE else types.FALSE;
}

fn integerP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return types.TRUE;
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (std.math.isNan(f) or std.math.isInf(f)) return types.FALSE;
        return if (f == @trunc(f)) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn realP(args: []const Value) PrimitiveError!Value {
    return if (types.isNumber(args[0])) types.TRUE else types.FALSE;
}

fn rationalP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0])) return types.TRUE;
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        return if (std.math.isFinite(f)) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn symbolP(args: []const Value) PrimitiveError!Value {
    return if (types.isSymbol(args[0])) types.TRUE else types.FALSE;
}

fn stringP(args: []const Value) PrimitiveError!Value {
    return if (types.isString(args[0])) types.TRUE else types.FALSE;
}

fn booleanP(args: []const Value) PrimitiveError!Value {
    return if (types.isBool(args[0])) types.TRUE else types.FALSE;
}

fn charP(args: []const Value) PrimitiveError!Value {
    return if (types.isChar(args[0])) types.TRUE else types.FALSE;
}

fn procedureP(args: []const Value) PrimitiveError!Value {
    return if (types.isProcedure(args[0])) types.TRUE else types.FALSE;
}

fn listP(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return types.FALSE;
        current = types.cdr(current);
    }
    return types.TRUE;
}

// ---------------------------------------------------------------------------
// Equivalence
// ---------------------------------------------------------------------------

fn eqP(args: []const Value) PrimitiveError!Value {
    return if (args[0] == args[1]) types.TRUE else types.FALSE;
}

fn eqvP(args: []const Value) PrimitiveError!Value {
    if (args[0] == args[1]) return types.TRUE;
    // Two flonums are eqv? if they have the same bits (handles NaN correctly)
    if (types.isFlonum(args[0]) and types.isFlonum(args[1])) {
        const a: u64 = @bitCast(types.toFlonum(args[0]));
        const b: u64 = @bitCast(types.toFlonum(args[1]));
        return if (a == b) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn equalP(args: []const Value) PrimitiveError!Value {
    return if (deepEqual(args[0], args[1])) types.TRUE else types.FALSE;
}

fn deepEqual(a: Value, b: Value) bool {
    if (a == b) return true;
    if (types.isFlonum(a) and types.isFlonum(b)) {
        const fa: u64 = @bitCast(types.toFlonum(a));
        const fb: u64 = @bitCast(types.toFlonum(b));
        return fa == fb;
    }
    if (types.isPair(a) and types.isPair(b)) {
        return deepEqual(types.car(a), types.car(b)) and
            deepEqual(types.cdr(a), types.cdr(b));
    }
    if (types.isString(a) and types.isString(b)) {
        const sa = types.toObject(a).as(types.SchemeString);
        const sb = types.toObject(b).as(types.SchemeString);
        return std.mem.eql(u8, sa.data, sb.data);
    }
    return false;
}

// ---------------------------------------------------------------------------
// Boolean
// ---------------------------------------------------------------------------

fn notFn(args: []const Value) PrimitiveError!Value {
    return if (!types.isTruthy(args[0])) types.TRUE else types.FALSE;
}

// ---------------------------------------------------------------------------
// I/O (uses stdout for now; will use ports later)
// ---------------------------------------------------------------------------

const printer = @import("printer.zig");

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        const written: usize = @intCast(result);
        if (written == 0) break;
        total += written;
    }
}

fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

fn display(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const s = printer.valueToString(gc.allocator, args[0], .display) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeStdout(s);
    return types.VOID;
}

fn write(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeStdout(s);
    return types.VOID;
}

fn newline(args: []const Value) PrimitiveError!Value {
    _ = args;
    writeStdout("\n");
    return types.VOID;
}

// ---------------------------------------------------------------------------
// String
// ---------------------------------------------------------------------------

fn numberToString(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
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

fn stringToNumber(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
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

fn stringLength(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const str = types.toObject(args[0]).as(types.SchemeString);
    return types.makeFixnum(@intCast(str.len));
}

fn stringAppend(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    var total_len: usize = 0;
    for (args) |a| {
        if (!types.isString(a)) return PrimitiveError.TypeError;
        total_len += types.toObject(a).as(types.SchemeString).len;
    }
    var result = gc.allocator.alloc(u8, total_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(result);
    var pos: usize = 0;
    for (args) |a| {
        const str = types.toObject(a).as(types.SchemeString);
        @memcpy(result[pos .. pos + str.len], str.data);
        pos += str.len;
    }
    return gc.allocString(result) catch return PrimitiveError.OutOfMemory;
}

fn symbolToString(args: []const Value) PrimitiveError!Value {
    if (!types.isSymbol(args[0])) return PrimitiveError.TypeError;
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.symbolName(args[0])) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

fn applyFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    // TODO: needs VM access for proper implementation
    return PrimitiveError.TypeError;
}

// ---------------------------------------------------------------------------
// Exception system (R7RS 6.11)
// ---------------------------------------------------------------------------

fn raiseFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse {
        // No VM — print error and abort
        const gc = gc_instance orelse return PrimitiveError.TypeError;
        writeStderr("Error: unhandled exception: ");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.TypeError;
        defer gc.allocator.free(s);
        writeStderr(s);
        writeStderr("\n");
        return PrimitiveError.TypeError;
    };
    vm.current_exception = args[0];
    return PrimitiveError.ExceptionRaised;
}

fn raiseContinuableFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse {
        const gc = gc_instance orelse return PrimitiveError.TypeError;
        writeStderr("Error: unhandled exception: ");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.TypeError;
        defer gc.allocator.free(s);
        writeStderr(s);
        writeStderr("\n");
        return PrimitiveError.TypeError;
    };
    vm.current_exception = args[0];
    return PrimitiveError.ExceptionRaised;
}

fn withExceptionHandlerFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const handler = args[0];
    const thunk = args[1];

    if (!types.isProcedure(handler)) return PrimitiveError.TypeError;
    if (!types.isProcedure(thunk)) return PrimitiveError.TypeError;

    // Push the handler onto the handler stack
    vm.pushHandler(handler) catch return PrimitiveError.OutOfMemory;

    // Call the thunk
    const result = vm.callThunk(thunk) catch |err| {
        if (err == vm_mod.VMError.ExceptionRaised) {
            // An exception was raised during the thunk.
            // Pop our handler and call it with the exception.
            vm.popHandler();
            const exc = vm.current_exception orelse types.FALSE;
            vm.current_exception = null;
            const handler_result = vm.callHandler(handler, exc) catch |herr| {
                return switch (herr) {
                    vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                    vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                    else => PrimitiveError.TypeError,
                };
            };
            return handler_result;
        }
        vm.popHandler();
        return switch (err) {
            vm_mod.VMError.TypeError => PrimitiveError.TypeError,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            vm_mod.VMError.DivisionByZero => PrimitiveError.DivisionByZero,
            else => PrimitiveError.TypeError,
        };
    };

    // Normal return — pop the handler
    vm.popHandler();
    return result;
}

fn errorObjectP(args: []const Value) PrimitiveError!Value {
    return if (types.isErrorObject(args[0])) types.TRUE else types.FALSE;
}

fn errorObjectMessage(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return PrimitiveError.TypeError;
    const err = types.toObject(args[0]).as(types.ErrorObject);
    return err.message;
}

fn errorObjectIrritants(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return PrimitiveError.TypeError;
    const err = types.toObject(args[0]).as(types.ErrorObject);
    return err.irritants;
}

fn fileErrorP(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.FALSE; // No file errors for now
}

fn readErrorP(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.FALSE; // No read errors for now
}

fn errorFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;

    // First arg is the message
    const message = args[0];

    // Build irritants list from remaining args
    var irritants: Value = types.NIL;
    if (args.len > 1) {
        var i = args.len;
        while (i > 1) {
            i -= 1;
            irritants = gc.allocPair(args[i], irritants) catch return PrimitiveError.OutOfMemory;
        }
    }

    // Create the error object
    const err_obj = gc.allocErrorObject(message, irritants) catch return PrimitiveError.OutOfMemory;

    // Raise it through the exception system
    const raise_args = [1]Value{err_obj};
    return raiseFn(&raise_args);
}
