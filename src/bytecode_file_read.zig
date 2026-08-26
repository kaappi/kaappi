//! Bytecode deserializer: `.sbc` bytes → Function graph.
//!
//! The read half of the `.sbc` codec. Every read path is defensive: a
//! malformed, truncated, or stale-build buffer returns null (a cache miss) or a
//! `CorruptedFile` error rather than trusting the bytes. Shares the format
//! contract (magic, version, constant tags, size limits, `compilerHash`) with
//! the serializer via `bytecode_file.zig`; see `bytecode_file_write.zig` for
//! the inverse.

const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const file_utils = @import("file_utils.zig");
const bf = @import("bytecode_file.zig");
const Value = types.Value;
const Function = types.Function;
const OpCode = types.OpCode;
const GC = memory.GC;
const BytecodeError = bf.BytecodeError;

// ---------------------------------------------------------------------------
// Read helpers
// ---------------------------------------------------------------------------

const Reader = struct {
    data: []const u8,
    pos: usize,

    fn readU8(self: *Reader) !u8 {
        if (self.pos >= self.data.len) return BytecodeError.CorruptedFile;
        const v = self.data[self.pos];
        self.pos += 1;
        return v;
    }

    fn readU16(self: *Reader) !u16 {
        if (self.pos + 2 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..2];
        self.pos += 2;
        return std.mem.littleToNative(u16, @bitCast(bytes.*));
    }

    fn readU32(self: *Reader) !u32 {
        if (self.pos + 4 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..4];
        self.pos += 4;
        return std.mem.littleToNative(u32, @bitCast(bytes.*));
    }

    fn readU64(self: *Reader) !u64 {
        if (self.pos + 8 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..8];
        self.pos += 8;
        return std.mem.littleToNative(u64, @bitCast(bytes.*));
    }

    fn readI64(self: *Reader) !i64 {
        if (self.pos + 8 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..8];
        self.pos += 8;
        return std.mem.littleToNative(i64, @bitCast(bytes.*));
    }

    fn readF64(self: *Reader) !f64 {
        if (self.pos + 8 > self.data.len) return BytecodeError.CorruptedFile;
        const bytes = self.data[self.pos..][0..8];
        self.pos += 8;
        const bits = std.mem.littleToNative(u64, @bitCast(bytes.*));
        return @bitCast(bits);
    }

    fn readBytes(self: *Reader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return BytecodeError.CorruptedFile;
        const result = self.data[self.pos..][0..len];
        self.pos += len;
        return result;
    }

    /// Reads a u16-length-prefixed header string, returning a slice that
    /// borrows `self.data` (valid as long as the backing buffer is).
    fn readStr(self: *Reader) ![]const u8 {
        const n = try self.readU16();
        if (n > bf.MAX_HEADER_STR_BYTES) return BytecodeError.CorruptedFile;
        return self.readBytes(n);
    }
};

fn freeBundledFiles(allocator: std.mem.Allocator, bf_map: *std.StringHashMap([]const u8)) void {
    var it = bf_map.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    bf_map.deinit();
}

fn freePreambleEntries(allocator: std.mem.Allocator, entries: [][]const u8, count: usize) void {
    for (0..count) |j| {
        allocator.free(entries[j]);
    }
    allocator.free(entries);
}

// ---------------------------------------------------------------------------
// Read constant
// ---------------------------------------------------------------------------

/// Decoded-object table for `TAG_BACKREF` (kaappi#2111): every
/// pair/string/vector/bytevector is appended at the same pre-order position
/// the writer assigned its id, so `shared.items[n]` is the object
/// `TAG_BACKREF n` names. Entries need no rooting of their own: an object is
/// registered only after being linked into (or while rooted as part of) the
/// constant under construction, whose spine is rooted, and completed
/// constants hang off functions rooted in `gc.extra_roots`.
const SharedTable = std.ArrayList(Value);

/// The `1`/`0` immutability byte v11 adds after the tag of the four mutable
/// literal types (kaappi#2110). The reader restores `Object.flags.immutable`
/// so a `set-car!` on a literal raises KP3002 warm exactly as it does cold.
fn readImmutableByte(r: *Reader) !bool {
    const v = try r.readU8();
    if (v > 1) return BytecodeError.CorruptedFile;
    return v != 0;
}

fn markImmutable(val: Value, immutable: bool) void {
    if (immutable) types.toObject(val).flags.immutable = true;
}

fn readConstant(r: *Reader, gc: *GC, all_funcs: []*Function, shared: *SharedTable, depth: u32) BytecodeError!Value {
    const tag = try r.readU8();
    return readConstantTagged(r, gc, all_funcs, shared, depth, tag);
}

