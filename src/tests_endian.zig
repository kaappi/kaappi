//! Byte-order pins for the surfaces where a big-endian host can disagree
//! with a little-endian one.
//!
//! WHY THIS FILE EXISTS, AND WHY IT IS ZIG RATHER THAN SCHEME.
//!
//! s390x is the project's only big-endian target and exists precisely to
//! catch byte-order bugs (#1654). What actually executes there in `ci.yml`
//! is three steps: the cross-compile, `zig build test -Dtarget=s390x-linux`,
//! and `r7rs-tests.scm`. **The unit suite is one of them** — so an assertion
//! placed here runs on the canary today, with no CI change required. That is
//! not true of any `tests/scheme/**` file: none of them run on that leg.
//!
//! DO NOT "VERIFY BIG-ENDIAN BEHAVIOUR" BY RUNNING THIS LOCALLY ON A MAC.
//! `build.zig` sets `skip_foreign_checks = true`, so `zig build test
//! -Dtarget=s390x-linux` compiles the test binary and then **silently skips
//! running it**, exiting 0 with no output — `--summary all` shows `run test
//! unit-tests skipped`. That is deliberate (it makes the same command a
//! compile gate for targets with no emulator, e.g. Windows), and it works on
//! the CI leg because `docker/setup-qemu-action` registers binfmt_misc, so
//! the direct spawn succeeds and Zig never consults its foreign-executor
//! logic at all. The consequence to remember: a clean local exit code from
//! that command is evidence the code *compiles* big-endian, and evidence of
//! nothing whatsoever about how it *behaves*.
//!
//! Two properties in this codebase cannot be pinned from Scheme at all, and
//! both live here:
//!
//!   1. **`%host-big-endian?` telling the truth.** SRFI 74's `(endianness
//!      native)` is `(if (%host-big-endian?) 'big 'little)`, so every
//!      "native accessors agree" assertion written in Scheme is circular:
//!      it can only re-derive the answer from the same primitive. The one
//!      non-circular check is against the machine, which needs a memory
//!      probe, which needs Zig.
//!
//!   2. **The `.sbc` codec's canonical little-endian scalars.** Every
//!      scalar goes through `nativeToLittle`/`littleToNative`, but the
//!      existing round-trip tests write and read on the *same* host, so a
//!      paired byte-swap bug cancels out and they stay green. The two tests
//!      below break the pairing in each direction independently: the writer
//!      is checked against literal expected bytes, and the reader is fed a
//!      hand-assembled literal-little-endian header. Neither expected value
//!      depends on the host, so both mean the same thing on every target.
//!
//! Endian-*insensitive* by construction, deliberately not pinned here:
//! bytecode operands inside `Function.code` are assembled and consumed a
//! byte at a time (`v >> 8`, `v & 0xFF` in `compiler.zig`; `readU16` in
//! `vm_dispatch.zig`), never byte-punned; bignum limbs are `[]u64` in
//! little-endian *limb* order, with each limb serialized through
//! `writeU64`; and SRFI 178 bit order is spec-defined, not host-defined.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const types = @import("types.zig");
const memory = @import("memory.zig");
const file_utils = @import("file_utils.zig");
const bf = @import("bytecode_file.zig");
const bfw = @import("bytecode_file_write.zig");
const th = @import("testing_helpers.zig");

const GC = memory.GC;
const Function = types.Function;

/// The host's byte order observed as a *memory layout* rather than read off
/// `builtin.cpu.arch.endian()`. On a big-endian host the most significant
/// byte of the word occupies the lowest address.
fn probeHostIsBigEndian() bool {
    var word: u32 = 0x01020304;
    const bytes: *const [4]u8 = @ptrCast(&word);
    return bytes[0] == 0x01;
}

// ---------------------------------------------------------------------------
// 1. The host's byte order, and the one primitive that reports it
// ---------------------------------------------------------------------------

test "endian: the memory probe agrees with builtin.cpu.arch.endian()" {
    const declared_big = builtin.cpu.arch.endian() == .big;
    try std.testing.expectEqual(declared_big, probeHostIsBigEndian());
}

