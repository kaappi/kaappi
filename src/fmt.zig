//! `kaappi fmt` — canonical, comment-preserving Scheme formatter (kaappi#1518,
//! the final item of the machine-legibility epic kaappi#1503).
//!
//! A canonical formatter makes diffs meaningful, ends style review, and gives
//! agents format-on-save invariance. `zig fmt` does this for the compiler's Zig;
//! nothing did it for Scheme. `kaappi fmt` fills that gap:
//!
//!   kaappi fmt [--check] files...     # format in place, or check for CI
//!   kaappi fmt [--check]              # read stdin, write stdout (or check)
//!
//! **Design.** Comments are not datums, so the ordinary reader (which discards
//! them) cannot drive a formatter. This module has its own *concrete* syntax
//! reader: a lexer (`Lexer`) that emits every lexeme — including line comments,
//! block comments, `#;` datum comments, and the blank-line structure between
//! them — and a parser (`Parser`) that builds a CST (`Node`) preserving all of
//! it. Atom text is kept verbatim, so number/character/string spellings are
//! never rewritten. `fmt_print.zig` walks the CST and lays it out canonically:
//! 2-space R7RS indentation, single-space separators, closing parens gathered,
//! forms reflowed to fit `max_width` columns.
//!
//! **Safety.** Layout can only rearrange whitespace *between* lexemes, never
//! change them, so the datums a program reads are invariant. That invariant is
//! also *checked at runtime*: before writing any file, `verifyRoundTrip` re-reads
//! the original and the formatted text with the real reader and compares the
//! datum sequences with `equal?`. On any mismatch — or if either side fails to
//! read — `fmt` refuses to write and reports it, so a bug here can never corrupt
//! a source file.

const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");
const primitives = @import("primitives.zig");
const reporting = @import("reporting.zig");
const file_utils = @import("file_utils.zig");
const fmt_print = @import("fmt_print.zig");

const Value = types.Value;
const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

const is_wasm = @import("builtin").os.tag == .wasi;

/// Largest file `fmt` will touch. Formatting is whole-file, so an oversized
/// source is rejected rather than partially processed.
const max_file_bytes: usize = 8 * 1024 * 1024;

// ── CST ───────────────────────────────────────────────────────────────────

pub const NodeKind = enum {
    /// A datum atom kept verbatim: symbol, number, string, character, boolean,
    /// `|piped symbol|`, `#t`/`#f`, a datum-label reference `#3#`, or a lone `.`.
    atom,
    /// A parenthesised list `( … )` or a vector/bytevector `#( … )` / `#u8( … )`.
    /// `text` is the opening delimiter; the close is always `)`.
    list,
    /// A reader prefix glued to exactly one following datum: `'`, `` ` ``, `,`,
    /// `,@`, or a datum-label definition `#3=`. `children[0]` is the datum.
    prefix,
    /// `#;` datum comment: `children[0]` is the commented-out (but preserved)
    /// datum. It contributes no datum to a read of the program.
    datum_comment,
    /// A `; …` line comment (text excludes the trailing newline).
    line_comment,
    /// A `#| … |#` block comment (text is verbatim, may span lines).
    block_comment,
};

pub const Node = struct {
    kind: NodeKind,
    /// Verbatim source for atoms/comments; the opening delimiter for lists;
    /// the prefix characters for prefixes; `"#;"` for datum comments.
    text: []const u8 = "",
    /// List elements (may include interspersed comments); the single target of
    /// a prefix or datum comment; empty for atoms and comments.
    children: []Node = &.{},
    /// Number of newlines in the whitespace immediately preceding this node's
    /// first lexeme. 0 = same line as the previous lexeme; ≥2 = a blank line
    /// separated them. Drives trailing-vs-leading comment placement and
    /// blank-line grouping; ordinary code layout is otherwise reflowed.
    newlines_before: u32 = 0,
    /// A `#(` / `#u8(` literal, whose first element is data, never an operator.
    is_data: bool = false,
    /// Memoised inline width (see `fmt_print`), so fit checks stay linear.
    inline_width: ?usize = null,
    width_computed: bool = false,
};

pub const ParseError = error{
    UnterminatedList,
    UnterminatedString,
    UnterminatedBlockComment,
    UnexpectedRightParen,
    DanglingPrefix,
    NestingTooDeep,
    OutOfMemory,
};

const max_nesting: u32 = 1024;

// ── Lexer ───────────────────────────────────────────────────────────────────

const TokKind = enum {
    lparen,
    rparen,
    list_open, // "#(" or "#u8("
    atom,
    prefix, // ' ` , ,@ #N=
    datum_comment, // #;
    line_comment,
    block_comment,
    eof,
};

