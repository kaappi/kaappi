const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const unicode = @import("unicode_tables.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "char-alphabetic?", .func = &charAlphabeticP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-numeric?", .func = &charNumericP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-whitespace?", .func = &charWhitespaceP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-upper-case?", .func = &charUpperCaseP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-lower-case?", .func = &charLowerCaseP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-upcase", .func = &charUpcaseFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-downcase", .func = &charDowncaseFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-foldcase", .func = &charFoldcaseFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_char) },
    .{ .name = "digit-value", .func = &digitValueFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_char) },
    .{ .name = "char-ci<?", .func = &charCiLtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-ci<=?", .func = &charCiLeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-ci=?", .func = &charCiEqFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-ci>=?", .func = &charCiGeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "char-ci>?", .func = &charCiGtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "string-ci<?", .func = &stringCiLtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "string-ci<=?", .func = &stringCiLeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "string-ci=?", .func = &stringCiEqFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "string-ci>=?", .func = &stringCiGeFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "string-ci>?", .func = &stringCiGtFn, .arity = .{ .variadic = 2 }, .libs = LS.initMany(&.{ .scheme_char, .scheme_r5rs }) },
    .{ .name = "string-upcase", .func = &stringUpcaseFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_char) },
    .{ .name = "string-downcase", .func = &stringDowncaseFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_char) },
    .{ .name = "string-foldcase", .func = &stringFoldcaseFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_char) },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Unicode classification helpers
// ---------------------------------------------------------------------------

fn isUnicodeLetter(cp: u21) bool {
    if (cp <= 127) return std.ascii.isAlphabetic(@intCast(cp));
    return unicode.inRanges(&unicode.alphabetic_ranges, cp);
}

pub fn isUnicodeUppercase(cp: u21) bool {
    if (cp <= 127) return std.ascii.isUpper(@intCast(cp));
    return unicode.inRanges(&unicode.uppercase_ranges, cp);
}

pub fn isUnicodeLowercase(cp: u21) bool {
    if (cp <= 127) return std.ascii.isLower(@intCast(cp));
    return unicode.inRanges(&unicode.lowercase_ranges, cp);
}

pub fn isUnicodeCased(cp: u21) bool {
    if (cp <= 127) return std.ascii.isAlphabetic(@intCast(cp));
    return unicode.inRanges(&unicode.cased_ranges, cp);
}

fn isUnicodeWhitespace(cp: u21) bool {
    if (cp <= 127) {
        return switch (cp) {
            0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20 => true,
            else => false,
        };
    }
    return switch (cp) {
        0x85, // NEXT LINE
        0xA0, // NO-BREAK SPACE
        0x1680, // OGHAM SPACE MARK
        0x2000,
        0x2001,
        0x2002,
        0x2003,
        0x2004,
        0x2005,
        0x2006,
        0x2007,
        0x2008,
        0x2009,
        0x200A, // EN/EM spaces etc
        0x2028, // LINE SEPARATOR
        0x2029, // PARAGRAPH SEPARATOR
        0x202F, // NARROW NO-BREAK SPACE
        0x205F, // MEDIUM MATHEMATICAL SPACE
        0x3000, // IDEOGRAPHIC SPACE
        => true,
        else => false,
    };
}

fn isUnicodeNumeric(cp: u21) bool {
    if (cp >= '0' and cp <= '9') return true;
    const digit_zeros = [_]u21{
        0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66,
        0x0BE6, 0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20,
        0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90,
        0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0,
        0xA9F0, 0xAA50, 0xABF0, 0xFF10,
    };
    for (digit_zeros) |zero| {
        if (cp >= zero and cp <= zero + 9) return true;
    }
    return false;
}

pub fn unicodeUpcase(cp: u21) u21 {
    if (cp <= 127) return @intCast(std.ascii.toUpper(@intCast(cp)));
    return unicode.findUpper(cp) orelse cp;
}

