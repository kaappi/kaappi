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
