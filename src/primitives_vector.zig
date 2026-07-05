const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

pub fn registerVector(vm: *vm_mod.VM) !void {
    try primitives.reg(vm, "vector", &vectorFn, .{ .variadic = 0 });
    try primitives.reg(vm, "make-vector", &makeVectorFn, .{ .variadic = 1 });
    try primitives.reg(vm, "vector?", &vectorP, .{ .exact = 1 });
    try primitives.reg(vm, "vector-length", &vectorLengthFn, .{ .exact = 1 });
    try primitives.reg(vm, "vector-ref", &vectorRefFn, .{ .exact = 2 });
    try primitives.reg(vm, "vector-set!", &vectorSetFn, .{ .exact = 3 });
    try primitives.reg(vm, "vector->list", &vectorToListFn, .{ .variadic = 1 });
    try primitives.reg(vm, "list->vector", &listToVectorFn, .{ .exact = 1 });
    try primitives.reg(vm, "vector-fill!", &vectorFillFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-copy", &vectorCopyFn, .{ .variadic = 1 });
    try primitives.reg(vm, "vector-copy!", &vectorCopyBangFn, .{ .variadic = 3 });
    try primitives.reg(vm, "vector-append", &vectorAppendFn, .{ .variadic = 0 });
    try primitives.reg(vm, "vector-for-each", &vectorForEachFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-map", &vectorMapFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector->string", &vectorToStringFn, .{ .variadic = 1 });
    // SRFI 133 additions
    try primitives.reg(vm, "vector-empty?", &vectorEmptyFn, .{ .exact = 1 });
    try primitives.reg(vm, "vector-count", &vectorCountFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-any", &vectorAnyFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-every", &vectorEveryFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-index", &vectorIndexFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-index-right", &vectorIndexRightFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-skip", &vectorSkipFn, .{ .exact = 2 });
    try primitives.reg(vm, "vector-skip-right", &vectorSkipRightFn, .{ .exact = 2 });
    try primitives.reg(vm, "vector-swap!", &vectorSwapFn, .{ .exact = 3 });
    try primitives.reg(vm, "vector-reverse!", &vectorReverseBangFn, .{ .variadic = 1 });
    try primitives.reg(vm, "vector-reverse-copy", &vectorReverseCopyFn, .{ .variadic = 1 });
    try primitives.reg(vm, "vector-unfold", &vectorUnfoldFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-unfold-right", &vectorUnfoldRightFn, .{ .variadic = 2 });
    try primitives.reg(vm, "vector-binary-search", &vectorBinarySearchFn, .{ .exact = 3 });
    try primitives.reg(vm, "vector-concatenate", &vectorConcatenateFn, .{ .exact = 1 });
    try primitives.reg(vm, "vector-cumulate", &vectorCumulateFn, .{ .exact = 3 });
    try primitives.reg(vm, "vector-partition", &vectorPartitionFn, .{ .exact = 2 });
    try primitives.reg(vm, "vector-append-subvectors", &vectorAppendSubvectorsFn, .{ .variadic = 0 });
}

// ---------------------------------------------------------------------------
// (vector e1 e2 ...) — create a vector from arguments
// ---------------------------------------------------------------------------

fn vectorFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocVector(args) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (make-vector k) or (make-vector k fill)
// ---------------------------------------------------------------------------

fn makeVectorFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return primitives.typeError("make-vector", "exact non-negative integer", args[0]);
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("make-vector", "exact non-negative integer", args[0]);
    const size: usize = @intCast(k);
    const fill: Value = if (args.len > 1) args[1] else types.UNDEFINED;
    return gc.allocVectorFill(size, fill) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (vector? obj)
// ---------------------------------------------------------------------------

fn vectorP(args: []const Value) PrimitiveError!Value {
    return if (types.isVector(args[0])) types.TRUE else types.FALSE;
}

// ---------------------------------------------------------------------------
// (vector-length v)
// ---------------------------------------------------------------------------

fn vectorLengthFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-length", "vector", args[0]);
    const vec = types.toVector(args[0]);
    return types.makeFixnum(@intCast(vec.data.len));
}

// ---------------------------------------------------------------------------
// (vector-ref v k)
// ---------------------------------------------------------------------------

fn vectorRefFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-ref", "vector", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("vector-ref", "exact integer", args[1]);
    const vec = types.toVector(args[0]);
    const k = types.toFixnum(args[1]);
    if (k < 0 or @as(usize, @intCast(k)) >= vec.data.len) return primitives.indexError("vector-ref", k, vec.data.len);
    return vec.data[@intCast(k)];
}

// ---------------------------------------------------------------------------
// (vector-set! v k obj)
// ---------------------------------------------------------------------------

fn vectorSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-set!", "vector", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("vector-set!", "exact integer", args[1]);
    const vec = types.toVector(args[0]);
    const k = types.toFixnum(args[1]);
    if (k < 0 or @as(usize, @intCast(k)) >= vec.data.len) return primitives.indexError("vector-set!", k, vec.data.len);
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[2]);
    vec.data[@intCast(k)] = args[2];
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (vector->list v) or (vector->list v start) or (vector->list v start end)
// ---------------------------------------------------------------------------

