const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const build_options = @import("build_options");
const types = @import("types.zig");
const memory = @import("memory.zig");
const main = @import("main.zig");
const file_utils = @import("file_utils.zig");
const write = @import("bytecode_file_write.zig");
const read = @import("bytecode_file_read.zig");
const Value = types.Value;
const Function = types.Function;
const GC = memory.GC;

// ---------------------------------------------------------------------------
// Shared format contract
//
// This file is the hub of the `.sbc` codec. It owns the on-disk format
// constants, the error set, and the cache-key hashing that both halves agree
// on, then re-exports the serializer (`bytecode_file_write.zig`) and
// deserializer (`bytecode_file_read.zig`) so external callers see a single
// `bytecode_file` module. Tests exercising the full round-trip live here.
// ---------------------------------------------------------------------------

// File format constants
pub const MAGIC = [4]u8{ 'K', 'P', 'B', 'C' };
// v11 (kaappi#2110/#2111/#2113): pair/string/vector/bytevector constants carry
// an immutability byte after their tag, so a literal that must reject
// `set-car!` cold still rejects it warm; a shareable constant reached twice is
// emitted once and referenced by `TAG_BACKREF` afterwards, so datum-label
// sharing and cycles round-trip as the same object; and the writer now
// enforces every limit the reader enforces, refusing (never truncating) an
// entry that could not be read back. The compiler hash also folds in the
// compile target (kaappi#2155).
// v10 (kaappi#1516): the header carries the producing build id and the source
// path after the compiler hash, so `kaappi cache status` can report which
// source and which binary produced each cache entry. The compiler hash itself
// now folds in the git build id (see `compilerHash`), so a dev rebuild at the
// same version string — different commit, or clean vs. dirty — no longer
// collides. Two *dirty* builds at the same commit still do; see compilerHashFor.
// v9 (kaappi#1506): line-table entries carry a column alongside the line so
// runtime errors can report `file:line:col`. A version mismatch makes
// `readFileWithTopLevel` return null, so older `.sbc` caches are ignored and
// silently recompiled — no stale-cache hazard.
/// Format version. v12 (kaappi#2166): TAG_COMPLEX payload changed from two
/// f64s + two exactness bytes to two nested component constants, so the
/// wire format is incompatible with v11 files.
pub const VERSION: u16 = 12;
pub const MAX_FUNCTIONS: u32 = 16_384;
pub const MAX_TOP_LEVEL_FUNCTIONS: u32 = 4_096;
pub const MAX_CODE_BYTES: u32 = 4_194_304;
pub const MAX_CONSTANTS_PER_FUNCTION: u32 = 65_535;
pub const MAX_SYMBOL_BYTES: u16 = 4_096;
// Upper bound for the two length-prefixed header strings (build id, source
// path). A path can approach PATH_MAX (4096 on Linux); build ids are short.
// Writes truncate to this; reads reject anything longer as corrupt.
pub const MAX_HEADER_STR_BYTES: u16 = 4_096;
pub const MAX_STRING_BYTES: u32 = 1_048_576;
pub const MAX_VECTOR_LEN: u32 = 262_144;
pub const MAX_BYTEVECTOR_LEN: u32 = 1_048_576;
pub const MAX_BIGNUM_LIMBS: u32 = 262_144;
pub const MAX_CONSTANT_DEPTH: u32 = 256;
// Bundle-section caps (`--compile` artifacts; the auto-run cache writes both
// sections empty). Shared by both halves so the writer refuses what the
// reader rejects, same contract as the constant limits above. A bundled-file
// *path* is additionally capped at `MAX_HEADER_STR_BYTES` on the write side —
// stricter than the reader's u16 length encoding, which is safe (a stricter
// writer can never produce an unloadable artifact) and keeps the `@intCast`
// to u16 from being reachable.
pub const MAX_BUNDLED_FILES: u32 = 4_096;
pub const MAX_PREAMBLE_FORMS: u32 = 4_096;

// Constant type tags
pub const TAG_FIXNUM: u8 = 0;
pub const TAG_FLONUM: u8 = 1;
pub const TAG_SYMBOL: u8 = 2;
pub const TAG_STRING: u8 = 3;
pub const TAG_BOOLEAN: u8 = 4;
pub const TAG_NIL: u8 = 5;
pub const TAG_VOID: u8 = 6;
pub const TAG_CHAR: u8 = 7;
pub const TAG_FUNCTION: u8 = 8;
pub const TAG_PAIR: u8 = 9;
pub const TAG_VECTOR: u8 = 10;
pub const TAG_BYTEVECTOR: u8 = 11;
pub const TAG_BIGNUM: u8 = 12;
pub const TAG_RATIONAL: u8 = 13;
pub const TAG_COMPLEX: u8 = 14;
pub const TAG_EOF: u8 = 15;
pub const TAG_UNDEFINED: u8 = 16;
/// Back-reference to an already-decoded pair/string/vector/bytevector, by
/// pre-order first-encounter index (kaappi#2111). This is what lets datum-label
/// sharing (`'(#1=(1 2) #1#)`) and cyclic literals round-trip as the *same*
/// object instead of a copy per reference.
pub const TAG_BACKREF: u8 = 17;

pub const BytecodeError = error{
    InvalidMagic,
    UnsupportedVersion,
    HashMismatch,
    InvalidConstantTag,
    CorruptedFile,
    OutOfMemory,
    FileNotFound,
    ReadError,
    WriteError,
    /// The writer refused a value that would exceed a limit the reader
    /// enforces (constant nesting, string/vector/bytevector/bignum size,
    /// constants-per-function, code size, function count). Writing it anyway
    /// would produce an entry that can never load — a permanent cache miss
    /// (kaappi#2113) — so the write fails loudly instead.
    LimitExceeded,
    /// The writer met a constant the format cannot represent (an unexpected
    /// heap tag, or a denormalized bignum). Before kaappi#2113 these were
    /// silently written as TAG_NIL, which a cache HIT would then serve as a
    /// wrong constant.
    UnsupportedConstant,
};

