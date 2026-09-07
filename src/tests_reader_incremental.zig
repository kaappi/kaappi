//! Incomplete-input mode of the reader (kaappi#1893/#1920/#1940/#1945).
//!
//! The incremental `read` path (primitives_io.readDatumFn) parses a growing
//! buffer chunk by chunk and refills on exactly `UnexpectedEof`. The
//! invariant that makes it sound, and that these tests pin at the reader
//! level, is:
//!
//!   with `incomplete_input = true`, EVERY proper byte-prefix of a datum's
//!   text parses to `UnexpectedEof` — never to a different error (which the
//!   loop treats as final: #1893/#1920/#1945) and never to a successful
//!   prefix datum (which the loop commits, silently splitting the token:
//!   #1940).
//!
//! The prefix sweep below runs that property over one representative source
//! per token class. The end-to-end fd-port behavior (real 4096-byte chunk
//! boundaries, stash, the string-port oracle) is covered by
//! tests/scheme/compliance/reader-port-refill-gaps.scm.

const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");
const printer = @import("printer.zig");
const th = @import("testing_helpers.zig");
const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;

fn parseOne(gc: *memory.GC, source: []const u8, incomplete: bool) ReadError!?types.Value {
    var r = Reader.init(gc, source);
    r.incomplete_input = incomplete;
    defer r.deinit();
    return r.readDatumOrEof();
}

/// Every proper byte-prefix of `src`, parsed in incomplete-input mode, must
/// yield UnexpectedEof (truncated: refill and re-parse) or null (only
/// complete trivia so far — a finished comment or directive; discarding is
/// safe because no datum text has begun). What the incremental loop can
/// never recover from is the other two outcomes: a successful datum commits
/// a silently split token (#1940), and any other error is treated as final
/// (#1893/#1920/#1945). Then `src` followed by a newline must parse.
fn expectPrefixesIncomplete(src: []const u8) !void {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    var k: usize = 1;
    while (k < src.len) : (k += 1) {
        const result = parseOne(&gc, src[0..k], true);
        if (result) |maybe_datum| {
            if (maybe_datum != null) {
                std.debug.print("prefix {d} of \"{s}\" finalized a datum\n", .{ k, src });
                return error.TestUnexpectedResult;
            }
        } else |err| {
            if (err != ReadError.UnexpectedEof) {
                std.debug.print("prefix {d} of \"{s}\" reported {s}\n", .{ k, src, @errorName(err) });
                return error.TestUnexpectedResult;
            }
        }
    }

    // With its terminating delimiter present the datum must parse even in
    // incomplete mode — otherwise the incremental loop could never return it.
    const with_delim = try std.mem.concat(testing.allocator, u8, &.{ src, "\n" });
    defer testing.allocator.free(with_delim);
    const parsed = parseOne(&gc, with_delim, true) catch |e| {
        std.debug.print("\"{s}\" + newline failed to parse in incomplete mode\n", .{src});
        return e;
    };
    try testing.expect(parsed != null);
}

test "incomplete mode: every proper prefix of every token class is UnexpectedEof" {
    // One representative per scanner path. Each entry is a single datum.
    const catalog = [_][]const u8{
        // strings (#1893) — plain, \n escape, \x escape, UTF-8 content
        "\"zzzz zzzz\"",
        "\"aa\\nbb\"",
        "\"aa\\x41;bb\"",
        "\"aaλbb\"",
        // raw string, byte string, quoted symbol with escape (#1940 raisers)
        "#\"Q\"raw \" body\"Q\"",
        "#u8\"ab\\x41;cd\"",
        "|q s\\x41;m|",
        // silent splitters (#1940)
        "zzzzzz",
        "123456",
        "12.5e3",
        "1/24",
        "1+2i",
        "#true",
        "#false",
        "#\\space",
        "#\\x41",
        "#\\a",
        "#d1234",
        "#xFF/3",
        "#e#x10",
        "#x1.8p3",
        // #i, not #e: #e+inf.0 is InvalidNumber since #1911 (no exact
        // representation — string->number parity), so #i is the valid
        // representative of the prefixed inf/nan scanner path.
        "#i+inf.0",
        "+inf.0",
        "...",
        ".5",
        "#u8(1 2)",
        // SRFI 4 homogeneous-vector literals (#2548): the same closed
        // self-delimiting class as #u8(, and the prefix cut points the
        // 'u'/'s'/'f'/'c' dispatch must refill on, not finalize ("#s1" is
        // not a #s1 datum — it is the beginning of #s16( ... )).
        "#s16(1 -2)",
        "#f32(1.5)",
        "#u64(1 2)",
        "#c64(1.5+0.5i)",
        // multi-byte UTF-8 codepoints (#1945): 2-, 3-, 4-byte, bare and
        // inside a container
        "λλ",
        "ああ",
        "𝜆𝜆",
        "(qqλqq)",
        "(qqあqq)",
        "(qq𝜆qq)",
        "#\\λ",
        // dotted pairs (#1920): truncation after the tail datum and with
        // the dot as the last byte are interior prefixes here
        "(a . b)",
        "(#t . 0)",
        // structure, comments, labels, directives
        "(aa bb cc)",
        "#(1 2 3)",
        "'(a b)",
        "; c\n(a)",
        "#|blk|# (x)",
        "#;(skip) (x)",
        "#0=(a #0#)",
        "#!fold-case ABC",
    };
    for (catalog) |src| {
        try expectPrefixesIncomplete(src);
    }
}

