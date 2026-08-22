const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const unicode = @import("unicode_tables.zig");
const Value = types.Value;

pub const ReadError = error{
    UnexpectedEof,
    UnexpectedChar,
    UnexpectedRightParen,
    InvalidNumber,
    InvalidCharacterName,
    UnterminatedString,
    InvalidEscape,
    DotNotInList,
    OutOfMemory,
    NestingTooDeep,
    TokenTooLong,
};

/// Detail message for a read error that needs more than the diagnostics
/// registry's bare template -- e.g. echoing the offending token. Mirrors the
/// compiler's `syntax_error_detail` (compiler.zig, KEP-0005/#1504); threadlocal
/// for the same reason (reading can happen on any thread). `Reader.nextToken`
/// resets this at the start of every call -- the reader's single token-dispatch
/// entry point, including the nested calls `skipWhitespaceAndCommentsChecked`
/// makes for `#;`-datum comments -- so a stale detail from an earlier,
/// unrelated token can never be misattributed to a later error (kaappi#1723).
pub threadlocal var read_error_detail: [256]u8 = [_]u8{0} ** 256;
pub threadlocal var read_error_detail_len: usize = 0;

pub fn getReadErrorDetail() []const u8 {
    return read_error_detail[0..read_error_detail_len];
}

/// Clear the channel. Called by a reporter after consuming a detail, mirroring
/// `compiler.resetCompileErrorSpan` -- defensive belt-and-suspenders alongside
/// the per-token reset in `nextToken`.
pub fn resetReadErrorDetail() void {
    read_error_detail_len = 0;
}

/// A token longer than the buffer overflows this on a pathologically long
/// malformed identifier (the format string embeds it twice); rather than
/// trusting `bufPrint`'s failure case to mean "the whole buffer holds valid
/// output" (it doesn't specify how much of a partial write landed), build the
/// writer directly and read back exactly how much it actually wrote -- same
/// pattern as `compiler.formatSyntaxError`. The result is a cleanly truncated
/// prefix of the intended message, never a partially-overwritten buffer.
fn setReadErrorDetail(comptime fmt: []const u8, args: anytype) void {
    var w: std.Io.Writer = .fixed(&read_error_detail);
    w.print(fmt, args) catch {};
    read_error_detail_len = w.buffered().len;
}

pub const Token = union(enum) {
    lparen,
    rparen,
    dot,
    quote,
    backquote,
    comma,
    comma_at,
    hash_lparen,
    hash_u8_lparen,
    boolean: bool,
    fixnum: i64,
    flonum: f64,
    string: []const u8,
    /// SRFI 207 string-notated bytevector literal, #u8"...": already-
    /// decoded raw bytes (escapes resolved), ready for allocBytevector.
    bytevector_bytes: []const u8,
    symbol: []const u8,
    character: u21,
    datum_label_def: u32,
    datum_label_ref: u32,
    bignum_str: struct { str: []const u8, radix: u8 },
    rational: struct { num: i64, den: i64 },
    /// Rational literal whose numerator or denominator overflows i64.
    /// Digit runs are parsed as bignums at datum construction.
    big_rational: struct { num_str: []const u8, den_str: []const u8, radix: u8 },
    /// Number body carrying an explicit #e/#i prefix (str = the body span,
    /// prefixes already consumed). Converted at datum construction through
    /// the same digit-exact parseNumberText that backs string->number, so
    /// the two parsers cannot diverge on exactness (R7RS 6.2.7, #1911).
    prefixed_real: struct { str: []const u8, exact: bool, radix: u8 },
    /// A complex literal's two component Values (fixnum/bignum/rational for
    /// exact components, flonum for decimals/exponents/inf/nan). Components
    /// are built digit-exactly by the scanner — never through f64 — so
    /// 2^53+1 and friends survive reading (kaappi#2166). The values are
    /// rooted in `Reader.complex_root` until the datum constructor converts
    /// the token.
    complex: struct { real: Value, imag: Value },
    eof,
};