const Tok = struct {
    kind: TokKind,
    text: []const u8,
    newlines_before: u32,
};

const Lexer = struct {
    src: []const u8,
    pos: usize = 0,

    fn isSpace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0c;
    }

    /// A boundary between atoms. Mirrors `reader.Reader.isDelimiter` so the
    /// formatter carves the same lexemes the real reader does.
    fn isDelimiter(c: u8) bool {
        return isSpace(c) or c == '(' or c == ')' or c == '"' or c == ';' or c == '|';
    }

    /// Consume whitespace, returning the newline count. Whitespace-only runs and
    /// blank lines are recovered from this count, not stored verbatim.
    fn skipSpace(self: *Lexer) u32 {
        var newlines: u32 = 0;
        while (self.pos < self.src.len and isSpace(self.src[self.pos])) : (self.pos += 1) {
            if (self.src[self.pos] == '\n') newlines += 1;
        }
        return newlines;
    }

    fn next(self: *Lexer) ParseError!Tok {
        const nl = self.skipSpace();
        if (self.pos >= self.src.len) return .{ .kind = .eof, .text = "", .newlines_before = nl };
        const start = self.pos;
        const c = self.src[self.pos];
        const kind: TokKind = switch (c) {
            '(' => blk: {
                self.pos += 1;
                break :blk .lparen;
            },
            ')' => blk: {
                self.pos += 1;
                break :blk .rparen;
            },
            '\'', '`' => blk: {
                self.pos += 1;
                break :blk .prefix;
            },
            ',' => blk: {
                self.pos += 1;
                if (self.pos < self.src.len and self.src[self.pos] == '@') self.pos += 1;
                break :blk .prefix;
            },
            ';' => blk: {
                while (self.pos < self.src.len and self.src[self.pos] != '\n') self.pos += 1;
                break :blk .line_comment;
            },
            '"' => blk: {
                try self.scanString();
                break :blk .atom;
            },
            '|' => blk: {
                try self.scanPipe();
                break :blk .atom;
            },
            '#' => try self.scanHash(),
            else => blk: {
                self.scanAtom();
                break :blk .atom;
            },
        };
        return .{ .kind = kind, .text = self.src[start..self.pos], .newlines_before = nl };
    }

    /// A `#`-led lexeme: block comment, datum comment, vector/bytevector open,
    /// character literal, datum-label prefix/reference, or a `#`-atom (`#t`,
    /// `#xFF`, …). `self.pos` is at the `#`.
    fn scanHash(self: *Lexer) ParseError!TokKind {
        const rest = self.src[self.pos..];
        if (rest.len >= 2 and rest[1] == '|') {
            try self.scanBlockComment();
            return .block_comment;
        }
        if (rest.len >= 2 and rest[1] == ';') {
            self.pos += 2;
            return .datum_comment;
        }
        if (rest.len >= 2 and rest[1] == '(') {
            self.pos += 2;
            return .list_open;
        }
        if (rest.len >= 4 and std.mem.eql(u8, rest[0..4], "#u8(")) {
            self.pos += 4;
            return .list_open;
        }
        // SRFI 207 string-notated bytevector #u8"...": one verbatim lexeme,
        // like the ordinary string it contains-ish -- checked before the
        // plain "#u8(" case can't apply and before falling through to
        // scanAtom, which would otherwise stop at the `"` (a delimiter)
        // and split this into two lexemes ("#u8" then a separate string).
        if (rest.len >= 4 and std.mem.eql(u8, rest[0..3], "#u8") and rest[3] == '"') {
            self.pos += 3;
            try self.scanString();
            return .atom;
        }
        if (rest.len >= 2 and rest[1] == '"') {
            try self.scanRawString();
            return .atom;
        }
        if (rest.len >= 2 and rest[1] == '\\') {
            self.scanChar();
            return .atom;
        }
        // Datum-label definition `#N=` is a prefix on the following datum; a
        // reference `#N#` is a standalone atom. Both are rare; anything else
        // `#`-led is an ordinary atom (booleans, radix/exactness numbers).
        if (rest.len >= 2 and std.ascii.isDigit(rest[1])) {
            var i: usize = 1;
            while (i < rest.len and std.ascii.isDigit(rest[i])) i += 1;
            if (i < rest.len and rest[i] == '=') {
                self.pos += i + 1;
                return .prefix;
            }
        }
        self.scanAtom();
        return .atom;
    }

    /// SRFI 267 raw string `#"X" content "X"` — one verbatim lexeme, kept
    /// byte-for-byte (newlines included; a multiline atom never inlines, see
    /// `computeMeasure`). Mirrors reader_tokens.readRawString: the delimiter X
    /// is the bytes up to the next `"`, the terminator is `"` X `"`, and no
    /// escape sequences exist. `self.pos` is at the `#`.
    fn scanRawString(self: *Lexer) ParseError!void {
        self.pos += 2; // consume `#"`
        const delim_start = self.pos;
        while (self.pos < self.src.len and self.src[self.pos] != '"') self.pos += 1;
        if (self.pos >= self.src.len) return ParseError.UnterminatedString;
        const delim = self.src[delim_start..self.pos];
        self.pos += 1; // the `"` closing the delimiter / opening the content
        while (self.pos < self.src.len) : (self.pos += 1) {
            if (self.src[self.pos] == '"' and
                self.pos + delim.len + 2 <= self.src.len and
                std.mem.eql(u8, self.src[self.pos + 1 .. self.pos + 1 + delim.len], delim) and
                self.src[self.pos + 1 + delim.len] == '"')
            {
                self.pos += delim.len + 2; // consume the whole terminator
                return;
            }
        }
        return ParseError.UnterminatedString;
    }

    fn scanAtom(self: *Lexer) void {
        // `#` dispatches specially only at a token boundary (see `scanHash`), so
        // as an interior constituent it is ordinary: this keeps `#0#` (a datum
        // label reference) and `#e#xFF` (stacked prefixes) single atoms.
        self.pos += 1;
        while (self.pos < self.src.len and !isDelimiter(self.src[self.pos])) {
            self.pos += 1;
        }
    }

    fn scanString(self: *Lexer) ParseError!void {
        self.pos += 1; // opening "
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '\\') {
                self.pos += 2; // escape: skip the escaped byte too
                continue;
            }
            self.pos += 1;
            if (c == '"') return;
        }
        return ParseError.UnterminatedString;
    }

    fn scanPipe(self: *Lexer) ParseError!void {
        self.pos += 1; // opening |
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '\\') {
                self.pos += 2;
                continue;
            }
            self.pos += 1;
            if (c == '|') return;
        }
        return ParseError.UnterminatedString;
    }

    /// `#\…` — the escaped char may itself be a delimiter (`#\(`, `#\;`, `#\ `),
    /// so consume it unconditionally; a *named* char (`#\space`, `#\x41`) then
    /// continues over its alphanumeric tail.
    fn scanChar(self: *Lexer) void {
        self.pos += 2; // #\
        if (self.pos >= self.src.len) return;
        const first = self.src[self.pos];
        if (first < 0x80) {
            self.pos += 1;
        } else {
            const seq = std.unicode.utf8ByteSequenceLength(first) catch 1;
            self.pos += @min(seq, self.src.len - self.pos);
        }
        if (std.ascii.isAlphabetic(first)) {
            while (self.pos < self.src.len and std.ascii.isAlphanumeric(self.src[self.pos])) self.pos += 1;
        }
    }

    fn scanBlockComment(self: *Lexer) ParseError!void {
        self.pos += 2; // #|
        var depth: usize = 1;
        while (self.pos + 1 < self.src.len) {
            if (self.src[self.pos] == '#' and self.src[self.pos + 1] == '|') {
                depth += 1;
                self.pos += 2;
            } else if (self.src[self.pos] == '|' and self.src[self.pos + 1] == '#') {
                depth -= 1;
                self.pos += 2;
                if (depth == 0) return;
            } else {
                self.pos += 1;
            }
        }
        return ParseError.UnterminatedBlockComment;
    }
};

