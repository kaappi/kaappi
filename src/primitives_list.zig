const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
fn getGC() ?*@import("memory.zig").GC {
    return primitives.gc_instance;
}
const deepEqual = primitives.deepEqual;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerList(vm: *vm_mod.VM) !void {
    try reg(vm, "list-ref", &listRefFn, .{ .exact = 2 });
    try reg(vm, "list-tail", &listTailFn, .{ .exact = 2 });
    try reg(vm, "list-set!", &listSetFn, .{ .exact = 3 });
    try reg(vm, "list-copy", &listCopyFn, .{ .exact = 1 });
    try reg(vm, "make-list", &makeListFn, .{ .variadic = 1 });
    try reg(vm, "member", &memberFn, .{ .exact = 2 });
    try reg(vm, "memq", &memqFn, .{ .exact = 2 });
    try reg(vm, "memv", &memvFn, .{ .exact = 2 });
    try reg(vm, "assoc", &assocFn, .{ .exact = 2 });
    try reg(vm, "assq", &assqFn, .{ .exact = 2 });
    try reg(vm, "assv", &assvFn, .{ .exact = 2 });
    try reg(vm, "map", &mapFn, .{ .variadic = 2 });
    try reg(vm, "for-each", &forEachFn, .{ .variadic = 2 });
    try reg(vm, "boolean=?", &booleanEqP, .{ .variadic = 2 });
    try reg(vm, "symbol=?", &symbolEqP, .{ .variadic = 2 });
    try reg(vm, "features", &featuresFn, .{ .exact = 0 });
    try reg(vm, "string->symbol", &stringToSymbol, .{ .exact = 1 });
}
// List utilities
// ---------------------------------------------------------------------------

fn listRefFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0) return PrimitiveError.TypeError;
    var idx: i64 = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        if (idx == k) return types.car(current);
        idx += 1;
        current = types.cdr(current);
    }
    return PrimitiveError.TypeError; // index out of bounds
}

fn listTailFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0) return PrimitiveError.TypeError;
    var idx: i64 = 0;
    var current = args[0];
    while (idx < k) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        current = types.cdr(current);
        idx += 1;
    }
    return current;
}

fn listSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0) return PrimitiveError.TypeError;
    var idx: i64 = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        if (idx == k) {
            types.setCar(current, args[2]);
            return types.VOID;
        }
        idx += 1;
        current = types.cdr(current);
    }
    return PrimitiveError.TypeError; // index out of bounds
}

fn listCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    var current = args[0];
    if (current == types.NIL) return types.NIL;
    if (!types.isPair(current)) return current; // atoms are returned as-is

    // Collect elements
    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    while (current != types.NIL) {
        if (!types.isPair(current)) {
            // improper list: append the tail
            break;
        }
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }
    // Build the copy from the end
    var result: Value = current; // NIL for proper, last cdr for improper
    var i = elems.items.len;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(elems.items[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn makeListFn(args: []const Value) PrimitiveError!Value {
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[0]);
    if (k < 0) return PrimitiveError.TypeError;
    const fill: Value = if (args.len > 1) args[1] else types.UNDEFINED;
    var result: Value = types.NIL;
    var i: i64 = 0;
    while (i < k) : (i += 1) {
        result = gc.allocPair(fill, result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn memberFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        if (deepEqual(args[0], types.car(current))) return current;
        current = types.cdr(current);
    }
    return types.FALSE;
}

fn memqFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        if (args[0] == types.car(current)) return current;
        current = types.cdr(current);
    }
    return types.FALSE;
}

fn memvFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        if (args[0] == elem) return current;
        // eqv? also checks flonum bit-equality
        if (types.isFlonum(args[0]) and types.isFlonum(elem)) {
            const a: u64 = @bitCast(types.toFlonum(args[0]));
            const b: u64 = @bitCast(types.toFlonum(elem));
            if (a == b) return current;
        }
        current = types.cdr(current);
    }
    return types.FALSE;
}

fn assocFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const pair = types.car(current);
        if (!types.isPair(pair)) return PrimitiveError.TypeError;
        if (deepEqual(args[0], types.car(pair))) return pair;
        current = types.cdr(current);
    }
    return types.FALSE;
}