test "endian: %host-big-endian? reports the host's real byte order" {
    // The load-bearing one. SRFI 74's `(endianness native)`, and therefore
    // every `blob-*-native-*` accessor, is exactly this primitive's answer.
    // Nothing reachable from Scheme can check it -- a Scheme test can only
    // ask the same primitive again.
    try th.expectEvalBool("(%host-big-endian?)", probeHostIsBigEndian());
}

test "endian: %host-big-endian? is false on a little-endian host and true on a big-endian one" {
    // Spelled out as two mutually exclusive arms so the failure message on
    // the s390x leg names the direction that broke rather than printing a
    // bare boolean mismatch.
    if (probeHostIsBigEndian()) {
        try th.expectEvalBool("(%host-big-endian?)", true);
        try th.expectEvalBool("(not (%host-big-endian?))", false);
    } else {
        try th.expectEvalBool("(%host-big-endian?)", false);
        try th.expectEvalBool("(not (%host-big-endian?))", true);
    }
}

// ---------------------------------------------------------------------------
// 2. `.sbc` writer: scalars are little-endian on every host
//
// Each expected byte string below is a constant, not a function of the host.
// On a little-endian host `nativeToLittle` is the identity and these pass
// trivially; on s390x they are the byte-swap assertion.
// ---------------------------------------------------------------------------

fn expectWriterBytes(
    comptime writeFn: []const u8,
    value: anytype,
    expected: []const u8,
) !void {
    const allocator = std.testing.allocator;
    var w = bfw.Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);
    try @field(bfw.Writer, writeFn)(&w, allocator, value);
    try std.testing.expectEqualSlices(u8, expected, w.buf.items);
}

test "endian: .sbc writeU16 emits little-endian bytes" {
    try expectWriterBytes("writeU16", @as(u16, 0x0102), &.{ 0x02, 0x01 });
}

test "endian: .sbc writeU32 emits little-endian bytes" {
    try expectWriterBytes("writeU32", @as(u32, 0x01020304), &.{ 0x04, 0x03, 0x02, 0x01 });
}

test "endian: .sbc writeU64 emits little-endian bytes" {
    try expectWriterBytes(
        "writeU64",
        @as(u64, 0x0102030405060708),
        &.{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 },
    );
}

test "endian: .sbc writeI64 emits little-endian bytes for a negative value" {
    // -2 is 0xFFFF_FFFF_FFFF_FFFE; the discriminating byte is the 0xFE, which
    // sits at the lowest address on a little-endian encoding and would move to
    // the highest if the conversion were dropped.
    try expectWriterBytes(
        "writeI64",
        @as(i64, -2),
        &.{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
    );
}

test "endian: .sbc writeF64 emits the IEEE-754 bits little-endian" {
    // 1.5 is 0x3FF8_0000_0000_0000.
    try expectWriterBytes(
        "writeF64",
        @as(f64, 1.5),
        &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x3F },
    );
}

test "endian: .sbc writeStr's u16 length prefix is little-endian" {
    const allocator = std.testing.allocator;
    var w = bfw.Writer{ .buf = .empty };
    defer w.buf.deinit(allocator);
    // 258 bytes: the length's high byte is nonzero, so a dropped conversion
    // is visible in the prefix rather than hidden by a zero byte.
    const payload = "x" ** 258;
    try w.writeStr(allocator, payload);
    try std.testing.expectEqual(@as(usize, 2 + 258), w.buf.items.len);
    try std.testing.expectEqual(@as(u8, 0x02), w.buf.items[0]);
    try std.testing.expectEqual(@as(u8, 0x01), w.buf.items[1]);
}

// ---------------------------------------------------------------------------
// 3. `.sbc` reader: a hand-assembled little-endian header decodes correctly
//
// This is the direction the existing round-trip tests cannot cover, because
// they read back what this same host just wrote. Here the bytes are literals.
// ---------------------------------------------------------------------------

fn appendLeU16(list: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u16) !void {
    try list.append(allocator, @truncate(v));
    try list.append(allocator, @truncate(v >> 8));
}

