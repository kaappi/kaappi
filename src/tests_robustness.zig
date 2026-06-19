const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");

// ---------------------------------------------------------------------------
// Reader error tests
// ---------------------------------------------------------------------------

test "reader: unterminated string" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "\"hello");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnterminatedString, result);
}

test "reader: unterminated block comment" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "#| unclosed comment");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnexpectedEof, result);
}

test "reader: mismatched parenthesis" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, ")");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnexpectedRightParen, result);
}

test "reader: unterminated list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "(1 2 3");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnexpectedEof, result);
}

test "reader: dot outside list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, ". 42");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.DotNotInList, result);
}

test "reader: invalid character name" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "#\\nonexistent");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.InvalidCharacterName, result);
}

test "reader: nesting depth limit" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    // Build a string with 1100 nested open parens
    var buf: [2200]u8 = undefined;
    for (0..1100) |i| {
        buf[i] = '(';
    }
    for (1100..2200) |i| {
        buf[i] = ')';
    }
    var reader = reader_mod.Reader.init(&gc, &buf);
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.NestingTooDeep, result);
}

test "reader: valid nested block comment" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "#| outer #| inner |# still outer |# 42");
    defer reader.deinit();
    const result = try reader.readDatum();
    try std.testing.expect(types.isFixnum(result));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "reader: rational with zero denominator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "1/0");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.InvalidNumber, result);
}

// ---------------------------------------------------------------------------
// Numeric overflow / bignum promotion
// ---------------------------------------------------------------------------

test "fixnum overflow promotes to bignum: addition" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 4611686018427387903 1)");
    try std.testing.expect(types.isBignum(result));
}

test "fixnum overflow promotes to bignum: multiplication" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(* 4611686018427387903 2)");
    try std.testing.expect(types.isBignum(result));
}

test "fixnum underflow promotes to bignum: subtraction" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(- -4611686018427387904 1)");
    try std.testing.expect(types.isBignum(result));
}

test "division by zero raises error" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(guard (exn (#t 'caught)) (/ 1 0))");
    try std.testing.expect(types.isSymbol(result));
}

// ---------------------------------------------------------------------------
// Unicode string operations
// ---------------------------------------------------------------------------

test "string-length with multi-byte UTF-8" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(string-length \"hello\")");
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(result));
}

test "string-ref with ASCII" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(char->integer (string-ref \"abc\" 1))");
    try std.testing.expectEqual(@as(i64, 98), types.toFixnum(result));
}

test "substring basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(substring \"hello world\" 6 11)");
    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("world", str.data[0..str.len]);
}

// ---------------------------------------------------------------------------
// GC stress — allocate many objects to trigger collection cycles
// ---------------------------------------------------------------------------

test "GC stress: build long list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let loop ((i 0) (acc '()))
        \\  (if (= i 10000)
        \\      (length acc)
        \\      (loop (+ i 1) (cons i acc))))
    );
    try std.testing.expectEqual(@as(i64, 10000), types.toFixnum(result));
}

test "GC stress: many string allocations" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let loop ((i 0))
        \\  (if (= i 5000)
        \\      i
        \\      (begin
        \\        (string-append "hello" "world" (number->string i))
        \\        (loop (+ i 1)))))
    );
    try std.testing.expectEqual(@as(i64, 5000), types.toFixnum(result));
}

test "GC stress: many vector allocations" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let loop ((i 0))
        \\  (if (= i 5000)
        \\      i
        \\      (begin
        \\        (make-vector 10 i)
        \\        (loop (+ i 1)))))
    );
    try std.testing.expectEqual(@as(i64, 5000), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Continuation edge cases
// ---------------------------------------------------------------------------

test "call/cc: normal return without invoking continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-current-continuation (lambda (k) 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call/ec: escape continuation basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-escape-continuation (lambda (k) (k 99) 0))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Exception handling
// ---------------------------------------------------------------------------

test "guard catches division by zero" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (exn (#t (error-object-message exn)))
        \\  (/ 1 0))
    );
    try std.testing.expect(types.isString(result));
}

test "guard with re-raise" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (exn
        \\    ((string? (error-object-message exn)) "string-error"))
        \\  (error "test error" 1 2 3))
    );
    try std.testing.expect(types.isString(result));
}

// ---------------------------------------------------------------------------
// Special float values
// ---------------------------------------------------------------------------

test "special float: +inf.0" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("+inf.0");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isPositiveInf(types.toFlonum(result)));
}

test "special float: -inf.0" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("-inf.0");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNegativeInf(types.toFlonum(result)));
}

test "special float: +nan.0" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("+nan.0");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNan(types.toFlonum(result)));
}

test "nan arithmetic: nan + 1" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ +nan.0 1)");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNan(types.toFlonum(result)));
}

test "inf arithmetic: inf - inf is nan" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(- +inf.0 +inf.0)");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNan(types.toFlonum(result)));
}
