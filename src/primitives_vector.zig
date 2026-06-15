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

pub fn registerVector(vm: *vm_mod.VM) !void {
    try reg(vm, "vector", &vectorFn, .{ .variadic = 0 });
    try reg(vm, "make-vector", &makeVectorFn, .{ .variadic = 1 });
    try reg(vm, "vector?", &vectorP, .{ .exact = 1 });
    try reg(vm, "vector-length", &vectorLengthFn, .{ .exact = 1 });
    try reg(vm, "vector-ref", &vectorRefFn, .{ .exact = 2 });
    try reg(vm, "vector-set!", &vectorSetFn, .{ .exact = 3 });
    try reg(vm, "vector->list", &vectorToListFn, .{ .variadic = 1 });
    try reg(vm, "list->vector", &listToVectorFn, .{ .exact = 1 });
    try reg(vm, "vector-fill!", &vectorFillFn, .{ .exact = 2 });
    try reg(vm, "vector-copy", &vectorCopyFn, .{ .variadic = 1 });
    try reg(vm, "vector-copy!", &vectorCopyBangFn, .{ .variadic = 3 });
    try reg(vm, "vector-append", &vectorAppendFn, .{ .variadic = 0 });
    try reg(vm, "vector-for-each", &vectorForEachFn, .{ .variadic = 2 });
    try reg(vm, "vector-map", &vectorMapFn, .{ .variadic = 2 });
    try reg(vm, "vector->string", &vectorToStringFn, .{ .exact = 1 });
}

// ---------------------------------------------------------------------------
// (vector e1 e2 ...) — create a vector from arguments
// ---------------------------------------------------------------------------

fn vectorFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocVector(args) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (make-vector k) or (make-vector k fill)
// ---------------------------------------------------------------------------

fn makeVectorFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const k = types.toFixnum(args[0]);
    if (k < 0) return PrimitiveError.TypeError;
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
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    const vec = types.toVector(args[0]);
    return types.makeFixnum(@intCast(vec.data.len));
}

// ---------------------------------------------------------------------------
// (vector-ref v k)
// ---------------------------------------------------------------------------

fn vectorRefFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const vec = types.toVector(args[0]);
    const k = types.toFixnum(args[1]);
    if (k < 0 or @as(usize, @intCast(k)) >= vec.data.len) return PrimitiveError.TypeError;
    return vec.data[@intCast(k)];
}

// ---------------------------------------------------------------------------
// (vector-set! v k obj)
// ---------------------------------------------------------------------------

fn vectorSetFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const vec = types.toVector(args[0]);
    const k = types.toFixnum(args[1]);
    if (k < 0 or @as(usize, @intCast(k)) >= vec.data.len) return PrimitiveError.TypeError;
    vec.data[@intCast(k)] = args[2];
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (vector->list v) or (vector->list v start) or (vector->list v start end)
// ---------------------------------------------------------------------------

fn vectorToListFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    const vec = types.toVector(args[0]);
    const len = vec.data.len;

    var start: usize = 0;
    var end: usize = len;

    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[1]);
        if (s < 0 or @as(usize, @intCast(s)) > len) return PrimitiveError.TypeError;
        start = @intCast(s);
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[2]);
        if (e < 0 or @as(usize, @intCast(e)) > len) return PrimitiveError.TypeError;
        end = @intCast(e);
    }
    if (start > end) return PrimitiveError.TypeError;

    var result: Value = types.NIL;
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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Count elements
    var count: usize = 0;
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
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
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    const vec = types.toVector(args[0]);
    @memset(vec.data, args[1]);
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (vector-copy v) or (vector-copy v start) or (vector-copy v start end)
// ---------------------------------------------------------------------------

