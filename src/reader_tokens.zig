const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;
const Token = reader_mod.Token;

/// Exponent markers accepted in decimal reals. R7RS only requires `e`; the
/// short/single/double/long markers (s/f/d/l) are a common extension and are
/// normalized to `e` before parsing.
fn isExpMarker(c: u8) bool {
    return switch (c) {
        'e', 'E', 's', 'S', 'f', 'F', 'd', 'D', 'l', 'L' => true,
        else => false,
    };
}

/// Parse a decimal real, translating any non-`e` exponent marker to `e` so the
/// standard float parser accepts it. The token contains at most one such marker
/// (the scanner stops at any other letter), so a blanket replacement is safe.
fn parseDecimalReal(s: []const u8) ?f64 {
    // Handle rationals like "1/2", "+3/4", "-5/6"
    for (s, 0..) |ch, idx| {
        if (ch == '/' and idx > 0 and idx < s.len - 1) {
            const num = std.fmt.parseInt(i64, s[0..idx], 10) catch return null;
            const den = std.fmt.parseInt(i64, s[idx + 1 ..], 10) catch return null;
            if (den == 0) return null;
            return @as(f64, @floatFromInt(num)) / @as(f64, @floatFromInt(den));
        }
    }
    var buf: [128]u8 = undefined;
    if (s.len <= buf.len) {
        var changed = false;
        for (s, 0..) |ch, i| {
            if (isExpMarker(ch) and ch != 'e' and ch != 'E') {
                buf[i] = 'e';
                changed = true;
            } else {
                buf[i] = ch;
            }
        }
        if (changed) return std.fmt.parseFloat(f64, buf[0..s.len]) catch null;
    }
    return std.fmt.parseFloat(f64, s) catch null;
}

