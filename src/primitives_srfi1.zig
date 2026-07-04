const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

pub fn registerSrfi1(vm: *vm_mod.VM) !void {
    // Folds
    try primitives.reg(vm, "fold", &foldFn, .{ .variadic = 3 });
    try primitives.reg(vm, "fold-right", &foldRightFn, .{ .variadic = 3 });
    try primitives.reg(vm, "reduce", &reduceFn, .{ .exact = 3 });
    try primitives.reg(vm, "reduce-right", &reduceRightFn, .{ .exact = 3 });

    // Filtering
    try primitives.reg(vm, "filter", &filterFn, .{ .exact = 2 });
    try primitives.reg(vm, "remove", &removeFn, .{ .exact = 2 });
    try primitives.reg(vm, "partition", &partitionFn, .{ .exact = 2 });

    // Searching
    try primitives.reg(vm, "find", &findFn, .{ .exact = 2 });
    try primitives.reg(vm, "find-tail", &findTailFn, .{ .exact = 2 });
    try primitives.reg(vm, "any", &anyFn, .{ .variadic = 2 });
    try primitives.reg(vm, "every", &everyFn, .{ .variadic = 2 });
    try primitives.reg(vm, "count", &countFn, .{ .variadic = 2 });

    // Construction
    try primitives.reg(vm, "iota", &iotaFn, .{ .variadic = 1 });
    try primitives.reg(vm, "zip", &zipFn, .{ .variadic = 1 });
    try primitives.reg(vm, "concatenate", &concatenateFn, .{ .exact = 1 });

    // Extraction
    try primitives.reg(vm, "take", &takeFn, .{ .exact = 2 });
    try primitives.reg(vm, "drop", &dropFn, .{ .exact = 2 });
    try primitives.reg(vm, "take-while", &takeWhileFn, .{ .exact = 2 });
    try primitives.reg(vm, "drop-while", &dropWhileFn, .{ .exact = 2 });

    // Mapping
    try primitives.reg(vm, "filter-map", &filterMapFn, .{ .variadic = 2 });
    try primitives.reg(vm, "append-map", &appendMapFn, .{ .variadic = 2 });

    // Misc
    try primitives.reg(vm, "last", &lastFn, .{ .exact = 1 });
    try primitives.reg(vm, "last-pair", &lastPairFn, .{ .exact = 1 });
    try primitives.reg(vm, "proper-list?", &properListPFn, .{ .exact = 1 });
    try primitives.reg(vm, "dotted-list?", &dottedListPFn, .{ .exact = 1 });
    try primitives.reg(vm, "circular-list?", &circularListPFn, .{ .exact = 1 });

    // Set operations
    try primitives.reg(vm, "lset-intersection", &lsetIntersectionFn, .{ .variadic = 2 });
    try primitives.reg(vm, "lset-difference", &lsetDifferenceFn, .{ .variadic = 2 });
    try primitives.reg(vm, "lset=", &lsetEqualFn, .{ .variadic = 1 });
    try primitives.reg(vm, "lset-adjoin", &lsetAdjoinFn, .{ .variadic = 2 });
    try primitives.reg(vm, "lset-union", &lsetUnionFn, .{ .variadic = 1 });
    try primitives.reg(vm, "lset-xor", &lsetXorFn, .{ .variadic = 1 });

    // Additional constructors
    try primitives.reg(vm, "xcons", &xconsFn, .{ .exact = 2 });
    try primitives.reg(vm, "cons*", &consStarFn, .{ .variadic = 1 });
    try primitives.reg(vm, "list-tabulate", &listTabulateFn, .{ .exact = 2 });
    try primitives.reg(vm, "circular-list", &circularListFn, .{ .variadic = 0 });

    // Additional predicates
    try primitives.reg(vm, "not-pair?", &notPairPFn, .{ .exact = 1 });
    try primitives.reg(vm, "null-list?", &nullListPFn, .{ .exact = 1 });
    try primitives.reg(vm, "list=", &listEqualFn, .{ .variadic = 1 });

    // Additional selectors
    try primitives.reg(vm, "first", &firstFn, .{ .exact = 1 });
    try primitives.reg(vm, "second", &secondFn, .{ .exact = 1 });
    try primitives.reg(vm, "third", &thirdFn, .{ .exact = 1 });
    try primitives.reg(vm, "fourth", &fourthFn, .{ .exact = 1 });
    try primitives.reg(vm, "fifth", &fifthFn, .{ .exact = 1 });
    try primitives.reg(vm, "sixth", &sixthFn, .{ .exact = 1 });
    try primitives.reg(vm, "seventh", &seventhFn, .{ .exact = 1 });
    try primitives.reg(vm, "eighth", &eighthFn, .{ .exact = 1 });
    try primitives.reg(vm, "ninth", &ninthFn, .{ .exact = 1 });
    try primitives.reg(vm, "tenth", &tenthFn, .{ .exact = 1 });
    try primitives.reg(vm, "car+cdr", &carCdrFn, .{ .exact = 1 });
    try primitives.reg(vm, "take-right", &takeRightFn, .{ .exact = 2 });
    try primitives.reg(vm, "drop-right", &dropRightFn, .{ .exact = 2 });
    try primitives.reg(vm, "split-at", &splitAtFn, .{ .exact = 2 });

    // Additional searching
    try primitives.reg(vm, "list-index", &listIndexFn, .{ .variadic = 2 });
    try primitives.reg(vm, "span", &spanFn, .{ .exact = 2 });
    try primitives.reg(vm, "break", &breakFn, .{ .exact = 2 });

    // Deletion
    try primitives.reg(vm, "delete", &deleteFn, .{ .variadic = 2 });
    try primitives.reg(vm, "delete-duplicates", &deleteDuplicatesFn, .{ .variadic = 1 });

    // Association lists
    try primitives.reg(vm, "alist-cons", &alistConsFn, .{ .exact = 3 });
    try primitives.reg(vm, "alist-copy", &alistCopyFn, .{ .exact = 1 });
    try primitives.reg(vm, "alist-delete", &alistDeleteFn, .{ .variadic = 2 });

    // Unfold
    try primitives.reg(vm, "unfold", &unfoldFn, .{ .variadic = 4 });
    try primitives.reg(vm, "unfold-right", &unfoldRightFn, .{ .variadic = 4 });

    // Additional misc
    try primitives.reg(vm, "append-reverse", &appendReverseFn, .{ .exact = 2 });
    try primitives.reg(vm, "length+", &lengthPlusFn, .{ .exact = 1 });
    try primitives.reg(vm, "unzip1", &unzip1Fn, .{ .exact = 1 });
    try primitives.reg(vm, "unzip2", &unzip2Fn, .{ .exact = 1 });
    try primitives.reg(vm, "pair-for-each", &pairForEachFn, .{ .variadic = 2 });
    try primitives.reg(vm, "pair-fold", &pairFoldFn, .{ .variadic = 3 });
    try primitives.reg(vm, "pair-fold-right", &pairFoldRightFn, .{ .variadic = 3 });
    try primitives.reg(vm, "map-in-order", &mapInOrderFn, .{ .variadic = 2 });
}