// ---------------------------------------------------------------------------
// Public API (implemented in the read/write halves)
// ---------------------------------------------------------------------------

pub const Writer = write.Writer;
pub const writeFileWithTopLevel = write.writeFileWithTopLevel;
pub const writeFileWithBundle = write.writeFileWithBundle;

pub const DeserializeResult = read.DeserializeResult;
pub const freeDeserializeResult = read.freeDeserializeResult;
pub const HeaderInfo = read.HeaderInfo;
pub const deserializeFromBuffer = read.deserializeFromBuffer;
pub const readFromBuffer = read.readFromBuffer;
pub const readFileWithTopLevel = read.readFileWithTopLevel;
pub const readHeaderInfo = read.readHeaderInfo;

// ---------------------------------------------------------------------------
// Utility: compute source hash
// ---------------------------------------------------------------------------

pub fn sourceHash(source: []const u8) u64 {
    return std.hash.Wyhash.hash(0, source);
}

/// The target identity this binary bakes into bytecode (kaappi#2155): the
/// triple, plus the compile-time feature set `cond-expand` is resolved
/// against. All 17 release binaries are built from one clean checkout, so
/// without this component they would share a compiler hash and load each
/// other's `.sbc` — with only the *producing* target's `cond-expand` branch
/// present in it. Hashing the feature list (not just the triple) also makes
/// the key change automatically the day a feature identifier becomes arch- or
/// OS-gated in a way the triple alone would not capture.
pub const compile_target_id = blk: {
    var s: []const u8 = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag) ++ "-" ++ @tagName(builtin.abi);
    for (types.platform_features) |f| s = s ++ ";" ++ f;
    break :blk s;
};

/// The cache-key half that identifies the *compiler*. Combines the release
/// version string, the git build id (short HEAD hash, `-dirty` when the tree
/// had uncommitted changes; "unknown" when git is unavailable at build time),
/// and the compile target (`compile_target_id`, kaappi#2155). Two binaries
/// built from the same commit with a clean tree *for the same target* share a
/// key and may reuse each other's cache; a different commit, a dirty vs.
/// clean tree, or a different target differs — so a stale or cross-target
/// entry is rejected on load and recompiled. This closes most of the
/// long-standing footgun where same-version rebuilds silently ran the
/// previous binary's bytecode (kaappi#1516).
///
/// It does NOT separate two *dirty* builds at the same commit: `-dirty` is a
/// flag, not a hash of the working tree, so every uncommitted state shares one
/// build id and rebuilds of different uncommitted changes reuse each other's
/// entries. `kaappi cache clear` between rebuilds is still required when
/// A/B-testing compiler changes — see docs/dev/cache.md and
/// docs/dev/performance.md. Pure in its inputs so the keying is unit-testable.
pub fn compilerHashFor(version_str: []const u8, build_id: []const u8, target: []const u8) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(version_str);
    h.update(&[_]u8{0}); // separator: keep each boundary unambiguous
    h.update(build_id);
    h.update(&[_]u8{0});
    h.update(target);
    return h.final();
}

pub fn compilerHash() u64 {
    return compilerHashFor(main.version, build_options.git_build_id, compile_target_id);
}

// ---------------------------------------------------------------------------
// Embedded-.sbc rejection classification
// ---------------------------------------------------------------------------

/// Why `readFromBuffer` refused an embedded `.sbc` (kaappi#1930). The loader
/// collapses every header mismatch into `null`, and for a bundled binary the
/// common cause is a *stale bundle*: the `.sbc`'s compiler hash (version +
/// build id + target) differs from this binary's because the tree moved — a
/// new commit, or a clean<->dirty flip — between producing the `.sbc` and
/// building the bundler. Distinguish that from a genuinely unreadable payload
/// so the fatal diagnostic can name the real fix instead of "wrong version or
/// format".
pub const EmbeddedRejection = enum {
    /// The header is unreadable, a different format/version, or otherwise not
    /// a loadable bundle. Keep the generic message.
    invalid,
    /// The header parses but names a different compiler build; the bundle
    /// must be regenerated from the current source.
    foreign_build,
};

/// Classify a `.sbc` buffer that `readFromBuffer` just refused. Pure in its
/// input so the classification is unit-testable without a VM.
pub fn classifyEmbeddedRejection(data: []const u8) EmbeddedRejection {
    const info = read.readHeaderInfo(data) orelse return .invalid;
    return if (info.current_build) .invalid else .foreign_build;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Derive a .sbc cache path from a source path (.scm or .sld).
/// Replaces the extension with .sbc, or appends .sbc if no known extension.
pub fn getSbcPath(allocator: std.mem.Allocator, src_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, src_path, ".scm")) {
        return std.fmt.allocPrint(allocator, "{s}.sbc", .{src_path[0 .. src_path.len - 4]});
    }
    if (std.mem.endsWith(u8, src_path, ".sld")) {
        return std.fmt.allocPrint(allocator, "{s}.sbc", .{src_path[0 .. src_path.len - 4]});
    }
    return std.fmt.allocPrint(allocator, "{s}.sbc", .{src_path});
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bytecode round-trip: simple function" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    // Create a simple function with some constants
    const func = try gc.allocFunction();
    // Add some bytecode
    func.code.append(allocator, @intFromEnum(types.OpCode.load_const)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, 0) catch unreachable; // idx high
    func.code.append(allocator, 0) catch unreachable; // idx low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

    // Add a fixnum constant
    func.constants.append(allocator, types.makeFixnum(42)) catch unreachable;
    func.arity = 0;
    func.locals_count = 1;

    // Serialize
    var funcs_arr = [_]*Function{func};
    const hash: u64 = 12345;
    const path = "/tmp/kaappi_test_roundtrip.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, "test.scm", path);
    defer {
        // Clean up test file
        _ = platform.unlink(path);
    }

    // Deserialize
    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    try std.testing.expectEqual(@as(u32, 1), loaded.top_level_count);
    try std.testing.expect(loaded.funcs.len >= 1);

    const loaded_func = loaded.funcs[0];
    try std.testing.expectEqual(@as(u8, 0), loaded_func.arity);
    try std.testing.expectEqual(@as(u16, 1), loaded_func.locals_count);
    try std.testing.expectEqual(@as(usize, 8), loaded_func.code.items.len);
    try std.testing.expectEqual(@as(usize, 1), loaded_func.constants.items.len);
    try std.testing.expect(types.isFixnum(loaded_func.constants.items[0]));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(loaded_func.constants.items[0]));
}

