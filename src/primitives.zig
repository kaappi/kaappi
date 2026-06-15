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
    ContinuationInvoked,
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

    // I/O (with optional port argument)
    try reg(vm, "display", &display, .{ .variadic = 1 });
    try reg(vm, "write", &write, .{ .variadic = 1 });
    try reg(vm, "newline", &newline, .{ .variadic = 0 });

    // Port procedures
    try reg(vm, "current-input-port", &currentInputPort, .{ .exact = 0 });
    try reg(vm, "current-output-port", &currentOutputPort, .{ .exact = 0 });
    try reg(vm, "current-error-port", &currentErrorPort, .{ .exact = 0 });
    try reg(vm, "port?", &portP, .{ .exact = 1 });
    try reg(vm, "input-port?", &inputPortP, .{ .exact = 1 });
    try reg(vm, "output-port?", &outputPortP, .{ .exact = 1 });
    try reg(vm, "textual-port?", &textualPortP, .{ .exact = 1 });
    try reg(vm, "binary-port?", &binaryPortP, .{ .exact = 1 });
    try reg(vm, "input-port-open?", &inputPortOpenP, .{ .exact = 1 });
    try reg(vm, "output-port-open?", &outputPortOpenP, .{ .exact = 1 });
    try reg(vm, "open-input-file", &openInputFile, .{ .exact = 1 });
    try reg(vm, "open-output-file", &openOutputFile, .{ .exact = 1 });
    try reg(vm, "close-port", &closePort, .{ .exact = 1 });
    try reg(vm, "close-input-port", &closePort, .{ .exact = 1 });
    try reg(vm, "close-output-port", &closePort, .{ .exact = 1 });
    try reg(vm, "read-char", &readCharFn, .{ .variadic = 0 });
    try reg(vm, "peek-char", &peekCharFn, .{ .variadic = 0 });
    try reg(vm, "read-line", &readLineFn, .{ .variadic = 0 });
    try reg(vm, "char-ready?", &charReadyP, .{ .variadic = 0 });
    try reg(vm, "write-char", &writeCharFn, .{ .variadic = 1 });
    try reg(vm, "write-string", &writeStringFn, .{ .variadic = 1 });
    try reg(vm, "read", &readDatumFn, .{ .variadic = 0 });
    try reg(vm, "file-exists?", &fileExistsP, .{ .exact = 1 });
    try reg(vm, "eof-object?", &eofObjectP, .{ .exact = 1 });
    try reg(vm, "eof-object", &eofObjectFn, .{ .exact = 0 });

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

    // Record system (R7RS 5.5) — internal primitives
    try reg(vm, "%make-record-type", &makeRecordTypeFn, .{ .exact = 2 });
    try reg(vm, "%make-record", &makeRecordFn, .{ .variadic = 1 });
    try reg(vm, "%record?", &recordCheckFn, .{ .exact = 2 });
    try reg(vm, "%record-ref", &recordRefFn, .{ .exact = 2 });
    try reg(vm, "%record-set!", &recordSetFn, .{ .exact = 3 });

    // Continuations (R7RS 6.10)
    try reg(vm, "call-with-current-continuation", &callWithCurrentContinuation, .{ .exact = 1 });
    try reg(vm, "call/cc", &callWithCurrentContinuation, .{ .exact = 1 });
    try reg(vm, "dynamic-wind", &dynamicWindFn, .{ .exact = 3 });
    try reg(vm, "values", &valuesFn, .{ .variadic = 0 });
    try reg(vm, "call-with-values", &callWithValuesFn, .{ .exact = 2 });
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
// I/O — Port-based (R7RS 6.13)
// ---------------------------------------------------------------------------

const printer = @import("printer.zig");
const reader_mod = @import("reader.zig");

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

/// Get the output port: use args[1] if provided, else current-output-port.
fn getOutputPort(args: []const Value, arg_idx: usize) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return PrimitiveError.TypeError;
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_output) return PrimitiveError.TypeError;
        if (!port.is_open) return PrimitiveError.TypeError;
        return port;
    }
    // Use current-output-port from VM
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    if (!types.isPort(vm.stdout_port)) return PrimitiveError.TypeError;
    return types.toObject(vm.stdout_port).as(types.Port);
}

