const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;

// Extracted modules
const primitives_arithmetic = @import("primitives_arithmetic.zig");
const primitives_io = @import("primitives_io.zig");
const primitives_control = @import("primitives_control.zig");

pub const PrimitiveError = error{
    TypeError,
    DivisionByZero,
    ArityMismatch,
    OutOfMemory,
    ExceptionRaised,
    ContinuationInvoked,
};

pub fn registerAll(vm: *vm_mod.VM) !void {
    // Delegate to extracted modules
    try primitives_arithmetic.registerArithmetic(vm);
    try primitives_io.registerIO(vm);
    try primitives_control.registerControl(vm);

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
    try reg(vm, "complex?", &complexP, .{ .exact = 1 });
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

    // String
    try reg(vm, "string-length", &stringLength, .{ .exact = 1 });
    try reg(vm, "string-append", &stringAppend, .{ .variadic = 0 });
    try reg(vm, "symbol->string", &symbolToString, .{ .exact = 1 });

    // Record system (R7RS 5.5) -- internal primitives
    try reg(vm, "%make-record-type", &makeRecordTypeFn, .{ .exact = 2 });
    try reg(vm, "%make-record", &makeRecordFn, .{ .variadic = 1 });
    try reg(vm, "%record?", &recordCheckFn, .{ .exact = 2 });
    try reg(vm, "%record-ref", &recordRefFn, .{ .exact = 2 });
    try reg(vm, "%record-set!", &recordSetFn, .{ .exact = 3 });

    // Misc
    try reg(vm, "apply", &applyFn, .{ .variadic = 2 });
}

pub fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    const val = try vm.gc.allocNativeFn(name, func, arity);
    try vm.defineGlobal(name, val);
}

// ---------------------------------------------------------------------------
// Numeric helpers (pub for use by extracted modules)
// ---------------------------------------------------------------------------

pub fn anyFlonum(args: []const Value) bool {
    for (args) |a| {
        if (types.isFlonum(a)) return true;
    }
    return false;
}

pub fn toF64(v: Value) PrimitiveError!f64 {
    if (types.isFixnum(v)) return @floatFromInt(types.toFixnum(v));
    if (types.isFlonum(v)) return types.toFlonum(v);
    return PrimitiveError.TypeError;
}

pub fn makeFlonumVal(f: f64) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocFlonum(f) catch return PrimitiveError.OutOfMemory;
}

pub fn isNum(v: Value) bool {
    return types.isFixnum(v) or types.isFlonum(v);
}

// ---------------------------------------------------------------------------
// GC / VM instances (pub for use by extracted modules)
// ---------------------------------------------------------------------------

pub var gc_instance: ?*@import("memory.zig").GC = null;

pub fn setGCInstance(gc: *@import("memory.zig").GC) void {
    gc_instance = gc;
}

// ---------------------------------------------------------------------------
// Pairs and lists
// ---------------------------------------------------------------------------

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

fn complexP(args: []const Value) PrimitiveError!Value {
    return if (types.isNumber(args[0])) types.TRUE else types.FALSE;
}

fn realP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0]) or types.isFlonum(args[0])) types.TRUE else types.FALSE;
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
// String
// ---------------------------------------------------------------------------

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
    const vm = @import("vm.zig").vm_instance orelse return PrimitiveError.TypeError;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    // Collect all arguments: args[1..n-1] are individual, args[n-1] is a list
    var call_args: [256]Value = undefined;
    var count: usize = 0;

    // Individual args (everything between proc and the final list)
    for (args[1 .. args.len - 1]) |a| {
        if (count >= 256) return PrimitiveError.OutOfMemory;
        call_args[count] = a;
        count += 1;
    }

    // Flatten the last arg (must be a proper list)
    var rest = args[args.len - 1];
    while (rest != types.NIL) {
        if (!types.isPair(rest)) return PrimitiveError.TypeError;
        if (count >= 256) return PrimitiveError.OutOfMemory;
        call_args[count] = types.car(rest);
        count += 1;
        rest = types.cdr(rest);
    }

    return vm.callWithArgs(proc, call_args[0..count]) catch |err| {
        return switch (err) {
            @import("vm.zig").VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            @import("vm.zig").VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            @import("vm.zig").VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };
}

// ---------------------------------------------------------------------------
// Record system (R7RS 5.5) -- internal primitives
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