/// `depth` counts nesting only — the cdr spine of a list is read iteratively
/// at constant depth, mirroring `writeConstant`, so both halves accept and
/// refuse exactly the same shapes (kaappi#2113).
fn readConstantTagged(r: *Reader, gc: *GC, all_funcs: []*Function, shared: *SharedTable, depth: u32, tag: u8) BytecodeError!Value {
    if (depth > bf.MAX_CONSTANT_DEPTH) return BytecodeError.CorruptedFile;
    switch (tag) {
        bf.TAG_FIXNUM => {
            const n = try r.readI64();
            if (n < -(1 << 47) or n >= (1 << 47)) return BytecodeError.CorruptedFile;
            return types.makeFixnum(n);
        },
        bf.TAG_FLONUM => {
            const f = try r.readF64();
            return types.makeFlonum(f);
        },
        bf.TAG_SYMBOL => {
            const name_len = try r.readU16();
            if (name_len > bf.MAX_SYMBOL_BYTES) return BytecodeError.CorruptedFile;
            const name = try r.readBytes(name_len);
            return gc.allocSymbol(name) catch return BytecodeError.OutOfMemory;
        },
        bf.TAG_STRING => {
            const immutable = try readImmutableByte(r);
            const data_len = try r.readU32();
            if (data_len > bf.MAX_STRING_BYTES) return BytecodeError.CorruptedFile;
            const data = try r.readBytes(data_len);
            const v = gc.allocString(data) catch return BytecodeError.OutOfMemory;
            markImmutable(v, immutable);
            shared.append(gc.allocator, v) catch return BytecodeError.OutOfMemory;
            return v;
        },
        bf.TAG_BOOLEAN => {
            const v = try r.readU8();
            if (v > 1) return BytecodeError.CorruptedFile;
            return if (v != 0) types.TRUE else types.FALSE;
        },
        bf.TAG_NIL => return types.NIL,
        bf.TAG_VOID => return types.VOID,
        bf.TAG_EOF => return types.EOF,
        bf.TAG_UNDEFINED => return types.UNDEFINED,
        bf.TAG_CHAR => {
            const cp = try r.readU32();
            if (cp > 0x10FFFF) return BytecodeError.CorruptedFile;
            if (cp >= 0xD800 and cp <= 0xDFFF) return BytecodeError.CorruptedFile;
            return types.makeChar(@intCast(cp));
        },
        bf.TAG_FUNCTION => {
            const idx = try r.readU32();
            if (idx >= all_funcs.len) return BytecodeError.CorruptedFile;
            return types.makePointer(&all_funcs[idx].header);
        },
        bf.TAG_CLOSURE => {
            // kaappi#1888: a procedural transformer's proc. The upvalue count
            // must match the inner function's own — the writer derived this
            // closure from it.
            const idx = try r.readU32();
            if (idx >= all_funcs.len) return BytecodeError.CorruptedFile;
            const func = all_funcs[idx];
            const count = try r.readU32();
            if (count != func.upvalue_count) return BytecodeError.CorruptedFile;
            var cls_val = gc.allocClosure(func) catch return BytecodeError.OutOfMemory;
            gc.pushRoot(&cls_val);
            defer gc.popRoot();
            const cls = types.toObject(cls_val).as(types.Closure);
            for (0..count) |i| {
                const uv = try readConstant(r, gc, all_funcs, shared, depth + 1);
                cls.upvalues[i] = uv;
                gc.writeBarrier(types.toObject(cls_val), uv);
            }
            return cls_val;
        },
        bf.TAG_PAIR => {
            // Allocate before reading children and register immediately, so a
            // back-reference inside this pair's own subtree — a cycle — can
            // resolve to it. Fields are filled as each child completes, which
            // is also what keeps every registered object transitively rooted
            // while later children allocate.
            const head_immutable = try readImmutableByte(r);
            var head = gc.allocPair(types.NIL, types.NIL) catch return BytecodeError.OutOfMemory;
            markImmutable(head, head_immutable);
            shared.append(gc.allocator, head) catch return BytecodeError.OutOfMemory;
            gc.pushRoot(&head);
            defer gc.popRoot();
            var cur = head;
            while (true) {
                const car_val = try readConstant(r, gc, all_funcs, shared, depth + 1);
                types.toObject(cur).as(types.Pair).car = car_val;
                gc.writeBarrier(types.toObject(cur), car_val);
                const cdr_tag = try r.readU8();
                if (cdr_tag == bf.TAG_PAIR) {
                    // Continue the spine iteratively, mirroring the writer.
                    const next_immutable = try readImmutableByte(r);
                    const next = gc.allocPair(types.NIL, types.NIL) catch return BytecodeError.OutOfMemory;
                    markImmutable(next, next_immutable);
                    shared.append(gc.allocator, next) catch return BytecodeError.OutOfMemory;
                    types.toObject(cur).as(types.Pair).cdr = next;
                    gc.writeBarrier(types.toObject(cur), next);
                    cur = next;
                    continue;
                }
                const cdr_val = try readConstantTagged(r, gc, all_funcs, shared, depth + 1, cdr_tag);
                types.toObject(cur).as(types.Pair).cdr = cdr_val;
                gc.writeBarrier(types.toObject(cur), cdr_val);
                return head;
            }
        },
        bf.TAG_VECTOR => {
            const immutable = try readImmutableByte(r);
            const len = try r.readU32();
            if (len > bf.MAX_VECTOR_LEN) return BytecodeError.CorruptedFile;
            var vec_val = gc.allocVectorFill(len, types.NIL) catch return BytecodeError.OutOfMemory;
            markImmutable(vec_val, immutable);
            shared.append(gc.allocator, vec_val) catch return BytecodeError.OutOfMemory;
            gc.pushRoot(&vec_val);
            defer gc.popRoot();
            for (0..len) |i| {
                const elem = try readConstant(r, gc, all_funcs, shared, depth + 1);
                const vec = types.toVector(vec_val);
                vec.data[i] = elem;
                gc.writeBarrier(types.toObject(vec_val), elem);
            }
            return vec_val;
        },
        bf.TAG_BYTEVECTOR => {
            const immutable = try readImmutableByte(r);
            const len = try r.readU32();
            if (len > bf.MAX_BYTEVECTOR_LEN) return BytecodeError.CorruptedFile;
            const data = try r.readBytes(len);
            const v = gc.allocBytevector(data) catch return BytecodeError.OutOfMemory;
            markImmutable(v, immutable);
            shared.append(gc.allocator, v) catch return BytecodeError.OutOfMemory;
            return v;
        },
        bf.TAG_BIGNUM => {
            const positive = (try r.readU8()) != 0;
            const len = try r.readU32();
            if (len == 0 or len > bf.MAX_BIGNUM_LIMBS) return BytecodeError.CorruptedFile;
            const allocator = gc.allocator;
            const limbs = allocator.alloc(u64, len) catch return BytecodeError.OutOfMemory;
            defer allocator.free(limbs);
            for (0..len) |i| {
                limbs[i] = try r.readU64();
            }
            if (limbs[len - 1] == 0) return BytecodeError.CorruptedFile;
            return gc.allocBignumFromLimbs(limbs, len, positive) catch return BytecodeError.OutOfMemory;
        },
        bf.TAG_RATIONAL => {
            const num = try readConstant(r, gc, all_funcs, shared, depth + 1);
            if (!types.isFixnum(num) and !types.isBignum(num)) return BytecodeError.CorruptedFile;
            var num_root = num;
            gc.pushRoot(&num_root);
            defer gc.popRoot();
            const den = try readConstant(r, gc, all_funcs, shared, depth + 1);
            if (!types.isFixnum(den) and !types.isBignum(den)) return BytecodeError.CorruptedFile;
            if (types.isFixnum(den) and types.toFixnum(den) == 0) return BytecodeError.CorruptedFile;
            if (types.isBignum(den) and types.toBignum(den).len == 0) return BytecodeError.CorruptedFile;
            return gc.allocRational(num_root, den) catch return BytecodeError.OutOfMemory;
        },
        bf.TAG_COMPLEX => {
            const real = try readConstant(r, gc, all_funcs, shared, depth + 1);
            if (!isRealConstant(real)) return BytecodeError.CorruptedFile;
            var real_root = real;
            gc.pushRoot(&real_root);
            defer gc.popRoot();
            const imag = try readConstant(r, gc, all_funcs, shared, depth + 1);
            if (!isRealConstant(imag)) return BytecodeError.CorruptedFile;
            return gc.allocComplex(real_root, imag) catch return BytecodeError.OutOfMemory;
        },
        bf.TAG_BACKREF => {
            const id = try r.readU32();
            if (id >= shared.items.len) return BytecodeError.CorruptedFile;
            return shared.items[id];
        },
        else => return BytecodeError.InvalidConstantTag,
    }
}