pub fn unicodeDowncase(cp: u21) u21 {
    if (cp <= 127) return @intCast(std.ascii.toLower(@intCast(cp)));
    return unicode.findLower(cp) orelse cp;
}

// ---------------------------------------------------------------------------
// Character classification
// ---------------------------------------------------------------------------

fn charAlphabeticP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-alphabetic?", "char", args[0]);
    return if (isUnicodeLetter(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charNumericP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-numeric?", "char", args[0]);
    return if (isUnicodeNumeric(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charWhitespaceP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-whitespace?", "char", args[0]);
    return if (isUnicodeWhitespace(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charUpperCaseP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-upper-case?", "char", args[0]);
    return if (isUnicodeUppercase(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charLowerCaseP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-lower-case?", "char", args[0]);
    return if (isUnicodeLowercase(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

// ---------------------------------------------------------------------------
// Case operations
// ---------------------------------------------------------------------------

fn charUpcaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-upcase", "char", args[0]);
    return types.makeChar(unicodeUpcase(types.toChar(args[0])));
}

fn charDowncaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-downcase", "char", args[0]);
    return types.makeChar(unicodeDowncase(types.toChar(args[0])));
}

fn charFoldcaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("char-foldcase", "char", args[0]);
    return types.makeChar(foldChar(types.toChar(args[0])));
}

pub fn charFoldcase(cp: u21) u21 {
    return foldChar(cp);
}

// ---------------------------------------------------------------------------
// digit-value
// ---------------------------------------------------------------------------

fn digitValueFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("digit-value", "char", args[0]);
    const cp = types.toChar(args[0]);
    if (cp >= '0' and cp <= '9') {
        return types.makeFixnum(@as(i64, cp) - '0');
    }
    const digit_zeros = [_]u21{
        0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66,
        0x0BE6, 0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20,
        0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90,
        0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0,
        0xA9F0, 0xAA50, 0xABF0, 0xFF10,
    };
    for (digit_zeros) |zero| {
        if (cp >= zero and cp <= zero + 9) {
            return types.makeFixnum(@as(i64, cp) - @as(i64, zero));
        }
    }
    return types.FALSE;
}

// ---------------------------------------------------------------------------
// Case-insensitive char comparison
// ---------------------------------------------------------------------------

fn foldChar(cp: u21) u21 {
    if (cp <= 127) return @intCast(std.ascii.toLower(@intCast(cp)));
    return unicode.findFold(cp) orelse unicodeDowncase(cp);
}

fn compareCiChars(proc: []const u8, args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isChar(args[i])) return primitives.typeError(proc, "char", args[i]);
        if (!types.isChar(args[i + 1])) return primitives.typeError(proc, "char", args[i + 1]);
        const a = foldChar(types.toChar(args[i]));
        const b = foldChar(types.toChar(args[i + 1]));
        const pass = switch (cmp) {
            .lt => a < b,
            .le => a <= b,
            .eq => a == b,
            .ge => a >= b,
            .gt => a > b,
        };
        if (!pass) return types.FALSE;
    }
    return types.TRUE;
}

fn charCiLtFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars("char-ci<?", args, .lt);
}

fn charCiLeFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars("char-ci<=?", args, .le);
}

fn charCiEqFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars("char-ci=?", args, .eq);
}

fn charCiGeFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars("char-ci>=?", args, .ge);
}

fn charCiGtFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars("char-ci>?", args, .gt);
}

// ---------------------------------------------------------------------------
// Case-insensitive string comparison
// ---------------------------------------------------------------------------

const FoldResult = struct {
    cps: [3]u21,
    len: u2,
};