// ── Parser ───────────────────────────────────────────────────────────────────

const Parser = struct {
    lexer: Lexer,
    arena: std.mem.Allocator,
    depth: u32 = 0,

    fn take(self: *Parser) ParseError!Tok {
        return self.lexer.next();
    }

    /// Parse the whole program: a sequence of top-level nodes until EOF.
    fn parseProgram(self: *Parser) ParseError![]Node {
        var out: std.ArrayList(Node) = .empty;
        while (true) {
            const tok = try self.take();
            if (tok.kind == .eof) break;
            if (tok.kind == .rparen) return ParseError.UnexpectedRightParen;
            const node = try self.nodeFromTok(tok);
            try out.append(self.arena, node);
        }
        return out.toOwnedSlice(self.arena);
    }

    /// Parse list elements until the matching `)`.
    fn parseList(self: *Parser, open: Tok, is_data: bool) ParseError!Node {
        if (self.depth >= max_nesting) return ParseError.NestingTooDeep;
        self.depth += 1;
        defer self.depth -= 1;

        var out: std.ArrayList(Node) = .empty;
        while (true) {
            const tok = try self.take();
            switch (tok.kind) {
                .eof => return ParseError.UnterminatedList,
                .rparen => break,
                else => try out.append(self.arena, try self.nodeFromTok(tok)),
            }
        }
        return .{
            .kind = .list,
            .text = open.text,
            .children = try out.toOwnedSlice(self.arena),
            .newlines_before = open.newlines_before,
            .is_data = is_data,
        };
    }

    /// Build a node from an already-taken token, recursing for lists and for the
    /// single datum a prefix / datum comment binds to.
    fn nodeFromTok(self: *Parser, tok: Tok) ParseError!Node {
        switch (tok.kind) {
            .lparen => return self.parseList(tok, false),
            .list_open => return self.parseList(tok, true),
            .atom, .line_comment, .block_comment => return .{
                .kind = switch (tok.kind) {
                    .line_comment => .line_comment,
                    .block_comment => .block_comment,
                    else => .atom,
                },
                // Trailing whitespace inside a line comment is invisible and
                // never part of a datum; strip it so the output has no trailing
                // spaces. Block comment and atom text stays byte-for-byte.
                .text = if (tok.kind == .line_comment)
                    std.mem.trimEnd(u8, tok.text, " \t")
                else
                    tok.text,
                .newlines_before = tok.newlines_before,
            },
            .prefix, .datum_comment => {
                const target = try self.parsePrefixTarget();
                const child = try self.arena.alloc(Node, 1);
                child[0] = target;
                return .{
                    .kind = if (tok.kind == .prefix) .prefix else .datum_comment,
                    .text = if (tok.kind == .datum_comment) "#;" else tok.text,
                    .children = child,
                    .newlines_before = tok.newlines_before,
                };
            },
            .eof, .rparen => unreachable, // handled by callers
        }
    }

    /// The datum a prefix binds to. A prefix immediately followed by a comment
    /// (rather than a datum) is degenerate; binding to it verbatim keeps the CST
    /// simple, and the round-trip check catches any resulting divergence.
    fn parsePrefixTarget(self: *Parser) ParseError!Node {
        const tok = try self.take();
        return switch (tok.kind) {
            .eof, .rparen => ParseError.DanglingPrefix,
            else => self.nodeFromTok(tok),
        };
    }
};

