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

test "exact rational comparisons never fall back to f64 (issue 844)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // (2^100+1)/2^101 and 1/2 are distinct exact numbers within one double ULP.
    try std.testing.expectEqual(types.FALSE, try vm.eval("(= (/ (+ (expt 2 100) 1) (expt 2 101)) 1/2)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< 1/2 (/ (+ (expt 2 100) 1) (expt 2 101)))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (/ (+ (expt 2 100) 1) (expt 2 101)) 1/2)"));

    // i64 cross-product overflows but parts still fit fixnums.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< 1/1000000000 1/999999999)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 3000000000/6000000000 1/2)"));

    // Rational vs bignum near equality (differ by 1/3).
    try std.testing.expectEqual(types.FALSE, try vm.eval("(= (/ (+ (* 3 (expt 2 100)) 1) 3) (expt 2 100))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (/ (+ (* 3 (expt 2 100)) 1) 3) (expt 2 100))"));
}

test "exact-vs-inexact comparisons stay transitive (issue 844)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // (exact 0.3333333333333333) is 6004799503160661/18014398509481984, not 1/3.
    try std.testing.expectEqual(types.FALSE, try vm.eval("(= (exact 0.3333333333333333) 1/3)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(= 1/3 0.3333333333333333)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< 0.3333333333333333 1/3)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> 1/3 0.3333333333333333)"));

    // Transitivity: e = double(1/3) < 1/3, and e = 0.333..., so e /= 1/3.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(let ((e (exact 0.3333333333333333))) (and (= e 0.3333333333333333) (< e 1/3) (not (= e 1/3))))"));

    // Controls that must keep working.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 1/2 0.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< 1/3 +inf.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> 1/3 -inf.0)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(= 1/3 +nan.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= -1/2 -0.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< -1/3 -0.3333333333333333)"));
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

test "types.toF64 handles bignums (#792)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Single-limb bignum
    const big1 = try vm.eval("(expt 2 60)");
    try std.testing.expect(types.isBignum(big1));
    try std.testing.expectApproxEqRel(@as(f64, 1152921504606846976.0), types.toF64(big1), 1e-10);

    // Multi-limb bignum
    const big2 = try vm.eval("(expt 10 20)");
    try std.testing.expect(types.isBignum(big2));
    try std.testing.expect(types.toF64(big2) > 9.9e19);

    // Bignum-backed rational: numerator is bignum
    const rat1 = try vm.eval("(/ (expt 10 20) 3)");
    const f1 = types.toF64(rat1);
    try std.testing.expect(f1 > 3.3e19);

    // Bignum-backed rational: denominator is bignum
    const rat2 = try vm.eval("(/ 1 (expt 10 20))");
    const f2 = types.toF64(rat2);
    try std.testing.expect(std.math.isFinite(f2));
    try std.testing.expect(f2 > 0.0);
    try std.testing.expect(f2 < 1e-19);
}

test "bignum rational arithmetic survives GC stress (#1414)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // 2^50 and 2^48 both exceed the ±2^47 fixnum range, so the rational
    // accumulator loops in +, -, *, / allocate a bignum on every update.
    _ = try vm.eval("(define big-a 1125899906842624)");
    _ = try vm.eval("(define big-b 281474976710656)");

    // Collect on every allocation: an unrooted intermediate is freed and its
    // memory reused by the next accumulator update, aliasing the operands.
    gc.stress = true;

    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 4 (/ big-a big-b))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 1407374883553280 (+ big-a big-b))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 844424930131968 (- big-a big-b))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 4 (* big-a (/ 1 big-b)))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= (/ 5 big-a) (+ (/ 1 big-a) (/ 1 big-b)))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval(
        "(= 1000000007 (/ (* 1234567890123456789 1000000007) 1234567890123456789))",
    ));
    // string->number's rational parse holds the numerator bignum across the
    // denominator parse — same unrooted-intermediate hazard. First case takes
    // the makeFixnumChecked branch (parts fit i64), second takes the
    // parseBignumString branch (parts >= 2^63).
    try std.testing.expectEqual(types.TRUE, try vm.eval(
        "(= 4 (string->number \"1125899906842624/281474976710656\"))",
    ));
    try std.testing.expectEqual(types.TRUE, try vm.eval(
        "(= 2 (string->number \"36893488147419103232/18446744073709551616\"))",
    ));
}
