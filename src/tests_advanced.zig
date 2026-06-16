// Phase 11: Deferred features
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

// ---------------------------------------------------------------------------
// apply tests
// ---------------------------------------------------------------------------

test "apply with list arg" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(apply + '(1 2 3))");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(result));
}

test "apply with individual and list args" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(apply + 1 2 '(3 4))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));
}

test "apply with cons" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(apply cons 1 '(2))");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.cdr(result)));
}

test "apply with lambda" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(apply (lambda (x y) (+ x y)) '(3 4))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "apply with empty list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(apply + '())");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// case tests
// ---------------------------------------------------------------------------

test "case basic match" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(case (+ 1 1)
        \\  ((1) 'one)
        \\  ((2) 'two)
        \\  ((3) 'three))
    );
    try std.testing.expectEqualStrings("two", types.symbolName(result));
}

test "case else clause" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(case 99
        \\  ((1) 'one)
        \\  ((2) 'two)
        \\  (else 'other))
    );
    try std.testing.expectEqualStrings("other", types.symbolName(result));
}

test "case multiple datums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(case 2
        \\  ((1 2 3) 'small)
        \\  ((4 5 6) 'big)
        \\  (else 'other))
    );
    try std.testing.expectEqualStrings("small", types.symbolName(result));
}

test "case no match no else" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(case 99
        \\  ((1) 'one)
        \\  ((2) 'two))
    );
    try std.testing.expectEqual(types.VOID, result);
}

test "case with symbol datums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(case 'b
        \\  ((a) 1)
        \\  ((b) 2)
        \\  ((c) 3))
    );
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// let-values tests
// ---------------------------------------------------------------------------

test "let-values basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let-values (((a b) (values 1 2))) (+ a b))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "let-values multiple bindings" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let-values (((a b) (values 1 2)) ((c) (values 3))) (+ a b c))");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(result));
}

test "let-values single value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let-values (((x) 42)) x)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "let*-values basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let*-values (((a b) (values 1 2)) ((c) (values (+ a b)))) c)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "case with multiple body exprs" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(case 1
        \\  ((1) (+ 1 1) (+ 2 2))
        \\  (else 99))
    );
    try std.testing.expectEqual(@as(i64, 4), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// case-lambda tests
// ---------------------------------------------------------------------------

test "case-lambda dispatch by arity" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define f
        \\  (case-lambda
        \\    (() 0)
        \\    ((x) x)
        \\    ((x y) (+ x y))))
    );

    const r0 = try vm.eval("(f)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(r0));

    const r1 = try vm.eval("(f 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r1));

    const r2 = try vm.eval("(f 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r2));
}

// ---------------------------------------------------------------------------
// Complex number tests
// ---------------------------------------------------------------------------

test "make-rectangular and real-part/imag-part" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const z = try vm.eval("(make-rectangular 3.0 4.0)");
    try std.testing.expect(types.isComplex(z));

    const rp = try vm.eval("(real-part (make-rectangular 3.0 4.0))");
    try std.testing.expect(types.isFlonum(rp));
    try std.testing.expectEqual(@as(f64, 3.0), types.toFlonum(rp));

    const ip = try vm.eval("(imag-part (make-rectangular 3.0 4.0))");
    try std.testing.expect(types.isFlonum(ip));
    try std.testing.expectEqual(@as(f64, 4.0), types.toFlonum(ip));
}

test "complex arithmetic addition" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(real-part (+ (make-rectangular 1.0 2.0) (make-rectangular 3.0 4.0)))");
    try std.testing.expectEqual(@as(f64, 4.0), types.toFlonum(result));

    const imag = try vm.eval("(imag-part (+ (make-rectangular 1.0 2.0) (make-rectangular 3.0 4.0)))");
    try std.testing.expectEqual(@as(f64, 6.0), types.toFlonum(imag));
}