test "incomplete mode: bare tokens at end-of-slice do not finalize" {
    // The full text of an extendable token is itself "a prefix of something
    // longer" while more input may follow; only a delimiter finalizes it.
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const extendable = [_][]const u8{ "zzz", "123", "#true", "#\\space", "1+2i", "+inf.0" };
    for (extendable) |src| {
        try testing.expectError(ReadError.UnexpectedEof, parseOne(&gc, src, true));
    }
}

test "incomplete mode: self-delimiting closers finalize at end-of-slice" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const closed = [_][]const u8{ "(a b)", "\"zz\"", "#u8(1)", "#(x)", "|qq|", "(a . b)", "#\"D\"r\"D\"", "#u8\"a\"", "#s16(1)", "#f32(1.5)" };
    for (closed) |src| {
        const parsed = try parseOne(&gc, src, true);
        try testing.expect(parsed != null);
    }
}

test "incomplete mode: truncated line comment is UnexpectedEof, complete one is clean EOF" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    // No newline yet: the comment may continue in the next chunk — resuming
    // mid-comment turns its tail into program data (#1940's worst case).
    try testing.expectError(ReadError.UnexpectedEof, parseOne(&gc, "; secret", true));
    // Newline present: the comment is complete trivia.
    try testing.expectEqual(@as(?types.Value, null), try parseOne(&gc, "; done\n", true));
}

test "whole-input mode keeps the precise final verdicts" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    // Truncations at real EOF are genuine errors again, with their kinds.
    try testing.expectError(ReadError.UnterminatedString, parseOne(&gc, "\"abc", false));
    try testing.expectError(ReadError.UnterminatedString, parseOne(&gc, "#\"Q\"abc", false));
    try testing.expectError(ReadError.DotNotInList, parseOne(&gc, "(a .", false));
    // #1920: input exhausted where `)` belongs is UnexpectedEof in every
    // mode — the incomplete-datum case, not a wrong character.
    try testing.expectError(ReadError.UnexpectedEof, parseOne(&gc, "(a . b", false));
    try testing.expectError(ReadError.UnexpectedEof, parseOne(&gc, "(a b", false));
    // Bare tokens genuinely end at EOF.
    const sym = (try parseOne(&gc, "zzz", false)).?;
    const sym_str = try printer.valueToString(testing.allocator, sym, .write);
    defer testing.allocator.free(sym_str);
    try testing.expectEqualStrings("zzz", sym_str);
}

test "homogeneous-vector prefixes: cut runs refill, complete verdicts (#2548)" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    // A run cut at end-of-slice may still complete into a #TAG( prefix once
    // the next chunk arrives — "#s1" is the beginning of #s16( ... ), never
    // a finished "#s1" datum.
    const cut_prefixes = [_][]const u8{ "#s", "#s1", "#s16", "#s8", "#u", "#u1", "#u16", "#f3", "#f32", "#c", "#c6", "#c128" };
    for (cut_prefixes) |src| {
        try testing.expectError(ReadError.UnexpectedEof, parseOne(&gc, src, true));
        try testing.expectError(ReadError.UnexpectedChar, parseOne(&gc, src, false));
    }
    // "#f"/"#false" keep the boolean verdicts: cut runs refill (#1940), a
    // true end-of-input is the boolean.
    for ([_][]const u8{ "#f", "#false" }) |src| {
        try testing.expectError(ReadError.UnexpectedEof, parseOne(&gc, src, true));
        try testing.expect((try parseOne(&gc, src, false)) != null);
    }
    // A complete prefix before '(' is a closed literal even in incomplete
    // mode; a mismatched prefix ('u9') is a final error in both modes.
    try testing.expect((try parseOne(&gc, "#s16(1)", true)) != null);
    try testing.expectError(ReadError.UnexpectedChar, parseOne(&gc, "#u9(1)", true));
    try testing.expectError(ReadError.UnexpectedChar, parseOne(&gc, "#u9(1)", false));
    // "#u8\"...\"" (SRF 207) is untouched, and its cut before the quote
    // still refills.
    try testing.expect((try parseOne(&gc, "#u8\"ab\"", true)) != null);
}

