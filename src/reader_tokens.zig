const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const primitives_char = @import("primitives_char.zig");
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

/// Consume the '/' at the current position plus the following run of digits
/// valid in `radix`, returning the denominator digit slice (possibly empty).
fn scanDenominatorDigits(self: *Reader, radix: u8) []const u8 {
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
    return self.source[den_start..self.pos];
}

/// Build a big_rational token for a rational literal with an i64-overflowing
/// numerator or denominator. Unlike the fixnum rational path (which admits
/// trailing complex syntax like 1/2+3i), a bignum rational must end at a
/// delimiter — otherwise the tail would be silently read as a second datum.
fn bigRationalToken(self: *Reader, num_str: []const u8, den_str: []const u8, radix: u8) ReadError!Token {
    if (den_str.len > Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
    if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
        return ReadError.InvalidNumber;
    return .{ .big_rational = .{ .num_str = num_str, .den_str = den_str, .radix = radix } };
}

pub fn readNumber(self: *Reader) ReadError!Token {
    if (self.pos >= self.source.len) return ReadError.InvalidNumber;
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
    if (num_str.len > Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;

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
        // Check for inf.0/nan.0 as imaginary part (e.g., 3.0+inf.0i)
        const rest_after_sign = self.source[self.pos..];
        if (rest_after_sign.len >= 5) {
            const maybe_special = blk: {
                if (rest_after_sign.len >= 5 and std.ascii.eqlIgnoreCase(rest_after_sign[0..5], "inf.0"))
                    break :blk @as(?f64, std.math.inf(f64));
                if (rest_after_sign.len >= 5 and std.ascii.eqlIgnoreCase(rest_after_sign[0..5], "nan.0"))
                    break :blk @as(?f64, std.math.nan(f64));
                break :blk @as(?f64, null);
            };
            if (maybe_special) |special_val| {
                if (self.pos + 5 < self.source.len and
                    (self.source[self.pos + 5] == 'i' or self.source[self.pos + 5] == 'I') and
                    (self.pos + 6 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 6])))
                {
                    self.pos += 6; // skip inf.0i / nan.0i
                    const real = parseDecimalReal(num_str) orelse return ReadError.InvalidNumber;
                    const imag = if (self.source[imag_start] == '-') -special_val else special_val;
                    return .{ .complex = .{ .real = real, .imag = imag, .exact_real = real_exact, .exact_imag = false } };
                }
            }
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
            const imag_str = self.source[imag_start .. self.pos - 1];
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
            if (err != error.Overflow) return ReadError.InvalidNumber;
            // Numerator overflows i64: still check for a rational literal N/D
            // so bignum numerators fall back to bignum parsing in the datum
            // constructor instead of leaving '/' behind as a stray token.
            if (self.pos < self.source.len and self.source[self.pos] == '/' and
                self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))
            {
                const den_str = scanDenominatorDigits(self, 10);
                return bigRationalToken(self, num_str, den_str, 10);
            }
            return .{ .bignum_str = .{ .str = num_str, .radix = 10 } };
        };
        // Check for rational literal: N/D
        if (self.pos < self.source.len and self.source[self.pos] == '/' and
            self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))
        {
            const den_str = scanDenominatorDigits(self, 10);
            const den = std.fmt.parseInt(i64, den_str, 10) catch |err| {
                if (err == error.Overflow) return bigRationalToken(self, num_str, den_str, 10);
                return ReadError.InvalidNumber;
            };
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
                    return .{ .complex = .{ .real = real_val, .imag = if (self.source[csave] == '+') 1.0 else -1.0, .exact_real = true, .exact_imag = true } };
                }
                // Try parsing imaginary part
                const imag_start2 = csave;
                var imag_end = self.pos;
                var imag_has_dot2 = false;
                while (imag_end < self.source.len and (std.ascii.isDigit(self.source[imag_end]) or self.source[imag_end] == '.' or self.source[imag_end] == '/')) {
                    if (self.source[imag_end] == '.') imag_has_dot2 = true;
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
                    return .{ .complex = .{ .real = real_val, .imag = imag_val, .exact_real = true, .exact_imag = !imag_has_dot2 } };
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
    if (sym_text.len > Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
    const text = if (self.fold_case) blk: {
        self.token_buf.clearRetainingCapacity();
        var i: usize = 0;
        while (i < sym_text.len) {
            if (self.token_buf.items.len >= Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
            const byte = sym_text[i];
            if (byte < 0x80) {
                self.token_buf.append(self.gc.allocator, std.ascii.toLower(byte)) catch return ReadError.OutOfMemory;
                i += 1;
            } else {
                const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch {
                    self.token_buf.append(self.gc.allocator, byte) catch return ReadError.OutOfMemory;
                    i += 1;
                    continue;
                };
                if (i + seq_len > sym_text.len) {
                    self.token_buf.append(self.gc.allocator, byte) catch return ReadError.OutOfMemory;
                    i += 1;
                    continue;
                }
                const cp = std.unicode.utf8Decode(sym_text[i .. i + seq_len]) catch {
                    self.token_buf.append(self.gc.allocator, byte) catch return ReadError.OutOfMemory;
                    i += 1;
                    continue;
                };
                const folded = primitives_char.charFoldcase(cp);
                var enc_buf: [4]u8 = undefined;
                const enc_len = std.unicode.utf8Encode(folded, &enc_buf) catch {
                    self.token_buf.append(self.gc.allocator, byte) catch return ReadError.OutOfMemory;
                    i += 1;
                    continue;
                };
                self.token_buf.appendSlice(self.gc.allocator, enc_buf[0..enc_len]) catch return ReadError.OutOfMemory;
                i += seq_len;
            }
        }
        break :blk self.token_buf.items;
    } else sym_text;
    // Check special floats
    if (std.ascii.eqlIgnoreCase(text, "+inf.0")) return .{ .flonum = std.math.inf(f64) };
    if (std.ascii.eqlIgnoreCase(text, "-inf.0")) return .{ .flonum = -std.math.inf(f64) };
    if (std.ascii.eqlIgnoreCase(text, "+nan.0")) return .{ .flonum = std.math.nan(f64) };
    if (std.ascii.eqlIgnoreCase(text, "-nan.0")) return .{ .flonum = std.math.nan(f64) };
    // Pure imaginary special floats: +inf.0i, -inf.0i, +nan.0i, -nan.0i
    if (std.ascii.eqlIgnoreCase(text, "+inf.0i")) return .{ .complex = .{ .real = 0.0, .imag = std.math.inf(f64) } };
    if (std.ascii.eqlIgnoreCase(text, "-inf.0i")) return .{ .complex = .{ .real = 0.0, .imag = -std.math.inf(f64) } };
    if (std.ascii.eqlIgnoreCase(text, "+nan.0i")) return .{ .complex = .{ .real = 0.0, .imag = std.math.nan(f64) } };
    if (std.ascii.eqlIgnoreCase(text, "-nan.0i")) return .{ .complex = .{ .real = 0.0, .imag = std.math.nan(f64) } };
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
            .fixnum, .rational, .bignum_str, .big_rational => tok,
            .flonum => |f| blk: {
                if (!std.math.isFinite(f)) break :blk Token{ .flonum = f };
                const max_i64_f: f64 = @floatFromInt(@as(i64, std.math.maxInt(i64)));
                const min_i64_f: f64 = @floatFromInt(@as(i64, std.math.minInt(i64)));
                if (f > max_i64_f or f < min_i64_f) break :blk Token{ .flonum = f };
                const trunc: i64 = @intFromFloat(f);
                if (@as(f64, @floatFromInt(trunc)) == f) break :blk Token{ .fixnum = trunc };
                // Non-integer float: convert to rational via continued fraction
                var num: i64 = 1;
                var den: i64 = 0;
                var prev_num: i64 = 0;
                var prev_den: i64 = 1;
                var x = @abs(f);
                var iters: u32 = 0;
                while (iters < 64) : (iters += 1) {
                    if (x > max_i64_f) break;
                    const a: i64 = @intFromFloat(x);
                    const new_num = @mulWithOverflow(a, num);
                    if (new_num[1] != 0) break;
                    const final_num = @addWithOverflow(new_num[0], prev_num);
                    if (final_num[1] != 0) break;
                    const new_den = @mulWithOverflow(a, den);
                    if (new_den[1] != 0) break;
                    const final_den = @addWithOverflow(new_den[0], prev_den);
                    if (final_den[1] != 0) break;
                    prev_num = num;
                    prev_den = den;
                    num = final_num[0];
                    den = final_den[0];
                    const approx = @as(f64, @floatFromInt(num)) / @as(f64, @floatFromInt(den));
                    if (@abs(approx - @abs(f)) < 1e-15) break;
                    const frac = x - @as(f64, @floatFromInt(a));
                    if (frac < 1e-15) break;
                    x = 1.0 / frac;
                }
                if (f < 0) num = -num;
                if (den == 1) break :blk Token{ .fixnum = num };
                break :blk Token{ .rational = .{ .num = num, .den = den } };
            },
            .complex => |c| blk: {
                break :blk Token{ .complex = .{ .real = c.real, .imag = c.imag, .exact_real = true, .exact_imag = true } };
            },
            else => ReadError.InvalidNumber,
        };
    }
    return switch (tok) {
        .flonum, .complex => tok,
        .fixnum => |n| .{ .flonum = @floatFromInt(n) },
        .rational => |r| .{ .flonum = @as(f64, @floatFromInt(r.num)) / @as(f64, @floatFromInt(r.den)) },
        .bignum_str => |bs| .{ .flonum = std.fmt.parseFloat(f64, bs.str) catch return ReadError.InvalidNumber },
        // Like .bignum_str, only decimal digit runs can go through parseFloat.
        .big_rational => |r| blk: {
            if (r.radix != 10) return ReadError.InvalidNumber;
            const nf = std.fmt.parseFloat(f64, r.num_str) catch return ReadError.InvalidNumber;
            const df = std.fmt.parseFloat(f64, r.den_str) catch return ReadError.InvalidNumber;
            break :blk .{ .flonum = nf / df };
        },
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
                if (!std.mem.eql(u8, word, "true")) return ReadError.UnexpectedChar;
            }
            if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                return ReadError.UnexpectedChar;
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
                if (!std.mem.eql(u8, word, "false")) return ReadError.UnexpectedChar;
            }
            if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                return ReadError.UnexpectedChar;
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
    if (num_str.len > Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
    if (num_str.len == 0 or (num_str.len == 1 and (num_str[0] == '+' or num_str[0] == '-'))) return ReadError.InvalidNumber;
    const n = std.fmt.parseInt(i64, num_str, radix) catch |err| {
        if (err != error.Overflow) return ReadError.InvalidNumber;
        // Numerator overflows i64: still consume a rational N/D so the '/'
        // does not get re-tokenized as the start of a symbol.
        if (self.pos < self.source.len and self.source[self.pos] == '/') {
            const slash_pos = self.pos;
            const den_str = scanDenominatorDigits(self, radix);
            if (den_str.len > 0) return bigRationalToken(self, num_str, den_str, radix);
            self.pos = slash_pos; // no digits after '/', backtrack
        }
        return .{ .bignum_str = .{ .str = num_str, .radix = radix } };
    };
    // Check for rational literal: N/D (within same radix)
    if (self.pos < self.source.len and self.source[self.pos] == '/') {
        const slash_pos = self.pos;
        const den_str = scanDenominatorDigits(self, radix);
        if (den_str.len > 0) {
            const den = std.fmt.parseInt(i64, den_str, radix) catch |err| {
                if (err == error.Overflow) return bigRationalToken(self, num_str, den_str, radix);
                return ReadError.InvalidNumber;
            };
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
                if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) return ReadError.InvalidCharacterName;
                if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                    return ReadError.UnexpectedChar;
                return .{ .character = cp };
            }
            // Just #\x alone — return 'x'
            if (self.pos >= self.source.len or !std.ascii.isAlphabetic(self.source[self.pos])) {
                if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                    return ReadError.UnexpectedChar;
                return .{ .character = first_byte };
            }
        }
        while (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
            self.pos += 1;
        }
        const name = self.source[start..self.pos];
        if (name.len == 1) {
            if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                return ReadError.UnexpectedChar;
            return .{ .character = name[0] };
        }
        const char_val: u21 = if (std.ascii.eqlIgnoreCase(name, "space")) ' ' else if (std.ascii.eqlIgnoreCase(name, "newline")) '\n' else if (std.ascii.eqlIgnoreCase(name, "tab")) '\t' else if (std.ascii.eqlIgnoreCase(name, "return")) '\r' else if (std.ascii.eqlIgnoreCase(name, "null")) 0 else if (std.ascii.eqlIgnoreCase(name, "alarm")) 7 else if (std.ascii.eqlIgnoreCase(name, "backspace")) 8 else if (std.ascii.eqlIgnoreCase(name, "delete")) 0x7F else if (std.ascii.eqlIgnoreCase(name, "escape")) 0x1B else return ReadError.InvalidCharacterName;
        if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
            return ReadError.UnexpectedChar;
        return .{ .character = char_val };
    }

    // Multi-byte UTF-8 character (e.g., #\λ)
    if (first_byte >= 0x80) {
        const seq_len = std.unicode.utf8ByteSequenceLength(first_byte) catch {
            return ReadError.InvalidCharacterName;
        };
        if (self.pos + seq_len > self.source.len) return ReadError.UnexpectedEof;
        const cp = std.unicode.utf8Decode(self.source[self.pos .. self.pos + seq_len]) catch {
            return ReadError.InvalidCharacterName;
        };
        self.pos += seq_len;
        if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
            return ReadError.UnexpectedChar;
        return .{ .character = cp };
    }

    // Single ASCII non-letter character (e.g., #\( #\) #\1 etc.)
    self.pos += 1;
    return .{ .character = first_byte };
}

const reader_datum = @import("reader_datum.zig");
