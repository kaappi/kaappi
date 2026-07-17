// Phase 7: Exceptions (R7RS 6.11)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const VMError = th.VMError;

test "guard basic catch" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(guard (e (#t e)) (raise 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "absurd payload requests raise catchable errors on every OS (FreeBSD overcommit)" {
    // Overcommitting kernels (FreeBSD's default) reserve a 100 TB malloc
    // happily and die at the zero-fill; the GC's max_payload_bytes cap
    // must fail these before touching the OS (docs/dev/freebsd.md).
    try th.expectEvalTrue("(guard (e (#t #t)) (make-bytevector 100000000000000) #f)");
    try th.expectEvalTrue("(guard (e (#t #t)) (make-vector 100000000000000) #f)");
    try th.expectEvalTrue("(guard (e (#t #t)) (make-string 100000000000000) #f)");
}

test "guard with error-object" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e ((error-object? e) (error-object-message e)))
        \\  (error "oops" 1 2))
    );
    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("oops", str.data[0..str.len]);
}

test "guard with else clause" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e (else 99))
        \\  (error "test"))
    );
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "guard no exception" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(guard (e (else 99)) (+ 1 2))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "with-exception-handler basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Exercise with-exception-handler directly via call/cc to escape
    const result = try vm.eval(
        \\(call-with-current-continuation
        \\  (lambda (k)
        \\    (with-exception-handler
        \\      (lambda (e) (k 42))
        \\      (lambda () (raise "boom")))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "with-exception-handler normal return" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(with-exception-handler
        \\  (lambda (e) 99)
        \\  (lambda () (+ 1 2)))
    );
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "error-object predicates" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval(
        \\(guard (e (#t (error-object? e)))
        \\  (error "msg"))
    );
    try std.testing.expectEqual(types.TRUE, r1);

    // Non-error-object
    const r2 = try vm.eval(
        \\(guard (e (#t (error-object? e)))
        \\  (raise 42))
    );
    try std.testing.expectEqual(types.FALSE, r2);
}

test "error-object-irritants" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e ((error-object? e) (error-object-irritants e)))
        \\  (error "msg" 1 2 3))
    );
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(types.cdr(types.cdr(result)))));
}

test "file-error? and read-error?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-error? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(read-error? 42)"));
}

test "raise without handler is error" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval("(raise 42)");
    try std.testing.expectError(VMError.ExceptionRaised, result);
}

test "guard with multiple clauses" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // First clause doesn't match, second does
    const result = try vm.eval(
        \\(guard (e
        \\         ((string? e) 1)
        \\         ((number? e) 2)
        \\         (else 3))
        \\  (raise 42))
    );
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "nested guard" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (outer (#t (+ outer 100)))
        \\  (guard (inner (#t (+ inner 10)))
        \\    (raise 1)))
    );
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "uncaught (error ...) formats message and irritants into error detail" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval("(error \"index out of range\" 5)");
    try std.testing.expectError(VMError.ExceptionRaised, result);
    try std.testing.expectEqualStrings("index out of range 5", vm.getErrorDetail());
}

test "uncaught raise of non-error value reports the raised value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval("(raise 42)");
    try std.testing.expectError(VMError.ExceptionRaised, result);
    try std.testing.expectEqualStrings("uncaught exception: 42", vm.getErrorDetail());
}

test "uncaught (error ...) with string irritant writes the irritant" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval("(error \"bad input\" \"foo\" 7)");
    try std.testing.expectError(VMError.ExceptionRaised, result);
    try std.testing.expectEqualStrings("bad input \"foo\" 7", vm.getErrorDetail());
}

test "caught exception does not populate error detail" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(guard (e (#t 'ok)) (error \"boom\" 1))");
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("", vm.getErrorDetail());
}