// ---------------------------------------------------------------------------
// VM call helper
// ---------------------------------------------------------------------------

fn callVM(proc: Value, call_args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    return vm.callWithArgs(proc, call_args) catch |err| {
        return primitives.mapVMError(err);
    };
}

fn isTruthyResult(v: Value) bool {
    return types.isTruthy(v);
}

fn buildList(gc: *memory.GC, items: []const Value, tail: Value) PrimitiveError!Value {
    var result = tail;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i = items.len;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(items[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

const MultiListIter = struct {
    currents: [256]Value,
    call_args: [257]Value,
    list_count: usize,
    use_pairs: bool,

    fn init(lists: []const Value, use_pairs: bool) MultiListIter {
        var self: MultiListIter = .{
            .currents = undefined,
            .call_args = undefined,
            .list_count = lists.len,
            .use_pairs = use_pairs,
        };
        for (0..lists.len) |i| self.currents[i] = lists[i];
        return self;
    }

    fn next(self: *MultiListIter, name: []const u8) PrimitiveError!?[]Value {
        for (0..self.list_count) |i| {
            if (self.currents[i] == types.NIL) return null;
            if (!types.isPair(self.currents[i])) return primitives.typeError(name, "pair", self.currents[i]);
        }
        for (0..self.list_count) |i| {
            self.call_args[i] = if (self.use_pairs) self.currents[i] else types.car(self.currents[i]);
        }
        return self.call_args[0..self.list_count];
    }

    fn advance(self: *MultiListIter) void {
        for (0..self.list_count) |i| self.currents[i] = types.cdr(self.currents[i]);
    }
};

// ---------------------------------------------------------------------------
// Folds
// ---------------------------------------------------------------------------

// (fold proc init list1 ...)
fn foldFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    var acc = args[1];
    if (args.len < 3) return PrimitiveError.ArityMismatch;

    gc.pushRoot(&acc) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    var iter = MultiListIter.init(args[2..], false);
    while (try iter.next("fold")) |_| {
        iter.call_args[iter.list_count] = acc;
        acc = try callVM(proc, iter.call_args[0 .. iter.list_count + 1]);
        iter.advance();
    }
    return acc;
}

// (fold-right proc init list1 ...)
fn foldRightFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
            if (!types.isPair(current)) return primitives.typeError("fold-right", "pair", current);
            all_elems[i].append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
            current = types.cdr(current);
            count += 1;
        }
        if (count < min_len) min_len = count;
    }

    // Fold from right to left
    var acc = init;
    gc.pushRoot(&acc) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    const ridentity = args[1];
    var lst = args[2];

    if (lst == types.NIL) return ridentity;
    if (!types.isPair(lst)) return primitives.typeError("reduce", "pair", lst);

    var acc = types.car(lst);
    gc.pushRoot(&acc) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    lst = types.cdr(lst);

    while (lst != types.NIL) {
        if (!types.isPair(lst)) return primitives.typeError("reduce", "pair", lst);
        const call_args_buf = [2]Value{ types.car(lst), acc };
        acc = try callVM(proc, &call_args_buf);
        lst = types.cdr(lst);
    }
    return acc;
}

