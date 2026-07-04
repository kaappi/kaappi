const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const bignum_mod = @import("bignum.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
fn getGC() ?*@import("memory.zig").GC {
    return memory.gc_instance;
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
    try reg(vm, "member", &memberFn, .{ .variadic = 2 });
    try reg(vm, "memq", &memqFn, .{ .exact = 2 });
    try reg(vm, "memv", &memvFn, .{ .exact = 2 });
    try reg(vm, "assoc", &assocFn, .{ .variadic = 2 });
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
    if (!types.isFixnum(args[1])) return primitives.typeError("list-ref", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.indexError("list-ref", k, 0);
    var idx: i64 = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("list-ref", "pair", current);
        if (idx == k) return types.car(current);
        idx += 1;
        current = types.cdr(current);
    }
    return primitives.indexError("list-ref", k, @intCast(idx));
}

fn listTailFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return primitives.typeError("list-tail", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.indexError("list-tail", k, 0);
    var idx: i64 = 0;
    var current = args[0];
    while (idx < k) {
        if (!types.isPair(current)) return primitives.typeError("list-tail", "pair", current);
        current = types.cdr(current);
        idx += 1;
    }
    return current;
}

fn listSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return primitives.typeError("list-set!", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.indexError("list-set!", k, 0);
    var idx: i64 = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("list-set!", "pair", current);
        if (idx == k) {
            if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(current), args[2]);
            types.setCar(current, args[2]);
            return types.VOID;
        }
        idx += 1;
        current = types.cdr(current);
    }
    return primitives.indexError("list-set!", k, @intCast(idx));
}

fn listCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    var current = args[0];
    if (current == types.NIL) return types.NIL;
    if (!types.isPair(current)) return current; // atoms are returned as-is

    // Collect elements with cycle detection
    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    var slow = current;
    var fast = current;
    var step: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) break;
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
        if (step) {
            slow = types.cdr(slow);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (slow == fast and slow != types.NIL) return PrimitiveError.TypeError; // bare-ok: circular list
        }
        step = !step;
    }
    // Build the copy from the end
    var result: Value = current; // NIL for proper, last cdr for improper
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i = elems.items.len;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(elems.items[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn makeListFn(args: []const Value) PrimitiveError!Value {
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return primitives.typeError("make-list", "non-negative integer", args[0]);
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("make-list", "non-negative integer", args[0]);
    const fill: Value = if (args.len > 1) args[1] else types.UNDEFINED;
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i: i64 = 0;
    while (i < k) : (i += 1) {
        result = gc.allocPair(fill, result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn memberFn(args: []const Value) PrimitiveError!Value {
    const has_compare = args.len >= 3;
    const compare = if (has_compare) args[2] else types.NIL;
    if (has_compare and !types.isProcedure(compare)) return primitives.typeError("member", "procedure", compare);
    var current = args[1];
    var slow = current;
    var fast = current;
    var step: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("member", "proper list", current);
        if (has_compare) {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
            const call_args = [2]Value{ args[0], types.car(current) };
            const result = vm.callWithArgs(compare, &call_args) catch |err| {
                return primitives.mapVMError(err);
            };
            if (result != types.FALSE) return current;
        } else {
            if (deepEqual(args[0], types.car(current))) return current;
        }
        current = types.cdr(current);
        if (step) {
            slow = types.cdr(slow);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (slow == fast and slow != types.NIL) return PrimitiveError.TypeError; // bare-ok: circular list
        }
        step = !step;
    }
    return types.FALSE;
}

fn memqFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    var slow = current;
    var fast = current;
    var step: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("memq", "proper list", current);
        if (args[0] == types.car(current)) return current;
        current = types.cdr(current);
        if (step) {
            slow = types.cdr(slow);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (slow == fast and slow != types.NIL) return PrimitiveError.TypeError; // bare-ok: circular list
        }
        step = !step;
    }
    return types.FALSE;
}

fn isEqv(a: Value, b: Value) bool {
    if (a == b) return true;
    if (types.isFlonum(a) and types.isFlonum(b)) {
        const fa: u64 = @bitCast(types.toFlonum(a));
        const fb: u64 = @bitCast(types.toFlonum(b));
        return fa == fb;
    }
    if (types.isBignum(a) and types.isBignum(b)) {
        return bignum_mod.compare(a, b) == 0;
    }
    if ((types.isBignum(a) and types.isFixnum(b)) or
        (types.isFixnum(a) and types.isBignum(b)))
    {
        return bignum_mod.compare(a, b) == 0;
    }
    if (types.isComplex(a) and types.isComplex(b)) {
        const ca = types.toComplex(a);
        const cb = types.toComplex(b);
        const ra: u64 = @bitCast(ca.real);
        const rb: u64 = @bitCast(cb.real);
        const ia: u64 = @bitCast(ca.imag);
        const ib: u64 = @bitCast(cb.imag);
        return ra == rb and ia == ib;
    }
    if (types.isRationalObj(a) and types.isRationalObj(b)) {
        const ra = types.toRational(a);
        const rb = types.toRational(b);
        if (ra.numerator == rb.numerator and ra.denominator == rb.denominator) return true;
        const n_eq = if (ra.numerator == rb.numerator) true else if ((types.isBignum(ra.numerator) or types.isFixnum(ra.numerator)) and (types.isBignum(rb.numerator) or types.isFixnum(rb.numerator))) bignum_mod.compare(ra.numerator, rb.numerator) == 0 else false;
        const d_eq = if (ra.denominator == rb.denominator) true else if ((types.isBignum(ra.denominator) or types.isFixnum(ra.denominator)) and (types.isBignum(rb.denominator) or types.isFixnum(rb.denominator))) bignum_mod.compare(ra.denominator, rb.denominator) == 0 else false;
        return n_eq and d_eq;
    }
    return false;
}

fn memvFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    var slow = current;
    var fast = current;
    var step: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("memv", "proper list", current);
        if (isEqv(args[0], types.car(current))) return current;
        current = types.cdr(current);
        if (step) {
            slow = types.cdr(slow);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (slow == fast and slow != types.NIL) return PrimitiveError.TypeError; // bare-ok: circular list
        }
        step = !step;
    }
    return types.FALSE;
}

