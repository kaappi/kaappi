//! Bytecode serializer: Function graph → `.sbc` bytes.
//!
//! The write half of the `.sbc` codec. Shares the format contract (magic,
//! version, constant tags, size limits, `compilerHash`) with the deserializer
//! via `bytecode_file.zig`; see `bytecode_file_read.zig` for the inverse.
//!
//! Three entry kinds share the function-section writer (v13, kaappi#1888):
//! programs (with a positional replay-slot section), `--compile` bundles
//! (bundled files + preamble), and `.sld` libraries (transformers + replay
//! events + invalidation records — see `writeFileWithLibrary`).

const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const build_options = @import("build_options");
const types = @import("types.zig");
const bf = @import("bytecode_file.zig");
const Value = types.Value;
const Function = types.Function;
const BytecodeError = bf.BytecodeError;

// ---------------------------------------------------------------------------
// Write helpers
// ---------------------------------------------------------------------------

// The byte-emitting methods are `pub` so the round-trip tests in
// `bytecode_file.zig` can hand-assemble `.sbc` fixtures; `init`/`deinit` are the
// serializer's own lifecycle and stay internal.
pub const Writer = struct {
    buf: std.ArrayList(u8),

    fn init() Writer {
        return .{ .buf = .empty };
    }

    pub fn writeU8(self: *Writer, allocator: std.mem.Allocator, v: u8) !void {
        self.buf.append(allocator, v) catch return BytecodeError.OutOfMemory;
    }

    pub fn writeU16(self: *Writer, allocator: std.mem.Allocator, v: u16) !void {
        const bytes: [2]u8 = @bitCast(std.mem.nativeToLittle(u16, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    pub fn writeU32(self: *Writer, allocator: std.mem.Allocator, v: u32) !void {
        const bytes: [4]u8 = @bitCast(std.mem.nativeToLittle(u32, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    pub fn writeU64(self: *Writer, allocator: std.mem.Allocator, v: u64) !void {
        const bytes: [8]u8 = @bitCast(std.mem.nativeToLittle(u64, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    pub fn writeI64(self: *Writer, allocator: std.mem.Allocator, v: i64) !void {
        const bytes: [8]u8 = @bitCast(std.mem.nativeToLittle(i64, v));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    pub fn writeF64(self: *Writer, allocator: std.mem.Allocator, v: f64) !void {
        const bits: u64 = @bitCast(v);
        const bytes: [8]u8 = @bitCast(std.mem.nativeToLittle(u64, bits));
        self.buf.appendSlice(allocator, &bytes) catch return BytecodeError.OutOfMemory;
    }

    pub fn writeBytes(self: *Writer, allocator: std.mem.Allocator, data: []const u8) !void {
        self.buf.appendSlice(allocator, data) catch return BytecodeError.OutOfMemory;
    }

    /// A u16-length-prefixed header string, truncated to `MAX_HEADER_STR_BYTES`
    /// (informational fields — provenance for `cache status` — so a pathological
    /// over-long path is clamped rather than rejected).
    pub fn writeStr(self: *Writer, allocator: std.mem.Allocator, s: []const u8) !void {
        const n: u16 = @intCast(@min(s.len, bf.MAX_HEADER_STR_BYTES));
        try self.writeU16(allocator, n);
        try self.writeBytes(allocator, s[0..n]);
    }

    fn deinit(self: *Writer, allocator: std.mem.Allocator) void {
        self.buf.deinit(allocator);
    }
};

// ---------------------------------------------------------------------------
// Function collection (flatten nested functions depth-first)
// ---------------------------------------------------------------------------

/// Collect all functions into a flat array with top-level functions first,
/// followed by their nested functions. This ensures that when deserializing,
/// the first top_level_count entries in the array are the top-level functions.
fn collectFunctions(allocator: std.mem.Allocator, top_level_funcs: []*Function) !std.ArrayList(*Function) {
    var result: std.ArrayList(*Function) = .empty;

    // First pass: add all top-level functions
    for (top_level_funcs) |func| {
        result.append(allocator, func) catch return BytecodeError.OutOfMemory;
    }

    // Second pass: add nested functions (DFS through each top-level function's constants)
    for (top_level_funcs) |func| {
        try collectNestedFunctions(allocator, func, &result);
    }

    return result;
}

fn collectNestedFunctions(allocator: std.mem.Allocator, func: *Function, result: *std.ArrayList(*Function)) !void {
    for (func.constants.items) |constant| {
        if (types.isPointer(constant) and types.toObject(constant).tag == .function) {
            const child_func = types.toObject(constant).as(Function);
            // Check if already collected
            var already = false;
            for (result.items) |existing| {
                if (existing == child_func) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                result.append(allocator, child_func) catch return BytecodeError.OutOfMemory;
                try collectNestedFunctions(allocator, child_func, result);
            }
        }
    }
}

fn findFunctionIndex(all_funcs: []*Function, func: *Function) ?u32 {
    for (all_funcs, 0..) |f, i| {
        if (f == func) return @intCast(i);
    }
    return null;
}

// ---------------------------------------------------------------------------
// Write constant
// ---------------------------------------------------------------------------

/// Shared-structure map (kaappi#2111): heap address → back-reference id for
/// every pair/string/vector/bytevector already emitted, in pre-order
/// first-encounter order. `readConstant` rebuilds the same table in the same
/// order, so `TAG_BACKREF n` names the same object on both sides. This is
/// what keeps datum-label sharing (`eq?`), makes shared DAGs linear instead
/// of exponential in the output, and lets cyclic literals terminate.
const SharedMap = std.AutoHashMap(usize, u32);

fn noteShared(seen: *SharedMap, obj: *types.Object) !void {
    const id: u32 = @intCast(seen.count());
    seen.put(@intFromPtr(obj), id) catch return BytecodeError.OutOfMemory;
}

fn immutableByte(obj: *types.Object) u8 {
    return if (obj.flags.immutable) @as(u8, 1) else 0;
}

/// Serialize one constant. Refuses — never truncates — anything the reader
/// would reject (kaappi#2113): `error.LimitExceeded` for a size/depth cap,
/// `error.UnsupportedConstant` for a value the format cannot represent. A
/// refused write means no `.sbc` is produced at all, so the alternative
/// failure mode (an entry that recompiles and rewrites itself on every run,
/// forever, while `cache status` calls it "current") cannot happen.
///
/// `depth` counts *nesting* (car descent, vector elements, rational parts);
/// the cdr spine of a list is walked iteratively at constant depth, so a long
/// quoted list is cacheable and only pathological nesting hits the cap.
fn writeConstant(w: *Writer, allocator: std.mem.Allocator, val: Value, all_funcs: []*Function, seen: *SharedMap, depth: u32) !void {
    if (depth > bf.MAX_CONSTANT_DEPTH) return BytecodeError.LimitExceeded;
    if (types.isFixnum(val)) {
        try w.writeU8(allocator, bf.TAG_FIXNUM);
        try w.writeI64(allocator, types.toFixnum(val));
        return;
    }

    if (val == types.NIL) {
        try w.writeU8(allocator, bf.TAG_NIL);
        return;
    }

    if (val == types.TRUE) {
        try w.writeU8(allocator, bf.TAG_BOOLEAN);
        try w.writeU8(allocator, 1);
        return;
    }

    if (val == types.FALSE) {
        try w.writeU8(allocator, bf.TAG_BOOLEAN);
        try w.writeU8(allocator, 0);
        return;
    }

    if (val == types.VOID) {
        try w.writeU8(allocator, bf.TAG_VOID);
        return;
    }

    if (val == types.EOF) {
        try w.writeU8(allocator, bf.TAG_EOF);
        return;
    }

    if (val == types.UNDEFINED) {
        try w.writeU8(allocator, bf.TAG_UNDEFINED);
        return;
    }

    if (types.isChar(val)) {
        try w.writeU8(allocator, bf.TAG_CHAR);
        try w.writeU32(allocator, @as(u32, types.toChar(val)));
        return;
    }

    if (types.isFlonum(val)) {
        try w.writeU8(allocator, bf.TAG_FLONUM);
        try w.writeF64(allocator, types.toFlonum(val));
        return;
    }

    if (types.isPointer(val)) {
        const obj = types.toObject(val);
        // A shareable object already emitted becomes a back-reference
        // (kaappi#2111), so shared structure and cycles read back as the same
        // object, not a fresh copy per reference.
        switch (obj.tag) {
            .pair, .string, .vector, .bytevector => {
                if (seen.get(@intFromPtr(obj))) |id| {
                    try w.writeU8(allocator, bf.TAG_BACKREF);
                    try w.writeU32(allocator, id);
                    return;
                }
            },
            else => {},
        }
        switch (obj.tag) {
            .symbol => {
                const sym = obj.as(types.Symbol);
                if (sym.name.len > bf.MAX_SYMBOL_BYTES) return BytecodeError.LimitExceeded;
                try w.writeU8(allocator, bf.TAG_SYMBOL);
                try w.writeU16(allocator, @intCast(sym.name.len));
                try w.writeBytes(allocator, sym.name);
            },
            .string => {
                const str = obj.as(types.SchemeString);
                if (str.data.len > bf.MAX_STRING_BYTES) return BytecodeError.LimitExceeded;
                try noteShared(seen, obj);
                try w.writeU8(allocator, bf.TAG_STRING);
                try w.writeU8(allocator, immutableByte(obj));
                try w.writeU32(allocator, @intCast(str.data.len));
                try w.writeBytes(allocator, str.data);
            },
            .function => {
                const func = obj.as(Function);
                const idx = findFunctionIndex(all_funcs, func) orelse return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, bf.TAG_FUNCTION);
                try w.writeU32(allocator, idx);
            },
            .closure => {
                // kaappi#1888: a procedural transformer's `proc` may be a
                // closure. The function table carries the inner Function; the
                // captured upvalues ride along as ordinary constants.
                const cls = obj.as(types.Closure);
                const idx = findFunctionIndex(all_funcs, cls.func) orelse return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, bf.TAG_CLOSURE);
                try w.writeU32(allocator, idx);
                try w.writeU32(allocator, @intCast(cls.upvalues.len));
                for (cls.upvalues) |uv| {
                    try writeConstant(w, allocator, uv, all_funcs, seen, depth + 1);
                }
            },
            .pair => {
                // Iterative over the cdr spine: a quoted list of N elements
                // costs no recursion depth (kaappi#2113). Registration order —
                // this pair, then its car's subtree, then the cdr — must
                // mirror readConstant's exactly so back-reference ids agree.
                var cur = val;
                while (true) {
                    const cobj = types.toObject(cur);
                    try noteShared(seen, cobj);
                    try w.writeU8(allocator, bf.TAG_PAIR);
                    try w.writeU8(allocator, immutableByte(cobj));
                    try writeConstant(w, allocator, types.car(cur), all_funcs, seen, depth + 1);
                    const cdr_val = types.cdr(cur);
                    if (types.isPointer(cdr_val) and
                        types.toObject(cdr_val).tag == .pair and
                        !seen.contains(@intFromPtr(types.toObject(cdr_val))))
                    {
                        cur = cdr_val;
                        continue;
                    }
                    // Immediate, non-pair, or an already-seen pair (a shared
                    // or cyclic tail, emitted as a back-reference above).
                    try writeConstant(w, allocator, cdr_val, all_funcs, seen, depth + 1);
                    return;
                }
            },
            .vector => {
                const vec = obj.as(types.Vector);
                if (vec.data.len > bf.MAX_VECTOR_LEN) return BytecodeError.LimitExceeded;
                try noteShared(seen, obj);
                try w.writeU8(allocator, bf.TAG_VECTOR);
                try w.writeU8(allocator, immutableByte(obj));
                try w.writeU32(allocator, @intCast(vec.data.len));
                for (vec.data) |elem| {
                    try writeConstant(w, allocator, elem, all_funcs, seen, depth + 1);
                }
            },
            .bytevector => {
                const bv = obj.as(types.Bytevector);
                if (bv.data.len > bf.MAX_BYTEVECTOR_LEN) return BytecodeError.LimitExceeded;
                try noteShared(seen, obj);
                try w.writeU8(allocator, bf.TAG_BYTEVECTOR);
                try w.writeU8(allocator, immutableByte(obj));
                try w.writeU32(allocator, @intCast(bv.data.len));
                try w.writeBytes(allocator, bv.data);
            },
            .bignum => {
                const bn = obj.as(types.Bignum);
                if (bn.len > bf.MAX_BIGNUM_LIMBS) return BytecodeError.LimitExceeded;
                // The reader rejects a denormalized bignum (zero limbs, or a
                // zero top limb); a canonical one never has either.
                if (bn.len == 0 or bn.limbs[bn.len - 1] == 0) return BytecodeError.UnsupportedConstant;
                try w.writeU8(allocator, bf.TAG_BIGNUM);
                try w.writeU8(allocator, if (bn.positive) @as(u8, 1) else @as(u8, 0));
                try w.writeU32(allocator, @intCast(bn.len));
                for (bn.limbs[0..bn.len]) |limb| {
                    try w.writeU64(allocator, limb);
                }
            },
            .rational => {
                const rat = obj.as(types.Rational);
                try w.writeU8(allocator, bf.TAG_RATIONAL);
                try writeConstant(w, allocator, rat.numerator, all_funcs, seen, depth + 1);
                try writeConstant(w, allocator, rat.denominator, all_funcs, seen, depth + 1);
            },
            .complex => {
                const cx = obj.as(types.Complex);
                // Components are written as nested constants (fixnum /
                // bignum / rational / flonum), digit-exact like every other
                // value — the old f64+flags encoding could not carry an
                // exact component (kaappi#2166). A non-real component is
                // unrepresentable, so the writer refuses it loudly (review).
                if (!isRealComponent(cx.real) or !isRealComponent(cx.imag))
                    return BytecodeError.UnsupportedConstant;
                try w.writeU8(allocator, bf.TAG_COMPLEX);
                try writeConstant(w, allocator, cx.real, all_funcs, seen, depth + 1);
                try writeConstant(w, allocator, cx.imag, all_funcs, seen, depth + 1);
            },
            else => return BytecodeError.UnsupportedConstant,
        }
        return;
    }

    return BytecodeError.UnsupportedConstant;
}

/// A component Value a serialized Complex may hold: any real number
/// (fixnum/bignum/rational/flonum), never a complex.
fn isRealComponent(v: Value) bool {
    return types.isFixnum(v) or types.isFlonum(v) or types.isBignum(v) or types.isRationalObj(v);
}

// ---------------------------------------------------------------------------
// Enhanced writeFile that records the top-level function count
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Function section (shared by all three entry kinds)
// ---------------------------------------------------------------------------

/// Write the header + function table. `roots` are the functions to serialize
/// first (in order), with nested functions collected after them;
/// `top_level_count` names how many of `roots` are replayable top-level forms —
/// for library entries the aux functions (procedural-transformer procs) that
/// follow must NOT count. `seen` is the whole-file shared-structure map, owned
/// by the caller so later sections (transformer patterns/templates) continue
/// the same id sequence.
fn writeFuncsSection(
    w: *Writer,
    allocator: std.mem.Allocator,
    roots: []*Function,
    top_level_count: u32,
    entry_kind: u8,
    source_hash: u64,
    source_path: []const u8,
    seen: *SharedMap,
) !std.ArrayList(*Function) {
    var all_funcs_list = try collectFunctions(allocator, roots);
    // The refusal paths below (kaappi#2113) make mid-write errors ordinary;
    // don't leak the collected list when one fires.
    errdefer all_funcs_list.deinit(allocator);
    const all_funcs = all_funcs_list.items;

    // Refuse anything the reader's structural caps would reject (kaappi#2113):
    // an entry past any of them could be written but never loaded — a
    // permanent, invisible cache miss.
    if (all_funcs.len > bf.MAX_FUNCTIONS) return BytecodeError.LimitExceeded;
    if (top_level_count > roots.len or top_level_count > bf.MAX_TOP_LEVEL_FUNCTIONS) return BytecodeError.LimitExceeded;

    try w.writeBytes(allocator, &bf.MAGIC);
    try w.writeU16(allocator, bf.VERSION);
    try w.writeU64(allocator, source_hash);
    try w.writeU64(allocator, bf.compilerHash());
    // Provenance (v10): the build that produced this cache and the source it
    // came from. Folded into no hash — purely for `kaappi cache status` to
    // report. The build id is also part of `compilerHash`, so a stale entry is
    // rejected on load regardless of what these strings say.
    try w.writeStr(allocator, build_options.git_build_id);
    try w.writeStr(allocator, source_path);
    // v13 (kaappi#1888): the entry kind selects the tail layout — program
    // slots, bundle sections, or the library sections.
    try w.writeU8(allocator, entry_kind);
    try w.writeU32(allocator, @intCast(all_funcs.len));
    try w.writeU32(allocator, top_level_count);

    for (all_funcs) |func| {
        if (func.code.items.len > bf.MAX_CODE_BYTES) return BytecodeError.LimitExceeded;
        if (func.constants.items.len > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.LimitExceeded;
        if (func.line_table.items.len > bf.MAX_CODE_BYTES) return BytecodeError.LimitExceeded;

        try w.writeU8(allocator, func.arity);
        try w.writeU16(allocator, func.locals_count);
        try w.writeU16(allocator, func.upvalue_count);
        try w.writeU8(allocator, if (func.is_variadic) @as(u8, 1) else @as(u8, 0));

        if (func.name) |name| {
            if (name.len > bf.MAX_SYMBOL_BYTES) return BytecodeError.LimitExceeded;
            try w.writeU16(allocator, @intCast(name.len));
            try w.writeBytes(allocator, name);
        } else {
            try w.writeU16(allocator, 0);
        }

        try w.writeU32(allocator, @intCast(func.code.items.len));
        try w.writeBytes(allocator, func.code.items);

        try w.writeU32(allocator, @intCast(func.constants.items.len));
        for (func.constants.items) |constant| {
            try writeConstant(w, allocator, constant, all_funcs, seen, 0);
        }

        // Debug info: source_line and line_table (added in v7; col added in v9)
        try w.writeU32(allocator, func.source_line);
        try w.writeU32(allocator, @intCast(func.line_table.items.len));
        for (func.line_table.items) |entry| {
            try w.writeU16(allocator, entry.offset);
            try w.writeU32(allocator, entry.line);
            try w.writeU32(allocator, entry.col);
        }
    }

    return all_funcs_list;
}

fn writeBufferToFile(w: *Writer, path: []const u8) !void {
    if (comptime is_wasm) return BytecodeError.WriteError;
    var path_buf: [platform.PATH_MAX]u8 = undefined;
    if (path.len >= path_buf.len) return BytecodeError.WriteError;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const fd = platform.openWriteTrunc(path_buf[0..path.len :0], 0o644) catch return BytecodeError.WriteError;
    defer _ = platform.close(fd);

    var total: usize = 0;
    while (total < w.buf.items.len) {
        const result = platform.write(fd, w.buf.items.ptr + total, w.buf.items.len - total);
        if (result < 0) {
            if (platform.errno(result) == .INTR) continue;
            return BytecodeError.WriteError;
        }
        if (result == 0) return BytecodeError.WriteError;
        total += @as(usize, @intCast(result));
    }
}

pub fn writeFileWithTopLevel(allocator: std.mem.Allocator, top_level_funcs: []*Function, source_hash: u64, source_path: []const u8, path: []const u8) !void {
    // No declarations recorded → every top-level form is a compiled function,
    // in order (the synthesized slots below).
    var w = Writer.init();
    defer w.deinit(allocator);
    var seen = SharedMap.init(allocator);
    defer seen.deinit();

    var all_funcs_list = try writeFuncsSection(&w, allocator, top_level_funcs, @intCast(top_level_funcs.len), bf.ENTRY_PROGRAM, source_hash, source_path, &seen);
    defer all_funcs_list.deinit(allocator);

    try w.writeU32(allocator, @intCast(top_level_funcs.len));
    for (top_level_funcs, 0..) |_, i| {
        try w.writeU8(allocator, bf.SLOT_FUNCTION);
        try w.writeU32(allocator, @intCast(i));
    }

    try writeIncludeAndDepSections(&w, allocator, &.{}, &.{});

    // Empty bundled files and preamble sections (regular cache files)
    try w.writeU32(allocator, 0);
    try w.writeU32(allocator, 0);

    try writeBufferToFile(&w, path);
}

/// How a warm run replays one top-level form of a program entry (kaappi#1888):
/// execute the compiled function, or re-read and re-dispatch the declaration's
/// source text through `handleTopLevelForm`. Positional — the slot order IS
/// the top-level form order, so an `import` between two defines stays between
/// them (the #2200 reorder class cannot arise).
pub const Slot = union(enum) {
    /// Index into the entry's top-level functions (`funcs[0..top_level_count]`).
    function: u32,
    /// Verbatim source bytes of a declaration the VM interprets (`import`,
    /// `define-library`, `include`, ...), plus its 1-based source line for
    /// error reporting parity with the cold path and the reader's fold-case
    /// state at the time the form was read — a `#!fold-case` directive falls
    /// inside an earlier form's span, so a per-slot re-parse must be told
    /// (#1888 review).
    declaration: struct { line: u32, src: []const u8, fold_case: bool = false },
};

/// Write a program entry whose top-level stream interleaves compiled
/// functions with interpreted declarations (kaappi#1888). `slots` is the full
/// form stream in order; each `.function` slot's index refers to the
/// entry's top-level function table.
pub fn writeFileWithSlots(
    allocator: std.mem.Allocator,
    top_level_funcs: []*Function,
    slots: []const Slot,
    includes: []const bf.IncludeRecord,
    deps: []const bf.DepRecord,
    source_hash: u64,
    source_path: []const u8,
    path: []const u8,
) !void {
    var w = Writer.init();
    defer w.deinit(allocator);
    var seen = SharedMap.init(allocator);
    defer seen.deinit();

    var all_funcs_list = try writeFuncsSection(&w, allocator, top_level_funcs, @intCast(top_level_funcs.len), bf.ENTRY_PROGRAM, source_hash, source_path, &seen);
    defer all_funcs_list.deinit(allocator);

    if (slots.len > bf.MAX_TOP_LEVEL_FUNCTIONS) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, @intCast(slots.len));
    for (slots) |slot| {
        switch (slot) {
            .function => |idx| {
                if (idx >= top_level_funcs.len) return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, bf.SLOT_FUNCTION);
                try w.writeU32(allocator, idx);
            },
            .declaration => |d| {
                if (d.src.len > bf.MAX_STRING_BYTES) return BytecodeError.LimitExceeded;
                try w.writeU8(allocator, bf.SLOT_DECLARATION);
                try w.writeU32(allocator, d.line);
                try w.writeU8(allocator, if (d.fold_case) @as(u8, 1) else @as(u8, 0));
                try w.writeU32(allocator, @intCast(d.src.len));
                try w.writeBytes(allocator, d.src);
            },
        }
    }

    try writeIncludeAndDepSections(&w, allocator, includes, deps);

    try w.writeU32(allocator, 0);
    try w.writeU32(allocator, 0);

    try writeBufferToFile(&w, path);
}

/// The include/dependency invalidation sections, shared by the program and
/// library entry kinds (#1888 review: a program's compiled slots embed
/// imported-macro expansions, so its entry must stale exactly like a
/// library's).
fn writeIncludeAndDepSections(w: *Writer, allocator: std.mem.Allocator, includes: []const bf.IncludeRecord, deps: []const bf.DepRecord) !void {
    if (includes.len > bf.MAX_LIBRARY_INCLUDES) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, @intCast(includes.len));
    for (includes) |inc| {
        if (inc.path.len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.LimitExceeded;
        try w.writeU16(allocator, @intCast(inc.path.len));
        try w.writeBytes(allocator, inc.path);
        try w.writeU64(allocator, inc.hash);
    }

    if (deps.len > bf.MAX_LIBRARY_DEPS) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, @intCast(deps.len));
    for (deps) |dep| {
        if (dep.rel_path.len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.LimitExceeded;
        if (dep.resolved_path.len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.LimitExceeded;
        if (dep.lib_name.len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.LimitExceeded;
        try w.writeU16(allocator, @intCast(dep.rel_path.len));
        try w.writeBytes(allocator, dep.rel_path);
        try w.writeU16(allocator, @intCast(dep.resolved_path.len));
        try w.writeBytes(allocator, dep.resolved_path);
        try w.writeU64(allocator, dep.source_hash);
        try w.writeU16(allocator, @intCast(dep.lib_name.len));
        try w.writeBytes(allocator, dep.lib_name);
    }
}

/// One replay event of a `.sld` library entry (kaappi#1888), in the exact
/// order the cold load produced them.
pub const LibEventRecord = union(enum) {
    /// Run form_funcs[idx] with `env` pointed at the reconstructed lib_env.
    run_lib: u32,
    /// Run form_funcs[idx] with `env` = null (compiled against vm.globals).
    run_global: u32,
    /// Put the transformer into lib_env under `name`. The writer builds the
    /// deduplicated transformer table from these.
    register_tx: struct { name: []const u8, tx: *types.Transformer },
};

/// An include-family file a cold library load read, with its content hash —
/// the invalidation dimension the .sld's own source hash cannot see.
pub const IncludeRecord = struct { path: []const u8, hash: u64 };

/// A file-backed dependency library the load resolved and read. Validated at
/// warm time by re-resolving `rel_path` through the current lib-path (a
/// `--lib-path` change that re-resolves elsewhere is a miss) and re-hashing
/// the file at the recorded path.
pub const DepRecord = struct { rel_path: []const u8, resolved_path: []const u8, source_hash: u64, lib_name: []const u8 };

/// Write a `.sld` library cache entry (kaappi#1888). `form_funcs` are the
/// library body's compiled top-level functions in run order; `events` is the
/// interleaved replay log (transformer registrations included); `includes` and
/// `deps` are the invalidation records.
pub fn writeFileWithLibrary(
    allocator: std.mem.Allocator,
    form_funcs: []*Function,
    events: []const LibEventRecord,
    includes: []const IncludeRecord,
    deps: []const DepRecord,
    source_hash: u64,
    source_path: []const u8,
    path: []const u8,
) !void {
    var w = Writer.init();
    defer w.deinit(allocator);
    var seen = SharedMap.init(allocator);
    defer seen.deinit();

    // The transformer table, deduplicated by object identity, plus the aux
    // functions procedural transformers reference (their procs) — appended
    // after the form functions so event indices stay within form_funcs.
    var tx_table: std.ArrayList(*types.Transformer) = .empty;
    defer tx_table.deinit(allocator);
    var aux: std.ArrayList(*Function) = .empty;
    defer aux.deinit(allocator);
    for (events) |ev| {
        if (ev != .register_tx) continue;
        const tx = ev.register_tx.tx;
        var found = false;
        for (tx_table.items) |t| {
            if (t == tx) {
                found = true;
                break;
            }
        }
        if (!found) {
            if (tx_table.items.len >= bf.MAX_LIBRARY_TRANSFORMERS) return BytecodeError.LimitExceeded;
            tx_table.append(allocator, tx) catch return BytecodeError.OutOfMemory;
            if (tx.kind != .syntax_rules) {
                try collectProcFunction(allocator, tx.proc, &aux, form_funcs);
            }
        }
    }

    var roots: std.ArrayList(*Function) = .empty;
    defer roots.deinit(allocator);
    roots.appendSlice(allocator, form_funcs) catch return BytecodeError.OutOfMemory;
    roots.appendSlice(allocator, aux.items) catch return BytecodeError.OutOfMemory;

    var all_funcs_list = try writeFuncsSection(&w, allocator, roots.items, @intCast(form_funcs.len), bf.ENTRY_LIBRARY, source_hash, source_path, &seen);
    defer all_funcs_list.deinit(allocator);
    const all_funcs = all_funcs_list.items;

    // Transformer table. Every field is data (identifiers, datum trees, slot
    // ids); `def_env` is deliberately absent — the warm load re-points it at
    // the reconstructed lib_env.
    try w.writeU32(allocator, @intCast(tx_table.items.len));
    for (tx_table.items) |tx| {
        try writeTransformer(&w, allocator, tx, all_funcs, &seen);
    }

    // Events.
    if (events.len > bf.MAX_LIBRARY_EVENTS) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, @intCast(events.len));
    for (events) |ev| {
        switch (ev) {
            .run_lib => |idx| {
                if (idx >= form_funcs.len) return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, bf.EVENT_RUN_LIB);
                try w.writeU32(allocator, idx);
            },
            .run_global => |idx| {
                if (idx >= form_funcs.len) return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, bf.EVENT_RUN_GLOBAL);
                try w.writeU32(allocator, idx);
            },
            .register_tx => |reg| {
                if (reg.name.len > bf.MAX_TX_NAME_BYTES) return BytecodeError.LimitExceeded;
                var table_index: ?u32 = null;
                for (tx_table.items, 0..) |t, i| {
                    if (t == reg.tx) {
                        table_index = @intCast(i);
                        break;
                    }
                }
                try w.writeU8(allocator, bf.EVENT_REGISTER_TX);
                try w.writeU16(allocator, @intCast(reg.name.len));
                try w.writeBytes(allocator, reg.name);
                try w.writeU32(allocator, table_index orelse return BytecodeError.CorruptedFile);
            },
        }
    }

    // Include/dependency records (shared section helper).
    try writeIncludeAndDepSections(&w, allocator, includes, deps);

    // Empty bundle tail (uniform with the other kinds).
    try w.writeU32(allocator, 0);
    try w.writeU32(allocator, 0);

    try writeBufferToFile(&w, path);
}

/// Append the Function behind a procedural transformer's `proc` to `aux` (a
/// bare procedure directly, or a closure's inner function), deduplicated
/// against the form functions and earlier aux entries — a proc shared by two
/// transformers must keep its identity across the round trip.
fn collectProcFunction(allocator: std.mem.Allocator, proc: Value, aux: *std.ArrayList(*Function), form_funcs: []*Function) !void {
    var func: ?*Function = null;
    if (types.isFunction(proc)) {
        func = types.toObject(proc).as(Function);
    } else if (types.isClosure(proc)) {
        func = types.toObject(proc).as(types.Closure).func;
    } else {
        // A proc the codec cannot represent (native function, record, ...):
        // refuse so the whole library stays uncached rather than half-serializing.
        return BytecodeError.UnsupportedConstant;
    }
    const f = func.?;
    for (form_funcs) |existing| {
        if (existing == f) return;
    }
    for (aux.items) |existing| {
        if (existing == f) return;
    }
    aux.append(allocator, f) catch return BytecodeError.OutOfMemory;
}

fn writeTxStr(w: *Writer, allocator: std.mem.Allocator, s: []const u8) !void {
    if (s.len > bf.MAX_SYMBOL_BYTES) return BytecodeError.LimitExceeded;
    try w.writeU16(allocator, @intCast(s.len));
    try w.writeBytes(allocator, s);
}

fn writeTransformer(w: *Writer, allocator: std.mem.Allocator, tx: *types.Transformer, all_funcs: []*Function, seen: *SharedMap) !void {
    // let-syntax peer snapshots are computed by compileLetSyntax for
    // body-scoped macros and never occur for a lib_env-registered transformer;
    // refuse rather than silently drop them (they drive sibling suppression).
    if (tx.let_syntax_peer_names.len != 0 or tx.let_syntax_peer_vals.len != 0)
        return BytecodeError.UnsupportedConstant;

    try w.writeU8(allocator, switch (tx.kind) {
        .syntax_rules => 0,
        .er_macro => 1,
        .lisp_macro => 2,
    });
    try w.writeU16(allocator, tx.num_rules);

    if (tx.literals.len > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, @intCast(tx.literals.len));
    for (tx.literals) |v| try writeConstant(w, allocator, v, all_funcs, seen, 0);
    if (tx.num_rules > bf.MAX_CONSTANTS_PER_FUNCTION) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, tx.num_rules);
    for (tx.patterns[0..tx.num_rules]) |v| try writeConstant(w, allocator, v, all_funcs, seen, 0);
    try w.writeU32(allocator, tx.num_rules);
    for (tx.templates[0..tx.num_rules]) |v| try writeConstant(w, allocator, v, all_funcs, seen, 0);
    // The procedural body (NIL for syntax_rules); written as one ordinary
    // constant so a Function/Closure proc resolves through the function table.
    try writeConstant(w, allocator, tx.proc, all_funcs, seen, 0);

    if (tx.custom_ellipsis) |ce| {
        try w.writeU8(allocator, 1);
        try writeTxStr(w, allocator, ce);
    } else {
        try w.writeU8(allocator, 0);
    }

    try w.writeU32(allocator, @intCast(tx.literal_bound.len));
    for (tx.literal_bound) |slot| try w.writeU32(allocator, slot);

    try w.writeU32(allocator, @intCast(tx.captured_locals.len));
    for (tx.captured_locals) |cl| {
        try writeTxStr(w, allocator, cl.name);
        try w.writeU16(allocator, cl.slot);
    }

    try w.writeU32(allocator, @intCast(tx.bound_free_refs.len));
    for (tx.bound_free_refs) |name| try writeTxStr(w, allocator, name);

    try w.writeU32(allocator, @intCast(tx.def_site_local_refs.len));
    for (tx.def_site_local_refs) |name| try writeTxStr(w, allocator, name);

    if (tx.def_lib_name) |dln| {
        try w.writeU8(allocator, 1);
        try writeTxStr(w, allocator, dln);
    } else {
        try w.writeU8(allocator, 0);
    }

    try w.writeU8(allocator, if (tx.finalized) 1 else 0);
    try w.writeU8(allocator, if (tx.peers_computed) 1 else 0);
}

/// Write a standalone .sbc with bundled library sources and preamble forms.
pub fn writeFileWithBundle(
    allocator: std.mem.Allocator,
    top_level_funcs: []*Function,
    source_hash: u64,
    source_path: []const u8,
    bundled_files: *const std.StringHashMap([]const u8),
    preamble: []const []const u8,
    path: []const u8,
) !void {
    var w = Writer.init();
    defer w.deinit(allocator);
    var seen = SharedMap.init(allocator);
    defer seen.deinit();

    var all_funcs_list = try writeFuncsSection(&w, allocator, top_level_funcs, @intCast(top_level_funcs.len), bf.ENTRY_BUNDLE, source_hash, source_path, &seen);
    defer all_funcs_list.deinit(allocator);

    // Bundled files section. Same refusal contract as the constant limits
    // (kaappi#2113): anything the reader would reject fails the write with
    // the reason, instead of producing an artifact that only fails at run
    // time as "invalid embedded bytecode". The key cap also keeps the u16
    // length cast below from being reachable.
    if (bundled_files.count() > bf.MAX_BUNDLED_FILES) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, @intCast(bundled_files.count()));
    var it = bundled_files.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;
        if (key.len > bf.MAX_HEADER_STR_BYTES) return BytecodeError.LimitExceeded;
        if (val.len > bf.MAX_STRING_BYTES) return BytecodeError.LimitExceeded;
        try w.writeU16(allocator, @intCast(key.len));
        try w.writeBytes(allocator, key);
        try w.writeU32(allocator, @intCast(val.len));
        try w.writeBytes(allocator, val);
    }

    // Preamble section (top-level forms to replay at runtime)
    if (preamble.len > bf.MAX_PREAMBLE_FORMS) return BytecodeError.LimitExceeded;
    try w.writeU32(allocator, @intCast(preamble.len));
    for (preamble) |src| {
        if (src.len > bf.MAX_STRING_BYTES) return BytecodeError.LimitExceeded;
        try w.writeU32(allocator, @intCast(src.len));
        try w.writeBytes(allocator, src);
    }

    try writeBufferToFile(&w, path);
}