test "endian: readHeaderInfo decodes a hand-assembled little-endian header" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &bf.MAGIC);
    try appendLeU16(&buf, allocator, bf.VERSION);
    // source_hash = 0x0102030405060708, spelled little-endian by hand.
    try buf.appendSlice(allocator, &.{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 });
    // compiler_hash = 0x1122334455667788, likewise.
    try buf.appendSlice(allocator, &.{ 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11 });
    try appendLeU16(&buf, allocator, 2);
    try buf.appendSlice(allocator, "id");
    try appendLeU16(&buf, allocator, 6);
    try buf.appendSlice(allocator, "a.scm\x00"[0..6]);

    const info = bf.readHeaderInfo(buf.items) orelse
        return error.HeaderRejected;
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), info.source_hash);
    try std.testing.expectEqual(@as(u64, 0x1122334455667788), info.compiler_hash);
    try std.testing.expectEqualStrings("id", info.build_id);
}

test "endian: readHeaderInfo rejects a big-endian-spelled version field" {
    // The discriminating control for the test above: the same header with
    // only the two VERSION bytes swapped must be rejected. If it were
    // accepted, `readHeaderInfo` would be ignoring byte order rather than
    // honouring it -- and on a big-endian host that is precisely the bug
    // this file exists to catch.
    comptime {
        // The control is only discriminating while VERSION's two bytes
        // differ. At VERSION 10 (0x000A) they do. A future bump to a value
        // like 0x0101 would make the swap invisible and this test vacuous,
        // so fail the build then rather than keep a green no-op.
        const lo: u8 = @truncate(bf.VERSION);
        const hi: u8 = @truncate(bf.VERSION >> 8);
        if (lo == hi) @compileError(
            "bytecode_file.VERSION's two bytes are equal, so byte-swapping it " ++
                "is undetectable and this endianness control asserts nothing. " ++
                "Pick a different discriminating field, or a VERSION whose bytes differ.",
        );
    }
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &bf.MAGIC);
    try buf.append(allocator, @truncate(bf.VERSION >> 8));
    try buf.append(allocator, @truncate(bf.VERSION));
    try buf.appendSlice(allocator, &[_]u8{0} ** 16);
    try appendLeU16(&buf, allocator, 0);
    try appendLeU16(&buf, allocator, 0);

    try std.testing.expect(bf.readHeaderInfo(buf.items) == null);
}

// ---------------------------------------------------------------------------
// 4. A real `.sbc` file, checked at the byte level
//
// The two tests above use the codec's own primitives; this one goes through
// the whole serializer and reads the bytes back off disk, so a byte-order
// mistake made in the header assembly rather than in a `writeXxx` helper
// still shows up.
// ---------------------------------------------------------------------------

test "endian: a written .sbc file carries VERSION and source_hash little-endian" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_void)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try th.tmpDirRealPathAlloc(&tmp, allocator);
    defer allocator.free(dir);
    const path = try std.fs.path.joinZ(allocator, &.{ dir, "endian.sbc" });
    defer allocator.free(path);

    var funcs_arr = [_]*Function{func};
    const hash: u64 = 0x0102030405060708;
    try bf.writeFileWithTopLevel(allocator, &funcs_arr, hash, "endian.scm", path);

    const bytes = try file_utils.readWholeFile(allocator, path, 1 << 20);
    defer allocator.free(bytes);

    try std.testing.expect(bytes.len >= 14);
    try std.testing.expectEqualSlices(u8, &bf.MAGIC, bytes[0..4]);
    try std.testing.expectEqual(@as(u8, @truncate(bf.VERSION)), bytes[4]);
    try std.testing.expectEqual(@as(u8, @truncate(bf.VERSION >> 8)), bytes[5]);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 },
        bytes[6..14],
    );
}

// ---------------------------------------------------------------------------
// 5. The whole-file golden fixture (audit v2, Phase 7D)
//
// Section 2 checks the writer's scalar helpers and section 3 checks the
// reader's header parse. Neither reaches the *body*: the per-function record
// (arity/locals/upvalues/name/code/constants/line table) and every constant
// encoding. Those are exercised only by the round-trip tests in
// `bytecode_file.zig`, which write and read on the same host — so a byte-swap
// present on BOTH sides cancels out and leaves them green on every machine,
// big-endian included. That is the exact bug class s390x exists to catch and
// the one thing no existing test can see.
//
// The fixture below breaks the pairing. `GOLDEN_BODY` is a literal byte
// sequence, hand-derived field by field from the format in
// `bytecode_file_write.writeFunctionsToBuffer`, and it is used twice with no
// contact between the two uses:
//
//   * `writer` builds the corresponding Function graph, serializes it, and
//     asserts the file equals the literal. Consults no reader code.
//   * `reader` feeds the literal to `deserializeFromBuffer` and asserts every
//     decoded field. Consults no writer code.
//
// Neither expected value is a function of the host, so both mean the same
// thing on s390x as on x86_64. A swap on one side fails one test; a *paired*
// swap fails both — while the round-trip tests stay green, which is the point.
//
// Every multi-byte value below was chosen so its byte-reverse is a different
// value (no zero padding that hides a swap, no palindromes). Read any comment
// as "value V, LSB first" and the ordering is checkable by eye.
// ---------------------------------------------------------------------------

