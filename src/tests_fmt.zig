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
    try testing.expect(fmt.verifyRoundTrip(&gc, src, formatted) == .ok);
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

test "verifyRoundTrip separates a user read error from a real mismatch" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // A user syntax error in the original: the CST lexer tolerates `#\qqq` but
    // the real reader rejects it, so it is the original_unreadable case — not a
    // formatter mismatch (kaappi#2080).
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const bad = "(display #\\qqq)\n";
    const formatted = try fmt.formatSource(arena.allocator(), bad);
    switch (fmt.verifyRoundTrip(&gc, bad, formatted)) {
        .original_unreadable => |f| try testing.expectEqual(@as(u32, 1), f.line),
        else => return error.ExpectedOriginalUnreadable,
    }

    // Two texts that both read but to different datums is a real mismatch.
    switch (fmt.verifyRoundTrip(&gc, "(a b)", "(a c)")) {
        .mismatch => {},
        else => return error.ExpectedMismatch,
    }
}

test "original_unreadable reports the line after a lone CR" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The `;` comment ends at the lone CR (kaappi#2079); the invalid `#\qqq` is
    // on line 2, and `getLineCol` must count that CR as a line ending so the
    // reported position says line 2, not line 1.
    const bad = "; note\r#\\qqq\n";
    const formatted = try fmt.formatSource(arena.allocator(), bad);
    switch (fmt.verifyRoundTrip(&gc, bad, formatted)) {
        .original_unreadable => |f| try testing.expectEqual(@as(u32, 2), f.line),
        else => return error.ExpectedOriginalUnreadable,
    }
}

test "columnCount never lets a bad lead byte swallow the next byte" {
    // 0xC2 is a two-byte lead, but 'A' (0x41) is not a continuation byte: the
    // malformed sequence must count as two columns, not one. A truncated
    // multi-byte sequence at end-of-slice counts its lead byte alone, and valid
    // scalars still count one column each (kaappi#2149 review).
    try testing.expectEqual(@as(usize, 2), fmt_print.columnCount(&.{ 0xC2, 'A' }));
    try testing.expectEqual(@as(usize, 1), fmt_print.columnCount(&.{0xC2}));
    try testing.expectEqual(@as(usize, 1), fmt_print.columnCount("λ"));
    try testing.expectEqual(@as(usize, 3), fmt_print.columnCount("aλb"));
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
        if (fmt.verifyRoundTrip(&gc, program, once) != .ok) {
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

// kaappi#2141: every reader-prefix kind recurses through parsePrefixTarget,
// which once bypassed the parseList-only max_nesting check and overflowed the
// native stack (exit 134 at ~158000 on an 8 MB stack). The chain must instead
// hit the same NestingTooDeep the reader enforces at 1025.
test "deep prefix chain of every kind is a format error, not a crash" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const prefixes = [_][]const u8{ "'", "`", ",", ",@", "#;", "#1=" };
    for (prefixes) |pfx| {
        var src: std.ArrayList(u8) = .empty;
        defer src.deinit(testing.allocator);
        for (0..2000) |_| try src.appendSlice(testing.allocator, pfx);
        try src.append(testing.allocator, 'x');
        try testing.expectError(fmt.ParseError.NestingTooDeep, fmt.formatSource(arena.allocator(), src.items));
    }
}

// Prefixes and lists draw from one shared depth budget (the reader counts both
// toward its single 1025 cap), so a chain that mixes them must be rejected at
// the same total depth — not once per kind.
test "prefix and list nesting share one depth budget" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var too_deep: std.ArrayList(u8) = .empty;
    defer too_deep.deinit(testing.allocator);
    try too_deep.appendNTimes(testing.allocator, '\'', 600);
    try too_deep.appendNTimes(testing.allocator, '(', 600);
    try too_deep.append(testing.allocator, 'x');
    try too_deep.appendNTimes(testing.allocator, ')', 600);
    try testing.expectError(fmt.ParseError.NestingTooDeep, fmt.formatSource(arena.allocator(), too_deep.items));

    // 500 + 500 = 1000 stays under the cap and formats without recursion trouble.
    var legal: std.ArrayList(u8) = .empty;
    defer legal.deinit(testing.allocator);
    try legal.appendNTimes(testing.allocator, '\'', 500);
    try legal.appendNTimes(testing.allocator, '(', 500);
    try legal.append(testing.allocator, 'x');
    try legal.appendNTimes(testing.allocator, ')', 500);
    const want = try std.mem.concat(testing.allocator, u8, &.{ legal.items, "\n" });
    defer testing.allocator.free(want);
    try expectFormat(legal.items, want);
}

