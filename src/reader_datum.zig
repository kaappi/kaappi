const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const Value = types.Value;
const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;
const Token = reader_mod.Token;

pub fn readDatum(self: *Reader) ReadError!Value {
    const tok = try self.nextToken();
    return tokenToValue(self, tok);
}

fn tokenToValue(self: *Reader, tok: Token) ReadError!Value {
    switch (tok) {
        .fixnum => |n| return types.makeFixnum(n),
        .flonum => |f| return self.gc.allocFlonum(f) catch return ReadError.OutOfMemory,
        .bignum_str => |digits| {
            const bignum_mod = @import("bignum.zig");
            return bignum_mod.parseBignumString(self.gc, digits) catch return ReadError.OutOfMemory;
        },
        .rational => |r| {
            if (r.den == 0) return ReadError.InvalidNumber;
            const arith = @import("primitives_arithmetic.zig");
            return arith.makeRationalFromReader(self.gc, r.num, r.den) catch return ReadError.OutOfMemory;
        },
        .complex => |c| return self.gc.allocComplex(c.real, c.imag) catch return ReadError.OutOfMemory,
        .boolean => |b| return if (b) types.TRUE else types.FALSE,
        .character => |c| return types.makeChar(c),
        .string => |s| {
            const val = self.gc.allocString(s) catch return ReadError.OutOfMemory;
            types.toObject(val).as(types.SchemeString).immutable = true;
            return val;
        },
        .symbol => |name| return self.gc.allocSymbol(name) catch return ReadError.OutOfMemory,
        .lparen => return readList(self),
        .quote => return readAbbreviation(self, "quote"),
        .backquote => return readAbbreviation(self, "quasiquote"),
        .comma => return readAbbreviation(self, "unquote"),
        .comma_at => return readAbbreviation(self, "unquote-splicing"),
        .hash_lparen => return readVector(self),
        .hash_u8_lparen => return readBytevector(self),
        .datum_label_def => |n| {
            const datum = try readDatum(self);
            if (n < self.labels.len) {
                self.labels[n] = datum;
            }
            return datum;
        },
        .datum_label_ref => |n| {
            if (n < self.labels.len) {
                if (self.labels[n]) |val| return val;
            }
            return ReadError.InvalidNumber;
        },
        .rparen => return ReadError.UnexpectedRightParen,
        .dot => return ReadError.DotNotInList,
        .eof => return ReadError.UnexpectedEof,
    }
}

fn readList(self: *Reader) ReadError!Value {
    self.skipWhitespaceAndComments();
    if (self.pos < self.source.len and self.source[self.pos] == ')') {
        self.pos += 1;
        return types.NIL;
    }

    const first = try readDatum(self);
    var first_root = first;
    self.gc.pushRoot(&first_root);
    defer self.gc.popRoot();

    self.skipWhitespaceAndComments();
    if (self.pos < self.source.len and self.source[self.pos] == '.') {
        if (self.pos + 1 < self.source.len and Reader.isDelimiter(self.source[self.pos + 1])) {
            self.pos += 1;
            const rest = try readDatum(self);
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len or self.source[self.pos] != ')') {
                return ReadError.UnexpectedChar;
            }
            self.pos += 1;
            return self.gc.allocPair(first_root, rest) catch return ReadError.OutOfMemory;
        }
    }

    var rest = try readListTail(self);
    _ = &rest;
    return self.gc.allocPair(first_root, rest) catch return ReadError.OutOfMemory;
}

fn readListTail(self: *Reader) ReadError!Value {
    self.skipWhitespaceAndComments();
    if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
    if (self.source[self.pos] == ')') {
        self.pos += 1;
        return types.NIL;
    }

    if (self.source[self.pos] == '.' and
        self.pos + 1 < self.source.len and
        Reader.isDelimiter(self.source[self.pos + 1]))
    {
        self.pos += 1;
        const rest = try readDatum(self);
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len or self.source[self.pos] != ')') {
            return ReadError.UnexpectedChar;
        }
        self.pos += 1;
        return rest;
    }

    const elem = try readDatum(self);
    var elem_root = elem;
    self.gc.pushRoot(&elem_root);
    defer self.gc.popRoot();

    const rest = try readListTail(self);
    return self.gc.allocPair(elem_root, rest) catch return ReadError.OutOfMemory;
}

fn readAbbreviation(self: *Reader, keyword: []const u8) ReadError!Value {
    const datum = try readDatum(self);
    var datum_root = datum;
    self.gc.pushRoot(&datum_root);
    defer self.gc.popRoot();

    const sym = self.gc.allocSymbol(keyword) catch return ReadError.OutOfMemory;
    var sym_root = sym;
    self.gc.pushRoot(&sym_root);
    defer self.gc.popRoot();

    const rest = self.gc.allocPair(datum_root, types.NIL) catch return ReadError.OutOfMemory;
    return self.gc.allocPair(sym_root, rest) catch return ReadError.OutOfMemory;
}

fn readVector(self: *Reader) ReadError!Value {
    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(self.gc.allocator);

    while (true) {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
        if (self.source[self.pos] == ')') {
            self.pos += 1;
            break;
        }
        const elem = try readDatum(self);
        elems.append(self.gc.allocator, elem) catch return ReadError.OutOfMemory;
    }

    return self.gc.allocVector(elems.items) catch return ReadError.OutOfMemory;
}

fn readBytevector(self: *Reader) ReadError!Value {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(self.gc.allocator);

    while (true) {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
        if (self.source[self.pos] == ')') {
            self.pos += 1;
            break;
        }
        const tok = try self.nextToken();
        switch (tok) {
            .fixnum => |n| {
                if (n < 0 or n > 255) return ReadError.InvalidNumber;
                bytes.append(self.gc.allocator, @intCast(@as(u64, @bitCast(n)))) catch return ReadError.OutOfMemory;
            },
            else => return ReadError.UnexpectedChar,
        }
    }

    return self.gc.allocBytevector(bytes.items) catch return ReadError.OutOfMemory;
}
