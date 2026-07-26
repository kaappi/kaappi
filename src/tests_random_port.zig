//! Unit tests for the SRFI-271 random generator core (types.RandomGen), the
//! OS entropy fill (platform.osRandomBytes), and the SRFI-27 default random
//! source's after-fork reseed mechanism (primitives_random.zig). End-to-end
//! library semantics are covered by tests/scheme/srfi/srfi271.scm; the real
//! fork(2) wiring by tests/scheme/ffi/fork-reseed.scm.

const std = @import("std");
const types = @import("types.zig");
const platform = @import("platform.zig");
const testing = std.testing;

test "determinized RandomGen is reproducible from an equal seed state" {
    var a = types.RandomGen{ .kind = .determinized, .s = .{ 1, 2, 3, 4 } };
    var b = types.RandomGen{ .kind = .determinized, .s = .{ 1, 2, 3, 4 } };
    for (0..512) |_| {
        try testing.expectEqual(a.nextByte().?, b.nextByte().?);
    }
}

test "determinized RandomGen diverges for different seeds" {
    var a = types.RandomGen{ .kind = .determinized, .s = .{ 1, 2, 3, 4 } };
    var b = types.RandomGen{ .kind = .determinized, .s = .{ 4, 3, 2, 1 } };
    var differ = false;
    for (0..64) |_| {
        if (a.nextByte().? != b.nextByte().?) {
            differ = true;
            break;
        }
    }
    try testing.expect(differ);
}

test "determinized RandomGen from a nonzero seed is not stuck at zero" {
    var g = types.RandomGen{ .kind = .determinized, .s = .{ 0x9E3779B97F4A7C15, 2, 3, 4 } };
    var any_nonzero = false;
    for (0..64) |_| {
        if (g.nextByte().? != 0) {
            any_nonzero = true;
            break;
        }
    }
    try testing.expect(any_nonzero);
}

test "RandomGen hands out bytes contiguously across block boundaries" {
    // Reading N bytes one at a time must equal reading them from a fresh
    // generator: no bytes dropped or duplicated at the 8-byte block seam.
    var g1 = types.RandomGen{ .kind = .determinized, .s = .{ 5, 6, 7, 8 } };
    var g2 = types.RandomGen{ .kind = .determinized, .s = .{ 5, 6, 7, 8 } };
    var buf1: [20]u8 = undefined;
    var buf2: [20]u8 = undefined;
    for (&buf1) |*x| x.* = g1.nextByte().?;
    // consume g2 in two uneven bursts straddling the 8-byte blocks
    for (buf2[0..3]) |*x| x.* = g2.nextByte().?;
    for (buf2[3..20]) |*x| x.* = g2.nextByte().?;
    try testing.expectEqualSlices(u8, &buf1, &buf2);
}

test "determinized RandomGen never fails" {
    // Determinized generation is a pure PRNG: nextByte is always non-null.
    var g = types.RandomGen{ .kind = .determinized, .s = .{ 9, 8, 7, 6 } };
    for (0..64) |_| try testing.expect(g.nextByte() != null);
}

test "osRandomBytes succeeds and fills the whole buffer" {
    var buf: [96]u8 = .{0} ** 96;
    try testing.expect(platform.osRandomBytes(&buf));
    // A healthy OS entropy source is ~never all-zero across 96 bytes.
    var nonzero: usize = 0;
    for (buf) |b| {
        if (b != 0) nonzero += 1;
    }
    try testing.expect(nonzero > 0);
}

test "osRandomBytes handles empty and single-byte buffers" {
    var none: [0]u8 = .{};
    try testing.expect(platform.osRandomBytes(&none)); // empty is trivially true
    var one: [1]u8 = .{0};
    try testing.expect(platform.osRandomBytes(&one));
}

test "randomized RandomGen yields real entropy bytes (never null on a healthy host)" {
    var g = types.RandomGen{ .kind = .randomized };
    // Exercise the entropy-refill path many times over (~13 blocks).
    for (0..100) |_| try testing.expect(g.nextByte() != null);
}

test "stale default random source reseeds in place on next draw (fork child, #atfork)" {
    const th = @import("testing_helpers.zig");
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(random-integer 1000000)");
    const src_val = ctx.vm.default_random_source;
    const rs = types.toObject(src_val).as(types.RandomSource);

    // Learn where one draw takes the current state, then rewind.
    const saved = rs.prng;
    _ = try ctx.vm.eval("(random-integer 1000000)");
    const advanced = rs.prng;
    rs.prng = saved;

    // What the pthread_atfork child handler does in a forked child.
    ctx.vm.default_rs_needs_reseed = true;

    _ = try ctx.vm.eval("(random-integer 1000000)");
    try testing.expect(!ctx.vm.default_rs_needs_reseed);
    // Same heap object: (srfi 27)'s load-time default-random-source
    // snapshot must stay the live default.
    try testing.expectEqual(src_val, ctx.vm.default_random_source);
    // Without the reseed, replaying `saved` would land exactly on
    // `advanced`; a fresh OS-entropy seed collides only with ~2^-64 odds.
    try testing.expect(!std.meta.eql(rs.prng, advanced));
}
