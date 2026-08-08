// Ellipsis validation regressions -- split out of tests_macros.zig (kept
// that file under the 1500-line policy) as its own natural seam: every test
// here exercises the R7RS 4.3.2 ellipsis rules the expander now enforces --
// #682 (a pattern variable used under fewer template ellipses than its
// pattern depth is a syntax error, not a silent `()`) and #2082 (at most one
// ellipsis per list or vector pattern).
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

// Issue #682: R7RS 4.3.2 / SRFI 149 rule 1 -- a pattern variable matched at
// ellipsis depth N may be used under AT MOST N template ellipses
// (SRFI 149 relaxes R7RS "as many" upward only). Under-using it previously
// substituted the unset `.value` (always NIL) for the list binding, silently
// discarding the matched input. Fixed in expander_instantiate.zig: the
// depth-0 use site in instantiateTemplate and the direct-reference depth
// check in instantiateEllipsis both raise EllipsisDepthMismatch, which the
// compiler reports as a syntax error.

test "syntax-rules: depth 2->1 under-use is an error (#682's own repro)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // `a` matches at depth 2, the template uses it under a single ellipsis.
    _ = try vm.eval(
        \\(define-syntax bad-depth
        \\  (syntax-rules ()
        \\    ((_ ((a ...) ...) (b ...))
        \\     (list (list a b) ...))))
    );
    const result = vm.eval("(bad-depth ((1 2) (3 4)) (10 20))");
    try std.testing.expectError(error.CompileError, result);
}

test "syntax-rules: depth 1->0 under-use (no ellipsis) is an error (#682)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax under
        \\  (syntax-rules () ((_ a ...) '(under a))))
    );
    const result = vm.eval("(under 1 2 3)");
    try std.testing.expectError(error.CompileError, result);
}

test "syntax-rules: quoted depth 2->1 under-use is an error (#682)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax lower
        \\  (syntax-rules () ((_ ((x ...) ...)) '(x ...))))
    );
    const result = vm.eval("(lower ((1 2) (3 4)))");
    try std.testing.expectError(error.CompileError, result);
}

test "syntax-rules: correct-depth uses are untouched by the #682 checks (control)" {
    // The same shapes at their own depth must keep expanding exactly right:
    // nested ellipsis at depth 2, consecutive-ellipsis flattening, and SRFI
    // 149's legitimate excess (depth-1 sibling replicated innermost under a
    // depth-2 driver).
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax nested (syntax-rules ()
        \\    ((_ ((a ...) ...) (b ...)) '(((a b) ...) ...))))
        \\  (equal? (nested ((1 2) (3 4)) (10 20))
        \\          '(((1 10) (2 10)) ((3 20) (4 20)))))
    );
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax flatten (syntax-rules ()
        \\    ((_ (a ...) ...) (list a ... ...))))
        \\  (equal? (flatten (1 2) (3 4)) '(1 2 3 4)))
    );
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax ragged (syntax-rules ()
        \\    ((_ (a ...) ((b ...) ...)) '(((a b) ...) ...))))
        \\  (equal? (ragged (x y) ((1 2 3) (4)))
        \\          '(((x 1) (x 2) (x 3)) ((y 4)))))
    );
}

// Issue #2082: the R7RS 4.3.2 <pattern> grammar admits at most one
// <ellipsis> per list or vector pattern. Accepting a second one previously
// split the input arbitrarily -- the surplus ellipsis tokens were counted as
// fixed tail elements by the matcher's length arithmetic. Now rejected at
// define-syntax time (compiler_define_syntax.zig's validPatternGrammar).

test "syntax-rules: two ellipses in one list pattern is a syntax error (#2082)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval(
        \\(define-syntax two-ell
        \\  (syntax-rules ()
        \\    ((_ a ... b ...) (list (list a ...) (list b ...)))))
    );
    try std.testing.expectError(error.CompileError, result);
}

test "syntax-rules: two ellipses in one vector pattern is a syntax error (#2082)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval(
        \\(define-syntax two-ell-vec
        \\  (syntax-rules ()
        \\    ((_ #(a ... b ...)) (list (list a ...) (list b ...)))))
    );
    try std.testing.expectError(error.CompileError, result);
}

test "syntax-rules: two ellipses in a vector dotted tail is a syntax error (#2082)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The dotted tail of a list pattern may itself be a vector pattern
    // ((_ . #(...)) is a legal datum the matcher recurses into); the
    // grammar check must validate it like any other vector pattern.
    const result = vm.eval(
        \\(define-syntax two-ell-dot
        \\  (syntax-rules ()
        \\    ((_ . #(a ... b ...)) (list (list a ...) (list b ...)))))
    );
    try std.testing.expectError(error.CompileError, result);
}

test "syntax-rules: ellipsis-named literals and legal tail shapes survive #2082 (control)" {
    // The ellipsis identifier listed in <literals> is an ordinary pattern
    // element, so two of them are just fixed elements. And every legal
    // SRFI 46 tail shape (fixed tail, dotted tail, nested) is still
    // accepted.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax dots-lit (syntax-rules ... (...)
        \\    ((_ a ... b) (list a b))))
        \\  (equal? (dots-lit 1 ... 2) '(1 2)))
    );
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax tail (syntax-rules ()
        \\    ((_ a b ... y z) (list a (list b ...) y z))))
        \\  (equal? (tail 1 2 3 4 5) '(1 (2 3) 4 5)))
    );
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax dot-tail (syntax-rules ()
        \\    ((_ a ... z . r) (list (list a ...) z 'r))))
        \\  (equal? (dot-tail 1 2 3) '((1 2) 3 ())))
    );
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax nested (syntax-rules ()
        \\    ((_ (a ... z) ...) (list (list (list a ...) z) ...))))
        \\  (equal? (nested (1 2 3) (4 5)) '(((1 2) 3) ((4) 5))))
    );
}

test "syntax-rules: SRFI 149 excess with empty/unequal drivers zips, not errors (#682)" {
    // A depth-1 variable used at a depth-2 template position is zipped
    // against the depth-2 driver (SRFI 149 rule 2, chibi reference impl):
    // the outer run repeats min(counts) times. Before the count check
    // became depth-aware, an empty or shorter driver raised
    // EllipsisCountMismatch on legal input, and a binding that matched
    // ZERO repetitions kept its placeholder depth 1, so the driver never
    // qualified and EllipsisNoPatternVariable fired instead.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax ragged (syntax-rules ()
        \\    ((_ (a ...) ((b ...) ...)) '(((a b) ...) ...))))
        \\  (and (equal? (ragged (x y) ()) '())
        \\       (equal? (ragged () ()) '())
        \\       (equal? (ragged (x y z) ((1 2) (3))) '(((x 1) (x 2)) ((y 3))))
        \\       (equal? (ragged (x y) ((1 2) (3) (4))) '(((x 1) (x 2)) ((y 3))))
        \\       (equal? (ragged (x y) ((1 2 3) (4))) '(((x 1) (x 2) (x 3)) ((y 4))))))
    );
}

test "syntax-rules: same-depth count mismatch still errors (#78 control)" {
    // The depth-aware count rule must NOT relax the R7RS 4.3.2
    // requirement that pattern variables matched at the same depth and
    // used under the same ellipsis have equal counts. This is the
    // kaappi#78 shape (previously read uninitialized memory).
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-syntax zip (syntax-rules ()
        \\  ((_ (a ...) (b ...)) '((a b) ...))))
    );
    const result = vm.eval("(zip (1 2 3) (4 5))");
    try std.testing.expectError(error.CompileError, result);
}
