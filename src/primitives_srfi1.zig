const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerSrfi1(vm: *vm_mod.VM) !void {
    // Folds
    try reg(vm, "fold", &foldFn, .{ .variadic = 3 });
    try reg(vm, "fold-right", &foldRightFn, .{ .variadic = 3 });
    try reg(vm, "reduce", &reduceFn, .{ .exact = 3 });
    try reg(vm, "reduce-right", &reduceRightFn, .{ .exact = 3 });

    // Filtering
    try reg(vm, "filter", &filterFn, .{ .exact = 2 });
    try reg(vm, "remove", &removeFn, .{ .exact = 2 });
    try reg(vm, "partition", &partitionFn, .{ .exact = 2 });

    // Searching
    try reg(vm, "find", &findFn, .{ .exact = 2 });
    try reg(vm, "find-tail", &findTailFn, .{ .exact = 2 });
    try reg(vm, "any", &anyFn, .{ .variadic = 2 });
    try reg(vm, "every", &everyFn, .{ .variadic = 2 });
    try reg(vm, "count", &countFn, .{ .variadic = 2 });

    // Construction
    try reg(vm, "iota", &iotaFn, .{ .variadic = 1 });
    try reg(vm, "zip", &zipFn, .{ .variadic = 1 });
    try reg(vm, "concatenate", &concatenateFn, .{ .exact = 1 });

    // Extraction
    try reg(vm, "take", &takeFn, .{ .exact = 2 });
    try reg(vm, "drop", &dropFn, .{ .exact = 2 });
    try reg(vm, "take-while", &takeWhileFn, .{ .exact = 2 });
    try reg(vm, "drop-while", &dropWhileFn, .{ .exact = 2 });

    // Mapping
    try reg(vm, "filter-map", &filterMapFn, .{ .variadic = 2 });
    try reg(vm, "append-map", &appendMapFn, .{ .variadic = 2 });

    // Misc
    try reg(vm, "last", &lastFn, .{ .exact = 1 });
    try reg(vm, "last-pair", &lastPairFn, .{ .exact = 1 });
    try reg(vm, "proper-list?", &properListPFn, .{ .exact = 1 });
    try reg(vm, "dotted-list?", &dottedListPFn, .{ .exact = 1 });
    try reg(vm, "circular-list?", &circularListPFn, .{ .exact = 1 });

    // Set operations
    try reg(vm, "lset-intersection", &lsetIntersectionFn, .{ .variadic = 2 });
    try reg(vm, "lset-difference", &lsetDifferenceFn, .{ .variadic = 2 });
    try reg(vm, "lset=", &lsetEqualFn, .{ .variadic = 1 });
}

// ---------------------------------------------------------------------------
// VM call helper
// ---------------------------------------------------------------------------

fn callVM(proc: Value, call_args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    return vm.callWithArgs(proc, call_args) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };
}

fn isTruthyResult(v: Value) bool {
    return types.isTruthy(v);
}

// ---------------------------------------------------------------------------
// Folds
// ---------------------------------------------------------------------------

// (fold proc init list1 ...)
fn foldFn(args: []const Value) PrimitiveError!Value {
    const proc = args[0];
    var acc = args[1];
    const list_count = args.len - 2;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    // Current pointers for each list
    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[2 + i];
    }

    var call_args_buf: [257]Value = undefined;

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

        // call_args = (car(list1), car(list2), ..., acc)
        for (0..list_count) |i| {
            call_args_buf[i] = types.car(currents[i]);
        }
        call_args_buf[list_count] = acc;

        acc = try callVM(proc, call_args_buf[0 .. list_count + 1]);

        // Advance
        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }
    return acc;
}

// (fold-right proc init list1 ...)
fn foldRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    const init = args[1];
    const list_count = args.len - 2;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    // For fold-right, we need to collect all elements first
    // Collect elements from each list
    var all_elems: [256]std.ArrayList(Value) = undefined;
    for (0..list_count) |i| {
        all_elems[i] = .empty;
    }
    defer {
        for (0..list_count) |i| {
            all_elems[i].deinit(gc.allocator);
        }
    }

    // Find the shortest list length
    var min_len: usize = std.math.maxInt(usize);
    for (0..list_count) |i| {
        var current = args[2 + i];
        var count: usize = 0;
        while (current != types.NIL) {
            if (!types.isPair(current)) return PrimitiveError.TypeError;
            all_elems[i].append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
            current = types.cdr(current);
            count += 1;
        }
        if (count < min_len) min_len = count;
    }

    // Fold from right to left
    var acc = init;
    var call_args_buf: [257]Value = undefined;
    var idx = min_len;
    while (idx > 0) {
        idx -= 1;
        for (0..list_count) |i| {
            call_args_buf[i] = all_elems[i].items[idx];
        }
        call_args_buf[list_count] = acc;
        acc = try callVM(proc, call_args_buf[0 .. list_count + 1]);
    }
    return acc;
}

