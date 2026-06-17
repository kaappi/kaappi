const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;
const Token = reader_mod.Token;

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
        } else if ((c == 'e' or c == 'E') and !has_exp) {
            has_exp = true;
            self.pos += 1;
            if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                self.pos += 1;
            }
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
        if (self.pos < self.source.len and self.source[self.pos] == 'i' and
            (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
        {
            self.pos += 1;
            const real = std.fmt.parseFloat(f64, num_str) catch return ReadError.InvalidNumber;
            const imag: f64 = if (self.source[imag_start] == '+') 1.0 else -1.0;
            return .{ .complex = .{ .real = real, .imag = imag } };
        }
        // Parse imaginary magnitude
        var imag_has_dot = false;
        var imag_has_exp = false;
        while (self.pos < self.source.len) {
            const ic = self.source[self.pos];
            if (std.ascii.isDigit(ic)) {
                self.pos += 1;
            } else if (ic == '.' and !imag_has_dot and !imag_has_exp) {
                imag_has_dot = true;
                self.pos += 1;
            } else if ((ic == 'e' or ic == 'E') and !imag_has_exp) {
                imag_has_exp = true;
                self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-'))
                    self.pos += 1;
            } else break;
        }
        // Must end with 'i'
        if (self.pos < self.source.len and self.source[self.pos] == 'i') {
            self.pos += 1;
            const real = std.fmt.parseFloat(f64, num_str) catch return ReadError.InvalidNumber;
            const imag_str = self.source[imag_start..self.pos - 1];
            const imag = std.fmt.parseFloat(f64, imag_str) catch return ReadError.InvalidNumber;
            return .{ .complex = .{ .real = real, .imag = imag } };
        }
        // Not a complex literal — backtrack
        self.pos = imag_start;
    }
    // Check for pure imaginary: just "i" suffix (e.g., "2i")
    if (self.pos < self.source.len and self.source[self.pos] == 'i' and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
    {
        self.pos += 1;
        const imag = std.fmt.parseFloat(f64, num_str) catch return ReadError.InvalidNumber;
        return .{ .complex = .{ .real = 0.0, .imag = imag } };
    }

    if (has_dot or has_exp) {
        const f = std.fmt.parseFloat(f64, num_str) catch return ReadError.InvalidNumber;
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
            return .{ .rational = .{ .num = n, .den = den } };
        }
        return .{ .fixnum = n };
    }
}

/// If fold_case is active, lowercase the symbol text using token_buf
/// and check for special float literals on the folded text.
/// Returns the (possibly folded) symbol token.
pub fn foldAndReturnSymbol(self: *Reader, sym_text: []const u8) ReadError!Token {
    if (self.fold_case) {
        self.token_buf.clearRetainingCapacity();
        for (sym_text) |ch| {
            self.token_buf.append(self.gc.allocator, std.ascii.toLower(ch)) catch return ReadError.OutOfMemory;
        }
        const folded = self.token_buf.items;
        // Check special floats on folded text
        if (std.mem.eql(u8, folded, "+inf.0")) return .{ .flonum = std.math.inf(f64) };
        if (std.mem.eql(u8, folded, "-inf.0")) return .{ .flonum = -std.math.inf(f64) };
        if (std.mem.eql(u8, folded, "+nan.0")) return .{ .flonum = std.math.nan(f64) };
        if (std.mem.eql(u8, folded, "-nan.0")) return .{ .flonum = std.math.nan(f64) };
        return .{ .symbol = folded };
    }
    // Check special floats on original text
    if (std.mem.eql(u8, sym_text, "+inf.0")) return .{ .flonum = std.math.inf(f64) };
    if (std.mem.eql(u8, sym_text, "-inf.0")) return .{ .flonum = -std.math.inf(f64) };
    if (std.mem.eql(u8, sym_text, "+nan.0")) return .{ .flonum = std.math.nan(f64) };
    if (std.mem.eql(u8, sym_text, "-nan.0")) return .{ .flonum = std.math.nan(f64) };
    return .{ .symbol = sym_text };
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
        'b' => {
            self.pos += 1;
            return readIntegerWithRadix(self, 2);
        },
        'o' => {
            self.pos += 1;
            return readIntegerWithRadix(self, 8);
        },
        'x' => {
            self.pos += 1;
            return readIntegerWithRadix(self, 16);
        },
        'd' => {
            self.pos += 1;
            return readNumber(self);
        },
        'e' => {
            self.pos += 1;
            const tok = try readNumber(self);
            return switch (tok) {
                .fixnum => tok,
                .rational => tok, // rationals are already exact
                .flonum => |f| .{ .fixnum = @intFromFloat(f) },
                else => ReadError.InvalidNumber,
            };
        },
        'i' => {
            self.pos += 1;
            const tok = try readNumber(self);
            return switch (tok) {
                .flonum => tok,
                .fixnum => |n| .{ .flonum = @floatFromInt(n) },
                .rational => |r| .{ .flonum = @as(f64, @floatFromInt(r.num)) / @as(f64, @floatFromInt(r.den)) },
                else => ReadError.InvalidNumber,
            };
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

