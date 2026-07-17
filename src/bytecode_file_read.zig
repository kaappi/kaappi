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

fn readConstant(r: *Reader, gc: *GC, all_funcs: []*Function, depth: u32) !Value {
    if (depth > bf.MAX_CONSTANT_DEPTH) return BytecodeError.CorruptedFile;
    const tag = try r.readU8();
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
            const data_len = try r.readU32();
            if (data_len > bf.MAX_STRING_BYTES) return BytecodeError.CorruptedFile;
            const data = try r.readBytes(data_len);
            return gc.allocString(data) catch return BytecodeError.OutOfMemory;
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
        bf.TAG_PAIR => {
            const car_val = try readConstant(r, gc, all_funcs, depth + 1);
            // Root car to protect from GC during cdr read
            var car_root = car_val;
            gc.pushRoot(&car_root);
            defer gc.popRoot();
            const cdr_val = try readConstant(r, gc, all_funcs, depth + 1);
            return gc.allocPair(car_root, cdr_val) catch return BytecodeError.OutOfMemory;
        },
        bf.TAG_VECTOR => {
            const len = try r.readU32();
            if (len > bf.MAX_VECTOR_LEN) return BytecodeError.CorruptedFile;
            var vec_val = gc.allocVectorFill(len, types.NIL) catch return BytecodeError.OutOfMemory;
            gc.pushRoot(&vec_val);
            defer gc.popRoot();
            for (0..len) |i| {
                const elem = try readConstant(r, gc, all_funcs, depth + 1);
                const vec = types.toVector(vec_val);
                vec.data[i] = elem;
                gc.writeBarrier(types.toObject(vec_val), elem);
            }
            return vec_val;
        },
        bf.TAG_BYTEVECTOR => {
            const len = try r.readU32();
            if (len > bf.MAX_BYTEVECTOR_LEN) return BytecodeError.CorruptedFile;
            const data = try r.readBytes(len);
            return gc.allocBytevector(data) catch return BytecodeError.OutOfMemory;
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
            const num = try readConstant(r, gc, all_funcs, depth + 1);
            if (!types.isFixnum(num) and !types.isBignum(num)) return BytecodeError.CorruptedFile;
            var num_root = num;
            gc.pushRoot(&num_root);
            defer gc.popRoot();
            const den = try readConstant(r, gc, all_funcs, depth + 1);
            if (!types.isFixnum(den) and !types.isBignum(den)) return BytecodeError.CorruptedFile;
            if (types.isFixnum(den) and types.toFixnum(den) == 0) return BytecodeError.CorruptedFile;
            if (types.isBignum(den) and types.toBignum(den).len == 0) return BytecodeError.CorruptedFile;
            return gc.allocRational(num_root, den) catch return BytecodeError.OutOfMemory;
        },
        bf.TAG_COMPLEX => {
            const real = try r.readF64();
            const imag = try r.readF64();
            const exact_real = (try r.readU8()) != 0;
            const exact_imag = (try r.readU8()) != 0;
            return gc.allocComplexEx(real, imag, exact_real, exact_imag) catch return BytecodeError.OutOfMemory;
        },
        else => return BytecodeError.InvalidConstantTag,
    }
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

pub const DeserializeResult = struct {
    funcs: []*Function,
    top_level_count: u32,
    bundled_files: ?std.StringHashMap([]const u8) = null,
    preamble: ?[][]const u8 = null,
};

pub fn deserializeFromBuffer(gc: *GC, data: []const u8, expected_hash: ?u64) !?DeserializeResult {
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

    const func_count = r.readU32() catch return null;
    if (func_count == 0 or func_count > bf.MAX_FUNCTIONS) return null;

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
            const val = readConstant(&r, gc, all_funcs, 0) catch return null;
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

    // Read bundled files section
    const bf_count = r.readU32() catch return null;
    var bundled_files: ?std.StringHashMap([]const u8) = null;
    if (bf_count > 0) {
        if (bf_count > 4096) return null;
        var bfm = std.StringHashMap([]const u8).init(allocator);
        for (0..bf_count) |_| {
            const path_len = r.readU16() catch {
                freeBundledFiles(allocator, &bfm);
                return null;
            };
            const path_bytes = r.readBytes(path_len) catch {
                freeBundledFiles(allocator, &bfm);
                return null;
            };
            const content_len = r.readU32() catch {
                freeBundledFiles(allocator, &bfm);
                return null;
            };
            if (content_len > bf.MAX_STRING_BYTES) {
                freeBundledFiles(allocator, &bfm);
                return null;
            }
            const content = r.readBytes(content_len) catch {
                freeBundledFiles(allocator, &bfm);
                return null;
            };
            const key = allocator.dupe(u8, path_bytes) catch {
                freeBundledFiles(allocator, &bfm);
                return BytecodeError.OutOfMemory;
            };
            const val = allocator.dupe(u8, content) catch {
                allocator.free(key);
                freeBundledFiles(allocator, &bfm);
                return BytecodeError.OutOfMemory;
            };
            bfm.put(key, val) catch {
                allocator.free(key);
                allocator.free(val);
                freeBundledFiles(allocator, &bfm);
                return BytecodeError.OutOfMemory;
            };
        }
        bundled_files = bfm;
    }

    // Read preamble section
    const preamble_count = r.readU32() catch {
        if (bundled_files) |*b| freeBundledFiles(allocator, b);
        return null;
    };
    var preamble: ?[][]const u8 = null;
    if (preamble_count > 0) {
        if (preamble_count > 4096) {
            if (bundled_files) |*b| freeBundledFiles(allocator, b);
            return null;
        }
        const entries = allocator.alloc([]const u8, preamble_count) catch {
            if (bundled_files) |*b| freeBundledFiles(allocator, b);
            return BytecodeError.OutOfMemory;
        };
        for (0..preamble_count) |i| {
            const src_len = r.readU32() catch {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*b| freeBundledFiles(allocator, b);
                return null;
            };
            if (src_len > bf.MAX_STRING_BYTES) {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*b| freeBundledFiles(allocator, b);
                return null;
            }
            const src = r.readBytes(src_len) catch {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*b| freeBundledFiles(allocator, b);
                return null;
            };
            entries[i] = allocator.dupe(u8, src) catch {
                freePreambleEntries(allocator, entries, i);
                if (bundled_files) |*b| freeBundledFiles(allocator, b);
                return BytecodeError.OutOfMemory;
            };
        }
        preamble = entries;
    }

    if (r.pos != data.len) {
        if (bundled_files) |*b| freeBundledFiles(allocator, b);
        if (preamble) |p| freePreambleEntries(allocator, p, p.len);
        return null;
    }

    const result = allocator.alloc(*Function, func_count) catch return BytecodeError.OutOfMemory;
    @memcpy(result, all_funcs);
    // Load succeeded: keep the functions rooted for the rest of the run so a GC
    // during execution of one top-level form cannot free the others.
    keep_roots = true;
    return .{ .funcs = result, .top_level_count = top_level_count, .bundled_files = bundled_files, .preamble = preamble };
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