// (reduce-right f ridentity list)
fn reduceRightFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    const ridentity = args[1];
    const lst = args[2];

    if (lst == types.NIL) return ridentity;

    // Collect elements
    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    var current = lst;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("reduce-right", "pair", current);
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    if (elems.items.len == 0) return ridentity;

    var acc = elems.items[elems.items.len - 1];
    gc.pushRoot(&acc) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("filter", "pair", current);
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (isTruthyResult(result)) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    return buildList(gc, results.items, types.NIL);
}

// (remove pred list) — opposite of filter
fn removeFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("remove", "pair", current);
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (!isTruthyResult(result)) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    return buildList(gc, results.items, types.NIL);
}

// (partition pred list) — returns two values: (matching, non-matching)
fn partitionFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var yes: std.ArrayList(Value) = .empty;
    defer yes.deinit(gc.allocator);
    var no: std.ArrayList(Value) = .empty;
    defer no.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("partition", "pair", current);
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

    var yes_list = try buildList(gc, yes.items, types.NIL);
    gc.pushRoot(&yes_list) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const no_list = try buildList(gc, no.items, types.NIL);
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
        if (!types.isPair(current)) return primitives.typeError("find", "pair", current);
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
        if (!types.isPair(current)) return primitives.typeError("find-tail", "pair", current);
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
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var iter = MultiListIter.init(args[1..], false);
    while (try iter.next("any")) |call_args| {
        const result = try callVM(pred, call_args);
        if (isTruthyResult(result)) return result;
        iter.advance();
    }
    return types.FALSE;
}

// (every pred list1 ...) — returns last truthy result or #f
fn everyFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var iter = MultiListIter.init(args[1..], false);
    var last_result: Value = types.TRUE;
    while (try iter.next("every")) |call_args| {
        const result = try callVM(pred, call_args);
        if (!isTruthyResult(result)) return types.FALSE;
        last_result = result;
        iter.advance();
    }
    return last_result;
}

// (count pred list1 ...) — count satisfying elements
fn countFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var iter = MultiListIter.init(args[1..], false);
    var n: i64 = 0;
    while (try iter.next("count")) |call_args| {
        const result = try callVM(pred, call_args);
        if (isTruthyResult(result)) n += 1;
        iter.advance();
    }
    return types.makeFixnum(n);
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

// (iota count) or (iota count start) or (iota count start step)
fn iotaFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0]) and !types.isFlonum(args[0])) return primitives.typeError("iota", "number", args[0]);

    const count_val = if (types.isFixnum(args[0])) types.toFixnum(args[0]) else @as(i64, @intFromFloat(types.toFlonum(args[0])));
    if (count_val < 0) return primitives.typeError("iota", "non-negative integer", args[0]);
    const cnt: usize = @intCast(count_val);

    // Determine if we should use flonum or fixnum arithmetic
    const use_flonum = (args.len > 1 and types.isFlonum(args[1])) or
        (args.len > 2 and types.isFlonum(args[2]));

    if (use_flonum) {
        var start: f64 = 0.0;
        var step: f64 = 1.0;
        if (args.len > 1) start = primitives.toF64(args[1]) catch return primitives.typeError("iota", "number", args[1]);
        if (args.len > 2) step = primitives.toF64(args[2]) catch return primitives.typeError("iota", "number", args[2]);

        var result: Value = types.NIL;
        gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        var i = cnt;
        while (i > 0) {
            i -= 1;
            const v = start + @as(f64, @floatFromInt(i)) * step;
            var fval = types.makeFlonum(v);
            gc.pushRoot(&fval) catch return PrimitiveError.OutOfMemory;
            result = gc.allocPair(fval, result) catch {
                gc.popRoot();
                return PrimitiveError.OutOfMemory;
            };
            gc.popRoot();
        }
        return result;
    } else {
        var start: i64 = 0;
        var step: i64 = 1;
        if (args.len > 1) {
            if (!types.isFixnum(args[1])) return primitives.typeError("iota", "integer", args[1]);
            start = types.toFixnum(args[1]);
        }
        if (args.len > 2) {
            if (!types.isFixnum(args[2])) return primitives.typeError("iota", "integer", args[2]);
            step = types.toFixnum(args[2]);
        }

        var result: Value = types.NIL;
        gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 0) return types.NIL;

    var iter = MultiListIter.init(args, false);
    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (try iter.next("zip")) |call_args| {
        var row: Value = types.NIL;
        var j = call_args.len;
        while (j > 0) {
            j -= 1;
            row = gc.allocPair(call_args[j], row) catch return PrimitiveError.OutOfMemory;
        }
        results.append(gc.allocator, row) catch return PrimitiveError.OutOfMemory;
        iter.advance();
    }

    return buildList(gc, results.items, types.NIL);
}

