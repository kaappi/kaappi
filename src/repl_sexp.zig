//! Structural s-expression editing for the REPL: slurp, barf, raise, rotate.
//! These move a *paren* rather than a character — the edits a Lisp programmer
//! actually wants, and the ones a character-oriented editor makes tedious.
//!
//! Everything here is a pure transform over `(buffer, byte cursor)`, so it is
//! testable without a terminal. `repl.zig` hands the result to isocline, which
//! owns the keys (`vendor/isocline/PATCHES.md`, patch 3).
//!
//! ## Where this came from
//!
//! The commands and their keybindings are bestline's (Justine Tunney's
//! linenoise fork, BSD-2-Clause) — kaappi#2216 filed them after that library
//! was evaluated and rejected as a base for the REPL. **The code is not a
//! port.** Two of the four do not exist there to port: `bestlineEditRaise` is
//! an empty stub, and `bestlineEditRotate` rotates the *kill ring* (emacs
//! yank-pop), not the datums of a form. The two that do exist, barf and slurp,
//! count `(` and `)` runes with a mirror stack and no notion of strings,
//! comments, or character literals — which is exactly the bug class the issue
//! asked the port to avoid, so the scanner below derives its rules from
//! `reader.zig` instead. Attribution is for the design; the implementation is
//! Kaappi's.
//!
//! ## Scope of the scanner
//!
//! `[` and `]` are deliberately *not* delimiters or brackets: Kaappi's reader
//! gives them no meaning (`0]` is KP1002), and `Reader.isDelimiter` is what
//! decides where an atom ends here, so the two cannot drift apart. A form that
//! is still unbalanced has no close paren to move, so every command declines
//! (returns null) rather than guessing.

const std = @import("std");
const Reader = @import("reader.zig").Reader;

/// A half-open byte range `[start, end)` of the buffer.
pub const Span = struct { start: usize, end: usize };

/// Discriminant shared with isocline's `ic_sexp_command_t`; the numbering is
/// the contract between the two (see `isocline.zig`).
pub const Command = enum(c_uint) {
    slurp = 0,
    barf = 1,
    raise = 2,
    rotate = 3,
};

/// A rewritten buffer plus where the cursor lands in it. `text` is owned by
/// the caller.
pub const Edit = struct { text: []u8, pos: usize };

/// Bounds nesting recursion. A REPL buffer is pasted as often as typed, so a
/// pathological `((((…` must decline rather than smash the stack.
const max_depth: u32 = 256;

// --- Lexical scanning ------------------------------------------------------

/// Whitespace, `;` line comments, `#|…|#` block comments (nesting), and
/// `#!fold-case` directives — everything the reader skips *except* `#;`, which
/// needs to scan a datum and so lives in `skipTrivia`.
fn skipAtomicTrivia(src: []const u8, from: usize) usize {
    var i = from;
    while (i < src.len) {
        const c = src[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0b or c == 0x0c) {
            i += 1;
            continue;
        }
        if (c == ';') {
            while (i < src.len and src[i] != '\n') : (i += 1) {}
            continue;
        }
        if (c == '#' and i + 1 < src.len and src[i + 1] == '|') {
            var depth: usize = 1;
            var j = i + 2;
            while (j < src.len and depth > 0) {
                if (src[j] == '#' and j + 1 < src.len and src[j + 1] == '|') {
                    depth += 1;
                    j += 2;
                } else if (src[j] == '|' and j + 1 < src.len and src[j + 1] == '#') {
                    depth -= 1;
                    j += 2;
                } else {
                    j += 1;
                }
            }
            // An unterminated block comment swallows the rest of the buffer,
            // which is what the reader does too.
            if (depth > 0) return src.len;
            i = j;
            continue;
        }
        if (c == '#' and i + 1 < src.len and src[i + 1] == '!') {
            i += 2;
            while (i < src.len and !Reader.isDelimiter(src[i])) : (i += 1) {}
            continue;
        }
        break;
    }
    return i;
}