pub const Reader = struct {
    source: []const u8,
    pos: usize = 0,
    gc: *memory.GC,
    token_buf: std.ArrayList(u8),
    fold_case: bool = false,
    mark_immutable: bool = true,
    labels: [32]?Value = .{null} ** 32,
    source_name: []const u8 = "<input>",
    depth: u32 = 0,
    /// True when `source` is a possibly-truncated prefix of a longer input:
    /// the incremental `read` path (primitives_io.readDatumFn) parses a
    /// growing buffer chunk by chunk, refilling on `UnexpectedEof`. In this
    /// mode a scan that stops at end-of-slice — rather than at a delimiter
    /// or a closing character — must report `UnexpectedEof`: never finalize
    /// a token more bytes could extend, and never reject one more bytes
    /// could complete (kaappi#1893/#1920/#1940/#1945). Whole-input parses
    /// (file loading, string ports, the final parse at fd EOF) leave it
    /// false and keep the precise error kinds.
    incomplete_input: bool = false,
    /// False for a parse whose data is thrown away — the REPL's
    /// input-completeness probe (`repl.inputIncomplete`) reads the pending
    /// buffer only to learn whether it is truncated, then discards every datum
    /// it built. `source_spans` is keyed on heap pointers and is never pruned
    /// (it lives as long as the GC), so recording spans for values that are
    /// garbage before the next collection grows the table for nothing and
    /// leaves keys that a recycled object can later alias.
    record_spans: bool = true,
    /// Set when a `#!` directive was consumed. The incremental `read` loop
    /// must not discard a buffer that held one the way it discards pure
    /// whitespace/comments: a directive carries state (fold-case) forward,
    /// and every refill re-parses the buffer from scratch with a fresh
    /// Reader, so the directive's bytes have to stay in the buffer.
    saw_directive: bool = false,
    /// GC root slots for the component Values of a complex number being
    /// scanned (kaappi#2166): the scanner builds the exact real and imaginary
    /// parts digit-exactly one after the other, so the first must stay
    /// reachable across the second's allocation. Rooted only for the duration
    /// of one number's tokenization by `beginComplexRootScope`/
    /// `endComplexRootScope` (reader_tokens.zig) — pushed at the tokenizer
    /// entry and popped on its exit, strictly nested within the balanced
    /// list/datum roots the reader stacks around each element (kaappi#2283).
    /// `complex_roots_pushed` marks the scope open, so the nested
    /// readNumberPrefixed→readNumber pair opens it exactly once.
    complex_root: [2]Value = .{ types.NIL, types.NIL },
    complex_roots_pushed: bool = false,

    pub const MAX_NESTING_DEPTH = 1024;
    pub const MAX_BLOCK_COMMENT_DEPTH = 256;
    pub const MAX_TOKEN_BYTES = 64 * 1024;

    pub fn init(gc: *memory.GC, source: []const u8) Reader {
        return .{
            .source = source,
            .gc = gc,
            .token_buf = .empty,
        };
    }

    pub fn initWithName(gc: *memory.GC, source: []const u8, name: []const u8) Reader {
        var r = init(gc, source);
        r.source_name = name;
        return r;
    }

    /// Compute line and column from the current position by scanning from the
    /// start of the source. O(n) per call but only used on error paths and
    /// datum boundaries, not every character advance.
    pub fn getLineCol(self: *Reader) struct { line: u32, col: u32 } {
        var line: u32 = 1;
        var col: u32 = 1;
        for (self.source[0..self.pos]) |c| {
            if (c == '\n') {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
        }
        return .{ .line = line, .col = col };
    }

    /// Record the source span of a just-read datum in the GC's span side-table,
    /// keyed on the datum's heap pointer. Only heap objects with stable identity
    /// (pairs, vectors) can be keyed — interned symbols and immediate atoms
    /// share representations and cannot. `start_pos` is the byte offset of the
    /// datum's first character (captured before reading); `self.pos` is one past
    /// its last character. A single scan from source start to `self.pos` yields
    /// both endpoints in 1-based `(line, col)` (kaappi#1506).
    pub fn recordSpan(self: *Reader, val: Value, start_pos: usize) void {
        if (!self.record_spans) return;
        if (!types.isPair(val) and !types.isVector(val)) return;
        const end_pos = self.pos;
        var line: u32 = 1;
        var col: u32 = 1;
        var start_line: u32 = 1;
        var start_col: u32 = 1;
        var i: usize = 0;
        while (i < end_pos and i < self.source.len) : (i += 1) {
            if (i == start_pos) {
                start_line = line;
                start_col = col;
            }
            if (self.source[i] == '\n') {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
        }
        if (start_pos >= end_pos) {
            start_line = line;
            start_col = col;
        }
        self.gc.source_spans.put(val, .{
            .line = start_line,
            .col = start_col,
            .end_line = line,
            .end_col = col,
        }) catch {};
    }

    pub fn deinit(self: *Reader) void {
        // The complex-component roots are scoped to a single number's
        // tokenization now (kaappi#2283, beginComplexRootScope), so they are
        // always balanced by the time deinit runs — no root to pop here.
        self.token_buf.deinit(self.gc.allocator);
    }

    fn peek(self: *Reader) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn advance(self: *Reader) ?u8 {
        if (self.pos >= self.source.len) return null;
        const c = self.source[self.pos];
        self.pos += 1;
        return c;
    }

    /// True when the current position is at end-of-slice while more input
    /// may still follow — the point where a token scan cannot be finalized
    /// or rejected yet (see `incomplete_input`).
    pub fn truncatedHere(self: *const Reader) bool {
        return self.incomplete_input and self.pos >= self.source.len;
    }

    fn ensureTokenSpace(self: *Reader, extra: usize) ReadError!void {
        if (self.token_buf.items.len + extra > MAX_TOKEN_BYTES) {
            return ReadError.TokenTooLong;
        }
    }

    fn appendTokenByte(self: *Reader, byte: u8) ReadError!void {
        try self.ensureTokenSpace(1);
        self.token_buf.append(self.gc.allocator, byte) catch return ReadError.OutOfMemory;
    }

    fn appendTokenSlice(self: *Reader, slice: []const u8) ReadError!void {
        try self.ensureTokenSpace(slice.len);
        self.token_buf.appendSlice(self.gc.allocator, slice) catch return ReadError.OutOfMemory;
    }

    pub fn skipWhitespaceAndCommentsChecked(self: *Reader) ReadError!void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else if (c == ';') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
                // A line comment cut off by end-of-slice may continue in the
                // next chunk; resuming there after a refill would feed the
                // comment's tail to the datum stream as code (#1940).
                if (self.truncatedHere()) return ReadError.UnexpectedEof;
            } else if (c == '#' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == ';') {
                self.pos += 2;
                _ = try self.readDatum();
            } else if (c == '#' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '|') {
                self.pos += 2;
                try self.skipBlockComment();
            } else {
                break;
            }
        }
    }

    fn skipBlockComment(self: *Reader) ReadError!void {
        var depth: usize = 1;
        while (depth > 0 and self.pos + 1 < self.source.len) {
            if (self.source[self.pos] == '#' and self.source[self.pos + 1] == '|') {
                if (depth >= MAX_BLOCK_COMMENT_DEPTH) return ReadError.NestingTooDeep;
                depth += 1;
                self.pos += 2;
            } else if (self.source[self.pos] == '|' and self.source[self.pos + 1] == '#') {
                depth -= 1;
                self.pos += 2;
            } else {
                self.pos += 1;
            }
        }
        if (depth > 0) return ReadError.UnexpectedEof;
    }

    pub fn isUnicodeLetter(cp: u21) bool {
        if (cp <= 127) return std.ascii.isAlphabetic(@intCast(cp));
        return unicode.inRanges(&unicode.alphabetic_ranges, cp);
    }

    fn isUnicodeSubsequent(cp: u21) bool {
        if (cp <= 127) {
            const c: u8 = @intCast(cp);
            return isSubsequent(c);
        }
        return isUnicodeLetter(cp);
    }

    pub fn isDelimiter(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r' or
            c == '(' or c == ')' or c == '"' or c == ';' or c == '|';
    }

    fn isInitial(c: u8) bool {
        return std.ascii.isAlphabetic(c) or isSpecialInitial(c);
    }

    fn isSpecialInitial(c: u8) bool {
        return switch (c) {
            '!', '$', '%', '&', '*', '/', ':', '<', '=', '>', '?', '@', '^', '_', '~' => true,
            else => false,
        };
    }

    fn isSubsequent(c: u8) bool {
        return isInitial(c) or std.ascii.isDigit(c) or isSpecialSubsequent(c);
    }

    fn isSpecialSubsequent(c: u8) bool {
        return c == '+' or c == '-' or c == '.' or c == '@';
    }

    pub fn nextToken(self: *Reader) ReadError!Token {
        read_error_detail_len = 0;
        try self.skipWhitespaceAndCommentsChecked();
        if (self.pos >= self.source.len) return .eof;

        const c = self.source[self.pos];
        switch (c) {
            '(' => {
                self.pos += 1;
                return .lparen;
            },
            ')' => {
                self.pos += 1;
                return .rparen;
            },
            '\'' => {
                self.pos += 1;
                return .quote;
            },
            '`' => {
                self.pos += 1;
                return .backquote;
            },
            ',' => {
                self.pos += 1;
                if (self.peek() == @as(u8, '@')) {
                    self.pos += 1;
                    return .comma_at;
                }
                return .comma;
            },
            '"' => return self.readString(),
            '#' => return self.readHash(),
            '+', '-' => {
                if (self.pos + 1 < self.source.len) {
                    const n1 = self.source[self.pos + 1];
                    if (std.ascii.isDigit(n1)) return self.readNumber();
                    // Sign followed by a leading-dot decimal, e.g. -.1 or +.5
                    if (n1 == '.' and self.pos + 2 < self.source.len and
                        std.ascii.isDigit(self.source[self.pos + 2]))
                    {
                        return self.readNumber();
                    }
                    // Imaginary unit: +i / -i (but not +inf.0, +identifier)
                    if ((n1 == 'i' or n1 == 'I') and
                        (self.pos + 2 >= self.source.len or isDelimiter(self.source[self.pos + 2])))
                    {
                        return self.readNumber();
                    }
                }
                // Check for peculiar identifiers: +, -, +inf.0, -inf.0, etc.
                return self.readSymbol();
            },
            '.' => {
                if (self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
                    return self.readNumber();
                }
                if (self.pos + 1 >= self.source.len) {
                    // "." as the slice's last byte is undecidable while more
                    // input may follow: it could be a pair dot, ".5", or
                    // "..." (#1920's DotNotInList case).
                    if (self.incomplete_input) return ReadError.UnexpectedEof;
                    self.pos += 1;
                    return .dot;
                }
                if (isDelimiter(self.source[self.pos + 1])) {
                    self.pos += 1;
                    return .dot;
                }
                // Could be ... or .symbol
                return self.readSymbol();
            },
            '0'...'9' => return self.readNumber(),
            '|' => return self.readQuotedSymbol(),
            else => {
                if (isInitial(c)) {
                    return self.readSymbol();
                }
                // Check for Unicode identifier start (multi-byte UTF-8)
                if (c >= 0x80) {
                    const seq_len = std.unicode.utf8ByteSequenceLength(c) catch return ReadError.UnexpectedChar;
                    if (self.pos + seq_len > self.source.len) {
                        // A codepoint whose bytes straddle the end of the
                        // slice is a truncation, not bad UTF-8 (#1945).
                        if (self.incomplete_input) return ReadError.UnexpectedEof;
                        return ReadError.UnexpectedChar;
                    }
                    const cp = std.unicode.utf8Decode(self.source[self.pos .. self.pos + seq_len]) catch return ReadError.UnexpectedChar;
                    if (isUnicodeLetter(cp)) {
                        return self.readUnicodeSymbol();
                    }
                    return ReadError.UnexpectedChar;
                }
                return ReadError.UnexpectedChar;
            },
        }
    }

    const reader_tokens = @import("reader_tokens.zig");
    const reader_datum = @import("reader_datum.zig");

    fn readNumber(self: *Reader) ReadError!Token {
        const start = self.pos;
        const tok = try reader_tokens.readNumber(self);
        // A numeric token whose scan stopped only because the slice ended
        // may be a prefix of a longer literal ("1" of "12", "3." of "3.5").
        if (self.truncatedHere()) return ReadError.UnexpectedEof;
        if (self.pos < self.source.len and !isDelimiter(self.source[self.pos])) {
            // Only reclassify when the character actually glued onto the number
            // could continue an identifier (`<subsequent>`, ASCII or Unicode) --
            // `3-state`, `5foo`, `1.2.3` are malformed number literals, since
            // R7RS identifiers can never begin with a digit (kaappi#1723). A
            // character that ISN'T a valid identifier continuation either --
            // e.g. the backtick in `3\``, or a stray comma -- is unrelated to
            // that rule and stays the original, accurate UnexpectedChar: an
            // "identifiers cannot begin with a digit" hint would be nonsensical
            // for it, and consumeGluedIdentifierChars would consume nothing
            // anyway, leaving the message describing the number alone as if
            // that were the problem.
            const glued_start = self.pos;
            consumeGluedIdentifierChars(self);
            // Glue running to end-of-slice can't be judged yet: "1e" may be
            // the prefix of the valid "1e5", not a malformed identifier.
            if (self.truncatedHere()) return ReadError.UnexpectedEof;
            if (self.pos == glued_start) return ReadError.UnexpectedChar;
            // Consume the rest of the token so the message can echo it in full,
            // then rewind to the token's start so the reported position is the
            // start of the bad token, not wherever the number scan stopped.
            setReadErrorDetail(
                "invalid number literal '{s}': identifiers cannot begin with a digit; use |{s}| for a literal symbol",
                .{ self.source[start..self.pos], self.source[start..self.pos] },
            );
            self.pos = start;
            return ReadError.InvalidNumber;
        }
        return tok;
    }

    /// Consume the R7RS `<subsequent>` characters (ASCII or Unicode, matching
    /// `readSymbol`'s identifier scan) glued onto an already-parsed number
    /// token. Only called right before raising `InvalidNumber` for such a
    /// token, purely so its full text can be echoed in the diagnostic
    /// (kaappi#1723).
    fn consumeGluedIdentifierChars(self: *Reader) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c < 0x80) {
                if (isSubsequent(c)) {
                    self.pos += 1;
                } else {
                    break;
                }
            } else {
                const seq_len = std.unicode.utf8ByteSequenceLength(c) catch break;
                if (self.pos + seq_len > self.source.len) break;
                const cp = std.unicode.utf8Decode(self.source[self.pos .. self.pos + seq_len]) catch break;
                if (isUnicodeSubsequent(cp)) {
                    self.pos += seq_len;
                } else {
                    break;
                }
            }
        }
    }

    fn foldAndReturnSymbol(self: *Reader, sym_text: []const u8) ReadError!Token {
        return reader_tokens.foldAndReturnSymbol(self, sym_text);
    }

    fn readSymbol(self: *Reader) ReadError!Token {
        const start = self.pos;
        const first = self.source[self.pos];

        if (first == '+' or first == '-') {
            self.pos += 1;
            // Bare + or - is a valid symbol
            if (self.pos >= self.source.len or isDelimiter(self.source[self.pos])) {
                return self.foldAndReturnSymbol(self.source[start..self.pos]);
            }
            // +i, -i, peculiar identifiers with sign subsequent
            if (isInitial(self.source[self.pos]) or isSpecialSubsequent(self.source[self.pos])) {
                while (self.pos < self.source.len and isSubsequent(self.source[self.pos])) {
                    self.pos += 1;
                }
                const sym_text = self.source[start..self.pos];
                return self.foldAndReturnSymbol(sym_text);
            }
            return self.foldAndReturnSymbol(self.source[start..self.pos]);
        }

        if (first == '.') {
            self.pos += 1;
            // Must be ... or .subsequent
            while (self.pos < self.source.len and isSubsequent(self.source[self.pos])) {
                self.pos += 1;
            }
            return self.foldAndReturnSymbol(self.source[start..self.pos]);
        }

        // Regular identifier (may include Unicode subsequent chars)
        while (self.pos < self.source.len) {
            const sc = self.source[self.pos];
            if (sc < 0x80) {
                if (isSubsequent(sc)) {
                    self.pos += 1;
                } else {
                    break;
                }
            } else {
                const seq_len = std.unicode.utf8ByteSequenceLength(sc) catch break;
                if (self.pos + seq_len > self.source.len) {
                    // Mid-codepoint truncation: ending the symbol here would
                    // split it and leave stray lead bytes behind (#1945).
                    if (self.incomplete_input) return ReadError.UnexpectedEof;
                    break;
                }
                const scp = std.unicode.utf8Decode(self.source[self.pos .. self.pos + seq_len]) catch break;
                if (isUnicodeSubsequent(scp)) {
                    self.pos += seq_len;
                } else {
                    break;
                }
            }
        }
        return self.foldAndReturnSymbol(self.source[start..self.pos]);
    }

    /// Read a symbol that starts with a Unicode (multi-byte) character.
    /// The source bytes are used directly as the symbol name since they are
    /// already valid UTF-8.
    fn readUnicodeSymbol(self: *Reader) ReadError!Token {
        const start = self.pos;
        // Consume the first multi-byte character (already validated by caller)
        const first_len = std.unicode.utf8ByteSequenceLength(self.source[self.pos]) catch 1;
        self.pos += first_len;
        // Continue consuming subsequent characters (ASCII or Unicode)
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c < 0x80) {
                // ASCII byte: check if it's a valid subsequent character
                if (isSubsequent(c)) {
                    self.pos += 1;
                } else {
                    break;
                }
            } else {
                // Multi-byte UTF-8: decode and check
                const seq_len = std.unicode.utf8ByteSequenceLength(c) catch break;
                if (self.pos + seq_len > self.source.len) {
                    // Mid-codepoint truncation, as in readSymbol (#1945).
                    if (self.incomplete_input) return ReadError.UnexpectedEof;
                    break;
                }
                const cp = std.unicode.utf8Decode(self.source[self.pos .. self.pos + seq_len]) catch break;
                if (isUnicodeSubsequent(cp)) {
                    self.pos += seq_len;
                } else {
                    break;
                }
            }
        }
        const sym_text = self.source[start..self.pos];
        if (sym_text.len > MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
        return self.foldAndReturnSymbol(sym_text);
    }

    fn readQuotedSymbol(self: *Reader) ReadError!Token {
        self.pos += 1; // skip |
        self.token_buf.clearRetainingCapacity();
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '|') {
                self.pos += 1;
                return .{ .symbol = self.token_buf.items };
            }
            if (c == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 1;
                const escaped = self.source[self.pos];
                switch (escaped) {
                    '|' => try self.appendTokenByte('|'),
                    '\\' => try self.appendTokenByte('\\'),
                    'x' => {
                        // \xNN; hex scalar value escape
                        self.pos += 1;
                        const hex_start = self.pos;
                        while (self.pos < self.source.len and self.source[self.pos] != ';') {
                            self.pos += 1;
                        }
                        if (self.pos >= self.source.len) {
                            // The terminating ';' may be in the next chunk.
                            if (self.incomplete_input) return ReadError.UnexpectedEof;
                            return ReadError.InvalidEscape;
                        }
                        const hex_str = self.source[hex_start..self.pos];
                        const cp = std.fmt.parseInt(u21, hex_str, 16) catch return ReadError.InvalidEscape;
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch return ReadError.InvalidEscape;
                        try self.appendTokenSlice(buf[0..len]);
                        // pos now points at ';', will be advanced by the outer loop
                    },
                    'a' => try self.appendTokenByte(0x07),
                    'b' => try self.appendTokenByte(0x08),
                    'n' => try self.appendTokenByte('\n'),
                    'r' => try self.appendTokenByte('\r'),
                    't' => try self.appendTokenByte('\t'),
                    '"' => try self.appendTokenByte('"'),
                    else => {
                        try self.appendTokenByte(escaped);
                    },
                }
            } else {
                try self.appendTokenByte(c);
            }
            self.pos += 1;
        }
        return ReadError.UnexpectedEof;
    }

    fn readString(self: *Reader) ReadError!Token {
        self.pos += 1; // skip opening "
        self.token_buf.clearRetainingCapacity();
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '"') {
                self.pos += 1;
                return .{ .string = self.token_buf.items };
            }
            if (c == '\\') {
                self.pos += 1;
                if (self.pos >= self.source.len) {
                    if (self.incomplete_input) return ReadError.UnexpectedEof;
                    return ReadError.UnterminatedString;
                }
                const esc = self.source[self.pos];
                switch (esc) {
                    'n' => try self.appendTokenByte('\n'),
                    'r' => try self.appendTokenByte('\r'),
                    't' => try self.appendTokenByte('\t'),
                    'a' => try self.appendTokenByte(0x07),
                    'b' => try self.appendTokenByte(0x08),
                    '"' => try self.appendTokenByte('"'),
                    '\\' => try self.appendTokenByte('\\'),
                    '|' => try self.appendTokenByte('|'),
                    'x' => {
                        self.pos += 1;
                        const hex_start = self.pos;
                        while (self.pos < self.source.len and self.source[self.pos] != ';') {
                            self.pos += 1;
                        }
                        if (self.pos >= self.source.len) {
                            // The terminating ';' may be in the next chunk.
                            if (self.incomplete_input) return ReadError.UnexpectedEof;
                            return ReadError.InvalidEscape;
                        }
                        const hex_str = self.source[hex_start..self.pos];
                        const cp = std.fmt.parseInt(u21, hex_str, 16) catch return ReadError.InvalidEscape;
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch return ReadError.InvalidEscape;
                        try self.appendTokenSlice(buf[0..len]);
                        // pos now points at ';', will be advanced below
                    },
                    '\n' => {
                        // Line continuation: skip whitespace after newline
                        self.pos += 1;
                        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
                            self.pos += 1;
                        }
                        continue;
                    },
                    '\r' => {
                        self.pos += 1;
                        if (self.pos < self.source.len and self.source[self.pos] == '\n') self.pos += 1;
                        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
                            self.pos += 1;
                        }
                        continue;
                    },
                    ' ', '\t' => {
                        // Skip whitespace before newline
                        self.pos += 1;
                        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
                            self.pos += 1;
                        }
                        if (self.pos < self.source.len and (self.source[self.pos] == '\n' or self.source[self.pos] == '\r')) {
                            if (self.source[self.pos] == '\r') self.pos += 1;
                            if (self.pos < self.source.len and self.source[self.pos] == '\n') self.pos += 1;
                            while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
                                self.pos += 1;
                            }
                            continue;
                        }
                        // The line continuation's newline may be in the next
                        // chunk; only a real non-newline byte is an error.
                        if (self.truncatedHere()) return ReadError.UnexpectedEof;
                        return ReadError.InvalidEscape;
                    },
                    else => return ReadError.InvalidEscape,
                }
            } else {
                try self.appendTokenByte(c);
            }
            self.pos += 1;
        }
        if (self.incomplete_input) return ReadError.UnexpectedEof;
        return ReadError.UnterminatedString;
    }

    fn readHash(self: *Reader) ReadError!Token {
        return reader_tokens.readHash(self);
    }

    fn readCharacter(self: *Reader) ReadError!Token {
        return reader_tokens.readCharacter(self);
    }

    pub fn readDatum(self: *Reader) ReadError!Value {
        return reader_datum.readDatum(self);
    }

    /// readDatum, but a clean end of input (only whitespace, comments, or
    /// `#!` directives left) yields null instead of UnexpectedEof — the
    /// distinction `read` needs to return the EOF object rather than raise.
    pub fn readDatumOrEof(self: *Reader) ReadError!?Value {
        return reader_datum.readDatumOrEof(self);
    }

    pub fn hasMore(self: *Reader) ReadError!bool {
        try self.skipWhitespaceAndCommentsChecked();
        return self.pos < self.source.len;
    }
};

