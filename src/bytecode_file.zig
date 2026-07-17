const std = @import("std");
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
// v10 (kaappi#1516): the header carries the producing build id and the source
// path after the compiler hash, so `kaappi cache status` can report which
// source and which binary produced each cache entry. The compiler hash itself
// now folds in the git build id (see `compilerHash`), so a dev rebuild at the
// same version string — different commit or a dirty tree — no longer collides.
// v9 (kaappi#1506): line-table entries carry a column alongside the line so
// runtime errors can report `file:line:col`. A version mismatch makes
// `readFileWithTopLevel` return null, so older `.sbc` caches are ignored and
// silently recompiled — no stale-cache hazard.
pub const VERSION: u16 = 10;
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
};

// ---------------------------------------------------------------------------
// Public API (implemented in the read/write halves)
// ---------------------------------------------------------------------------

pub const Writer = write.Writer;
pub const writeFileWithTopLevel = write.writeFileWithTopLevel;
pub const writeFileWithBundle = write.writeFileWithBundle;

pub const DeserializeResult = read.DeserializeResult;
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

/// The cache-key half that identifies the *compiler*. Combines the release
/// version string with the git build id (short HEAD hash, `-dirty` when the
/// tree had uncommitted changes; "unknown" when git is unavailable at build
/// time). Two binaries built from the same commit with a clean tree share a
/// key and may reuse each other's cache; any other pair — a dev rebuild after
/// an edit, a different commit, a dirty vs. clean tree — differs, so a stale
/// entry is rejected on load and recompiled. This closes the long-standing
/// footgun where same-version rebuilds silently ran the previous binary's
/// bytecode (kaappi#1516). Pure in its inputs so the keying is unit-testable.
pub fn compilerHashFor(version_str: []const u8, build_id: []const u8) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(version_str);
    h.update(&[_]u8{0}); // separator: keep version/build-id boundary unambiguous
    h.update(build_id);
    return h.final();
}

pub fn compilerHash() u64 {
    return compilerHashFor(main.version, build_options.git_build_id);
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
    try std.testing.expect(compilerHashFor(v, "aaaaaaa") != compilerHashFor(v, "bbbbbbb"));
    try std.testing.expect(compilerHashFor(v, "aaaaaaa") != compilerHashFor(v, "aaaaaaa-dirty"));
    // A clean rebuild of the exact same commit keeps the key (caches shareable).
    try std.testing.expect(compilerHashFor(v, "aaaaaaa") == compilerHashFor(v, "aaaaaaa"));
    // The version/build-id separator prevents boundary collisions: "a"+"bc"
    // must not hash equal to "ab"+"c".
    try std.testing.expect(compilerHashFor("a", "bc") != compilerHashFor("ab", "c"));
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
    const other_build_key = compilerHashFor(main.version, "0000000-other-build");
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

test "readHeaderInfo round-trips build id and source path" {
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

    const cx = try gc.allocComplexEx(3.0, 4.0, false, false);
    func.constants.append(allocator, cx) catch unreachable;

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
    try std.testing.expectEqual(@as(usize, 5), consts.len);

    try std.testing.expect(types.isVector(consts[0]));
    const loaded_vec = types.toObject(consts[0]).as(types.Vector);
    try std.testing.expectEqual(@as(usize, 3), loaded_vec.data.len);
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(loaded_vec.data[0]));

    try std.testing.expect(types.isPair(consts[1]));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(consts[1])));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.cdr(consts[1])));

    try std.testing.expect(types.isBignum(consts[2]));

    try std.testing.expect(types.isRational(consts[3]));

    try std.testing.expect(types.isComplex(consts[4]));
    const loaded_cx = types.toObject(consts[4]).as(types.Complex);
    try std.testing.expectEqual(@as(f64, 3.0), loaded_cx.real);
    try std.testing.expectEqual(@as(f64, 4.0), loaded_cx.imag);
}

test "bytecode round-trip: line table and source_line preserved" {
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