test "bytecode round-trip: hash mismatch returns null" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

    var funcs_arr = [_]*Function{func};
    const path = "/tmp/kaappi_test_mismatch.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, 12345, "test.scm", path);
    defer {
        _ = platform.unlink(path);
    }

    // Try reading with different hash
    const result = try readFileWithTopLevel(&gc, 99999, path);
    try std.testing.expect(result == null);
}

test "bytecode round-trip: various constant types" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    // Root the function: the constant allocations below can collect, and an
    // unrooted func would be swept while we are still appending into it.
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

    // Add various constant types
    func.constants.append(allocator, types.makeFixnum(-100)) catch unreachable;
    func.constants.append(allocator, types.TRUE) catch unreachable;
    func.constants.append(allocator, types.FALSE) catch unreachable;
    func.constants.append(allocator, types.NIL) catch unreachable;
    func.constants.append(allocator, types.VOID) catch unreachable;
    func.constants.append(allocator, types.makeChar('Z')) catch unreachable;

    const sym = try gc.allocSymbol("hello");
    func.constants.append(allocator, sym) catch unreachable;

    const str = try gc.allocString("world");
    func.constants.append(allocator, str) catch unreachable;

    const flo = types.makeFlonum(3.14);
    func.constants.append(allocator, flo) catch unreachable;

    const bv_data = [_]u8{ 1, 2, 3 };
    const bv = try gc.allocBytevector(&bv_data);
    func.constants.append(allocator, bv) catch unreachable;

    func.arity = 0;
    func.locals_count = 1;

    var funcs_arr = [_]*Function{func};
    const hash: u64 = 54321;
    const path = "/tmp/kaappi_test_constants.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, "test.scm", path);
    defer {
        _ = platform.unlink(path);
    }

    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    const consts = loaded.funcs[0].constants.items;
    try std.testing.expectEqual(@as(usize, 10), consts.len);
    try std.testing.expectEqual(@as(i64, -100), types.toFixnum(consts[0]));
    try std.testing.expectEqual(types.TRUE, consts[1]);
    try std.testing.expectEqual(types.FALSE, consts[2]);
    try std.testing.expectEqual(types.NIL, consts[3]);
    try std.testing.expectEqual(types.VOID, consts[4]);
    try std.testing.expect(types.isChar(consts[5]));
    try std.testing.expectEqual(@as(u21, 'Z'), types.toChar(consts[5]));
    try std.testing.expect(types.isSymbol(consts[6]));
    try std.testing.expectEqualStrings("hello", types.symbolName(consts[6]));
    try std.testing.expect(types.isString(consts[7]));
    try std.testing.expectEqualStrings("world", types.toObject(consts[7]).as(types.SchemeString).data);
    try std.testing.expect(types.isFlonum(consts[8]));
    try std.testing.expectEqual(@as(f64, 3.14), types.toFlonum(consts[8]));
    try std.testing.expect(types.isBytevector(consts[9]));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3 }, types.toBytevector(consts[9]).data);
}

test "bytecode round-trip: nested functions" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    // Create a child function
    const child_func = try gc.allocFunction();
    child_func.code.append(allocator, @intFromEnum(types.OpCode.load_const)) catch unreachable;
    child_func.code.append(allocator, 0) catch unreachable; // dst high
    child_func.code.append(allocator, 0) catch unreachable; // dst low
    child_func.code.append(allocator, 0) catch unreachable; // idx high
    child_func.code.append(allocator, 0) catch unreachable; // idx low
    child_func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    child_func.code.append(allocator, 0) catch unreachable; // src high
    child_func.code.append(allocator, 0) catch unreachable; // src low
    child_func.constants.append(allocator, types.makeFixnum(99)) catch unreachable;
    child_func.arity = 1;
    child_func.locals_count = 1;

    // Create parent function that references child
    const parent_func = try gc.allocFunction();
    parent_func.code.append(allocator, @intFromEnum(types.OpCode.closure)) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable; // dst high
    parent_func.code.append(allocator, 0) catch unreachable; // dst low
    parent_func.code.append(allocator, 0) catch unreachable; // idx high
    parent_func.code.append(allocator, 0) catch unreachable; // idx low
    parent_func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    parent_func.code.append(allocator, 0) catch unreachable; // src high
    parent_func.code.append(allocator, 0) catch unreachable; // src low
    parent_func.constants.append(allocator, types.makePointer(&child_func.header)) catch unreachable;
    parent_func.arity = 0;
    parent_func.locals_count = 1;

    var funcs_arr = [_]*Function{parent_func};
    const hash: u64 = 77777;
    const path = "/tmp/kaappi_test_nested.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, "test.scm", path);
    defer {
        _ = platform.unlink(path);
    }

    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    try std.testing.expectEqual(@as(u32, 1), loaded.top_level_count);
    try std.testing.expect(loaded.funcs.len >= 2);

    // Check parent references child correctly
    const loaded_parent = loaded.funcs[0];
    try std.testing.expectEqual(@as(usize, 1), loaded_parent.constants.items.len);
    try std.testing.expect(types.isFunction(loaded_parent.constants.items[0]));

    const loaded_child = types.toObject(loaded_parent.constants.items[0]).as(Function);
    try std.testing.expectEqual(@as(u8, 1), loaded_child.arity);
    try std.testing.expectEqual(@as(usize, 1), loaded_child.constants.items.len);
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(loaded_child.constants.items[0]));
}