// ---------------------------------------------------------------------------
// Convenience
// ---------------------------------------------------------------------------

pub fn readString(gc: *memory.GC, source: []const u8) ReadError!Value {
    var reader = Reader.init(gc, source);
    defer reader.deinit();
    return reader.readDatum();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const printer = @import("printer.zig");

fn readAndPrint(gc: *memory.GC, input: []const u8) ![]u8 {
    const val = try readString(gc, input);
    return printer.valueToString(gc.allocator, val, .write);
}

fn readAndDisplay(gc: *memory.GC, input: []const u8) ![]u8 {
    const val = try readString(gc, input);
    return printer.valueToString(gc.allocator, val, .display);
}

test "read integers" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "42");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("42", s);
}

test "read negative integer" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "-7");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("-7", s);
}

test "read booleans" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const t = try readAndPrint(&gc, "#t");
    defer testing.allocator.free(t);
    try testing.expectEqualStrings("#t", t);

    const f = try readAndPrint(&gc, "#false");
    defer testing.allocator.free(f);
    try testing.expectEqualStrings("#f", f);
}

test "read symbol" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "hello");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("hello", s);
}

test "read list" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "(1 2 3)");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("(1 2 3)", s);
}

test "read nested list" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "(+ 1 (* 2 3))");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("(+ 1 (* 2 3))", s);
}

