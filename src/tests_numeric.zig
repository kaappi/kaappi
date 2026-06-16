// Phase 4: Numeric Tower (flonums, mixed arithmetic, division, rounding, exactness, sqrt, expt, trig, special floats, gcd, comparisons, predicates, string->number)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "eval float literal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("3.14");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), types.toFlonum(result), 1e-10);
}

test "eval float with exponent" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("1e10");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expectApproxEqAbs(@as(f64, 1e10), types.toFlonum(result), 1.0);
}

test "eval mixed arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(+ 1 2.0)");
    try std.testing.expect(types.isFlonum(r1));
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), types.toFlonum(r1), 1e-10);

    const r2 = try vm.eval("(* 2 3.5)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(- 10.0 3)");
    try std.testing.expect(types.isFlonum(r3));
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), types.toFlonum(r3), 1e-10);
}

test "eval division" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Exact division stays fixnum
    const r1 = try vm.eval("(/ 10 2)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(r1));

    // Non-exact division returns rational
    const r2 = try vm.eval("(/ 10 3)");
    try std.testing.expect(types.isRationalObj(r2));
    const rat2 = types.toRational(r2);
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(rat2.numerator));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(rat2.denominator));

    // Unary division returns rational
    const r3 = try vm.eval("(/ 4)");
    try std.testing.expect(types.isRationalObj(r3));
    const rat3 = types.toRational(r3);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(rat3.numerator));
    try std.testing.expectEqual(@as(i64, 4), types.toFixnum(rat3.denominator));
}

test "eval rounding" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(floor 3.7)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), types.toFlonum(r1), 1e-10);

    const r2 = try vm.eval("(ceiling 3.2)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(truncate -3.7)");
    try std.testing.expectApproxEqAbs(@as(f64, -3.0), types.toFlonum(r3), 1e-10);

    // floor on fixnum returns fixnum
    const r4 = try vm.eval("(floor 42)");
    try std.testing.expect(types.isFixnum(r4));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r4));
}

test "eval exactness" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(exact? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(exact? 3.14)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(inexact? 3.14)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(inexact? 42)"));

    // exact converts flonum to fixnum
    const r1 = try vm.eval("(exact 3.0)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r1));

    // inexact converts fixnum to flonum
    const r2 = try vm.eval("(inexact 42)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), types.toFlonum(r2), 1e-10);
}

test "eval sqrt" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Perfect square returns fixnum
    const r1 = try vm.eval("(sqrt 4)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(r1));

    // Non-perfect square returns flonum
    const r2 = try vm.eval("(sqrt 2.0)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 1.4142135623730951), types.toFlonum(r2), 1e-10);
}

test "eval expt" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(expt 2 10)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 1024), types.toFixnum(r1));

    const r2 = try vm.eval("(expt 2.0 0.5)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 1.4142135623730951), types.toFlonum(r2), 1e-10);
}

test "eval trig" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(sin 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), types.toFlonum(r1), 1e-10);

    const r2 = try vm.eval("(cos 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(atan 1.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.7853981633974483), types.toFlonum(r3), 1e-10);
}

test "eval special float values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("+inf.0");
    try std.testing.expect(types.isFlonum(r1));
    try std.testing.expect(std.math.isInf(types.toFlonum(r1)));

    const r2 = try vm.eval("-inf.0");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expect(std.math.isInf(types.toFlonum(r2)));
    try std.testing.expect(types.toFlonum(r2) < 0);

    const r3 = try vm.eval("+nan.0");
    try std.testing.expect(types.isFlonum(r3));
    try std.testing.expect(std.math.isNan(types.toFlonum(r3)));

    try std.testing.expectEqual(types.TRUE, try vm.eval("(infinite? +inf.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(nan? +nan.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(finite? 1)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(finite? +inf.0)"));
}

test "eval gcd and lcm" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(gcd 32 -36)");
    try std.testing.expectEqual(@as(i64, 4), types.toFixnum(r1));

    const r2 = try vm.eval("(lcm 4 6)");
    try std.testing.expectEqual(@as(i64, 12), types.toFixnum(r2));

    const r3 = try vm.eval("(gcd)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(r3));

    const r4 = try vm.eval("(lcm)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r4));
}

test "eval comparisons with mixed types" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 1 1.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< 1 2.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> 3.5 2)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(<= 1 1.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= 2.0 2)"));
}

test "eval number predicates with flonums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(number? 3.14)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(integer? 3.0)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(integer? 3.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(zero? 0.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(positive? 1.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(negative? -2.3)"));
}

test "eval string->number" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(string->number \"42\")");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r1));

    const r2 = try vm.eval("(string->number \"3.14\")");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(string->number \"hello\")");
    try std.testing.expectEqual(types.FALSE, r3);
}