/// Emit `n` bytes of `v`, least-significant first, using shifts only — so the
/// helper itself cannot inherit the host's byte order the way a `@bitCast`
/// would. This is what makes the hand-assembled header independent of the
/// codec under test.
fn appendLe(list: *std.ArrayList(u8), allocator: std.mem.Allocator, n: usize, v: u64) !void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        try list.append(allocator, @truncate(v >> @intCast(i * 8)));
    }
}

const GOLDEN_SOURCE_HASH: u64 = 0x0102030405060708;
const GOLDEN_SOURCE_PATH = "g.scm";
/// Only the reader test uses this: the writer stamps `build_options.git_build_id`,
/// which differs per build, so the writer test spells the real one instead.
const GOLDEN_BUILD_ID = "bid";

const LOAD_VOID: u8 = @intFromEnum(types.OpCode.load_void);
const RETURN: u8 = @intFromEnum(types.OpCode.@"return");

/// Everything after the variable-length header (magic, version, source hash,
/// compiler hash, build id, source path). Offsets 0..14 of the header are
/// already pinned by section 4; the compiler hash and the two string length
/// prefixes are spelled by hand in both tests below.
///
/// Written as one `++` chain of per-field literals rather than a flat array so
/// `zig fmt` cannot reflow a value across a line boundary: each line below is
/// exactly one field, and its comment names the value it spells LSB-first.
const GOLDEN_BODY =
    [_]u8{ 0x02, 0x00, 0x00, 0x00 } ++ // func_count u32 = 2
    [_]u8{ 0x01, 0x00, 0x00, 0x00 } ++ // top_level_count u32 = 1

    // ---- function 0 (top level) ----
    [_]u8{0x02} ++ // arity u8 = 2
    [_]u8{ 0x01, 0x02 } ++ // locals_count u16 = 0x0201
    [_]u8{ 0x03, 0x04 } ++ // upvalue_count u16 = 0x0403
    [_]u8{0x01} ++ // is_variadic u8 = 1
    [_]u8{ 0x02, 0x00 } ++ "fn".* ++ // name: u16 length 2, then bytes
    [_]u8{ 0x06, 0x00, 0x00, 0x00 } ++ // code_len u32 = 6
    [_]u8{ LOAD_VOID, 0x00, 0x00, RETURN, 0x00, 0x00 } ++
    [_]u8{ 0x13, 0x00, 0x00, 0x00 } ++ // const_count u32 = 19

    // 0: fixnum -2, i64 0xFFFFFFFFFFFFFFFE
    [_]u8{bf.TAG_FIXNUM} ++ [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF } ++
    // 1: flonum 1.5, IEEE-754 bits 0x3FF8000000000000
    [_]u8{bf.TAG_FLONUM} ++ [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x3F } ++
    // 2: symbol "ab", u16 length prefix
    [_]u8{bf.TAG_SYMBOL} ++ [_]u8{ 0x02, 0x00 } ++ "ab".* ++
    // 3: string "cd" (mutable), v11 immutability byte, u32 length prefix.
    //    Back-reference id 0 (first shareable object registered).
    [_]u8{ bf.TAG_STRING, 0x00 } ++ [_]u8{ 0x02, 0x00, 0x00, 0x00 } ++ "cd".* ++
    [_]u8{ bf.TAG_BOOLEAN, 0x01 } ++ // 4: #t
    [_]u8{ bf.TAG_BOOLEAN, 0x00 } ++ // 5: #f
    [_]u8{bf.TAG_NIL} ++ // 6: '()
    [_]u8{bf.TAG_VOID} ++ // 7: void
    [_]u8{bf.TAG_EOF} ++ // 8: eof object
    [_]u8{bf.TAG_UNDEFINED} ++ // 9: undefined
    // 10: char U+1F600, u32 0x0001F600
    [_]u8{bf.TAG_CHAR} ++ [_]u8{ 0x00, 0xF6, 0x01, 0x00 } ++
    // 11: function reference, index u32 = 1
    [_]u8{bf.TAG_FUNCTION} ++ [_]u8{ 0x01, 0x00, 0x00, 0x00 } ++
    // 12: pair (3 . 4), IMMUTABLE (v11 byte = 1), two nested fixnum
    //     constants. Back-reference id 1.
    [_]u8{ bf.TAG_PAIR, 0x01 } ++
    [_]u8{bf.TAG_FIXNUM} ++ [_]u8{ 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } ++
    [_]u8{bf.TAG_FIXNUM} ++ [_]u8{ 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } ++
    // 13: vector #(5) (mutable), u32 length then one nested fixnum.
    //     Back-reference id 2.
    [_]u8{ bf.TAG_VECTOR, 0x00 } ++ [_]u8{ 0x01, 0x00, 0x00, 0x00 } ++
    [_]u8{bf.TAG_FIXNUM} ++ [_]u8{ 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } ++
    // 14: bytevector #u8(7 8) (mutable), u32 length then raw bytes.
    //     Back-reference id 3.
    [_]u8{ bf.TAG_BYTEVECTOR, 0x00 } ++ [_]u8{ 0x02, 0x00, 0x00, 0x00 } ++ [_]u8{ 0x07, 0x08 } ++
    // 15: bignum +0x0102030405060708: sign u8, limb count u32, one limb u64
    [_]u8{bf.TAG_BIGNUM} ++ [_]u8{0x01} ++ [_]u8{ 0x01, 0x00, 0x00, 0x00 } ++
    [_]u8{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 } ++
    // 16: rational 22/7, two nested fixnum constants
    [_]u8{bf.TAG_RATIONAL} ++
    [_]u8{bf.TAG_FIXNUM} ++ [_]u8{ 0x16, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } ++
    [_]u8{bf.TAG_FIXNUM} ++ [_]u8{ 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } ++
    // 17: complex 3.0+4.0i: TAG_COMPLEX, then two nested constants —
    //     TAG_FLONUM + f64 0x4008000000000000, TAG_FLONUM + f64
    //     0x4010000000000000 (components are Values, kaappi#2166)
    [_]u8{bf.TAG_COMPLEX} ++
    [_]u8{bf.TAG_FLONUM} ++ [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x40 } ++
    [_]u8{bf.TAG_FLONUM} ++ [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x40 } ++
    // 18: the pair from constant 12 again — a v11 back-reference, u32 id 1
    //     (LSB first; its byte-reverse is a different id, so a swap shows)
    [_]u8{bf.TAG_BACKREF} ++ [_]u8{ 0x01, 0x00, 0x00, 0x00 } ++
    [_]u8{ 0x01, 0x02, 0x03, 0x00 } ++ // source_line u32 = 0x00030201
    [_]u8{ 0x01, 0x00, 0x00, 0x00 } ++ // line_table count u32 = 1
    [_]u8{ 0x02, 0x01 } ++ // entry offset u16 = 0x0102
    [_]u8{ 0x02, 0x03, 0x04, 0x00 } ++ // entry line u32 = 0x00040302
    [_]u8{ 0x05, 0x06, 0x07, 0x00 } ++ // entry col  u32 = 0x00070605

    // ---- function 1 (nested, referenced by constant 11) ----
    [_]u8{0x00} ++ // arity u8 = 0
    [_]u8{ 0x01, 0x00 } ++ // locals_count u16 = 1
    [_]u8{ 0x00, 0x00 } ++ // upvalue_count u16 = 0
    [_]u8{0x00} ++ // is_variadic u8 = 0
    [_]u8{ 0x00, 0x00 } ++ // name_len u16 = 0
    [_]u8{ 0x06, 0x00, 0x00, 0x00 } ++ // code_len u32 = 6
    [_]u8{ LOAD_VOID, 0x00, 0x00, RETURN, 0x00, 0x00 } ++
    [_]u8{ 0x00, 0x00, 0x00, 0x00 } ++ // const_count u32 = 0
    [_]u8{ 0x00, 0x00, 0x00, 0x00 } ++ // source_line u32 = 0
    [_]u8{ 0x00, 0x00, 0x00, 0x00 } ++ // line_table count u32 = 0

    [_]u8{ 0x00, 0x00, 0x00, 0x00 } ++ // bundled-files count u32 = 0
    [_]u8{ 0x00, 0x00, 0x00, 0x00 }; // preamble count u32 = 0

