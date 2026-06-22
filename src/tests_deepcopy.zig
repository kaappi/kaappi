const std = @import("std");
const memory = @import("memory.zig");
const types = @import("types.zig");

test "deepCopy fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const val = types.makeFixnum(42);
    const copied = try gc.deepCopy(val);
    try std.testing.expectEqual(val, copied);
}

test "deepCopy string" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const str = try gc1.allocString("hello");
    const copied = try gc2.deepCopy(str);

    try std.testing.expect(str != copied);
    const orig = types.toObject(str).as(types.SchemeString);
    const copy = types.toObject(copied).as(types.SchemeString);
    try std.testing.expectEqualSlices(u8, orig.data[0..orig.len], copy.data[0..copy.len]);
}

test "deepCopy pair" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const pair = try gc1.allocPair(types.makeFixnum(1), types.makeFixnum(2));
    const copied = try gc2.deepCopy(pair);

    try std.testing.expect(pair != copied);
    const orig_p = types.toObject(pair).as(types.Pair);
    const copy_p = types.toObject(copied).as(types.Pair);
    try std.testing.expectEqual(orig_p.car, copy_p.car);
    try std.testing.expectEqual(orig_p.cdr, copy_p.cdr);
}

test "deepCopy nested list" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const three = try gc1.allocPair(types.makeFixnum(3), types.NIL);
    const two = try gc1.allocPair(types.makeFixnum(2), three);
    const one = try gc1.allocPair(types.makeFixnum(1), two);
    const copied = try gc2.deepCopy(one);

    const p1 = types.toObject(copied).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(1), p1.car);
    const p2 = types.toObject(p1.cdr).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(2), p2.car);
    const p3 = types.toObject(p2.cdr).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(3), p3.car);
    try std.testing.expectEqual(types.NIL, p3.cdr);
}
