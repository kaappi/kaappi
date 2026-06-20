const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const HashTable = types.HashTable;
const HashEntry = types.HashEntry;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerHashTable(vm: *vm_mod.VM) !void {
    try reg(vm, "make-hash-table", &makeHashTableFn, .{ .variadic = 0 });
    try reg(vm, "hash-table?", &hashTablePFn, .{ .exact = 1 });
    try reg(vm, "hash-table-ref", &hashTableRefFn, .{ .variadic = 2 });
    try reg(vm, "hash-table-set!", &hashTableSetFn, .{ .exact = 3 });
    try reg(vm, "hash-table-delete!", &hashTableDeleteFn, .{ .exact = 2 });
    try reg(vm, "hash-table-exists?", &hashTableExistsFn, .{ .exact = 2 });
    try reg(vm, "hash-table-size", &hashTableSizeFn, .{ .exact = 1 });
    try reg(vm, "hash-table-keys", &hashTableKeysFn, .{ .exact = 1 });
    try reg(vm, "hash-table-values", &hashTableValuesFn, .{ .exact = 1 });
    try reg(vm, "hash-table-walk", &hashTableWalkFn, .{ .exact = 2 });
    try reg(vm, "hash-table->alist", &hashTableToAlistFn, .{ .exact = 1 });
    try reg(vm, "alist->hash-table", &alistToHashTableFn, .{ .exact = 1 });
    try reg(vm, "hash-table-copy", &hashTableCopyFn, .{ .exact = 1 });
    try reg(vm, "hash-table-update!/default", &hashTableUpdateDefaultFn, .{ .exact = 4 });
    try reg(vm, "hash", &hashFn, .{ .variadic = 1 });
    try reg(vm, "string-hash", &stringHashFn, .{ .variadic = 1 });
    try reg(vm, "string-ci-hash", &stringCiHashFn, .{ .variadic = 1 });
    try reg(vm, "hash-by-identity", &hashByIdentityFn, .{ .variadic = 1 });
    try reg(vm, "hash-table-ref/default", &hashTableRefDefaultFn, .{ .exact = 3 });
    try reg(vm, "hash-table-fold", &hashTableFoldFn, .{ .exact = 3 });
    try reg(vm, "hash-table-merge!", &hashTableMergeFn, .{ .exact = 2 });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn getHashTable(v: Value) PrimitiveError!*HashTable {
    if (!types.isHashTable(v)) return PrimitiveError.TypeError;
    return types.toHashTable(v);
}

/// Find index of key in entries, or null if not found.
fn findKey(ht: *HashTable, key: Value) ?usize {
    for (ht.entries[0..ht.count], 0..) |entry, i| {
        if (primitives.deepEqual(entry.key, key)) return i;
    }
    return null;
}

fn growIfNeeded(ht: *HashTable) PrimitiveError!void {
    if (ht.count < ht.capacity) return;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const new_cap = if (ht.capacity == 0) 8 else ht.capacity * 2;
    const new_entries = gc.allocator.alloc(HashEntry, new_cap) catch return PrimitiveError.OutOfMemory;
    if (ht.count > 0) {
        @memcpy(new_entries[0..ht.count], ht.entries[0..ht.count]);
    }
    if (ht.capacity > 0) {
        gc.allocator.free(ht.entries);
    }
    ht.entries = new_entries;
    ht.capacity = new_cap;
}

// ---------------------------------------------------------------------------
// Procedures
// ---------------------------------------------------------------------------

// (make-hash-table) or (make-hash-table equal-proc hash-proc)
fn makeHashTableFn(args: []const Value) PrimitiveError!Value {
    _ = args; // ignore optional comparator/hash args; we always use equal?
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocHashTable(8) catch return PrimitiveError.OutOfMemory;
}

// (hash-table? obj)
fn hashTablePFn(args: []const Value) PrimitiveError!Value {
    return if (types.isHashTable(args[0])) types.TRUE else types.FALSE;
}

// (hash-table-ref ht key) or (hash-table-ref ht key default)
fn hashTableRefFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable(args[0]);
    if (findKey(ht, args[1])) |idx| {
        return ht.entries[idx].value;
    }
    // Key not found — call thunk if provided
    if (args.len > 2) {
        if (types.isProcedure(args[2])) {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
            return vm.callWithArgs(args[2], &[_]Value{}) catch |err| {
                return switch (err) {
                    vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                    vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                    vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                    else => PrimitiveError.TypeError,
                };
            };
        }
        return args[2]; // non-procedure default (for backwards compat)
    }
    return PrimitiveError.TypeError; // no default, error
}