test "source hash computation" {
    const h1 = sourceHash("(+ 1 2)");
    const h2 = sourceHash("(+ 1 2)");
    const h3 = sourceHash("(+ 1 3)");

    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != h3);
}

/// A minimal single-function fixture for the constant round-trip tests below:
/// a return-only body, arity 0, ready to receive constants.
fn makeRoundTripFunc(gc: *GC) !*Function {
    const allocator = gc.allocator;
    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.arity = 0;
    func.locals_count = 1;
    return func;
}

fn roundTrip(gc: *GC, func: *Function, path: [:0]const u8) !DeserializeResult {
    var funcs_arr = [_]*Function{func};
    try writeFileWithTopLevel(gc.allocator, &funcs_arr, 0x1234, "test.scm", path);
    defer _ = platform.unlink(path);
    const result = try readFileWithTopLevel(gc, 0x1234, path);
    return result orelse error.TestUnexpectedResult;
}

test "bytecode round-trip: immutability flag preserved (kaappi#2110)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    // A literal's Object.flags.immutable must survive the codec, or a warm
    // run accepts a set-car! the cold run rejected. One immutable and one
    // mutable instance of each of the four types, so both flag values are
    // exercised for every tag.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try makeRoundTripFunc(&gc);
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();

    const c = &func.constants;
    inline for (.{ true, false }) |immutable| {
        const pair = try gc.allocPair(types.makeFixnum(1), types.makeFixnum(2));
        types.toObject(pair).flags.immutable = immutable;
        c.append(allocator, pair) catch unreachable;
        const str = try gc.allocString("abc");
        types.toObject(str).flags.immutable = immutable;
        c.append(allocator, str) catch unreachable;
        const vec = try gc.allocVectorFill(2, types.makeFixnum(7));
        types.toObject(vec).flags.immutable = immutable;
        c.append(allocator, vec) catch unreachable;
        const bv = try gc.allocBytevector(&[_]u8{ 1, 2, 3 });
        types.toObject(bv).flags.immutable = immutable;
        c.append(allocator, bv) catch unreachable;
    }

    const loaded = try roundTrip(&gc, func, "/tmp/kaappi_test_immutable.sbc");
    defer allocator.free(loaded.funcs);

    const k = loaded.funcs[0].constants.items;
    try std.testing.expectEqual(@as(usize, 8), k.len);
    for (k[0..4]) |v| try std.testing.expect(types.toObject(v).flags.immutable);
    for (k[4..8]) |v| try std.testing.expect(!types.toObject(v).flags.immutable);
}

test "bytecode round-trip: datum-label sharing preserved via backrefs (kaappi#2111)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    // '(#1=(1 2) #1#) and friends: an object reached twice must decode as the
    // SAME object (eq?), not a copy per reference.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try makeRoundTripFunc(&gc);
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();

    // shared = (1 2); outer = (shared shared); also a vector #(shared "s" "s")
    var shared_pair = try gc.allocPair(types.makeFixnum(1), try gc.allocPair(types.makeFixnum(2), types.NIL));
    gc.pushRoot(&shared_pair);
    var tail = try gc.allocPair(shared_pair, types.NIL);
    gc.pushRoot(&tail);
    const outer = try gc.allocPair(shared_pair, tail);
    func.constants.append(allocator, outer) catch unreachable;

    var shared_str = try gc.allocString("s");
    gc.pushRoot(&shared_str);
    const vec = try gc.allocVectorFill(3, types.NIL);
    const vecp = types.toVector(vec);
    vecp.data[0] = shared_pair;
    vecp.data[1] = shared_str;
    vecp.data[2] = shared_str;
    gc.writeBarrier(types.toObject(vec), shared_pair);
    gc.writeBarrier(types.toObject(vec), shared_str);
    func.constants.append(allocator, vec) catch unreachable;
    gc.popRoot(); // shared_str
    gc.popRoot(); // tail
    gc.popRoot(); // shared_pair

    const loaded = try roundTrip(&gc, func, "/tmp/kaappi_test_shared.sbc");
    defer allocator.free(loaded.funcs);

    const k = loaded.funcs[0].constants.items;
    // (car outer) and (cadr outer) are the same object again.
    const car0 = types.car(k[0]);
    const cadr0 = types.car(types.cdr(k[0]));
    try std.testing.expectEqual(car0, cadr0);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(car0)));
    // Sharing also holds ACROSS constants: the vector's slot 0 is that pair.
    const lv = types.toVector(k[1]);
    try std.testing.expectEqual(car0, lv.data[0]);
    // And the two string slots are one string.
    try std.testing.expectEqual(lv.data[1], lv.data[2]);
}