// (concatenate list-of-lists)
fn concatenateFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Collect all sublists
    var sublists: std.ArrayList(Value) = .empty;
    defer sublists.deinit(gc.allocator);

    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("concatenate", "pair", current);
        sublists.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    if (sublists.items.len == 0) return types.NIL;

    var result = sublists.items[sublists.items.len - 1];
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var idx = sublists.items.len - 1;
    while (idx > 0) {
        idx -= 1;
        var lst = sublists.items[idx];
        var elems: std.ArrayList(Value) = .empty;
        defer elems.deinit(gc.allocator);
        while (lst != types.NIL) {
            if (!types.isPair(lst)) return primitives.typeError("concatenate", "pair", lst);
            elems.append(gc.allocator, types.car(lst)) catch return PrimitiveError.OutOfMemory;
            lst = types.cdr(lst);
        }
        result = try buildList(gc, elems.items, result);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

// (take list k) — first k elements
fn takeFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[1])) return primitives.typeError("take", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.typeError("take", "non-negative integer", args[1]);
    const count: usize = @intCast(k);

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    var current = args[0];
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (!types.isPair(current)) return primitives.typeError("take", "pair", current);
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    return buildList(gc, elems.items, types.NIL);
}

// (drop list k) — remaining after first k
fn dropFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return primitives.typeError("drop", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.typeError("drop", "non-negative integer", args[1]);

    var current = args[0];
    var i: i64 = 0;
    while (i < k) : (i += 1) {
        if (!types.isPair(current)) return primitives.typeError("drop", "pair", current);
        current = types.cdr(current);
    }
    return current;
}

// (take-while pred list)
fn takeWhileFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("take-while", "pair", current);
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (!isTruthyResult(result)) break;
        elems.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    return buildList(gc, elems.items, types.NIL);
}

// (drop-while pred list)
fn dropWhileFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    var current = args[1];

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("drop-while", "pair", current);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);
    const roots_base = gc.extra_roots.items.len;
    defer gc.extra_roots.shrinkRetainingCapacity(roots_base);

    var iter = MultiListIter.init(args[1..], false);
    while (try iter.next("filter-map")) |call_args| {
        const result = try callVM(proc, call_args);
        if (isTruthyResult(result)) {
            results.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
            gc.extra_roots.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
        }
        iter.advance();
    }

    return buildList(gc, results.items, types.NIL);
}

// (append-map proc list1 ...) — map then append results
fn appendMapFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var all_elems: std.ArrayList(Value) = .empty;
    defer all_elems.deinit(gc.allocator);
    const roots_base = gc.extra_roots.items.len;
    defer gc.extra_roots.shrinkRetainingCapacity(roots_base);

    var iter = MultiListIter.init(args[1..], false);
    while (try iter.next("append-map")) |call_args| {
        const result = try callVM(proc, call_args);
        var sub = result;
        while (sub != types.NIL) {
            if (!types.isPair(sub)) return primitives.typeError("append-map", "pair", sub);
            const elem = types.car(sub);
            all_elems.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
            gc.extra_roots.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
            sub = types.cdr(sub);
        }
        iter.advance();
    }

    return buildList(gc, all_elems.items, types.NIL);
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

// (last list) — last element
fn lastFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    if (!types.isPair(current)) return primitives.typeError("last", "pair", current);

    while (true) {
        const next = types.cdr(current);
        if (!types.isPair(next)) return types.car(current);
        current = next;
    }
}

// (last-pair list) — last pair in list
fn lastPairFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    if (!types.isPair(current)) return primitives.typeError("last-pair", "pair", current);

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
        if (!types.isPair(current)) return primitives.typeError("lset-*", "pair", current);
        const call_args = [2]Value{ elem, types.car(current) };
        const result = try callVM(pred, &call_args);
        if (isTruthyResult(result)) return true;
        current = types.cdr(current);
    }
    return false;
}

// (lset-intersection = list1 list2 ...) — elements of list1 in ALL other lists
fn lsetIntersectionFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const list1 = args[1];
    const other_count = args.len - 2;

    if (other_count == 0) return list1;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    var current = list1;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("lset-intersection", "pair", current);
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

    return buildList(gc, results.items, types.NIL);
}

// (lset-difference = list1 list2 ...) — elements of list1 NOT in any other list
fn lsetDifferenceFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const list1 = args[1];
    const other_count = args.len - 2;

    if (other_count == 0) return list1;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    var current = list1;
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("lset-difference", "pair", current);
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

    return buildList(gc, results.items, types.NIL);
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
            if (!types.isPair(current)) return primitives.typeError("lset=", "pair", current);
            if (!try memberByPred(pred, types.car(current), b)) return types.FALSE;
            current = types.cdr(current);
        }

        // Every element of b must be in a
        current = b;
        while (current != types.NIL) {
            if (!types.isPair(current)) return primitives.typeError("lset=", "pair", current);
            if (!try memberByPred(pred, types.car(current), a)) return types.FALSE;
            current = types.cdr(current);
        }
    }
    return types.TRUE;
}

// ---------------------------------------------------------------------------
// Additional constructors
// ---------------------------------------------------------------------------

// (xcons d a) — reversed cons: (cons a d)
fn xconsFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPair(args[1], args[0]) catch return PrimitiveError.OutOfMemory;
}

// (cons* a1 a2 ... an) — like list but last element is tail
fn consStarFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 0) return PrimitiveError.ArityMismatch;
    if (args.len == 1) return args[0];
    var result = args[args.len - 1];
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i = args.len - 1;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(args[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// (list-tabulate n init-proc) — build list by calling init-proc on 0..n-1
fn listTabulateFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return primitives.typeError("list-tabulate", "integer", args[0]);
    const n = types.toFixnum(args[0]);
    if (n < 0) return primitives.typeError("list-tabulate", "non-negative integer", args[0]);
    const proc = args[1];

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        const call_args = [1]Value{types.makeFixnum(i)};
        const val = try callVM(proc, &call_args);
        elems.append(gc.allocator, val) catch return PrimitiveError.OutOfMemory;
    }

    return buildList(gc, elems.items, types.NIL);
}