/// Parse `source` into a top-level CST node sequence. Caller owns nothing —
/// everything is arena-allocated.
pub fn parse(arena: std.mem.Allocator, source: []const u8) ParseError![]Node {
    var p = Parser{ .lexer = .{ .src = source }, .arena = arena };
    return p.parseProgram();
}

// ── Public formatting API ────────────────────────────────────────────────────

/// Format `source` into a fresh, canonical string (arena-allocated). Does *not*
/// verify semantic preservation — callers that write to disk must go through
/// `formatFile`, which does.
pub fn formatSource(arena: std.mem.Allocator, source: []const u8) ParseError![]u8 {
    const nodes = try parse(arena, source);
    return fmt_print.print(arena, nodes);
}

/// True when `original` and `formatted` read to `equal?` datum sequences. This
/// is the safety net: layout must never change the program a reader sees. Any
/// read failure on either side (or a length/element mismatch) returns false, so
/// the caller refuses to write.
pub fn verifyRoundTrip(gc: *memory.GC, original: []const u8, formatted: []const u8) bool {
    const roots_base = gc.extra_roots.items.len;
    defer gc.extra_roots.shrinkRetainingCapacity(roots_base);

    var orig_list: std.ArrayList(Value) = .empty;
    defer orig_list.deinit(gc.allocator);
    if (!readAllRooted(gc, original, &orig_list)) return false;

    var fmt_list: std.ArrayList(Value) = .empty;
    defer fmt_list.deinit(gc.allocator);
    if (!readAllRooted(gc, formatted, &fmt_list)) return false;

    if (orig_list.items.len != fmt_list.items.len) return false;
    for (orig_list.items, fmt_list.items) |a, b| {
        if (!primitives.deepEqual(a, b)) return false;
    }
    return true;
}

/// Read every datum from `source`, appending to `out` and mirroring each into
/// `gc.extra_roots` so a later read's allocations cannot collect earlier datums.
/// Returns false on any read error.
fn readAllRooted(gc: *memory.GC, source: []const u8, out: *std.ArrayList(Value)) bool {
    var r = reader_mod.Reader.init(gc, source);
    defer r.deinit();
    while (r.hasMore() catch return false) {
        const datum = r.readDatum() catch return false;
        out.append(gc.allocator, datum) catch return false;
        gc.extra_roots.append(gc.allocator, datum) catch return false;
    }
    return true;
}