fn vectorToListFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isVector(args[0])) return primitives.typeError("vector->list", "vector", args[0]);
    const vec = types.toVector(args[0]);
    const len = vec.data.len;

    const range = try primitives.parseOptionalRange(args, 1, len, "vector->list");
    const start = range.start;
    const end = range.end;

    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
    var i = end;
    while (i > start) {
        i -= 1;
        result = gc.allocPair(vec.data[i], result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// ---------------------------------------------------------------------------
// (list->vector list)
// ---------------------------------------------------------------------------

fn listToVectorFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Count elements
    var count: usize = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return primitives.typeError("list->vector", "proper list", args[0]);
        count += 1;
        current = types.cdr(current);
    }

    // Allocate and fill
    const data = gc.allocator.alloc(Value, count) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(data);
    current = args[0];
    for (0..count) |i| {
        data[i] = types.car(current);
        current = types.cdr(current);
    }
    return gc.allocVector(data) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (vector-fill! v fill)
// ---------------------------------------------------------------------------

fn vectorFillFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-fill!", "vector", args[0]);
    const vec = types.toVector(args[0]);
    const len = vec.data.len;

    const range = try primitives.parseOptionalRange(args, 2, len, "vector-fill!");
    const start = range.start;
    const end = range.end;
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    @memset(vec.data[start..end], args[1]);
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (vector-copy v) or (vector-copy v start) or (vector-copy v start end)
// ---------------------------------------------------------------------------

fn vectorCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isVector(args[0])) return primitives.typeError("vector-copy", "vector", args[0]);
    const vec = types.toVector(args[0]);
    const len = vec.data.len;

    const range = try primitives.parseOptionalRange(args, 1, len, "vector-copy");
    const start = range.start;
    const end = range.end;

    return gc.allocVector(vec.data[start..end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (vector-copy! to at from) or (vector-copy! to at from start) or
// (vector-copy! to at from start end)
// ---------------------------------------------------------------------------

fn vectorCopyBangFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-copy!", "vector", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("vector-copy!", "exact non-negative integer", args[1]);
    if (!types.isVector(args[2])) return primitives.typeError("vector-copy!", "vector", args[2]);

    const to_vec = types.toVector(args[0]);
    const at_val = types.toFixnum(args[1]);
    if (at_val < 0) return primitives.typeError("vector-copy!", "exact non-negative integer", args[1]);
    const at: usize = @intCast(at_val);
    const from_vec = types.toVector(args[2]);
    const from_len = from_vec.data.len;

    const range = try primitives.parseOptionalRange(args, 3, from_len, "vector-copy!");
    const start = range.start;
    const end = range.end;

    const count = end - start;
    if (at + count > to_vec.data.len) return primitives.typeError("vector-copy!", "valid index range", args[1]);

    if (memory.gc_instance) |gc| {
        for (from_vec.data[start..end]) |val| {
            gc.writeBarrier(types.toObject(args[0]), val);
        }
    }
    // Use a loop that handles overlapping regions correctly
    if (at <= start) {
        for (0..count) |i| {
            to_vec.data[at + i] = from_vec.data[start + i];
        }
    } else {
        var i = count;
        while (i > 0) {
            i -= 1;
            to_vec.data[at + i] = from_vec.data[start + i];
        }
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (vector-append v1 v2 ...)
// ---------------------------------------------------------------------------

fn vectorAppendFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Calculate total length
    var total: usize = 0;
    for (args) |a| {
        if (!types.isVector(a)) return primitives.typeError("vector-append", "vector", a);
        total += types.toVector(a).data.len;
    }

    const data = gc.allocator.alloc(Value, total) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(data);

    var pos: usize = 0;
    for (args) |a| {
        const vec = types.toVector(a);
        @memcpy(data[pos .. pos + vec.data.len], vec.data);
        pos += vec.data.len;
    }

    return gc.allocVector(data) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (vector-for-each proc v1 v2 ...)
// ---------------------------------------------------------------------------

fn vectorForEachFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return primitives.typeError("vector-for-each", "procedure", proc);

    // Validate all vector arguments and find minimum length
    const vec_count = args.len - 1;
    if (vec_count == 0) return primitives.typeError("vector-for-each", "at least one vector argument", types.VOID);

    var min_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        if (!types.isVector(a)) return primitives.typeError("vector-for-each", "vector", a);
        const vlen = types.toVector(a).data.len;
        if (vlen < min_len) min_len = vlen;
    }

    // Iterate over elements
    var stack_buf: [256]Value = undefined;
    const call_args = if (vec_count > 256)
        gc.allocator.alloc(Value, vec_count) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..vec_count];
    defer if (vec_count > 256) gc.allocator.free(call_args);
    for (0..min_len) |i| {
        for (0..vec_count) |vi| {
            call_args[vi] = types.toVector(args[1 + vi]).data[i];
        }

        _ = vm.callWithArgs(proc, call_args) catch |err| {
            return err;
        };
    }

    return types.VOID;
}