/// `skipAtomicTrivia` plus `#;` datum comments, which consume the datum that
/// follows them. Mutually recursive with `scanDatum` — `#;(a b)` has to scan a
/// list to know how much to skip.
fn skipTrivia(src: []const u8, from: usize, depth: u32) usize {
    var i = from;
    while (true) {
        i = skipAtomicTrivia(src, i);
        if (i + 1 < src.len and src[i] == '#' and src[i + 1] == ';') {
            if (depth >= max_depth) return i;
            const inner = skipTrivia(src, i + 2, depth + 1);
            const d = scanDatum(src, inner, depth + 1) orelse return i;
            i = d.end;
            continue;
        }
        return i;
    }
}

/// How many bytes open a list at `i`, or null if nothing does. `#(` and `#u8(`
/// are list openers as much as `(` is: their contents are datums that barf and
/// slurp move across.
fn listOpenLen(src: []const u8, i: usize) ?usize {
    if (i >= src.len) return null;
    if (src[i] == '(') return 1;
    if (src[i] != '#') return null;
    if (i + 1 < src.len and src[i + 1] == '(') return 2;
    if (i + 3 < src.len and (src[i + 1] == 'u' or src[i + 1] == 'U') and
        src[i + 2] == '8' and src[i + 3] == '(') return 4;
    return null;
}

/// How many bytes of datum prefix (`'`, `` ` ``, `,`, `,@`) sit at `i`.
fn prefixLen(src: []const u8, i: usize) usize {
    if (i >= src.len) return 0;
    return switch (src[i]) {
        '\'', '`' => 1,
        ',' => if (i + 1 < src.len and src[i + 1] == '@') @as(usize, 2) else 1,
        else => 0,
    };
}

/// The span of the single datum beginning at `start`, which must already be
/// past any trivia. Null when the datum is unterminated (an open list, an
/// unclosed string) or when `start` is not a datum start at all.
fn scanDatum(src: []const u8, start: usize, depth: u32) ?Span {
    if (depth >= max_depth) return null;
    if (start >= src.len) return null;

    const pl = prefixLen(src, start);
    if (pl > 0) {
        const inner_start = skipTrivia(src, start + pl, depth + 1);
        const inner = scanDatum(src, inner_start, depth + 1) orelse return null;
        return .{ .start = start, .end = inner.end };
    }

    if (listOpenLen(src, start)) |ol| return scanList(src, start, ol, depth);

    const c = src[start];
    switch (c) {
        ')' => return null,
        '"' => return scanQuoted(src, start, '"'),
        '|' => return scanQuoted(src, start, '|'),
        '#' => {
            // `#|` and `#;` are trivia, never the start of a datum.
            if (start + 1 < src.len and (src[start + 1] == '|' or src[start + 1] == ';')) return null;
            if (start + 1 < src.len and src[start + 1] == '\\') return scanCharLiteral(src, start);
            return scanAtom(src, start);
        },
        else => return scanAtom(src, start),
    }
}

fn scanList(src: []const u8, start: usize, open_len: usize, depth: u32) ?Span {
    var i = start + open_len;
    while (true) {
        i = skipTrivia(src, i, depth + 1);
        if (i >= src.len) return null;
        if (src[i] == ')') return .{ .start = start, .end = i + 1 };
        const d = scanDatum(src, i, depth + 1) orelse return null;
        i = d.end;
    }
}

/// A `"string"` or a `|pipe symbol|` — same shape, different terminator, both
/// with `\` escapes.
fn scanQuoted(src: []const u8, start: usize, term: u8) ?Span {
    var i = start + 1;
    while (i < src.len) {
        if (src[i] == '\\') {
            i += 2;
            continue;
        }
        if (src[i] == term) return .{ .start = start, .end = i + 1 };
        i += 1;
    }
    return null;
}