test "a dangling datum comment is a distinct error from a dangling quote" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // `#;` at EOF, at a close paren, or as a file's only content.
    try testing.expectError(fmt.ParseError.DanglingDatumComment, fmt.formatSource(arena.allocator(), "#;"));
    try testing.expectError(fmt.ParseError.DanglingDatumComment, fmt.formatSource(arena.allocator(), "#; \n"));
    try testing.expectError(fmt.ParseError.DanglingDatumComment, fmt.formatSource(arena.allocator(), "(#;)"));
    // The prefix wording is untouched for actual prefixes.
    try testing.expectError(fmt.ParseError.DanglingPrefix, fmt.formatSource(arena.allocator(), "'"));
    try testing.expectError(fmt.ParseError.DanglingPrefix, fmt.formatSource(arena.allocator(), "(`)"));
    try testing.expectError(fmt.ParseError.DanglingPrefix, fmt.formatSource(arena.allocator(), ",@"));
}

test "empty input yields empty output" {
    try expectFormat("", "");
    try expectFormat("   \n\n  ", "");
}

// ── SRFI 267 raw strings (#1652 corpus fallout) ──────────────────────────────
// The CST lexer must carve `#"X" content "X"` exactly like the real reader
// (reader_tokens.readRawString), or the round-trip guard refuses the file —
// srfi267.scm surfaced this the first time the corpus actually reached it.

test "raw string is one verbatim lexeme" {
    try expectFormat("(display   #\"\"no escapes \\n here\"\")", "(display #\"\"no escapes \\n here\"\")\n");
    try expectFormat("(a  #\"X\"quotes \" inside\"X\"  b)", "(a #\"X\"quotes \" inside\"X\" b)\n");
}

test "multiline raw string never inlines and stays byte-identical" {
    const src = "(define text #\"\"line one\nline two\"\")\n";
    try expectIdempotent(src);
    try expectRoundTrips(src);
}

test "raw strings round-trip through the real reader" {
    try expectRoundTrips("(list #\"\"plain\"\" #\"q\"with \" quote\"q\")");
}

test "unterminated raw string is a format error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(fmt.ParseError.UnterminatedString, fmt.formatSource(arena.allocator(), "(a #\"X\"never closed"));
}

// ── Line endings (kaappi#1897) ───────────────────────────────────────────────
// Policy: LF, like `zig fmt`. Every line break `fmt` emits is a bare `\n`;
// bytes inside a datum are never touched. The round-trip guard is blind to this
// entirely — `\r` is whitespace to the reader, so a whole-file CRLF→LF rewrite
// is `equal?`-invariant — which is exactly why it needs its own tests.

/// Assert `src` holds no CR outside a datum after formatting. Datum-bearing
/// lexemes (strings, raw strings, `|symbols|`, `#\return`) are exempt, so this
/// is only applied to sources that contain none.
fn expectNoCr(src: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try fmtInto(arena.allocator(), src);
    if (std.mem.indexOfScalar(u8, got, '\r')) |at| {
        std.debug.print("stray CR at byte {d} of:\n{s}\n", .{ at, got });
        return error.StrayCarriageReturn;
    }
}

test "CRLF and lone CR both format to LF" {
    try expectFormat("(define x 1)\r\n(define y 2)\r\n", "(define x 1)\n(define y 2)\n");
    try expectFormat("(define x 1)\r(define y 2)\r", "(define x 1)\n(define y 2)\n");
    // Mixed within one file: no dominant-ending heuristic, every ending is LF.
    try expectFormat("(a)\r\n(b)\n(c)\r", "(a)\n(b)\n(c)\n");
}

test "line endings never affect the output" {
    // The policy in one property: a file and its CRLF twin format identically.
    // This is what a preserve policy would have made false.
    const programs = [_][]const u8{
        "(define (f x)\n  (+ x 1))\n",
        ";; header\n(define x 1) ; trailing\n\n(define y 2)\n",
        "(begin\n  (a)\n\n  (b))\n",
        "#| block\n   comment |#\n(define x 1)\n",
        "(let loop ((i 0))\n  (when (< i 10) (loop (+ i 1))))\n",
    };
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for (programs) |lf| {
        _ = arena.reset(.retain_capacity);
        const a = arena.allocator();

        const crlf = try std.mem.replaceOwned(u8, a, lf, "\n", "\r\n");
        try testing.expectEqualStrings(try fmt.formatSource(a, lf), try fmt.formatSource(a, crlf));

        // The CR-only twin is a twin for every program now that a lone CR ends
        // a `;` comment too (kaappi#2079).
        const cr = try std.mem.replaceOwned(u8, a, lf, "\n", "\r");
        try testing.expectEqualStrings(try fmt.formatSource(a, lf), try fmt.formatSource(a, cr));
    }
}