// ---------------------------------------------------------------------------
// (vector-map proc v1 v2 ...)
// ---------------------------------------------------------------------------

fn vectorMapFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return primitives.typeError("vector-map", "procedure", proc);

    // Validate all vector arguments and find minimum length
    const vec_count = args.len - 1;
    if (vec_count == 0) return primitives.typeError("vector-map", "at least one vector argument", types.VOID);

    var min_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        if (!types.isVector(a)) return primitives.typeError("vector-map", "vector", a);
        const vlen = types.toVector(a).data.len;
        if (vlen < min_len) min_len = vlen;
    }

    // Allocate result buffer
    const results = gc.allocator.alloc(Value, min_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(results);

    const scope = gc.rootedScope();
    defer scope.release();

    var stack_buf: [256]Value = undefined;
    const call_args = if (vec_count > 256)
        gc.allocator.alloc(Value, vec_count) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..vec_count];
    defer if (vec_count > 256) gc.allocator.free(call_args);
    for (0..min_len) |i| {
        for (0..vec_count) |vi| {
            call_args[vi] = types.toVector(args[1 + vi]).data[i];
        }

        results[i] = vm.callWithArgs(proc, call_args) catch |err| {
            return err;
        };
        gc.extra_roots.append(gc.allocator, results[i]) catch return PrimitiveError.OutOfMemory;
    }

    return gc.allocVector(results) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (vector->string v) — convert vector of characters to string
// ---------------------------------------------------------------------------