/// `#\a`, `#\space`, `#\x41`, `#\(`, `#\λ`. The first codepoint is always part
/// of the literal however delimiting it looks — which is the whole reason
/// `#\(` must not be counted as an open paren.
fn scanCharLiteral(src: []const u8, start: usize) ?Span {
    var i = start + 2;
    if (i >= src.len) return null;
    const first = src[i];
    const seq = std.unicode.utf8ByteSequenceLength(first) catch 1;
    i = @min(i + seq, src.len);
    // Only an alphanumeric first character can begin a *named* character
    // (`space`, `x41`); anything else is the literal, whole.
    if (std.ascii.isAlphanumeric(first)) {
        while (i < src.len and !Reader.isDelimiter(src[i])) : (i += 1) {}
    }
    return .{ .start = start, .end = i };
}

fn scanAtom(src: []const u8, start: usize) ?Span {
    var i = start;
    while (i < src.len and !Reader.isDelimiter(src[i])) : (i += 1) {}
    if (i == start) return null;
    return .{ .start = start, .end = i };
}

// --- Locating the form under the cursor ------------------------------------

/// The innermost *closed* list containing the cursor.
pub const Form = struct {
    /// Byte offset of `(` (or of the `#` in `#(` / `#u8(`).
    open: usize,
    /// First byte after the opener, where the children begin.
    body: usize,
    /// Byte offset of the matching `)`.
    close: usize,
};

/// Walk the whole buffer keeping a stack of open lists, and return the
/// innermost one whose interior spans `pos`.
///
/// "Interior" is `open < pos <= close`: the cursor just after `(` is inside,
/// just after `)` is outside. Only a list that actually closed can be
/// returned — an unbalanced buffer has no paren to move, so every command
/// declines.
///
/// Strings, comments, character literals and pipe symbols are skipped whole,
/// so a paren inside one never reaches the stack. Datum *prefixes* are
/// stepped over one token at a time rather than scanned as a unit, or the
/// cursor inside `'(a b)` would find no enclosing form.
pub fn enclosingList(src: []const u8, pos: usize) ?Form {
    var stack: [max_depth]struct { open: usize, body: usize } = undefined;
    var sp: usize = 0;
    var best: ?Form = null;
    var i: usize = 0;

    while (true) {
        i = skipTrivia(src, i, 0);
        if (i >= src.len) break;

        if (src[i] == ')') {
            if (sp > 0) {
                sp -= 1;
                const top = stack[sp];
                if (top.open < pos and pos <= i) {
                    if (best == null or top.open > best.?.open) {
                        best = .{ .open = top.open, .body = top.body, .close = i };
                    }
                }
            }
            i += 1;
            continue;
        }

        if (listOpenLen(src, i)) |ol| {
            if (sp >= stack.len) return best;
            stack[sp] = .{ .open = i, .body = i + ol };
            sp += 1;
            i += ol;
            continue;
        }

        const pl = prefixLen(src, i);
        if (pl > 0) {
            i += pl;
            continue;
        }

        // An unterminated string or pipe symbol means the rest of the buffer
        // is literal text: stop rather than walking into it and counting its
        // parens.
        const d = scanDatum(src, i, 0) orelse break;
        i = d.end;
    }
    return best;
}

/// The datum spans directly inside `form`, in order.
fn collectChildren(
    allocator: std.mem.Allocator,
    src: []const u8,
    form: Form,
    out: *std.ArrayList(Span),
) !void {
    var i = form.body;
    while (true) {
        i = skipTrivia(src, i, 0);
        if (i >= form.close) break;
        const d = scanDatum(src, i, 0) orelse break;
        if (d.end > form.close) break;
        try out.append(allocator, d);
        i = d.end;
    }
}

// --- The commands ----------------------------------------------------------

/// Apply `cmd` at byte offset `pos`. Returns null when the command does not
/// apply — an unbalanced form, nothing to slurp, a form too short to rotate —
/// in which case the caller leaves the buffer untouched. On success the
/// returned `text` is owned by the caller.
pub fn apply(
    allocator: std.mem.Allocator,
    cmd: Command,
    src: []const u8,
    pos: usize,
) ?Edit {
    const p = @min(pos, src.len);
    const form = enclosingList(src, p) orelse return null;
    return switch (cmd) {
        .slurp => slurp(allocator, src, form, p),
        .barf => barf(allocator, src, form, p),
        .raise => raise(allocator, src, form, p),
        .rotate => rotate(allocator, src, form, p),
    } catch null;
}

