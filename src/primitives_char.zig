const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerChar(vm: *vm_mod.VM) !void {
    // Character classification
    try reg(vm, "char-alphabetic?", &charAlphabeticP, .{ .exact = 1 });
    try reg(vm, "char-numeric?", &charNumericP, .{ .exact = 1 });
    try reg(vm, "char-whitespace?", &charWhitespaceP, .{ .exact = 1 });
    try reg(vm, "char-upper-case?", &charUpperCaseP, .{ .exact = 1 });
    try reg(vm, "char-lower-case?", &charLowerCaseP, .{ .exact = 1 });

    // Case operations
    try reg(vm, "char-upcase", &charUpcaseFn, .{ .exact = 1 });
    try reg(vm, "char-downcase", &charDowncaseFn, .{ .exact = 1 });
    try reg(vm, "char-foldcase", &charFoldcaseFn, .{ .exact = 1 });

    // Digit value
    try reg(vm, "digit-value", &digitValueFn, .{ .exact = 1 });

    // Case-insensitive char comparison
    try reg(vm, "char-ci<?", &charCiLtFn, .{ .variadic = 2 });
    try reg(vm, "char-ci<=?", &charCiLeFn, .{ .variadic = 2 });
    try reg(vm, "char-ci=?", &charCiEqFn, .{ .variadic = 2 });
    try reg(vm, "char-ci>=?", &charCiGeFn, .{ .variadic = 2 });
    try reg(vm, "char-ci>?", &charCiGtFn, .{ .variadic = 2 });

    // Case-insensitive string comparison
    try reg(vm, "string-ci<?", &stringCiLtFn, .{ .variadic = 2 });
    try reg(vm, "string-ci<=?", &stringCiLeFn, .{ .variadic = 2 });
    try reg(vm, "string-ci=?", &stringCiEqFn, .{ .variadic = 2 });
    try reg(vm, "string-ci>=?", &stringCiGeFn, .{ .variadic = 2 });
    try reg(vm, "string-ci>?", &stringCiGtFn, .{ .variadic = 2 });

    // String case operations
    try reg(vm, "string-upcase", &stringUpcaseFn, .{ .exact = 1 });
    try reg(vm, "string-downcase", &stringDowncaseFn, .{ .exact = 1 });
    try reg(vm, "string-foldcase", &stringFoldcaseFn, .{ .exact = 1 });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn getStringSlice(v: Value) PrimitiveError![]const u8 {
    if (!types.isString(v)) return PrimitiveError.TypeError;
    const str = types.toObject(v).as(types.SchemeString);
    return str.data[0..str.len];
}

// ---------------------------------------------------------------------------
// Unicode classification helpers
// ---------------------------------------------------------------------------

fn isUnicodeLetter(cp: u21) bool {
    if (cp <= 127) return std.ascii.isAlphabetic(@intCast(cp));
    // Latin-1 Supplement letters (0xC0-0xFF excluding 0xD7 multiply, 0xF7 divide)
    if (cp >= 0xC0 and cp <= 0xFF and cp != 0xD7 and cp != 0xF7) return true;
    // Latin Extended-A, -B
    if (cp >= 0x100 and cp <= 0x24F) return true;
    // IPA Extensions
    if (cp >= 0x250 and cp <= 0x2AF) return true;
    // Greek and Coptic
    if (cp >= 0x370 and cp <= 0x3FF) return true;
    // Cyrillic
    if (cp >= 0x400 and cp <= 0x4FF) return true;
    // Cyrillic Supplement
    if (cp >= 0x500 and cp <= 0x52F) return true;
    // Armenian
    if (cp >= 0x530 and cp <= 0x58F) return true;
    // Hebrew (letters range)
    if (cp >= 0x5D0 and cp <= 0x5EA) return true;
    // Arabic
    if (cp >= 0x600 and cp <= 0x6FF) return true;
    // Devanagari
    if (cp >= 0x900 and cp <= 0x97F) return true;
    // Thai
    if (cp >= 0x0E01 and cp <= 0x0E3A) return true;
    // Georgian
    if (cp >= 0x10A0 and cp <= 0x10FF) return true;
    // Hangul Jamo
    if (cp >= 0x1100 and cp <= 0x11FF) return true;
    // Hiragana
    if (cp >= 0x3040 and cp <= 0x309F) return true;
    // Katakana
    if (cp >= 0x30A0 and cp <= 0x30FF) return true;
    // CJK Unified Ideographs
    if (cp >= 0x4E00 and cp <= 0x9FFF) return true;
    // Hangul Syllables
    if (cp >= 0xAC00 and cp <= 0xD7AF) return true;
    // CJK Extension A
    if (cp >= 0x3400 and cp <= 0x4DBF) return true;
    // Cherokee
    if (cp >= 0x13A0 and cp <= 0x13EF) return true;
    // Latin Extended Additional
    if (cp >= 0x1E00 and cp <= 0x1EFF) return true;
    // Georgian Mtavruli (uppercase)
    if (cp >= 0x1C90 and cp <= 0x1CBA) return true;
    // Greek Extended
    if (cp >= 0x1F00 and cp <= 0x1FFF) return true;
    // Cherokee lowercase
    if (cp >= 0xAB70 and cp <= 0xABBF) return true;
    return false;
}

fn isUnicodeUppercase(cp: u21) bool {
    if (cp <= 127) return std.ascii.isUpper(@intCast(cp));
    // Latin-1 Supplement uppercase (0xC0-0xD6, 0xD8-0xDE)
    if (cp >= 0xC0 and cp <= 0xD6) return true;
    if (cp >= 0xD8 and cp <= 0xDE) return true;
    // Latin Extended-A uppercase (even codepoints in many ranges)
    // Latin Extended-A: 0x100-0x17E - uppercase are typically even codepoints
    if (cp >= 0x100 and cp <= 0x17E) {
        // Most pairs: even=upper, odd=lower (e.g. 0x100=A-macron, 0x101=a-macron)
        return (cp & 1) == 0;
    }
    // Greek uppercase (0x391-0x3A9, excluding 0x3A2)
    if (cp >= 0x391 and cp <= 0x3A9 and cp != 0x3A2) return true;
    // Cyrillic uppercase (0x410-0x42F)
    if (cp >= 0x410 and cp <= 0x42F) return true;
    // Armenian uppercase (0x531-0x556)
    if (cp >= 0x531 and cp <= 0x556) return true;
    // Georgian Mtavruli (0x1C90-0x1CBA)
    if (cp >= 0x1C90 and cp <= 0x1CBA) return true;
    // Cherokee uppercase (0x13A0-0x13EF)
    if (cp >= 0x13A0 and cp <= 0x13EF) return true;
    return false;
}

fn isUnicodeLowercase(cp: u21) bool {
    if (cp <= 127) return std.ascii.isLower(@intCast(cp));
    // Latin-1 Supplement lowercase (0xDF-0xF6, 0xF8-0xFF)
    if (cp >= 0xDF and cp <= 0xF6) return true;
    if (cp >= 0xF8 and cp <= 0xFF) return true;
    // Latin Extended-A lowercase (odd codepoints in many ranges)
    if (cp >= 0x100 and cp <= 0x17E) {
        return (cp & 1) == 1;
    }
    // Greek lowercase (0x3B1-0x3C9)
    if (cp >= 0x3B1 and cp <= 0x3C9) return true;
    // Cyrillic lowercase (0x430-0x44F)
    if (cp >= 0x430 and cp <= 0x44F) return true;
    // Armenian lowercase (0x561-0x586)
    if (cp >= 0x561 and cp <= 0x586) return true;
    // Cherokee lowercase (0xAB70-0xABBF)
    if (cp >= 0xAB70 and cp <= 0xABBF) return true;
    return false;
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
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, // EN/EM spaces etc
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

fn unicodeUpcase(cp: u21) u21 {
    if (cp <= 127) return @intCast(std.ascii.toUpper(@intCast(cp)));
    // Latin-1 Supplement: lowercase 0xE0-0xF6, 0xF8-0xFE -> subtract 0x20
    if (cp >= 0xE0 and cp <= 0xF6) return cp - 0x20;
    if (cp >= 0xF8 and cp <= 0xFE) return cp - 0x20;
    // Latin Extended-A: odd (lowercase) -> even (uppercase)
    if (cp >= 0x101 and cp <= 0x17E and (cp & 1) == 1) return cp - 1;
    // Long s
    if (cp == 0x017F) return 'S';
    // Greek accented lowercase -> uppercase
    if (cp == 0x03AC) return 0x0386; // ά -> Ά
    if (cp == 0x03AD) return 0x0388; // έ -> Έ
    if (cp == 0x03AE) return 0x0389; // ή -> Ή
    if (cp == 0x03AF) return 0x038A; // ί -> Ί
    if (cp == 0x03CC) return 0x038C; // ό -> Ό
    if (cp == 0x03CD) return 0x038E; // ύ -> Ύ
    if (cp == 0x03CE) return 0x038F; // ώ -> Ώ
    // Greek final sigma -> Sigma (before range check since 0x3C2 is in range)
    if (cp == 0x03C2) return 0x03A3;
    // Greek lowercase (0x3B1-0x3C9) -> uppercase (0x391-0x3A9)
    if (cp >= 0x3B1 and cp <= 0x3C9) return cp - 0x20;
    // Cyrillic lowercase (0x430-0x44F) -> uppercase (0x410-0x42F)
    if (cp >= 0x430 and cp <= 0x44F) return cp - 0x20;
    // Armenian lowercase (0x561-0x586) -> uppercase (0x531-0x556)
    if (cp >= 0x561 and cp <= 0x586) return cp - 0x30;
    // Georgian Mkhedruli (0x10D0-0x10FA) -> Mtavruli (0x1C90-0x1CBA)
    if (cp >= 0x10D0 and cp <= 0x10FA) return cp + 0xBC0;
    // Cherokee lowercase (0xAB70-0xABBF) -> uppercase (0x13A0-0x13EF)
    if (cp >= 0xAB70 and cp <= 0xABBF) return cp - 0x97D0;
    return cp;
}

fn unicodeDowncase(cp: u21) u21 {
    if (cp <= 127) return @intCast(std.ascii.toLower(@intCast(cp)));
    // Latin-1 Supplement: uppercase 0xC0-0xD6, 0xD8-0xDE -> add 0x20
    if (cp >= 0xC0 and cp <= 0xD6) return cp + 0x20;
    if (cp >= 0xD8 and cp <= 0xDE) return cp + 0x20;
    // Latin Extended-A: even (uppercase) -> odd (lowercase)
    if (cp >= 0x100 and cp <= 0x17E and (cp & 1) == 0) return cp + 1;
    // Greek accented uppercase -> lowercase
    if (cp == 0x0386) return 0x03AC; // Ά -> ά
    if (cp == 0x0388) return 0x03AD; // Έ -> έ
    if (cp == 0x0389) return 0x03AE; // Ή -> ή
    if (cp == 0x038A) return 0x03AF; // Ί -> ί
    if (cp == 0x038C) return 0x03CC; // Ό -> ό
    if (cp == 0x038E) return 0x03CD; // Ύ -> ύ
    if (cp == 0x038F) return 0x03CE; // Ώ -> ώ
    // Greek uppercase (0x391-0x3A9) -> lowercase (0x3B1-0x3C9), skip 0x3A2
    if (cp >= 0x391 and cp <= 0x3A9 and cp != 0x3A2) return cp + 0x20;
    // Cyrillic uppercase (0x410-0x42F) -> lowercase (0x430-0x44F)
    if (cp >= 0x410 and cp <= 0x42F) return cp + 0x20;
    // Armenian uppercase (0x531-0x556) -> lowercase (0x561-0x586)
    if (cp >= 0x531 and cp <= 0x556) return cp + 0x30;
    // Georgian Mtavruli (0x1C90-0x1CBA) -> Mkhedruli (0x10D0-0x10FA)
    if (cp >= 0x1C90 and cp <= 0x1CBA) return cp - 0xBC0;
    // Cherokee uppercase (0x13A0-0x13EF) -> lowercase (0xAB70-0xABBF)
    if (cp >= 0x13A0 and cp <= 0x13EF) return cp + 0x97D0;
    return cp;
}

// ---------------------------------------------------------------------------
// Character classification
// ---------------------------------------------------------------------------

fn charAlphabeticP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return if (isUnicodeLetter(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charNumericP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return if (isUnicodeNumeric(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charWhitespaceP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return if (isUnicodeWhitespace(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charUpperCaseP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return if (isUnicodeUppercase(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

fn charLowerCaseP(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return if (isUnicodeLowercase(types.toChar(args[0]))) types.TRUE else types.FALSE;
}

// ---------------------------------------------------------------------------
// Case operations
// ---------------------------------------------------------------------------

fn charUpcaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return types.makeChar(unicodeUpcase(types.toChar(args[0])));
}

fn charDowncaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    return types.makeChar(unicodeDowncase(types.toChar(args[0])));
}

fn charFoldcaseFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const cp = types.toChar(args[0]);
    return types.makeChar(switch (cp) {
        0x017F => 's',
        else => unicodeDowncase(cp),
    });
}

// ---------------------------------------------------------------------------
// digit-value
// ---------------------------------------------------------------------------

fn digitValueFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
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
    return unicodeDowncase(cp);
}

fn compareCiChars(args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        if (!types.isChar(args[i]) or !types.isChar(args[i + 1])) return PrimitiveError.TypeError;
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
    return compareCiChars(args, .lt);
}

fn charCiLeFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .le);
}

fn charCiEqFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .eq);
}

fn charCiGeFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .ge);
}