fn vectorToStringFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isVector(args[0])) return primitives.typeError("vector->string", "vector", args[0]);
    const vec = types.toVector(args[0]);
    const len = vec.data.len;

    const range = try primitives.parseOptionalRange(args, 1, len, "vector->string");

    const data = vec.data[range.start..range.end];

    // Calculate UTF-8 length
    var utf8_len: usize = 0;
    for (data) |elem| {
        if (!types.isChar(elem)) return primitives.typeError("vector->string", "character", elem);
        const cp = types.toChar(elem);
        utf8_len += std.unicode.utf8CodepointSequenceLength(cp) catch return primitives.typeError("vector->string", "valid character", elem);
    }

    // Build string
    const buf = gc.allocator.alloc(u8, utf8_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    for (data) |elem| {
        const cp = types.toChar(elem);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return primitives.typeError("vector->string", "valid character", elem);
        @memcpy(buf[pos .. pos + n], tmp[0..n]);
        pos += n;
    }

    return gc.allocString(buf[0..pos]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// SRFI 133 additions
// ---------------------------------------------------------------------------

fn callVM(proc: Value, call_args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    return vm.callWithArgs(proc, call_args) catch |err| {
        return err;
    };
}

// (vector-empty? v)
fn vectorEmptyFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-empty?", "vector", args[0]);
    const vec = types.toVector(args[0]);
    return if (vec.data.len == 0) types.TRUE else types.FALSE;
}

// (vector-count pred v1 ...)
fn vectorCountFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-count", "vector", args[1]);
    const vec = types.toVector(args[1]);
    var min_len: usize = vec.data.len;
    for (args[2..]) |extra| {
        if (!types.isVector(extra)) return primitives.typeError("vector-count", "vector", extra);
        const ev = types.toVector(extra);
        if (ev.data.len < min_len) min_len = ev.data.len;
    }
    const total_args = args.len - 1;
    var stack_buf: [256]Value = undefined;
    const call_args_buf = if (total_args > 256)
        gc.allocator.alloc(Value, total_args) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..total_args];
    defer if (total_args > 256) gc.allocator.free(call_args_buf);
    var n: i64 = 0;
    for (0..min_len) |i| {
        call_args_buf[0] = vec.data[i];
        var arg_count: usize = 1;
        for (args[2..]) |extra| {
            const ev = types.toVector(extra);
            call_args_buf[arg_count] = ev.data[i];
            arg_count += 1;
        }
        const result = try callVM(pred, call_args_buf[0..arg_count]);
        if (types.isTruthy(result)) n += 1;
    }
    return types.makeFixnum(n);
}

// (vector-any pred v1 ...)
fn vectorAnyFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-any", "vector", args[1]);
    const vec = types.toVector(args[1]);
    const total_args = args.len - 1;
    var stack_buf: [256]Value = undefined;
    const call_args_buf = if (total_args > 256)
        gc.allocator.alloc(Value, total_args) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..total_args];
    defer if (total_args > 256) gc.allocator.free(call_args_buf);
    for (0..vec.data.len) |i| {
        call_args_buf[0] = vec.data[i];
        var arg_count: usize = 1;
        for (args[2..]) |extra| {
            if (!types.isVector(extra)) return primitives.typeError("vector-any", "vector", extra);
            const ev = types.toVector(extra);
            if (i >= ev.data.len) return types.FALSE;
            call_args_buf[arg_count] = ev.data[i];
            arg_count += 1;
        }
        const result = try callVM(pred, call_args_buf[0..arg_count]);
        if (types.isTruthy(result)) return result;
    }
    return types.FALSE;
}

// (vector-every pred v1 ...)
fn vectorEveryFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-every", "vector", args[1]);
    const vec = types.toVector(args[1]);
    const total_args = args.len - 1;
    var stack_buf: [256]Value = undefined;
    const call_args_buf = if (total_args > 256)
        gc.allocator.alloc(Value, total_args) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..total_args];
    defer if (total_args > 256) gc.allocator.free(call_args_buf);
    var last: Value = types.TRUE;
    for (0..vec.data.len) |i| {
        call_args_buf[0] = vec.data[i];
        var arg_count: usize = 1;
        for (args[2..]) |extra| {
            if (!types.isVector(extra)) return primitives.typeError("vector-every", "vector", extra);
            const ev = types.toVector(extra);
            if (i >= ev.data.len) return last;
            call_args_buf[arg_count] = ev.data[i];
            arg_count += 1;
        }
        const result = try callVM(pred, call_args_buf[0..arg_count]);
        if (!types.isTruthy(result)) return types.FALSE;
        last = result;
    }
    return last;
}

