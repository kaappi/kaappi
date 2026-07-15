//! Tests for `kaappi fmt` (kaappi#1518): exact-output cases, comment and
//! blank-line preservation, the idempotence property (`fmt(fmt(x)) == fmt(x)`)
//! over generated programs, and the semantics-preserving round-trip guarantee.

const std = @import("std");
const testing = std.testing;
const fmt = @import("fmt.zig");
const fmt_print = @import("fmt_print.zig");
const memory = @import("memory.zig");
const fuzz_gen = @import("fuzz_gen.zig");

/// Format `src` into an arena-backed string. Caller frees via the arena.
fn fmtInto(arena: std.mem.Allocator, src: []const u8) ![]u8 {
    return fmt.formatSource(arena, src);
}

/// Assert `src` formats to exactly `want`.
fn expectFormat(src: []const u8, want: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try fmtInto(arena.allocator(), src);
    try testing.expectEqualStrings(want, got);
}

/// Assert formatting is idempotent for `src`: the first pass is a fixed point.
fn expectIdempotent(src: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const once = try fmtInto(arena.allocator(), src);
    const twice = try fmtInto(arena.allocator(), once);
    try testing.expectEqualStrings(once, twice);
}

/// Assert formatting preserves the datums a reader sees.
fn expectRoundTrips(src: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const formatted = try fmtInto(arena.allocator(), src);

    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    try testing.expect(fmt.verifyRoundTrip(&gc, src, formatted));
}

// ── Spacing and gathering ─────────────────────────────────────────────────────

test "collapses runs of whitespace to single spaces" {
    try expectFormat("(+   1\t\t2    3)", "(+ 1 2 3)\n");
}

test "gathers trailing close parens" {
    try expectFormat("(a (b (c)\n)\n)", "(a (b (c)))\n");
}

test "atoms are preserved verbatim" {
    try expectFormat("(list 1.5e10 #xFF #\\newline \"a b\" 'x)", "(list 1.5e10 #xFF #\\newline \"a b\" 'x)\n");
}

test "quote and unquote glue to their datum" {
    try expectFormat("( quote   x )", "(quote x)\n");
    try expectFormat("`(a ,b ,@c)", "`(a ,b ,@c)\n");
}

test "empty list and single trailing newline" {
    try expectFormat("()", "()\n");
    try expectFormat("(a)\n\n\n", "(a)\n");
}

test "vector literals keep their prefix" {
    try expectFormat("#(1 2 3)", "#(1 2 3)\n");
    try expectFormat("#u8( 0 255 )", "#u8(0 255)\n");
}

// ── Special-form indentation ──────────────────────────────────────────────────

test "define body breaks to two-space indent" {
    const src = "(define (f x) (aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd eeeeeeeeee ffffffffff))";
    try expectFormat(src,
        \\(define (f x)
        \\  (aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd eeeeeeeeee ffffffffff))
        \\
    );
}

test "when keeps test on head line, body indented two" {
    const src = "(when some-condition (step-one arg) (step-two arg) (step-three arg) (step-four arg))";
    try expectFormat(src,
        \\(when some-condition
        \\  (step-one arg)
        \\  (step-two arg)
        \\  (step-three arg)
        \\  (step-four arg))
        \\
    );
}

test "let bindings and body" {
    const src = "(let ((alpha 1) (beta 2) (gamma 3) (delta 4) (epsilon 5)) (+ alpha beta gamma delta epsilon))";
    try expectFormat(src,
        \\(let ((alpha 1) (beta 2) (gamma 3) (delta 4) (epsilon 5))
        \\  (+ alpha beta gamma delta epsilon))
        \\
    );
}

test "named let gets an extra distinguished form" {
    const src = "(let loop ((i 0) (acc (list))) (if (= i 100000) acc (loop (+ i 1) (cons i acc))))";
    try expectFormat(src,
        \\(let loop ((i 0) (acc (list)))
        \\  (if (= i 100000) acc (loop (+ i 1) (cons i acc))))
        \\
    );
}

test "call style aligns arguments under the first" {
    const src = "(some-procedure first-argument second-argument third-argument fourth-argument fifth-arg)";
    try expectFormat(src,
        \\(some-procedure first-argument
        \\                second-argument
        \\                third-argument
        \\                fourth-argument
        \\                fifth-arg)
        \\
    );
}

