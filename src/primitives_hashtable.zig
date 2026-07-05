const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const HashTable = types.HashTable;
const HashEntry = types.HashEntry;

pub fn registerHashTable(vm: *vm_mod.VM) !void {
    try primitives.reg(vm, "make-hash-table", &makeHashTableFn, .{ .variadic = 0 });
    try primitives.reg(vm, "hash-table?", &hashTablePFn, .{ .exact = 1 });
    try primitives.reg(vm, "hash-table-ref", &hashTableRefFn, .{ .variadic = 2 });
    try primitives.reg(vm, "hash-table-set!", &hashTableSetFn, .{ .exact = 3 });
    try primitives.reg(vm, "hash-table-delete!", &hashTableDeleteFn, .{ .exact = 2 });
    try primitives.reg(vm, "hash-table-exists?", &hashTableExistsFn, .{ .exact = 2 });
    try primitives.reg(vm, "hash-table-size", &hashTableSizeFn, .{ .exact = 1 });
    try primitives.reg(vm, "hash-table-keys", &hashTableKeysFn, .{ .exact = 1 });
    try primitives.reg(vm, "hash-table-values", &hashTableValuesFn, .{ .exact = 1 });
    try primitives.reg(vm, "hash-table-walk", &hashTableWalkFn, .{ .exact = 2 });
    try primitives.reg(vm, "hash-table->alist", &hashTableToAlistFn, .{ .exact = 1 });
    try primitives.reg(vm, "alist->hash-table", &alistToHashTableFn, .{ .variadic = 1 });
    try primitives.reg(vm, "hash-table-copy", &hashTableCopyFn, .{ .exact = 1 });
    try primitives.reg(vm, "hash-table-update!/default", &hashTableUpdateDefaultFn, .{ .exact = 4 });
    try primitives.reg(vm, "hash", &hashFn, .{ .variadic = 1 });
    try primitives.reg(vm, "string-hash", &stringHashFn, .{ .variadic = 1 });
    try primitives.reg(vm, "string-ci-hash", &stringCiHashFn, .{ .variadic = 1 });
    try primitives.reg(vm, "hash-by-identity", &hashByIdentityFn, .{ .variadic = 1 });
    try primitives.reg(vm, "hash-table-ref/default", &hashTableRefDefaultFn, .{ .exact = 3 });
    try primitives.reg(vm, "hash-table-fold", &hashTableFoldFn, .{ .exact = 3 });
    try primitives.reg(vm, "hash-table-merge!", &hashTableMergeFn, .{ .exact = 2 });
    try primitives.reg(vm, "hash-table-equivalence-function", &hashTableEquivFn, .{ .exact = 1 });
    try primitives.reg(vm, "hash-table-hash-function", &hashTableHashFn, .{ .exact = 1 });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn getHashTable(proc: []const u8, v: Value) PrimitiveError!*HashTable {
    if (!types.isHashTable(v)) return primitives.typeError(proc, "hash-table", v);
    return types.toHashTable(v);
}

const GC = memory.GC;

fn snapshotLiveEntries(gc: *GC, ht: *HashTable) ?[]HashEntry {
    if (ht.count == 0) return gc.allocator.alloc(HashEntry, 0) catch return null;
    const buf = gc.allocator.alloc(HashEntry, ht.count) catch return null;
    var idx: usize = 0;
    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.state == .occupied) {
            buf[idx] = entry;
            idx += 1;
            if (idx >= ht.count) break;
        }
    }
    return buf[0..idx];
}

pub fn valueHash(key: Value) usize {
    return valueHashDepth(key, 0);
}

const MAX_HASH_DEPTH = 8;

fn valueHashDepth(key: Value, depth: usize) usize {
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
    if (depth >= MAX_HASH_DEPTH) return @truncate(key *% 2654435761);
    if (types.isPair(key)) {
        const h1 = valueHashDepth(types.car(key), depth + 1);
        const h2 = valueHashDepth(types.cdr(key), depth + 1);
        return h1 *% 31 +% h2;
    }
    if (types.isVector(key)) {
        const vec = types.toObject(key).as(types.Vector);
        var h: usize = vec.data.len *% 2654435761;
        const limit = @min(vec.data.len, 4);
        for (vec.data[0..limit]) |v| h = h *% 31 +% valueHashDepth(v, depth + 1);
        return h;
    }
    if (types.isBytevector(key)) {
        const bv = types.toBytevector(key);
        var h: usize = bv.data.len *% 2654435761;
        for (bv.data) |b| h = h *% 31 +% b;
        return h;
    }
    return @truncate(key *% 2654435761);
}

fn findKey(ht: *HashTable, key: Value) ?usize {
    if (ht.capacity == 0) return null;
    const mask = ht.capacity - 1;
    var idx = valueHash(key) & mask;
    var probes: usize = 0;
    while (probes < ht.capacity) {
        const entry = &ht.entries[idx];
        if (entry.state == .empty) return null;
        if (entry.state == .occupied and primitives.deepEqual(entry.key, key)) return idx;
        idx = (idx + 1) & mask;
        probes += 1;
    }
    return null;
}

fn findSlot(ht: *HashTable, key: Value) struct { idx: usize, found: bool } {
    const mask = ht.capacity - 1;
    var idx = valueHash(key) & mask;
    var first_tombstone: ?usize = null;
    var probes: usize = 0;
    while (probes < ht.capacity) {
        const entry = &ht.entries[idx];
        if (entry.state == .empty) {
            return .{ .idx = first_tombstone orelse idx, .found = false };
        }
        if (entry.state == .tombstone) {
            if (first_tombstone == null) first_tombstone = idx;
        } else if (primitives.deepEqual(entry.key, key)) {
            return .{ .idx = idx, .found = true };
        }
        idx = (idx + 1) & mask;
        probes += 1;
    }
    return .{ .idx = first_tombstone orelse 0, .found = false };
}