// (vector-index pred v1 ...)
fn vectorIndexFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-index", "vector", args[1]);
    const vec = types.toVector(args[1]);
    const total_args = args.len - 1;
    var stack_buf: [256]Value = undefined;
    const call_args_buf = if (total_args > 256)
        gc.allocator.alloc(Value, total_args) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..total_args];
    defer if (total_args > 256) gc.allocator.free(call_args_buf);
    for (0..vec.data.len) |i| {
        call_args_buf[0] = vec.data[i];
        var arg_count: usize = 1;
        for (args[2..]) |extra| {
            if (!types.isVector(extra)) return primitives.typeError("vector-index", "vector", extra);
            const ev = types.toVector(extra);
            if (i >= ev.data.len) return types.FALSE;
            call_args_buf[arg_count] = ev.data[i];
            arg_count += 1;
        }
        const result = try callVM(pred, call_args_buf[0..arg_count]);
        if (types.isTruthy(result)) return types.makeFixnum(@intCast(i));
    }
    return types.FALSE;
}

// (vector-index-right pred v1 ...)
fn vectorIndexRightFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-index-right", "vector", args[1]);
    const vec = types.toVector(args[1]);
    var min_len: usize = vec.data.len;
    for (args[2..]) |extra| {
        if (!types.isVector(extra)) return primitives.typeError("vector-index-right", "vector", extra);
        const ev = types.toVector(extra);
        if (ev.data.len < min_len) min_len = ev.data.len;
    }
    const total_args = args.len - 1;
    var stack_buf: [256]Value = undefined;
    const call_args_buf = if (total_args > 256)
        gc.allocator.alloc(Value, total_args) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..total_args];
    defer if (total_args > 256) gc.allocator.free(call_args_buf);
    var i = min_len;
    while (i > 0) {
        i -= 1;
        call_args_buf[0] = vec.data[i];
        var arg_count: usize = 1;
        for (args[2..]) |extra| {
            const ev = types.toVector(extra);
            call_args_buf[arg_count] = ev.data[i];
            arg_count += 1;
        }
        const result = try callVM(pred, call_args_buf[0..arg_count]);
        if (types.isTruthy(result)) return types.makeFixnum(@intCast(i));
    }
    return types.FALSE;
}

// (vector-skip pred v1 ...) — index of first element NOT satisfying pred
fn vectorSkipFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-skip", "vector", args[1]);
    const vec = types.toVector(args[1]);
    for (0..vec.data.len) |i| {
        const call_args_buf = [1]Value{vec.data[i]};
        const result = try callVM(pred, &call_args_buf);
        if (!types.isTruthy(result)) return types.makeFixnum(@intCast(i));
    }
    return types.FALSE;
}

// (vector-skip-right pred v1 ...)
fn vectorSkipRightFn(args: []const Value) PrimitiveError!Value {
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-skip-right", "vector", args[1]);
    const vec = types.toVector(args[1]);
    var i = vec.data.len;
    while (i > 0) {
        i -= 1;
        const call_args_buf = [1]Value{vec.data[i]};
        const result = try callVM(pred, &call_args_buf);
        if (!types.isTruthy(result)) return types.makeFixnum(@intCast(i));
    }
    return types.FALSE;
}

// (vector-swap! vec i j)
fn vectorSwapFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-swap!", "vector", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("vector-swap!", "exact non-negative integer", args[1]);
    if (!types.isFixnum(args[2])) return primitives.typeError("vector-swap!", "exact non-negative integer", args[2]);
    const vec = types.toVector(args[0]);
    const i_raw = types.toFixnum(args[1]);
    const j_raw = types.toFixnum(args[2]);
    if (i_raw < 0) return primitives.typeError("vector-swap!", "exact non-negative integer", args[1]);
    if (j_raw < 0) return primitives.typeError("vector-swap!", "exact non-negative integer", args[2]);
    const i: usize = @intCast(i_raw);
    const j: usize = @intCast(j_raw);
    if (i >= vec.data.len) return primitives.typeError("vector-swap!", "valid index", args[1]);
    if (j >= vec.data.len) return primitives.typeError("vector-swap!", "valid index", args[2]);
    const tmp = vec.data[i];
    vec.data[i] = vec.data[j];
    vec.data[j] = tmp;
    return types.VOID;
}