test "complex arithmetic multiplication" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // (1+2i) * (3+4i) = (1*3 - 2*4) + (1*4 + 2*3)i = -5 + 10i
    const rp = try vm.eval("(real-part (* (make-rectangular 1.0 2.0) (make-rectangular 3.0 4.0)))");
    try std.testing.expectEqual(@as(f64, -5.0), types.toFlonum(rp));

    const ip = try vm.eval("(imag-part (* (make-rectangular 1.0 2.0) (make-rectangular 3.0 4.0)))");
    try std.testing.expectEqual(@as(f64, 10.0), types.toFlonum(ip));
}

test "complex magnitude" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(magnitude (make-rectangular 3.0 4.0))");
    try std.testing.expectEqual(@as(f64, 5.0), types.toFlonum(result));
}

test "real-part and imag-part of real numbers" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const rp = try vm.eval("(real-part 5)");
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(rp));

    const ip = try vm.eval("(imag-part 5)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(ip));
}

test "make-rectangular with zero imag returns flonum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(make-rectangular 5.0 0.0)");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expectEqual(@as(f64, 5.0), types.toFlonum(result));
}

test "complex? predicate" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(complex? 42)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(complex? 3.14)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(complex? (make-rectangular 1.0 2.0))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(complex? \"hello\")"));
}

test "case-lambda single clause" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define g (case-lambda ((x y) (* x y))))
    );

    const result = try vm.eval("(g 5 6)");
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// cond-expand tests
// ---------------------------------------------------------------------------

test "cond-expand r7rs feature" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  (r7rs 42)
        \\  (else 0))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "cond-expand kaappi feature" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  (kaappi 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

test "cond-expand unknown feature" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  (chicken 1)
        \\  (else 2))
    );
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "cond-expand and combinator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  ((and r7rs kaappi) 'both)
        \\  (else 'nope))
    );
    try std.testing.expectEqualStrings("both", types.symbolName(result));
}

test "cond-expand or combinator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  ((or chicken kaappi) 'found)
        \\  (else 'nope))
    );
    try std.testing.expectEqualStrings("found", types.symbolName(result));
}

test "cond-expand not combinator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  ((not chicken) 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

test "cond-expand library check" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  ((library (scheme base)) 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

// ---------------------------------------------------------------------------
// .sld loading tests
// ---------------------------------------------------------------------------

test "load library from .sld file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Import the test library from testlib/helper.sld
    _ = try vm.eval("(import (testlib helper))");

    const r1 = try vm.eval("(double 5)");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(r1));

    const r2 = try vm.eval("(triple 3)");
    try std.testing.expectEqual(@as(i64, 9), types.toFixnum(r2));
}

test "load library with include declaration" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Import the test library that uses include
    _ = try vm.eval("(import (testlib with-include))");

    const result = try vm.eval("(quadruple 5)");
    try std.testing.expectEqual(@as(i64, 20), types.toFixnum(result));
}

test "cond-expand no match no else is void" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  (chicken 1))
    );
    try std.testing.expectEqual(types.VOID, result);
}

// ---------------------------------------------------------------------------
// equal? on circular structures
// ---------------------------------------------------------------------------

test "equal? on circular lists terminates" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define a (list 1 2 3))");
    _ = try vm.eval("(set-cdr! (cddr a) a)");
    _ = try vm.eval("(define b (list 1 2 3))");
    _ = try vm.eval("(set-cdr! (cddr b) b)");
    const result = try vm.eval("(equal? a b)");
    try std.testing.expectEqual(types.TRUE, result);
}

test "equal? on different circular lists" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define a (list 1 2))");
    _ = try vm.eval("(set-cdr! (cdr a) a)");
    _ = try vm.eval("(define b (list 1 3))");
    _ = try vm.eval("(set-cdr! (cdr b) b)");
    const result = try vm.eval("(equal? a b)");
    try std.testing.expectEqual(types.FALSE, result);
}

// ---------------------------------------------------------------------------
// Nested quasiquote
// ---------------------------------------------------------------------------

test "nested quasiquote preserves inner structure" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("`(a `(b ,(+ 1 2)))");
    const s = try @import("printer.zig").valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(a (quasiquote (b (unquote (+ 1 2)))))", s);
}

test "nested quasiquote double unquote" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let ((x 1)) `(a `(b ,,x)))");
    const s = try @import("printer.zig").valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(a (quasiquote (b (unquote 1))))", s);
}