// (circular-list v1 v2 ...) — create circular list
fn circularListFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 0) return types.NIL;
    // Build the list first
    var first: Value = undefined;
    var last_pair: Value = undefined;
    first = gc.allocPair(args[0], types.NIL) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&first) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    last_pair = first;
    for (args[1..]) |a| {
        const new_pair = gc.allocPair(a, types.NIL) catch return PrimitiveError.OutOfMemory;
        types.setCdr(last_pair, new_pair);
        last_pair = new_pair;
    }
    // Close the loop
    types.setCdr(last_pair, first);
    return first;
}

// ---------------------------------------------------------------------------
// Additional predicates
// ---------------------------------------------------------------------------

// (not-pair? x)
fn notPairPFn(args: []const Value) PrimitiveError!Value {
    return if (!types.isPair(args[0])) types.TRUE else types.FALSE;
}

// (null-list? x) — like null? but errors on non-list
fn nullListPFn(args: []const Value) PrimitiveError!Value {
    if (args[0] == types.NIL) return types.TRUE;
    if (types.isPair(args[0])) return types.FALSE;
    return primitives.typeError("null-list?", "list", args[0]);
}

// (list= elt= list1 ...) — elementwise list equality
fn listEqualFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    const list_count = args.len - 1;
    if (list_count <= 1) return types.TRUE;

    for (0..list_count - 1) |i| {
        var a = args[1 + i];
        var b = args[2 + i];
        while (true) {
            if (a == types.NIL and b == types.NIL) break;
            if (a == types.NIL or b == types.NIL) return types.FALSE;
            if (!types.isPair(a) or !types.isPair(b)) return types.FALSE;
            const call_args = [2]Value{ types.car(a), types.car(b) };
            const result = try callVM(pred, &call_args);
            if (!isTruthyResult(result)) return types.FALSE;
            a = types.cdr(a);
            b = types.cdr(b);
        }
    }
    return types.TRUE;
}

// ---------------------------------------------------------------------------
// Additional selectors
// ---------------------------------------------------------------------------

// first..fifth: extract nth element from list
fn firstFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return primitives.typeError("first", "pair", args[0]);
    return types.car(args[0]);
}

fn secondFn(args: []const Value) PrimitiveError!Value {
    var p = args[0];
    if (!types.isPair(p)) return primitives.typeError("second", "pair", p);
    p = types.cdr(p);
    if (!types.isPair(p)) return primitives.typeError("second", "pair", p);
    return types.car(p);
}

fn thirdFn(args: []const Value) PrimitiveError!Value {
    var p = args[0];
    comptime var i = 0;
    inline while (i < 2) : (i += 1) {
        if (!types.isPair(p)) return primitives.typeError("third", "pair", p);
        p = types.cdr(p);
    }
    if (!types.isPair(p)) return primitives.typeError("third", "pair", p);
    return types.car(p);
}

fn fourthFn(args: []const Value) PrimitiveError!Value {
    var p = args[0];
    comptime var i = 0;
    inline while (i < 3) : (i += 1) {
        if (!types.isPair(p)) return primitives.typeError("fourth", "pair", p);
        p = types.cdr(p);
    }
    if (!types.isPair(p)) return primitives.typeError("fourth", "pair", p);
    return types.car(p);
}

fn fifthFn(args: []const Value) PrimitiveError!Value {
    var p = args[0];
    comptime var i = 0;
    inline while (i < 4) : (i += 1) {
        if (!types.isPair(p)) return primitives.typeError("fifth", "pair", p);
        p = types.cdr(p);
    }
    if (!types.isPair(p)) return primitives.typeError("fifth", "pair", p);
    return types.car(p);
}

fn nthFn(args: []const Value, comptime n: u8) PrimitiveError!Value {
    var p = args[0];
    comptime var i = 0;
    inline while (i < n) : (i += 1) {
        if (!types.isPair(p)) return primitives.typeError("list-ref (nth selector)", "pair", p);
        p = types.cdr(p);
    }
    if (!types.isPair(p)) return primitives.typeError("list-ref (nth selector)", "pair", p);
    return types.car(p);
}

fn sixthFn(args: []const Value) PrimitiveError!Value {
    return nthFn(args, 5);
}
fn seventhFn(args: []const Value) PrimitiveError!Value {
    return nthFn(args, 6);
}
fn eighthFn(args: []const Value) PrimitiveError!Value {
    return nthFn(args, 7);
}
fn ninthFn(args: []const Value) PrimitiveError!Value {
    return nthFn(args, 8);
}
fn tenthFn(args: []const Value) PrimitiveError!Value {
    return nthFn(args, 9);
}

// (car+cdr pair) — returns (values (car pair) (cdr pair))
fn carCdrFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isPair(args[0])) return primitives.typeError("car+cdr", "pair", args[0]);
    const vals = [2]Value{ types.car(args[0]), types.cdr(args[0]) };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// (take-right list k)