// (reduce f ridentity list)
fn reduceFn(args: []const Value) PrimitiveError!Value {
    const proc = args[0];
    const ridentity = args[1];
    var lst = args[2];

    if (lst == types.NIL) return ridentity;
    if (!types.isPair(lst)) return PrimitiveError.TypeError;

    var acc = types.car(lst);
    lst = types.cdr(lst);

    while (lst != types.NIL) {
        if (!types.isPair(lst)) return PrimitiveError.TypeError;
        const call_args_buf = [2]Value{ types.car(lst), acc };
        acc = try callVM(proc, &call_args_buf);
        lst = types.cdr(lst);
    }
    return acc;
}

// (reduce-right f ridentity list)
fn reduceRightFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    const ridentity = args[1];
    const lst = args[2];

    if (lst == types.NIL) return ridentity;

    // Collect elements
    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    var current = lst;
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    if (elems.items.len == 0) return ridentity;

    var acc = elems.items[elems.items.len - 1];
    var idx = elems.items.len - 1;
    while (idx > 0) {
        idx -= 1;
        const call_args_buf = [2]Value{ elems.items[idx], acc };
        acc = try callVM(proc, &call_args_buf);
    }
    return acc;
}

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

// (filter pred list)
fn filterFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (isTruthyResult(result)) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    // Build result list
    var result_list: Value = types.NIL;
    var i = results.items.len;
    while (i > 0) {
        i -= 1;
        result_list = gc.allocPair(results.items[i], result_list) catch return PrimitiveError.OutOfMemory;
    }
    return result_list;
}

// (remove pred list) — opposite of filter
fn removeFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (!isTruthyResult(result)) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    var result_list: Value = types.NIL;
    var i = results.items.len;
    while (i > 0) {
        i -= 1;
        result_list = gc.allocPair(results.items[i], result_list) catch return PrimitiveError.OutOfMemory;
    }
    return result_list;
}

// (partition pred list) — returns two values: (matching, non-matching)
fn partitionFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var yes: std.ArrayList(Value) = .empty;
    defer yes.deinit(gc.allocator);
    var no: std.ArrayList(Value) = .empty;
    defer no.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (isTruthyResult(result)) {
            yes.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        } else {
            no.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    // Build yes list
    var yes_list: Value = types.NIL;
    var i = yes.items.len;
    while (i > 0) {
        i -= 1;
        yes_list = gc.allocPair(yes.items[i], yes_list) catch return PrimitiveError.OutOfMemory;
    }

    // Build no list
    var no_list: Value = types.NIL;
    i = no.items.len;
    while (i > 0) {
        i -= 1;
        no_list = gc.allocPair(no.items[i], no_list) catch return PrimitiveError.OutOfMemory;
    }

    // Return as multiple values
    const vals = [2]Value{ yes_list, no_list };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Searching
// ---------------------------------------------------------------------------

// (find pred list) — first element satisfying pred, or #f
fn findFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    var current = args[1];

    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (isTruthyResult(result)) return elem;
        current = types.cdr(current);
    }
    return types.FALSE;
}

// (find-tail pred list) — sublist starting from first match
fn findTailFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    var current = args[1];

    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (isTruthyResult(result)) return current;
        current = types.cdr(current);
    }
    return types.FALSE;
}

// (any pred list1 ...) — returns first truthy pred result
fn anyFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[1 + i];
    }

    var call_args_buf: [256]Value = undefined;

    while (true) {
        var all_pairs = true;
        for (0..list_count) |i| {
            if (currents[i] == types.NIL) {
                all_pairs = false;
                break;
            }
            if (!types.isPair(currents[i])) return PrimitiveError.TypeError;
        }
        if (!all_pairs) break;

        for (0..list_count) |i| {
            call_args_buf[i] = types.car(currents[i]);
        }

        const result = try callVM(pred, call_args_buf[0..list_count]);
        if (isTruthyResult(result)) return result;

        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }
    return types.FALSE;
}