/// A component Value a deserialized Complex may hold: any real number
/// (fixnum/bignum/rational/flonum), never a complex.
fn isRealConstant(v: Value) bool {
    return types.isFixnum(v) or types.isFlonum(v) or types.isBignum(v) or types.isRationalObj(v);
}

// ---------------------------------------------------------------------------
// Bytecode validation
// ---------------------------------------------------------------------------

fn readU16FromCode(code: []const u8, ip: *usize) BytecodeError!u16 {
    if (ip.* + 2 > code.len) return BytecodeError.CorruptedFile;
    const hi: u16 = code[ip.*];
    const lo: u16 = code[ip.* + 1];
    ip.* += 2;
    return (hi << 8) | lo;
}

fn readI16FromCode(code: []const u8, ip: *usize) BytecodeError!i16 {
    return @bitCast(try readU16FromCode(code, ip));
}

fn validateSymbolConstant(func: *Function, idx: u16) BytecodeError!void {
    if (idx >= func.constants.items.len) return BytecodeError.CorruptedFile;
    if (!types.isSymbol(func.constants.items[idx])) return BytecodeError.CorruptedFile;
}

fn validateFunctionBytecode(func: *Function) BytecodeError!void {
    const code = func.code.items;
    var ip: usize = 0;
    while (ip < code.len) {
        const raw = code[ip];
        if (raw > @intFromEnum(OpCode.tail_eval)) return BytecodeError.CorruptedFile;
        const op: OpCode = @enumFromInt(raw);
        ip += 1;

        switch (op) {
            .load_const => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // dst
                const idx = try readU16FromCode(code, &ip);
                if (idx >= func.constants.items.len) return BytecodeError.CorruptedFile;
            },
            .load_nil, .load_true, .load_false, .load_void, .@"return", .push_handler, .box_local => {
                if (ip + 2 > code.len) return BytecodeError.CorruptedFile;
                ip += 2;
            },
            .move, .get_upvalue, .set_upvalue, .get_box_local, .set_box_local => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 4;
            },
            .call, .tail_call, .tail_apply, .self_tail_call, .tail_eval => {
                if (ip + 3 > code.len) return BytecodeError.CorruptedFile;
                ip += 3;
            },
            .tail_call_cc => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 4;
            },
            .get_global => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // dst
                const idx = try readU16FromCode(code, &ip);
                try validateSymbolConstant(func, idx);
            },
            .set_global, .define_global => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                const idx = try readU16FromCode(code, &ip);
                try validateSymbolConstant(func, idx);
                ip += 2; // src
            },
            .jump => {
                if (ip + 2 > code.len) return BytecodeError.CorruptedFile;
                const off = try readI16FromCode(code, &ip);
                const target = @as(i64, @intCast(ip)) + @as(i64, off);
                if (target < 0 or target > code.len) return BytecodeError.CorruptedFile;
            },
            .jump_false, .jump_true => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // test register
                const off = try readI16FromCode(code, &ip);
                const target = @as(i64, @intCast(ip)) + @as(i64, off);
                if (target < 0 or target > code.len) return BytecodeError.CorruptedFile;
            },
            .closure => {
                if (ip + 4 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // dst
                const idx = try readU16FromCode(code, &ip);
                if (idx >= func.constants.items.len) return BytecodeError.CorruptedFile;
                const func_val = func.constants.items[idx];
                if (!types.isFunction(func_val)) return BytecodeError.CorruptedFile;
                const inner = types.toObject(func_val).as(Function);
                const capture_bytes = @as(usize, inner.upvalue_count) * 3;
                if (ip + capture_bytes > code.len) return BytecodeError.CorruptedFile;
                ip += capture_bytes;
            },
            .cons => {
                if (ip + 6 > code.len) return BytecodeError.CorruptedFile;
                ip += 6;
            },
            .pop_handler, .halt => {},
            .call_global, .tail_call_global => {
                if (ip + 5 > code.len) return BytecodeError.CorruptedFile;
                ip += 2; // base register
                const idx = try readU16FromCode(code, &ip);
                try validateSymbolConstant(func, idx);
                ip += 1; // nargs
            },
        }
    }
}