fn takeRightFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[1])) return primitives.typeError("take-right", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.typeError("take-right", "non-negative integer", args[1]);
    // Find list length
    var len: i64 = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("take-right", "pair", current);
        current = types.cdr(current);
        len += 1;
    }
    // drop (len - k) elements
    const to_drop = len - k;
    if (to_drop < 0) return primitives.typeError("take-right", "valid index (k <= length)", args[1]);
    current = args[0];
    var i: i64 = 0;
    while (i < to_drop) : (i += 1) {
        current = types.cdr(current);
    }
    return current;
}

// (drop-right list k)
fn dropRightFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[1])) return primitives.typeError("drop-right", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.typeError("drop-right", "non-negative integer", args[1]);
    // Find list length
    var len: i64 = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("drop-right", "pair", current);
        current = types.cdr(current);
        len += 1;
    }
    const to_take = len - k;
    if (to_take < 0) return primitives.typeError("drop-right", "valid index (k <= length)", args[1]);
    const count: usize = @intCast(to_take);

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    current = args[0];
    var i: usize = 0;
    while (i < count) : (i += 1) {
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    return buildList(gc, elems.items, types.NIL);
}

// (split-at list k) — returns (values (take list k) (drop list k))
fn splitAtFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[1])) return primitives.typeError("split-at", "integer", args[1]);
    const k = types.toFixnum(args[1]);
    if (k < 0) return primitives.typeError("split-at", "non-negative integer", args[1]);
    const count: usize = @intCast(k);

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    var current = args[0];
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (!types.isPair(current)) return primitives.typeError("split-at", "pair", current);
        elems.append(gc.allocator, types.car(current)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    var prefix = try buildList(gc, elems.items, types.NIL);
    gc.pushRoot(&prefix) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const vals = [2]Value{ prefix, current };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Additional searching
// ---------------------------------------------------------------------------

// (list-index pred list1 ...) — index of first match
fn listIndexFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var iter = MultiListIter.init(args[1..], false);
    var idx: i64 = 0;
    while (try iter.next("list-index")) |call_args| {
        const result = try callVM(pred, call_args);
        if (isTruthyResult(result)) return types.makeFixnum(idx);
        iter.advance();
        idx += 1;
    }
    return types.FALSE;
}

// (span pred list) — returns (values prefix suffix) where prefix is take-while
fn spanFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("span", "pair", current);
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (!isTruthyResult(result)) break;
        elems.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    var prefix = try buildList(gc, elems.items, types.NIL);
    gc.pushRoot(&prefix) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const vals = [2]Value{ prefix, current };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// (break pred list) — like span but splits where pred first succeeds
fn breakFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var current = args[1];

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("break", "pair", current);
        const elem = types.car(current);
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (isTruthyResult(result)) break;
        elems.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    var prefix = try buildList(gc, elems.items, types.NIL);
    gc.pushRoot(&prefix) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const vals = [2]Value{ prefix, current };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

// (delete x list [=]) — remove all elements equal to x
fn deleteFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const x = args[0];
    var current = args[1];
    // Optional equality predicate
    const has_pred = args.len > 2;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("delete", "pair", current);
        const elem = types.car(current);
        var is_equal: bool = undefined;
        if (has_pred) {
            const call_args = [2]Value{ x, elem };
            const result = try callVM(args[2], &call_args);
            is_equal = isTruthyResult(result);
        } else {
            is_equal = primitives.deepEqual(x, elem);
        }
        if (!is_equal) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    return buildList(gc, results.items, types.NIL);
}

// (delete-duplicates list [=]) — remove duplicate elements
fn deleteDuplicatesFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var current = args[0];
    const has_pred = args.len > 1;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("delete-duplicates", "pair", current);
        const elem = types.car(current);
        // Check if elem already in results
        var found = false;
        for (results.items) |r| {
            if (has_pred) {
                const call_args = [2]Value{ elem, r };
                const result = try callVM(args[1], &call_args);
                if (isTruthyResult(result)) {
                    found = true;
                    break;
                }
            } else {
                if (primitives.deepEqual(elem, r)) {
                    found = true;
                    break;
                }
            }
        }
        if (!found) {
            results.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    return buildList(gc, results.items, types.NIL);
}

// ---------------------------------------------------------------------------
// Association lists
// ---------------------------------------------------------------------------

// (alist-cons key datum alist) — (cons (cons key datum) alist)
fn alistConsFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pair = gc.allocPair(args[0], args[1]) catch return PrimitiveError.OutOfMemory;
    return gc.allocPair(pair, args[2]) catch return PrimitiveError.OutOfMemory;
}

// (alist-copy alist) — shallow copy of association list
fn alistCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var current = args[0];

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("alist-copy", "pair", current);
        const entry = types.car(current);
        if (!types.isPair(entry)) return primitives.typeError("alist-copy", "pair", entry);
        const new_entry = gc.allocPair(types.car(entry), types.cdr(entry)) catch return PrimitiveError.OutOfMemory;
        elems.append(gc.allocator, new_entry) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    return buildList(gc, elems.items, types.NIL);
}