// (every pred list1 ...) — returns last truthy result or #f
fn everyFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[1 + i];
    }

    var call_args_buf: [256]Value = undefined;
    var last_result: Value = types.TRUE;

    while (true) {
        var all_pairs = true;
        for (0..list_count) |i| {
            if (currents[i] == types.NIL) {
                all_pairs = false;
                break;
            }
            if (!types.isPair(currents[i])) return PrimitiveError.TypeError;
        }
        if (!all_pairs) break;

        for (0..list_count) |i| {
            call_args_buf[i] = types.car(currents[i]);
        }

        const result = try callVM(pred, call_args_buf[0..list_count]);
        if (!isTruthyResult(result)) return types.FALSE;
        last_result = result;

        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }
    return last_result;
}

// (count pred list1 ...) — count satisfying elements
fn countFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[1 + i];
    }

    var call_args_buf: [256]Value = undefined;
    var n: i64 = 0;

    while (true) {
        var all_pairs = true;
        for (0..list_count) |i| {
            if (currents[i] == types.NIL) {
                all_pairs = false;
                break;
            }
            if (!types.isPair(currents[i])) return PrimitiveError.TypeError;
        }
        if (!all_pairs) break;

        for (0..list_count) |i| {
            call_args_buf[i] = types.car(currents[i]);
        }

        const result = try callVM(pred, call_args_buf[0..list_count]);
        if (isTruthyResult(result)) n += 1;

        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }
    return types.makeFixnum(n);
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

// (iota count) or (iota count start) or (iota count start step)
fn iotaFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0]) and !types.isFlonum(args[0])) return PrimitiveError.TypeError;

    const count_val = if (types.isFixnum(args[0])) types.toFixnum(args[0]) else @as(i64, @intFromFloat(types.toFlonum(args[0])));
    if (count_val < 0) return PrimitiveError.TypeError;
    const cnt: usize = @intCast(count_val);

    // Determine if we should use flonum or fixnum arithmetic
    const use_flonum = (args.len > 1 and types.isFlonum(args[1])) or
        (args.len > 2 and types.isFlonum(args[2]));

    if (use_flonum) {
        var start: f64 = 0.0;
        var step: f64 = 1.0;
        if (args.len > 1) start = primitives.toF64(args[1]) catch return PrimitiveError.TypeError;
        if (args.len > 2) step = primitives.toF64(args[2]) catch return PrimitiveError.TypeError;

        var result: Value = types.NIL;
        var i = cnt;
        while (i > 0) {
            i -= 1;
            const v = start + @as(f64, @floatFromInt(i)) * step;
            const fval = gc.allocFlonum(v) catch return PrimitiveError.OutOfMemory;
            result = gc.allocPair(fval, result) catch return PrimitiveError.OutOfMemory;
        }
        return result;
    } else {
        var start: i64 = 0;
        var step: i64 = 1;
        if (args.len > 1) {
            if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
            start = types.toFixnum(args[1]);
        }
        if (args.len > 2) {
            if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
            step = types.toFixnum(args[2]);
        }

        var result: Value = types.NIL;
        var i = cnt;
        while (i > 0) {
            i -= 1;
            result = gc.allocPair(types.makeFixnum(start + @as(i64, @intCast(i)) * step), result) catch return PrimitiveError.OutOfMemory;
        }
        return result;
    }
}