// ---------------------------------------------------------------------------
// Deserialize
// ---------------------------------------------------------------------------

/// How a warm program run replays one top-level form (kaappi#1888): the
/// compiled function, or the declaration's source text re-dispatched through
/// `handleTopLevelForm`. `declaration.src` is owned by the result.
pub const ProgramSlot = union(enum) {
    function: u32,
    declaration: struct { line: u32, src: []const u8, fold_case: bool = false },
};

/// One replay event of a `.sld` library entry (kaappi#1888). `register_tx.name`
/// is owned by the result.
pub const LibEvent = union(enum) {
    run_lib: u32,
    run_global: u32,
    register_tx: struct { name: []const u8, tx: *types.Transformer },
};

/// The library-only sections of a `.sld` entry. All strings are owned by the
/// result; the Transformer objects belong to the GC (rooted for the load).
pub const LibraryData = struct {
    events: []LibEvent,
};

pub const DeserializeResult = struct {
    funcs: []*Function,
    top_level_count: u32,
    bundled_files: ?std.StringHashMap([]const u8) = null,
    preamble: ?[][]const u8 = null,
    /// The header's entry-kind byte (bf.ENTRY_*): a program run must only
    /// replay an ENTRY_PROGRAM entry — a library entry shares its cache key
    /// with running the `.sld` directly (`kaappi lib.sld`), and its functions
    /// are library body thunks, not a program (#1888 review).
    entry_kind: u8 = bf.ENTRY_PROGRAM,
    /// Present for program entries (v13): the positional replay stream.
    slots: ?[]ProgramSlot = null,
    /// Present for library entries (v13).
    library: ?LibraryData = null,
    /// Include/dependency invalidation records — for library entries, and
    /// for program entries that touched any file-backed library or
    /// top-level include (#1888 review: a program's compiled slots embed
    /// imported-macro expansions, so its entry must stale when they change,
    /// exactly like a library's).
    includes: ?[]bf.IncludeRecord = null,
    deps: ?[]bf.DepRecord = null,
};

/// Frees everything a successful deserialize allocated with `allocator` — the
/// function-pointer slice, the bundled-file map, the preamble entries, the
/// program slots, the library sections. The `Function` and `Transformer`
/// objects themselves belong to the GC that loaded them (and stay in its
/// `extra_roots`). For callers like `cache status`'s loadability dry-run
/// (kaappi#2113) that load an entry only to discard it.
pub fn freeDeserializeResult(allocator: std.mem.Allocator, result: *DeserializeResult) void {
    allocator.free(result.funcs);
    if (result.bundled_files) |*b| freeBundledFiles(allocator, b);
    if (result.preamble) |p| freePreambleEntries(allocator, p, p.len);
    if (result.slots) |slots| {
        for (slots) |slot| {
            if (slot == .declaration) allocator.free(slot.declaration.src);
        }
        allocator.free(slots);
    }
    if (result.library) |*lib| {
        for (lib.events) |ev| {
            if (ev == .register_tx) allocator.free(ev.register_tx.name);
        }
        allocator.free(lib.events);
    }
    if (result.includes) |incs| {
        for (incs) |inc| allocator.free(@constCast(inc.path));
        allocator.free(incs);
    }
    if (result.deps) |deps| {
        for (deps) |dep| {
            allocator.free(@constCast(dep.rel_path));
            allocator.free(@constCast(dep.resolved_path));
            allocator.free(@constCast(dep.lib_name));
        }
        allocator.free(deps);
    }
    // Reset all fields uniformly, so an (unsupported, but cheap to survive)
    // second call frees nothing rather than double-freeing funcs.
    result.funcs = &.{};
    result.bundled_files = null;
    result.preamble = null;
    result.slots = null;
    result.library = null;
    result.includes = null;
    result.deps = null;
}

pub fn deserializeFromBuffer(gc: *GC, data: []const u8, expected_hash: ?u64) !?DeserializeResult {
    return deserializeFromBufferImpl(gc, data, expected_hash) catch |err| switch (err) {
        // Corrupt-cache exits inside the impl are errors there (so the
        // errdefer cleanup actually runs — `errdefer` does not fire on
        // `return null`, and every partially read section would leak,
        // #1888 review) but plain misses to every caller. OutOfMemory stays
        // an error: it is a runtime failure, not a cache verdict.
        error.OutOfMemory => error.OutOfMemory,
        else => null,
    };
}