test "a CR in a datum is program data and survives byte-for-byte" {
    // Changing any of these would change the program, so they are exempt from
    // the LF policy under *any* policy — string, raw string, piped symbol, and
    // the raw spelling of the return character.
    try expectFormat("(define s \"a\rb\")\n", "(define s \"a\rb\")\n");
    try expectFormat("(define c #\\\r)\n", "(define c #\\\r)\n");
    try expectFormat("(define s #\"X\"a\rb\"X\")\n", "(define s #\"X\"a\rb\"X\")\n");
    try expectFormat("(define |a\rb| 1)\n", "(define |a\rb| 1)\n");
    // A CRLF inside a string keeps *both* bytes; the embedded newline is what
    // stops the enclosing form from inlining, so the layout breaks around it.
    try expectFormat("(define s \"a\r\nb\")\n", "(define s\n  \"a\r\nb\")\n");
    try expectRoundTrips("(define s \"a\r\nb\")\n");
    try expectIdempotent("(define s \"a\r\nb\")\n");
}

test "comment line endings normalise; comment interiors are handled per kind" {
    // A line comment runs to its line ending — `\n` or a lone `\r` (kaappi#2079)
    // — so the CR of a CRLF ends it and never reaches the comment text; the LF
    // is ordinary whitespace. Before kaappi#1897 this was the one place fmt
    // emitted a CR of its own.
    try expectFormat("(define x 1) ; note\r\n(define y 2)\r\n", "(define x 1) ; note\n(define y 2)\n");
    try expectFormat(";; header\r\n(define x 1)\r\n", ";; header\n(define x 1)\n");
    try expectNoCr("(define x 1) ; note\r\n;; own line\r\n(define y 2)\r\n");

    // A block comment ends at `|#`, so its interior line endings normalise too:
    // its bytes reach no datum, and leaving them would make the output mixed.
    try expectFormat("#| a\r\nb |#\n(define x 1)\n", "#| a\nb |#\n(define x 1)\n");
    try expectFormat("#| a\rb |#\n(define x 1)\n", "#| a\nb |#\n(define x 1)\n");
    try expectNoCr("#| a\r\nb |#\r\n(define x 1)\r\n");
}

test "a lone CR ends a line comment — fmt mirrors the reader" {
    // R7RS 7.1.1 makes a lone ⟨return⟩ a line ending, and the reader now ends a
    // `;` comment at one (kaappi#2079). fmt's lexer carves the same lexeme, so
    // the comment stops at the CR and the following datum is not swallowed.
    try expectFormat("(define x 1) ; note\r(define y 2)\r", "(define x 1) ; note\n(define y 2)\n");
    try expectRoundTrips("(define x 1) ; note\r(define y 2)\r");
    try expectIdempotent("(define x 1) ; note\r(define y 2)\r");
}

test "blank-line grouping survives every line-ending convention" {
    try expectFormat("(a)\r\n\r\n(b)\r\n", "(a)\n\n(b)\n");
    // Lone CR counts as a line ending too, so `\r\r` is a blank line. Counting
    // only `\n` would flatten a CR-only file to one line and drop the grouping.
    try expectFormat("(a)\r\r(b)\r", "(a)\n\n(b)\n");
}

test "the trailing newline is added as LF, whatever the file used" {
    try expectFormat("(define x 1)", "(define x 1)\n");
    try expectFormat("(define x 1)\r\n(define y 2)", "(define x 1)\n(define y 2)\n");
    try expectFormat("\r\n", "");
}

test "idempotent and round-tripping across line-ending conventions" {
    const cases = [_][]const u8{
        "(define x 1)\r\n(define y 2)\r\n",
        "(define x 1)\r(define y 2)\r",
        "(a)\r\n(b)\n(c)\r",
        "#| a\r\nb |#\r\n(define x 1)\r\n",
        "(define s \"a\rb\")\r\n",
        "(define s #\"X\"a\r\nb\"X\")\r\n",
        ";; head\r\n(define x 1) ; tail\r\n\r\n(define y 2)\r\n",
    };
    for (cases) |c| {
        try expectIdempotent(c);
        try expectRoundTrips(c);
    }
}