// (hash-table-set! ht key value)
fn hashTableSetFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable(args[0]);
    if (findKey(ht, args[1])) |idx| {
        ht.entries[idx].value = args[2];
    } else {
        try growIfNeeded(ht);
        ht.entries[ht.count] = .{ .key = args[1], .value = args[2] };
        ht.count += 1;
    }
    return types.VOID;
}

// (hash-table-delete! ht key)
fn hashTableDeleteFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable(args[0]);
    if (findKey(ht, args[1])) |idx| {
        // Swap with last element
        if (idx < ht.count - 1) {
            ht.entries[idx] = ht.entries[ht.count - 1];
        }
        ht.count -= 1;
    }
    return types.VOID;
}

// (hash-table-exists? ht key)
fn hashTableExistsFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable(args[0]);
    return if (findKey(ht, args[1]) != null) types.TRUE else types.FALSE;
}

// (hash-table-size ht)
fn hashTableSizeFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable(args[0]);
    return types.makeFixnum(@intCast(ht.count));
}

// (hash-table-keys ht)
fn hashTableKeysFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable(args[0]);
    var result: Value = types.NIL;
    var i = ht.count;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(ht.entries[i].key, result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// (hash-table-values ht)
fn hashTableValuesFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable(args[0]);
    var result: Value = types.NIL;
    var i = ht.count;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(ht.entries[i].value, result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

// (hash-table-walk ht proc) — call (proc key value) for each entry
fn hashTableWalkFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable(args[0]);
    const proc = args[1];

    for (ht.entries[0..ht.count]) |entry| {
        const call_args = [2]Value{ entry.key, entry.value };
        _ = vm.callWithArgs(proc, &call_args) catch |err| {
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

// (hash-table->alist ht)
fn hashTableToAlistFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable(args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i = ht.count;
    while (i > 0) {
        i -= 1;
        var pair = gc.allocPair(ht.entries[i].key, ht.entries[i].value) catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&pair) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(pair, result) catch {
            gc.popRoot();
            return PrimitiveError.OutOfMemory;
        };
        gc.popRoot();
    }
    return result;
}

// (alist->hash-table alist)
fn alistToHashTableFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var current = args[0];

    // Count entries first
    var count: usize = 0;
    var tmp = current;
    while (tmp != types.NIL) {
        if (!types.isPair(tmp)) return PrimitiveError.TypeError;
        count += 1;
        tmp = types.cdr(tmp);
    }

    const initial_cap = @max(count, @as(usize, 8));
    const ht_val = gc.allocHashTable(initial_cap) catch return PrimitiveError.OutOfMemory;
    const ht = types.toHashTable(ht_val);

    while (current != types.NIL) {
        const entry_pair = types.car(current);
        if (!types.isPair(entry_pair)) return PrimitiveError.TypeError;
        const key = types.car(entry_pair);
        const value = types.cdr(entry_pair);

        // Only add if key not already present (first occurrence wins)
        if (findKey(ht, key) == null) {
            ht.entries[ht.count] = .{ .key = key, .value = value };
            ht.count += 1;
        }
        current = types.cdr(current);
    }
    return ht_val;
}

// (hash-table-copy ht)
fn hashTableCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const src = try getHashTable(args[0]);
    const cap = @max(src.count, @as(usize, 8));
    const dst_val = gc.allocHashTable(cap) catch return PrimitiveError.OutOfMemory;
    const dst = types.toHashTable(dst_val);
    @memcpy(dst.entries[0..src.count], src.entries[0..src.count]);
    dst.count = src.count;
    return dst_val;
}

// (hash-table-update!/default ht key proc default)
fn hashTableUpdateDefaultFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable(args[0]);
    const key = args[1];
    const proc = args[2];
    const default_val = args[3];

    const old_val = if (findKey(ht, key)) |idx|
        ht.entries[idx].value
    else
        default_val;

    const call_args = [1]Value{old_val};
    const new_val = vm.callWithArgs(proc, &call_args) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    if (findKey(ht, key)) |idx| {
        ht.entries[idx].value = new_val;
    } else {
        try growIfNeeded(ht);
        ht.entries[ht.count] = .{ .key = key, .value = new_val };
        ht.count += 1;
    }
    return types.VOID;
}

