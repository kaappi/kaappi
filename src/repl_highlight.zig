//! REPL syntax highlighting: the token scanner, the isocline highlighter
//! callback, and the theme→isocline style bridge.
//!
//! Split out of `repl.zig` (kaappi#2266) so the scanner and the style mapping
//! can be tested without a terminal and without dragging in the REPL loop.
//! Everything here is driven by `reader.zig`'s notion of where a token ends
//! (`Reader.isDelimiter`) and `config.zig`'s theme escapes, so the colors
//! cannot disagree with the parse. `repl.zig` registers `highlightCallback`
//! with isocline and calls `applyTheme` / `setEnabled` at startup; nothing
//! else in this module touches the editor.
//!
//! Under the WASI fallback (no tty layer) the editor does not exist, so the
//! `ic.*` references below are only ever analyzed when `repl()` is — which
//! `main.zig` never reaches on that target. The `use_isocline` gate is the
//! same one `repl.zig` uses.

const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const reader = @import("reader.zig");
const config_mod = @import("config.zig");

const use_isocline = !is_wasm;
const ic = if (use_isocline) @import("isocline.zig") else struct {};

/// Whether the user enabled highlighting (`repl.highlight` in
/// `~/.kaappi/config`). Owned here because `repl()` (which registers the
/// highlighter) and `highlightCallback` (which gates on it) both need it.
var highlight_enabled: bool = true;

pub fn setEnabled(flag: bool) void {
    highlight_enabled = flag;
}

pub fn enabled() bool {
    return highlight_enabled;
}

