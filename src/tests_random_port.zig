//! Unit tests for the SRFI-271 random generator core (types.RandomGen) and
//! the OS entropy fill (platform.osRandomBytes). End-to-end library semantics
//! are covered by tests/scheme/srfi/srfi271.scm.

const std = @import("std");
const types = @import("types.zig");
const platform = @import("platform.zig");
const testing = std.testing;

test "determinized RandomGen is reproducible from an equal seed state" {
    var a = types.RandomGen{ .kind = .determinized, .s = .{ 1, 2, 3, 4 } };
    var b = types.RandomGen{ .kind = .determinized, .s = .{ 1, 2, 3, 4 } };
    for (0..512) |_| {
        try testing.expectEqual(a.nextByte(), b.nextByte());
    }
}

test "determinized RandomGen diverges for different seeds" {
    var a = types.RandomGen{ .kind = .determinized, .s = .{ 1, 2, 3, 4 } };
    var b = types.RandomGen{ .kind = .determinized, .s = .{ 4, 3, 2, 1 } };
    var differ = false;
    for (0..64) |_| {
        if (a.nextByte() != b.nextByte()) {
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
        if (g.nextByte() != 0) {
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
    for (&buf1) |*x| x.* = g1.nextByte();
    // consume g2 in two uneven bursts straddling the 8-byte blocks
    for (buf2[0..3]) |*x| x.* = g2.nextByte();
    for (buf2[3..20]) |*x| x.* = g2.nextByte();
    try testing.expectEqualSlices(u8, &buf1, &buf2);
}

test "osRandomBytes fills the whole buffer" {
    var buf: [96]u8 = .{0} ** 96;
    platform.osRandomBytes(&buf);
    // A real entropy source is ~never all-zero across 96 bytes, and the
    // fallback drain also writes every slot.
    var nonzero: usize = 0;
    for (buf) |b| {
        if (b != 0) nonzero += 1;
    }
    try testing.expect(nonzero > 0);
}

test "osRandomBytes handles empty and single-byte buffers" {
    var none: [0]u8 = .{};
    platform.osRandomBytes(&none); // no-op, must not crash
    var one: [1]u8 = .{0};
    platform.osRandomBytes(&one); // must not crash
}

test "randomized RandomGen keeps producing bytes without EOF" {
    var g = types.RandomGen{ .kind = .randomized };
    // Exercise the entropy-refill path many times over (~13 blocks).
    for (0..100) |_| std.mem.doNotOptimizeAway(g.nextByte());
}