test "bytecode round-trip: cyclic literal terminates and re-ties the knot (kaappi#2111)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    // '#0=(1 2 . #0#): before backrefs this recursed to the depth guard,
    // wrote a truncated entry, and the reader rejected it — a permanent miss.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try makeRoundTripFunc(&gc);
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();

    var head = try gc.allocPair(types.makeFixnum(1), types.NIL);
    gc.pushRoot(&head);
    const second = try gc.allocPair(types.makeFixnum(2), head);
    types.toObject(head).as(types.Pair).cdr = second;
    gc.writeBarrier(types.toObject(head), second);
    func.constants.append(allocator, head) catch unreachable;
    gc.popRoot();

    // A self-referential vector too: #0=#(1 #0#).
    var cyc_vec = try gc.allocVectorFill(2, types.makeFixnum(1));
    gc.pushRoot(&cyc_vec);
    types.toVector(cyc_vec).data[1] = cyc_vec;
    gc.writeBarrier(types.toObject(cyc_vec), cyc_vec);
    func.constants.append(allocator, cyc_vec) catch unreachable;
    gc.popRoot();

    const loaded = try roundTrip(&gc, func, "/tmp/kaappi_test_cycle.sbc");
    defer allocator.free(loaded.funcs);

    const k = loaded.funcs[0].constants.items;
    // (cddr k0) is k0 itself again.
    try std.testing.expectEqual(k[0], types.cdr(types.cdr(k[0])));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(k[0])));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(k[0]))));
    try std.testing.expectEqual(k[1], types.toVector(k[1]).data[1]);
}

test "bytecode round-trip: a long quoted list costs no nesting depth (kaappi#2113)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    // The cdr spine is iterative on both sides, so a 400-element list — well
    // past MAX_CONSTANT_DEPTH — writes and reads back. Before this, element
    // 257 hit the writer's depth guard and the entry never loaded.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try makeRoundTripFunc(&gc);
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();

    var list = types.NIL;
    gc.pushRoot(&list);
    var i: i64 = 400;
    while (i > 0) : (i -= 1) {
        list = try gc.allocPair(types.makeFixnum(i), list);
    }
    func.constants.append(allocator, list) catch unreachable;
    gc.popRoot();

    const loaded = try roundTrip(&gc, func, "/tmp/kaappi_test_longlist.sbc");
    defer allocator.free(loaded.funcs);

    var cur = loaded.funcs[0].constants.items[0];
    var n: i64 = 1;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        try std.testing.expectEqual(n, types.toFixnum(types.car(cur)));
        n += 1;
    }
    try std.testing.expectEqual(@as(i64, 401), n);
    try std.testing.expectEqual(types.NIL, cur);
}

test "bytecode write: bundle sections refuse what the reader would reject too" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    // writeFileWithBundle's sections have the same refusal contract as the
    // constants: an oversized bundled file or preamble form fails the WRITE
    // with LimitExceeded, instead of producing a --compile artifact whose own
    // embedded bytecode the loader rejects at run time.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try makeRoundTripFunc(&gc);
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();
    var funcs_arr = [_]*Function{func};
    const path = "/tmp/kaappi_test_refuse_bundle.sbc";

    const big = allocator.alloc(u8, MAX_STRING_BYTES + 1) catch unreachable;
    defer allocator.free(big);
    @memset(big, ';');

    // Oversized bundled library source.
    var files = std.StringHashMap([]const u8).init(allocator);
    defer files.deinit();
    try files.put("srfi/big.sld", big);
    const no_preamble = [_][]const u8{};
    try std.testing.expectError(
        BytecodeError.LimitExceeded,
        writeFileWithBundle(allocator, &funcs_arr, 0x1234, "t.scm", &files, &no_preamble, path),
    );

    // Oversized preamble form.
    files.clearRetainingCapacity();
    const preamble = [_][]const u8{big};
    try std.testing.expectError(
        BytecodeError.LimitExceeded,
        writeFileWithBundle(allocator, &funcs_arr, 0x1234, "t.scm", &files, &preamble, path),
    );

    // Both refusals left nothing on disk.
    const missing = file_utils.readWholeFile(allocator, path, 1 << 20);
    try std.testing.expectError(error.FileNotFound, missing);

    // An in-bounds bundle still writes and reads back.
    try files.put("srfi/ok.sld", "(define-library (srfi ok) (export) (begin))");
    const preamble_ok = [_][]const u8{"(import (srfi ok))"};
    try writeFileWithBundle(allocator, &funcs_arr, 0x1234, "t.scm", &files, &preamble_ok, path);
    defer _ = platform.unlink(path);
    var loaded = (try readFileWithTopLevel(&gc, 0x1234, path)) orelse return error.TestUnexpectedResult;
    try std.testing.expect(loaded.bundled_files != null);
    try std.testing.expectEqual(@as(usize, 1), loaded.preamble.?.len);
    freeDeserializeResult(allocator, &loaded);
    // The uniform reset makes a second call a no-op rather than a double-free.
    freeDeserializeResult(allocator, &loaded);
}

