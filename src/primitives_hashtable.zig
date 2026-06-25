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

fn getHashTable(proc: []const u8, v: Value) PrimitiveError!*HashTable {
    if (!types.isHashTable(v)) return primitives.typeError(proc, "hash-table", v);
    return types.toHashTable(v);
}

// Sentinels: VOID = empty slot, EOF = tombstone (deleted)
const EMPTY: Value = types.VOID;
const TOMBSTONE: Value = types.EOF;

fn valueHash(key: Value) usize {
    if (types.isFixnum(key)) {
        return @truncate(@as(u64, @bitCast(types.toFixnum(key))) *% 2654435761);
    }
    if (types.isString(key)) {
        const s = types.toObject(key).as(types.SchemeString);
        var h: usize = 0;
        for (s.data[0..s.len]) |c| h = h *% 31 +% c;
        return h;
    }
    if (types.isSymbol(key)) {
        const name = types.symbolName(key);
        var h: usize = 5381;
        for (name) |c| h = h *% 33 +% c;
        return h;
    }
    if (types.isChar(key)) {
        return @as(usize, types.toChar(key)) *% 2654435761;
    }
    if (key == types.TRUE) return 1;
    if (key == types.FALSE) return 0;
    if (key == types.NIL) return 2;
    return @truncate(key *% 2654435761);
}

/// Find bucket index of key, or null if not found.
fn findKey(ht: *HashTable, key: Value) ?usize {
    if (ht.capacity == 0) return null;
    const mask = ht.capacity - 1;
    var idx = valueHash(key) & mask;
    var probes: usize = 0;
    while (probes < ht.capacity) {
        const k = ht.entries[idx].key;
        if (k == EMPTY) return null; // empty slot = key not present
        if (k != TOMBSTONE and primitives.deepEqual(k, key)) return idx;
        idx = (idx + 1) & mask;
        probes += 1;
    }
    return null;
}

/// Find slot for insertion: returns index of matching key, first tombstone, or empty slot.
fn findSlot(ht: *HashTable, key: Value) struct { idx: usize, found: bool } {
    const mask = ht.capacity - 1;
    var idx = valueHash(key) & mask;
    var first_tombstone: ?usize = null;
    var probes: usize = 0;
    while (probes < ht.capacity) {
        const k = ht.entries[idx].key;
        if (k == EMPTY) {
            return .{ .idx = first_tombstone orelse idx, .found = false };
        }
        if (k == TOMBSTONE) {
            if (first_tombstone == null) first_tombstone = idx;
        } else if (primitives.deepEqual(k, key)) {
            return .{ .idx = idx, .found = true };
        }
        idx = (idx + 1) & mask;
        probes += 1;
    }
    return .{ .idx = first_tombstone orelse 0, .found = false };
}

fn rehash(ht: *HashTable) PrimitiveError!void {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const new_cap = if (ht.capacity == 0) 8 else ht.capacity * 2;
    const new_entries = gc.allocator.alloc(HashEntry, new_cap) catch return PrimitiveError.OutOfMemory;
    for (new_entries) |*e| {
        e.key = EMPTY;
        e.value = EMPTY;
    }
    const old_entries = ht.entries;
    const old_cap = ht.capacity;
    ht.entries = new_entries;
    ht.capacity = new_cap;
    ht.count = 0;
    // Re-insert all live entries
    for (old_entries[0..old_cap]) |entry| {
        if (entry.key != EMPTY and entry.key != TOMBSTONE) {
            const slot = findSlot(ht, entry.key);
            ht.entries[slot.idx] = entry;
            ht.count += 1;
        }
    }
    gc.allocator.free(old_entries);
}

