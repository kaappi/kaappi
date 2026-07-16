//! Bytecode serializer: Function graph → `.sbc` bytes.
//!
//! The write half of the `.sbc` codec. Shares the format contract (magic,
//! version, constant tags, size limits, `compilerHash`) with the deserializer
//! via `bytecode_file.zig`; see `bytecode_file_read.zig` for the inverse.

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

fn writeConstant(w: *Writer, allocator: std.mem.Allocator, val: Value, all_funcs: []*Function, depth: u32) !void {
    if (depth > 256) {
        try w.writeU8(allocator, bf.TAG_NIL);
        return;
    }
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
        switch (obj.tag) {
            .symbol => {
                const sym = obj.as(types.Symbol);
                if (sym.name.len > bf.MAX_SYMBOL_BYTES) return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, bf.TAG_SYMBOL);
                try w.writeU16(allocator, @intCast(sym.name.len));
                try w.writeBytes(allocator, sym.name);
            },
            .string => {
                const str = obj.as(types.SchemeString);
                try w.writeU8(allocator, bf.TAG_STRING);
                try w.writeU32(allocator, @intCast(str.data.len));
                try w.writeBytes(allocator, str.data);
            },
            .function => {
                const func = obj.as(Function);
                const idx = findFunctionIndex(all_funcs, func) orelse return BytecodeError.CorruptedFile;
                try w.writeU8(allocator, bf.TAG_FUNCTION);
                try w.writeU32(allocator, idx);
            },
            .pair => {
                try w.writeU8(allocator, bf.TAG_PAIR);
                try writeConstant(w, allocator, types.car(val), all_funcs, depth + 1);
                try writeConstant(w, allocator, types.cdr(val), all_funcs, depth + 1);
            },
            .vector => {
                const vec = obj.as(types.Vector);
                try w.writeU8(allocator, bf.TAG_VECTOR);
                try w.writeU32(allocator, @intCast(vec.data.len));
                for (vec.data) |elem| {
                    try writeConstant(w, allocator, elem, all_funcs, depth + 1);
                }
            },
            .bytevector => {
                const bv = obj.as(types.Bytevector);
                try w.writeU8(allocator, bf.TAG_BYTEVECTOR);
                try w.writeU32(allocator, @intCast(bv.data.len));
                try w.writeBytes(allocator, bv.data);
            },
            .bignum => {
                const bn = obj.as(types.Bignum);
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
                try writeConstant(w, allocator, rat.numerator, all_funcs, depth + 1);
                try writeConstant(w, allocator, rat.denominator, all_funcs, depth + 1);
            },
            .complex => {
                const cx = obj.as(types.Complex);
                try w.writeU8(allocator, bf.TAG_COMPLEX);
                try w.writeF64(allocator, cx.real);
                try w.writeF64(allocator, cx.imag);
                try w.writeU8(allocator, if (cx.exact_real) @as(u8, 1) else @as(u8, 0));
                try w.writeU8(allocator, if (cx.exact_imag) @as(u8, 1) else @as(u8, 0));
            },
            else => {
                try w.writeU8(allocator, bf.TAG_NIL);
            },
        }
        return;
    }

    // Fallback for unrecognized values
    try w.writeU8(allocator, bf.TAG_NIL);
}

// ---------------------------------------------------------------------------
// Enhanced writeFile that records the top-level function count
// ---------------------------------------------------------------------------

fn writeFunctionsToBuffer(w: *Writer, allocator: std.mem.Allocator, top_level_funcs: []*Function, source_hash: u64, source_path: []const u8) !std.ArrayList(*Function) {
    const all_funcs_list = try collectFunctions(allocator, top_level_funcs);
    const all_funcs = all_funcs_list.items;

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
    try w.writeU32(allocator, @intCast(all_funcs.len));
    try w.writeU32(allocator, @intCast(top_level_funcs.len));

    for (all_funcs) |func| {
        try w.writeU8(allocator, func.arity);
        try w.writeU16(allocator, func.locals_count);
        try w.writeU16(allocator, func.upvalue_count);
        try w.writeU8(allocator, if (func.is_variadic) @as(u8, 1) else @as(u8, 0));

        if (func.name) |name| {
            if (name.len > bf.MAX_SYMBOL_BYTES) return BytecodeError.CorruptedFile;
            try w.writeU16(allocator, @intCast(name.len));
            try w.writeBytes(allocator, name);
        } else {
            try w.writeU16(allocator, 0);
        }

        try w.writeU32(allocator, @intCast(func.code.items.len));
        try w.writeBytes(allocator, func.code.items);

        try w.writeU32(allocator, @intCast(func.constants.items.len));
        for (func.constants.items) |constant| {
            try writeConstant(w, allocator, constant, all_funcs, 0);
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
    var w = Writer.init();
    defer w.deinit(allocator);

    var all_funcs_list = try writeFunctionsToBuffer(&w, allocator, top_level_funcs, source_hash, source_path);
    defer all_funcs_list.deinit(allocator);

    // Empty bundled files and preamble sections (regular cache files)
    try w.writeU32(allocator, 0);
    try w.writeU32(allocator, 0);

    try writeBufferToFile(&w, path);
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

    var all_funcs_list = try writeFunctionsToBuffer(&w, allocator, top_level_funcs, source_hash, source_path);
    defer all_funcs_list.deinit(allocator);

    // Bundled files section
    try w.writeU32(allocator, @intCast(bundled_files.count()));
    var it = bundled_files.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;
        try w.writeU16(allocator, @intCast(key.len));
        try w.writeBytes(allocator, key);
        try w.writeU32(allocator, @intCast(val.len));
        try w.writeBytes(allocator, val);
    }

    // Preamble section (top-level forms to replay at runtime)
    try w.writeU32(allocator, @intCast(preamble.len));
    for (preamble) |src| {
        try w.writeU32(allocator, @intCast(src.len));
        try w.writeBytes(allocator, src);
    }

    try writeBufferToFile(&w, path);
}