test "read dotted pair" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "(1 . 2)");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("(1 . 2)", s);
}

test "read quote" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "'foo");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("(quote foo)", s);
}

test "read string" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "\"hello world\"");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("\"hello world\"", s);
}

test "read raw string with empty delimiter" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // #""abc""  ->  abc
    const s = try readAndDisplay(&gc, "#\"\"abc\"\"");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("abc", s);
}

test "read raw string does not interpret escapes" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // #""a\nb""  ->  literal backslash-n, four characters, no newline.
    const disp = try readAndDisplay(&gc, "#\"\"a\\nb\"\"");
    defer testing.allocator.free(disp);
    try testing.expectEqualStrings("a\\nb", disp);

    // write mode round-trips the backslash as an escaped backslash.
    const wr = try readAndPrint(&gc, "#\"\"a\\nb\"\"");
    defer testing.allocator.free(wr);
    try testing.expectEqualStrings("\"a\\\\nb\"", wr);
}

test "read raw string with custom delimiter and embedded quotes" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // #"end"he said "hi""end"  ->  he said "hi"
    const s = try readAndDisplay(&gc, "#\"end\"he said \"hi\"\"end\"");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("he said \"hi\"", s);
}

test "read raw string content may embed the delimiter char" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // #"xx"a"x"b"xx"  ->  a"x"b  (leftmost "xx" terminator wins)
    const s = try readAndDisplay(&gc, "#\"xx\"a\"x\"b\"xx\"");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("a\"x\"b", s);
}