// (vector-reverse! vec [start [end]])
fn vectorReverseBangFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-reverse!", "vector", args[0]);
    const vec = types.toVector(args[0]);
    const range = try primitives.parseOptionalRange(args, 1, vec.data.len, "vector-reverse!");
    var lo = range.start;
    var hi = range.end;
    while (lo < hi) {
        hi -= 1;
        const tmp = vec.data[lo];
        vec.data[lo] = vec.data[hi];
        vec.data[hi] = tmp;
        lo += 1;
    }
    return types.VOID;
}

// (vector-reverse-copy vec [start [end]])
fn vectorReverseCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isVector(args[0])) return primitives.typeError("vector-reverse-copy", "vector", args[0]);
    const vec = types.toVector(args[0]);
    const range = try primitives.parseOptionalRange(args, 1, vec.data.len, "vector-reverse-copy");
    const len = range.end - range.start;
    const new_data = gc.allocator.alloc(Value, len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_data);
    for (0..len) |i| {
        new_data[i] = vec.data[range.end - 1 - i];
    }
    return gc.allocVector(new_data) catch return PrimitiveError.OutOfMemory;
}

// (vector-unfold f length [seeds ...])
fn vectorUnfoldFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const f = args[0];
    if (!types.isFixnum(args[1])) return primitives.typeError("vector-unfold", "exact non-negative integer", args[1]);
    const len_val = types.toFixnum(args[1]);
    if (len_val < 0) return primitives.typeError("vector-unfold", "exact non-negative integer", args[1]);
    const length: usize = @intCast(len_val);

    var seeds: std.ArrayList(Value) = .empty;
    defer seeds.deinit(gc.allocator);
    for (args[2..]) |s| {
        seeds.append(gc.allocator, s) catch return PrimitiveError.OutOfMemory;
    }

    const new_data = gc.allocator.alloc(Value, length) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_data);

    const scope = gc.rootedScope();
    defer scope.release();

    const call_count = 1 + seeds.items.len;
    var stack_buf: [257]Value = undefined;
    const call_args_buf = if (call_count > 257)
        gc.allocator.alloc(Value, call_count) catch return PrimitiveError.OutOfMemory
    else
        stack_buf[0..call_count];
    defer if (call_count > 257) gc.allocator.free(call_args_buf);

    for (0..length) |i| {
        call_args_buf[0] = types.makeFixnum(@intCast(i));
        for (seeds.items, 0..) |s, j| {
            call_args_buf[1 + j] = s;
        }
        const result = try callVM(f, call_args_buf);
        // Result should be (values elem new-seed1 new-seed2 ...)
        if (types.isMultipleValues(result)) {
            const mv = types.toObject(result).as(types.MultipleValues);
            if (mv.values.len == 0) return primitives.typeError("vector-unfold", "at least one return value from step procedure", result);
            new_data[i] = mv.values[0];
            for (0..seeds.items.len) |j| {
                if (j + 1 < mv.values.len) {
                    seeds.items[j] = mv.values[j + 1];
                }
            }
        } else {
            new_data[i] = result;
        }
        gc.extra_roots.append(gc.allocator, new_data[i]) catch return PrimitiveError.OutOfMemory;
        for (seeds.items) |s| {
            gc.extra_roots.append(gc.allocator, s) catch return PrimitiveError.OutOfMemory;
        }
    }
    return gc.allocVector(new_data) catch return PrimitiveError.OutOfMemory;
}