fn assqFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const pair = types.car(current);
        if (!types.isPair(pair)) return PrimitiveError.TypeError;
        if (args[0] == types.car(pair)) return pair;
        current = types.cdr(current);
    }
    return types.FALSE;
}

fn assvFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const pair = types.car(current);
        if (!types.isPair(pair)) return PrimitiveError.TypeError;
        const key = types.car(pair);
        if (args[0] == key) return pair;
        if (types.isFlonum(args[0]) and types.isFlonum(key)) {
            const a: u64 = @bitCast(types.toFlonum(args[0]));
            const b: u64 = @bitCast(types.toFlonum(key));
            if (a == b) return pair;
        }
        current = types.cdr(current);
    }
    return types.FALSE;
}

// ---------------------------------------------------------------------------
// boolean=? and symbol=?
// ---------------------------------------------------------------------------

fn booleanEqP(args: []const Value) PrimitiveError!Value {
    if (!types.isBool(args[0])) return PrimitiveError.TypeError;
    for (args[1..]) |a| {
        if (!types.isBool(a)) return PrimitiveError.TypeError;
        if (a != args[0]) return types.FALSE;
    }
    return types.TRUE;
}

fn symbolEqP(args: []const Value) PrimitiveError!Value {
    if (!types.isSymbol(args[0])) return PrimitiveError.TypeError;
    for (args[1..]) |a| {
        if (!types.isSymbol(a)) return PrimitiveError.TypeError;
        if (a != args[0]) return types.FALSE;
    }
    return types.TRUE;
}

// ---------------------------------------------------------------------------
// map and for-each (higher-order list functions)
// ---------------------------------------------------------------------------

fn mapFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    // Collect results in an ArrayList, iterate lists in parallel
    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    // Current pointers for each list
    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[1 + i];
    }

    var call_args: [256]Value = undefined;

    while (true) {
        // Check if any list is exhausted
        var all_pairs = true;
        for (0..list_count) |i| {
            if (currents[i] == types.NIL) {
                all_pairs = false;
                break;
            }
            if (!types.isPair(currents[i])) return PrimitiveError.TypeError;
        }
        if (!all_pairs) break;

        // Extract car of each list
        for (0..list_count) |i| {
            call_args[i] = types.car(currents[i]);
        }

        // Call procedure
        const result = vm.callWithArgs(proc, call_args[0..list_count]) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };

        results.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;

        // Advance each list
        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }

    // Build result list from collected values
    var result_list: Value = types.NIL;
    var i = results.items.len;
    while (i > 0) {
        i -= 1;
        result_list = gc.allocPair(results.items[i], result_list) catch return PrimitiveError.OutOfMemory;
    }
    return result_list;
}

fn forEachFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    // Current pointers for each list
    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[1 + i];
    }

    var call_args: [256]Value = undefined;

    while (true) {
        // Check if any list is exhausted
        var all_pairs = true;
        for (0..list_count) |i| {
            if (currents[i] == types.NIL) {
                all_pairs = false;
                break;
            }
            if (!types.isPair(currents[i])) return PrimitiveError.TypeError;
        }
        if (!all_pairs) break;

        // Extract car of each list
        for (0..list_count) |i| {
            call_args[i] = types.car(currents[i]);
        }

        // Call procedure (discard result)
        _ = vm.callWithArgs(proc, call_args[0..list_count]) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };

        // Advance each list
        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }

    return types.VOID;
}

// ---------------------------------------------------------------------------
// Misc procedures
// ---------------------------------------------------------------------------

fn featuresFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    // Return a list of feature identifiers
    const r7rs = gc.allocSymbol("r7rs") catch return PrimitiveError.OutOfMemory;
    const kaappi = gc.allocSymbol("kaappi") catch return PrimitiveError.OutOfMemory;
    const ieee_float = gc.allocSymbol("ieee-float") catch return PrimitiveError.OutOfMemory;
    const posix_sym = gc.allocSymbol("posix") catch return PrimitiveError.OutOfMemory;
    const items = [_]Value{ r7rs, kaappi, ieee_float, posix_sym };
    return gc.makeList(&items) catch return PrimitiveError.OutOfMemory;
}

fn stringToSymbol(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    return gc.allocSymbol(str.data[0..str.len]) catch return PrimitiveError.OutOfMemory;
}