// (hash obj [bound]) — generic hash function
fn hashFn(args: []const Value) PrimitiveError!Value {
    const h = valueHash(args[0]);
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return PrimitiveError.TypeError;
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

fn valueHash(v: Value) u64 {
    if (types.isFixnum(v)) {
        const n: u64 = @bitCast(types.toFixnum(v));
        return n *% 2654435761;
    }
    if (types.isString(v)) {
        const str_obj = types.toObject(v).as(types.SchemeString);
        const data = str_obj.data[0..str_obj.len];
        var h: u64 = 0;
        for (data) |c| {
            h = h *% 31 +% c;
        }
        return h;
    }
    if (v == types.TRUE) return 1;
    if (v == types.FALSE) return 0;
    if (v == types.NIL) return 2;
    if (types.isSymbol(v)) {
        const sym = types.toObject(v).as(types.Symbol);
        var h: u64 = 5381;
        for (sym.name) |c| {
            h = h *% 33 +% c;
        }
        return h;
    }
    if (types.isChar(v)) {
        return @as(u64, types.toChar(v)) *% 2654435761;
    }
    // Fallback: use bit pattern
    const bits: u64 = @bitCast(v);
    return bits *% 2654435761;
}

// (string-hash s [bound])
fn stringHashFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const str_obj = types.toObject(args[0]).as(types.SchemeString);
    const str = str_obj.data[0..str_obj.len];
    var h: u64 = 0;
    for (str) |c| {
        h = h *% 31 +% c;
    }
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return PrimitiveError.TypeError;
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

// (string-ci-hash s [bound])
fn stringCiHashFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const char_mod = @import("primitives_char.zig");
    const str_obj = types.toObject(args[0]).as(types.SchemeString);
    const str = str_obj.data[0..str_obj.len];
    var h: u64 = 0;
    var pos: usize = 0;
    while (pos < str.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(str[pos]) catch {
            h = h *% 31 +% str[pos];
            pos += 1;
            continue;
        };
        if (pos + seq_len > str.len) break;
        const cp = std.unicode.utf8Decode(str[pos .. pos + seq_len]) catch {
            h = h *% 31 +% str[pos];
            pos += 1;
            continue;
        };
        const folded = char_mod.charFoldcase(cp);
        h = h *% 31 +% folded;
        pos += seq_len;
    }
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return PrimitiveError.TypeError;
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

// (hash-by-identity obj [bound])
fn hashByIdentityFn(args: []const Value) PrimitiveError!Value {
    const h: u64 = @bitCast(args[0]);
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return PrimitiveError.TypeError;
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

// (hash-table-ref/default ht key default)
fn hashTableRefDefaultFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable(args[0]);
    if (findKey(ht, args[1])) |idx| {
        return ht.entries[idx].value;
    }
    return args[2];
}

// (hash-table-fold ht f init) — fold over hash table entries
fn hashTableFoldFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable(args[0]);
    const proc = args[1];
    var acc = args[2];

    for (ht.entries[0..ht.count]) |entry| {
        const call_args = [3]Value{ entry.key, entry.value, acc };
        acc = vm.callWithArgs(proc, &call_args) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
    }
    return acc;
}

// (hash-table-merge! ht1 ht2)
fn hashTableMergeFn(args: []const Value) PrimitiveError!Value {
    const ht1 = try getHashTable(args[0]);
    const ht2 = try getHashTable(args[1]);

    for (ht2.entries[0..ht2.count]) |entry| {
        if (findKey(ht1, entry.key)) |idx| {
            ht1.entries[idx].value = entry.value;
        } else {
            try growIfNeeded(ht1);
            ht1.entries[ht1.count] = entry;
            ht1.count += 1;
        }
    }
    return args[0];
}