// (vector-unfold-right f length [seeds ...])
fn vectorUnfoldRightFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const f = args[0];
    if (!types.isFixnum(args[1])) return primitives.typeError("vector-unfold-right", "exact non-negative integer", args[1]);
    const len_val = types.toFixnum(args[1]);
    if (len_val < 0) return primitives.typeError("vector-unfold-right", "exact non-negative integer", args[1]);
    const length: usize = @intCast(len_val);

    var seeds: std.ArrayList(Value) = .empty;
    defer seeds.deinit(gc.allocator);
    for (args[2..]) |s| {
        seeds.append(gc.allocator, s) catch return PrimitiveError.OutOfMemory;
    }

    const new_data = gc.allocator.alloc(Value, length) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_data);

    const scope = gc.rootedScope();
    defer scope.release();

    const call_count = 1 + seeds.items.len;
    var stack_buf_r: [257]Value = undefined;
    const call_args_buf = if (call_count > 257)
        gc.allocator.alloc(Value, call_count) catch return PrimitiveError.OutOfMemory
    else
        stack_buf_r[0..call_count];
    defer if (call_count > 257) gc.allocator.free(call_args_buf);

    // Fill from right to left (index length-1 down to 0)
    var i = length;
    while (i > 0) {
        i -= 1;
        call_args_buf[0] = types.makeFixnum(@intCast(i));
        for (seeds.items, 0..) |s, j| {
            call_args_buf[1 + j] = s;
        }
        const result = try callVM(f, call_args_buf);
        if (types.isMultipleValues(result)) {
            const mv = types.toObject(result).as(types.MultipleValues);
            if (mv.values.len == 0) return primitives.typeError("vector-unfold-right", "at least one return value from step procedure", result);
            new_data[i] = mv.values[0];
            for (mv.values[1..], 0..) |v, si| {
                if (si < seeds.items.len) seeds.items[si] = v;
            }
        } else {
            new_data[i] = result;
        }
        gc.extra_roots.append(gc.allocator, new_data[i]) catch return PrimitiveError.OutOfMemory;
        for (seeds.items) |s| {
            gc.extra_roots.append(gc.allocator, s) catch return PrimitiveError.OutOfMemory;
        }
    }
    return gc.allocVector(new_data) catch return PrimitiveError.OutOfMemory;
}

// (vector-binary-search vec value cmp) — binary search, returns index or #f
fn vectorBinarySearchFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return primitives.typeError("vector-binary-search", "vector", args[0]);
    const vec = types.toVector(args[0]);
    const value = args[1];
    const cmp = args[2];

    var lo: usize = 0;
    var hi: usize = vec.data.len;

    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const result = try callVM(cmp, &[2]Value{ vec.data[mid], value });
        if (!types.isFixnum(result)) return primitives.typeError("vector-binary-search", "integer from comparator", result);
        const c = types.toFixnum(result);
        if (c == 0) return types.makeFixnum(@intCast(mid));
        if (c < 0) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return types.FALSE;
}

// (vector-concatenate list-of-vectors)
fn vectorConcatenateFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var current = args[0];
    var total_len: usize = 0;
    // First pass: compute total length
    var tmp = current;
    while (tmp != types.NIL) {
        if (!types.isPair(tmp)) return primitives.typeError("vector-concatenate", "proper list", args[0]);
        const v = types.car(tmp);
        if (!types.isVector(v)) return primitives.typeError("vector-concatenate", "vector", v);
        total_len += types.toVector(v).data.len;
        tmp = types.cdr(tmp);
    }
    const new_data = gc.allocator.alloc(Value, total_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_data);
    var pos: usize = 0;
    while (current != types.NIL) {
        const v = types.toVector(types.car(current));
        @memcpy(new_data[pos .. pos + v.data.len], v.data);
        pos += v.data.len;
        current = types.cdr(current);
    }
    return gc.allocVector(new_data) catch return PrimitiveError.OutOfMemory;
}

// (vector-cumulate f knil vec)
fn vectorCumulateFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const f = args[0];
    var acc = args[1];
    if (!types.isVector(args[2])) return primitives.typeError("vector-cumulate", "vector", args[2]);
    const vec = types.toVector(args[2]);
    const new_data = gc.allocator.alloc(Value, vec.data.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_data);
    const scope = gc.rootedScope();
    defer scope.release();
    for (0..vec.data.len) |i| {
        const call_args_buf = [2]Value{ acc, vec.data[i] };
        acc = try callVM(f, &call_args_buf);
        new_data[i] = acc;
        gc.extra_roots.append(gc.allocator, acc) catch return PrimitiveError.OutOfMemory;
    }
    return gc.allocVector(new_data) catch return PrimitiveError.OutOfMemory;
}