/// Pull the next datum in past the closing paren:
///
///     (a| b) c d   ->   (a| b c) d
///
/// Only the close paren moves, and it moves right, so nothing before the
/// cursor changes and the cursor stays put.
fn slurp(allocator: std.mem.Allocator, src: []const u8, form: Form, pos: usize) !?Edit {
    const after = skipTrivia(src, form.close + 1, 0);
    const next = scanDatum(src, after, 0) orelse return null;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, src[0..form.close]);
    try out.appendSlice(allocator, src[form.close + 1 .. next.end]);
    try out.append(allocator, ')');
    try out.appendSlice(allocator, src[next.end..]);
    return Edit{ .text = try out.toOwnedSlice(allocator), .pos = pos };
}

/// Push the last datum out past the closing paren:
///
///     (a| b c)   ->   (a| b) c
///
/// The paren moves left, so a cursor to its right shifts along with the text.
/// A one-element list barfs to `() a`, matching paredit.
fn barf(allocator: std.mem.Allocator, src: []const u8, form: Form, pos: usize) !?Edit {
    var kids: std.ArrayList(Span) = .empty;
    defer kids.deinit(allocator);
    try collectChildren(allocator, src, form, &kids);
    if (kids.items.len == 0) return null;

    // The paren lands right after the second-to-last datum, so the whitespace
    // that separated the barfed datum stays outside with it.
    const n = kids.items.len;
    const at = if (n >= 2) kids.items[n - 2].end else form.body;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, src[0..at]);
    try out.append(allocator, ')');
    try out.appendSlice(allocator, src[at..form.close]);
    try out.appendSlice(allocator, src[form.close + 1 ..]);
    return Edit{
        .text = try out.toOwnedSlice(allocator),
        .pos = if (pos > at) pos + 1 else pos,
    };
}

/// Replace the enclosing form with the datum at point:
///
///     (+ 1 (* 2 |3))   ->   (+ 1 |3)
///
/// The datum at point is the child containing the cursor, or the first one
/// after it when the cursor sits in whitespace.
fn raise(allocator: std.mem.Allocator, src: []const u8, form: Form, pos: usize) !?Edit {
    var kids: std.ArrayList(Span) = .empty;
    defer kids.deinit(allocator);
    try collectChildren(allocator, src, form, &kids);
    if (kids.items.len == 0) return null;

    var chosen: ?Span = null;
    for (kids.items) |k| {
        if (pos >= k.start and pos <= k.end) {
            chosen = k;
            break;
        }
        if (k.start > pos) {
            chosen = k;
            break;
        }
    }
    const kid = chosen orelse kids.items[kids.items.len - 1];

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, src[0..form.open]);
    try out.appendSlice(allocator, src[kid.start..kid.end]);
    try out.appendSlice(allocator, src[form.close + 1 ..]);

    const offset = if (pos >= kid.start and pos <= kid.end) pos - kid.start else 0;
    return Edit{ .text = try out.toOwnedSlice(allocator), .pos = form.open + offset };
}