comptime {
    // The fixture is worthless if a value in it is its own byte-reverse: the
    // assertion would hold under a swapped codec. Guard the four scalars that
    // carry the argument (the rest are checked by eye against the comments).
    const pal = struct {
        fn isPalindrome(comptime n: usize, comptime v: u64) bool {
            comptime var i: usize = 0;
            inline while (i < n / 2) : (i += 1) {
                const lo: u8 = @truncate(v >> @intCast(i * 8));
                const hi: u8 = @truncate(v >> @intCast((n - 1 - i) * 8));
                if (lo != hi) return false;
            }
            return true;
        }
    };
    if (pal.isPalindrome(8, GOLDEN_SOURCE_HASH)) @compileError("GOLDEN_SOURCE_HASH is a byte-palindrome");
    if (pal.isPalindrome(2, 0x0201)) @compileError("locals_count is a byte-palindrome");
    if (pal.isPalindrome(4, 0x0001F600)) @compileError("the char codepoint is a byte-palindrome");
    if (pal.isPalindrome(8, 0x0102030405060708)) @compileError("the bignum limb is a byte-palindrome");
}

/// The header the writer stamps, spelled by hand with shifts. `build_id` is a
/// parameter because the writer always emits `build_options.git_build_id`
/// while the reader accepts any string there.
fn goldenHeader(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    build_id: []const u8,
) !void {
    try list.appendSlice(allocator, &bf.MAGIC);
    try appendLe(list, allocator, 2, bf.VERSION);
    try appendLe(list, allocator, 8, GOLDEN_SOURCE_HASH);
    // Must equal this binary's own key or the reader treats the buffer as a
    // stale-build miss. Its *bytes* are still hand-spelled little-endian.
    try appendLe(list, allocator, 8, bf.compilerHash());
    try appendLe(list, allocator, 2, build_id.len);
    try list.appendSlice(allocator, build_id);
    try appendLe(list, allocator, 2, GOLDEN_SOURCE_PATH.len);
    try list.appendSlice(allocator, GOLDEN_SOURCE_PATH);
}

