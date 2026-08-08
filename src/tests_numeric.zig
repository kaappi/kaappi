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

test "sqrt exact rational and bignum perfect squares" {
    // #1412: exact rationals whose numerator and denominator are both
    // perfect squares return exact rationals, and bignum perfect squares
    // return exact integer roots.
    try th.expectEvalTrue("(let ((r (sqrt 9/4))) (and (exact? r) (= r 3/2)))");
    try th.expectEvalTrue("(let ((r (sqrt 1/4))) (and (exact? r) (= r 1/2)))");
    try th.expectEvalTrue("(let ((r (sqrt 16/9))) (and (exact? r) (= r 4/3)))");
    try th.expectEvalTrue("(let ((r (sqrt (* 12345678901234567 12345678901234567)))) (and (exact? r) (= r 12345678901234567)))");
    // Non-perfect squares stay inexact
    try th.expectEvalTrue("(inexact? (sqrt 2/3))");
    try th.expectEvalTrue("(inexact? (sqrt 9/2))");
    try th.expectEvalTrue("(inexact? (sqrt 2/9))");
    // exact-integer-sqrt still works through the shared helper
    try th.expectEvalTrue("(call-with-values (lambda () (exact-integer-sqrt 17)) (lambda (s r) (and (= s 4) (= r 1))))");
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

test "rational->f64 is correct past f64 range on one side (#2183)" {
    // The naive toF64(num)/toF64(den) collapsed whenever a side alone left
    // f64 range while the quotient was representable: a bignum denominator
    // gave 0.0 for subnormal results, a bignum numerator gave +inf for
    // ordinary integers, and both overflowing gave nan (the parsers had no
    // band-aid). The shared scaled conversion must round correctly.
    //
    // Denominator alone overflows: true value is the min subnormal.
    try th.expectEvalTrue("(= (inexact (/ 1 (expt 2 1074))) 5e-324)");
    try th.expectEvalTrue("(= (inexact (/ 1 (expt 2 1049))) 1.6578092e-316)");
    // exact->inexact round-trip destroyed by the collapse.
    try th.expectEvalTrue("(= (inexact (exact 1e-320)) 1e-320)");
    // Numerator alone overflows: true value is an ordinary integer.
    try th.expectEvalTrue("(= (inexact (/ (+ (expt 2 1030) 1) (expt 2 1000))) 1073741824.0)");
    // Both overflow: the parsers used to give nan, inexact got it right.
    try th.expectEvalTrue(
        "(let ((s (string-append \"#i\" (number->string (+ (expt 2 1100) 1)) \"/\" (number->string (expt 2 1050)))))" ++
            " (and (= (string->number s) 1125899906842624.0)" ++
            "      (= (read (open-input-string s)) 1125899906842624.0)))",
    );
    // Correct rounding at the subnormal tie: 1/2^1075 is exactly halfway
    // between 0 and the min subnormal; round-to-nearest-even picks 0.0.
    try th.expectEvalTrue("(= (inexact (/ 1 (expt 2 1075))) 0.0)");
    // The whole top binade [2^1023, 2^1024) is representable: overflow
    // starts at 2^1024, not at 2^1023 (an off-by-one that returned +inf.0
    // for the entire binade).
    try th.expectEvalTrue("(= (inexact (/ (+ (expt 2 1024) 1) 2)) 8.98846567431158e307)");
    try th.expectEvalTrue("(= (inexact (/ (- (expt 2 1024) 1) 2)) 8.98846567431158e307)");
    // ... while values at or above 2^1024 still overflow.
    try th.expectEvalTrue("(infinite? (inexact (/ (expt 2 1024) 1)))");
    try th.expectEvalTrue("(infinite? (inexact (/ (+ (expt 2 1025) 1) 2)))");
    // A lopsided ratio must keep full mantissa precision (a short quotient
    // or an f64/f64 ratio used to be off by 1-2 ulp).
    try th.expectEvalTrue("(= (inexact (/ (+ (expt 10 400) 1) (expt 10 399))) 10.0)");
    // Controls: in-range and reducible cases unchanged.
    try th.expectEvalTrue("(= (inexact (/ 1 (expt 2 1000))) 9.332636185032189e-302)");
    try th.expectEvalTrue("(= (inexact (/ (expt 2 1100) (expt 2 1050))) 1125899906842624.0)");
    // Signs survive.
    try th.expectEvalTrue("(= (inexact (/ -1 (expt 2 1074))) -5e-324)");
}

test "reader accepts rational literals with bignum parts" {
    // Regression: the tokenizer parsed rational parts as i64 with no bignum
    // fallback, so 2^65/2^64 failed with a read error at the slash.
    try th.expectEval("36893488147419103232/18446744073709551616", 2);
    try th.expectEval("-36893488147419103232/18446744073709551616", -2);
    try th.expectEval("#e36893488147419103232/18446744073709551616", 2);
    // Radix-prefixed: 2^65/2^64 in hex, binary 2^65/2
    try th.expectEval("#x20000000000000000/10000000000000000", 2);
    try th.expectEvalTrue("(= #b100000000000000000000000000000000000000000000000000000000000000000/10 (expt 2 64))");
    // bignum/fixnum reducing to a bignum integer
    try th.expectEvalTrue("(= 36893488147419103232/2 (expt 2 64))");
    // Irreducible results keep exact bignum parts
    try th.expectEvalTrue("(= (numerator 36893488147419103232/3) (expt 2 65))");
    try th.expectEval("(denominator 36893488147419103232/3)", 3);
    try th.expectEvalTrue("(= (denominator 3/36893488147419103232) (expt 2 65))");
    try th.expectEvalTrue("(exact? 36893488147419103232/3)");
    // Inexact prefix divides as flonums
    try th.expectEvalTrue("(= #i36893488147419103232/18446744073709551616 2.0)");
    // Bignum/0 is a read error, matching 1/0
    try th.expectEvalTrue("(guard (e ((read-error? e) #t) (#t #f)) (read (open-input-string \"36893488147419103232/0\")))");
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

test "complex negation preserves exactness (#2166)" {
    // R7RS 6.2: negating an exact complex must stay exact. Unary (- z) and
    // (- 0 z) are rounding-free, so the exactness flags survive; the rest of
    // complex arithmetic still collapses to inexact (#2166 tracks it).
    try th.expectEvalTrue("(exact? (- (make-rectangular 3/2 1)))");
    try th.expectEvalTrue(
        "(let ((n (- (make-rectangular 3/2 1)))) (and (= (real-part n) -3/2) (= (imag-part n) -1)))",
    );
    try th.expectEvalTrue("(exact? (- 0 (make-rectangular 3/2 1)))");
    try th.expectEvalTrue("(eqv? (- 0 (make-rectangular 3/2 1)) (- (make-rectangular 3/2 1)))");
    // An inexact-zero minuend must NOT take the exact shortcut.
    try th.expectEvalTrue("(inexact? (- 0.0 (make-rectangular 3/2 1)))");
    // Inexact complexes stay inexact; mixed flags are preserved componentwise.
    try th.expectEvalTrue("(inexact? (- (make-rectangular 1.5 1.0)))");
    try th.expectEvalTrue(
        "(eqv? (- (make-rectangular 3/2 1.0)) (make-rectangular -3/2 -1.0))",
    );
    // An exact zero component normalizes to +0.0, not -0.0: the negation must
    // stay eqv? to the same value built directly by make-rectangular.
    try th.expectEvalTrue("(eqv? (- (make-rectangular 0 1)) (make-rectangular 0 -1))");
    try th.expectEvalTrue("(exact? (- (make-rectangular 0 1)))");
    // Double negation round-trips to an eqv? value.
    try th.expectEvalTrue(
        "(let ((z (make-rectangular 3/2 1))) (eqv? (- (- z)) z))",
    );
}

test "eqv? discriminates exact and inexact complex (#2167)" {
    // R7RS 6.1: one exact and one inexact number are never eqv?, however
    // equal their f64 images. = keeps saying #t (it ignores exactness).
    try th.expectEvalBool("(eqv? (make-rectangular -3/2 -1) -1.5-1.0i)", false);
    try th.expectEvalBool("(equal? (make-rectangular -3/2 -1) -1.5-1.0i)", false);
    try th.expectEvalBool("(= (make-rectangular -3/2 -1) -1.5-1.0i)", true);
    try th.expectEvalBool("(eqv? (make-rectangular 3/2 1) (make-rectangular 1.5 1))", false);
    // Mixed-component values compare flags componentwise.
    try th.expectEvalBool("(eqv? (make-rectangular 3/2 1.0) 1.5+1.0i)", false);
    // Same exactness still compares equal...
    try th.expectEvalBool("(eqv? (make-rectangular 3/2 1) (make-rectangular 3/2 1))", true);
    try th.expectEvalBool("(eqv? 1.5+1.0i 1.5+1.0i)", true);
    // ...and the bitwise component rule is untouched: signed zero and NaN.
    try th.expectEvalBool("(eqv? 0.0+1i -0.0+1i)", false);
    try th.expectEvalBool("(eqv? +nan.0+1i +nan.0+1i)", true);
    // memv/assv (isEqv) and case (compiled to an eqv? call) follow.
    try th.expectEvalBool("(memv (make-rectangular -3/2 -1) (list -1.5-1.0i))", false);
    try th.expectEvalBool(
        "(assv (make-rectangular -3/2 -1) (list (cons -1.5-1.0i 'x)))",
        false,
    );
    try th.expectEvalTrue(
        "(eq? 'else-branch (case (make-rectangular -3/2 -1) ((-1.5-1.0i) 'inexact-branch) (else 'else-branch)))",
    );
    try th.expectEvalTrue(
        "(eq? 'hit (case (- (make-rectangular 3/2 1)) ((-3/2-1i) 'hit) (else 'miss)))",
    );
}

// ---------------------------------------------------------------------------
// #1911 family: the reader's #e/#i path now routes through the same
// digit-exact parseNumberText as string->number, replacing a token-level
// f64-unrounding conversion that failed at both ends of the range.
// ---------------------------------------------------------------------------

test "#e keeps exactness past i64 (#1891)" {
    try th.expectEvalBool("(exact? #e1e19)", true);
    try th.expectEvalTrue("(= #e1e19 (expt 10 19))");
    try th.expectEvalBool("(exact? #e1e400)", true);
    try th.expectEvalTrue("(= #e1e400 (expt 10 400))");
    try th.expectEvalTrue("(= #e-1e19 (- (expt 10 19)))");
    try th.expectEvalTrue("(= #e1.5e20 (* 15 (expt 10 19)))");
    try th.expectEvalBool("(exact? #e#d1e20)", true);
}

test "#e decimal at the 2^63 boundary parses exactly, no panic (#1907)" {
    // Every double rounding to exactly 2^63 used to overflow @intFromFloat
    // and abort the process (exit 134): maxInt(i64) is not representable as
    // f64, so the old `f > @floatFromInt(maxInt(i64))` guard admitted 2^63
    // itself. Source literals are deliberate — a regression aborts this
    // test run loudly.
    try th.expectEvalTrue("(= #e9223372036854775808.0 (expt 2 63))");
    try th.expectEvalTrue("(= #e9223372036854775296.0 9223372036854775296)");
    try th.expectEvalTrue("(= #e-9223372036854775808.0 (- (expt 2 63)))");
    try th.expectEvalTrue("(= #e9223372036854774784.0 9223372036854774784)");
    // Digit-exact semantics: the exponent spelling denotes its decimal
    // value, not the f64 it happens to round to. string->number agrees.
    try th.expectEvalTrue("(= #e9.223372036854776e18 9223372036854776000)");
    try th.expectEvalTrue(
        "(equal? #e9.223372036854776e18 (string->number \"#e9.223372036854776e18\"))",
    );
}

test "#i honors the radix on bignum digit runs (#1908)" {
    // The digits used to be fed to parseFloat as decimal, silently wrong by
    // orders of magnitude (and a spurious error for hex letters). The
    // conversion is now the identical limb walk string->number uses.
    try th.expectEvalTrue("(= #i#x1000000000000000000 (inexact #x1000000000000000000))");
    try th.expectEvalTrue("(= #i#o100000000000000000000000 (inexact #o100000000000000000000000))");
    try th.expectEvalTrue("(= #i#xFFFFFFFFFFFFFFFFFF (inexact #xFFFFFFFFFFFFFFFFFF))");
    try th.expectEvalTrue("(equal? #i#x1000000000000000000 (string->number \"#i#x1000000000000000000\"))");
    try th.expectEvalBool("(exact? #i#x1000000000000000000/3)", false);
}

test "#e below 1e-15 keeps the value and its sign (#1909)" {
    // The old continued-fraction conversion converged to 0/1 inside its
    // absolute 1e-15 tolerance, losing the entire value.
    try th.expectEvalTrue("(= #e1e-16 (/ 1 (expt 10 16)))");
    try th.expectEvalTrue("(= #e1e-15 (/ 1 (expt 10 15)))");
    try th.expectEvalTrue("(negative? #e-1e-20)");
    try th.expectEvalTrue("(= #e1e-30 (/ 1 (expt 10 30)))");
    try th.expectEvalTrue("(= #e1.5e-18 (/ 3 (* 2 (expt 10 18))))");
}

test "#e/#i reach complex literals on both parsers (#1910, #751)" {
    try th.expectEvalBool("(exact? #i1+2i)", false);
    try th.expectEvalBool("(exact? (string->number \"#e1+2i\"))", true);
    try th.expectEvalBool("(exact? (string->number \"#i1+2i\"))", false);
    try th.expectEvalTrue("(equal? #i1+2i (string->number \"#i1+2i\"))");
    try th.expectEvalTrue("(equal? #e1+2i (string->number \"#e1+2i\"))");
    // A component past i64 used to write as the unreadable 0/0; it now
    // writes its exact digits and round-trips.
    try th.expectEvalTrue(
        "(let ((p (open-output-string))) (write #e1e19+1i p) (string=? (get-output-string p) \"10000000000000000000+1i\"))",
    );
    try th.expectEvalTrue(
        "(let ((x #e1e19+1i) (p (open-output-string))) (write x p) (equal? x (read (open-input-string (get-output-string p)))))",
    );
    // An exact-flagged component below the rational search's granularity
    // used to print as 0 (value destroyed); it now prints its exact
    // mantissa/2^k value, verified against the independent bignum printer
    // behind (exact f).
    try th.expectEvalTrue(
        "(let ((p (open-output-string)) (ex (exact 1e-300))) (write #e1e-300+1i p)" ++
            " (equal? (get-output-string p) (string-append (number->string (numerator ex))" ++
            " \"/\" (number->string (denominator ex)) \"+1i\")))",
    );
    // That spelling now reads back: the reader's complex grammar accepts
    // the m/2^k form (bignum rational real part) via the scaled
    // rational->f64 conversion (kaappi#2182/#2183), so the write/read
    // round-trip is exact -- this used to be a deliberately-failing pin.
    try th.expectEvalTrue(
        "(let ((p (open-output-string))) (write #e1e-300+1i p)" ++
            " (equal? (read (open-input-string (get-output-string p))) #e1e-300+1i))",
    );
    // The gate: a bignum rational that is NOT exactly representable in f64
    // still reads loudly instead of silently rounding an exact-flagged
    // component, and string->number agrees (R7RS 6.2.7).
    try th.expectEvalTrue(
        "(guard (e (#t #t)) (read (open-input-string \"10000000000000000000000000/3+1i\")) #f)",
    );
    try th.expectEvalBool("(string->number \"10000000000000000000000000/3+1i\")", false);
    // The gate's overflow side: a power-of-two-scaled numerator whose value
    // exceeds f64 range (2^2001/2) must stay loud too -- an exact-flagged
    // component that converts to +inf.0 is the same silent masquerade.
    try th.expectEvalTrue(
        "(guard (e (#t #t)) (read (open-input-string " ++
            "(string-append (number->string (expt 2 2001)) \"/2+1i\"))) #f)",
    );
    try th.expectEvalTrue(
        "(guard (e (#t #t)) (read (open-input-string \"1/10000000000000000000000001+1i\")) #f)",
    );
    // The dead zone is closed: an i64 power-of-two denominator past the
    // printer's small-rational recovery limit (1/2^40) is exactly
    // representable and now reads, matching the bignum path (and the
    // printer's own m/2^k output).
    try th.expectEvalTrue("(equal? (read (open-input-string \"1/1099511627776+1i\"))" ++
        " (read (open-input-string \"1/1099511627776+1i\")))");
    try th.expectEvalTrue("(number? (string->number \"1/1099511627776+1i\"))");
    // Radix-prefixed bignum rational complex tails honor the radix for the
    // imaginary part too (a hex 12 is 18, not decimal 12).
    try th.expectEvalTrue("(= (imag-part (read (open-input-string " ++
        "(string-append \"#x\" (number->string (expt 2 100) 16) \"/2+12i\")))) 18.0)");
    try th.expectEvalTrue("(= (imag-part (string->number " ++
        "(string-append \"#x\" (number->string (expt 2 100) 16) \"/2+12i\"))) 18.0)");
    // An exact-flagged imaginary part past 2^53 after a bignum rational real
    // is a loud error, not a silently rounded value claiming exactness.
    try th.expectEvalTrue(
        "(guard (e (#t #t)) (read (open-input-string " ++
            "(string-append \"1/3+123456789012345678901234567890i\"))) #f)",
    );
    // string->number shares the grammar: it accepts the m/2^k spelling too.
    try th.expectEvalTrue(
        "(let ((ex (exact 1e-300)))" ++
            " (let ((s (string-append (number->string (numerator ex)) \"/\" (number->string (denominator ex)) \"+1i\")))" ++
            "  (and (string->number s) (= (real-part (string->number s)) (exact->inexact 1e-300)))))",
    );
    // #e refuses non-finite components, like the flonum rule (#419).
    try th.expectEvalTrue("(guard (e (#t #t)) (read (open-input-string \"#e1e999+2i\")) #f)");
    try th.expectEvalBool("(string->number \"#e1e999+2i\")", false);
}

test "#e on inf/nan is a read error matching string->number's #f (#1911)" {
    try th.expectEvalTrue("(guard (e (#t #t)) (read (open-input-string \"#e+inf.0\")) #f)");
    try th.expectEvalTrue("(guard (e (#t #t)) (read (open-input-string \"#e-inf.0\")) #f)");
    try th.expectEvalTrue("(guard (e (#t #t)) (read (open-input-string \"#e+nan.0\")) #f)");
    try th.expectEvalBool("(string->number \"#e+inf.0\")", false);
    try th.expectEvalTrue("(and (inexact? #i+inf.0) (infinite? #i+inf.0))");
}

test "string->number accepts the unprefixed decimal spelling of 2^63 (#1921)" {
    // parseInt overflows on the final digit before ever seeing the '.', and
    // the bignum fallback's InvalidCharacter used to reject outright
    // instead of falling through to the decimal parse.
    try th.expectEvalTrue("(= (string->number \"9223372036854775808.0\") 9223372036854775808.0)");
    try th.expectEvalTrue(
        "(equal? (string->number \"9223372036854775808.0\") (read (open-input-string \"9223372036854775808.0\")))",
    );
    try th.expectEvalTrue("(= (string->number \"#e9223372036854775808.0\") (expt 2 63))");
    try th.expectEvalTrue("(= (string->number \"9223372036854775807.0\") 9223372036854775807.0)");
    try th.expectEvalTrue("(= (string->number \"-9223372036854775808.0\") -9223372036854775808.0)");
    // Overflowing digits followed by genuinely invalid text still reject.
    try th.expectEvalBool("(string->number \"92233720368547758081abc\")", false);
    try th.expectEvalBool("(string->number \"9223372036854775808.0.0\")", false);
}