/// Rotate the arguments of the enclosing form left, leaving the head alone:
///
///     (if a| b c)   ->   (if b c a|)
///
/// The head stays because rotating it too would turn every call form into
/// something that cannot be evaluated (`(+ 1 2)` -> `(1 2 +)`), and the point
/// of a cycle is that you can keep pressing it: repeating this n-1 times on n
/// arguments restores the original. The whitespace between arguments stays
/// where it is; only the datums move, and the cursor follows the one it was
/// on.
///
/// Needs a head and at least two arguments; anything shorter declines.
fn rotate(allocator: std.mem.Allocator, src: []const u8, form: Form, pos: usize) !?Edit {
    var kids: std.ArrayList(Span) = .empty;
    defer kids.deinit(allocator);
    try collectChildren(allocator, src, form, &kids);
    if (kids.items.len < 3) return null;
    const args = kids.items[1..];

    var slots: std.ArrayList(usize) = .empty;
    defer slots.deinit(allocator);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, src[0..args[0].start]);
    for (args, 0..) |_, j| {
        try slots.append(allocator, out.items.len);
        const from = args[(j + 1) % args.len];
        try out.appendSlice(allocator, src[from.start..from.end]);
        if (j + 1 < args.len) {
            try out.appendSlice(allocator, src[args[j].end..args[j + 1].start]);
        }
    }
    try out.appendSlice(allocator, src[args[args.len - 1].end..]);

    // The datum in slot k moved to slot k-1; carry the cursor with it.
    var new_pos = @min(pos, out.items.len);
    for (args, 0..) |a, k| {
        if (pos >= a.start and pos <= a.end) {
            const dest = (k + args.len - 1) % args.len;
            new_pos = slots.items[dest] + (pos - a.start);
            break;
        }
    }
    return Edit{ .text = try out.toOwnedSlice(allocator), .pos = new_pos };
}

// --- Tests -----------------------------------------------------------------

/// Drive a command with the cursor written as `|`, and compare against an
/// expected buffer written the same way — the two lines a user would see.
fn expectEdit(cmd: Command, before: []const u8, after: []const u8) !void {
    const a = std.testing.allocator;
    const cursor = std.mem.indexOfScalar(u8, before, '|') orelse return error.NoCursorMarker;
    const src = try std.mem.concat(a, u8, &.{ before[0..cursor], before[cursor + 1 ..] });
    defer a.free(src);

    const edit = apply(a, cmd, src, cursor) orelse {
        std.debug.print("command declined on \"{s}\"\n", .{before});
        return error.TestUnexpectedResult;
    };
    defer a.free(edit.text);

    var got: std.ArrayList(u8) = .empty;
    defer got.deinit(a);
    try got.appendSlice(a, edit.text[0..edit.pos]);
    try got.append(a, '|');
    try got.appendSlice(a, edit.text[edit.pos..]);
    try std.testing.expectEqualStrings(after, got.items);
}

/// Assert the command declines and leaves the buffer alone.
fn expectDeclined(cmd: Command, before: []const u8) !void {
    const a = std.testing.allocator;
    const cursor = std.mem.indexOfScalar(u8, before, '|') orelse return error.NoCursorMarker;
    const src = try std.mem.concat(a, u8, &.{ before[0..cursor], before[cursor + 1 ..] });
    defer a.free(src);
    if (apply(a, cmd, src, cursor)) |edit| {
        defer a.free(edit.text);
        std.debug.print("expected no edit on \"{s}\", got \"{s}\"\n", .{ before, edit.text });
        return error.TestUnexpectedResult;
    }
}

test "slurp — pulls the next datum in" {
    try expectEdit(.slurp, "(a| b) c d", "(a| b c) d");
    try expectEdit(.slurp, "(+ 1 2|) 3", "(+ 1 2 3|)");
    try expectEdit(.slurp, "(a|) (b c) d", "(a| (b c)) d");
}

test "slurp — keeps the separating whitespace outside" {
    try expectEdit(.slurp, "(a|)   c", "(a|   c)");
}

test "slurp — nothing to the right declines" {
    try expectDeclined(.slurp, "(a| b)");
    try expectDeclined(.slurp, "(a| b)   ");
    try expectDeclined(.slurp, "(a| b) ; trailing comment");
}

test "barf — pushes the last datum out" {
    try expectEdit(.barf, "(a| b c)", "(a| b) c");
    try expectEdit(.barf, "(a b c|)", "(a b) c|");
    // A cursor to the right of the moved paren travels with the text.
    try expectEdit(.barf, "(a b |c)", "(a b) |c");
}