/// The Function graph `GOLDEN_BODY` encodes. Both functions stay rooted for the
/// caller's lifetime via `gc.pushRoot`, so the caller must pop twice.
fn buildGoldenGraph(gc: *GC, allocator: std.mem.Allocator, roots: *[2]types.Value) !*Function {
    const child = try gc.allocFunction();
    roots[0] = types.makePointer(&child.header);
    gc.pushRoot(&roots[0]);
    child.code.appendSlice(allocator, &.{ LOAD_VOID, 0, 0, RETURN, 0, 0 }) catch unreachable;
    child.arity = 0;
    child.locals_count = 1;

    const parent = try gc.allocFunction();
    roots[1] = types.makePointer(&parent.header);
    gc.pushRoot(&roots[1]);
    parent.code.appendSlice(allocator, &.{ LOAD_VOID, 0, 0, RETURN, 0, 0 }) catch unreachable;
    parent.arity = 2;
    parent.locals_count = 0x0201;
    parent.upvalue_count = 0x0403;
    parent.is_variadic = true;
    parent.name = "fn"; // static literal; owns_name stays false

    const c = &parent.constants;
    c.append(allocator, types.makeFixnum(-2)) catch unreachable;
    c.append(allocator, types.makeFlonum(1.5)) catch unreachable;
    c.append(allocator, try gc.allocSymbol("ab")) catch unreachable;
    c.append(allocator, try gc.allocString("cd")) catch unreachable;
    c.append(allocator, types.TRUE) catch unreachable;
    c.append(allocator, types.FALSE) catch unreachable;
    c.append(allocator, types.NIL) catch unreachable;
    c.append(allocator, types.VOID) catch unreachable;
    c.append(allocator, types.EOF) catch unreachable;
    c.append(allocator, types.UNDEFINED) catch unreachable;
    c.append(allocator, types.makeChar(0x1F600)) catch unreachable;
    c.append(allocator, types.makePointer(&child.header)) catch unreachable;
    // Constant 12 is immutable, pinning the v11 immutability byte; constant 18
    // is the same pair again, pinning TAG_BACKREF (kaappi#2110/#2111).
    const pair = try gc.allocPair(types.makeFixnum(3), types.makeFixnum(4));
    types.toObject(pair).flags.immutable = true;
    c.append(allocator, pair) catch unreachable;
    const vec_data = [_]types.Value{types.makeFixnum(5)};
    c.append(allocator, try gc.allocVector(&vec_data)) catch unreachable;
    c.append(allocator, try gc.allocBytevector(&[_]u8{ 7, 8 })) catch unreachable;
    const limbs = [_]u64{0x0102030405060708};
    c.append(allocator, try gc.allocBignumFromLimbs(&limbs, 1, true)) catch unreachable;
    c.append(allocator, try gc.allocRational(types.makeFixnum(22), types.makeFixnum(7))) catch unreachable;
    c.append(allocator, try gc.allocComplex(types.makeFlonum(3.0), types.makeFlonum(4.0))) catch unreachable;
    c.append(allocator, pair) catch unreachable;

    parent.source_line = 0x00030201;
    parent.line_table.append(allocator, .{ .offset = 0x0102, .line = 0x00040302, .col = 0x00070605 }) catch unreachable;
    return parent;
}