fn foldCharExpanding(cp: u21) FoldResult {
    return switch (cp) {
        0x00DF => .{ .cps = .{ 's', 's', 0 }, .len = 2 },
        0x0130 => .{ .cps = .{ 0x0069, 0x0307, 0 }, .len = 2 },
        0x01F0 => .{ .cps = .{ 'j', 0x030C, 0 }, .len = 2 },
        0x0390 => .{ .cps = .{ 0x03B9, 0x0308, 0x0301 }, .len = 3 },
        0x03B0 => .{ .cps = .{ 0x03C5, 0x0308, 0x0301 }, .len = 3 },
        0xFB00 => .{ .cps = .{ 'f', 'f', 0 }, .len = 2 },
        0xFB01 => .{ .cps = .{ 'f', 'i', 0 }, .len = 2 },
        0xFB02 => .{ .cps = .{ 'f', 'l', 0 }, .len = 2 },
        0xFB03 => .{ .cps = .{ 'f', 'f', 'i' }, .len = 3 },
        0xFB04 => .{ .cps = .{ 'f', 'f', 'l' }, .len = 3 },
        0xFB05, 0xFB06 => .{ .cps = .{ 's', 't', 0 }, .len = 2 },
        else => {
            const folded = foldChar(cp);
            return .{ .cps = .{ folded, 0, 0 }, .len = 1 };
        },
    };
}

fn foldCompareStrings(a: []const u8, b: []const u8) std.math.Order {
    var ai: usize = 0;
    var bi: usize = 0;
    var a_buf: FoldResult = .{ .cps = .{ 0, 0, 0 }, .len = 0 };
    var b_buf: FoldResult = .{ .cps = .{ 0, 0, 0 }, .len = 0 };
    var a_idx: u2 = 0;
    var b_idx: u2 = 0;

    while (true) {
        if (a_idx >= a_buf.len) {
            if (ai >= a.len) {
                if (b_idx >= b_buf.len and bi >= b.len) return .eq;
                return .lt;
            }
            const a_len = std.unicode.utf8ByteSequenceLength(a[ai]) catch 1;
            const a_cp = if (ai + a_len <= a.len)
                (std.unicode.utf8Decode(a[ai .. ai + a_len]) catch @as(u21, a[ai]))
            else
                @as(u21, a[ai]);
            a_buf = foldCharExpanding(a_cp);
            a_idx = 0;
            ai += a_len;
        }
        if (b_idx >= b_buf.len) {
            if (bi >= b.len) return .gt;
            const b_len = std.unicode.utf8ByteSequenceLength(b[bi]) catch 1;
            const b_cp = if (bi + b_len <= b.len)
                (std.unicode.utf8Decode(b[bi .. bi + b_len]) catch @as(u21, b[bi]))
            else
                @as(u21, b[bi]);
            b_buf = foldCharExpanding(b_cp);
            b_idx = 0;
            bi += b_len;
        }
        const fa = a_buf.cps[a_idx];
        const fb = b_buf.cps[b_idx];
        if (fa < fb) return .lt;
        if (fa > fb) return .gt;
        a_idx += 1;
        b_idx += 1;
    }
}

fn compareCiStrings(proc: []const u8, args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try primitives.expectString(proc, args[i]);
        const b = try primitives.expectString(proc, args[i + 1]);
        const order = foldCompareStrings(a, b);
        const pass = switch (cmp) {
            .lt => order == .lt,
            .le => order != .gt,
            .eq => order == .eq,
            .ge => order != .lt,
            .gt => order == .gt,
        };
        if (!pass) return types.FALSE;
    }
    return types.TRUE;
}

fn stringCiLtFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings("string-ci<?", args, .lt);
}

fn stringCiLeFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings("string-ci<=?", args, .le);
}

fn stringCiEqFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings("string-ci=?", args, .eq);
}

fn stringCiGeFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings("string-ci>=?", args, .ge);
}

fn stringCiGtFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings("string-ci>?", args, .gt);
}

// ---------------------------------------------------------------------------
// String case operations
// ---------------------------------------------------------------------------