fn growIfNeeded(ht: *HashTable) PrimitiveError!void {
    // Grow when load factor > 75% (count uses > 3/4 of capacity)
    if (ht.capacity == 0 or ht.count * 4 >= ht.capacity * 3) {
        try rehash(ht);
    }
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
    const ht = try getHashTable("hash-table-ref", args[0]);
    if (findKey(ht, args[1])) |idx| {
        return ht.entries[idx].value;
    }
    // Key not found — call thunk if provided
    if (args.len > 2) {
        if (types.isProcedure(args[2])) {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
            return vm.callWithArgs(args[2], &[_]Value{}) catch |err| {
                return switch (err) {
                    vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                    vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                    vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                    else => PrimitiveError.TypeError, // bare-ok: catch fallback
                };
            };
        }
        return args[2]; // non-procedure default (for backwards compat)
    }
    return primitives.typeError("hash-table-ref", "key to be present or default", args[1]); // no default, error
}

// (hash-table-set! ht key value)
fn hashTableSetFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-set!", args[0]);
    try growIfNeeded(ht);
    const slot = findSlot(ht, args[1]);
    if (slot.found) {
        ht.entries[slot.idx].value = args[2];
    } else {
        ht.entries[slot.idx] = .{ .key = args[1], .value = args[2] };
        ht.count += 1;
    }
    return types.VOID;
}

// (hash-table-delete! ht key)
fn hashTableDeleteFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-delete!", args[0]);
    if (findKey(ht, args[1])) |idx| {
        ht.entries[idx].key = TOMBSTONE;
        ht.entries[idx].value = EMPTY;
        ht.count -= 1;
    }
    return types.VOID;
}

// (hash-table-exists? ht key)
fn hashTableExistsFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-exists?", args[0]);
    return if (findKey(ht, args[1]) != null) types.TRUE else types.FALSE;
}

// (hash-table-size ht)
fn hashTableSizeFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-size", args[0]);
    return types.makeFixnum(@intCast(ht.count));
}

// (hash-table-keys ht)
fn hashTableKeysFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-keys", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.key != EMPTY and entry.key != TOMBSTONE) {
            result = gc.allocPair(entry.key, result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

// (hash-table-values ht)
fn hashTableValuesFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-values", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.key != EMPTY and entry.key != TOMBSTONE) {
            result = gc.allocPair(entry.value, result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

// (hash-table-walk ht proc) — call (proc key value) for each entry
fn hashTableWalkFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-walk", args[0]);
    const proc = args[1];

    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.key != EMPTY and entry.key != TOMBSTONE) {
            const call_args = [2]Value{ entry.key, entry.value };
            _ = vm.callWithArgs(proc, &call_args) catch |err| {
                return switch (err) {
                    vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                    vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                    vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                    else => PrimitiveError.TypeError, // bare-ok: catch fallback
                };
            };
        }
    }
    return types.VOID;
}

// (hash-table->alist ht)
fn hashTableToAlistFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table->alist", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.key != EMPTY and entry.key != TOMBSTONE) {
            var pair = gc.allocPair(entry.key, entry.value) catch return PrimitiveError.OutOfMemory;
            gc.pushRoot(&pair) catch return PrimitiveError.OutOfMemory;
            result = gc.allocPair(pair, result) catch {
                gc.popRoot();
                return PrimitiveError.OutOfMemory;
            };
            gc.popRoot();
        }
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
        if (!types.isPair(tmp)) return primitives.typeError("alist->hash-table", "pair", tmp);
        count += 1;
        tmp = types.cdr(tmp);
    }

    const initial_cap = @max(count, @as(usize, 8));
    const ht_val = gc.allocHashTable(initial_cap) catch return PrimitiveError.OutOfMemory;
    const ht = types.toHashTable(ht_val);

    while (current != types.NIL) {
        const entry_pair = types.car(current);
        if (!types.isPair(entry_pair)) return primitives.typeError("alist->hash-table", "pair", entry_pair);
        const key = types.car(entry_pair);
        const value = types.cdr(entry_pair);

        // Only add if key not already present (first occurrence wins)
        const slot = findSlot(ht, key);
        if (!slot.found) {
            ht.entries[slot.idx] = .{ .key = key, .value = value };
            ht.count += 1;
        }
        current = types.cdr(current);
    }
    return ht_val;
}