// (zip list1 list2 ...) — transpose lists into list of lists
fn zipFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const list_count = args.len;
    if (list_count == 0) return types.NIL;

    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[i];
    }

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

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

        // Build a list of cars
        var row: Value = types.NIL;
        var j = list_count;
        while (j > 0) {
            j -= 1;
            row = gc.allocPair(types.car(currents[j]), row) catch return PrimitiveError.OutOfMemory;
        }
        results.append(gc.allocator, row) catch return PrimitiveError.OutOfMemory;

        // Advance
        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }

    // Build result list
    var result: Value = types.NIL;
    var i = results.items.len;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(results.items[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// (concatenate list-of-lists)
fn concatenateFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Collect all sublists
    var sublists: std.ArrayList(Value) = .empty;
    defer sublists.deinit(gc.allocator);

    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        sublists.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    if (sublists.items.len == 0) return types.NIL;

    // Append them all: result starts as last sublist, then prepend in reverse
    var result = sublists.items[sublists.items.len - 1];
    var idx = sublists.items.len - 1;
    while (idx > 0) {
        idx -= 1;
        var lst = sublists.items[idx];
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

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

// (take list k) — first k elements
fn takeFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0) return PrimitiveError.TypeError;
    const count: usize = @intCast(k);

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    var current = args[0];
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    var result: Value = types.NIL;
    var j = elems.items.len;
    while (j > 0) {
        j -= 1;
        result = gc.allocPair(elems.items[j], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// (drop list k) — remaining after first k
fn dropFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[1]);
    if (k < 0) return PrimitiveError.TypeError;

    var current = args[0];
    var i: i64 = 0;
    while (i < k) : (i += 1) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        current = types.cdr(current);
    }
    return current;
}

// (take-while pred list)
fn takeWhileFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (!isTruthyResult(result)) break;
        elems.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    var result: Value = types.NIL;
    var i = elems.items.len;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(elems.items[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// (drop-while pred list)
fn dropWhileFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    var current = args[1];

    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (!isTruthyResult(result)) return current;
        current = types.cdr(current);
    }
    return types.NIL;
}

// ---------------------------------------------------------------------------
// Mapping
// ---------------------------------------------------------------------------

// (filter-map proc list1 ...) — map + filter in one pass
fn filterMapFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[1 + i];
    }

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);
    var call_args_buf: [256]Value = undefined;

    while (true) {
        var all_pairs = true;
        for (0..list_count) |i| {
            if (currents[i] == types.NIL) {
                all_pairs = false;
                break;
            }
            if (!types.isPair(currents[i])) return PrimitiveError.TypeError;
        }
        if (!all_pairs) break;

        for (0..list_count) |i| {
            call_args_buf[i] = types.car(currents[i]);
        }

        const result = try callVM(proc, call_args_buf[0..list_count]);
        if (isTruthyResult(result)) {
            results.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
        }

        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }

    var result_list: Value = types.NIL;
    var i = results.items.len;
    while (i > 0) {
        i -= 1;
        result_list = gc.allocPair(results.items[i], result_list) catch return PrimitiveError.OutOfMemory;
    }
    return result_list;
}

// (append-map proc list1 ...) — map then append results
fn appendMapFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    const list_count = args.len - 1;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    var currents: [256]Value = undefined;
    for (0..list_count) |i| {
        currents[i] = args[1 + i];
    }

    var all_elems: std.ArrayList(Value) = .empty;
    defer all_elems.deinit(gc.allocator);
    var call_args_buf: [256]Value = undefined;

    while (true) {
        var all_pairs = true;
        for (0..list_count) |i| {
            if (currents[i] == types.NIL) {
                all_pairs = false;
                break;
            }
            if (!types.isPair(currents[i])) return PrimitiveError.TypeError;
        }
        if (!all_pairs) break;

        for (0..list_count) |i| {
            call_args_buf[i] = types.car(currents[i]);
        }

        const result = try callVM(proc, call_args_buf[0..list_count]);
        // result should be a list — flatten it
        var sub = result;
        while (sub != types.NIL) {
            if (!types.isPair(sub)) return PrimitiveError.TypeError;
            all_elems.append(gc.allocator, types.car(sub)) catch return PrimitiveError.OutOfMemory;
            sub = types.cdr(sub);
        }

        for (0..list_count) |i| {
            currents[i] = types.cdr(currents[i]);
        }
    }

    var result_list: Value = types.NIL;
    var i = all_elems.items.len;
    while (i > 0) {
        i -= 1;
        result_list = gc.allocPair(all_elems.items[i], result_list) catch return PrimitiveError.OutOfMemory;
    }
    return result_list;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

// (last list) — last element
fn lastFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    if (!types.isPair(current)) return PrimitiveError.TypeError;

    while (true) {
        const next = types.cdr(current);
        if (!types.isPair(next)) return types.car(current);
        current = next;
    }
}

// (last-pair list) — last pair in list
fn lastPairFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    if (!types.isPair(current)) return PrimitiveError.TypeError;

    while (true) {
        const next = types.cdr(current);
        if (!types.isPair(next)) return current;
        current = next;
    }
}

// (proper-list? x) — test if proper list (ends with nil)
fn properListPFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    // Use tortoise-and-hare for cycle detection
    var slow = current;
    var fast = current;
    var first = true;
    while (true) {
        if (current == types.NIL) return types.TRUE;
        if (!types.isPair(current)) return types.FALSE;
        current = types.cdr(current);
        // Advance hare
        if (!first) {
            if (fast == types.NIL) return types.TRUE;
            if (!types.isPair(fast)) return types.FALSE;
            fast = types.cdr(fast);
            if (fast == types.NIL) return types.TRUE;
            if (!types.isPair(fast)) return types.FALSE;
            fast = types.cdr(fast);
            slow = types.cdr(slow);
            if (slow == fast) return types.FALSE; // cycle detected
        }
        first = false;
        _ = &slow;
        _ = &fast;
    }
}

