const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
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
};

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
    symbol: []const u8,
    character: u21,
    datum_label_def: u32,
    datum_label_ref: u32,
    bignum_str: []const u8,
    rational: struct { num: i64, den: i64 },
    complex: struct { real: f64, imag: f64, exact_real: bool = false, exact_imag: bool = false },
    eof,
};

pub const Reader = struct {
    source: []const u8,
    pos: usize = 0,
    gc: *memory.GC,
    token_buf: std.ArrayList(u8),
    fold_case: bool = false,
    labels: [32]?Value = .{null} ** 32,
    source_name: []const u8 = "<input>",
    depth: u32 = 0,

    pub const MAX_NESTING_DEPTH = 1024;

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

    pub fn deinit(self: *Reader) void {
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

    pub fn skipWhitespaceAndComments(self: *Reader) void {
        self.skipWhitespaceAndCommentsChecked() catch {};
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

    // Unicode letter classification for identifier support
    fn isUnicodeLetter(cp: u21) bool {
        if (cp <= 127) return std.ascii.isAlphabetic(@intCast(cp));
        if (cp >= 0xC0 and cp <= 0xFF and cp != 0xD7 and cp != 0xF7) return true;
        if (cp >= 0x100 and cp <= 0x24F) return true;
        if (cp >= 0x250 and cp <= 0x2AF) return true;
        if (cp >= 0x370 and cp <= 0x3FF) return true;
        if (cp >= 0x400 and cp <= 0x4FF) return true;
        if (cp >= 0x500 and cp <= 0x52F) return true;
        if (cp >= 0x530 and cp <= 0x58F) return true;
        if (cp >= 0x5D0 and cp <= 0x5EA) return true;
        if (cp >= 0x600 and cp <= 0x6FF) return true;
        if (cp >= 0x900 and cp <= 0x97F) return true;
        if (cp >= 0x0E01 and cp <= 0x0E3A) return true;
        if (cp >= 0x10A0 and cp <= 0x10FF) return true;
        if (cp >= 0x1100 and cp <= 0x11FF) return true;
        if (cp >= 0x3040 and cp <= 0x309F) return true;
        if (cp >= 0x30A0 and cp <= 0x30FF) return true;
        if (cp >= 0x4E00 and cp <= 0x9FFF) return true;
        if (cp >= 0xAC00 and cp <= 0xD7AF) return true;
        if (cp >= 0x3400 and cp <= 0x4DBF) return true;
        if (cp >= 0x1E00 and cp <= 0x1EFF) return true;
        if (cp >= 0x1F00 and cp <= 0x1FFF) return true;
        return false;
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
                if (self.pos + 1 >= self.source.len or isDelimiter(self.source[self.pos + 1])) {
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
                    if (self.pos + seq_len > self.source.len) return ReadError.UnexpectedChar;
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
        return reader_tokens.readNumber(self);
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
            if (isSpecialSubsequent(self.source[self.pos]) or std.ascii.isAlphabetic(self.source[self.pos])) {
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
                if (self.pos + seq_len > self.source.len) break;
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
                if (self.pos + seq_len > self.source.len) break;
                const cp = std.unicode.utf8Decode(self.source[self.pos .. self.pos + seq_len]) catch break;
                if (isUnicodeSubsequent(cp)) {
                    self.pos += seq_len;
                } else {
                    break;
                }
            }
        }
        return .{ .symbol = self.source[start..self.pos] };
    }

    fn readQuotedSymbol(self: *Reader) ReadError!Token {
        self.pos += 1; // skip |
        self.token_buf.clearRetainingCapacity();
        const alloc = self.gc.allocator;
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
                    '|' => self.token_buf.append(alloc, '|') catch return ReadError.OutOfMemory,
                    '\\' => self.token_buf.append(alloc, '\\') catch return ReadError.OutOfMemory,
                    'x' => {
                        // \xNN; hex scalar value escape
                        self.pos += 1;
                        const hex_start = self.pos;
                        while (self.pos < self.source.len and self.source[self.pos] != ';') {
                            self.pos += 1;
                        }
                        if (self.pos >= self.source.len) return ReadError.InvalidEscape;
                        const hex_str = self.source[hex_start..self.pos];
                        const cp = std.fmt.parseInt(u21, hex_str, 16) catch return ReadError.InvalidEscape;
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch return ReadError.InvalidEscape;
                        self.token_buf.appendSlice(alloc, buf[0..len]) catch return ReadError.OutOfMemory;
                        // pos now points at ';', will be advanced by the outer loop
                    },
                    'a' => self.token_buf.append(alloc, 0x07) catch return ReadError.OutOfMemory,
                    'b' => self.token_buf.append(alloc, 0x08) catch return ReadError.OutOfMemory,
                    'n' => self.token_buf.append(alloc, '\n') catch return ReadError.OutOfMemory,
                    'r' => self.token_buf.append(alloc, '\r') catch return ReadError.OutOfMemory,
                    't' => self.token_buf.append(alloc, '\t') catch return ReadError.OutOfMemory,
                    '"' => self.token_buf.append(alloc, '"') catch return ReadError.OutOfMemory,
                    else => {
                        self.token_buf.append(alloc, escaped) catch return ReadError.OutOfMemory;
                    },
                }
            } else {
                self.token_buf.append(alloc, c) catch return ReadError.OutOfMemory;
            }
            self.pos += 1;
        }
        return ReadError.UnexpectedEof;
    }

    fn readString(self: *Reader) ReadError!Token {
        self.pos += 1; // skip opening "
        self.token_buf.clearRetainingCapacity();
        const alloc = self.gc.allocator;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '"') {
                self.pos += 1;
                return .{ .string = self.token_buf.items };
            }
            if (c == '\\') {
                self.pos += 1;
                if (self.pos >= self.source.len) return ReadError.UnterminatedString;
                const esc = self.source[self.pos];
                switch (esc) {
                    'n' => self.token_buf.append(alloc, '\n') catch return ReadError.OutOfMemory,
                    'r' => self.token_buf.append(alloc, '\r') catch return ReadError.OutOfMemory,
                    't' => self.token_buf.append(alloc, '\t') catch return ReadError.OutOfMemory,
                    'a' => self.token_buf.append(alloc, 0x07) catch return ReadError.OutOfMemory,
                    'b' => self.token_buf.append(alloc, 0x08) catch return ReadError.OutOfMemory,
                    '"' => self.token_buf.append(alloc, '"') catch return ReadError.OutOfMemory,
                    '\\' => self.token_buf.append(alloc, '\\') catch return ReadError.OutOfMemory,
                    '|' => self.token_buf.append(alloc, '|') catch return ReadError.OutOfMemory,
                    'x' => {
                        self.pos += 1;
                        const hex_start = self.pos;
                        while (self.pos < self.source.len and self.source[self.pos] != ';') {
                            self.pos += 1;
                        }
                        if (self.pos >= self.source.len) return ReadError.InvalidEscape;
                        const hex_str = self.source[hex_start..self.pos];
                        const cp = std.fmt.parseInt(u21, hex_str, 16) catch return ReadError.InvalidEscape;
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch return ReadError.InvalidEscape;
                        self.token_buf.appendSlice(alloc, buf[0..len]) catch return ReadError.OutOfMemory;
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
                        return ReadError.InvalidEscape;
                    },
                    else => return ReadError.InvalidEscape,
                }
            } else {
                self.token_buf.append(alloc, c) catch return ReadError.OutOfMemory;
            }
            self.pos += 1;
        }
        return ReadError.UnterminatedString;
    }


    fn readHash(self: *Reader) ReadError!Token {
        return reader_tokens.readHash(self);
    }

    fn readIntegerWithRadix(self: *Reader, radix: u8) ReadError!Token {
        return reader_tokens.readIntegerWithRadix(self, radix);
    }

    fn readCharacter(self: *Reader) ReadError!Token {
        return reader_tokens.readCharacter(self);
    }

    pub fn readDatum(self: *Reader) ReadError!Value {
        return reader_datum.readDatum(self);
    }

    pub fn hasMore(self: *Reader) bool {
        self.skipWhitespaceAndComments();
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