test "cond clauses align under the first clause" {
    const src = "(cond ((= x 1) 'one) ((= x 2) 'two) ((= x 3) 'three) ((= x 4) 'four) (else 'many))";
    try expectFormat(src,
        \\(cond ((= x 1) 'one)
        \\      ((= x 2) 'two)
        \\      ((= x 3) 'three)
        \\      ((= x 4) 'four)
        \\      (else 'many))
        \\
    );
}

// ── Comments ──────────────────────────────────────────────────────────────────

test "leading line comment stays on its own line" {
    try expectFormat(";; a header\n(define x 1)", ";; a header\n(define x 1)\n");
}

test "trailing line comment stays on the datum's line" {
    try expectFormat("(define x 1)   ; the answer", "(define x 1) ; the answer\n");
}

test "comment inside a body forces the break and is preserved" {
    const src = "(begin ; start\n (a) ; first\n (b))";
    try expectFormat(src,
        \\(begin ; start
        \\  (a) ; first
        \\  (b))
        \\
    );
}

test "block comment is preserved verbatim inline" {
    try expectFormat("(a #| note |# b)", "(a #| note |# b)\n");
}

test "trailing whitespace inside a line comment is stripped" {
    // Invisible and never part of a datum — the output must carry no trailing
    // spaces. (The literal string below ends the comment with two spaces.)
    try expectFormat(";; note  \n(define x 1)", ";; note\n(define x 1)\n");
}

test "datum comment is preserved and glued" {
    try expectFormat("(a #;(ignored) b)", "(a #;(ignored) b)\n");
}

// ── Blank lines ───────────────────────────────────────────────────────────────

test "single blank line between top-level forms is preserved" {
    try expectFormat("(a)\n\n(b)", "(a)\n\n(b)\n");
}

test "multiple blank lines collapse to one" {
    try expectFormat("(a)\n\n\n\n(b)", "(a)\n\n(b)\n");
}

test "blank line inside a body is preserved" {
    const src = "(define (f)\n  (first-step here)\n\n  (second-step here))";
    try expectFormat(src,
        \\(define (f)
        \\  (first-step here)
        \\
        \\  (second-step here))
        \\
    );
}

test "blank before the first body item is preserved" {
    // Regression: a blank line right after the head must survive, and re-parsing
    // it (now a single blank) must reach the same fixed point — see the
    // idempotence hazard fixed alongside hasBodyBlank.
    try expectFormat("(begin\n\n  (a)\n  (b))",
        \\(begin
        \\
        \\  (a)
        \\  (b))
        \\
    );
    try expectIdempotent("(begin\n\n\n  (a)\n  (b))");
}

test "blank before a distinguished subform collapses and stays idempotent" {
    // The blank sits before the binding list, which rides on the `let` head
    // line — so it is dropped, and the short form collapses to one line. If that
    // drop were paired with a forced break the result would oscillate.
    try expectFormat("(let\n\n  ((x 1))\n  x)", "(let ((x 1)) x)\n");
    try expectIdempotent("(let\n\n  ((x 1))\n  x)");
    try expectIdempotent("(define\n\n  x\n  1)");
}

// ── Idempotence ───────────────────────────────────────────────────────────────

test "idempotent on a spread of forms" {
    const cases = [_][]const u8{
        "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))",
        "(let loop ((i 0)) (when (< i 10) (display i) (loop (+ i 1))))",
        "(cond ((assv x table) => cdr) (else (error \"missing\" x)))",
        "(define-record-type point (make-point x y) point? (x point-x) (y point-y))",
        ";; top comment\n(import (scheme base) (scheme write))\n\n(display \"hi\")",
        "(when a (b) (c) (d) (e) (f) (g) (h) (i) (j) (k) (l) (m) (n) (o) (p) (q) (r))",
        "#(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30)",
    };
    for (cases) |c| try expectIdempotent(c);
}

// ── Round-trip semantics ──────────────────────────────────────────────────────

test "round-trips a spread of forms" {
    const cases = [_][]const u8{
        "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))",
        "'(1 2 . 3)",
        "`(a ,b ,@(c d) #(1 2))",
        "(a #;(dropped) b #| block |# c)",
        "#0=(1 2 . #0#)",
        "(list #\\a #\\space #\\x3bb \"str\\ning\" |weird sym|)",
        "(+ 1/2 3.5 #xFF #b101 +inf.0)",
    };
    for (cases) |c| try expectRoundTrips(c);
}

// ── Generated programs: idempotence + round-trip ──────────────────────────────

test "idempotent and semantics-preserving over generated programs" {
    const gc_stress = @import("build_options").gc_stress;
    const iterations: u64 = if (gc_stress) 40 else 400;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var seed: u64 = 0;
    while (seed < iterations) : (seed += 1) {
        _ = arena.reset(.retain_capacity);
        const a = arena.allocator();

        const program = try fuzz_gen.generateSeeded(seed, a);

        const once = try fmt.formatSource(a, program);
        const twice = try fmt.formatSource(a, once);
        try testing.expectEqualStrings(once, twice);

        var gc = memory.GC.init(testing.allocator);
        defer gc.deinit();
        if (!fmt.verifyRoundTrip(&gc, program, once)) {
            std.debug.print("round-trip drift on seed {d}:\n{s}\n---\n{s}\n", .{ seed, program, once });
            return error.RoundTripDrift;
        }
    }
}

// ── Parser diagnostics ────────────────────────────────────────────────────────

test "unterminated list is a format error, not a crash" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(fmt.ParseError.UnterminatedList, fmt.formatSource(arena.allocator(), "(a b c"));
}

test "unexpected close paren is a format error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(fmt.ParseError.UnexpectedRightParen, fmt.formatSource(arena.allocator(), "a)"));
}

test "empty input yields empty output" {
    try expectFormat("", "");
    try expectFormat("   \n\n  ", "");
}