test "read raw string preserves newlines verbatim" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // #"|"a<newline>b"|"  ->  a<newline>b
    const s = try readAndDisplay(&gc, "#\"|\"a\nb\"|\"");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("a\nb", s);
}

test "read raw string errors on missing terminator" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // Content never closed by the terminating `""`.
    try testing.expectError(ReadError.UnterminatedString, readString(&gc, "#\"\"abc"));
    // Delimiter never closed by a `"`.
    try testing.expectError(ReadError.UnterminatedString, readString(&gc, "#\"abc"));
}

test "read empty list" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "()");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("()", s);
}

test "read character" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "#\\a");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("#\\a", s);

    const s2 = try readAndPrint(&gc, "#\\space");
    defer testing.allocator.free(s2);
    try testing.expectEqualStrings("#\\space", s2);
}

test "skip line comment" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "; this is a comment\n42");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("42", s);
}

test "fold-case directive lowercases symbols" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "#!fold-case FOO");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("foo", s);
}

test "no-fold-case restores normal casing" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // Read two datums: first folded, second not
    var reader_inst = Reader.init(&gc, "#!fold-case ABC #!no-fold-case DEF");
    defer reader_inst.deinit();

    const val1 = try reader_inst.readDatum();
    const s1 = try printer.valueToString(testing.allocator, val1, .write);
    defer testing.allocator.free(s1);
    try testing.expectEqualStrings("abc", s1);

    const val2 = try reader_inst.readDatum();
    const s2 = try printer.valueToString(testing.allocator, val2, .write);
    defer testing.allocator.free(s2);
    try testing.expectEqualStrings("DEF", s2);
}