// (hash-table-copy ht)
fn hashTableCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const src = try getHashTable("hash-table-copy", args[0]);
    const dst_val = gc.allocHashTable(src.capacity) catch return PrimitiveError.OutOfMemory;
    const dst = types.toHashTable(dst_val);
    @memcpy(dst.entries[0..src.capacity], src.entries[0..src.capacity]);
    dst.count = src.count;
    return dst_val;
}

// (hash-table-update!/default ht key proc default)
fn hashTableUpdateDefaultFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-update!/default", args[0]);
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
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };

    try growIfNeeded(ht);
    const slot = findSlot(ht, key);
    if (slot.found) {
        ht.entries[slot.idx].value = new_val;
    } else {
        ht.entries[slot.idx] = .{ .key = key, .value = new_val };
        ht.count += 1;
    }
    return types.VOID;
}

// (hash obj [bound]) — generic hash function
fn hashFn(args: []const Value) PrimitiveError!Value {
    const h: u64 = valueHash(args[0]);
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("hash", "integer", args[1]);
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return primitives.typeError("hash", "positive integer", args[1]);
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

// (string-hash s [bound])
fn stringHashFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string-hash", "string", args[0]);
    const str_obj = types.toObject(args[0]).as(types.SchemeString);
    const str = str_obj.data[0..str_obj.len];
    var h: u64 = 0;
    for (str) |c| {
        h = h *% 31 +% c;
    }
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("string-hash", "integer", args[1]);
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return primitives.typeError("string-hash", "positive integer", args[1]);
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

// (string-ci-hash s [bound])
fn stringCiHashFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string-ci-hash", "string", args[0]);
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
        if (!types.isFixnum(args[1])) return primitives.typeError("string-ci-hash", "integer", args[1]);
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return primitives.typeError("string-ci-hash", "positive integer", args[1]);
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

// (hash-by-identity obj [bound])
fn hashByIdentityFn(args: []const Value) PrimitiveError!Value {
    const h: u64 = @bitCast(args[0]);
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("hash-by-identity", "integer", args[1]);
        const bound = types.toFixnum(args[1]);
        if (bound <= 0) return primitives.typeError("hash-by-identity", "positive integer", args[1]);
        return types.makeFixnum(@intCast(@mod(h, @as(u64, @intCast(bound)))));
    }
    return types.makeFixnum(@intCast(h & 0x3FFFFFFFFFFFFFFF));
}

// (hash-table-ref/default ht key default)
fn hashTableRefDefaultFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-ref/default", args[0]);
    if (findKey(ht, args[1])) |idx| {
        return ht.entries[idx].value;
    }
    return args[2];
}

// (hash-table-fold ht f init) — fold over hash table entries
fn hashTableFoldFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-fold", args[0]);
    const proc = args[1];
    var acc = args[2];

    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.key != EMPTY and entry.key != TOMBSTONE) {
            const call_args = [3]Value{ entry.key, entry.value, acc };
            acc = vm.callWithArgs(proc, &call_args) catch |err| {
                return switch (err) {
                    vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                    vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                    vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                    else => PrimitiveError.TypeError, // bare-ok: catch fallback
                };
            };
        }
    }
    return acc;
}

// (hash-table-merge! ht1 ht2)
fn hashTableMergeFn(args: []const Value) PrimitiveError!Value {
    const ht1 = try getHashTable("hash-table-merge!", args[0]);
    const ht2 = try getHashTable("hash-table-merge!", args[1]);

    for (ht2.entries[0..ht2.capacity]) |entry| {
        if (entry.key == EMPTY or entry.key == TOMBSTONE) continue;
        const slot = findSlot(ht1, entry.key);
        if (slot.found) {
            ht1.entries[slot.idx].value = entry.value;
        } else {
            try growIfNeeded(ht1);
            const new_slot = findSlot(ht1, entry.key);
            ht1.entries[new_slot.idx] = entry;
            ht1.count += 1;
        }
    }
    return args[0];
}
