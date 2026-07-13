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

test "case-lambda does not capture user variables named n or args" {
    // Regression: the desugaring bound its internal rest-args list to `args`
    // and the argument count to `n`, shadowing user variables of those names
    // inside clause bodies (#836).
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define n 42)");
    _ = try vm.eval("(define f (case-lambda ((x) (+ x n))))");
    const r1 = try vm.eval("(f 1)");
    try std.testing.expectEqual(@as(i64, 43), types.toFixnum(r1));

    _ = try vm.eval("(define args 100)");
    _ = try vm.eval("(define g (case-lambda ((x) (+ x args))))");
    const r2 = try vm.eval("(g 1)");
    try std.testing.expectEqual(@as(i64, 101), types.toFixnum(r2));

    // Rest-arg clauses go through the same desugaring
    _ = try vm.eval("(define h (case-lambda ((x . rest) (+ x n args))))");
    const r3 = try vm.eval("(h 1 2 3)");
    try std.testing.expectEqual(@as(i64, 143), types.toFixnum(r3));
}

test "case-lambda dispatches to clauses beyond the 32nd" {
    // Regression: a fixed 32-entry buffer silently dropped later clauses, so
    // calls matching them fell through to the wrong-number-of-arguments error.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const alloc = std.testing.allocator;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(alloc);

    // (define f (case-lambda (() 0) ((a0) 1) ((a0 a1) 2) ... arity 33))
    try src.appendSlice(alloc, "(define f (case-lambda");
    var arity: usize = 0;
    while (arity < 34) : (arity += 1) {
        try src.appendSlice(alloc, " ((");
        var j: usize = 0;
        while (j < arity) : (j += 1) {
            var buf: [16]u8 = undefined;
            try src.appendSlice(alloc, try std.fmt.bufPrint(&buf, " a{d}", .{j}));
        }
        var buf: [16]u8 = undefined;
        try src.appendSlice(alloc, try std.fmt.bufPrint(&buf, ") {d})", .{arity}));
    }
    try src.appendSlice(alloc, "))");
    _ = try vm.eval(src.items);

    src.clearRetainingCapacity();
    try src.appendSlice(alloc, "(f");
    var k: usize = 0;
    while (k < 33) : (k += 1) {
        try src.appendSlice(alloc, " 1");
    }
    try src.appendSlice(alloc, ")");

    const result = try vm.eval(src.items);
    try std.testing.expectEqual(@as(i64, 33), types.toFixnum(result));
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

// Regression for KEP-0004 Phase 0: evalFeatureReq's hardcoded known_libs
// fast-path (which never listed kaappi.* or srfi.18) was deleted in favor of
// always deferring to the globals.libraryExists callback. Locks in that the
// callback path alone still resolves these correctly.
test "cond-expand library check for kaappi fibers" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  ((library (kaappi fibers)) 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

test "cond-expand library check for srfi 18" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  ((library (srfi 18)) 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

// KEP-0004 Phase 1: bare feature identifiers for the KEP subsystems.
test "cond-expand kaappi-fibers feature" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  (kaappi-fibers 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

test "cond-expand kaappi-reactor feature" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  (kaappi-reactor 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

// Native unit-test builds are never wasm32-wasi, so kaappi-threads is always
// present here; its absence on wasm is covered by Lib.wasmAvailable's
// existing srfi_18 => false gate, not separately unit-testable on this host.
test "cond-expand kaappi-threads feature" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(cond-expand
        \\  (kaappi-threads 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(result));
}

// Regression: libraryIsAvailable must not let cond-expand report a
// disk-only library as available under --sandbox, since
// tryLoadLibraryFromFile rejects every file-backed load there — the
// mismatch would make (cond-expand ((library ...))) lie about what
// (import ...) can actually do, and let sandboxed code probe the host
// filesystem for .sld existence. srfi 41 is a portable .sld, never
// pre-registered in vm.libraries, so it only resolves via the disk
// probe this test is gating.
test "cond-expand library check honors sandbox mode" {
    // Skip when source tree isn't available (cross-compiled binary in container)
    _ = std.posix.openat(std.posix.AT.FDCWD, "lib/srfi/41.sld", .{}, 0) catch return error.SkipZigTest;

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const unsandboxed = try vm.eval(
        \\(cond-expand
        \\  ((library (srfi 41)) 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("yes", types.symbolName(unsandboxed));

    vm.sandbox_mode = true;
    const sandboxed = try vm.eval(
        \\(cond-expand
        \\  ((library (srfi 41)) 'yes)
        \\  (else 'no))
    );
    try std.testing.expectEqualStrings("no", types.symbolName(sandboxed));
}

// ---------------------------------------------------------------------------
// .sld loading tests
// ---------------------------------------------------------------------------

test "load library from .sld file" {
    // Skip when source tree isn't available (cross-compiled binary in container)
    _ = std.posix.openat(std.posix.AT.FDCWD, "testlib/helper.sld", .{}, 0) catch return error.SkipZigTest;

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
    _ = std.posix.openat(std.posix.AT.FDCWD, "testlib/with-include.sld", .{}, 0) catch return error.SkipZigTest;

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

// ---------------------------------------------------------------------------
// Closures with many captured variables (#809)
// ---------------------------------------------------------------------------

// Builds a program of the form
//   (define f (lambda () (define v0 0) ... (define v{n-1} {n-1})
//                        (lambda () (+ v0 (+ v1 ... (+ v{n-2} v{n-1}))))))
//   ((f))
// The inner lambda captures every v_i as an upvalue, so the returned closure
// has exactly `n` upvalues. Evaluating it yields 0+1+...+(n-1) = n*(n-1)/2.
// Pairwise `+` keeps every call under the 256-argument limit so the only thing
// under test is the upvalue count. Requires n >= 2.
fn buildManyCaptureProgram(src: *std.ArrayList(u8), n: usize) !void {
    const a = std.testing.allocator;
    try src.appendSlice(a, "(define f (lambda ()");
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const line = try std.fmt.allocPrint(a, " (define v{d} {d})", .{ i, i });
        defer a.free(line);
        try src.appendSlice(a, line);
    }
    try src.appendSlice(a, " (lambda () ");
    i = 0;
    while (i + 1 < n) : (i += 1) {
        const piece = try std.fmt.allocPrint(a, "(+ v{d} ", .{i});
        defer a.free(piece);
        try src.appendSlice(a, piece);
    }
    const last = try std.fmt.allocPrint(a, "v{d}", .{n - 1});
    defer a.free(last);
    try src.appendSlice(a, last);
    i = 0;
    while (i + 1 < n) : (i += 1) try src.append(a, ')');
    try src.appendSlice(a, ")))"); // close inner lambda, outer lambda, define
    try src.appendSlice(a, " ((f))");
}

test "closure capturing 27 variables does not overflow byte accounting (#809)" {
    // Regression: allocClosure computed `@sizeOf(Closure) + upvalue_count *
    // @sizeOf(Value)` in u8 arithmetic, overflowing (panic) at 27 captures.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const n = 27;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(std.testing.allocator);
    try buildManyCaptureProgram(&src, n);

    const result = try vm.eval(src.items);
    try std.testing.expectEqual(@as(i64, n * (n - 1) / 2), types.toFixnum(result));
}

test "closure capturing more than 255 variables compiles and runs (#809)" {
    // Regression: addUpvalue did `@intCast` of the upvalue count into a u8
    // upvalue_count field, panicking (compile-time) past 255 captures. The
    // field is now u16, matching the u16 upvalue index in the bytecode.
    //
    // The u16-width property is orthogonal to GC rooting, and compiling the
    // 300-capture program with a collection per allocation peaks around 7 GB
    // RSS under the testing allocator — the full-suite stress run gets
    // OOM-killed. Skip on stress builds; the 27-variable sibling test below
    // keeps the capture path exercised there.
    if (@import("build_options").gc_stress) return error.SkipZigTest;
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const n = 300;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(std.testing.allocator);
    try buildManyCaptureProgram(&src, n);

    const result = try vm.eval(src.items);
    try std.testing.expectEqual(@as(i64, n * (n - 1) / 2), types.toFixnum(result));
}