test "bytecode write: refuses what the reader would reject (kaappi#2113)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    // The writer must never produce an entry the reader rejects — that is a
    // permanent, invisible cache miss. Nesting past MAX_CONSTANT_DEPTH and an
    // oversized string both fail the WRITE with LimitExceeded, and no file
    // appears on disk.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try makeRoundTripFunc(&gc);
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();

    // ((((…1…)))) nested MAX_CONSTANT_DEPTH+2 deep via car.
    var nested = types.makeFixnum(1);
    gc.pushRoot(&nested);
    var d: u32 = 0;
    while (d < MAX_CONSTANT_DEPTH + 2) : (d += 1) {
        nested = try gc.allocPair(nested, types.NIL);
    }
    func.constants.append(allocator, nested) catch unreachable;
    gc.popRoot();

    var funcs_arr = [_]*Function{func};
    const path = "/tmp/kaappi_test_refuse_depth.sbc";
    try std.testing.expectError(BytecodeError.LimitExceeded, writeFileWithTopLevel(allocator, &funcs_arr, 0x1234, "test.scm", path));
    // Refused means refused: nothing was left on disk.
    const missing = file_utils.readWholeFile(allocator, path, 1 << 20);
    try std.testing.expectError(error.FileNotFound, missing);

    // Same for an oversized string constant.
    func.constants.clearRetainingCapacity();
    const big = allocator.alloc(u8, MAX_STRING_BYTES + 1) catch unreachable;
    defer allocator.free(big);
    @memset(big, 'x');
    func.constants.append(allocator, try gc.allocString(big)) catch unreachable;
    try std.testing.expectError(BytecodeError.LimitExceeded, writeFileWithTopLevel(allocator, &funcs_arr, 0x1234, "test.scm", path));

    // And exactly AT the cap still round-trips — the two halves agree on the
    // boundary, not merely near it.
    func.constants.clearRetainingCapacity();
    var at_cap = types.makeFixnum(1);
    gc.pushRoot(&at_cap);
    var d2: u32 = 0;
    while (d2 < MAX_CONSTANT_DEPTH) : (d2 += 1) {
        at_cap = try gc.allocPair(at_cap, types.NIL);
    }
    func.constants.append(allocator, at_cap) catch unreachable;
    gc.popRoot();
    const loaded = try roundTrip(&gc, func, path);
    allocator.free(loaded.funcs);
}

test "stale compiler version rejects cache" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var w = Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);

    const hash: u64 = 0xCAFE;
    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, hash);
    try w.writeU64(allocator, compilerHash() +% 1); // different compiler version
    try w.writeStr(allocator, "unknown"); // build id
    try w.writeStr(allocator, "test.scm"); // source path
    try w.writeU32(allocator, 1);
    try w.writeU32(allocator, 1);

    const result = try deserializeFromBuffer(&gc, w.buf.items, hash);
    try std.testing.expect(result == null);
}

test "compilerHashFor: same version, different build id → different key" {
    // The heart of kaappi#1516: a dev rebuild keeps the version string but
    // changes the git build id (new commit, or clean→dirty). The compiler key
    // must change so the older binary's bytecode is never reused.
    const v = "9.9.9";
    const t = "arm-macos-none;r7rs";
    try std.testing.expect(compilerHashFor(v, "aaaaaaa", t) != compilerHashFor(v, "bbbbbbb", t));
    try std.testing.expect(compilerHashFor(v, "aaaaaaa", t) != compilerHashFor(v, "aaaaaaa-dirty", t));
    // A clean rebuild of the exact same commit keeps the key (caches shareable).
    try std.testing.expect(compilerHashFor(v, "aaaaaaa", t) == compilerHashFor(v, "aaaaaaa", t));
    // The version/build-id separator prevents boundary collisions: "a"+"bc"
    // must not hash equal to "ab"+"c".
    try std.testing.expect(compilerHashFor("a", "bc", t) != compilerHashFor("ab", "c", t));
}

test "compilerHashFor: same clean commit, different target → different key" {
    // kaappi#2155: all release binaries are built from one clean checkout, so
    // version and build id are identical across all 17 targets. Only the
    // target component separates them — a POSIX-compiled entry (with only the
    // posix cond-expand branch in it) must be a miss for a Windows binary.
    const v = "9.9.9";
    const bid = "aaaaaaa";
    const posix = "aarch64-macos-none;r7rs;posix";
    const windows = "aarch64-windows-gnu;r7rs;windows";
    try std.testing.expect(compilerHashFor(v, bid, posix) != compilerHashFor(v, bid, windows));
    try std.testing.expect(compilerHashFor(v, bid, posix) == compilerHashFor(v, bid, posix));
    // Build-id/target separator: "b"+"ct" must not equal "bc"+"t".
    try std.testing.expect(compilerHashFor(v, "b", "ct") != compilerHashFor(v, "bc", "t"));
    // The real target id names this build's arch, OS, and feature set.
    try std.testing.expect(std.mem.indexOf(u8, compile_target_id, @tagName(builtin.os.tag)) != null);
    try std.testing.expect(std.mem.indexOf(u8, compile_target_id, ";r7rs") != null);
}

test "dev rebuild (different build id) rejects cache" {
    // End-to-end at the load boundary: a cache whose header records a compiler
    // hash from a *different* build (same version, other commit/dirty state) is
    // a miss, so a freshly rebuilt binary recompiles rather than running the
    // previous binary's bytecode.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var w = Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);

    const hash: u64 = 0x5EED;
    const other_build_key = compilerHashFor(main.version, "0000000-other-build", compile_target_id);
    try std.testing.expect(other_build_key != compilerHash()); // precondition
    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, hash);
    try w.writeU64(allocator, other_build_key);
    try w.writeStr(allocator, "0000000-other-build");
    try w.writeStr(allocator, "prog.scm");
    try w.writeU32(allocator, 1);
    try w.writeU32(allocator, 1);

    const result = try deserializeFromBuffer(&gc, w.buf.items, hash);
    try std.testing.expect(result == null);
}