// (alist-delete key alist [=]) — remove entries with matching key
fn alistDeleteFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const key = args[0];
    var current = args[1];
    const has_pred = args.len > 2;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("alist-delete", "pair", current);
        const entry = types.car(current);
        if (!types.isPair(entry)) return primitives.typeError("alist-delete", "pair", entry);
        const entry_key = types.car(entry);

        var is_equal: bool = undefined;
        if (has_pred) {
            const call_args = [2]Value{ key, entry_key };
            const result = try callVM(args[2], &call_args);
            is_equal = isTruthyResult(result);
        } else {
            is_equal = primitives.deepEqual(key, entry_key);
        }
        if (!is_equal) {
            results.append(gc.allocator, entry) catch return PrimitiveError.OutOfMemory;
        }
        current = types.cdr(current);
    }

    return buildList(gc, results.items, types.NIL);
}

// ---------------------------------------------------------------------------
// Additional set operations
// ---------------------------------------------------------------------------

// (lset-adjoin = list elt ...) — add elements not already present
fn lsetAdjoinFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    var result = args[1];
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    for (args[2..]) |elt| {
        if (!try memberByPred(pred, elt, result)) {
            result = gc.allocPair(elt, result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

// (lset-union = list1 ...) — union of all lists
fn lsetUnionFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const list_count = args.len - 1;
    if (list_count == 0) return types.NIL;

    var result = args[1];
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    for (args[2..]) |lst| {
        var current = lst;
        while (current != types.NIL) {
            if (!types.isPair(current)) return primitives.typeError("lset-union", "pair", current);
            const elem = types.car(current);
            if (!try memberByPred(pred, elem, result)) {
                result = gc.allocPair(elem, result) catch return PrimitiveError.OutOfMemory;
            }
            current = types.cdr(current);
        }
    }
    return result;
}

// (lset-xor = list1 ...) — symmetric difference
fn lsetXorFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    const list_count = args.len - 1;
    if (list_count == 0) return types.NIL;
    if (list_count == 1) return args[1];

    var result = args[1];
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    for (args[2..]) |lst| {
        // XOR of result and lst:
        // Elements in result but not in lst, plus elements in lst but not in result
        var new_result: std.ArrayList(Value) = .empty;
        defer new_result.deinit(gc.allocator);

        // Elements of result not in lst
        var current = result;
        while (current != types.NIL) {
            if (!types.isPair(current)) return primitives.typeError("lset-xor", "pair", current);
            const elem = types.car(current);
            if (!try memberByPred(pred, elem, lst)) {
                new_result.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
            }
            current = types.cdr(current);
        }

        // Elements of lst not in result
        current = lst;
        while (current != types.NIL) {
            if (!types.isPair(current)) return primitives.typeError("lset-xor", "pair", current);
            const elem = types.car(current);
            if (!try memberByPred(pred, elem, result)) {
                new_result.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
            }
            current = types.cdr(current);
        }

        result = try buildList(gc, new_result.items, types.NIL);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Unfold
// ---------------------------------------------------------------------------

// (unfold p f g seed [tail-gen]) — fundamental list constructor
fn unfoldFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const p = args[0]; // stop predicate
    const f = args[1]; // map function
    const g = args[2]; // successor
    var seed = args[3];
    const has_tail = args.len > 4;

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    const roots_base = gc.extra_roots.items.len;
    defer gc.extra_roots.shrinkRetainingCapacity(roots_base);
    gc.pushRoot(&seed) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    while (true) {
        const stop_args = [1]Value{seed};
        const stop = try callVM(p, &stop_args);
        if (isTruthyResult(stop)) break;

        const map_args = [1]Value{seed};
        const val = try callVM(f, &map_args);
        elems.append(gc.allocator, val) catch return PrimitiveError.OutOfMemory;
        gc.extra_roots.append(gc.allocator, val) catch return PrimitiveError.OutOfMemory;

        const succ_args = [1]Value{seed};
        seed = try callVM(g, &succ_args);
    }

    var tail: Value = types.NIL;
    if (has_tail) {
        const tail_args = [1]Value{seed};
        tail = try callVM(args[4], &tail_args);
    }
    return buildList(gc, elems.items, tail);
}

// (unfold-right p f g seed [tail]) — build list from right
fn unfoldRightFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const p = args[0];
    const f = args[1];
    const g = args[2];
    var seed = args[3];
    var result: Value = if (args.len > 4) args[4] else types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    gc.pushRoot(&seed) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    while (true) {
        const stop_args = [1]Value{seed};
        const stop = try callVM(p, &stop_args);
        if (isTruthyResult(stop)) break;

        const map_args = [1]Value{seed};
        var val = try callVM(f, &map_args);
        gc.pushRoot(&val) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(val, result) catch {
            gc.popRoot();
            return PrimitiveError.OutOfMemory;
        };
        gc.popRoot();

        const succ_args = [1]Value{seed};
        seed = try callVM(g, &succ_args);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Additional misc
// ---------------------------------------------------------------------------

// (append-reverse rev-head tail) — (append (reverse rev-head) tail)
fn appendReverseFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var current = args[0];
    var result = args[1];
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("append-reverse", "pair", current);
        result = gc.allocPair(types.car(current), result) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }
    return result;
}

// (length+ x) — length or #f if circular
fn lengthPlusFn(args: []const Value) PrimitiveError!Value {
    var current = args[0];
    var slow = current;
    var fast = current;
    var len: i64 = 0;

    while (current != types.NIL) {
        if (!types.isPair(current)) return types.makeFixnum(len); // dotted list
        current = types.cdr(current);
        len += 1;

        // Floyd's algorithm for cycle detection
        if (fast != types.NIL and types.isPair(fast)) {
            fast = types.cdr(fast);
            if (fast != types.NIL and types.isPair(fast)) {
                fast = types.cdr(fast);
            } else {
                continue;
            }
            slow = types.cdr(slow);
            if (slow == fast) return types.FALSE; // circular
        }
    }
    return types.makeFixnum(len);
}

// (unzip1 list) — map car
fn unzip1Fn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var current = args[0];
    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("unzip1", "pair", current);
        const sub = types.car(current);
        if (!types.isPair(sub)) return primitives.typeError("unzip1", "pair", sub);
        elems.append(gc.allocator, types.car(sub)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    return buildList(gc, elems.items, types.NIL);
}

// (unzip2 list) — returns (values (map car list) (map cadr list))
fn unzip2Fn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var current = args[0];
    var firsts: std.ArrayList(Value) = .empty;
    defer firsts.deinit(gc.allocator);
    var seconds: std.ArrayList(Value) = .empty;
    defer seconds.deinit(gc.allocator);

    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("unzip2", "pair", current);
        const sub = types.car(current);
        if (!types.isPair(sub)) return primitives.typeError("unzip2", "pair", sub);
        firsts.append(gc.allocator, types.car(sub)) catch return PrimitiveError.OutOfMemory;
        const rest = types.cdr(sub);
        if (!types.isPair(rest)) return primitives.typeError("unzip2", "pair", rest);
        seconds.append(gc.allocator, types.car(rest)) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }

    var list1 = try buildList(gc, firsts.items, types.NIL);
    gc.pushRoot(&list1) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const list2 = try buildList(gc, seconds.items, types.NIL);
    const vals = [2]Value{ list1, list2 };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