test "barf — a one-element list barfs to an empty one" {
    try expectEdit(.barf, "(|a)", "(|) a");
}

test "barf — an empty list declines" {
    try expectDeclined(.barf, "(|)");
}

test "barf then slurp is a round trip" {
    const a = std.testing.allocator;
    const src = "(+ 1 2 3)";
    const barfed = apply(a, .barf, src, 3).?;
    defer a.free(barfed.text);
    try std.testing.expectEqualStrings("(+ 1 2) 3", barfed.text);
    const slurped = apply(a, .slurp, barfed.text, barfed.pos).?;
    defer a.free(slurped.text);
    try std.testing.expectEqualStrings(src, slurped.text);
}

test "raise — replaces the enclosing form with the datum at point" {
    try expectEdit(.raise, "(+ 1 (* 2 |3))", "(+ 1 |3)");
    try expectEdit(.raise, "(+ 1 (|* 2 3))", "(+ 1 |*)");
    try expectEdit(.raise, "(foo (bar |(baz 1)))", "(foo |(baz 1))");
}

test "raise — a cursor in whitespace takes the datum after it" {
    try expectEdit(.raise, "(+ 1 (* | 2 3))", "(+ 1 |2)");
}

test "raise — an empty form declines" {
    try expectDeclined(.raise, "(|)");
}

test "rotate — cycles the arguments and leaves the head" {
    try expectEdit(.rotate, "(if a| b c)", "(if b c a|)");
    try expectEdit(.rotate, "(list 1| 2 3)", "(list 2 3 1|)");
}

test "rotate — repeating it restores the original" {
    const a = std.testing.allocator;
    const src = "(list 1 2 3)";
    var cur = try a.dupe(u8, src);
    defer a.free(cur);
    var pos: usize = 6;
    var round: usize = 0;
    while (round < 3) : (round += 1) {
        const e = apply(a, .rotate, cur, pos).?;
        a.free(cur);
        cur = e.text;
        pos = e.pos;
    }
    try std.testing.expectEqualStrings(src, cur);
}

test "rotate — too few datums to rotate" {
    try expectDeclined(.rotate, "(f| x)");
    try expectDeclined(.rotate, "(|x)");
    try expectDeclined(.rotate, "(|)");
}

test "rotate — preserves the gaps, moves only the datums" {
    try expectEdit(.rotate, "(f a|   bb  ccc)", "(f bb|   ccc  a)");
}

test "the cursor must be inside a form" {
    // Before the open paren and after the close paren are both outside.
    try expectDeclined(.barf, "|(a b c)");
    try expectDeclined(.barf, "(a b c)|");
    try expectDeclined(.barf, "|");
    try expectDeclined(.raise, "a| b c");
}

test "an unbalanced form has no paren to move" {
    try expectDeclined(.slurp, "(+ 1 2| 3");
    try expectDeclined(.barf, "(+ 1 2| 3");
    try expectDeclined(.raise, "(+ 1 2| 3");
    try expectDeclined(.rotate, "(+ 1 2| 3");
}

test "the innermost enclosing form wins" {
    try expectEdit(.barf, "(a (b |c d) e)", "(a (b |c) d e)");
    // Slurping from an inner form eats the outer form's next datum.
    try expectEdit(.slurp, "((a| b) c)", "((a| b c))");
    try expectEdit(.raise, "(a (b |c) d)", "(a |c d)");
}

test "a stray close paren before the form does not confuse the walk" {
    try expectEdit(.barf, ") (a b| c)", ") (a b|) c");
}

test "the cursor on the close paren is inside; past it is not" {
    try expectEdit(.barf, "(a b c|)", "(a b) c|");
    try expectDeclined(.barf, "(a b c)|");
}

test "a paren inside a string is not a paren" {
    try expectEdit(.barf, "(display \"a(b\" |x)", "(display \"a(b\") |x");
    try expectEdit(.slurp, "(a|) \"b)c\" d", "(a| \"b)c\") d");
    try expectDeclined(.barf, "(display \"unterminated| (");
}

