const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const Value = types.Value;
const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;
const Token = reader_mod.Token;

pub fn readDatum(self: *Reader) ReadError!Value {
    if (self.depth >= Reader.MAX_NESTING_DEPTH) return ReadError.NestingTooDeep;
    self.depth += 1;
    defer self.depth -= 1;
    const tok = try self.nextToken();
    return tokenToValue(self, tok);
}

fn tokenToValue(self: *Reader, tok: Token) ReadError!Value {
    switch (tok) {
        .fixnum => |n| {
            if (n > std.math.maxInt(i48) or n < std.math.minInt(i48)) {
                return self.gc.allocBignumFromI64(n) catch return ReadError.OutOfMemory;
            }
            return types.makeFixnum(n);
        },
        .flonum => |f| return types.makeFlonum(f),
        .bignum_str => |b| {
            const bignum_mod = @import("bignum.zig");
            return bignum_mod.parseBignumString(self.gc, b.str, b.radix) catch return ReadError.OutOfMemory;
        },
        .rational => |r| {
            if (r.den == 0) return ReadError.InvalidNumber;
            const arith = @import("primitives_arithmetic.zig");
            return arith.makeRationalFromReader(self.gc, r.num, r.den) catch return ReadError.OutOfMemory;
        },
        .complex => |c| return self.gc.allocComplexEx(c.real, c.imag, c.exact_real, c.exact_imag) catch return ReadError.OutOfMemory,
        .boolean => |b| return if (b) types.TRUE else types.FALSE,
        .character => |c| return types.makeChar(c),
        .string => |s| {
            const val = self.gc.allocString(s) catch return ReadError.OutOfMemory;
            if (self.mark_immutable) types.toObject(val).flags.immutable = true;
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
            if (n >= self.labels.len) return ReadError.InvalidNumber;
            // Pre-allocate a placeholder pair for circular references.
            // Root it so GC doesn't free it during the nested readDatum.
            var placeholder = self.gc.allocPair(types.VOID, types.NIL) catch return ReadError.OutOfMemory;
            self.gc.pushRoot(&placeholder);
            self.labels[n] = placeholder;
            const datum = readDatum(self) catch |err| {
                self.gc.popRoot();
                return err;
            };
            self.gc.popRoot();
            self.labels[n] = placeholder;
            if (types.isPair(datum)) {
                types.setCar(placeholder, types.car(datum));
                self.gc.writeBarrier(types.toObject(placeholder), types.car(datum));
                types.setCdr(placeholder, types.cdr(datum));
                self.gc.writeBarrier(types.toObject(placeholder), types.cdr(datum));
                if (self.mark_immutable) types.toObject(placeholder).flags.immutable = true;
                return placeholder;
            } else {
                self.labels[n] = datum;
                patchPlaceholder(self.gc, datum, placeholder) catch return ReadError.OutOfMemory;
                return datum;
            }
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
    try self.skipWhitespaceAndCommentsChecked();
    if (self.pos < self.source.len and self.source[self.pos] == ')') {
        self.pos += 1;
        return types.NIL;
    }

    const list_line = self.getLineCol().line;
    const first = try readDatum(self);
    var first_root = first;
    self.gc.pushRoot(&first_root);
    defer self.gc.popRoot();

    try self.skipWhitespaceAndCommentsChecked();
    if (self.pos < self.source.len and self.source[self.pos] == '.') {
        if (self.pos + 1 < self.source.len and Reader.isDelimiter(self.source[self.pos + 1])) {
            self.pos += 1;
            const rest = try readDatum(self);
            var rest_root = rest;
            self.gc.pushRoot(&rest_root);
            defer self.gc.popRoot();
            try self.skipWhitespaceAndCommentsChecked();
            if (self.pos >= self.source.len or self.source[self.pos] != ')') {
                return ReadError.UnexpectedChar;
            }
            self.pos += 1;
            const pair = self.gc.allocPair(first_root, rest_root) catch return ReadError.OutOfMemory;
            if (self.mark_immutable) types.toObject(pair).flags.immutable = true;
            self.gc.source_lines.put(pair, list_line) catch {};
            return pair;
        }
    }

    const rest = try readListTail(self);
    var rest_root = rest;
    self.gc.pushRoot(&rest_root);
    defer self.gc.popRoot();
    const pair = self.gc.allocPair(first_root, rest_root) catch return ReadError.OutOfMemory;
    if (self.mark_immutable) types.toObject(pair).flags.immutable = true;
    self.gc.source_lines.put(pair, list_line) catch {};
    return pair;
}

fn readListTail(self: *Reader) ReadError!Value {
    var result: Value = types.NIL;
    self.gc.pushRoot(&result);
    defer self.gc.popRoot();
    var elem: Value = types.NIL;
    self.gc.pushRoot(&elem);
    defer self.gc.popRoot();

    var tail: Value = types.NIL;

    while (true) {
        try self.skipWhitespaceAndCommentsChecked();
        if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
        if (self.source[self.pos] == ')') {
            self.pos += 1;
            return result;
        }

        if (self.source[self.pos] == '.' and
            self.pos + 1 < self.source.len and
            Reader.isDelimiter(self.source[self.pos + 1]))
        {
            self.pos += 1;
            const rest = try readDatum(self);
            if (tail == types.NIL) {
                result = rest;
            } else {
                types.setCdr(tail, rest);
            }
            try self.skipWhitespaceAndCommentsChecked();
            if (self.pos >= self.source.len or self.source[self.pos] != ')') {
                return ReadError.UnexpectedChar;
            }
            self.pos += 1;
            return result;
        }

        const elem_line = self.getLineCol().line;
        elem = try readDatum(self);
        const pair = self.gc.allocPair(elem, types.NIL) catch return ReadError.OutOfMemory;
        if (self.mark_immutable) types.toObject(pair).flags.immutable = true;
        self.gc.source_lines.put(pair, elem_line) catch {};

        if (result == types.NIL) {
            result = pair;
        } else {
            types.setCdr(tail, pair);
        }
        tail = pair;
    }
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
    if (self.mark_immutable) types.toObject(rest).flags.immutable = true;
    var rest_root = rest;
    self.gc.pushRoot(&rest_root);
    defer self.gc.popRoot();
    const result = self.gc.allocPair(sym_root, rest_root) catch return ReadError.OutOfMemory;
    if (self.mark_immutable) types.toObject(result).flags.immutable = true;
    return result;
}

fn readVector(self: *Reader) ReadError!Value {
    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(self.gc.allocator);

    // Each readDatum below allocates and may trigger GC. Elements already read
    // live only in `elems`, which is not a GC root, and rooting `&elems.items[i]`
    // is unsafe because the list can realloc. Mirror them into the GC's by-value
    // extra_roots (realloc-safe, scanned during marking) and drop them after.
    const roots_base = self.gc.extra_roots.items.len;
    defer self.gc.extra_roots.shrinkRetainingCapacity(roots_base);

    while (true) {
        try self.skipWhitespaceAndCommentsChecked();
        if (self.pos >= self.source.len) return ReadError.UnexpectedEof;
        if (self.source[self.pos] == ')') {
            self.pos += 1;
            break;
        }
        const elem = try readDatum(self);
        elems.append(self.gc.allocator, elem) catch return ReadError.OutOfMemory;
        self.gc.extra_roots.append(self.gc.allocator, elem) catch return ReadError.OutOfMemory;
    }

    const vec = self.gc.allocVector(elems.items) catch return ReadError.OutOfMemory;
    if (self.mark_immutable) types.toObject(vec).flags.immutable = true;
    return vec;
}

const memory = @import("memory.zig");

/// Walk `datum` and replace every occurrence of `placeholder` with `datum`.
/// Handles pairs (car/cdr) and vectors (slots). Uses an iterative traversal
/// with a hash-set for O(1) cycle detection.
fn patchPlaceholder(gc: *memory.GC, datum: Value, placeholder: Value) error{OutOfMemory}!void {
    var stack: std.ArrayList(Value) = .empty;
    defer stack.deinit(gc.allocator);
    var visited = std.AutoHashMap(Value, void).init(gc.allocator);
    defer visited.deinit();

    try stack.append(gc.allocator, datum);

    while (stack.items.len > 0) {
        const val = stack.pop().?;
        if (visited.contains(val)) continue;
        try visited.put(val, {});

        if (types.isPair(val)) {
            if (types.car(val) == placeholder) {
                types.setCar(val, datum);
                gc.writeBarrier(types.toObject(val), datum);
            } else {
                const car = types.car(val);
                if (types.isPair(car) or types.isVector(car))
                    try stack.append(gc.allocator, car);
            }
            if (types.cdr(val) == placeholder) {
                types.setCdr(val, datum);
                gc.writeBarrier(types.toObject(val), datum);
            } else {
                const cdr = types.cdr(val);
                if (types.isPair(cdr) or types.isVector(cdr))
                    try stack.append(gc.allocator, cdr);
            }
        } else if (types.isVector(val)) {
            for (types.toVector(val).data) |*slot| {
                if (slot.* == placeholder) {
                    slot.* = datum;
                    gc.writeBarrier(types.toObject(val), datum);
                } else if (types.isPair(slot.*) or types.isVector(slot.*)) {
                    try stack.append(gc.allocator, slot.*);
                }
            }
        }
    }
}

fn readBytevector(self: *Reader) ReadError!Value {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(self.gc.allocator);

    while (true) {
        try self.skipWhitespaceAndCommentsChecked();
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

    const bv = self.gc.allocBytevector(bytes.items) catch return ReadError.OutOfMemory;
    if (self.mark_immutable) types.toObject(bv).flags.immutable = true;
    return bv;
}