test "endian: the serializer reproduces the golden .sbc byte sequence" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var roots: [2]types.Value = .{ types.NIL, types.NIL };
    const parent = try buildGoldenGraph(&gc, allocator, &roots);
    defer gc.popRoot();
    defer gc.popRoot();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try th.tmpDirRealPathAlloc(&tmp, allocator);
    defer allocator.free(dir);
    const path = try std.fs.path.joinZ(allocator, &.{ dir, "golden.sbc" });
    defer allocator.free(path);

    var funcs_arr = [_]*Function{parent};
    try bf.writeFileWithTopLevel(allocator, &funcs_arr, GOLDEN_SOURCE_HASH, GOLDEN_SOURCE_PATH, path);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(allocator);
    try goldenHeader(&expected, allocator, build_options.git_build_id);
    try expected.appendSlice(allocator, &GOLDEN_BODY);

    const actual = try file_utils.readWholeFile(allocator, path, 1 << 20);
    defer allocator.free(actual);

    try std.testing.expectEqualSlices(u8, expected.items, actual);
}

test "endian: the deserializer decodes the golden .sbc byte sequence" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try goldenHeader(&buf, allocator, GOLDEN_BUILD_ID);
    try buf.appendSlice(allocator, &GOLDEN_BODY);

    const result = (try bf.deserializeFromBuffer(&gc, buf.items, GOLDEN_SOURCE_HASH)) orelse
        return error.GoldenBufferRejected;
    defer allocator.free(result.funcs);

    try std.testing.expectEqual(@as(u32, 1), result.top_level_count);
    try std.testing.expectEqual(@as(usize, 2), result.funcs.len);

    const f = result.funcs[0];
    try std.testing.expectEqual(@as(u8, 2), f.arity);
    try std.testing.expectEqual(@as(u16, 0x0201), f.locals_count);
    try std.testing.expectEqual(@as(u16, 0x0403), f.upvalue_count);
    try std.testing.expect(f.is_variadic);
    try std.testing.expectEqualStrings("fn", f.name.?);
    try std.testing.expectEqualSlices(u8, &.{ LOAD_VOID, 0, 0, RETURN, 0, 0 }, f.code.items);

    const k = f.constants.items;
    try std.testing.expectEqual(@as(usize, 19), k.len);
    try std.testing.expectEqual(@as(i64, -2), types.toFixnum(k[0]));
    try std.testing.expectEqual(@as(f64, 1.5), types.toFlonum(k[1]));
    try std.testing.expectEqualStrings("ab", types.symbolName(k[2]));
    try std.testing.expectEqualStrings("cd", types.toObject(k[3]).as(types.SchemeString).data);
    try std.testing.expectEqual(types.TRUE, k[4]);
    try std.testing.expectEqual(types.FALSE, k[5]);
    try std.testing.expectEqual(types.NIL, k[6]);
    try std.testing.expectEqual(types.VOID, k[7]);
    try std.testing.expectEqual(types.EOF, k[8]);
    try std.testing.expectEqual(types.UNDEFINED, k[9]);
    try std.testing.expectEqual(@as(u21, 0x1F600), types.toChar(k[10]));
    try std.testing.expect(types.isFunction(k[11]));
    try std.testing.expect(types.toObject(k[11]).as(Function) == result.funcs[1]);
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(k[12])));
    try std.testing.expectEqual(@as(i64, 4), types.toFixnum(types.cdr(k[12])));
    // v11: the immutability byte round-trips (kaappi#2110)…
    try std.testing.expect(types.toObject(k[12]).flags.immutable);
    try std.testing.expect(!types.toObject(k[3]).flags.immutable);
    // …and the back-reference decodes to the SAME object (kaappi#2111).
    try std.testing.expectEqual(k[12], k[18]);
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(types.toVector(k[13]).data[0]));
    try std.testing.expect(!types.toObject(k[13]).flags.immutable);
    try std.testing.expectEqualSlices(u8, &.{ 7, 8 }, types.toBytevector(k[14]).data);

    const bn = types.toBignum(k[15]);
    try std.testing.expectEqual(@as(usize, 1), bn.len);
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), bn.limbs[0]);
    try std.testing.expect(bn.positive);

    const rat = types.toObject(k[16]).as(types.Rational);
    try std.testing.expectEqual(@as(i64, 22), types.toFixnum(rat.numerator));
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(rat.denominator));

    const cx = types.toObject(k[17]).as(types.Complex);
    try std.testing.expectEqual(@as(f64, 3.0), types.toFlonum(cx.real));
    try std.testing.expectEqual(@as(f64, 4.0), types.toFlonum(cx.imag));

    try std.testing.expectEqual(@as(u32, 0x00030201), f.source_line);
    try std.testing.expectEqual(@as(usize, 1), f.line_table.items.len);
    try std.testing.expectEqual(@as(u16, 0x0102), f.line_table.items[0].offset);
    try std.testing.expectEqual(@as(u32, 0x00040302), f.line_table.items[0].line);
    try std.testing.expectEqual(@as(u32, 0x00070605), f.line_table.items[0].col);

    const child = result.funcs[1];
    try std.testing.expectEqual(@as(u8, 0), child.arity);
    try std.testing.expectEqual(@as(u16, 1), child.locals_count);
    try std.testing.expectEqual(@as(usize, 0), child.constants.items.len);
    try std.testing.expect(child.name == null);
}