test "datum label define and reference" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "(#0=(a b) #0#)");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("((a b) (a b))", s);
}

test "datum label forward reference in list" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const s = try readAndPrint(&gc, "(#0=42 #0#)");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("(42 42)", s);
}

test "prefixed numeric tokens require a trailing delimiter" {
    // #1929: readNumberPrefixed bypassed the delimiter check that the
    // un-prefixed path gets from the Reader.readNumber wrapper, so every
    // radix/exactness-prefixed spelling silently split "#b1p4" into the
    // fixnum 1 plus the symbol p4.  One check in readNumberPrefixed now
    // guards them all, and string->number agrees on every cell.  #2243
    // then accepted the R7RS <complex R> spellings (#x1/2+3i, #x1+2i)
    // that the guard had turned into errors: they are valid numbers and
    // now read whole again -- but only with radix-valid digits and a
    // clean delimiter.
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // A glued tail is a read error in every prefix family.
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#b1p4"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#o1e3"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#d1a"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#e34zz"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#i7q"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x1p4z"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x1/2z"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#e#b12"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#b#e12"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#b101foo"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x1zzz"));
    // Radix complex tails are R7RS-valid, but only with radix-valid digits
    // and a clean delimiter: an invalid digit, a missing i, or a glued
    // tail still errors (#2243).
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#b1+2i"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#o1+8i"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x1+2"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x1+2iz"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x3i"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#xi"));
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x3/4i"));
    // A 64-bit bignum real with a complex tail reads digit-exactly now.
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "#x99999999999999999999+2iz"));
    const big4 = try readAndPrint(&gc, "#x99999999999999999999+2i");
    defer testing.allocator.free(big4);
    try testing.expectEqualStrings("725355491768777504823705+2i", big4);
    // Components are Values now, so a component that does not round-trip
    // through f64 (2^53+1, a 64-bit hex bignum) reads digit-exactly instead
    // of erroring -- the #2182/#2243 gates dissolved with the f64
    // representation (kaappi#2166).
    const big = try readAndPrint(&gc, "#x20000000000001+2i");
    defer testing.allocator.free(big);
    try testing.expectEqualStrings("9007199254740993+2i", big);
    const big2 = try readAndPrint(&gc, "9007199254740993+2i");
    defer testing.allocator.free(big2);
    try testing.expectEqualStrings("9007199254740993+2i", big2);
    const big3 = try readAndPrint(&gc, "9007199254740993i");
    defer testing.allocator.free(big3);
    try testing.expectEqualStrings("+9007199254740993i", big3);

    // A whole list holding one is a read error too, never a longer list.
    try testing.expectError(ReadError.InvalidNumber, readString(&gc, "(#b1p4)"));

    // Valid prefixed spellings still read: hex floats, rationals, complex
    // with a decimal prefix, separators, and two-prefix combinations.
    const f = try readAndPrint(&gc, "#x1p4");
    defer testing.allocator.free(f);
    try testing.expectEqualStrings("16.0", f);

    const r = try readAndPrint(&gc, "#x1/2");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("1/2", r);

    const c = try readAndPrint(&gc, "#d1+2i");
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("1+2i", c);

    // Radix-prefixed complex reads whole and exact (R7RS <complex R>,
    // #2243) -- the same spellings that pre-#1929 silently split.
    const rx = try readAndPrint(&gc, "#x1/2+3i");
    defer testing.allocator.free(rx);
    try testing.expectEqualStrings("1/2+3i", rx);

    const rx2 = try readAndPrint(&gc, "#x1+2i");
    defer testing.allocator.free(rx2);
    try testing.expectEqualStrings("1+2i", rx2);

    const rb = try readAndPrint(&gc, "#b1+1i");
    defer testing.allocator.free(rb);
    try testing.expectEqualStrings("1+1i", rb);

    // The bare-sign pure imaginary is grammar in every radix (`+ i`), and
    // string->number agrees; the signless `#xi` spelling is not grammar.
    const rpi = try readAndPrint(&gc, "#x+i");
    defer testing.allocator.free(rpi);
    try testing.expectEqualStrings("+i", rpi);

    // `+ <ureal R> i`: a signed pure imaginary with an explicit magnitude
    // is also grammar in every radix (Chez reads #x+3i as 0+3i).
    const rpi2 = try readAndPrint(&gc, "#x+3i");
    defer testing.allocator.free(rpi2);
    try testing.expectEqualStrings("+3i", rpi2);

    const rpi3 = try readAndPrint(&gc, "#x+3/4i");
    defer testing.allocator.free(rpi3);
    try testing.expectEqualStrings("+3/4i", rpi3);

    // The imaginary marker is case-insensitive in both parsers.
    const rupper = try readAndPrint(&gc, "#x1+2I");
    defer testing.allocator.free(rupper);
    try testing.expectEqualStrings("1+2i", rupper);

    // Exact-flagged magnitudes beyond 2^53 that ARE representable (1e19 =
    // 5^19*2^19, 45 bits) still round-trip.
    const rbig = try readAndPrint(&gc, "#e1e19+1i");
    defer testing.allocator.free(rbig);
    try testing.expectEqualStrings("10000000000000000000+1i", rbig);

    const u = try readAndPrint(&gc, "#x1_f");
    defer testing.allocator.free(u);
    try testing.expectEqualStrings("31", u);

    const exact = try readAndPrint(&gc, "#e#x1p4");
    defer testing.allocator.free(exact);
    try testing.expectEqualStrings("16", exact);
}