// (dotted-list? x) — test if improper (doesn't end with nil, not circular)
fn dottedListPFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    if (!types.isPair(current)) {
        // Non-pair, non-nil is considered dotted
        return if (current != types.NIL) types.TRUE else types.FALSE;
    }

    // Use tortoise-and-hare for cycle detection
    var slow = current;
    var fast = current;
    while (true) {
        if (current == types.NIL) return types.FALSE; // proper list
        if (!types.isPair(current)) return types.TRUE; // improper/dotted

        // Advance fast pointer by 2
        fast = types.cdr(fast);
        if (fast == types.NIL) return types.FALSE;
        if (!types.isPair(fast)) return types.TRUE;
        fast = types.cdr(fast);
        if (fast == types.NIL) return types.FALSE;
        if (!types.isPair(fast)) return types.TRUE;

        slow = types.cdr(slow);
        if (slow == fast) return types.FALSE; // circular, not dotted

        current = types.cdr(current);
    }
}

// (circular-list? x) — test if circular
fn circularListPFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    if (!types.isPair(current)) return types.FALSE;

    // Floyd's tortoise-and-hare
    var slow = current;
    var fast = current;
    while (true) {
        // Advance fast by 2
        fast = types.cdr(fast);
        if (fast == types.NIL) return types.FALSE;
        if (!types.isPair(fast)) return types.FALSE;
        fast = types.cdr(fast);
        if (fast == types.NIL) return types.FALSE;
        if (!types.isPair(fast)) return types.FALSE;

        // Advance slow by 1
        slow = types.cdr(slow);

        if (slow == fast) return types.TRUE;
    }
    _ = &current;
}

// ---------------------------------------------------------------------------
// Set operations
// ---------------------------------------------------------------------------

fn memberByPred(pred: Value, elem: Value, list: Value) PrimitiveError!bool {
    var current = list;
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const call_args = [2]Value{ elem, types.car(current) };
        const result = try callVM(pred, &call_args);
        if (isTruthyResult(result)) return true;
        current = types.cdr(current);
    }
    return false;
}

// (lset-intersection = list1 list2 ...) — elements of list1 in ALL other lists
fn lsetIntersectionFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const list1 = args[1];
    const other_count = args.len - 2;

    if (other_count == 0) return list1;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    var current = list1;
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);

        var in_all = true;
        for (0..other_count) |i| {
            if (!try memberByPred(pred, elem, args[2 + i])) {
                in_all = false;
                break;
            }
        }
        if (in_all) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    var result_list: Value = types.NIL;
    var i = results.items.len;
    while (i > 0) {
        i -= 1;
        result_list = gc.allocPair(results.items[i], result_list) catch return PrimitiveError.OutOfMemory;
    }
    return result_list;
}

// (lset-difference = list1 list2 ...) — elements of list1 NOT in any other list
fn lsetDifferenceFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const list1 = args[1];
    const other_count = args.len - 2;

    if (other_count == 0) return list1;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    var current = list1;
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        const elem = types.car(current);

        var in_any = false;
        for (0..other_count) |i| {
            if (try memberByPred(pred, elem, args[2 + i])) {
                in_any = true;
                break;
            }
        }
        if (!in_any) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    var result_list: Value = types.NIL;
    var i = results.items.len;
    while (i > 0) {
        i -= 1;
        result_list = gc.allocPair(results.items[i], result_list) catch return PrimitiveError.OutOfMemory;
    }
    return result_list;
}

// (lset= = list1 list2 ...) — all lists contain the same elements
fn lsetEqualFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    const list_count = args.len - 1;

    if (list_count <= 1) return types.TRUE;

    for (0..list_count - 1) |i| {
        const a = args[1 + i];
        const b = args[2 + i];

        // Every element of a must be in b
        var current = a;
        while (current != types.NIL) {
            if (!types.isPair(current)) return PrimitiveError.TypeError;
            if (!try memberByPred(pred, types.car(current), b)) return types.FALSE;
            current = types.cdr(current);
        }

        // Every element of b must be in a
        current = b;
        while (current != types.NIL) {
            if (!types.isPair(current)) return PrimitiveError.TypeError;
            if (!try memberByPred(pred, types.car(current), a)) return types.FALSE;
            current = types.cdr(current);
        }
    }
    return types.TRUE;
}