fn deserializeFromBufferImpl(gc: *GC, data: []const u8, expected_hash: ?u64) BytecodeError!?DeserializeResult {
    const allocator = gc.allocator;

    // Enough for the fixed prefix (magic + version + source hash + compiler
    // hash); the variable-length strings that follow are bounds-checked as they
    // are read.
    if (data.len < 22) return null;

    var r = Reader{ .data = data, .pos = 0 };

    const magic = r.readBytes(4) catch return null;
    if (!std.mem.eql(u8, magic, &bf.MAGIC)) return null;

    const ver = r.readU16() catch return null;
    if (ver != bf.VERSION) return null;

    const file_hash = r.readU64() catch return null;
    if (expected_hash) |eh| {
        if (file_hash != eh) return null;
    }

    const file_compiler_hash = r.readU64() catch return null;
    if (file_compiler_hash != bf.compilerHash()) return null;

    // Provenance strings (v10): build id then source path. Read to advance the
    // cursor; the loaded functions don't need them (they are for `cache
    // status`). A truncated header here is a corrupt cache — treat as a miss.
    _ = r.readStr() catch return null;
    _ = r.readStr() catch return null;

    // Entry kind (v13): selects the tail layout.
    const entry_kind = r.readU8() catch return null;
    if (entry_kind != bf.ENTRY_PROGRAM and entry_kind != bf.ENTRY_BUNDLE and entry_kind != bf.ENTRY_LIBRARY)
        return null;

    const func_count = r.readU32() catch return null;
    // A library with no compiled body forms (pure re-export shim) and a
    // program whose forms are all declarations (an import-only script)
    // legitimately have empty function tables; a bundle does not.
    if ((func_count == 0 and entry_kind == bf.ENTRY_BUNDLE) or func_count > bf.MAX_FUNCTIONS) return null;

    const top_level_count = r.readU32() catch return null;
    if (top_level_count > func_count or top_level_count > bf.MAX_TOP_LEVEL_FUNCTIONS) return null;

    const all_funcs = allocator.alloc(*Function, func_count) catch return BytecodeError.OutOfMemory;
    defer allocator.free(all_funcs);

    // Root every loaded function in gc.extra_roots. During the load this keeps
    // functions alive while readConstant allocates. On success we KEEP them
    // rooted for the rest of the run (keep_roots = true below): the caller
    // executes the top-level functions one at a time, and a GC triggered while
    // running one form must not reclaim the other, not-yet-executed functions
    // (nor the shared nested functions they reference). This mirrors the fresh
    // compile path, where main.zig leaves every compiled top-level function in
    // gc.extra_roots for the whole run. On any error path the functions are
    // still reachable garbage, so we drop the roots to let them be collected.
    const roots_base = gc.extra_roots.items.len;
    var keep_roots = false;
    defer if (!keep_roots) gc.extra_roots.shrinkRetainingCapacity(roots_base);
    for (0..func_count) |i| {
        all_funcs[i] = gc.allocFunction() catch return BytecodeError.OutOfMemory;
        gc.extra_roots.append(allocator, types.makePointer(&all_funcs[i].header)) catch return BytecodeError.OutOfMemory;
    }

    // One back-reference table across all functions' constants, mirroring the
    // writer's single map (kaappi#2111).
    var shared: SharedTable = .empty;
    defer shared.deinit(allocator);

    for (0..func_count) |i| {
        const func = all_funcs[i];

        func.arity = r.readU8() catch return null;
        func.locals_count = r.readU16() catch return null;
        func.upvalue_count = r.readU16() catch return null;
        const variadic_byte = r.readU8() catch return null;
        func.is_variadic = variadic_byte != 0;

        const name_len = r.readU16() catch return null;
        if (name_len > bf.MAX_SYMBOL_BYTES) return null;
        if (name_len > 0) {
            const name_bytes = r.readBytes(name_len) catch return null;
            func.name = allocator.dupe(u8, name_bytes) catch return BytecodeError.OutOfMemory;
            func.owns_name = true;
        }

        const code_len = r.readU32() catch return null;
        if (code_len > bf.MAX_CODE_BYTES) {
            var buf: [128]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buf);
            w.print("error: bytecode too large ({d} bytes, max {d})\n", .{ code_len, bf.MAX_CODE_BYTES }) catch {};
            const msg = w.buffered();
            _ = platform.write(2, msg.ptr, msg.len);
            return null;
        }
        const code_bytes = r.readBytes(code_len) catch return null;
        func.code.appendSlice(allocator, code_bytes) catch return BytecodeError.OutOfMemory;

        const const_count = r.readU32() catch return null;
        if (const_count > bf.MAX_CONSTANTS_PER_FUNCTION) return null;
        for (0..const_count) |_| {
            const val = readConstant(&r, gc, all_funcs, &shared, 0) catch return null;
            func.constants.append(allocator, val) catch return BytecodeError.OutOfMemory;
        }

        // Debug info: source_line and line_table (added in v7; col added in v9)
        func.source_line = r.readU32() catch return null;
        const line_count = r.readU32() catch return null;
        if (line_count > bf.MAX_CODE_BYTES) return null;
        for (0..line_count) |_| {
            const offset = r.readU16() catch return null;
            const line = r.readU32() catch return null;
            const col = r.readU32() catch return null;
            func.line_table.append(allocator, .{ .offset = offset, .line = line, .col = col }) catch return BytecodeError.OutOfMemory;
        }
    }

    for (all_funcs) |func| {
        validateFunctionBytecode(func) catch return null;
    }

    // Program slot section (v13): the positional replay stream.
    var result: DeserializeResult = .{ .funcs = &.{}, .top_level_count = top_level_count, .entry_kind = entry_kind };
    var ok = false;
    // One cleanup funnel for every corrupt-cache `return null` below: frees
    // whichever sections were already read (kaappi#2113 discipline — nothing
    // partial leaks past a miss).
    defer if (!ok) freeDeserializeResult(allocator, &result);

    if (entry_kind == bf.ENTRY_PROGRAM) {
        const slot_count = r.readU32() catch return BytecodeError.CorruptedFile;
        if (slot_count > bf.MAX_TOP_LEVEL_FUNCTIONS) return BytecodeError.CorruptedFile;
        const entries = allocator.alloc(ProgramSlot, slot_count) catch return BytecodeError.OutOfMemory;
        var filled: usize = 0;
        errdefer {
            for (entries[0..filled]) |*sl| {
                if (sl.* == .declaration) allocator.free(sl.declaration.src);
            }
            allocator.free(entries);
        }
        for (0..slot_count) |i| {
            const tag = r.readU8() catch break;
            if (tag == bf.SLOT_FUNCTION) {
                const idx = r.readU32() catch break;
                if (idx >= top_level_count) break;
                entries[i] = .{ .function = idx };
            } else if (tag == bf.SLOT_DECLARATION) {
                const line = r.readU32() catch break;
                const flags = r.readU8() catch break;
                if (flags > 1) break;
                const src_len = r.readU32() catch break;
                if (src_len > bf.MAX_STRING_BYTES) break;
                const src_bytes = r.readBytes(src_len) catch break;
                const src = allocator.dupe(u8, src_bytes) catch return BytecodeError.OutOfMemory;
                entries[i] = .{ .declaration = .{ .line = line, .src = src, .fold_case = flags != 0 } };
            } else break;
            filled = i + 1;
        }
        if (filled != slot_count) return BytecodeError.CorruptedFile;
        result.slots = entries;
    }

    // Library sections (v13): transformers and the replay events.
    if (entry_kind == bf.ENTRY_LIBRARY) {
        result.library = readLibrarySections(&r, gc, all_funcs, top_level_count, &shared) catch |err| switch (err) {
            BytecodeError.OutOfMemory => return BytecodeError.OutOfMemory,
            else => return null,
        } orelse return BytecodeError.CorruptedFile;
    }

    // Include/dependency records — shared by the program and library kinds.
    if (entry_kind != bf.ENTRY_BUNDLE) {
        const include_count = r.readU32() catch return BytecodeError.CorruptedFile;
        if (include_count > bf.MAX_LIBRARY_INCLUDES) return BytecodeError.CorruptedFile;
        if (include_count > 0) {
            const includes = allocator.alloc(bf.IncludeRecord, include_count) catch return BytecodeError.OutOfMemory;
            var inc_filled: usize = 0;
            errdefer {
                for (includes[0..inc_filled]) |inc| allocator.free(@constCast(inc.path));
                allocator.free(includes);
            }
            for (0..include_count) |i| {
                const len = r.readU16() catch return BytecodeError.CorruptedFile;
                if (len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.CorruptedFile;
                // Borrowed reads first, dupe last: nothing may fail between
                // the allocation and the inc_filled assignment that makes the
                // loop's errdefer own it (#1888 review).
                const path_bytes = r.readBytes(len) catch return BytecodeError.CorruptedFile;
                const hash = r.readU64() catch return BytecodeError.CorruptedFile;
                const path = allocator.dupe(u8, path_bytes) catch return BytecodeError.OutOfMemory;
                includes[i] = .{ .path = path, .hash = hash };
                inc_filled = i + 1;
            }
            result.includes = includes;
        }

        const dep_count = r.readU32() catch return BytecodeError.CorruptedFile;
        if (dep_count > bf.MAX_LIBRARY_DEPS) return BytecodeError.CorruptedFile;
        if (dep_count > 0) {
            const deps = allocator.alloc(bf.DepRecord, dep_count) catch return BytecodeError.OutOfMemory;
            var dep_filled: usize = 0;
            errdefer {
                for (deps[0..dep_filled]) |dep| {
                    allocator.free(@constCast(dep.rel_path));
                    allocator.free(@constCast(dep.resolved_path));
                    allocator.free(@constCast(dep.lib_name));
                }
                allocator.free(deps);
            }
            for (0..dep_count) |i| {
                const rel_len = r.readU16() catch return BytecodeError.CorruptedFile;
                if (rel_len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.CorruptedFile;
                const rel = allocator.dupe(u8, r.readBytes(rel_len) catch return BytecodeError.CorruptedFile) catch return BytecodeError.OutOfMemory;
                errdefer allocator.free(rel);
                const res_len = r.readU16() catch return BytecodeError.CorruptedFile;
                if (res_len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.CorruptedFile;
                const resolved = allocator.dupe(u8, r.readBytes(res_len) catch return BytecodeError.CorruptedFile) catch return BytecodeError.OutOfMemory;
                errdefer allocator.free(resolved);
                const hash = r.readU64() catch return BytecodeError.CorruptedFile;
                const name_len = r.readU16() catch return BytecodeError.CorruptedFile;
                if (name_len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.CorruptedFile;
                const lib_name = allocator.dupe(u8, r.readBytes(name_len) catch return BytecodeError.CorruptedFile) catch return BytecodeError.OutOfMemory;
                deps[i] = .{ .rel_path = rel, .resolved_path = resolved, .source_hash = hash, .lib_name = lib_name };
                dep_filled = i + 1;
            }
            result.deps = deps;
        }
    }

    // Read bundled files section
    const bf_count = r.readU32() catch return BytecodeError.CorruptedFile;
    var bundled_files: ?std.StringHashMap([]const u8) = null;
    if (bf_count > 0) {
        if (bf_count > bf.MAX_BUNDLED_FILES) return BytecodeError.CorruptedFile;
        var bfm = std.StringHashMap([]const u8).init(allocator);
        var bfm_populated = false;
        errdefer if (!bfm_populated) freeBundledFiles(allocator, &bfm);
        for (0..bf_count) |_| {
            const path_len = r.readU16() catch return BytecodeError.CorruptedFile;
            const path_bytes = r.readBytes(path_len) catch return BytecodeError.CorruptedFile;
            const content_len = r.readU32() catch return BytecodeError.CorruptedFile;
            if (content_len > bf.MAX_STRING_BYTES) return BytecodeError.CorruptedFile;
            const content = r.readBytes(content_len) catch return BytecodeError.CorruptedFile;
            const key = allocator.dupe(u8, path_bytes) catch return BytecodeError.OutOfMemory;
            const val = allocator.dupe(u8, content) catch {
                allocator.free(key);
                return BytecodeError.OutOfMemory;
            };
            bfm.put(key, val) catch {
                allocator.free(key);
                allocator.free(val);
                return BytecodeError.OutOfMemory;
            };
        }
        bfm_populated = true;
        bundled_files = bfm;
    }
    result.bundled_files = bundled_files;

    // Read preamble section
    const preamble_count = r.readU32() catch return BytecodeError.CorruptedFile;
    if (preamble_count > bf.MAX_PREAMBLE_FORMS) return BytecodeError.CorruptedFile;
    if (preamble_count > 0) {
        const entries = allocator.alloc([]const u8, preamble_count) catch return BytecodeError.OutOfMemory;
        var pre_filled: usize = 0;
        errdefer freePreambleEntries(allocator, entries, pre_filled);
        for (0..preamble_count) |i| {
            const src_len = r.readU32() catch return BytecodeError.CorruptedFile;
            if (src_len > bf.MAX_STRING_BYTES) return BytecodeError.CorruptedFile;
            const src = r.readBytes(src_len) catch return BytecodeError.CorruptedFile;
            entries[i] = allocator.dupe(u8, src) catch return BytecodeError.OutOfMemory;
            pre_filled = i + 1;
        }
        result.preamble = entries;
    }

    if (r.pos != data.len) return BytecodeError.CorruptedFile;

    result.funcs = allocator.alloc(*Function, func_count) catch return BytecodeError.OutOfMemory;
    @memcpy(result.funcs, all_funcs);
    // Load succeeded: keep the functions rooted for the rest of the run so a GC
    // during execution of one top-level form cannot free the others.
    keep_roots = true;
    ok = true;
    return result;
}

/// One length-capped identifier/string field of a transformer record. The
/// bytes come from an INTERNED symbol (a GC root), matching the cold path's
/// convention — freeObject frees only the slice arrays, never these strings,
/// because the cold path borrows them from symbol names too.
fn readTxStr(r: *Reader, gc: *GC) BytecodeError![]const u8 {
    const len = try r.readU16();
    if (len > bf.MAX_SYMBOL_BYTES) return BytecodeError.CorruptedFile;
    const bytes = try r.readBytes(len);
    const sym = gc.allocSymbol(bytes) catch return BytecodeError.OutOfMemory;
    return types.symbolName(sym);
}

/// Read one Transformer record. The returned object's `def_env` is left null —
/// the warm loader points it (and only it) at the reconstructed lib_env. The
/// object is rooted in gc.extra_roots for the rest of the deserialize; the
/// warm loader trims those roots when the library finishes loading.
fn readTransformer(r: *Reader, gc: *GC, all_funcs: []*Function, shared: *SharedTable) BytecodeError!*types.Transformer {
    const allocator = gc.allocator;
    const kind_byte = try r.readU8();
    const kind: types.TransformerKind = switch (kind_byte) {
        0 => .syntax_rules,
        1 => .er_macro,
        2 => .lisp_macro,
        else => return BytecodeError.CorruptedFile,
    };
    const num_rules = try r.readU16();

    // Temporary roots for the component Values: allocTransformer dupes them
    // into its own slices, at which point they are reachable through the
    // transformer and the temp entries are shrunk away. The transformer
    // itself is then rooted for the rest of the deserialize — a later
    // record's readConstant allocations must not collect it — and stays
    // rooted until the warm loader trims the deserialize's roots.
    const roots_base = gc.extra_roots.items.len;

    var lits: std.ArrayList(Value) = .empty;
    defer lits.deinit(allocator);
    const lit_count = try r.readU32();
    if (lit_count > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.CorruptedFile;
    for (0..lit_count) |_| {
        const v = try readConstant(r, gc, all_funcs, shared, 0);
        gc.extra_roots.append(allocator, v) catch return BytecodeError.OutOfMemory;
        lits.append(allocator, v) catch return BytecodeError.OutOfMemory;
    }
    var pats: std.ArrayList(Value) = .empty;
    defer pats.deinit(allocator);
    const pat_count = try r.readU32();
    if (pat_count > bf.MAX_CONSTANTS_PER_FUNCTION or pat_count != num_rules) return BytecodeError.CorruptedFile;
    for (0..pat_count) |_| {
        const v = try readConstant(r, gc, all_funcs, shared, 0);
        gc.extra_roots.append(allocator, v) catch return BytecodeError.OutOfMemory;
        pats.append(allocator, v) catch return BytecodeError.OutOfMemory;
    }
    var tmps: std.ArrayList(Value) = .empty;
    defer tmps.deinit(allocator);
    const tmpl_count = try r.readU32();
    if (tmpl_count > bf.MAX_CONSTANTS_PER_FUNCTION or tmpl_count != num_rules) return BytecodeError.CorruptedFile;
    for (0..tmpl_count) |_| {
        const v = try readConstant(r, gc, all_funcs, shared, 0);
        gc.extra_roots.append(allocator, v) catch return BytecodeError.OutOfMemory;
        tmps.append(allocator, v) catch return BytecodeError.OutOfMemory;
    }
    const proc = try readConstant(r, gc, all_funcs, shared, 0);
    gc.extra_roots.append(allocator, proc) catch return BytecodeError.OutOfMemory;

    const tx_val = gc.allocTransformer(lits.items, pats.items, tmps.items) catch return BytecodeError.OutOfMemory;
    // Drop the component temp roots (now duped inside the transformer), then
    // take the transformer's own — order matters: shrinking after the append
    // would unroot it (the gc-stress "marking freed object" class).
    gc.extra_roots.shrinkRetainingCapacity(roots_base);
    gc.extra_roots.append(allocator, tx_val) catch return BytecodeError.OutOfMemory;
    const tx = types.toObject(tx_val).as(types.Transformer);
    tx.kind = kind;
    tx.proc = proc;
    errdefer gc.extra_roots.shrinkRetainingCapacity(roots_base);

    if (try r.readU8() != 0) {
        tx.custom_ellipsis = try readTxStr(r, gc);
    }
    const bound_count = try r.readU32();
    if (bound_count > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.CorruptedFile;
    if (bound_count > 0) {
        const slots = allocator.alloc(u32, bound_count) catch return BytecodeError.OutOfMemory;
        for (slots) |*s| s.* = try r.readU32();
        tx.literal_bound = slots;
    }
    const caps_count = try r.readU32();
    if (caps_count > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.CorruptedFile;
    if (caps_count > 0) {
        const caps = allocator.alloc(types.CapturedLocal, caps_count) catch return BytecodeError.OutOfMemory;
        for (caps) |*c| {
            c.name = try readTxStr(r, gc);
            c.slot = try r.readU16();
        }
        tx.captured_locals = caps;
    }
    const bfr_count = try r.readU32();
    if (bfr_count > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.CorruptedFile;
    if (bfr_count > 0) {
        const names = allocator.alloc([]const u8, bfr_count) catch return BytecodeError.OutOfMemory;
        for (names) |*n| n.* = try readTxStr(r, gc);
        tx.bound_free_refs = names;
    }
    const dslr_count = try r.readU32();
    if (dslr_count > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.CorruptedFile;
    if (dslr_count > 0) {
        const names = allocator.alloc([]const u8, dslr_count) catch return BytecodeError.OutOfMemory;
        for (names) |*n| n.* = try readTxStr(r, gc);
        tx.def_site_local_refs = names;
    }
    if (try r.readU8() != 0) {
        tx.def_lib_name = try readTxStr(r, gc);
    }
    tx.finalized = (try r.readU8()) != 0;
    tx.peers_computed = (try r.readU8()) != 0;
    return tx;
}

/// Read the transformer/event/include/dependency sections of a library entry.
/// Null (not an error) means corrupt — the caller treats it as a miss.
fn readLibrarySections(r: *Reader, gc: *GC, all_funcs: []*Function, top_level_count: u32, shared: *SharedTable) BytecodeError!?LibraryData {
    const allocator = gc.allocator;

    const tx_count = r.readU32() catch return BytecodeError.CorruptedFile;
    if (tx_count > bf.MAX_LIBRARY_TRANSFORMERS) return BytecodeError.CorruptedFile;
    const txs = allocator.alloc(*types.Transformer, tx_count) catch return BytecodeError.OutOfMemory;
    defer allocator.free(txs);
    for (0..tx_count) |i| {
        txs[i] = try readTransformer(r, gc, all_funcs, shared);
    }

    const event_count = r.readU32() catch return BytecodeError.CorruptedFile;
    if (event_count > bf.MAX_LIBRARY_EVENTS) return BytecodeError.CorruptedFile;
    const events = allocator.alloc(LibEvent, event_count) catch return BytecodeError.OutOfMemory;
    var events_filled: usize = 0;
    errdefer {
        for (events[0..events_filled]) |*ev| {
            if (ev.* == .register_tx) allocator.free(ev.register_tx.name);
        }
        allocator.free(events);
    }
    for (0..event_count) |i| {
        const tag = r.readU8() catch return BytecodeError.CorruptedFile;
        if (tag == bf.EVENT_RUN_LIB) {
            const idx = r.readU32() catch return BytecodeError.CorruptedFile;
            if (idx >= top_level_count) return BytecodeError.CorruptedFile;
            events[i] = .{ .run_lib = idx };
        } else if (tag == bf.EVENT_RUN_GLOBAL) {
            const idx = r.readU32() catch return BytecodeError.CorruptedFile;
            if (idx >= top_level_count) return BytecodeError.CorruptedFile;
            events[i] = .{ .run_global = idx };
        } else if (tag == bf.EVENT_REGISTER_TX) {
            const name_len = r.readU16() catch return BytecodeError.CorruptedFile;
            if (name_len > bf.MAX_TX_NAME_BYTES) return BytecodeError.CorruptedFile;
            const name_bytes = r.readBytes(name_len) catch return BytecodeError.CorruptedFile;
            const name = allocator.dupe(u8, name_bytes) catch return BytecodeError.OutOfMemory;
            const tx_idx = r.readU32() catch return BytecodeError.CorruptedFile;
            if (tx_idx >= txs.len) return BytecodeError.CorruptedFile;
            events[i] = .{ .register_tx = .{ .name = name, .tx = txs[tx_idx] } };
        } else return BytecodeError.CorruptedFile;
        events_filled = i + 1;
    }

    return .{ .events = events };
}

pub fn readFromBuffer(gc: *GC, data: []const u8) !?DeserializeResult {
    return deserializeFromBuffer(gc, data, null);
}

pub fn readFileWithTopLevel(gc: *GC, source_hash: u64, path: []const u8) !?DeserializeResult {
    const allocator = gc.allocator;
    const data = file_utils.readWholeFile(allocator, path, 4 * 1024 * 1024) catch return null;
    defer allocator.free(data);
    return deserializeFromBuffer(gc, data, source_hash);
}

// ---------------------------------------------------------------------------
// Header inspection (for `kaappi cache status`)
// ---------------------------------------------------------------------------

/// A cache entry's header, as surfaced by `kaappi cache status`. The `build_id`
/// and `source_path` slices borrow the buffer passed to `readHeaderInfo`.
pub const HeaderInfo = struct {
    source_hash: u64,
    compiler_hash: u64,
    build_id: []const u8,
    source_path: []const u8,
    /// True when this entry was produced by the running binary — i.e. a plain
    /// run of its source would hit (given the source is unchanged).
    current_build: bool,
};

/// Parse just the header of a `.sbc` buffer for reporting, without
/// deserializing any functions. Returns null when the buffer is not a
/// current-format Kaappi cache file (bad magic, or a version this binary can't
/// parse) — `cache status` shows such files by size only. Unlike the load path
/// this does *not* reject on a compiler-hash mismatch: reporting stale entries
/// from other builds is the whole point.
pub fn readHeaderInfo(data: []const u8) ?HeaderInfo {
    if (data.len < 22) return null;
    var r = Reader{ .data = data, .pos = 0 };
    const magic = r.readBytes(4) catch return null;
    if (!std.mem.eql(u8, magic, &bf.MAGIC)) return null;
    const ver = r.readU16() catch return null;
    if (ver != bf.VERSION) return null;
    const source_hash_val = r.readU64() catch return null;
    const compiler_hash_val = r.readU64() catch return null;
    const build_id = r.readStr() catch return null;
    const source_path = r.readStr() catch return null;
    return .{
        .source_hash = source_hash_val,
        .compiler_hash = compiler_hash_val,
        .build_id = build_id,
        .source_path = source_path,
        .current_build = compiler_hash_val == bf.compilerHash(),
    };
}