pub fn readNumber(self: *Reader) ReadError!Token {
    const start = self.pos;
    if (self.source[self.pos] == '+' or self.source[self.pos] == '-') {
        self.pos += 1;
    }
    var has_dot = false;
    var has_exp = false;
    while (self.pos < self.source.len) {
        const c = self.source[self.pos];
        if (std.ascii.isDigit(c)) {
            self.pos += 1;
        } else if (c == '.' and !has_dot and !has_exp) {
            has_dot = true;
            self.pos += 1;
        } else if (isExpMarker(c) and !has_exp and self.pos > start) {
            // An exponent marker only applies after at least one mantissa
            // character and must be followed by an optional sign and digits.
            const after = self.pos + 1;
            const sign = after < self.source.len and (self.source[after] == '+' or self.source[after] == '-');
            const digit_at = if (sign) after + 1 else after;
            if (digit_at >= self.source.len or !std.ascii.isDigit(self.source[digit_at])) break;
            has_exp = true;
            self.pos = digit_at;
        } else {
            break;
        }
    }
    const num_str = self.source[start..self.pos];

    // Check for complex literal: real+imagi or real-imagi
    if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
        const imag_start = self.pos;
        self.pos += 1; // skip +/-
        // Check for just +i or -i (imaginary unit)
        const real_exact = !has_dot and !has_exp;
        if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
            (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
        {
            self.pos += 1;
            const real = parseDecimalReal(num_str) orelse return ReadError.InvalidNumber;
            const imag: f64 = if (self.source[imag_start] == '+') 1.0 else -1.0;
            return .{ .complex = .{ .real = real, .imag = imag, .exact_real = real_exact, .exact_imag = true } };
        }
        // Parse imaginary magnitude (decimal, rational, or with exponent)
        var imag_has_dot = false;
        var imag_has_exp = false;
        var imag_has_slash = false;
        while (self.pos < self.source.len) {
            const ic = self.source[self.pos];
            if (std.ascii.isDigit(ic)) {
                self.pos += 1;
            } else if (ic == '.' and !imag_has_dot and !imag_has_exp and !imag_has_slash) {
                imag_has_dot = true;
                self.pos += 1;
            } else if (ic == '/' and !imag_has_slash and !imag_has_dot and !imag_has_exp) {
                imag_has_slash = true;
                self.pos += 1;
            } else if (isExpMarker(ic) and !imag_has_exp and !imag_has_slash) {
                imag_has_exp = true;
                self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-'))
                    self.pos += 1;
            } else break;
        }
        // Must end with 'i'
        if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I')) {
            self.pos += 1;
            const real = parseDecimalReal(num_str) orelse return ReadError.InvalidNumber;
            const imag_str = self.source[imag_start..self.pos - 1];
            const imag = parseDecimalReal(imag_str) orelse return ReadError.InvalidNumber;
            const imag_exact = !imag_has_dot and !imag_has_exp;
            return .{ .complex = .{ .real = real, .imag = imag, .exact_real = real_exact, .exact_imag = imag_exact } };
        }
        // Not a complex literal — backtrack
        self.pos = imag_start;
    }
    // Check for pure imaginary: just "i" suffix (e.g., "2i", "+i", "-i")
    if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
    {
        self.pos += 1;
        // A bare sign (or nothing) means a magnitude of 1, i.e. +i / -i.
        const imag = if (num_str.len == 0 or (num_str.len == 1 and (num_str[0] == '+' or num_str[0] == '-')))
            (if (num_str.len == 1 and num_str[0] == '-') @as(f64, -1.0) else @as(f64, 1.0))
        else
            parseDecimalReal(num_str) orelse return ReadError.InvalidNumber;
        const imag_exact2 = !has_dot and !has_exp;
        return .{ .complex = .{ .real = 0.0, .imag = imag, .exact_real = true, .exact_imag = imag_exact2 } };
    }

    if (has_dot or has_exp) {
        const f = parseDecimalReal(num_str) orelse return ReadError.InvalidNumber;
        return .{ .flonum = f };
    } else {
        const n = std.fmt.parseInt(i64, num_str, 10) catch |err| {
            if (err == error.Overflow) {
                return .{ .bignum_str = num_str };
            }
            return ReadError.InvalidNumber;
        };
        // Check for rational literal: N/D
        if (self.pos < self.source.len and self.source[self.pos] == '/' and
            self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))
        {
            self.pos += 1; // skip '/'
            const den_start = self.pos;
            while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                self.pos += 1;
            }
            const den_str = self.source[den_start..self.pos];
            const den = std.fmt.parseInt(i64, den_str, 10) catch return ReadError.InvalidNumber;
            // Check for complex after rational: 1/2+3/4i
            if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                const csave = self.pos;
                const real_val: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(den));
                self.pos += 1;
                // +i or -i
                if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
                    (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
                {
                    self.pos += 1;
                    return .{ .complex = .{ .real = real_val, .imag = if (self.source[csave] == '+') 1.0 else -1.0 } };
                }
                // Try parsing imaginary part
                const imag_start2 = csave;
                var imag_end = self.pos;
                while (imag_end < self.source.len and (std.ascii.isDigit(self.source[imag_end]) or self.source[imag_end] == '.' or self.source[imag_end] == '/')) {
                    imag_end += 1;
                }
                if (imag_end < self.source.len and (self.source[imag_end] == 'i' or self.source[imag_end] == 'I') and
                    (imag_end + 1 >= self.source.len or Reader.isDelimiter(self.source[imag_end + 1])))
                {
                    self.pos = imag_end + 1;
                    const imag_str = self.source[imag_start2..imag_end];
                    const imag_val = parseDecimalReal(imag_str) orelse {
                        self.pos = csave;
                        return .{ .rational = .{ .num = n, .den = den } };
                    };
                    return .{ .complex = .{ .real = real_val, .imag = imag_val } };
                }
                self.pos = csave;
            }
            return .{ .rational = .{ .num = n, .den = den } };
        }
        return .{ .fixnum = n };
    }
}

/// If fold_case is active, lowercase the symbol text using token_buf
/// and check for special float literals on the folded text.
/// Returns the (possibly folded) symbol token.
pub fn foldAndReturnSymbol(self: *Reader, sym_text: []const u8) ReadError!Token {
    const text = if (self.fold_case) blk: {
        self.token_buf.clearRetainingCapacity();
        for (sym_text) |ch| {
            self.token_buf.append(self.gc.allocator, std.ascii.toLower(ch)) catch return ReadError.OutOfMemory;
        }
        break :blk self.token_buf.items;
    } else sym_text;
    // Check special floats
    if (std.ascii.eqlIgnoreCase(text, "+inf.0")) return .{ .flonum = std.math.inf(f64) };
    if (std.ascii.eqlIgnoreCase(text, "-inf.0")) return .{ .flonum = -std.math.inf(f64) };
    if (std.ascii.eqlIgnoreCase(text, "+nan.0")) return .{ .flonum = std.math.nan(f64) };
    if (std.ascii.eqlIgnoreCase(text, "-nan.0")) return .{ .flonum = std.math.nan(f64) };
    // Check for complex literals with special floats: +inf.0+inf.0i etc.
    if (text.len > 2 and (text[text.len - 1] == 'i' or text[text.len - 1] == 'I')) {
        if (tryParseComplexSymbol(text)) |cpx| return .{ .complex = cpx };
    }
    return .{ .symbol = text };
}

