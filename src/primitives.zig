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
};

pub fn registerAll(vm: *vm_mod.VM) !void {
    // Arithmetic
    try reg(vm, "+", &add, .{ .variadic = 0 });
    try reg(vm, "-", &sub, .{ .variadic = 1 });
    try reg(vm, "*", &mul, .{ .variadic = 0 });
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
    try reg(vm, "string-length", &stringLength, .{ .exact = 1 });
    try reg(vm, "string-append", &stringAppend, .{ .variadic = 0 });
    try reg(vm, "symbol->string", &symbolToString, .{ .exact = 1 });

    // Misc
    try reg(vm, "apply", &applyFn, .{ .variadic = 2 });
    try reg(vm, "error", &errorFn, .{ .variadic = 1 });
}

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    const val = try vm.gc.allocNativeFn(name, func, arity);
    try vm.defineGlobal(name, val);
}

// ---------------------------------------------------------------------------
// Arithmetic
// ---------------------------------------------------------------------------

fn add(args: []const Value) PrimitiveError!Value {
    var sum: i64 = 0;
    for (args) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        sum += types.toFixnum(a);
    }
    return types.makeFixnum(sum);
}

fn sub(args: []const Value) PrimitiveError!Value {
    if (args.len == 0) return PrimitiveError.ArityMismatch;
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
    var product: i64 = 1;
    for (args) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        product *= types.toFixnum(a);
    }
    return types.makeFixnum(product);
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
    for (args[1..]) |a| {
        if (!types.isFixnum(args[0]) or !types.isFixnum(a)) return PrimitiveError.TypeError;
        if (types.toFixnum(args[0]) != types.toFixnum(a)) return types.FALSE;
    }
    return types.TRUE;
}

fn numLt(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isFixnum(args[i]) or !types.isFixnum(args[i + 1])) return PrimitiveError.TypeError;
        if (types.toFixnum(args[i]) >= types.toFixnum(args[i + 1])) return types.FALSE;
    }
    return types.TRUE;
}

fn numGt(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isFixnum(args[i]) or !types.isFixnum(args[i + 1])) return PrimitiveError.TypeError;
        if (types.toFixnum(args[i]) <= types.toFixnum(args[i + 1])) return types.FALSE;
    }
    return types.TRUE;
}

fn numLe(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isFixnum(args[i]) or !types.isFixnum(args[i + 1])) return PrimitiveError.TypeError;
        if (types.toFixnum(args[i]) > types.toFixnum(args[i + 1])) return types.FALSE;
    }
    return types.TRUE;
}

fn numGe(args: []const Value) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isFixnum(args[i]) or !types.isFixnum(args[i + 1])) return PrimitiveError.TypeError;
        if (types.toFixnum(args[i]) < types.toFixnum(args[i + 1])) return types.FALSE;
    }
    return types.TRUE;
}

fn zeroP(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    return if (types.toFixnum(args[0]) == 0) types.TRUE else types.FALSE;
}

fn positiveP(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    return if (types.toFixnum(args[0]) > 0) types.TRUE else types.FALSE;
}

fn negativeP(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    return if (types.toFixnum(args[0]) < 0) types.TRUE else types.FALSE;
}

fn absVal(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const n = types.toFixnum(args[0]);
    return types.makeFixnum(if (n < 0) -n else n);
}

fn minVal(args: []const Value) PrimitiveError!Value {
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
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    var result = types.toFixnum(args[0]);
    for (args[1..]) |a| {
        if (!types.isFixnum(a)) return PrimitiveError.TypeError;
        const n = types.toFixnum(a);
        if (n > result) result = n;
    }
    return types.makeFixnum(result);
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
    return if (types.isFixnum(args[0])) types.TRUE else types.FALSE;
}

fn integerP(args: []const Value) PrimitiveError!Value {
    return if (types.isFixnum(args[0])) types.TRUE else types.FALSE;
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
    return eqP(args);
}

fn equalP(args: []const Value) PrimitiveError!Value {
    return if (deepEqual(args[0], args[1])) types.TRUE else types.FALSE;
}

fn deepEqual(a: Value, b: Value) bool {
    if (a == b) return true;
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
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(args[0])}) catch return PrimitiveError.OutOfMemory;
    return gc.allocString(s) catch return PrimitiveError.OutOfMemory;
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

fn errorFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    writeStderr("Error: ");
    for (args) |a| {
        const s = printer.valueToString(gc.allocator, a, .display) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(s);
        writeStderr(s);
        writeStderr(" ");
    }
    writeStderr("\n");
    return PrimitiveError.TypeError; // TODO: proper exception system
}