fn isSchemeKeyword(word: []const u8) bool {
    const keywords = [_][]const u8{
        "define",         "lambda",             "if",            "cond",
        "let",            "let*",               "letrec",        "letrec*",
        "begin",          "set!",               "and",           "or",
        "when",           "unless",             "case",          "do",
        "define-syntax",  "syntax-rules",       "quote",         "quasiquote",
        "unquote",        "unquote-splicing",   "import",        "export",
        "define-library", "define-record-type", "define-values", "guard",
        "delay",          "delay-force",        "parameterize",  "include",
        "include-ci",     "else",               "=>",            "let-values",
        "let*-values",    "case-lambda",        "let-syntax",    "letrec-syntax",
        "syntax-error",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

/// Where a token ends, for the highlighter. This is `Reader.isDelimiter` — not
/// a copy of it — so the colors cannot disagree with the parse. In particular
/// `[` and `]` are *not* delimiters: the reader gives them no meaning (`0]` is
/// KP1002), so `[i` and `0]` are one atom each, and painting them like parens
/// advertised a structure neither the reader nor `repl_sexp` believes in
/// (kaappi#2216).
const isDelimiter = reader.Reader.isDelimiter;

fn isNumberLike(word: []const u8) bool {
    if (word.len == 0) return false;
    if (std.ascii.isDigit(word[0])) return true;
    if (word.len > 1 and (word[0] == '+' or word[0] == '-') and std.ascii.isDigit(word[1])) return true;
    // +inf.0, -inf.0, +nan.0, -nan.0
    if (std.mem.eql(u8, word, "+inf.0") or std.mem.eql(u8, word, "-inf.0") or
        std.mem.eql(u8, word, "+nan.0") or std.mem.eql(u8, word, "-nan.0")) return true;
    return false;
}

// Style names registered with isocline at REPL start (see `applyTheme`).
// `ic-bracematch` and `ic-prompt` are isocline's own names, redefined so the
// user's theme drives them too.
const style_keyword = "kaappi-keyword";
const style_string = "kaappi-string";
const style_number = "kaappi-number";
const style_comment = "kaappi-comment";
const style_boolean = "kaappi-boolean";
const style_paren = "kaappi-paren";

/// Hands each styled span to isocline, which records it in an attribute buffer
/// and renders it. Nothing is allocated and no escape sequence is written by
/// hand — which is what made the old emitter's allocator mismatch possible
/// (kaappi#234).
const IsoclineEmitter = struct {
    henv: ?*ic.HighlightEnv,
    fn emit(self: @This(), start: usize, end: usize, style: [*:0]const u8) void {
        if (end <= start) return;
        ic.highlight(self.henv, @intCast(start), @intCast(end - start), style);
    }
};

/// isocline highlighter. Unlike the linenoise callback this replaced, it gets
/// the whole form — every line of it — rather than the current physical line,
/// so the `accumulated_input` splice that used to reach back across the
/// continuation seam is gone. It also gets no cursor position: matching-paren
/// highlighting is isocline's own job now (`ic_enable_brace_matching`), styled
/// through `ic-bracematch`.
pub fn highlightCallback(henv: ?*ic.HighlightEnv, input_c: [*c]const u8, arg: ?*anyopaque) callconv(.c) void {
    _ = arg;
    if (!highlight_enabled) return;
    const input = if (input_c) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return;
    scanHighlight(input, IsoclineEmitter{ .henv = henv });
}

/// Splits `input` into styled spans, calling `ctx.emit(start, end, style)` for
/// each. Separated from the isocline call so the token rules can be tested
/// without a terminal — `ic_highlight` needs a live editor to write into.
fn scanHighlight(input: []const u8, ctx: anytype) void {
    if (input.len == 0) return;

    var i: usize = 0;
    while (i < input.len) {
        const ch = input[i];
        const start = i;

        if (ch == ';') {
            while (i < input.len and input[i] != '\n') : (i += 1) {}
            ctx.emit(start, i, style_comment);
            continue;
        }

        if (ch == '#' and i + 1 < input.len and input[i + 1] == '|') {
            i += 2;
            var depth: u32 = 1;
            while (i < input.len and depth > 0) {
                if (input[i] == '#' and i + 1 < input.len and input[i + 1] == '|') {
                    depth += 1;
                    i += 2;
                } else if (input[i] == '|' and i + 1 < input.len and input[i + 1] == '#') {
                    depth -= 1;
                    i += 2;
                } else {
                    i += 1;
                }
            }
            ctx.emit(start, i, style_comment);
            continue;
        }

        // #; datum comment prefix
        if (ch == '#' and i + 1 < input.len and input[i + 1] == ';') {
            i += 2;
            ctx.emit(start, i, style_comment);
            continue;
        }

        // #!fold-case / #!no-fold-case directives
        if (ch == '#' and i + 1 < input.len and input[i + 1] == '!') {
            while (i < input.len and !isDelimiter(input[i])) : (i += 1) {}
            ctx.emit(start, i, style_comment);
            continue;
        }

        // #u8( bytevector literal
        if (ch == '#' and i + 3 < input.len and input[i + 1] == 'u' and input[i + 2] == '8' and input[i + 3] == '(') {
            i += 4;
            ctx.emit(start, i, style_paren);
            continue;
        }

        // #( vector literal
        if (ch == '#' and i + 1 < input.len and input[i + 1] == '(') {
            i += 2;
            ctx.emit(start, i, style_paren);
            continue;
        }

        if (ch == '"') {
            i += 1;
            while (i < input.len) {
                if (input[i] == '\\' and i + 1 < input.len) {
                    i += 2;
                    continue;
                }
                if (input[i] == '"') {
                    i += 1;
                    break;
                }
                i += 1;
            }
            ctx.emit(start, i, style_string);
            continue;
        }

        if (ch == '(' or ch == ')') {
            i += 1;
            ctx.emit(start, i, style_paren);
            continue;
        }

        if (ch == '#' and i + 1 < input.len and input[i + 1] == '\\') {
            i += 2;
            if (i < input.len) {
                const first = input[i];
                if ((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z')) {
                    while (i < input.len and ((input[i] >= 'a' and input[i] <= 'z') or (input[i] >= 'A' and input[i] <= 'Z'))) : (i += 1) {}
                } else {
                    i += 1;
                }
            }
            ctx.emit(start, i, style_number);
            continue;
        }

        // #true / #false (R7RS extended boolean)
        if (ch == '#' and i + 4 < input.len) {
            if (std.mem.startsWith(u8, input[i..], "#true") and (i + 5 >= input.len or isDelimiter(input[i + 5]))) {
                i += 5;
                ctx.emit(start, i, style_boolean);
                continue;
            }
            if (i + 5 < input.len and std.mem.startsWith(u8, input[i..], "#false") and (i + 6 >= input.len or isDelimiter(input[i + 6]))) {
                i += 6;
                ctx.emit(start, i, style_boolean);
                continue;
            }
        }

        // #t / #f (short boolean)
        if (ch == '#' and i + 1 < input.len and (input[i + 1] == 't' or input[i + 1] == 'f')) {
            if (i + 2 >= input.len or isDelimiter(input[i + 2])) {
                i += 2;
                ctx.emit(start, i, style_boolean);
                continue;
            }
        }

        // #b #o #x #d #e #i number prefix
        if (ch == '#' and i + 1 < input.len) {
            const next = input[i + 1];
            if (next == 'b' or next == 'o' or next == 'x' or next == 'd' or next == 'e' or next == 'i') {
                while (i < input.len and !isDelimiter(input[i])) : (i += 1) {}
                ctx.emit(start, i, style_number);
                continue;
            }
        }

        // ,@ unquote-splicing
        if (ch == ',' and i + 1 < input.len and input[i + 1] == '@') {
            i += 2;
            ctx.emit(start, i, style_keyword);
            continue;
        }

        if (ch == '\'' or ch == '`' or ch == ',') {
            i += 1;
            ctx.emit(start, i, style_keyword);
            continue;
        }

        // |...| pipe-quoted symbol: left unstyled, as before
        if (ch == '|') {
            i += 1;
            while (i < input.len and input[i] != '|') {
                if (input[i] == '\\' and i + 1 < input.len) i += 1;
                i += 1;
            }
            if (i < input.len) i += 1;
            continue;
        }

        if (!isDelimiter(ch)) {
            while (i < input.len and !isDelimiter(input[i])) : (i += 1) {}
            const word = input[start..i];
            if (isSchemeKeyword(word)) {
                ctx.emit(start, i, style_keyword);
            } else if (isNumberLike(word)) {
                ctx.emit(start, i, style_number);
            }
            continue;
        }

        i += 1;
    }
}

/// Translate one of `config.Theme`'s SGR escapes into an isocline style string.
///
/// The theme stores escapes because linenoise was handed raw bytes; isocline
/// takes style *names* and does its own rendering, which is what lets it
/// measure widths correctly and downsample color for the terminal. `config.zig`
/// only ever produces `\x1b[<n>m` or `\x1b[1;<n>m` (from a color name, via
/// `colorToAnsi`), or the empty string for `none`, so the mapping is total.
/// Anything unrecognized yields "" — isocline's default, i.e. unstyled.
fn ansiToIcStyle(escape: []const u8, buf: []u8) [:0]const u8 {
    const empty: [:0]const u8 = "";
    if (escape.len < 4) return empty;
    if (!std.mem.startsWith(u8, escape, "\x1b[")) return empty;
    if (escape[escape.len - 1] != 'm') return empty;
    var body = escape[2 .. escape.len - 1];

    var bold = false;
    if (std.mem.startsWith(u8, body, "1;")) {
        bold = true;
        body = body[2..];
    }
    const code = std.fmt.parseInt(u8, body, 10) catch return empty;
    const name: []const u8 = switch (code) {
        30 => "ansi-black",
        31 => "ansi-maroon",
        32 => "ansi-green",
        33 => "ansi-olive",
        34 => "ansi-navy",
        35 => "ansi-purple",
        36 => "ansi-teal",
        37 => "ansi-silver",
        90 => "ansi-darkgray",
        91 => "ansi-red",
        92 => "ansi-lime",
        93 => "ansi-yellow",
        94 => "ansi-blue",
        95 => "ansi-fuchsia",
        96 => "ansi-aqua",
        97 => "ansi-white",
        else => return empty,
    };
    const s = if (bold)
        std.fmt.bufPrintZ(buf, "bold {s}", .{name}) catch return empty
    else
        std.fmt.bufPrintZ(buf, "{s}", .{name}) catch return empty;
    return s;
}

/// Register the configured theme with isocline. `ic-prompt` and `ic-bracematch`
/// are isocline's own style names, redefined here so the user's `repl.color.*`
/// settings reach the prompt and the matching-paren highlight that isocline now
/// draws itself.
pub fn applyTheme(t: config_mod.Theme) void {
    var buf: [32]u8 = undefined;
    const pairs = [_]struct { name: [*:0]const u8, escape: []const u8 }{
        .{ .name = style_keyword, .escape = t.keyword },
        .{ .name = style_string, .escape = t.string },
        .{ .name = style_number, .escape = t.number },
        .{ .name = style_comment, .escape = t.comment },
        .{ .name = style_boolean, .escape = t.boolean },
        .{ .name = style_paren, .escape = t.paren },
        .{ .name = "ic-bracematch", .escape = t.match_paren },
        .{ .name = "ic-prompt", .escape = t.prompt },
    };
    for (pairs) |p| {
        ic.styleDef(p.name, ansiToIcStyle(p.escape, &buf));
    }
}

/// Collects the spans `scanHighlight` emits, so the token rules can be checked
/// without a live isocline editor.
const SpanCollector = struct {
    styles: *std.ArrayList([]const u8),
    starts: *std.ArrayList(usize),
    ends: *std.ArrayList(usize),
    fn emit(self: @This(), start: usize, end: usize, style: [*:0]const u8) void {
        if (end <= start) return;
        self.styles.append(std.testing.allocator, std.mem.span(style)) catch {};
        self.starts.append(std.testing.allocator, start) catch {};
        self.ends.append(std.testing.allocator, end) catch {};
    }
};

/// Assert that `input[expect_start..expect_end]` is styled `style`.
fn expectSpan(input: []const u8, expect_start: usize, expect_end: usize, style: []const u8) !void {
    var styles: std.ArrayList([]const u8) = .empty;
    var starts: std.ArrayList(usize) = .empty;
    var ends: std.ArrayList(usize) = .empty;
    defer styles.deinit(std.testing.allocator);
    defer starts.deinit(std.testing.allocator);
    defer ends.deinit(std.testing.allocator);
    scanHighlight(input, SpanCollector{ .styles = &styles, .starts = &starts, .ends = &ends });
    for (styles.items, starts.items, ends.items) |st, a, b| {
        if (a == expect_start and b == expect_end and std.mem.eql(u8, st, style)) return;
    }
    std.debug.print("no {s} span at [{d},{d}) in \"{s}\"; got:\n", .{ style, expect_start, expect_end, input });
    for (styles.items, starts.items, ends.items) |st, a, b| {
        std.debug.print("  [{d},{d}) {s} = \"{s}\"\n", .{ a, b, st, input[a..b] });
    }
    return error.TestUnexpectedResult;
}

/// Assert no span of `style` covers any of `input`.
fn expectNoStyle(input: []const u8, style: []const u8) !void {
    var styles: std.ArrayList([]const u8) = .empty;
    var starts: std.ArrayList(usize) = .empty;
    var ends: std.ArrayList(usize) = .empty;
    defer styles.deinit(std.testing.allocator);
    defer starts.deinit(std.testing.allocator);
    defer ends.deinit(std.testing.allocator);
    scanHighlight(input, SpanCollector{ .styles = &styles, .starts = &starts, .ends = &ends });
    for (styles.items) |st| {
        if (std.mem.eql(u8, st, style)) return error.TestUnexpectedResult;
    }
}

test "scanHighlight — keywords and parens" {
    try expectSpan("(define x 1)", 0, 1, style_paren);
    try expectSpan("(define x 1)", 1, 7, style_keyword);
    try expectSpan("(define x 1)", 11, 12, style_paren);
}

test "scanHighlight — spans a multi-line form" {
    // The whole form reaches the highlighter now, not just one line, so an
    // offset past the newline must still resolve.
    const src = "(define (f x)\n  (+ x 1))";
    try expectSpan(src, 1, 7, style_keyword);
    try expectSpan(src, 16, 17, style_paren);
}

test "scanHighlight — string and comment" {
    try expectSpan("(display \"hi\")", 9, 13, style_string);
    try expectSpan("(+ 1) ; note", 6, 12, style_comment);
    try expectSpan("(+ #| b |# 1)", 3, 10, style_comment);
}

test "scanHighlight — a comment ends at the newline, not the buffer" {
    const src = "; one\n(+ 1 2)";
    try expectSpan(src, 0, 5, style_comment);
    try expectSpan(src, 6, 7, style_paren);
}

test "scanHighlight — #true/#false get boolean style" {
    try expectSpan("#true", 0, 5, style_boolean);
    try expectSpan("#false", 0, 6, style_boolean);
    try expectSpan("#t", 0, 2, style_boolean);
}

test "scanHighlight — #trueish is not boolean" {
    try expectNoStyle("#trueish", style_boolean);
}

test "scanHighlight — vector and bytevector open" {
    try expectSpan("#(1 2)", 0, 2, style_paren);
    try expectSpan("#u8(1 2)", 0, 4, style_paren);
}

test "scanHighlight — radix prefixes are numbers" {
    try expectSpan("#xff", 0, 4, style_number);
    try expectSpan("#b101", 0, 5, style_number);
    try expectSpan("#o77", 0, 4, style_number);
    try expectSpan("#e1.5", 0, 5, style_number);
}

test "scanHighlight — quote forms are keywords" {
    try expectSpan(",@x", 0, 2, style_keyword);
    try expectSpan("'x", 0, 1, style_keyword);
    try expectSpan("`x", 0, 1, style_keyword);
}

test "scanHighlight — datum comment and directive" {
    try expectSpan("#; foo", 0, 2, style_comment);
    try expectSpan("#!fold-case", 0, 11, style_comment);
}

test "scanHighlight — |symbol| is not a keyword" {
    try expectNoStyle("|define|", style_keyword);
}

test "scanHighlight — char literal parens do not become parens" {
    try expectSpan("#\\(", 0, 3, style_number);
    try expectNoStyle("#\\(", style_paren);
}

test "scanHighlight — brackets are not parens (kaappi#2216)" {
    // The reader pairs neither, `setMatchingBraces` is given "()" alone, and
    // `repl_sexp` treats them as ordinary atom characters. The highlighter
    // used to paint them anyway.
    try expectNoStyle("[i 0]", style_paren);
    try expectSpan("(let loop ([i 0]) i)", 0, 1, style_paren);
    try expectSpan("(let loop ([i 0]) i)", 10, 11, style_paren);
}

test "scanHighlight — infinities and nan are numbers" {
    try expectSpan("+inf.0", 0, 6, style_number);
    try expectSpan("-nan.0", 0, 6, style_number);
}

test "ansiToIcStyle — every colour config.zig emits maps to an isocline name" {
    var buf: [32]u8 = undefined;
    const cases = [_]struct { escape: []const u8, want: []const u8 }{
        .{ .escape = "\x1b[30m", .want = "ansi-black" },
        .{ .escape = "\x1b[31m", .want = "ansi-maroon" },
        .{ .escape = "\x1b[32m", .want = "ansi-green" },
        .{ .escape = "\x1b[33m", .want = "ansi-olive" },
        .{ .escape = "\x1b[34m", .want = "ansi-navy" },
        .{ .escape = "\x1b[35m", .want = "ansi-purple" },
        .{ .escape = "\x1b[36m", .want = "ansi-teal" },
        .{ .escape = "\x1b[37m", .want = "ansi-silver" },
        .{ .escape = "\x1b[90m", .want = "ansi-darkgray" },
        .{ .escape = "\x1b[91m", .want = "ansi-red" },
        .{ .escape = "\x1b[92m", .want = "ansi-lime" },
        .{ .escape = "\x1b[93m", .want = "ansi-yellow" },
        .{ .escape = "\x1b[94m", .want = "ansi-blue" },
        .{ .escape = "\x1b[95m", .want = "ansi-fuchsia" },
        .{ .escape = "\x1b[96m", .want = "ansi-aqua" },
        .{ .escape = "\x1b[97m", .want = "ansi-white" },
        // The `1;` form config.zig produces for a `bold <colour>` setting.
        .{ .escape = "\x1b[1;30m", .want = "bold ansi-black" },
        .{ .escape = "\x1b[1;93m", .want = "bold ansi-yellow" },
        .{ .escape = "\x1b[1;90m", .want = "bold ansi-darkgray" },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c.want, ansiToIcStyle(c.escape, &buf));
    }
}

test "ansiToIcStyle — unrecognized input is unstyled, never a wrong style" {
    var buf: [32]u8 = undefined;
    const rejects = [_][]const u8{
        "", // what `none` produces
        "\x1b[m", // shorter than any real escape
        "\x1b[0m", // reset: not a foreground colour
        "\x1b[39m", // default foreground: no isocline name for it
        "\x1b[42m", // a background colour, not a foreground one
        "0;31m", // no CSI introducer
        "\x1b[31", // no terminator
        "\x1b[xxm", // body is not a number
        "\x1b[1;xm", // ...nor after the bold prefix
        "\x1b[999m", // out of range for the u8 parse
    };
    for (rejects) |r| {
        try std.testing.expectEqualStrings("", ansiToIcStyle(r, &buf));
    }
}

test "ansiToIcStyle — both built-in themes round-trip through applyTheme's buffer" {
    // The coupling check, and the reason this function is worth testing at all:
    // it is the only bridge between config.zig's SGR escapes and isocline's
    // style names, and every failure mode returns "" — which renders unstyled
    // with nothing to notice. If config.zig ever changes how it spells a
    // colour, or a style name outgrows applyTheme's [32]u8 (bufPrintZ failing
    // is also just ""), all eight styles would quietly go plain. Assert the
    // real themes map instead of trusting hand-written escapes to stay in step.
    var buf: [32]u8 = undefined;
    for ([_]config_mod.Theme{ config_mod.Theme.dark, config_mod.Theme.light }) |t| {
        // Exactly the eight fields applyTheme feeds through.
        const escapes = [_][]const u8{
            t.keyword, t.string,      t.number, t.comment,
            t.boolean, t.match_paren, t.paren,  t.prompt,
        };
        for (escapes) |e| {
            const style = ansiToIcStyle(e, &buf);
            try std.testing.expect(style.len > 0);
            try std.testing.expect(std.mem.startsWith(u8, style, "ansi-") or
                std.mem.startsWith(u8, style, "bold ansi-"));
        }
    }
}
