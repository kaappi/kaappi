// Phase 9: Ports and I/O (R7RS 6.13)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "current-output-port returns a port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(port? (current-output-port))"));
}

test "current-input-port returns an input port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(input-port? (current-input-port))"));
}

test "current-output-port is an output port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port? (current-output-port))"));
}

test "current-error-port is an output port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port? (current-error-port))"));
}

test "port predicates on non-port values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(port? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(port? #t)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(port? '())"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(input-port? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(output-port? \"hello\")"));
}

test "input-port-open? and output-port-open?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(input-port-open? (current-input-port))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port-open? (current-output-port))"));
}

test "textual-port? returns true for ports" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(textual-port? (current-output-port))"));
}

test "eof-object and eof-object?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(eof-object? (eof-object))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eof-object? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eof-object? #f)"));
}

test "write to file and read back with read-line" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Write to a temp file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-readline.txt"))
    );
    _ = try vm.eval(
        \\(write-string "hello world" p)
    );
    _ = try vm.eval("(newline p)");
    _ = try vm.eval("(close-port p)");

    // Read it back
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-readline.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    _ = try vm.eval("(close-port p2)");

    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("hello world", str.data[0..str.len]);
}

test "write-char and read-char" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Write chars to a temp file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-char.txt"))
    );
    _ = try vm.eval("(write-char #\\A p)");
    _ = try vm.eval("(write-char #\\B p)");
    _ = try vm.eval("(write-char #\\C p)");
    _ = try vm.eval("(close-port p)");

    // Read chars back
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-char.txt"))
    );
    const r1 = try vm.eval("(read-char p2)");
    try std.testing.expect(types.isChar(r1));
    try std.testing.expectEqual(@as(u21, 'A'), types.toChar(r1));

    const r2 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(@as(u21, 'B'), types.toChar(r2));

    const r3 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(@as(u21, 'C'), types.toChar(r3));

    // Should get EOF
    const r4 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(types.EOF, r4);

    _ = try vm.eval("(close-port p2)");
}

test "peek-char does not consume" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-peek.txt"))
    );
    _ = try vm.eval("(write-char #\\X p)");
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-peek.txt"))
    );
    // Peek should return X without consuming
    const r1 = try vm.eval("(peek-char p2)");
    try std.testing.expect(types.isChar(r1));
    try std.testing.expectEqual(@as(u21, 'X'), types.toChar(r1));

    // Read should also return X (peeked byte)
    const r2 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(@as(u21, 'X'), types.toChar(r2));

    // Now should get EOF
    const r3 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(types.EOF, r3);

    _ = try vm.eval("(close-port p2)");
}

test "close-port marks port as closed" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-close.txt"))
    );
    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port-open? p)"));
    _ = try vm.eval("(close-port p)");
    try std.testing.expectEqual(types.FALSE, try vm.eval("(output-port-open? p)"));
}

test "file-exists?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Create a file first
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-exists.txt"))
    );
    _ = try vm.eval("(close-port p)");

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(file-exists? "/tmp/kaappi-test-exists.txt")
    ));
    try std.testing.expectEqual(types.FALSE, try vm.eval(
        \\(file-exists? "/tmp/kaappi-nonexistent-file-12345.txt")
    ));
}

test "file-exists? returns #t for unreadable files" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const path: [*:0]const u8 = "/tmp/kaappi-test-noperm.txt";

    // Create a file via Scheme, then remove all permissions
    _ = try vm.eval(
        \\(let ((p (open-output-file "/tmp/kaappi-test-noperm.txt"))) (close-port p))
    );
    if (std.c.chmod(path, 0o000) != 0) return error.SkipZigTest;
    defer _ = std.posix.system.unlink(path);

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(file-exists? "/tmp/kaappi-test-noperm.txt")
    ));
}

test "file-exists? returns #t for FIFOs" {
    if (comptime @import("builtin").os.tag == .wasi) return error.SkipZigTest;
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const path: [*:0]const u8 = "/tmp/kaappi-test-fifo";
    _ = std.posix.system.unlink(path);
    const mkfifo = @extern(*const fn ([*:0]const u8, std.c.mode_t) callconv(.c) c_int, .{ .name = "mkfifo" });
    if (mkfifo(path, 0o644) != 0) return error.SkipZigTest;
    defer _ = std.posix.system.unlink(path);

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(file-exists? "/tmp/kaappi-test-fifo")
    ));
}

test "read datum from file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Write a Scheme expression to a file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-read.txt"))
    );
    _ = try vm.eval(
        \\(write-string "(+ 1 2)" p)
    );
    _ = try vm.eval("(close-port p)");

    // Read it back as a datum
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-read.txt"))
    );
    const result = try vm.eval("(read p2)");
    _ = try vm.eval("(close-port p2)");

    // Result should be the list (+ 1 2)
    try std.testing.expect(types.isPair(result));
    try std.testing.expect(types.isSymbol(types.car(result)));
    try std.testing.expectEqualStrings("+", types.symbolName(types.car(result)));
}