fn charCiGtFn(args: []const Value) PrimitiveError!Value {
    return compareCiChars(args, .gt);
}

// ---------------------------------------------------------------------------
// Case-insensitive string comparison
// ---------------------------------------------------------------------------

fn foldCompareStrings(a: []const u8, b: []const u8) std.math.Order {
    // Compare codepoints after case-folding
    var ai: usize = 0;
    var bi: usize = 0;
    while (ai < a.len and bi < b.len) {
        const a_len = std.unicode.utf8ByteSequenceLength(a[ai]) catch 1;
        const b_len = std.unicode.utf8ByteSequenceLength(b[bi]) catch 1;
        const a_cp = if (ai + a_len <= a.len)
            (std.unicode.utf8Decode(a[ai .. ai + a_len]) catch @as(u21, a[ai]))
        else
            @as(u21, a[ai]);
        const b_cp = if (bi + b_len <= b.len)
            (std.unicode.utf8Decode(b[bi .. bi + b_len]) catch @as(u21, b[bi]))
        else
            @as(u21, b[bi]);
        const fa = unicodeDowncase(a_cp);
        const fb = unicodeDowncase(b_cp);
        if (fa < fb) return .lt;
        if (fa > fb) return .gt;
        ai += a_len;
        bi += b_len;
    }
    if (ai < a.len) return .gt;
    if (bi < b.len) return .lt;
    return .eq;
}