fn stringCaseMap(data: []const u8, comptime case_fn: fn (u21) u21) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    // Case mapping may change byte lengths, so use a dynamic buffer
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);
    var i: usize = 0;
    while (i < data.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(data[i]) catch 1;
        if (i + seq_len > data.len) {
            // Invalid trailing bytes: copy as-is
            result.append(gc.allocator, data[i]) catch return PrimitiveError.OutOfMemory;
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(data[i .. i + seq_len]) catch {
            result.append(gc.allocator, data[i]) catch return PrimitiveError.OutOfMemory;
            i += 1;
            continue;
        };
        const mapped = case_fn(cp);
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(mapped, &tmp) catch {
            // Should not happen for valid codepoints; copy original
            result.appendSlice(gc.allocator, data[i .. i + seq_len]) catch return PrimitiveError.OutOfMemory;
            i += seq_len;
            continue;
        };
        result.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
        i += seq_len;
    }
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

fn stringUpcaseFn(args: []const Value) PrimitiveError!Value {
    const data = try primitives.expectString("string-upcase", args[0]);
    return stringCaseMapExpanding(data, .upcase);
}

fn stringDowncaseFn(args: []const Value) PrimitiveError!Value {
    const data = try primitives.expectString("string-downcase", args[0]);
    return stringCaseMapExpanding(data, .downcase);
}

fn stringFoldcaseFn(args: []const Value) PrimitiveError!Value {
    const data = try primitives.expectString("string-foldcase", args[0]);
    return stringCaseMapExpanding(data, .foldcase);
}

const CaseMode = enum { upcase, downcase, foldcase };

pub fn appendCodepoint(result: *std.ArrayList(u8), alloc: std.mem.Allocator, cp: u21) PrimitiveError!void {
    var tmp: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &tmp) catch return PrimitiveError.OutOfMemory;
    result.appendSlice(alloc, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
}

fn stringCaseMapExpanding(data: []const u8, mode: CaseMode) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);

    var i: usize = 0;
    var prev_cased = false;
    while (i < data.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(data[i]) catch 1;
        if (i + seq_len > data.len) {
            result.append(gc.allocator, data[i]) catch return PrimitiveError.OutOfMemory;
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(data[i .. i + seq_len]) catch {
            result.append(gc.allocator, data[i]) catch return PrimitiveError.OutOfMemory;
            i += 1;
            continue;
        };

        switch (mode) {
            .upcase => {
                switch (cp) {
                    0x00DF => {
                        try appendCodepoint(&result, gc.allocator, 'S');
                        try appendCodepoint(&result, gc.allocator, 'S');
                    },
                    0x01F0 => {
                        try appendCodepoint(&result, gc.allocator, 'J');
                        try appendCodepoint(&result, gc.allocator, 0x030C);
                    },
                    0x0390 => {
                        try appendCodepoint(&result, gc.allocator, 0x0399);
                        try appendCodepoint(&result, gc.allocator, 0x0308);
                        try appendCodepoint(&result, gc.allocator, 0x0301);
                    },
                    0x03B0 => {
                        try appendCodepoint(&result, gc.allocator, 0x03A5);
                        try appendCodepoint(&result, gc.allocator, 0x0308);
                        try appendCodepoint(&result, gc.allocator, 0x0301);
                    },
                    0xFB00 => {
                        try appendCodepoint(&result, gc.allocator, 'F');
                        try appendCodepoint(&result, gc.allocator, 'F');
                    },
                    0xFB01 => {
                        try appendCodepoint(&result, gc.allocator, 'F');
                        try appendCodepoint(&result, gc.allocator, 'I');
                    },
                    0xFB02 => {
                        try appendCodepoint(&result, gc.allocator, 'F');
                        try appendCodepoint(&result, gc.allocator, 'L');
                    },
                    0xFB03 => {
                        try appendCodepoint(&result, gc.allocator, 'F');
                        try appendCodepoint(&result, gc.allocator, 'F');
                        try appendCodepoint(&result, gc.allocator, 'I');
                    },
                    0xFB04 => {
                        try appendCodepoint(&result, gc.allocator, 'F');
                        try appendCodepoint(&result, gc.allocator, 'F');
                        try appendCodepoint(&result, gc.allocator, 'L');
                    },
                    else => try appendCodepoint(&result, gc.allocator, unicodeUpcase(cp)),
                }
            },
            .downcase => {
                switch (cp) {
                    0x0130 => {
                        try appendCodepoint(&result, gc.allocator, 0x0069);
                        try appendCodepoint(&result, gc.allocator, 0x0307);
                    },
                    0x03A3 => {
                        // Greek final sigma: Σ at end of word → ς
                        const next_cp = blk: {
                            const ni = i + seq_len;
                            if (ni >= data.len) break :blk @as(?u21, null);
                            const nsl = std.unicode.utf8ByteSequenceLength(data[ni]) catch break :blk @as(?u21, null);
                            if (ni + nsl > data.len) break :blk @as(?u21, null);
                            break :blk std.unicode.utf8Decode(data[ni .. ni + nsl]) catch null;
                        };
                        const next_is_cased = if (next_cp) |nc| isUnicodeCased(nc) else false;
                        if (prev_cased and !next_is_cased)
                            try appendCodepoint(&result, gc.allocator, 0x03C2) // ς
                        else
                            try appendCodepoint(&result, gc.allocator, 0x03C3); // σ
                    },
                    else => try appendCodepoint(&result, gc.allocator, unicodeDowncase(cp)),
                }
            },
            .foldcase => {
                switch (cp) {
                    0x00DF => {
                        try appendCodepoint(&result, gc.allocator, 's');
                        try appendCodepoint(&result, gc.allocator, 's');
                    },
                    0x0130 => {
                        try appendCodepoint(&result, gc.allocator, 0x0069);
                        try appendCodepoint(&result, gc.allocator, 0x0307);
                    },
                    0x01F0 => {
                        try appendCodepoint(&result, gc.allocator, 'j');
                        try appendCodepoint(&result, gc.allocator, 0x030C);
                    },
                    0x0390 => {
                        try appendCodepoint(&result, gc.allocator, 0x03B9);
                        try appendCodepoint(&result, gc.allocator, 0x0308);
                        try appendCodepoint(&result, gc.allocator, 0x0301);
                    },
                    0x03B0 => {
                        try appendCodepoint(&result, gc.allocator, 0x03C5);
                        try appendCodepoint(&result, gc.allocator, 0x0308);
                        try appendCodepoint(&result, gc.allocator, 0x0301);
                    },
                    0xFB00 => {
                        try appendCodepoint(&result, gc.allocator, 'f');
                        try appendCodepoint(&result, gc.allocator, 'f');
                    },
                    0xFB01 => {
                        try appendCodepoint(&result, gc.allocator, 'f');
                        try appendCodepoint(&result, gc.allocator, 'i');
                    },
                    0xFB02 => {
                        try appendCodepoint(&result, gc.allocator, 'f');
                        try appendCodepoint(&result, gc.allocator, 'l');
                    },
                    0xFB03 => {
                        try appendCodepoint(&result, gc.allocator, 'f');
                        try appendCodepoint(&result, gc.allocator, 'f');
                        try appendCodepoint(&result, gc.allocator, 'i');
                    },
                    0xFB04 => {
                        try appendCodepoint(&result, gc.allocator, 'f');
                        try appendCodepoint(&result, gc.allocator, 'f');
                        try appendCodepoint(&result, gc.allocator, 'l');
                    },
                    0xFB05, 0xFB06 => {
                        try appendCodepoint(&result, gc.allocator, 's');
                        try appendCodepoint(&result, gc.allocator, 't');
                    },
                    else => {
                        const folded = unicode.findFold(cp) orelse unicodeDowncase(cp);
                        try appendCodepoint(&result, gc.allocator, folded);
                    },
                }
            },
        }
        prev_cased = isUnicodeCased(cp);
        i += seq_len;
    }
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}