fn assocFn(args: []const Value) PrimitiveError!Value {
    const has_compare = args.len >= 3;
    const compare = if (has_compare) args[2] else types.NIL;
    if (has_compare and !types.isProcedure(compare)) return primitives.typeError("assoc", "procedure", compare);
    var current = args[1];
    var slow = current;
    var fast = current;
    var step_flag: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("assoc", "association list", current);
        const pair = types.car(current);
        if (!types.isPair(pair)) return primitives.typeError("assoc", "pair", pair);
        if (has_compare) {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
            const call_args = [2]Value{ args[0], types.car(pair) };
            const result = vm.callWithArgs(compare, &call_args) catch |err| {
                return primitives.mapVMError(err);
            };
            if (result != types.FALSE) return pair;
        } else {
            if (deepEqual(args[0], types.car(pair))) return pair;
        }
        current = types.cdr(current);
        if (step_flag) {
            slow = types.cdr(slow);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (slow == fast and slow != types.NIL) return PrimitiveError.TypeError; // bare-ok: circular list
        }
        step_flag = !step_flag;
    }
    return types.FALSE;
}

fn assqFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    var slow = current;
    var fast = current;
    var step: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("assq", "association list", current);
        const pair = types.car(current);
        if (!types.isPair(pair)) return primitives.typeError("assq", "pair", pair);
        if (args[0] == types.car(pair)) return pair;
        current = types.cdr(current);
        if (step) {
            slow = types.cdr(slow);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (slow == fast and slow != types.NIL) return PrimitiveError.TypeError; // bare-ok: circular list
        }
        step = !step;
    }
    return types.FALSE;
}

fn assvFn(args: []const Value) PrimitiveError!Value {
    var current = args[1];
    var slow = current;
    var fast = current;
    var step: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("assv", "association list", current);
        const pair = types.car(current);
        if (!types.isPair(pair)) return primitives.typeError("assv", "pair", pair);
        if (isEqv(args[0], types.car(pair))) return pair;
        current = types.cdr(current);
        if (step) {
            slow = types.cdr(slow);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (types.isPair(fast)) fast = types.cdr(fast);
            if (slow == fast and slow != types.NIL) return PrimitiveError.TypeError; // bare-ok: circular list
        }
        step = !step;
    }
    return types.FALSE;
}

// ---------------------------------------------------------------------------
// boolean=? and symbol=?
// ---------------------------------------------------------------------------

fn booleanEqP(args: []const Value) PrimitiveError!Value {
    if (!types.isBool(args[0])) return primitives.typeError("boolean=?", "boolean", args[0]);
    for (args[1..]) |a| {
        if (!types.isBool(a)) return primitives.typeError("boolean=?", "boolean", a);
        if (a != args[0]) return types.FALSE;
    }
    return types.TRUE;
}

fn symbolEqP(args: []const Value) PrimitiveError!Value {
    if (!types.isSymbol(args[0])) return primitives.typeError("symbol=?", "symbol", args[0]);
    for (args[1..]) |a| {
        if (!types.isSymbol(a)) return primitives.typeError("symbol=?", "symbol", a);
        if (a != args[0]) return types.FALSE;
    }
    return types.TRUE;
}

// ---------------------------------------------------------------------------
// map and for-each (higher-order list functions)
// ---------------------------------------------------------------------------

fn mapFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return primitives.typeError("map", "procedure", proc);

    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    // Build result list incrementally (rooted head + tail)
    var result_head: Value = types.NIL;
    gc.pushRoot(&result_head) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var result_tail: Value = types.NIL;
    gc.pushRoot(&result_tail) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

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
            if (!types.isPair(currents[i])) return primitives.typeError("map", "proper list", currents[i]);
        }
        if (!all_pairs) break;

        // Extract car of each list
        for (0..list_count) |i| {
            call_args[i] = types.car(currents[i]);
        }

        // Call procedure
        const result = vm.callWithArgs(proc, call_args[0..list_count]) catch |err| {
            return primitives.mapVMError(err);
        };

        const new_pair = gc.allocPair(result, types.NIL) catch return PrimitiveError.OutOfMemory;
        if (result_head == types.NIL) {
            result_head = new_pair;
        } else {
            types.setCdr(result_tail, new_pair);
        }
        result_tail = new_pair;

        // Advance each list
        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }

    return result_head;
}

fn forEachFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return primitives.typeError("for-each", "procedure", proc);

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
            if (!types.isPair(currents[i])) return primitives.typeError("for-each", "proper list", currents[i]);
        }
        if (!all_pairs) break;

        // Extract car of each list
        for (0..list_count) |i| {
            call_args[i] = types.car(currents[i]);
        }

        // Call procedure (discard result)
        _ = vm.callWithArgs(proc, call_args[0..list_count]) catch |err| {
            return primitives.mapVMError(err);
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
    if (!types.isString(args[0])) return primitives.typeError("string->symbol", "string", args[0]);
    const gc = getGC() orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    return gc.allocSymbol(str.data[0..str.len]) catch return PrimitiveError.OutOfMemory;
}