fn compareCiStrings(args: []const Value, comptime cmp: enum { lt, le, eq, ge, gt }) PrimitiveError!Value {
    for (0..args.len - 1) |i| {
        const a = try getStringSlice(args[i]);
        const b = try getStringSlice(args[i + 1]);
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
    return compareCiStrings(args, .lt);
}

fn stringCiLeFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .le);
}

fn stringCiEqFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .eq);
}

fn stringCiGeFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .ge);
}

fn stringCiGtFn(args: []const Value) PrimitiveError!Value {
    return compareCiStrings(args, .gt);
}

// ---------------------------------------------------------------------------
// String case operations
// ---------------------------------------------------------------------------

fn stringCaseMap(data: []const u8, comptime case_fn: fn (u21) u21) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const data = try getStringSlice(args[0]);
    return stringCaseMapExpanding(data, .upcase);
}

fn stringDowncaseFn(args: []const Value) PrimitiveError!Value {
    const data = try getStringSlice(args[0]);
    return stringCaseMapExpanding(data, .downcase);
}

fn stringFoldcaseFn(args: []const Value) PrimitiveError!Value {
    const data = try getStringSlice(args[0]);
    return stringCaseMapExpanding(data, .foldcase);
}

const CaseMode = enum { upcase, downcase, foldcase };