/// Get the input port: use args[0] if provided, else current-input-port.
fn getInputPort(args: []const Value, arg_idx: usize) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return PrimitiveError.TypeError;
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_input) return PrimitiveError.TypeError;
        if (!port.is_open) return PrimitiveError.TypeError;
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    if (!types.isPort(vm.stdin_port)) return PrimitiveError.TypeError;
    return types.toObject(vm.stdin_port).as(types.Port);
}

fn writeToPort(port: *types.Port, bytes: []const u8) void {
    writeToFd(port.fd, bytes);
}

fn display(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1);
    const s = printer.valueToString(gc.allocator, args[0], .display) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn write(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1);
    const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn newline(args: []const Value) PrimitiveError!Value {
    const port = try getOutputPort(args, 0);
    writeToPort(port, "\n");
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Port procedures (R7RS 6.13)
// ---------------------------------------------------------------------------

fn currentInputPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    return vm.stdin_port;
}

fn currentOutputPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    return vm.stdout_port;
}

fn currentErrorPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    return vm.stderr_port;
}

fn portP(args: []const Value) PrimitiveError!Value {
    return if (types.isPort(args[0])) types.TRUE else types.FALSE;
}

fn inputPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_input) types.TRUE else types.FALSE;
}

fn outputPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_output) types.TRUE else types.FALSE;
}

fn textualPortP(args: []const Value) PrimitiveError!Value {
    // All our ports are textual
    return if (types.isPort(args[0])) types.TRUE else types.FALSE;
}

fn binaryPortP(args: []const Value) PrimitiveError!Value {
    // We don't have binary ports yet
    _ = args;
    return types.FALSE;
}

fn inputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_input and port.is_open) types.TRUE else types.FALSE;
}

fn outputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_output and port.is_open) types.TRUE else types.FALSE;
}

fn openInputFile(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    // We need a null-terminated path for openat
    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch {
        return PrimitiveError.TypeError; // file-error
    };

    // Dup the name for the port
    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, true, false, owned_name, true) catch return PrimitiveError.OutOfMemory;
}

fn openOutputFile(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch {
        return PrimitiveError.TypeError; // file-error
    };

    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, false, true, owned_name, true) catch return PrimitiveError.OutOfMemory;
}

fn closePort(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const port = types.toObject(args[0]).as(types.Port);
    if (port.is_open and port.fd > 2) {
        _ = std.posix.system.close(port.fd);
    }
    port.is_open = false;
    return types.VOID;
}

fn readOneByte(port: *types.Port) ?u8 {
    // Check peek buffer first
    if (port.peek_byte) |b| {
        port.peek_byte = null;
        return b;
    }
    var buf: [1]u8 = undefined;
    const n = std.posix.read(port.fd, &buf) catch return null;
    if (n == 0) return null; // EOF
    return buf[0];
}

fn readCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    const byte = readOneByte(port) orelse return types.EOF;
    return types.makeChar(@intCast(byte));
}

fn peekCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    if (port.peek_byte) |b| {
        return types.makeChar(@intCast(b));
    }
    var buf: [1]u8 = undefined;
    const n = std.posix.read(port.fd, &buf) catch return types.EOF;
    if (n == 0) return types.EOF;
    port.peek_byte = buf[0];
    return types.makeChar(@intCast(buf[0]));
}

fn readLineFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0);

    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(gc.allocator);

    while (true) {
        const byte = readOneByte(port) orelse {
            // EOF
            if (line_buf.items.len == 0) return types.EOF;
            break;
        };
        if (byte == '\n') break;
        if (byte == '\r') {
            // Check for \r\n
            const next = readOneByte(port);
            if (next) |nb| {
                if (nb != '\n') {
                    port.peek_byte = nb; // put it back
                }
            }
            break;
        }
        line_buf.append(gc.allocator, byte) catch return PrimitiveError.OutOfMemory;
    }

    return gc.allocString(line_buf.items) catch return PrimitiveError.OutOfMemory;
}

fn charReadyP(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    if (port.peek_byte != null) return types.TRUE;
    // For simplicity, always return #t (non-blocking check not worth the complexity)
    return types.TRUE;
}

fn writeCharFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const port = try getOutputPort(args, 1);
    const cp = types.toChar(args[0]);
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch return PrimitiveError.TypeError;
    writeToPort(port, buf[0..len]);
    return types.VOID;
}