fn tryParseSpecialFloat(s: []const u8) ?f64 {
    if (std.ascii.eqlIgnoreCase(s, "+inf.0")) return std.math.inf(f64);
    if (std.ascii.eqlIgnoreCase(s, "-inf.0")) return -std.math.inf(f64);
    if (std.ascii.eqlIgnoreCase(s, "+nan.0")) return std.math.nan(f64);
    if (std.ascii.eqlIgnoreCase(s, "-nan.0")) return std.math.nan(f64);
    return null;
}

fn tryParseComplexSymbol(text: []const u8) ?@TypeOf(@as(Token, undefined).complex) {
    const body = text[0 .. text.len - 1]; // strip trailing 'i'
    // Find the split point: last +/- that's not at position 0
    var split: ?usize = null;
    var j: usize = body.len;
    while (j > 1) {
        j -= 1;
        if (body[j] == '+' or body[j] == '-') {
            split = j;
            break;
        }
    }
    const sp = split orelse return null;
    const real_part = body[0..sp];
    const imag_part = body[sp..];
    const real = tryParseSpecialFloat(real_part) orelse parseDecimalReal(real_part) orelse return null;
    var imag: f64 = undefined;
    if (imag_part.len == 1) {
        imag = if (imag_part[0] == '+') 1.0 else -1.0;
    } else {
        imag = tryParseSpecialFloat(imag_part) orelse parseDecimalReal(imag_part) orelse return null;
    }
    return .{ .real = real, .imag = imag };
}


/// Try to read an inf/nan literal (case-insensitive) at the current position,
/// consuming it on success. These are decimal flonums regardless of any radix
/// prefix.
fn tryReadInfNan(self: *Reader) ?f64 {
    const rest = self.source[self.pos..];
    const cands = [_]struct { s: []const u8, v: f64 }{
        .{ .s = "+inf.0", .v = std.math.inf(f64) },
        .{ .s = "-inf.0", .v = -std.math.inf(f64) },
        .{ .s = "+nan.0", .v = std.math.nan(f64) },
        .{ .s = "-nan.0", .v = std.math.nan(f64) },
    };
    for (cands) |c| {
        if (rest.len >= c.s.len and std.ascii.eqlIgnoreCase(rest[0..c.s.len], c.s) and
            (rest.len == c.s.len or Reader.isDelimiter(rest[c.s.len])))
        {
            self.pos += c.s.len;
            return c.v;
        }
    }
    return null;
}

/// Apply an exactness prefix (#e / #i) to a freshly read numeric token.
fn applyExactness(tok: Token, exact: ?bool) ReadError!Token {
    const want_exact = exact orelse return tok;
    if (want_exact) {
        return switch (tok) {
            .fixnum, .rational, .bignum_str => tok,
            .flonum => |f| if (std.math.isFinite(f)) .{ .fixnum = @intFromFloat(f) } else .{ .flonum = f },
            else => ReadError.InvalidNumber,
        };
    }
    return switch (tok) {
        .flonum, .complex => tok,
        .fixnum => |n| .{ .flonum = @floatFromInt(n) },
        .rational => |r| .{ .flonum = @as(f64, @floatFromInt(r.num)) / @as(f64, @floatFromInt(r.den)) },
        else => ReadError.InvalidNumber,
    };
}

/// Read a number after an initial radix/exactness prefix has been consumed,
/// allowing one further prefix of the other kind (R7RS permits `#e#x10`,
/// `#x#i10`, etc.). Then read the body in the chosen radix and apply exactness.
fn readNumberPrefixed(self: *Reader, radix0: u8, exact0: ?bool) ReadError!Token {
    var radix = radix0;
    var exact = exact0;
    if (self.pos + 1 < self.source.len and self.source[self.pos] == '#') {
        var consumed = true;
        switch (std.ascii.toLower(self.source[self.pos + 1])) {
            'b' => radix = 2,
            'o' => radix = 8,
            'd' => radix = 10,
            'x' => radix = 16,
            'e' => exact = true,
            'i' => exact = false,
            else => consumed = false,
        }
        if (consumed) self.pos += 2;
    }

    if (tryReadInfNan(self)) |f| return applyExactness(.{ .flonum = f }, exact);

    const tok = if (radix == 10) try readNumber(self) else try readIntegerWithRadix(self, radix);
    return applyExactness(tok, exact);
}

