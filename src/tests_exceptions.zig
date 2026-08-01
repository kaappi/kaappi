// Phase 7: Exceptions (R7RS 6.11)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const errors = @import("errors.zig");
const diagnostics = @import("diagnostics.zig");
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

test "guard clauses run in the guard's own dynamic environment (#1988)" {
    // R7RS 4.2.7. The outer guard is outside the parameterize, so its clause
    // must see p = 1. It used to see 2: the clauses were evaluated at the raise
    // point, which for the raise-continuable a declining inner guard issues is
    // still inside the parameterize.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define p (make-parameter 1))");
    const result = try ctx.vm.eval(
        \\(guard (e (#t (p)))
        \\  (parameterize ((p 2))
        \\    (guard (e ((number? e) 'no-match))
        \\      (raise 'boom))))
    );
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result));
}

test "a declining guard's after-thunks run before the outer clauses (#1988)" {
    // Same defect through dynamic-wind: the after thunk belongs to an extent
    // the outer clause is outside of, so it runs on the way out, not after.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define log '())");
    _ = try ctx.vm.eval(
        \\(guard (e (#t (set! log (cons 'clause log))))
        \\  (dynamic-wind
        \\    (lambda () (set! log (cons 'before log)))
        \\    (lambda () (guard (e ((number? e) 'no-match)) (raise 'x)))
        \\    (lambda () (set! log (cons 'after log)))))
    );
    const ordered = try ctx.vm.eval("(equal? (reverse log) '(before after clause))");
    try std.testing.expectEqual(types.TRUE, ordered);
}

test "a declining guard strands no exception handler (#1988)" {
    // The implicit re-raise pops the guard's handler and the outer one escapes,
    // so the pop stands. Re-pushing left one stale entry per declining guard:
    // the next raise found it and called an escape whose extent had ended.
    try th.expectEval(
        \\(with-exception-handler
        \\  (lambda (e) 7)
        \\  (lambda ()
        \\    (guard (e (#t 'caught)) (raise-continuable 'x))
        \\    (raise-continuable 'y)))
    , 7);
}

test "a guard clause can still reinstate a continuation from the body (#1988)" {
    // The unwind that puts the clauses in the guard's dynamic environment must
    // leave the call stack alone: (srfi 255)'s restarters escape from a clause
    // into a continuation captured inside the guard body.
    try th.expectEval(
        \\(guard (c (#t ((cdr c) 99)))
        \\  (call-with-current-continuation
        \\    (lambda (k)
        \\      (with-exception-handler
        \\        (lambda (e) (raise-continuable (cons e k)))
        \\        (lambda () (error "boom") 'not-reached)))))
    , 99);
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

// -- #1886: growable handler/wind stacks, and uncatchable VM limits ---------
//
// Both stacks were fixed 64-entry inline arrays, and the overflow past them
// reached the program as an ordinary catchable error object -- so an
// enclosing `guard` swallowed it and the program returned a wrong value with
// exit 0. The Scheme-visible depth cases live in
// tests/scheme/smoke/handler-wind-depth-1886.scm; what needs Zig is the
// error *identity* (the point of the bug was that it was lost) and the hard
// limit itself, which no Scheme program can reach before running out of
// frames first.

test "nested guard past the old 64-handler cap returns each level's own value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define (f n)
        \\  (guard (e (#t n))
        \\    (if (= n 0) (raise 'b) (f (- n 1)))))
    );
    // 63 worked before the fix; 64 returned 1 and 100 returned 37. 90 forces
    // a real reallocation (the 65th push grows 64 -> 128) and is the deepest
    // this may go: `guard` costs two native re-entrancy frames per level
    // (call/ec + with-exception-handler), and callReentrant's own cap is 200
    // in a Debug build, so nested guard tops out at 99 there — measured, not
    // estimated. Growth across *several* doublings is covered by the
    // direct-push test below, which needs no re-entrancy at all.
    for ([_]i64{ 63, 64, 65, 90 }) |depth| {
        var buf: [64]u8 = undefined;
        const src = try std.fmt.bufPrint(&buf, "(f {d})", .{depth});
        const result = try vm.eval(src);
        try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result));
    }
}

test "handler stack grows past its initial capacity" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const initial = vm.handler_stack.len;
    const target = initial * 4;
    for (0..target) |_| try vm.pushHandler(types.FALSE);
    try std.testing.expectEqual(target, vm.handler_count);
    try std.testing.expect(vm.handler_stack.len >= target);
    // The entries survived the reallocations that grew the buffer.
    for (vm.handler_stack[0..vm.handler_count]) |h| {
        try std.testing.expectEqual(types.FALSE, h.handler);
    }
    for (0..target) |_| vm.popHandler();
}

test "wind stack grows past its initial capacity" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const target = vm.wind_stack.len * 4;
    for (0..target) |_| {
        try vm.ensureWindCapacity(vm.wind_count + 1);
        vm.wind_stack[vm.wind_count] = .{ .before = types.FALSE, .after = types.TRUE };
        vm.wind_count += 1;
    }
    try std.testing.expectEqual(target, vm.wind_count);
    for (vm.wind_stack[0..vm.wind_count]) |wr| {
        try std.testing.expectEqual(types.FALSE, wr.before);
        try std.testing.expectEqual(types.TRUE, wr.after);
    }
    vm.wind_count = 0;
}

test "exceeding the hard handler limit is StackOverflow, not OutOfMemory" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // KP9002 out-of-memory was the reported code; nothing failed to allocate.
    try std.testing.expectError(
        VMError.StackOverflow,
        vm.ensureHandlerCapacity(vm_mod.MAX_HANDLER_LIMIT + 1),
    );
    try std.testing.expectError(
        VMError.StackOverflow,
        vm.ensureWindCapacity(vm_mod.MAX_WIND_LIMIT + 1),
    );
    // Mapped to KP3008, the code the diagnostics registry already had for it.
    try std.testing.expectEqual(
        diagnostics.Code.stack_overflow,
        diagnostics.runtimeErrorCode(VMError.StackOverflow),
    );
}

test "a stack overflow is not catchable by guard" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Unbounded non-tail recursion exhausts the frame stack. Before #1886 the
    // guard clause ran and this evaluated to 'caught with no error at all.
    const result = vm.eval(
        \\(define (deep n) (+ 1 (deep (+ n 1))))
        \\(guard (e (#t 'caught)) (deep 0))
    );
    try std.testing.expectError(VMError.StackOverflow, result);
}

test "with-exception-handler does not convert a stack overflow into a condition" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval(
        \\(define (deep n) (+ 1 (deep (+ n 1))))
        \\(with-exception-handler (lambda (e) 'swallowed) (lambda () (deep 0)))
    );
    try std.testing.expectError(VMError.StackOverflow, result);
}

test "genuine program faults stay catchable" {
    // The uncatchable set is limits and control signals only -- a type error,
    // an unbound variable, or a bad index is still exactly what guard is for.
    try th.expectEvalTrue("(guard (e (#t #t)) (car 5))");
    try th.expectEvalTrue("(guard (e (#t #t)) (no-such-variable-at-all))");
    try th.expectEvalTrue("(guard (e (#t #t)) (vector-ref (vector 1 2) 99))");
    try th.expectEvalTrue("(guard (e (#t #t)) (/ 1 0))");
}

test "isUncatchable covers limits and signals but not program faults" {
    // A new KaappiError tag defaults to catchable; this pins the intent so
    // adding one is a deliberate decision rather than a silent default.
    try std.testing.expect(errors.isUncatchable(error.StackOverflow));
    try std.testing.expect(errors.isUncatchable(error.ExecutionTimeout));
    try std.testing.expect(errors.isUncatchable(error.Terminated));
    try std.testing.expect(errors.isUncatchable(error.Yielded));

    try std.testing.expect(!errors.isUncatchable(error.TypeError));
    try std.testing.expect(!errors.isUncatchable(error.ArityMismatch));
    try std.testing.expect(!errors.isUncatchable(error.UndefinedVariable));
    try std.testing.expect(!errors.isUncatchable(error.DivisionByZero));
    try std.testing.expect(!errors.isUncatchable(error.IndexOutOfBounds));
    try std.testing.expect(!errors.isUncatchable(error.InvalidArgument));
    try std.testing.expect(!errors.isUncatchable(error.NotAProcedure));
    try std.testing.expect(!errors.isUncatchable(error.ExceptionRaised));
    // Handled by each catch site before this predicate is consulted.
    try std.testing.expect(!errors.isUncatchable(error.ContinuationInvoked));
    // Overloaded: also the payload-size cap. See isUncatchable's doc comment.
    try std.testing.expect(!errors.isUncatchable(error.OutOfMemory));
}