test "display and write with port argument" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Write using display with port argument
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-display.txt"))
    );
    _ = try vm.eval(
        \\(display "hello" p)
    );
    _ = try vm.eval("(display 42 p)");
    _ = try vm.eval("(close-port p)");

    // Read back
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-display.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    _ = try vm.eval("(close-port p2)");

    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("hello42", str.data[0..str.len]);
}

test "open-input-file on port is an input port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Create a file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-iport.txt"))
    );
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-iport.txt"))
    );
    try std.testing.expectEqual(types.TRUE, try vm.eval("(port? p2)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(input-port? p2)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(output-port? p2)"));
    _ = try vm.eval("(close-port p2)");
}

test "read-line returns eof on empty file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Create an empty file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-empty.txt"))
    );
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-empty.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    try std.testing.expectEqual(types.EOF, result);
    _ = try vm.eval("(close-port p2)");
}

test "read-line with multiple lines" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Write multiple lines
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-multiline.txt"))
    );
    _ = try vm.eval(
        \\(write-string "line1" p)
    );
    _ = try vm.eval("(newline p)");
    _ = try vm.eval(
        \\(write-string "line2" p)
    );
    _ = try vm.eval("(newline p)");
    _ = try vm.eval("(close-port p)");

    // Read lines
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-multiline.txt"))
    );

    const r1 = try vm.eval("(read-line p2)");
    try std.testing.expect(types.isString(r1));
    const s1 = types.toObject(r1).as(types.SchemeString);
    try std.testing.expectEqualStrings("line1", s1.data[0..s1.len]);

    const r2 = try vm.eval("(read-line p2)");
    try std.testing.expect(types.isString(r2));
    const s2 = types.toObject(r2).as(types.SchemeString);
    try std.testing.expectEqualStrings("line2", s2.data[0..s2.len]);

    _ = try vm.eval("(close-port p2)");
}

test "write to port with write procedure" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-write.txt"))
    );
    _ = try vm.eval(
        \\(write "quoted" p)
    );
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-write.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    _ = try vm.eval("(close-port p2)");

    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    // write should produce quoted output
    try std.testing.expectEqualStrings("\"quoted\"", str.data[0..str.len]);
}

test "import scheme file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (scheme file))");
    // After import, open-input-file should be available
    try std.testing.expectEqual(types.TRUE, try vm.eval("(procedure? open-input-file)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(procedure? open-output-file)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(procedure? file-exists?)"));
}

test "read-string 0 on non-exhausted port returns empty string, not eof (issue #815)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define p (open-input-string \"abc\"))");

    // k = 0 with input available: empty string, NOT eof
    const zero = try vm.eval("(read-string 0 p)");
    try std.testing.expect(types.isString(zero));
    const zstr = types.toObject(zero).as(types.SchemeString);
    try std.testing.expectEqualStrings("", zstr.data[0..zstr.len]);
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eof-object? (read-string 0 p))"));

    // Reading remaining characters still works normally afterwards.
    const all = try vm.eval("(read-string 3 p)");
    const astr = types.toObject(all).as(types.SchemeString);
    try std.testing.expectEqualStrings("abc", astr.data[0..astr.len]);

    // k > 0 at EOF still returns eof.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(eof-object? (read-string 3 p))"));
    // k = 0 at EOF returns empty string (port exhausted, but zero requested).
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eof-object? (read-string 0 p))"));
}

// Regression: #811 — current-output-port must be a parameter object
test "parameterize current-output-port redirects display" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(define sp (open-output-string))
        \\(parameterize ((current-output-port sp))
        \\  (display "hello"))
        \\(get-output-string sp)
    );
    const s = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("hello", s.data[0..s.len]);
}

test "read after peek-char preserves stream order (#804)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let ((p (open-input-string "(x)abc de")))
        \\  (let ((r1 (read p)))
        \\    (let ((pc (peek-char p)))
        \\      (let ((r2 (read p)))
        \\        (let ((r3 (read p)))
        \\          (let ((sp (open-output-string)))
        \\            (write (list r1 pc r2 r3) sp)
        \\            (get-output-string sp)))))))
    );
    const s = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("((x) #\\a abc de)", s.data[0..s.len]);
}

test "parameterize current-input-port redirects read-line" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(parameterize ((current-input-port (open-input-string "test-line")))
        \\  (read-line))
    );
    const s = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("test-line", s.data[0..s.len]);
}

test "current-input-port survives extreme GC pressure (#1013)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.gc_threshold = 1;
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(input-port? (current-input-port))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port? (current-output-port))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port? (current-error-port))"));
}