test "classifyEmbeddedRejection: foreign build id is distinguished from corrupt" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    // kaappi#1930: a bundled binary whose embedded .sbc came from a different
    // build must say so instead of "invalid embedded bytecode". The loader
    // refuses both cases with null, so the diagnostic classifier has to tell
    // them apart from the header alone.
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    // A well-formed .sbc produced by a foreign build (same shape as the
    // "dev rebuild rejects cache" fixture above): the header parses, so it
    // must classify as .foreign_build, not .invalid.
    var foreign = Writer{ .buf = .empty };
    defer foreign.buf.deinit(allocator);
    const foreign_key = compilerHashFor(main.version, "0000000-other-build", compile_target_id);
    try foreign.writeBytes(allocator, &MAGIC);
    try foreign.writeU16(allocator, VERSION);
    try foreign.writeU64(allocator, 0x5EED);
    try foreign.writeU64(allocator, foreign_key);
    try foreign.writeStr(allocator, "0000000-other-build");
    try foreign.writeStr(allocator, "prog.scm");
    try foreign.writeU32(allocator, 1);
    try foreign.writeU32(allocator, 1);

    const foreign_rejection = classifyEmbeddedRejection(foreign.buf.items);
    try std.testing.expect(foreign_rejection == .foreign_build);
    // And the loader really does refuse it.
    try std.testing.expect(try deserializeFromBuffer(&gc, foreign.buf.items, 0x5EED) == null);

    // A buffer that is not a .sbc at all must classify as .invalid.
    try std.testing.expect(classifyEmbeddedRejection("not bytecode") == .invalid);

    // A headerless/truncated buffer must classify as .invalid rather than
    // crashing the classifier.
    try std.testing.expect(classifyEmbeddedRejection(foreign.buf.items[0..10]) == .invalid);

    // A valid .sbc written by *this* binary has a matching compiler hash, so
    // if the loader refused it for any reason it is a payload problem, not a
    // stale-bundle one — .invalid, never .foreign_build.
    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.arity = 0;
    func.locals_count = 1;
    var funcs_arr = [_]*Function{func};
    const path = "/tmp/kaappi_test_classify.sbc";
    defer _ = std.posix.system.unlink(@ptrCast(path.ptr));
    try writeFileWithTopLevel(allocator, &funcs_arr, 0xBEEF, "/home/u/prog.scm", path);
    const data = try file_utils.readWholeFile(allocator, path, 1 << 20);
    defer allocator.free(data);
    try std.testing.expect(classifyEmbeddedRejection(data) == .invalid);
}

test "readHeaderInfo round-trips build id and source path" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.arity = 0;
    func.locals_count = 1;

    var funcs_arr = [_]*Function{func};
    const path = "/tmp/kaappi_test_headerinfo.sbc";
    defer _ = std.posix.system.unlink(@ptrCast(path.ptr));
    try writeFileWithTopLevel(allocator, &funcs_arr, 0xABCD, "/home/u/prog.scm", path);

    const data = try file_utils.readWholeFile(allocator, path, 1 << 20);
    defer allocator.free(data);

    const info = readHeaderInfo(data) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 0xABCD), info.source_hash);
    try std.testing.expectEqualStrings(build_options.git_build_id, info.build_id);
    try std.testing.expectEqualStrings("/home/u/prog.scm", info.source_path);
    // Written by this very binary, so it reads back as the current build.
    try std.testing.expect(info.current_build);
}

test "bytecode validation rejects oversized function count header" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var w = Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);

    const hash: u64 = 0xA11CE;
    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, hash);
    try w.writeU64(allocator, compilerHash());
    try w.writeStr(allocator, "unknown"); // build id
    try w.writeStr(allocator, "test.scm"); // source path
    try w.writeU32(allocator, @as(u32, @intCast(MAX_FUNCTIONS + 1)));
    try w.writeU32(allocator, 1);

    const path = "/tmp/kaappi_test_bad_func_count.sbc";
    const fd = platform.openWriteTrunc(path, 0o644) catch unreachable;
    defer _ = platform.close(fd);
    defer _ = platform.unlink(path);

    var total: usize = 0;
    while (total < w.buf.items.len) {
        const wrote = platform.write(fd, w.buf.items.ptr + total, w.buf.items.len - total);
        if (wrote < 0) {
            if (platform.errno(wrote) == .INTR) continue;
            break;
        }
        if (wrote == 0) break;
        total += @as(usize, @intCast(wrote));
    }

    const loaded = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(loaded == null);
}

