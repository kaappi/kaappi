const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const bignum_mod = @import("bignum.zig");
const char_mod = @import("primitives_char.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;
const HashTable = types.HashTable;
const HashEntry = types.HashEntry;
const CompareMode = types.CompareMode;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "make-hash-table", .func = &makeHashTableFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table?", .func = &hashTablePFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-ref", .func = &hashTableRefFn, .arity = .{ .variadic = 2 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-set!", .func = &hashTableSetFn, .arity = .{ .exact = 3 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-delete!", .func = &hashTableDeleteFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-exists?", .func = &hashTableExistsFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-size", .func = &hashTableSizeFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-keys", .func = &hashTableKeysFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-values", .func = &hashTableValuesFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-walk", .func = &hashTableWalkFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table->alist", .func = &hashTableToAlistFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "alist->hash-table", .func = &alistToHashTableFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-copy", .func = &hashTableCopyFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-update!", .func = &hashTableUpdateFn, .arity = .{ .variadic = 3 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-update!/default", .func = &hashTableUpdateDefaultFn, .arity = .{ .exact = 4 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash", .func = &hashFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "string-hash", .func = &stringHashFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "string-ci-hash", .func = &stringCiHashFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-by-identity", .func = &hashByIdentityFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-ref/default", .func = &hashTableRefDefaultFn, .arity = .{ .exact = 3 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-fold", .func = &hashTableFoldFn, .arity = .{ .exact = 3 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-merge!", .func = &hashTableMergeFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-equivalence-function", .func = &hashTableEquivFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
    .{ .name = "hash-table-hash-function", .func = &hashTableHashFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_69) },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn getHashTable(proc: []const u8, v: Value) PrimitiveError!*HashTable {
    if (!types.isHashTable(v)) return primitives.typeError(proc, "hash-table", v);
    return types.toHashTable(v);
}

const GC = memory.GC;

// ---------------------------------------------------------------------------
// Compare mode detection and dispatch
// ---------------------------------------------------------------------------

fn detectMode(equiv_val: Value) CompareMode {
    if (types.isNativeFn(equiv_val)) {
        const nf = types.toNativeFn(equiv_val);
        if (std.mem.eql(u8, nf.name, "eq?")) return .eq;
        if (std.mem.eql(u8, nf.name, "eqv?")) return .eqv;
        if (std.mem.eql(u8, nf.name, "equal?")) return .equal;
        if (std.mem.eql(u8, nf.name, "string=?")) return .string_eq;
        if (std.mem.eql(u8, nf.name, "string-ci=?")) return .string_ci;
    }
    return .custom;
}

fn lookupGlobal(vm: *vm_mod.VM, name: []const u8) Value {
    vm.lockGlobalsShared();
    defer vm.unlockGlobalsShared();
    return vm.globals.get(name) orelse 0;
}

fn defaultHashName(mode: CompareMode) []const u8 {
    return switch (mode) {
        .eq => "hash-by-identity",
        .string_eq => "string-hash",
        .string_ci => "string-ci-hash",
        else => "hash",
    };
}

fn extractComparatorFns(val: Value) ?struct { equiv: Value, hash_fn: Value } {
    if (!types.isPointer(val)) return null;
    const obj = types.toObject(val);
    if (obj.tag != .record_instance) return null;
    const ri = obj.as(types.RecordInstance);
    if (!std.mem.eql(u8, ri.record_type.name, "<comparator>")) return null;
    if (ri.fields.len < 4) return null;
    return .{ .equiv = ri.fields[1], .hash_fn = ri.fields[3] };
}

fn configureHashTable(ht: *HashTable, ht_val: Value, gc: *GC, vm: *vm_mod.VM, args: []const Value) void {
    if (args.len > 0) {
        var equiv_val = args[0];
        var hash_val: Value = 0;
        var has_hash = args.len > 1;
        if (has_hash) hash_val = args[1];

        if (extractComparatorFns(args[0])) |cmp| {
            equiv_val = cmp.equiv;
            if (!has_hash) {
                hash_val = cmp.hash_fn;
                has_hash = true;
            }
        }

        ht.compare_mode = detectMode(equiv_val);
        ht.equiv_fn = equiv_val;
        gc.writeBarrier(types.toObject(ht_val), equiv_val);
        if (has_hash) {
            ht.hash_fn = hash_val;
            gc.writeBarrier(types.toObject(ht_val), hash_val);
        } else {
            ht.hash_fn = lookupGlobal(vm, defaultHashName(ht.compare_mode));
            gc.writeBarrier(types.toObject(ht_val), ht.hash_fn);
        }
    } else {
        ht.equiv_fn = lookupGlobal(vm, "equal?");
        ht.hash_fn = lookupGlobal(vm, "hash");
        gc.writeBarrier(types.toObject(ht_val), ht.equiv_fn);
        gc.writeBarrier(types.toObject(ht_val), ht.hash_fn);
    }
}

fn eqvEqual(a: Value, b: Value) bool {
    if (a == b) return true;
    if ((types.isBignum(a) or types.isFixnum(a)) and (types.isBignum(b) or types.isFixnum(b))) {
        if (types.isBignum(a) or types.isBignum(b)) {
            return bignum_mod.compare(a, b) == 0;
        }
    }
    if (types.isRationalObj(a) and types.isRationalObj(b)) {
        const ra = types.toRational(a);
        const rb = types.toRational(b);
        return eqvEqual(ra.numerator, rb.numerator) and eqvEqual(ra.denominator, rb.denominator);
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
    return false;
}

fn stringBytesOrNull(v: Value) ?[]const u8 {
    if (!types.isString(v)) return null;
    const s = types.toObject(v).as(types.SchemeString);
    return s.data[0..s.len];
}

fn equalForTable(ht: *HashTable, a: Value, b: Value) PrimitiveError!bool {
    return switch (ht.compare_mode) {
        .equal => primitives.deepEqual(a, b),
        .eq => a == b,
        .eqv => eqvEqual(a, b),
        .string_eq => blk: {
            const sa = stringBytesOrNull(a) orelse return PrimitiveError.TypeError;
            const sb = stringBytesOrNull(b) orelse return PrimitiveError.TypeError;
            break :blk std.mem.eql(u8, sa, sb);
        },
        .string_ci => blk: {
            const sa = stringBytesOrNull(a) orelse return PrimitiveError.TypeError;
            const sb = stringBytesOrNull(b) orelse return PrimitiveError.TypeError;
            break :blk char_mod.foldCompareStrings(sa, sb) == .eq;
        },
        .custom => blk: {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
            const call_args = [2]Value{ a, b };
            const result = vm.callWithArgs(ht.equiv_fn, &call_args) catch |err| {
                return err;
            };
            break :blk types.isTruthy(result);
        },
    };
}

fn identityHash(key: Value) usize {
    return @truncate(key *% 2654435761);
}

fn stringContentHash(data: []const u8) usize {
    var h: usize = 0;
    for (data) |c| h = h *% 31 +% c;
    return h;
}

fn stringCiContentHash(data: []const u8) usize {
    var h: usize = 0;
    var pos: usize = 0;
    while (pos < data.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(data[pos]) catch {
            h = h *% 31 +% data[pos];
            pos += 1;
            continue;
        };
        if (pos + seq_len > data.len) break;
        const cp = std.unicode.utf8Decode(data[pos .. pos + seq_len]) catch {
            h = h *% 31 +% data[pos];
            pos += 1;
            continue;
        };
        const folded = char_mod.charFoldcase(cp);
        h = h *% 31 +% folded;
        pos += seq_len;
    }
    return h;
}

fn hashForTable(ht: *HashTable, key: Value) PrimitiveError!usize {
    return switch (ht.compare_mode) {
        .equal, .eqv => valueHash(key),
        .eq => identityHash(key),
        .string_eq => blk: {
            const data = stringBytesOrNull(key) orelse return PrimitiveError.TypeError;
            break :blk stringContentHash(data);
        },
        .string_ci => blk: {
            const data = stringBytesOrNull(key) orelse return PrimitiveError.TypeError;
            break :blk stringCiContentHash(data);
        },
        .custom => blk: {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
            const call_args = [1]Value{key};
            const result = vm.callWithArgs(ht.hash_fn, &call_args) catch |err| {
                return err;
            };
            if (types.isFixnum(result)) {
                const v = types.toFixnum(result);
                break :blk @as(usize, @intCast(if (v < 0) -v else v));
            }
            break :blk @truncate(@as(u64, result) *% 2654435761);
        },
    };
}

pub fn hashForMode(mode: CompareMode, key: Value) usize {
    return switch (mode) {
        .equal, .eqv => valueHash(key),
        .eq => identityHash(key),
        .string_eq => stringContentHash(stringBytesOrNull(key) orelse return identityHash(key)),
        .string_ci => stringCiContentHash(stringBytesOrNull(key) orelse return identityHash(key)),
        .custom => valueHash(key),
    };
}

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
    if (types.isFlonum(key)) {
        return @truncate(key *% 2654435761);
    }
    if (types.isBignum(key)) {
        const bn = types.toObject(key).as(types.Bignum);
        var h: usize = if (bn.positive) @as(usize, 0) else @as(usize, 1);
        for (bn.limbs[0..bn.len]) |limb| h = h *% 31 +% @as(usize, @truncate(limb));
        return h;
    }
    if (types.isRationalObj(key)) {
        const r = types.toRational(key);
        const h1 = valueHashDepth(r.numerator, depth + 1);
        const h2 = valueHashDepth(r.denominator, depth + 1);
        return h1 *% 31 +% h2;
    }
    if (types.isComplex(key)) {
        const c = types.toComplex(key);
        const hr: usize = @truncate(@as(u64, @bitCast(c.real)) *% 2654435761);
        const hi: usize = @truncate(@as(u64, @bitCast(c.imag)) *% 2654435761);
        return hr *% 31 +% hi;
    }
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

fn findKey(ht: *HashTable, key: Value) PrimitiveError!?usize {
    if (ht.capacity == 0) return null;
    const mask = ht.capacity - 1;
    var idx = (try hashForTable(ht, key)) & mask;
    var probes: usize = 0;
    while (probes < ht.capacity) {
        const entry = &ht.entries[idx];
        if (entry.state == .empty) return null;
        if (entry.state == .occupied and try equalForTable(ht, entry.key, key)) return idx;
        idx = (idx + 1) & mask;
        probes += 1;
    }
    return null;
}

const FindSlotResult = struct { idx: usize, found: bool };

fn findSlot(ht: *HashTable, key: Value) PrimitiveError!FindSlotResult {
    const mask = ht.capacity - 1;
    var idx = (try hashForTable(ht, key)) & mask;
    var first_tombstone: ?usize = null;
    var probes: usize = 0;
    while (probes < ht.capacity) {
        const entry = &ht.entries[idx];
        if (entry.state == .empty) {
            return .{ .idx = first_tombstone orelse idx, .found = false };
        }
        if (entry.state == .tombstone) {
            if (first_tombstone == null) first_tombstone = idx;
        } else if (try equalForTable(ht, entry.key, key)) {
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
    const old_count = ht.count;
    ht.entries = new_entries;
    ht.capacity = new_cap;
    ht.count = 0;
    const mask = new_cap - 1;
    for (old_entries[0..old_cap]) |entry| {
        if (entry.state == .occupied) {
            const h = hashForTable(ht, entry.key) catch |err| {
                ht.entries = old_entries;
                ht.capacity = old_cap;
                ht.count = old_count;
                gc.allocator.free(new_entries);
                return err;
            };
            var idx = h & mask;
            while (new_entries[idx].state == .occupied) {
                idx = (idx + 1) & mask;
            }
            new_entries[idx] = entry;
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

// (make-hash-table) or (make-hash-table equal-proc [hash-proc])
fn makeHashTableFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const ht_val = gc.allocHashTable(8) catch return PrimitiveError.OutOfMemory;
    const ht = types.toHashTable(ht_val);
    configureHashTable(ht, ht_val, gc, vm, args);
    return ht_val;
}

// (hash-table? obj)
fn hashTablePFn(args: []const Value) PrimitiveError!Value {
    return if (types.isHashTable(args[0])) types.TRUE else types.FALSE;
}

// (hash-table-ref ht key) or (hash-table-ref ht key default)
fn hashTableRefFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-ref", args[0]);
    if (try findKey(ht, args[1])) |idx| {
        return ht.entries[idx].value;
    }
    // Key not found — call thunk if provided
    if (args.len > 2) {
        if (types.isProcedure(args[2])) {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
            return vm.callWithArgs(args[2], &[_]Value{}) catch |err| {
                return err;
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
    const slot = try findSlot(ht, args[1]);
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
    if (try findKey(ht, args[1])) |idx| {
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
    return if ((try findKey(ht, args[1])) != null) types.TRUE else types.FALSE;
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

    // Root all entries up front: the first callback can delete+allocate and
    // free a not-yet-visited entry's key/value that only the snapshot holds.
    const scope = gc.rootedScope();
    defer scope.release();
    for (snapshot) |entry| {
        gc.extra_roots.append(gc.allocator, entry.key) catch return PrimitiveError.OutOfMemory;
        gc.extra_roots.append(gc.allocator, entry.value) catch return PrimitiveError.OutOfMemory;
    }

    for (snapshot) |entry| {
        const call_args = [2]Value{ entry.key, entry.value };
        _ = vm.callWithArgs(proc, &call_args) catch |err| {
            return err;
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

// (alist->hash-table alist) or (alist->hash-table alist equal-proc [hash-proc])
fn alistToHashTableFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
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
    configureHashTable(ht, ht_val, gc, vm, args[1..]);

    while (current != types.NIL) {
        const entry_pair = types.car(current);
        if (!types.isPair(entry_pair)) return primitives.typeError("alist->hash-table", "pair", entry_pair);
        const key = types.car(entry_pair);
        const value = types.cdr(entry_pair);

        // Only add if key not already present (first occurrence wins)
        const slot = try findSlot(ht, key);
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
    dst.compare_mode = src.compare_mode;
    dst.equiv_fn = src.equiv_fn;
    dst.hash_fn = src.hash_fn;
    gc.writeBarrier(types.toObject(dst_val), dst.equiv_fn);
    gc.writeBarrier(types.toObject(dst_val), dst.hash_fn);
    return dst_val;
}

// (hash-table-update! ht key function [thunk])
fn hashTableUpdateFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-update!", args[0]);
    const key = args[1];
    const proc = args[2];

    const old_val = if (try findKey(ht, key)) |idx|
        ht.entries[idx].value
    else if (args.len > 3) blk: {
        break :blk vm.callWithArgs(args[3], &[_]Value{}) catch |err| {
            return err;
        };
    } else {
        return primitives.typeError("hash-table-update!", "key to be present or thunk", key);
    };

    const call_args = [1]Value{old_val};
    const new_val = vm.callWithArgs(proc, &call_args) catch |err| {
        return err;
    };

    try growIfNeeded(ht);
    const slot = try findSlot(ht, key);
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

// (hash-table-update!/default ht key proc default)
fn hashTableUpdateDefaultFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const ht = try getHashTable("hash-table-update!/default", args[0]);
    const key = args[1];
    const proc = args[2];
    const default_val = args[3];

    const old_val = if (try findKey(ht, key)) |idx|
        ht.entries[idx].value
    else
        default_val;

    const call_args = [1]Value{old_val};
    const new_val = vm.callWithArgs(proc, &call_args) catch |err| {
        return err;
    };

    try growIfNeeded(ht);
    const slot = try findSlot(ht, key);
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
    if (try findKey(ht, args[1])) |idx| {
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

    // Root all entries up front: the first callback can delete+allocate and
    // free a not-yet-visited entry's key/value that only the snapshot holds.
    const scope = gc.rootedScope();
    defer scope.release();
    for (snapshot) |entry| {
        gc.extra_roots.append(gc.allocator, entry.key) catch return PrimitiveError.OutOfMemory;
        gc.extra_roots.append(gc.allocator, entry.value) catch return PrimitiveError.OutOfMemory;
    }

    for (snapshot) |entry| {
        const call_args = [3]Value{ entry.key, entry.value, acc };
        acc = vm.callWithArgs(proc, &call_args) catch |err| {
            return err;
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
        const slot = try findSlot(ht1, entry.key);
        if (gc) |g| {
            g.writeBarrier(types.toObject(args[0]), entry.key);
            g.writeBarrier(types.toObject(args[0]), entry.value);
        }
        if (slot.found) {
            ht1.entries[slot.idx].value = entry.value;
        } else {
            try growIfNeeded(ht1);
            const new_slot = try findSlot(ht1, entry.key);
            ht1.entries[new_slot.idx] = entry;
            ht1.count += 1;
        }
    }
    return args[0];
}

fn hashTableEquivFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-equivalence-function", args[0]);
    if (ht.equiv_fn != 0) return ht.equiv_fn;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    return lookupGlobal(vm, "equal?");
}

fn hashTableHashFn(args: []const Value) PrimitiveError!Value {
    const ht = try getHashTable("hash-table-hash-function", args[0]);
    if (ht.hash_fn != 0) return ht.hash_fn;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    return lookupGlobal(vm, "hash");
}
