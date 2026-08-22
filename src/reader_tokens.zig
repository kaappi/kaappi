const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const primitives_char = @import("primitives_char.zig");
const bignum = @import("bignum.zig");
const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;
const Token = reader_mod.Token;
const Value = types.Value;

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
/// SRFI 169: strips digit-separator underscores first (radix 10 -- the sign,
/// `.`, `/`, and exponent-marker characters here are never digits, so a
/// misplaced underscore next to any of them is correctly rejected the same
/// way as one between two ordinary digits that shouldn't have one).
fn parseDecimalReal(raw: []const u8) ?f64 {
    var underscore_buf: [256]u8 = undefined;
    const s = bignum.stripUnderscores(raw, 10, &underscore_buf) orelse return null;
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
/// May include SRFI-169 digit-separator underscores, unvalidated here --
/// callers hand the result to a parser that strips and validates them
/// (`parseBignumString`, or a stack-local strip before `std.fmt.parseInt`).
fn scanDenominatorDigits(self: *Reader, radix: u8) []const u8 {
    self.pos += 1; // skip '/'
    const den_start = self.pos;
    while (self.pos < self.source.len) {
        const rc = self.source[self.pos];
        const valid = rc == '_' or switch (radix) {
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

/// Root a complex token's component Values before any further allocation.
/// Open the complex-component root scope for one number's tokenization: root
/// both `complex_root` slots (NIL until a component is stored) so a heap
/// component — the imaginary part is built first on the radix-prefixed paths
/// (tryComplexTail runs before the real part) — survives the *other*
/// component's allocation, the use-after-free kaappi#2166 fixed.
///
/// The scope is bounded by the tokenizer call, NOT the Reader's lifetime
/// (kaappi#2283). Registering the roots once and popping them only at
/// `Reader.deinit` put a persistent entry into the LIFO root stack *between*
/// the balanced `pushRoot`/`popRoot` pairs `readList`/`readDatum` wrap around
/// every element: those `defer popRoot`s then popped this slot instead of
/// their own, orphaning a live list root that dangled until a later
/// collection marked it — a crash whose timing depended on GC scheduling and
/// stack contents (it surfaced only on riscv64/QEMU). Pushing at the
/// tokenizer entry and popping on its exit keeps the stack strictly nested.
///
/// Returns true when this call opened the scope. `readNumberPrefixed` calls
/// `readNumber`, so only the outer of that pair opens (and closes) it.
fn beginComplexRootScope(self: *Reader) bool {
    if (self.complex_roots_pushed) return false;
    self.complex_root = .{ types.NIL, types.NIL };
    self.complex_roots_pushed = true;
    self.gc.pushRoot(&self.complex_root[0]);
    self.gc.pushRoot(&self.complex_root[1]);
    return true;
}

fn endComplexRootScope(self: *Reader) void {
    self.gc.popRoot();
    self.gc.popRoot();
    self.complex_root = .{ types.NIL, types.NIL };
    self.complex_roots_pushed = false;
}

/// Store a complex number's real/imaginary component in the tokenizer's root
/// scope (opened by `beginComplexRootScope`), keeping it marked across the
/// other component's allocation.
fn rootComplexReal(self: *Reader, real: Value) void {
    self.complex_root[0] = real;
}

fn rootComplexImag(self: *Reader, imag: Value) void {
    self.complex_root[1] = imag;
}

/// Parse a signed radix-R integer or rational component text into an exact
/// Value (fixnum, bignum, or reduced rational), digit-exactly at any size.
/// The round-trip gates that an f64 component forced are gone: components
/// are Values, so nothing ever rounds (kaappi#2166, dissolving #2182/#2183).
/// Returns null on invalid digits or a zero denominator.
fn parseExactComponent(self: *Reader, text: []const u8, radix: u8) ?Value {
    if (std.mem.indexOfScalar(u8, text, '/')) |sp| {
        if (sp == 0 or sp + 1 >= text.len) return null;
        const num = bignum.parseBignumString(self.gc, text[0..sp], radix) catch return null;
        var slot = self.gc.rootedSlot(num) catch return null;
        defer slot.release();
        const den = bignum.parseBignumString(self.gc, text[sp + 1 ..], radix) catch return null;
        if (types.isFixnum(den) and types.toFixnum(den) == 0) return null;
        if (types.isBignum(den) and bignum.isZero(den)) return null;
        const arith = @import("primitives_arithmetic.zig");
        return arith.makeRationalReduced(self.gc, slot.get(), den) catch return null;
    }
    return bignum.parseBignumString(self.gc, text, radix) catch return null;
}

/// Build the reduced rational n/den as an exact Value (fixnum when den
/// divides num) and root it as the complex real component (kaappi#2166).
fn tryRationalComponent(self: *Reader, n: i64, den: i64) ?Value {
    const arith = @import("primitives_arithmetic.zig");
    const r = arith.makeRationalReduced(self.gc, types.makeFixnum(n), types.makeFixnum(den)) catch return null;
    rootComplexReal(self, r);
    return r;
}

/// Build an exact integer component from an i64 (fixnum, or bignum past
/// i48) through the reader's own GC — gc_instance may be unset in
/// contexts that only read (kaappi#2166).
fn exactIntComponent(self: *Reader, n: i64) ?Value {
    if (n >= std.math.minInt(i48) and n <= std.math.maxInt(i48))
        return types.makeFixnum(n);
    return self.gc.allocBignumFromI64(n) catch return null;
}

/// Complex tail after a bignum rational real part: `num/den+imag i`,
/// `num/den+i`, and the `-` twins (R7RS <complex R>), mirroring the
/// i64-rational path in `readNumber` but building the real part digit-exactly
/// as a bignum rational Value. With Value components there is no f64
/// round-trip gate, so any bignum parts are accepted (kaappi#2166). The
/// position is restored on every failure path.
fn tryComplexTailBigRational(self: *Reader, num_str: []const u8, den_str: []const u8, radix: u8) ?Token {
    if (self.pos >= self.source.len) return null;
    const next = self.source[self.pos];
    if (next != '+' and next != '-' and next != 'i' and next != 'I') return null;
    const save = self.pos;
    // The real part is the bignum rational num_str/den_str, built
    // digit-exactly (kaappi#2166).
    const num = bignum.parseBignumString(self.gc, num_str, radix) catch {
        self.pos = save;
        return null;
    };
    var slot = self.gc.rootedSlot(num) catch {
        self.pos = save;
        return null;
    };
    defer slot.release();
    const den = bignum.parseBignumString(self.gc, den_str, radix) catch {
        self.pos = save;
        return null;
    };
    if (types.isFixnum(den) and types.toFixnum(den) == 0) {
        self.pos = save;
        return null;
    }
    if (types.isBignum(den) and bignum.isZero(den)) {
        self.pos = save;
        return null;
    }
    const arith = @import("primitives_arithmetic.zig");
    const real = arith.makeRationalReduced(self.gc, slot.get(), den) catch {
        self.pos = save;
        return null;
    };
    rootComplexReal(self, real);

    // Pure imaginary with an explicit magnitude: `+ <ureal R> i` /
    // `- <ureal R> i` (R7RS <complex R>; the sign inside num_str is the
    // production marker and the signless m/2^k i is not grammar). Mirrors
    // the i64 rational path; the sign is absorbed into `real` by the parse.
    if ((next == 'i' or next == 'I') and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])) and
        num_str.len > 0 and (num_str[0] == '+' or num_str[0] == '-'))
    {
        self.pos += 1;
        rootComplexImag(self, real);
        return .{ .complex = .{ .real = types.makeFixnum(0), .imag = real } };
    }
    if (next != '+' and next != '-') return null;
    const neg = next == '-'; // sign applies to the imaginary part below

    self.pos += 1; // skip +/-
    // +i / -i: the unit imaginary.
    if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
    {
        self.pos += 1;
        const unit: Value = if (neg) types.makeFixnum(-1) else types.makeFixnum(1);
        rootComplexImag(self, unit);
        return .{ .complex = .{ .real = real, .imag = unit } };
    }
    // Imaginary magnitude: radix digits (plus '/' for N/D; '.' only in
    // radix 10) then 'i', mirroring the i64 paths. `radix` matters here:
    // readIntegerWithRadix reaches this helper with radix 2/8/16, where a
    // component is radix digits and the decimal shapes do not exist.
    const mag_start = self.pos;
    var imag_has_dot = false;
    while (self.pos < self.source.len) {
        const ic = self.source[self.pos];
        const valid_digit = ic == '_' or switch (radix) {
            2 => ic == '0' or ic == '1',
            8 => ic >= '0' and ic <= '7',
            16 => std.ascii.isHex(ic),
            else => std.ascii.isDigit(ic),
        };
        if (valid_digit) {
            self.pos += 1;
        } else if (radix == 10 and ic == '.' and !imag_has_dot) {
            imag_has_dot = true;
            self.pos += 1;
        } else if (ic == '/') {
            self.pos += 1;
        } else break;
    }
    if (self.pos == mag_start) {
        self.pos = save;
        return null;
    }
    if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
    {
        self.pos += 1;
        const imag_str = self.source[mag_start .. self.pos - 1];
        // An exact-flagged imaginary part is parsed digit-exactly (radix
        // 10 integers/rationals via parseDecimalReal's text, but as a
        // Value); a decimal part is a flonum (kaappi#2166).
        const imag = if (imag_has_dot) blk: {
            if (radix != 10) {
                self.pos = save;
                return null;
            }
            break :blk types.makeFlonum(parseDecimalReal(imag_str) orelse {
                self.pos = save;
                return null;
            });
        } else parseExactComponent(self, imag_str, radix) orelse {
            self.pos = save;
            return null;
        };
        rootComplexImag(self, imag);
        const signed_imag = if (neg) (negateComponent(self, imag) orelse {
            self.pos = save;
            return null;
        }) else imag;
        rootComplexImag(self, signed_imag);
        return .{ .complex = .{ .real = real, .imag = signed_imag } };
    }
    self.pos = save;
    return null;
}

/// Negate a component Value (fixnum/bignum/rational/flonum). The caller
/// must have rooted `v` and must root the result before the next
/// allocation (heap results are returned unrooted).
fn negateComponent(self: *Reader, v: Value) ?Value {
    if (types.isFixnum(v)) return types.makeFixnum(-types.toFixnum(v));
    if (types.isFlonum(v)) return types.makeFlonum(-types.toFlonum(v));
    if (types.isBignum(v)) return bignum.negate(self.gc, v) catch return null;
    if (types.isRationalObj(v)) {
        const r = types.toRational(v);
        const neg_num = bignum.negate(self.gc, r.numerator) catch return null;
        var slot = self.gc.rootedSlot(neg_num) catch return null;
        defer slot.release();
        const arith = @import("primitives_arithmetic.zig");
        return arith.makeRationalReduced(self.gc, slot.get(), r.denominator) catch return null;
    }
    return null;
}

/// A malformed numeric token with no delimiter between the failure point and
/// end-of-slice may be a truncated prefix of a valid literal (`3.` of `3.5`,
/// `1_` of `1_2`, `#e+in` of `#e+inf.0` — the scan can stop with unconsumed
/// bytes left, so this is a tail scan, not just pos >= len): in
/// incomplete-input mode report UnexpectedEof so the incremental reader
/// fetches more bytes instead of delivering a final verdict (#1940).
/// Identity — plain InvalidNumber — whenever a delimiter ends the token
/// within the slice or the whole input is known; deferral never loses the
/// error, because the whole-input parse at fd EOF re-judges the full token.
fn invalidNumberOrEof(self: *Reader) ReadError {
    return if (numberTailTruncated(self)) ReadError.UnexpectedEof else ReadError.InvalidNumber;
}

/// True when, in incomplete-input mode, everything from the current position
/// to end-of-slice is delimiter-free. A just-scanned numeric token followed
/// by such a tail cannot be finalized: the tail (e.g. the "+2" a backtracked
/// complex-literal attempt left behind out of a straddled "1+2i") may
/// continue in the next chunk (#1940).
fn numberTailTruncated(self: *Reader) bool {
    if (!self.incomplete_input) return false;
    var i = self.pos;
    while (i < self.source.len) : (i += 1) {
        if (Reader.isDelimiter(self.source[i])) return false;
    }
    return true;
}

pub fn readNumber(self: *Reader) ReadError!Token {
    const opened_scope = beginComplexRootScope(self);
    defer if (opened_scope) endComplexRootScope(self);
    if (self.pos >= self.source.len) return invalidNumberOrEof(self);
    const start = self.pos;
    if (self.source[self.pos] == '+' or self.source[self.pos] == '-') {
        self.pos += 1;
    }
    var has_dot = false;
    var has_exp = false;
    while (self.pos < self.source.len) {
        const c = self.source[self.pos];
        if (std.ascii.isDigit(c) or c == '_') {
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
            const real = if (real_exact) (parseExactComponent(self, num_str, 10) orelse return invalidNumberOrEof(self)) else types.makeFlonum(parseDecimalReal(num_str) orelse return invalidNumberOrEof(self));
            rootComplexReal(self, real);
            const imag: Value = if (self.source[imag_start] == '+') types.makeFixnum(1) else types.makeFixnum(-1);
            rootComplexImag(self, imag);
            return .{ .complex = .{ .real = real, .imag = imag } };
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
                    const real = if (real_exact) (parseExactComponent(self, num_str, 10) orelse return invalidNumberOrEof(self)) else types.makeFlonum(parseDecimalReal(num_str) orelse return invalidNumberOrEof(self));
                    rootComplexReal(self, real);
                    const imag_v: f64 = if (self.source[imag_start] == '-') -special_val else special_val;
                    const imag = types.makeFlonum(imag_v);
                    rootComplexImag(self, imag);
                    return .{ .complex = .{ .real = real, .imag = imag } };
                }
            }
        }
        // Parse imaginary magnitude (decimal, rational, or with exponent)
        var imag_has_dot = false;
        var imag_has_exp = false;
        var imag_has_slash = false;
        while (self.pos < self.source.len) {
            const ic = self.source[self.pos];
            if (std.ascii.isDigit(ic) or ic == '_') {
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
            const imag_str = self.source[imag_start .. self.pos - 1];
            const imag_exact = !imag_has_dot and !imag_has_exp;
            const real = if (real_exact) (parseExactComponent(self, num_str, 10) orelse return invalidNumberOrEof(self)) else types.makeFlonum(parseDecimalReal(num_str) orelse return invalidNumberOrEof(self));
            rootComplexReal(self, real);
            const imag = if (imag_exact) (parseExactComponent(self, imag_str, 10) orelse return invalidNumberOrEof(self)) else types.makeFlonum(parseDecimalReal(imag_str) orelse return invalidNumberOrEof(self));
            rootComplexImag(self, imag);
            return .{ .complex = .{ .real = real, .imag = imag } };
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
        const imag: Value = if (num_str.len == 0 or (num_str.len == 1 and (num_str[0] == '+' or num_str[0] == '-')))
            (if (num_str.len == 1 and num_str[0] == '-') types.makeFixnum(-1) else types.makeFixnum(1))
        else if (!has_dot and !has_exp)
            (parseExactComponent(self, num_str, 10) orelse return invalidNumberOrEof(self))
        else
            types.makeFlonum(parseDecimalReal(num_str) orelse return invalidNumberOrEof(self));
        const zero: Value = types.makeFixnum(0);
        rootComplexReal(self, zero);
        rootComplexImag(self, imag);
        return .{ .complex = .{ .real = zero, .imag = imag } };
    }

    if (has_dot or has_exp) {
        const f = parseDecimalReal(num_str) orelse return invalidNumberOrEof(self);
        return .{ .flonum = f };
    } else {
        // SRFI 169: strip+validate embedded digit-separator underscores
        // (the loop above tolerates but doesn't validate them) before
        // handing off to parseInt, which doesn't understand them. The
        // overflow fallbacks keep the raw slices -- bigRationalToken/
        // .bignum_str are parsed later by parseBignumString, which strips
        // internally.
        var num_strip_buf: [256]u8 = undefined;
        const clean_num_str = bignum.stripUnderscores(num_str, 10, &num_strip_buf) orelse return invalidNumberOrEof(self);
        const n = std.fmt.parseInt(i64, clean_num_str, 10) catch |err| {
            if (err != error.Overflow) return invalidNumberOrEof(self);
            // Numerator overflows i64: still check for a rational literal N/D
            // so bignum numerators fall back to bignum parsing in the datum
            // constructor instead of leaving '/' behind as a stray token.
            if (self.pos < self.source.len and self.source[self.pos] == '/' and
                self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))
            {
                const den_str = scanDenominatorDigits(self, 10);
                if (tryComplexTailBigRational(self, num_str, den_str, 10)) |tok| return tok;
                return bigRationalToken(self, num_str, den_str, 10);
            }
            return .{ .bignum_str = .{ .str = num_str, .radix = 10 } };
        };
        // Check for rational literal: N/D
        if (self.pos < self.source.len and self.source[self.pos] == '/' and
            self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))
        {
            const den_str = scanDenominatorDigits(self, 10);
            var den_strip_buf: [256]u8 = undefined;
            const clean_den_str = bignum.stripUnderscores(den_str, 10, &den_strip_buf) orelse return invalidNumberOrEof(self);
            const den = std.fmt.parseInt(i64, clean_den_str, 10) catch |err| {
                if (err == error.Overflow) {
                    if (tryComplexTailBigRational(self, num_str, den_str, 10)) |tok| return tok;
                    return bigRationalToken(self, num_str, den_str, 10);
                }
                return invalidNumberOrEof(self);
            };
            // Check for complex after rational: 1/2+3/4i
            if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                const csave = self.pos;
                self.pos += 1;
                // +i or -i
                if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
                    (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
                {
                    self.pos += 1;
                    const real = tryRationalComponent(self, n, den) orelse return invalidNumberOrEof(self);
                    const imag: Value = if (self.source[csave] == '+') types.makeFixnum(1) else types.makeFixnum(-1);
                    rootComplexImag(self, imag);
                    return .{ .complex = .{ .real = real, .imag = imag } };
                }
                // Try parsing imaginary part
                const imag_start2 = csave;
                var imag_end = self.pos;
                var imag_has_dot2 = false;
                while (imag_end < self.source.len and (std.ascii.isDigit(self.source[imag_end]) or self.source[imag_end] == '.' or self.source[imag_end] == '/' or self.source[imag_end] == '_')) {
                    if (self.source[imag_end] == '.') imag_has_dot2 = true;
                    imag_end += 1;
                }
                if (imag_end < self.source.len and (self.source[imag_end] == 'i' or self.source[imag_end] == 'I') and
                    (imag_end + 1 >= self.source.len or Reader.isDelimiter(self.source[imag_end + 1])))
                {
                    self.pos = imag_end + 1;
                    const imag_str = self.source[imag_start2..imag_end];
                    const real = tryRationalComponent(self, n, den) orelse return invalidNumberOrEof(self);
                    // imag_str carries the sign and may be an integer,
                    // rational, or (with a dot) a decimal; exact parts are
                    // built digit-exactly (kaappi#2166).
                    const imag = if (imag_has_dot2)
                        types.makeFlonum(parseDecimalReal(imag_str) orelse {
                            self.pos = csave;
                            return .{ .rational = .{ .num = n, .den = den } };
                        })
                    else
                        (parseExactComponent(self, imag_str, 10) orelse {
                            self.pos = csave;
                            return .{ .rational = .{ .num = n, .den = den } };
                        });
                    rootComplexImag(self, imag);
                    return .{ .complex = .{ .real = real, .imag = imag } };
                }
                self.pos = csave;
            }
            // Pure imaginary with an explicit magnitude: +3/4i is 0+3/4i
            // (R7RS <complex R> -> `+ <ureal R> i` | `- <ureal R> i`; the
            // sign is the production marker, and the signless 3/4i is not
            // grammar). Chez and guile read it this way too (#2243).
            if ((num_str[0] == '+' or num_str[0] == '-') and
                self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
                (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
            {
                self.pos += 1;
                const zero: Value = types.makeFixnum(0);
                rootComplexReal(self, zero);
                const arith = @import("primitives_arithmetic.zig");
                const imag = arith.makeRationalReduced(self.gc, types.makeFixnum(n), types.makeFixnum(den)) catch return invalidNumberOrEof(self);
                rootComplexImag(self, imag);
                return .{ .complex = .{ .real = zero, .imag = imag } };
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
    // A symbol scan that stopped only because the slice ended (every caller
    // otherwise stops at a delimiter or non-subsequent byte, leaving pos on
    // it) may be a prefix of a longer identifier — "zz" of "zzz", "+inf" of
    // "+inf.0". Silently finalizing here is #1940's split-symbol bug.
    if (self.truncatedHere()) return ReadError.UnexpectedEof;
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
    if (std.ascii.eqlIgnoreCase(text, "+inf.0i")) return .{ .complex = .{ .real = types.makeFixnum(0), .imag = types.makeFlonum(std.math.inf(f64)) } };
    if (std.ascii.eqlIgnoreCase(text, "-inf.0i")) return .{ .complex = .{ .real = types.makeFixnum(0), .imag = types.makeFlonum(-std.math.inf(f64)) } };
    if (std.ascii.eqlIgnoreCase(text, "+nan.0i")) return .{ .complex = .{ .real = types.makeFixnum(0), .imag = types.makeFlonum(std.math.nan(f64)) } };
    if (std.ascii.eqlIgnoreCase(text, "-nan.0i")) return .{ .complex = .{ .real = types.makeFixnum(0), .imag = types.makeFlonum(std.math.nan(f64)) } };
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
    return .{ .real = types.makeFlonum(real), .imag = types.makeFlonum(imag) };
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

/// Read a number after an initial radix/exactness prefix has been consumed,
/// allowing one further prefix of the other kind (R7RS permits `#e#x10`,
/// `#x#i10`, etc.). Then read the body in the chosen radix.
///
/// An exactness prefix is NOT applied at token level: the body span becomes
/// a `.prefixed_real` token that datum construction routes through the same
/// digit-exact `parseNumberText` behind `string->number`, so `read` cannot
/// diverge from it (R7RS 6.2.7). The old token-level conversion parsed to
/// f64 first and un-rounded with an i64 continued fraction, which panicked
/// at 2^63 (#1907), dropped `#e` past i64 (#1891), collapsed sub-1e-15
/// values to 0 (#1909), and read `#i` radix bignums as decimal (#1908).
/// The tokenizer still runs first so token-boundary and incremental-input
/// (`incomplete_input`) behavior is exactly what unprefixed numbers get.
fn readNumberPrefixed(self: *Reader, radix0: u8, exact0: ?bool) ReadError!Token {
    const opened_scope = beginComplexRootScope(self);
    defer if (opened_scope) endComplexRootScope(self);
    var radix = radix0;
    var exact = exact0;
    if (self.pos < self.source.len and self.source[self.pos] == '#') {
        if (self.pos + 1 >= self.source.len) {
            // "#e#" cut right at the second prefix's letter: the letter may
            // be in the next chunk (falls through to readNumber's own
            // InvalidNumber when the whole input is known).
            if (self.incomplete_input) return ReadError.UnexpectedEof;
        } else {
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
    }

    if (tryReadInfNan(self)) |f| {
        // "#e+inf.0" ending exactly at the slice can't be finalized: a
        // non-delimiter in the next chunk would make it a different (and
        // invalid) token, not this flonum.
        if (self.truncatedHere()) return ReadError.UnexpectedEof;
        // #e on an infinity/NaN has no exact representation: a read error,
        // matching string->number's #f on the same text (#419, #1911).
        if (exact orelse false) return ReadError.InvalidNumber;
        return .{ .flonum = f };
    }

    const body_start = self.pos;
    const tok = if (radix == 10) try readNumber(self) else try readIntegerWithRadix(self, radix);
    if (numberTailTruncated(self)) return ReadError.UnexpectedEof;
    // The token body must end at a delimiter or end of input (R7RS 7.1.1
    // terminates numbers, like identifiers, at a <delimiter>). The file-local
    // readNumber/readIntegerWithRadix do not check this -- the delimiter
    // check lives in the Reader.readNumber wrapper used only by the
    // un-prefixed path, so every prefixed spelling (`#b`, `#o`, `#d`, `#e`,
    // `#i`, `#x`, and two-prefix combinations) skipped it: `#x1p4z`, `#e34zz`
    // and `#b101foo` each read as a number plus a leftover symbol, silently
    // changing an enclosing list's length (#1929). A single check here closes
    // all 382 swept cells: tryReadInfNan already guards its own tail, the
    // radix-10 complex grammar consumes `+...i` as part of the token, and
    // readHexFloatSuffix/parseHexFloat reject malformed float bodies.
    if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
        return invalidNumberOrEof(self);
    const want_exact = exact orelse return tok;
    switch (tok) {
        // Complex tokens keep their token-level parse: readNumber's complex
        // grammar is wider than parseNumberText's (rational and inf/nan
        // parts), so re-parsing the span would reject valid literals. The
        // #e/#i prefix converts both components (a stored complex is never
        // mixed-exactness), with #e refusing non-finite parts the same way
        // the parseNumberText path does (kaappi#2166).
        .complex => |c| {
            const numeric = @import("primitives_numeric.zig");
            if (want_exact) {
                const re_nan = types.isFlonum(c.real) and !std.math.isFinite(types.toFlonum(c.real));
                const im_nan = types.isFlonum(c.imag) and !std.math.isFinite(types.toFlonum(c.imag));
                if (re_nan or im_nan) return ReadError.InvalidNumber;
                const real = numeric.exactComponentGc(self.gc, c.real) catch return ReadError.OutOfMemory;
                rootComplexReal(self, real);
                const imag = numeric.exactComponentGc(self.gc, c.imag) catch return ReadError.OutOfMemory;
                rootComplexImag(self, imag);
                return .{ .complex = .{ .real = real, .imag = imag } };
            }
            const real = numeric.inexactFn(&[1]Value{c.real}) catch return ReadError.OutOfMemory;
            rootComplexReal(self, real);
            const imag = numeric.inexactFn(&[1]Value{c.imag}) catch return ReadError.OutOfMemory;
            rootComplexImag(self, imag);
            return .{ .complex = .{ .real = real, .imag = imag } };
        },
        else => return .{ .prefixed_real = .{
            .str = self.source[body_start..self.pos],
            .exact = want_exact,
            .radix = radix,
        } },
    }
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
                // "#tru" cut mid-word may be a prefix of "#true" (#1940).
                if (self.truncatedHere()) return ReadError.UnexpectedEof;
                const word = self.source[start..self.pos];
                if (!std.mem.eql(u8, word, "true")) return ReadError.UnexpectedChar;
            }
            // Bare "#t" at end-of-slice may be "#true" cut after the t.
            if (self.truncatedHere()) return ReadError.UnexpectedEof;
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
                if (self.truncatedHere()) return ReadError.UnexpectedEof;
                const word = self.source[start..self.pos];
                if (!std.mem.eql(u8, word, "false")) return ReadError.UnexpectedChar;
            }
            if (self.truncatedHere()) return ReadError.UnexpectedEof;
            if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                return ReadError.UnexpectedChar;
            return .{ .boolean = false };
        },
        '\\' => return readCharacter(self),
        '"' => return readRawString(self), // SRFI 267 raw string: #"X"..."X"
        '(' => {
            self.pos += 1;
            return .hash_lparen;
        },
        'u' => {
            // #u8( bytevector literal, or SRFI 207's #u8"..." string-
            // notated form.
            if (self.pos + 2 < self.source.len and self.source[self.pos + 1] == '8') {
                if (self.source[self.pos + 2] == '(') {
                    self.pos += 3;
                    return .hash_u8_lparen;
                }
                if (self.source[self.pos + 2] == '"') {
                    self.pos += 2;
                    return readByteStringLiteral(self);
                }
            }
            // "#u" or "#u8" cut at end-of-slice may still become #u8( or
            // #u8" once the next chunk arrives (#1940). "#u<other>" is a
            // real error regardless of what follows.
            if (self.incomplete_input and
                (self.pos + 1 >= self.source.len or
                    (self.source[self.pos + 1] == '8' and self.pos + 2 >= self.source.len)))
                return ReadError.UnexpectedEof;
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
            self.saw_directive = true;
            const dir_start = self.pos;
            while (self.pos < self.source.len) {
                const dc = self.source[self.pos];
                if (std.ascii.isAlphabetic(dc) or dc == '-') {
                    self.pos += 1;
                } else {
                    break;
                }
            }
            // "#!fold-c" cut mid-name: judging (and ignoring) the directive
            // now would drop its effect once the rest arrives.
            if (self.truncatedHere()) return ReadError.UnexpectedEof;
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
            // Exhausting the slice mid-label is a truncation whatever the
            // digits parse to, so check before parseInt: an overflowing
            // label cut at the boundary must refill, not report a verdict.
            if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
            const label_num = std.fmt.parseInt(u32, label_str, 10) catch return ReadError.InvalidNumber;
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

/// Parse an SRFI 267 raw string literal. Called from `readHash` with `self.pos`
/// pointing at the opening `"` (the byte right after `#`). Grammar:
///
///     ⟨raw string (X)⟩ ⩴ `#"` X `"` ⟨internal⟩ `"` X `"`
///
/// where the delimiter X is any run of bytes not containing `"`, and the
/// internal content is the longest run that does not contain the terminator
/// sequence `"` X `"`. No escape sequences are interpreted — every byte between
/// the opening and terminating delimiters is copied verbatim (newlines
/// included). The byte-level scan is UTF-8-safe because `"` (0x22) never appears
/// as a continuation byte in a valid multi-byte sequence.
pub fn readRawString(self: *Reader) ReadError!Token {
    self.pos += 1; // consume opening `"`

    // Delimiter X: bytes up to the next `"`. Stopping at `"` guarantees X holds
    // no `"`, so it is always a ⟨valid delimiter⟩.
    const delim_start = self.pos;
    while (self.pos < self.source.len and self.source[self.pos] != '"') {
        self.pos += 1;
    }
    if (self.pos >= self.source.len) {
        // The delimiter's closing `"` may be in the next chunk (#1940).
        if (self.incomplete_input) return ReadError.UnexpectedEof;
        return ReadError.UnterminatedString;
    }
    const delim = self.source[delim_start..self.pos];
    self.pos += 1; // consume the `"` closing the delimiter / opening the content

    // Terminator is `"` ++ delim ++ `"`. Copy bytes until its leftmost match.
    self.token_buf.clearRetainingCapacity();
    while (self.pos < self.source.len) {
        if (self.source[self.pos] == '"' and matchesRawTerminator(self, delim)) {
            self.pos += delim.len + 2; // consume the whole terminator
            return .{ .string = self.token_buf.items };
        }
        if (self.token_buf.items.len >= Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
        self.token_buf.append(self.gc.allocator, self.source[self.pos]) catch return ReadError.OutOfMemory;
        self.pos += 1;
    }
    if (self.incomplete_input) return ReadError.UnexpectedEof;
    return ReadError.UnterminatedString;
}

/// True when the bytes at `self.pos` are the raw-string terminator `"` delim `"`.
/// The caller has already checked that `self.source[self.pos] == '"'`.
fn matchesRawTerminator(self: *Reader, delim: []const u8) bool {
    const need = delim.len + 2;
    if (self.pos + need > self.source.len) return false;
    if (!std.mem.eql(u8, self.source[self.pos + 1 .. self.pos + 1 + delim.len], delim)) return false;
    return self.source[self.pos + 1 + delim.len] == '"';
}

/// SRFI 207 string-notated bytevector: #u8"...". Deliberately a separate
/// reader from the ordinary string reader (`readString` in reader.zig),
/// not a shared/refactored one -- the grammar is similar but meaningfully
/// different in two ways the spec is explicit about: (1) a direct
/// (unescaped) byte must be printable ASCII (0x20-0x7E) other than `"`/
/// `\`; anything else, including a valid multi-byte UTF-8 character, is
/// a syntax error here (unlike ordinary strings, which accept any UTF-8
/// text directly) -- the spec's own rationale gives `#u8"\xE000;"` as
/// explicitly invalid to make this point. (2) `\xHH;` decodes to exactly
/// one raw byte value 0-255, not a Unicode codepoint UTF-8-encoded into
/// however many bytes that takes -- `\x89;` is the single byte 0x89, not
/// a UTF-8 encoding of U+0089. The other escapes (`\a \b \t \n \r \" \\
/// \|`, and the backslash-whitespace-newline-whitespace line
/// continuation) match ordinary strings exactly.
/// Advances past a run of spaces/tabs. Shared by the three
/// readByteStringLiteral line-continuation escapes below (`\<newline>`,
/// `\<return>`, and `\<space-or-tab>`), each of which skips intraline
/// whitespace at more than one point in its own handling.
fn skipIntralineWhitespace(self: *Reader) void {
    while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
        self.pos += 1;
    }
}

pub fn readByteStringLiteral(self: *Reader) ReadError!Token {
    self.pos += 1; // skip opening `"`
    self.token_buf.clearRetainingCapacity();
    while (self.pos < self.source.len) {
        const c = self.source[self.pos];
        if (c == '"') {
            self.pos += 1;
            return .{ .bytevector_bytes = self.token_buf.items };
        }
        if (c == '\\') {
            self.pos += 1;
            if (self.pos >= self.source.len) {
                if (self.incomplete_input) return ReadError.UnexpectedEof;
                return ReadError.UnterminatedString;
            }
            const esc = self.source[self.pos];
            switch (esc) {
                'n' => try appendByteStringByte(self, '\n'),
                'r' => try appendByteStringByte(self, '\r'),
                't' => try appendByteStringByte(self, '\t'),
                'a' => try appendByteStringByte(self, 0x07),
                'b' => try appendByteStringByte(self, 0x08),
                '"' => try appendByteStringByte(self, '"'),
                '\\' => try appendByteStringByte(self, '\\'),
                '|' => try appendByteStringByte(self, '|'),
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
                    const byte_val = std.fmt.parseInt(u8, hex_str, 16) catch return ReadError.InvalidEscape;
                    try appendByteStringByte(self, byte_val);
                    // pos now points at ';', advanced below
                },
                '\n' => {
                    self.pos += 1;
                    skipIntralineWhitespace(self);
                    continue;
                },
                '\r' => {
                    self.pos += 1;
                    if (self.pos < self.source.len and self.source[self.pos] == '\n') self.pos += 1;
                    skipIntralineWhitespace(self);
                    continue;
                },
                ' ', '\t' => {
                    self.pos += 1;
                    skipIntralineWhitespace(self);
                    if (self.pos < self.source.len and (self.source[self.pos] == '\n' or self.source[self.pos] == '\r')) {
                        if (self.source[self.pos] == '\r') self.pos += 1;
                        if (self.pos < self.source.len and self.source[self.pos] == '\n') self.pos += 1;
                        skipIntralineWhitespace(self);
                        continue;
                    }
                    // The line continuation's newline may be in the next
                    // chunk; only a real non-newline byte is an error.
                    if (self.truncatedHere()) return ReadError.UnexpectedEof;
                    return ReadError.InvalidEscape;
                },
                else => return ReadError.InvalidEscape,
            }
            self.pos += 1;
            continue;
        }
        // Any unescaped byte must be printable ASCII (0x20-0x7E); this
        // also correctly rejects the lead byte of any multi-byte UTF-8
        // sequence (>= 0x80), matching the spec's ASCII-only direct
        // syntax -- non-ASCII bytes must go through \x.
        if (c < 0x20 or c > 0x7E) return ReadError.UnexpectedChar;
        try appendByteStringByte(self, c);
        self.pos += 1;
    }
    if (self.incomplete_input) return ReadError.UnexpectedEof;
    return ReadError.UnterminatedString;
}

fn appendByteStringByte(self: *Reader, b: u8) ReadError!void {
    if (self.token_buf.items.len >= Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
    self.token_buf.append(self.gc.allocator, b) catch return ReadError.OutOfMemory;
}

/// If the reader is positioned at a `+`/`-` that begins a valid R7RS
/// complex tail -- `+<ureal R> i`, `+i`, or the `-` twins, i.e. the
/// `<real R> (+|-) <ureal R> i` productions of R7RS 7.1.1 -- consume it
/// and return the imaginary part. Otherwise restore the position and
/// return null so the caller's delimiter check reports the glued tail as
/// a read error rather than silently splitting the token (#2243). Radix
/// digits only: `#b1+2i` (2 is not a binary digit) still errors. Mirrors
/// the radix-10 `readNumber` complex grammar, minus the decimal/exponent
/// and inf/nan imaginary spellings that never exist in another radix.
fn tryComplexTail(self: *Reader, radix: u8) ?struct { imag: Value } {
    if (self.pos >= self.source.len) return null;
    const sign = self.source[self.pos];
    if (sign != '+' and sign != '-') return null;
    const save = self.pos;
    const neg = sign == '-';
    self.pos += 1;

    // +i / -i: the unit imaginary.
    if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
    {
        self.pos += 1;
        const unit: Value = if (neg) types.makeFixnum(-1) else types.makeFixnum(1);
        rootComplexImag(self, unit);
        return .{ .imag = unit };
    }

    // <ureal R>: radix digits (with SRFI-169 `_`), optionally /denominator.
    const mag_start = self.pos;
    while (self.pos < self.source.len) {
        const rc = self.source[self.pos];
        const valid = rc == '_' or switch (radix) {
            2 => rc == '0' or rc == '1',
            8 => rc >= '0' and rc <= '7',
            16 => std.ascii.isHex(rc),
            else => std.ascii.isDigit(rc),
        };
        if (!valid) break;
        self.pos += 1;
    }
    if (self.pos == mag_start) {
        self.pos = save; // no digits after the sign
        return null;
    }
    const mag_str = self.source[mag_start..self.pos];

    // Rational magnitude N/D.
    if (self.pos < self.source.len and self.source[self.pos] == '/') {
        const slash_pos = self.pos;
        const den_str = scanDenominatorDigits(self, radix);
        if (den_str.len > 0 and self.pos < self.source.len and
            (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
            (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
        {
            self.pos += 1; // consume the trailing i
            const mag = parseExactComponent(self, self.source[mag_start .. self.pos - 1], radix) orelse {
                self.pos = save;
                return null;
            };
            rootComplexImag(self, mag);
            const signed = if (neg) (negateComponent(self, mag) orelse {
                self.pos = save;
                return null;
            }) else mag;
            rootComplexImag(self, signed);
            return .{ .imag = signed };
        }
        self.pos = slash_pos; // not a rational tail -- fall through to integer
    }

    // Integer magnitude: the 'i' must follow the digits directly.
    if (self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
    {
        self.pos += 1;
        const mag = parseExactComponent(self, mag_str, radix) orelse {
            self.pos = save;
            return null;
        };
        rootComplexImag(self, mag);
        const signed = if (neg) (negateComponent(self, mag) orelse {
            self.pos = save;
            return null;
        }) else mag;
        rootComplexImag(self, signed);
        return .{ .imag = signed };
    }
    self.pos = save;
    return null;
}

pub fn readIntegerWithRadix(self: *Reader, radix: u8) ReadError!Token {
    const start = self.pos;
    // Handle optional sign
    if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
        self.pos += 1;
    }
    while (self.pos < self.source.len) {
        const rc = self.source[self.pos];
        const valid = rc == '_' or switch (radix) {
            2 => rc == '0' or rc == '1',
            8 => rc >= '0' and rc <= '7',
            16 => std.ascii.isHex(rc),
            else => std.ascii.isDigit(rc),
        };
        if (!valid) break;
        self.pos += 1;
    }

    // SRFI 270: hexadecimal float body/suffix -- #x1.2p3, #x9p9, #xFE.FF
    // (the "p" exponent, a power of 2, is optional; a "." fractional part
    // alone with no "p" is also a hex float, e.g. #xFE.FF). Only #x can
    // produce these -- '.'/'p' are never valid digits in any other radix,
    // so this can't misfire for #b/#o/#d.
    if (radix == 16 and self.pos < self.source.len and
        (self.source[self.pos] == '.' or self.source[self.pos] == 'p' or self.source[self.pos] == 'P'))
    {
        return readHexFloatSuffix(self, start);
    }

    const num_str = self.source[start..self.pos];
    if (num_str.len > Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
    if (num_str.len == 0) return invalidNumberOrEof(self);
    if (num_str.len == 1 and (num_str[0] == '+' or num_str[0] == '-')) {
        // A bare sign is only valid as the whole real part of the pure
        // imaginary `+i` / `-i` (R7RS <complex R> -> `+ i` | `- i`), which
        // the radix-10 path also accepts; the signless `i` spelling
        // (`#xi`) is not grammar, and neither is a bare sign followed by
        // anything else (#2243).  Chez reads `#x+i` as 0+1i too.
        if (self.pos < self.source.len and
            (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
            (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
        {
            const neg = num_str[0] == '-';
            self.pos += 1;
            const zero: Value = types.makeFixnum(0);
            const unit: Value = if (neg) types.makeFixnum(-1) else types.makeFixnum(1);
            rootComplexReal(self, zero);
            rootComplexImag(self, unit);
            return .{ .complex = .{ .real = zero, .imag = unit } };
        }
        return invalidNumberOrEof(self);
    }
    // SRFI 169: num_str/den_str may carry embedded digit-separator
    // underscores at this point (the scan loops above tolerate but don't
    // validate them); strip+validate right before parseInt, which doesn't
    // understand them. The overflow fallbacks below keep the raw (unstripped)
    // slices, since bigRationalToken/.bignum_str are parsed later by
    // parseBignumString, which strips internally.
    var num_strip_buf: [256]u8 = undefined;
    const clean_num_str = bignum.stripUnderscores(num_str, radix, &num_strip_buf) orelse return invalidNumberOrEof(self);
    const n = std.fmt.parseInt(i64, clean_num_str, radix) catch |err| {
        if (err != error.Overflow) return invalidNumberOrEof(self);
        // Numerator overflows i64: still consume a rational N/D so the '/'
        // does not get re-tokenized as the start of a symbol.
        if (self.pos < self.source.len and self.source[self.pos] == '/') {
            const slash_pos = self.pos;
            const den_str = scanDenominatorDigits(self, radix);
            if (den_str.len > 0) {
                if (tryComplexTailBigRational(self, num_str, den_str, radix)) |tok| return tok;
                return bigRationalToken(self, num_str, den_str, radix);
            }
            self.pos = slash_pos; // no digits after '/', backtrack
        }
        // A complex tail after a bignum integer real part reads digit-exactly
        // (kaappi#2166) — the same shape the i64 path takes below.
        if (tryComplexTail(self, radix)) |tail| {
            const real = bignum.parseBignumString(self.gc, num_str, radix) catch return invalidNumberOrEof(self);
            rootComplexReal(self, real);
            return .{ .complex = .{ .real = real, .imag = tail.imag } };
        }
        return .{ .bignum_str = .{ .str = num_str, .radix = radix } };
    };
    // Check for rational literal: N/D (within same radix)
    if (self.pos < self.source.len and self.source[self.pos] == '/') {
        const slash_pos = self.pos;
        const den_str = scanDenominatorDigits(self, radix);
        if (den_str.len > 0) {
            var den_strip_buf: [256]u8 = undefined;
            const clean_den_str = bignum.stripUnderscores(den_str, radix, &den_strip_buf) orelse return invalidNumberOrEof(self);
            const den = std.fmt.parseInt(i64, clean_den_str, radix) catch |err| {
                if (err == error.Overflow) {
                    if (tryComplexTailBigRational(self, num_str, den_str, radix)) |tok| return tok;
                    return bigRationalToken(self, num_str, den_str, radix);
                }
                return invalidNumberOrEof(self);
            };
            // Pure imaginary with an explicit magnitude: #x+3/4i is 0+3/4i
            // (R7RS <complex R> -> `+ <ureal R> i` | `- <ureal R> i`; the
            // sign is the production marker, and the signless #x3/4i is
            // not grammar). Chez and guile read it this way too (#2243).
            if ((num_str[0] == '+' or num_str[0] == '-') and
                self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
                (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
            {
                self.pos += 1;
                const zero: Value = types.makeFixnum(0);
                rootComplexReal(self, zero);
                const arith = @import("primitives_arithmetic.zig");
                const imag = arith.makeRationalReduced(self.gc, types.makeFixnum(n), types.makeFixnum(den)) catch return invalidNumberOrEof(self);
                rootComplexImag(self, imag);
                return .{ .complex = .{ .real = zero, .imag = imag } };
            }
            // Complex after a rational: #x1/2+3i, #x1/2+i (R7RS 7.1.1
            // `<real R> (+|-) <ureal R> i`). The real part keeps its exact
            // rational value through the token-level parse, exactly like the
            // radix-10 path does for `1/2+3i` (#2243).
            if (tryComplexTail(self, radix)) |tail| {
                const real = tryRationalComponent(self, n, den) orelse return invalidNumberOrEof(self);
                return .{ .complex = .{ .real = real, .imag = tail.imag } };
            }
            return .{ .rational = .{ .num = n, .den = den } };
        }
        // No digits after '/', backtrack
        self.pos = slash_pos;
    }
    // Pure imaginary with an explicit magnitude: #x+3i is 0+3i (R7RS
    // <complex R> -> `+ <ureal R> i`, the sign being the marker).
    if ((num_str[0] == '+' or num_str[0] == '-') and
        self.pos < self.source.len and (self.source[self.pos] == 'i' or self.source[self.pos] == 'I') and
        (self.pos + 1 >= self.source.len or Reader.isDelimiter(self.source[self.pos + 1])))
    {
        self.pos += 1;
        const zero: Value = types.makeFixnum(0);
        rootComplexReal(self, zero);
        const imag = exactIntComponent(self, n) orelse return invalidNumberOrEof(self);
        rootComplexImag(self, imag);
        return .{ .complex = .{ .real = zero, .imag = imag } };
    }
    // Complex after a plain integer: #x1+2i, #x1-i (#2243).
    if (tryComplexTail(self, radix)) |tail| {
        const real = exactIntComponent(self, n) orelse return invalidNumberOrEof(self);
        rootComplexReal(self, real);
        return .{ .complex = .{ .real = real, .imag = tail.imag } };
    }
    return .{ .fixnum = n };
}

/// Finishes reading a SRFI-270 hex float once `readIntegerWithRadix` has
/// spotted a `.` or `p`/`P` right after the leading hex-digit run: consumes
/// an optional `.`-fraction and an optional `p`-exponent, then hands the
/// whole `[sign] hex[.hex] [p[sign]digits]` slice to `bignum.parseHexFloat`.
fn readHexFloatSuffix(self: *Reader, start: usize) ReadError!Token {
    if (self.pos < self.source.len and self.source[self.pos] == '.') {
        self.pos += 1;
        while (self.pos < self.source.len and (std.ascii.isHex(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
    }
    if (self.pos < self.source.len and (self.source[self.pos] == 'p' or self.source[self.pos] == 'P')) {
        self.pos += 1;
        if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
            self.pos += 1;
        }
        while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
    }
    const full_str = self.source[start..self.pos];
    if (full_str.len > Reader.MAX_TOKEN_BYTES) return ReadError.TokenTooLong;
    const f = bignum.parseHexFloat(full_str) orelse return invalidNumberOrEof(self);
    return .{ .flonum = f };
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
                // "#\x4" cut mid-digits may continue as "#\x41" (#1940).
                if (self.truncatedHere()) return ReadError.UnexpectedEof;
                const hex_str = self.source[start + 1 .. self.pos];
                const cp = std.fmt.parseInt(u21, hex_str, 16) catch return ReadError.InvalidNumber;
                if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) return ReadError.InvalidCharacterName;
                if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                    return ReadError.UnexpectedChar;
                return .{ .character = cp };
            }
            // Just #\x alone — return 'x'
            if (self.pos >= self.source.len or !std.ascii.isAlphabetic(self.source[self.pos])) {
                // "#\x" at end-of-slice may be "#\x41" cut before its digits.
                if (self.truncatedHere()) return ReadError.UnexpectedEof;
                if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
                    return ReadError.UnexpectedChar;
                return .{ .character = first_byte };
            }
        }
        while (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
            self.pos += 1;
        }
        // A name scan stopped by end-of-slice may be a prefix: "#\s" of
        // "#\space", "#\spa" of "#\space" (#1940's #\s + `pace' split).
        if (self.truncatedHere()) return ReadError.UnexpectedEof;
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
        // "#\λ" at end-of-slice: a non-delimiter in the next chunk would
        // make this a (malformed) longer literal, not the character λ.
        if (self.truncatedHere()) return ReadError.UnexpectedEof;
        if (self.pos < self.source.len and !Reader.isDelimiter(self.source[self.pos]))
            return ReadError.UnexpectedChar;
        return .{ .character = cp };
    }

    // Single ASCII non-letter character (e.g., #\( #\) #\1 etc.)
    self.pos += 1;
    return .{ .character = first_byte };
}

const reader_datum = @import("reader_datum.zig");