test "a paren inside a comment is not a paren" {
    try expectEdit(.barf, "(a b| ; )))\n c)", "(a b|) ; )))\n c");
    try expectEdit(.barf, "(a b| #| ) |# c)", "(a b|) #| ) |# c");
}

test "a character literal paren is not a paren (kaappi#358)" {
    try expectEdit(.barf, "(char=? #\\(| x)", "(char=? #\\(|) x");
    try expectEdit(.raise, "(f (char=? #\\)| ))", "(f |#\\))");
    try expectEdit(.barf, "(list #\\space| #\\a)", "(list #\\space|) #\\a");
}

test "a pipe symbol hides its parens too (kaappi#358)" {
    try expectEdit(.barf, "(list '|foo(bar|| x)", "(list '|foo(bar|) x");
}

test "a datum comment is skipped, not treated as a datum" {
    // `#;(b c)` is trivia: the last real datum is `d`, and the comment goes
    // out with it rather than being barfed on its own.
    try expectEdit(.barf, "(a| #;(b c) d)", "(a|) #;(b c) d");
    try expectEdit(.raise, "(+ #;(x) |1)", "|1");
}

test "vector and bytevector literals are forms too" {
    try expectEdit(.barf, "#(1 2| 3)", "#(1 2|) 3");
    try expectEdit(.slurp, "#u8(1 2|) 3", "#u8(1 2 3|)");
    try expectEdit(.rotate, "#(a| b c)", "#(b c a|)");
}

test "a quoted form is still a form (its prefix is not a datum boundary)" {
    try expectEdit(.barf, "'(a b| c)", "'(a b|) c");
    try expectEdit(.slurp, "(a|) '(b c)", "(a| '(b c))");
    try expectEdit(.barf, "`(a ,b| ,@c)", "`(a ,b|) ,@c");
}

test "brackets are ordinary characters, not parens" {
    // The reader gives `[`/`]` no meaning, so they neither open a form nor
    // delimit a datum: `[i` and `0]` are one atom each.
    try expectEdit(.barf, "(let loop| ([i 0]) i)", "(let loop|) ([i 0]) i");
    try expectDeclined(.barf, "(let loop ([i| 0]) i)");
}

test "a multi-line form edits across the newline" {
    try expectEdit(
        .barf,
        "(define (f x)\n  (+ x 1)|\n  2)",
        "(define (f x)\n  (+ x 1)|)\n  2",
    );
}

test "utf-8 stays intact" {
    try expectEdit(.barf, "(list \"λ\" |π)", "(list \"λ\") |π");
    try expectEdit(.rotate, "(f λ| π ω)", "(f π| ω λ)");
}

test "deeply nested input declines rather than smashing the stack" {
    const a = std.testing.allocator;
    const depth = max_depth + 64;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(a);
    try src.appendNTimes(a, '(', depth);
    try src.appendSlice(a, "x");
    try src.appendNTimes(a, ')', depth);
    // No crash, no hang; whatever it decides, it decides in bounded stack.
    if (apply(a, .barf, src.items, depth + 1)) |e| a.free(e.text);
    if (apply(a, .raise, src.items, depth + 1)) |e| a.free(e.text);
}

test "enclosingList — finds the innermost closed list" {
    const src = "(+ 1 (* 2 3))";
    const f = enclosingList(src, 10).?;
    try std.testing.expectEqual(@as(usize, 5), f.open);
    try std.testing.expectEqual(@as(usize, 6), f.body);
    try std.testing.expectEqual(@as(usize, 11), f.close);

    // Just inside the outer open paren, just before the outer close paren.
    try std.testing.expectEqual(@as(usize, 0), enclosingList(src, 1).?.open);
    try std.testing.expectEqual(@as(usize, 0), enclosingList(src, 12).?.open);
    // Outside on either end.
    try std.testing.expect(enclosingList(src, 0) == null);
    try std.testing.expect(enclosingList(src, 13) == null);
}