test "bytecode round-trip: vector pair bignum rational complex constants" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    // Root the function: the constant allocations below can collect, and an
    // unrooted func would be swept while we are still appending into it.
    var func_root = types.makePointer(&func.header);
    gc.pushRoot(&func_root);
    defer gc.popRoot();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // src high
    func.code.append(allocator, 0) catch unreachable; // src low

    const vec_data = [_]Value{ types.makeFixnum(10), types.makeFixnum(20), types.makeFixnum(30) };
    const vec = try gc.allocVector(&vec_data);
    func.constants.append(allocator, vec) catch unreachable;

    const pair = try gc.allocPair(types.makeFixnum(1), types.makeFixnum(2));
    func.constants.append(allocator, pair) catch unreachable;

    const limbs = [_]u64{ 0xDEADBEEF, 0xCAFEBABE };
    const bn = try gc.allocBignumFromLimbs(&limbs, 2, true);
    func.constants.append(allocator, bn) catch unreachable;

    const rat_num = types.makeFixnum(22);
    const rat_den = types.makeFixnum(7);
    const rat = try gc.allocRational(rat_num, rat_den);
    func.constants.append(allocator, rat) catch unreachable;

    const cx = try gc.allocComplex(types.makeFlonum(3.0), types.makeFlonum(4.0));
    func.constants.append(allocator, cx) catch unreachable;

    // Exact components (bignum real, rational imag) must survive the .sbc
    // round trip digit-exactly (kaappi#2166). The bignum must stay rooted
    // across the allocRational in the second argument (gc-stress).
    const cx_bn = try gc.allocBignumFromI64(9007199254740993);
    var cx_bn_root = cx_bn;
    gc.pushRoot(&cx_bn_root);
    defer gc.popRoot();
    const cx_exact = try gc.allocComplex(cx_bn_root, try gc.allocRational(types.makeFixnum(3), types.makeFixnum(4)));
    func.constants.append(allocator, cx_exact) catch unreachable;

    func.arity = 0;
    func.locals_count = 1;

    var funcs_arr = [_]*Function{func};
    const hash: u64 = 88888;
    const path = "/tmp/kaappi_test_advanced_consts.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, "test.scm", path);
    defer {
        _ = platform.unlink(path);
    }

    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    const consts = loaded.funcs[0].constants.items;
    try std.testing.expectEqual(@as(usize, 6), consts.len);

    try std.testing.expect(types.isVector(consts[0]));
    const loaded_vec = types.toObject(consts[0]).as(types.Vector);
    try std.testing.expectEqual(@as(usize, 3), loaded_vec.data.len);
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(loaded_vec.data[0]));

    try std.testing.expect(types.isPair(consts[1]));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(consts[1])));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.cdr(consts[1])));

    try std.testing.expect(types.isBignum(consts[2]));

    // Constant 5: the exact complex with a bignum real and rational imag
    // survives the round trip digit-exactly (kaappi#2166).
    const loaded_cx2 = types.toObject(consts[5]).as(types.Complex);
    const cx2_bn = types.toBignum(loaded_cx2.real);
    try std.testing.expectEqual(@as(usize, 1), cx2_bn.len);
    try std.testing.expectEqual(@as(u64, 9007199254740993), cx2_bn.limbs[0]);
    const cx2_rat = types.toRational(loaded_cx2.imag);
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(cx2_rat.numerator));
    try std.testing.expectEqual(@as(i64, 4), types.toFixnum(cx2_rat.denominator));

    try std.testing.expect(types.isRational(consts[3]));

    try std.testing.expect(types.isComplex(consts[4]));
    const loaded_cx = types.toObject(consts[4]).as(types.Complex);
    try std.testing.expectEqual(@as(f64, 3.0), types.toFlonum(loaded_cx.real));
    try std.testing.expectEqual(@as(f64, 4.0), types.toFlonum(loaded_cx.imag));
}

test "bytecode round-trip: line table and source_line preserved" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_const)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.constants.append(allocator, types.makeFixnum(42)) catch unreachable;
    func.arity = 1;
    func.locals_count = 2;
    func.source_line = 5;
    func.line_table.append(allocator, .{ .offset = 0, .line = 5, .col = 3 }) catch unreachable;
    func.line_table.append(allocator, .{ .offset = 5, .line = 7, .col = 9 }) catch unreachable;

    var funcs_arr = [_]*Function{func};
    const hash: u64 = 11111;
    const path = "/tmp/kaappi_test_linetable.sbc";

    try writeFileWithTopLevel(allocator, &funcs_arr, hash, "test.scm", path);
    defer _ = platform.unlink(path);

    const result = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(result != null);

    const loaded = result.?;
    defer allocator.free(loaded.funcs);

    const lf = loaded.funcs[0];
    try std.testing.expectEqual(@as(u32, 5), lf.source_line);
    try std.testing.expectEqual(@as(usize, 2), lf.line_table.items.len);
    try std.testing.expectEqual(@as(u16, 0), lf.line_table.items[0].offset);
    try std.testing.expectEqual(@as(u32, 5), lf.line_table.items[0].line);
    try std.testing.expectEqual(@as(u32, 3), lf.line_table.items[0].col);
    try std.testing.expectEqual(@as(u16, 5), lf.line_table.items[1].offset);
    try std.testing.expectEqual(@as(u32, 7), lf.line_table.items[1].line);
    try std.testing.expectEqual(@as(u32, 9), lf.line_table.items[1].col);
    try std.testing.expectEqual(@as(u32, 7), lf.lineForOffset(6));
    const loc = lf.locForOffset(6);
    try std.testing.expectEqual(@as(u32, 7), loc.line);
    try std.testing.expectEqual(@as(u32, 9), loc.col);
}

test "bytecode validation rejects invalid opcode" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var w = Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);

    const hash: u64 = 0xBADC0DE;
    try w.writeBytes(allocator, &MAGIC);
    try w.writeU16(allocator, VERSION);
    try w.writeU64(allocator, hash);
    try w.writeU64(allocator, compilerHash());
    try w.writeStr(allocator, "unknown"); // build id
    try w.writeStr(allocator, "test.scm"); // source path
    try w.writeU32(allocator, 1); // function count
    try w.writeU32(allocator, 1); // top-level count

    // Function header
    try w.writeU8(allocator, 0); // arity
    try w.writeU16(allocator, 1); // locals_count
    try w.writeU16(allocator, 0); // upvalue_count
    try w.writeU8(allocator, 0); // is_variadic
    try w.writeU16(allocator, 0); // name_len

    // Body: one invalid opcode byte
    try w.writeU32(allocator, 1); // code_len
    try w.writeU8(allocator, 0xFF);
    try w.writeU32(allocator, 0); // const_count
    try w.writeU32(allocator, 0); // source_line
    try w.writeU32(allocator, 0); // line_table count

    const path = "/tmp/kaappi_test_invalid_opcode.sbc";
    const fd = platform.openWriteTrunc(path, 0o644) catch unreachable;
    defer _ = platform.close(fd);
    defer _ = platform.unlink(path);

    var total: usize = 0;
    while (total < w.buf.items.len) {
        const wrote = platform.write(fd, w.buf.items.ptr + total, w.buf.items.len - total);
        if (wrote < 0) {
            if (platform.errno(wrote) == .INTR) continue;
            break;
        }
        if (wrote == 0) break;
        total += @as(usize, @intCast(wrote));
    }

    const loaded = try readFileWithTopLevel(&gc, hash, path);
    try std.testing.expect(loaded == null);
}