pub fn readHash(self: *Reader) ReadError!Token {
    self.pos += 1; // skip #
    if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
    const c = self.source[self.pos];
    switch (c) {
        't' => {
            self.pos += 1;
            // Check for #true
            if (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
                const start = self.pos - 1;
                while (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
                    self.pos += 1;
                }
                const word = self.source[start..self.pos];
                if (std.mem.eql(u8, word, "true")) return .{ .boolean = true };
                return ReadError.UnexpectedChar;
            }
            return .{ .boolean = true };
        },
        'f' => {
            self.pos += 1;
            if (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
                const start = self.pos - 1;
                while (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
                    self.pos += 1;
                }
                const word = self.source[start..self.pos];
                if (std.mem.eql(u8, word, "false")) return .{ .boolean = false };
                return ReadError.UnexpectedChar;
            }
            return .{ .boolean = false };
        },
        '\\' => return readCharacter(self),
        '(' => {
            self.pos += 1;
            return .hash_lparen;
        },
        'u' => {
            // #u8( bytevector literal
            if (self.pos + 2 < self.source.len and
                self.source[self.pos + 1] == '8' and
                self.source[self.pos + 2] == '(')
            {
                self.pos += 3;
                return .hash_u8_lparen;
            }
            return ReadError.UnexpectedChar;
        },
        'b', 'B' => {
            self.pos += 1;
            return readNumberPrefixed(self, 2, null);
        },
        'o', 'O' => {
            self.pos += 1;
            return readNumberPrefixed(self, 8, null);
        },
        'x', 'X' => {
            self.pos += 1;
            return readNumberPrefixed(self, 16, null);
        },
        'd', 'D' => {
            self.pos += 1;
            return readNumberPrefixed(self, 10, null);
        },
        'e', 'E' => {
            self.pos += 1;
            return readNumberPrefixed(self, 10, true);
        },
        'i', 'I' => {
            self.pos += 1;
            return readNumberPrefixed(self, 10, false);
        },
        '!' => {
            self.pos += 1;
            const dir_start = self.pos;
            while (self.pos < self.source.len) {
                const dc = self.source[self.pos];
                if (std.ascii.isAlphabetic(dc) or dc == '-') {
                    self.pos += 1;
                } else {
                    break;
                }
            }
            const directive = self.source[dir_start..self.pos];
            if (std.mem.eql(u8, directive, "fold-case")) {
                self.fold_case = true;
            } else if (std.mem.eql(u8, directive, "no-fold-case")) {
                self.fold_case = false;
            }
            // Treated as whitespace/comment -- recurse to get next token
            return self.nextToken();
        },
        '0'...'9' => {
            // Datum labels: #N= (define) and #N# (reference)
            const label_start = self.pos;
            while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                self.pos += 1;
            }
            const label_str = self.source[label_start..self.pos];
            const label_num = std.fmt.parseInt(u32, label_str, 10) catch return ReadError.InvalidNumber;
            if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
            if (self.source[self.pos] == '=') {
                self.pos += 1;
                return .{ .datum_label_def = label_num };
            } else if (self.source[self.pos] == '#') {
                self.pos += 1;
                return .{ .datum_label_ref = label_num };
            }
            return ReadError.UnexpectedChar;
        },
        else => return ReadError.UnexpectedChar,
    }
}