test "SRFI 4 homogeneous-vector literals: kinds, immutability, round-trip (#2548)" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // Reads to a NumericVector of the right kind, elements stored exactly,
    // including full integer syntax in an element (#xff).
    const v = (try parseOne(&gc, "#s16(1 -2 #xff)", false)) orelse return error.TestUnexpectedResult;
    try testing.expect(types.isNumericVector(v));
    const nv = types.toObject(v).as(types.NumericVector);
    try testing.expectEqual(types.NumericElementKind.s16, nv.kind);
    try testing.expectEqual(@as(usize, 6), nv.data.len);
    var expect: [6]u8 = undefined;
    const native_endian = @import("builtin").cpu.arch.endian();
    std.mem.writeInt(i16, expect[0..2], 1, native_endian);
    std.mem.writeInt(i16, expect[2..4], -2, native_endian);
    std.mem.writeInt(i16, expect[4..6], 255, native_endian);
    try testing.expectEqualSlices(u8, &expect, nv.data);

    // A literal is immutable, like #u8( and #(... literals.
    try testing.expect(types.toObject(v).flags.immutable);

    // Range and type failures are read errors with kinds. An integer-vector
    // element that is not an exact integer (a symbol, or 1.5) is InvalidNumber;
    // a float/complex-vector element that is not a number at all is the
    // tokenizer-level UnexpectedChar.
    try testing.expectError(ReadError.InvalidNumber, parseOne(&gc, "#u16(70000)", false));
    try testing.expectError(ReadError.InvalidNumber, parseOne(&gc, "#u8(300)", false));
    try testing.expectError(ReadError.InvalidNumber, parseOne(&gc, "#s16(sym)", false));
    try testing.expectError(ReadError.UnexpectedChar, parseOne(&gc, "#f32(sym)", false));

    // write produces the read-identical literal (SRFI 4's external
    // representation) — the native tier's constant embedding relies on it.
    const s = try printer.valueToString(testing.allocator, v, .write);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("#s16(1 -2 255)", s);
    const back = (try parseOne(&gc, s, false)) orelse return error.TestUnexpectedResult;
    try testing.expect(types.isNumericVector(back));
    try testing.expectEqualSlices(u8, nv.data, types.toObject(back).as(types.NumericVector).data);
}

test "nested homogeneous-vector literals pay the depth gate (#2548 review)" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // Scalar elements are depth-neutral, so a literal under the LAST plain
    // nesting that still reads (1023 parens, the same boundary the plain-atom
    // controls in tests/scheme/compliance/printer-gaps.scm sit at) reads
    // fine — a real seam guard, since it fails if elements ever start paying
    // the per-datum depth increment.
    var leaf: std.ArrayList(u8) = .empty;
    defer leaf.deinit(testing.allocator);
    const plain = Reader.MAX_NESTING_DEPTH - 1; // 1023: the last depth that reads
    for (0..plain) |_| leaf.append(testing.allocator, '(') catch return error.OutOfMemory;
    leaf.appendSlice(testing.allocator, "#s16(1 2)") catch return error.OutOfMemory;
    for (0..plain) |_| leaf.append(testing.allocator, ')') catch return error.OutOfMemory;
    try testing.expect((try parseOne(&gc, leaf.items, false)) != null);
    // One more paren on each side crosses the seam: the literal token now
    // sits at MAX_NESTING_DEPTH and pays the gate, so the same shape reads
    // as NestingTooDeep.
    leaf.insert(testing.allocator, 0, '(') catch return error.OutOfMemory;
    leaf.append(testing.allocator, ')') catch return error.OutOfMemory;
    try testing.expectError(ReadError.NestingTooDeep, parseOne(&gc, leaf.items, false));

    var nested: std.ArrayList(u8) = .empty;
    defer nested.deinit(testing.allocator);
    const depth = Reader.MAX_NESTING_DEPTH + 50;
    for (0..depth) |_| nested.appendSlice(testing.allocator, "#s8(") catch return error.OutOfMemory;
    nested.append(testing.allocator, '1') catch return error.OutOfMemory;
    for (0..depth) |_| nested.append(testing.allocator, ')') catch return error.OutOfMemory;
    try testing.expectError(ReadError.NestingTooDeep, parseOne(&gc, nested.items, false));
}

test "readDatumOrEof: trailing trivia is clean EOF, not a read error" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    // hasMore()+readDatum reported UnexpectedEof for a trailing #! directive
    // (hasMore cannot see directives), which `read` turned into a spurious
    // read error instead of the EOF object.
    try testing.expectEqual(@as(?types.Value, null), try parseOne(&gc, "#!fold-case", false));
    try testing.expectEqual(@as(?types.Value, null), try parseOne(&gc, "; only a comment", false));
    try testing.expectEqual(@as(?types.Value, null), try parseOne(&gc, "#|block|#", false));
    try testing.expectEqual(@as(?types.Value, null), try parseOne(&gc, "   ", false));
    try testing.expectEqual(@as(?types.Value, null), try parseOne(&gc, "", false));
}

test "read procedure: trailing directive yields the EOF object" {
    try th.expectEvalTrue("(eof-object? (read (open-input-string \"#!fold-case\")))");
    // A directive before a datum still applies to it.
    try th.expectEvalTrue("(eq? 'abc (read (open-input-string \"#!fold-case ABC\")))");
}

test "read procedure: error message names what failed (#1920)" {
    try th.expectEvalTrue(
        \\(equal? "read error: unterminated string literal"
        \\        (guard (e (#t (error-object-message e)))
        \\          (read (open-input-string "\"abc"))))
    );
    try th.expectEvalTrue(
        \\(equal? "read error: unexpected end of input"
        \\        (guard (e (#t (error-object-message e)))
        \\          (read (open-input-string "(a . b"))))
    );
}