fn appendCodepoint(result: *std.ArrayList(u8), alloc: std.mem.Allocator, cp: u21) PrimitiveError!void {
    var tmp: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &tmp) catch return PrimitiveError.OutOfMemory;
    result.appendSlice(alloc, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
}

fn stringCaseMapExpanding(data: []const u8, mode: CaseMode) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
                    0x00DF => { try appendCodepoint(&result, gc.allocator, 'S'); try appendCodepoint(&result, gc.allocator, 'S'); },
                    0x01F0 => { try appendCodepoint(&result, gc.allocator, 'J'); try appendCodepoint(&result, gc.allocator, 0x030C); },
                    0x0390 => { try appendCodepoint(&result, gc.allocator, 0x0399); try appendCodepoint(&result, gc.allocator, 0x0308); try appendCodepoint(&result, gc.allocator, 0x0301); },
                    0x03B0 => { try appendCodepoint(&result, gc.allocator, 0x03A5); try appendCodepoint(&result, gc.allocator, 0x0308); try appendCodepoint(&result, gc.allocator, 0x0301); },
                    0xFB00 => { try appendCodepoint(&result, gc.allocator, 'F'); try appendCodepoint(&result, gc.allocator, 'F'); },
                    0xFB01 => { try appendCodepoint(&result, gc.allocator, 'F'); try appendCodepoint(&result, gc.allocator, 'I'); },
                    0xFB02 => { try appendCodepoint(&result, gc.allocator, 'F'); try appendCodepoint(&result, gc.allocator, 'L'); },
                    0xFB03 => { try appendCodepoint(&result, gc.allocator, 'F'); try appendCodepoint(&result, gc.allocator, 'F'); try appendCodepoint(&result, gc.allocator, 'I'); },
                    0xFB04 => { try appendCodepoint(&result, gc.allocator, 'F'); try appendCodepoint(&result, gc.allocator, 'F'); try appendCodepoint(&result, gc.allocator, 'L'); },
                    else => try appendCodepoint(&result, gc.allocator, unicodeUpcase(cp)),
                }
            },
            .downcase => {
                switch (cp) {
                    0x0130 => { try appendCodepoint(&result, gc.allocator, 0x0069); try appendCodepoint(&result, gc.allocator, 0x0307); },
                    0x03A3 => {
                        // Greek final sigma: Σ at end of word → ς
                        const next_cp = blk: {
                            const ni = i + seq_len;
                            if (ni >= data.len) break :blk @as(?u21, null);
                            const nsl = std.unicode.utf8ByteSequenceLength(data[ni]) catch break :blk @as(?u21, null);
                            if (ni + nsl > data.len) break :blk @as(?u21, null);
                            break :blk std.unicode.utf8Decode(data[ni .. ni + nsl]) catch null;
                        };
                        const next_is_cased = if (next_cp) |nc| isUnicodeLetter(nc) else false;
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
                    0x00DF => { try appendCodepoint(&result, gc.allocator, 's'); try appendCodepoint(&result, gc.allocator, 's'); },
                    0x0130 => { try appendCodepoint(&result, gc.allocator, 0x0069); try appendCodepoint(&result, gc.allocator, 0x0307); },
                    0x017F => try appendCodepoint(&result, gc.allocator, 's'),
                    0x01F0 => { try appendCodepoint(&result, gc.allocator, 'j'); try appendCodepoint(&result, gc.allocator, 0x030C); },
                    0x03A3 => try appendCodepoint(&result, gc.allocator, 0x03C3),
                    else => try appendCodepoint(&result, gc.allocator, unicodeDowncase(cp)),
                }
            },
        }
        prev_cased = isUnicodeLetter(cp);
        i += seq_len;
    }
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