pub fn readIntegerWithRadix(self: *Reader, radix: u8) ReadError!Token {
    const start = self.pos;
    // Handle optional sign
    if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
        self.pos += 1;
    }
    while (self.pos < self.source.len) {
        const rc = self.source[self.pos];
        const valid = switch (radix) {
            2 => rc == '0' or rc == '1',
            8 => rc >= '0' and rc <= '7',
            16 => std.ascii.isHex(rc),
            else => std.ascii.isDigit(rc),
        };
        if (!valid) break;
        self.pos += 1;
    }
    const num_str = self.source[start..self.pos];
    if (num_str.len == 0 or (num_str.len == 1 and (num_str[0] == '+' or num_str[0] == '-'))) return ReadError.InvalidNumber;
    const n = std.fmt.parseInt(i64, num_str, radix) catch |err| {
        if (err == error.Overflow and radix == 10) {
            return .{ .bignum_str = num_str };
        }
        return ReadError.InvalidNumber;
    };
    // Check for rational literal: N/D (within same radix)
    if (self.pos < self.source.len and self.source[self.pos] == '/') {
        const slash_pos = self.pos;
        self.pos += 1; // skip '/'
        const den_start = self.pos;
        while (self.pos < self.source.len) {
            const rc = self.source[self.pos];
            const valid = switch (radix) {
                2 => rc == '0' or rc == '1',
                8 => rc >= '0' and rc <= '7',
                16 => std.ascii.isHex(rc),
                else => std.ascii.isDigit(rc),
            };
            if (!valid) break;
            self.pos += 1;
        }
        if (self.pos > den_start) {
            const den_str = self.source[den_start..self.pos];
            const den = std.fmt.parseInt(i64, den_str, radix) catch return ReadError.InvalidNumber;
            return .{ .rational = .{ .num = n, .den = den } };
        }
        // No digits after '/', backtrack
        self.pos = slash_pos;
    }
    return .{ .fixnum = n };
}


pub fn readCharacter(self: *Reader) ReadError!Token {
    self.pos += 1; // skip backslash
    if (self.pos >= self.source.len) return ReadError.UnexpectedEof;

    const first_byte = self.source[self.pos];

    // Try named character, hex literal, or single ASCII letter
    if (std.ascii.isAlphabetic(first_byte)) {
        const start = self.pos;
        // If first char is 'x', also consume hex digits for #\xHHHH
        if (first_byte == 'x' or first_byte == 'X') {
            self.pos += 1;
            if (self.pos < self.source.len and std.ascii.isHex(self.source[self.pos])) {
                while (self.pos < self.source.len and std.ascii.isHex(self.source[self.pos])) {
                    self.pos += 1;
                }
                const hex_str = self.source[start + 1 .. self.pos];
                const cp = std.fmt.parseInt(u21, hex_str, 16) catch return ReadError.InvalidNumber;
                return .{ .character = cp };
            }
            // Just #\x alone — return 'x'
            if (self.pos >= self.source.len or !std.ascii.isAlphabetic(self.source[self.pos])) {
                return .{ .character = first_byte };
            }
        }
        while (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
            self.pos += 1;
        }
        const name = self.source[start..self.pos];
        if (name.len == 1) {
            return .{ .character = name[0] };
        }
        if (std.ascii.eqlIgnoreCase(name, "space")) return .{ .character = ' ' };
        if (std.ascii.eqlIgnoreCase(name, "newline")) return .{ .character = '\n' };
        if (std.ascii.eqlIgnoreCase(name, "tab")) return .{ .character = '\t' };
        if (std.ascii.eqlIgnoreCase(name, "return")) return .{ .character = '\r' };
        if (std.ascii.eqlIgnoreCase(name, "null")) return .{ .character = 0 };
        if (std.ascii.eqlIgnoreCase(name, "alarm")) return .{ .character = 7 };
        if (std.ascii.eqlIgnoreCase(name, "backspace")) return .{ .character = 8 };
        if (std.ascii.eqlIgnoreCase(name, "delete")) return .{ .character = 0x7F };
        if (std.ascii.eqlIgnoreCase(name, "escape")) return .{ .character = 0x1B };
        return ReadError.InvalidCharacterName;
    }

    // Multi-byte UTF-8 character (e.g., #\λ)
    if (first_byte >= 0x80) {
        const seq_len = std.unicode.utf8ByteSequenceLength(first_byte) catch {
            self.pos += 1;
            return .{ .character = first_byte };
        };
        if (self.pos + seq_len > self.source.len) return ReadError.UnexpectedEof;
        const cp = std.unicode.utf8Decode(self.source[self.pos .. self.pos + seq_len]) catch {
            self.pos += 1;
            return .{ .character = first_byte };
        };
        self.pos += seq_len;
        return .{ .character = cp };
    }

    // Single ASCII non-letter character (e.g., #\( #\) #\1 etc.)
    self.pos += 1;
    return .{ .character = first_byte };
}

const reader_datum = @import("reader_datum.zig");