// ── CLI entry ────────────────────────────────────────────────────────────────

pub const Options = struct {
    check: bool = false,
    files: []const []const u8 = &.{},
};

/// `kaappi fmt [--check] [files...]`. With no files, reads stdin and writes the
/// formatted result to stdout (`--check` instead exits nonzero if it differs).
/// Returns the process exit code.
pub fn run(gc: *memory.GC, opts: Options) u8 {
    if (opts.files.len == 0) return runStdin(gc, opts.check);

    var any_error = false;
    var any_changed = false;
    for (opts.files) |path| {
        switch (formatFile(gc, path, opts.check)) {
            .ok => {},
            .changed => any_changed = true,
            .failed => any_error = true,
        }
    }
    if (any_error) return 1;
    if (opts.check and any_changed) return 1;
    return 0;
}

const FileOutcome = enum { ok, changed, failed };

/// Format one file. In write mode, rewrites it only when the content changes and
/// the round-trip check passes. In `--check` mode, never writes; reports the path
/// if it is not already formatted.
fn formatFile(gc: *memory.GC, path: []const u8, check: bool) FileOutcome {
    const allocator = gc.allocator;

    const source = file_utils.readWholeFile(allocator, path, max_file_bytes) catch {
        reportFileError(path, "cannot read file");
        return .failed;
    };
    defer allocator.free(source);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();

    const formatted = formatSource(arena_state.allocator(), source) catch |err| {
        reportFileError(path, parseErrorMessage(err));
        return .failed;
    };

    if (!verifyRoundTrip(gc, source, formatted)) {
        reportFileError(path, "internal error: formatting would change the program; file left unchanged");
        return .failed;
    }

    if (std.mem.eql(u8, formatted, source)) return .ok;

    if (check) {
        writeStdout(path);
        writeStdout("\n");
        return .changed;
    }

    writeWholeFile(path, formatted) catch {
        reportFileError(path, "cannot write file");
        return .failed;
    };
    return .changed;
}

fn runStdin(gc: *memory.GC, check: bool) u8 {
    const allocator = gc.allocator;
    const source = readAllStdin(allocator) catch {
        writeStderr("kaappi fmt: cannot read stdin\n");
        return 1;
    };
    defer allocator.free(source);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();

    const formatted = formatSource(arena_state.allocator(), source) catch |err| {
        writeStderr("kaappi fmt: ");
        writeStderr(parseErrorMessage(err));
        writeStderr("\n");
        return 1;
    };

    if (!verifyRoundTrip(gc, source, formatted)) {
        writeStderr("kaappi fmt: internal error: formatting would change the program\n");
        return 1;
    }

    if (check) return if (std.mem.eql(u8, formatted, source)) 0 else 1;
    writeStdout(formatted);
    return 0;
}

fn parseErrorMessage(err: ParseError) []const u8 {
    return switch (err) {
        ParseError.UnterminatedList => "syntax error: unterminated list",
        ParseError.UnterminatedString => "syntax error: unterminated string or |symbol|",
        ParseError.UnterminatedBlockComment => "syntax error: unterminated block comment",
        ParseError.UnexpectedRightParen => "syntax error: unexpected ')'",
        ParseError.DanglingPrefix => "syntax error: quote/unquote with no datum",
        ParseError.NestingTooDeep => "syntax error: nesting too deep",
        ParseError.OutOfMemory => "out of memory",
    };
}

fn reportFileError(path: []const u8, msg: []const u8) void {
    writeStderr("kaappi fmt: ");
    writeStderr(path);
    writeStderr(": ");
    writeStderr(msg);
    writeStderr("\n");
}

fn writeWholeFile(path: []const u8, bytes: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    var buf: [std.posix.PATH_MAX]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const fd = platform.openWriteTrunc(buf[0..path.len :0], 0o644) catch |err| return err;
    defer _ = platform.close(fd);
    reporting.writeToFd(fd, bytes);
}

fn readAllStdin(allocator: std.mem.Allocator) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = platform.read(0, &tmp, tmp.len);
        if (raw == 0) break;
        if (raw < 0) {
            if (platform.errno(raw) == .INTR) continue;
            return error.ReadFailed;
        }
        const n: usize = @intCast(raw);
        if (result.items.len + n > max_file_bytes) return error.StreamTooLong;
        try result.appendSlice(allocator, tmp[0..n]);
    }
    return result.toOwnedSlice(allocator);
}

test {
    _ = @import("tests_fmt.zig");
}