fn rehash(ht: *HashTable) PrimitiveError!void {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const new_cap = if (ht.capacity == 0) 8 else ht.capacity * 2;
    const new_entries = gc.allocator.alloc(HashEntry, new_cap) catch return PrimitiveError.OutOfMemory;
    for (new_entries) |*e| {
        e.* = .{ .key = 0, .value = 0, .state = .empty };
    }
    const old_entries = ht.entries;
    const old_cap = ht.capacity;
    ht.entries = new_entries;
    ht.capacity = new_cap;
    ht.count = 0;
    for (old_entries[0..old_cap]) |entry| {
        if (entry.state == .occupied) {
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
                return primitives.mapVMError(err);
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
    if (memory.gc_instance) |gc| {
        gc.writeBarrier(types.toObject(args[0]), args[1]);
        gc.writeBarrier(types.toObject(args[0]), args[2]);
    }
    if (slot.found) {
        ht.entries[slot.idx].value = args[2];
    } else {
        ht.entries[slot.idx] = .{ .key = args[1], .value = args[2], .state = .occupied };
        ht.count += 1;
    }
    return types.VOID;
}

// (hash-table-delete! ht key)
fn hashTableDeleteFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-delete!", args[0]);
    if (findKey(ht, args[1])) |idx| {
        ht.entries[idx].state = .tombstone;
        ht.entries[idx].key = 0;
        ht.entries[idx].value = 0;
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-keys", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.state == .occupied) {
            result = gc.allocPair(entry.key, result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

// (hash-table-values ht)
fn hashTableValuesFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-values", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.state == .occupied) {
            result = gc.allocPair(entry.value, result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

// (hash-table-walk ht proc) — call (proc key value) for each entry
fn hashTableWalkFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-walk", args[0]);
    const proc = args[1];

    const snapshot = snapshotLiveEntries(gc, ht) orelse return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(snapshot);

    for (snapshot) |entry| {
        const call_args = [2]Value{ entry.key, entry.value };
        _ = vm.callWithArgs(proc, &call_args) catch |err| {
            return primitives.mapVMError(err);
        };
    }
    return types.VOID;
}

// (hash-table->alist ht)
fn hashTableToAlistFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table->alist", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
    for (ht.entries[0..ht.capacity]) |entry| {
        if (entry.state == .occupied) {
            var pair = gc.allocPair(entry.key, entry.value) catch return PrimitiveError.OutOfMemory;
            gc.pushRoot(&pair);
            result = gc.allocPair(pair, result) catch {
                gc.popRoot();
                return PrimitiveError.OutOfMemory;
            };
            gc.popRoot();
        }
    }
    return result;
}

// (alist->hash-table alist) or (alist->hash-table alist equal-proc hash-proc)
// The optional comparator/hash args are accepted and ignored, like make-hash-table.
fn alistToHashTableFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
            ht.entries[slot.idx] = .{ .key = key, .value = value, .state = .occupied };
            ht.count += 1;
        }
        current = types.cdr(current);
    }
    return ht_val;
}

// (hash-table-copy ht)
fn hashTableCopyFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
        return primitives.mapVMError(err);
    };

    try growIfNeeded(ht);
    const slot = findSlot(ht, key);
    if (memory.gc_instance) |gc| {
        gc.writeBarrier(types.toObject(args[0]), key);
        gc.writeBarrier(types.toObject(args[0]), new_val);
    }
    if (slot.found) {
        ht.entries[slot.idx].value = new_val;
    } else {
        ht.entries[slot.idx] = .{ .key = key, .value = new_val, .state = .occupied };
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-fold", args[0]);
    const proc = args[1];
    var acc = args[2];

    gc.pushRoot(&acc);
    defer gc.popRoot();

    const snapshot = snapshotLiveEntries(gc, ht) orelse return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(snapshot);

    for (snapshot) |entry| {
        const call_args = [3]Value{ entry.key, entry.value, acc };
        acc = vm.callWithArgs(proc, &call_args) catch |err| {
            return primitives.mapVMError(err);
        };
    }
    return acc;
}

// (hash-table-merge! ht1 ht2)
fn hashTableMergeFn(args: []const Value) PrimitiveError!Value {
    const ht1 = try getHashTable("hash-table-merge!", args[0]);
    const ht2 = try getHashTable("hash-table-merge!", args[1]);
    if (ht1 == ht2) return args[0];

    const gc = memory.gc_instance;
    for (ht2.entries[0..ht2.capacity]) |entry| {
        if (entry.state != .occupied) continue;
        const slot = findSlot(ht1, entry.key);
        if (gc) |g| {
            g.writeBarrier(types.toObject(args[0]), entry.key);
            g.writeBarrier(types.toObject(args[0]), entry.value);
        }
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

fn hashTableEquivFn(args: []const Value) PrimitiveError!Value {
    _ = try getHashTable("hash-table-equivalence-function", args[0]);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: infrastructure guard
    vm.lockGlobalsShared();
    defer vm.unlockGlobalsShared();
    return vm.globals.get("equal?") orelse return PrimitiveError.TypeError; // bare-ok: infrastructure guard
}

fn hashTableHashFn(args: []const Value) PrimitiveError!Value {
    _ = try getHashTable("hash-table-hash-function", args[0]);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: infrastructure guard
    vm.lockGlobalsShared();
    defer vm.unlockGlobalsShared();
    return vm.globals.get("hash") orelse return PrimitiveError.TypeError; // bare-ok: infrastructure guard
}