fn vectorCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    const vec = types.toVector(args[0]);
    const len = vec.data.len;

    var start: usize = 0;
    var end: usize = len;

    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[1]);
        if (s < 0 or @as(usize, @intCast(s)) > len) return PrimitiveError.TypeError;
        start = @intCast(s);
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[2]);
        if (e < 0 or @as(usize, @intCast(e)) > len) return PrimitiveError.TypeError;
        end = @intCast(e);
    }
    if (start > end) return PrimitiveError.TypeError;

    return gc.allocVector(vec.data[start..end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (vector-copy! to at from) or (vector-copy! to at from start) or
// (vector-copy! to at from start end)
// ---------------------------------------------------------------------------

fn vectorCopyBangFn(args: []const Value) PrimitiveError!Value {
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    if (!types.isVector(args[2])) return PrimitiveError.TypeError;

    const to_vec = types.toVector(args[0]);
    const at_val = types.toFixnum(args[1]);
    if (at_val < 0) return PrimitiveError.TypeError;
    const at: usize = @intCast(at_val);
    const from_vec = types.toVector(args[2]);
    const from_len = from_vec.data.len;

    var start: usize = 0;
    var end: usize = from_len;

    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return PrimitiveError.TypeError;
        const s = types.toFixnum(args[3]);
        if (s < 0 or @as(usize, @intCast(s)) > from_len) return PrimitiveError.TypeError;
        start = @intCast(s);
    }
    if (args.len > 4) {
        if (!types.isFixnum(args[4])) return PrimitiveError.TypeError;
        const e = types.toFixnum(args[4]);
        if (e < 0 or @as(usize, @intCast(e)) > from_len) return PrimitiveError.TypeError;
        end = @intCast(e);
    }
    if (start > end) return PrimitiveError.TypeError;

    const count = end - start;
    if (at + count > to_vec.data.len) return PrimitiveError.TypeError;

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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Calculate total length
    var total: usize = 0;
    for (args) |a| {
        if (!types.isVector(a)) return PrimitiveError.TypeError;
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
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    // Validate all vector arguments and find minimum length
    const vec_count = args.len - 1;
    if (vec_count == 0) return PrimitiveError.TypeError;

    var min_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        if (!types.isVector(a)) return PrimitiveError.TypeError;
        const vlen = types.toVector(a).data.len;
        if (vlen < min_len) min_len = vlen;
    }

    // Iterate over elements
    var call_args: [256]Value = undefined;
    for (0..min_len) |i| {
        // Build argument list: one element from each vector
        for (0..vec_count) |vi| {
            call_args[vi] = types.toVector(args[1 + vi]).data[i];
        }

        _ = vm.callWithArgs(proc, call_args[0..vec_count]) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
    }

    return types.VOID;
}

// ---------------------------------------------------------------------------
// (vector-map proc v1 v2 ...)
// ---------------------------------------------------------------------------

fn vectorMapFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    // Validate all vector arguments and find minimum length
    const vec_count = args.len - 1;
    if (vec_count == 0) return PrimitiveError.TypeError;

    var min_len: usize = std.math.maxInt(usize);
    for (args[1..]) |a| {
        if (!types.isVector(a)) return PrimitiveError.TypeError;
        const vlen = types.toVector(a).data.len;
        if (vlen < min_len) min_len = vlen;
    }

    // Allocate result buffer
    const results = gc.allocator.alloc(Value, min_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(results);

    var call_args: [256]Value = undefined;
    for (0..min_len) |i| {
        // Build argument list: one element from each vector
        for (0..vec_count) |vi| {
            call_args[vi] = types.toVector(args[1 + vi]).data[i];
        }

        results[i] = vm.callWithArgs(proc, call_args[0..vec_count]) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
    }

    return gc.allocVector(results) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (vector->string v) — convert vector of characters to string
// ---------------------------------------------------------------------------

fn vectorToStringFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isVector(args[0])) return PrimitiveError.TypeError;
    const vec = types.toVector(args[0]);

    // Calculate UTF-8 length
    var utf8_len: usize = 0;
    for (vec.data) |elem| {
        if (!types.isChar(elem)) return PrimitiveError.TypeError;
        const cp = types.toChar(elem);
        utf8_len += std.unicode.utf8CodepointSequenceLength(cp) catch return PrimitiveError.TypeError;
    }

    // Build string
    const buf = gc.allocator.alloc(u8, utf8_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);
    var pos: usize = 0;
    for (vec.data) |elem| {
        const cp = types.toChar(elem);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch return PrimitiveError.TypeError;
        @memcpy(buf[pos .. pos + n], tmp[0..n]);
        pos += n;
    }

    return gc.allocString(buf[0..pos]) catch return PrimitiveError.OutOfMemory;
}