fn writeStringFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const port = try getOutputPort(args, 1);
    const str = types.toObject(args[0]).as(types.SchemeString);
    writeToPort(port, str.data[0..str.len]);
    return types.VOID;
}

fn readDatumFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0);

    // Read the entire remaining content from the port into a buffer
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gc.allocator);

    // First consume any peeked byte
    if (port.peek_byte) |b| {
        buf.append(gc.allocator, b) catch return PrimitiveError.OutOfMemory;
        port.peek_byte = null;
    }

    // Read all remaining data from the fd
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(port.fd, &tmp) catch break;
        if (n == 0) break;
        buf.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    if (buf.items.len == 0) return types.EOF;

    // Parse one datum from the buffer
    var reader = reader_mod.Reader.init(gc, buf.items);
    defer reader.deinit();
    const datum = reader.readDatum() catch return types.EOF;

    // Any remaining data after the datum stays unconsumed.
    // For file ports, this is fine since read is typically used to
    // parse the entire file content sequentially.
    return datum;
}

fn fileExistsP(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    // Try to open the file read-only to check existence
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch {
        return types.FALSE;
    };
    _ = std.posix.system.close(fd);
    return types.TRUE;
}

fn eofObjectP(args: []const Value) PrimitiveError!Value {
    return if (args[0] == types.EOF) types.TRUE else types.FALSE;
}