// ---------------------------------------------------------------------------
// 6. The cache key itself is a function of bytes, not of host byte order
//
// `sourceHash` and `compilerHashFor` are Wyhash, whose Zig implementation reads
// its input through `std.mem.readInt(..., .little)` — so the same source text
// keys to the same u64 on s390x as on x86_64, and a `.sbc` is not silently
// re-compiled (or silently *accepted*) because of the host's byte order.
// Nothing states that today, and it is not obvious: a hash that used native
// loads would make the key host-dependent while every other test stayed green.
//
// The expected values are captured constants, not derived ones — for a hash
// there is no independent derivation, and the property being pinned is
// host-invariance, not the specific number. A failure therefore means one of
// two things, both worth knowing: the host disagrees (the bug this file exists
// for), or Wyhash changed under a Zig upgrade, which silently invalidates every
// cache entry in the wild.
// ---------------------------------------------------------------------------

test "endian: sourceHash is host-independent" {
    try std.testing.expectEqual(@as(u64, 15036897837213381375), bf.sourceHash("(display \"hello\")\n"));
}

test "endian: compilerHashFor is host-independent" {
    // Captured constant (see the section comment): re-captured when the key
    // gained its target component (kaappi#2155), which deliberately changed
    // the value for every input.
    try std.testing.expectEqual(@as(u64, 9530204811558404380), bf.compilerHashFor("0.0.0-test", "abc1234", "aarch64-macos-none;r7rs"));
}