// (vector-partition pred vec)
fn vectorPartitionFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const pred = args[0];
    if (!types.isVector(args[1])) return primitives.typeError("vector-partition", "vector", args[1]);
    const vec = types.toVector(args[1]);
    var yes: std.ArrayList(Value) = .empty;
    defer yes.deinit(gc.allocator);
    var no: std.ArrayList(Value) = .empty;
    defer no.deinit(gc.allocator);

    // The predicate runs arbitrary Scheme and may mutate `vec`, displacing an
    // element whose only remaining reference is the yes/no accumulator. Those
    // lists are invisible to the GC, so root every classified element to keep
    // it alive across later predicate calls (which can trigger collection).
    const scope = gc.rootedScope();
    defer scope.release();

    for (vec.data) |elem| {
        const call_args_buf = [1]Value{elem};
        const result = try callVM(pred, &call_args_buf);
        if (types.isTruthy(result)) {
            yes.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        } else {
            no.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
        }
        gc.extra_roots.append(gc.allocator, elem) catch return PrimitiveError.OutOfMemory;
    }

    const combined = gc.allocator.alloc(Value, yes.items.len + no.items.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(combined);
    @memcpy(combined[0..yes.items.len], yes.items);
    @memcpy(combined[yes.items.len..], no.items);
    var result_vec = gc.allocVector(combined) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&result_vec);
    defer gc.popRoot();
    const count_val = types.makeFixnum(@intCast(yes.items.len));

    const vals = [2]Value{ result_vec, count_val };
    return gc.allocMultipleValues(&vals) catch return PrimitiveError.OutOfMemory;
}

fn vectorAppendSubvectorsFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len % 3 != 0) return primitives.typeError("vector-append-subvectors", "multiple of 3 arguments", types.makeFixnum(@intCast(args.len)));

    var total: usize = 0;
    var i: usize = 0;
    while (i < args.len) : (i += 3) {
        if (!types.isVector(args[i])) return primitives.typeError("vector-append-subvectors", "vector", args[i]);
        if (!types.isFixnum(args[i + 1])) return primitives.typeError("vector-append-subvectors", "integer", args[i + 1]);
        if (!types.isFixnum(args[i + 2])) return primitives.typeError("vector-append-subvectors", "integer", args[i + 2]);
        const s = types.toFixnum(args[i + 1]);
        const e = types.toFixnum(args[i + 2]);
        if (s < 0) return primitives.typeError("vector-append-subvectors", "non-negative integer", args[i + 1]);
        if (e < 0) return primitives.typeError("vector-append-subvectors", "non-negative integer", args[i + 2]);
        const start: usize = @intCast(s);
        const end: usize = @intCast(e);
        const vec_len = types.toVector(args[i]).data.len;
        if (start > vec_len) return primitives.indexError("vector-append-subvectors", s, vec_len);
        if (end > vec_len) return primitives.indexError("vector-append-subvectors", e, vec_len);
        if (end < start) return primitives.typeError("vector-append-subvectors", "valid range (end >= start)", args[i + 2]);
        total += end - start;
    }

    const result_data = gc.allocator.alloc(Value, total) catch return PrimitiveError.OutOfMemory;
    var pos: usize = 0;
    i = 0;
    while (i < args.len) : (i += 3) {
        const vec = types.toVector(args[i]);
        const start: usize = @intCast(types.toFixnum(args[i + 1]));
        const end: usize = @intCast(types.toFixnum(args[i + 2]));
        @memcpy(result_data[pos .. pos + (end - start)], vec.data[start..end]);
        pos += end - start;
    }
    defer gc.allocator.free(result_data);
    return gc.allocVector(result_data) catch return PrimitiveError.OutOfMemory;
}