// (pair-for-each proc list1 ...) — like for-each but passes pairs not elements
fn pairForEachFn(args: []const Value) PrimitiveError!Value {
    const proc = args[0];
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var iter = MultiListIter.init(args[1..], true);
    while (try iter.next("pair-for-each")) |call_args| {
        _ = try callVM(proc, call_args);
        iter.advance();
    }
    return types.VOID;
}

// (pair-fold kons knil list1 ...) — like fold but passes pairs not elements
fn pairFoldFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    var acc = args[1];
    if (args.len < 3) return PrimitiveError.ArityMismatch;

    gc.pushRoot(&acc) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    var iter = MultiListIter.init(args[2..], true);
    while (try iter.next("pair-fold")) |_| {
        iter.call_args[iter.list_count] = acc;
        acc = try callVM(proc, iter.call_args[0 .. iter.list_count + 1]);
        iter.advance();
    }
    return acc;
}

// (pair-fold-right kons knil list1 ...) — like fold-right but passes pairs
fn pairFoldRightFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    const init = args[1];
    const list_count = args.len - 2;
    if (list_count == 0) return PrimitiveError.ArityMismatch;

    var all_pairs: [256]std.ArrayList(Value) = undefined;
    for (0..list_count) |i| all_pairs[i] = .empty;
    defer for (0..list_count) |i| all_pairs[i].deinit(gc.allocator);

    var min_len: usize = std.math.maxInt(usize);
    for (0..list_count) |i| {
        var current = args[2 + i];
        var count: usize = 0;
        while (current != types.NIL) {
            if (!types.isPair(current)) return primitives.typeError("pair-fold-right", "pair", current);
            all_pairs[i].append(gc.allocator, current) catch return PrimitiveError.OutOfMemory;
            current = types.cdr(current);
            count += 1;
        }
        if (count < min_len) min_len = count;
    }

    var acc = init;
    gc.pushRoot(&acc) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var call_args_buf: [257]Value = undefined;
    var idx = min_len;
    while (idx > 0) {
        idx -= 1;
        for (0..list_count) |i| call_args_buf[i] = all_pairs[i].items[idx];
        call_args_buf[list_count] = acc;
        acc = try callVM(proc, call_args_buf[0 .. list_count + 1]);
    }
    return acc;
}

// (map-in-order proc list1 ...) — same as map, guarantees left-to-right
fn mapInOrderFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (args.len < 2) return PrimitiveError.ArityMismatch;

    var results: std.ArrayList(Value) = .empty;
    defer results.deinit(gc.allocator);
    const extra_roots_base = gc.extra_roots.items.len;
    defer gc.extra_roots.shrinkRetainingCapacity(extra_roots_base);

    var iter = MultiListIter.init(args[1..], false);
    while (try iter.next("map-in-order")) |call_args| {
        const result = try callVM(proc, call_args);
        results.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
        gc.extra_roots.append(gc.allocator, result) catch return PrimitiveError.OutOfMemory;
        iter.advance();
    }

    return buildList(gc, results.items, types.NIL);
}