fn eofObjectFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.EOF;
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
        if (err == vm_mod.VMError.ContinuationInvoked) {
            return PrimitiveError.ContinuationInvoked;
        }
        if (err == vm_mod.VMError.ExceptionRaised) {
            // An exception was raised during the thunk.
            // Pop our handler and call it with the exception.
            vm.popHandler();
            const exc = vm.current_exception orelse types.FALSE;
            vm.current_exception = null;
            const handler_result = vm.callHandler(handler, exc) catch |herr| {
                return switch (herr) {
                    vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
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

// ---------------------------------------------------------------------------
// Record system (R7RS 5.5) — internal primitives
// ---------------------------------------------------------------------------

fn makeRecordTypeFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    // args[0] = name (string), args[1] = num_fields (fixnum)
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const num_fields: u8 = @intCast(types.toFixnum(args[1]));
    return gc.allocRecordType(str.data[0..str.len], num_fields) catch return PrimitiveError.OutOfMemory;
}

fn makeRecordFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    // args[0] = record_type, args[1..] = field values
    if (!types.isRecordType(args[0])) return PrimitiveError.TypeError;
    const rt = types.toObject(args[0]).as(types.RecordType);
    return gc.allocRecordInstance(rt, args[1..]) catch return PrimitiveError.OutOfMemory;
}

fn recordCheckFn(args: []const Value) PrimitiveError!Value {
    // args[0] = value to check, args[1] = record_type
    if (!types.isRecordType(args[1])) return PrimitiveError.TypeError;
    const rt = types.toObject(args[1]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return types.FALSE;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    return if (ri.record_type == rt) types.TRUE else types.FALSE;
}

fn recordRefFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum)
    if (!types.isRecordInstance(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    const idx: usize = @intCast(types.toFixnum(args[1]));
    if (idx >= ri.fields.len) return PrimitiveError.TypeError;
    return ri.fields[idx];
}

fn recordSetFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum), args[2] = new value
    if (!types.isRecordInstance(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    const idx: usize = @intCast(types.toFixnum(args[1]));
    if (idx >= ri.fields.len) return PrimitiveError.TypeError;
    ri.fields[idx] = args[2];
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Continuations (R7RS 6.10)
// ---------------------------------------------------------------------------

fn callWithCurrentContinuation(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const proc = args[0];
    if (!types.isProcedure(proc)) return PrimitiveError.TypeError;

    // Determine where the result of call/cc should be stored.
    // The native function's result is stored by callValue at registers[base],
    // where base is the absolute register of the call instruction's base_reg.
    // We need to capture the continuation such that when invoked, it places
    // the value at the correct register. Since the native function returns
    // a value that gets stored at base by callValue, the continuation
    // should mimic this: restore state and place value at the same spot.
    //
    // The calling frame is frames[frame_count - 1]. The call instruction
    // that invoked call/cc used base_reg, which callValue received as the
    // absolute base. We don't have direct access to base here, but we can
    // compute it: the caller's frame ip has already advanced past the call
    // instruction. We need to use the caller's context.
    //
    // A simpler approach: capture the continuation with the current state.
    // The caller's frame has ip pointing past the call instruction, so when
    // the continuation is restored, execution will resume right after the call.
    // We just need to know where the result goes.
    //
    // In the calling convention, for a native fn, callValue stores the result
    // at registers[base]. We need to communicate this to the continuation.
    // Since we don't have base in the native fn, we'll use a different strategy:
    // store the frame count and use dst from the calling frame.
    //
    // When a native function returns a value from a .call opcode, the result
    // is stored at registers[base] where base = frame.base + base_reg.
    // The continuation captures the current state. When invoked, it should
    // place the value where callValue would have stored it.
    //
    // For the callWithCC approach in the VM, we rely on the VM method.

    // The caller frame's base_reg determines where the result goes.
    // We need to look at the instruction that called us. The ip has advanced
    // past the call instruction (call base_reg nargs = 3 bytes).
    // So ip - 2 gives us the position of nargs, ip - 3 gives base_reg.
    const caller = &vm.frames[vm.frame_count - 1];
    const call_ip = caller.ip;
    // The call opcode is: [opcode:1][base_reg:1][nargs:1]
    // So caller.ip points past nargs, and base_reg is at caller.ip - 2
    const base_reg = caller.code[call_ip - 2];
    const abs_base = caller.base + base_reg;

    // Capture continuation. When invoked, it will place the value at abs_base.
    const cont = vm.captureContinuation(@intCast(base_reg), caller.base) catch return PrimitiveError.OutOfMemory;

    // Root the continuation so it survives GC during the proc call
    var cont_val = cont;
    vm.gc.pushRoot(&cont_val);

    // Call proc(continuation)
    const result = vm.callHandler(proc, cont_val) catch |err| {
        vm.gc.popRoot();
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            vm_mod.VMError.ArityMismatch => PrimitiveError.TypeError,
            else => PrimitiveError.TypeError,
        };
    };

    vm.gc.popRoot();

    // If proc returned normally (without invoking the continuation),
    // store the result where call/cc's result goes.
    // callValue will store this in registers[base], which is registers[abs_base].
    _ = abs_base;
    return result;
}

fn dynamicWindFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const before = args[0];
    const thunk = args[1];
    const after = args[2];

    if (!types.isProcedure(before)) return PrimitiveError.TypeError;
    if (!types.isProcedure(thunk)) return PrimitiveError.TypeError;
    if (!types.isProcedure(after)) return PrimitiveError.TypeError;

    // Call before thunk
    _ = vm.callThunk(before) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    // Push wind record
    if (vm.wind_count >= 64) return PrimitiveError.OutOfMemory;
    vm.wind_stack[vm.wind_count] = .{ .before = before, .after = after };
    vm.wind_count += 1;

    // Call thunk
    const result = vm.callThunk(thunk) catch |err| {
        // If continuation was invoked, the wind stack has been replaced
        // so we shouldn't try to pop/call after
        if (err == vm_mod.VMError.ContinuationInvoked) return PrimitiveError.ContinuationInvoked;

        // On other errors, pop wind record and call after
        vm.wind_count -= 1;
        _ = vm.callThunk(after) catch {};
        return switch (err) {
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    // Pop wind record
    vm.wind_count -= 1;

    // Call after thunk
    _ = vm.callThunk(after) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    return result;
}

fn valuesFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 1) return args[0];
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocMultipleValues(args) catch return PrimitiveError.OutOfMemory;
}

fn callWithValuesFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const producer = args[0];
    const consumer = args[1];

    if (!types.isProcedure(producer)) return PrimitiveError.TypeError;
    if (!types.isProcedure(consumer)) return PrimitiveError.TypeError;

    // Call producer
    const produced = vm.callThunk(producer) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    // Call consumer with the produced values
    if (types.isMultipleValues(produced)) {
        const mv = types.toObject(produced).as(types.MultipleValues);
        const result = vm.callWithArgs(consumer, mv.values) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        return result;
    } else {
        // Single value — call consumer with one argument
        const result = vm.callHandler(consumer, produced) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        return result;
    }
}
