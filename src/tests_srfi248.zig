// SRFI 248 (minimal delimited continuations) unit tests. with-unwind-handler,
// empty-continuation?, and the extended guard live in lib/srfi/248.sld and build
// on the sticky-handler VM primitives added to primitives_control.zig, so these
// import the portable library from the source tree's lib/ directory.
const std = @import("std");
const types = @import("types.zig");
const th = @import("testing_helpers.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn ctxWith248(ctx: *th.TestContext) !void {
    try ctx.init();
    // zig build test runs from the repo root, so lib/srfi/248.sld is reachable
    // via the "lib" search path.
    ctx.vm.lib_paths = &[_][]const u8{"lib"};
    _ = try ctx.vm.eval("(import (srfi 248))");
}

fn fix(ctx: *th.TestContext, src: []const u8) !i64 {
    return types.toFixnum(try ctx.vm.eval(src));
}

test "srfi 248: with-unwind-handler returns thunk result and catches raises" {
    var ctx: th.TestContext = undefined;
    try ctxWith248(&ctx);
    defer ctx.deinit();

    // No raise: with-unwind-handler yields the thunk's result.
    try expectEqual(@as(i64, 42), try fix(&ctx, "(with-unwind-handler (lambda (o k) 0) (lambda () (+ 40 2)))"));
    // raise-continuable is delivered to the handler.
    try expectEqual(@as(i64, 99), try fix(&ctx, "(with-unwind-handler (lambda (o k) o) (lambda () (raise-continuable 99)))"));
    // plain raise is delivered to the handler too.
    try expectEqual(@as(i64, 7), try fix(&ctx, "(with-unwind-handler (lambda (o k) o) (lambda () (raise 7) 0))"));
    // The handler can resume the delimited continuation, composing with the
    // current caller: k here is (lambda (v) (+ 1 v)).
    try expectEqual(@as(i64, 21), try fix(&ctx, "(with-unwind-handler (lambda (o k) (+ 1 (k 10))) (lambda () (* 2 (raise-continuable 'p))))"));
}

test "srfi 248: empty-continuation? distinguishes tail context" {
    var ctx: th.TestContext = undefined;
    try ctxWith248(&ctx);
    defer ctx.deinit();

    _ = try ctx.vm.eval(
        \\(define (probe thunk)
        \\  (with-unwind-handler (lambda (o k) (empty-continuation? k)) thunk))
    );
    // raise-continuable in tail position of the thunk -> empty continuation.
    try expect(types.isTruthy(try ctx.vm.eval("(probe (lambda () (raise-continuable 1)))")));
    // result consumed by an enclosing form -> non-empty.
    try expect(!types.isTruthy(try ctx.vm.eval("(probe (lambda () (not (raise-continuable 1))))")));
    try expect(!types.isTruthy(try ctx.vm.eval("(probe (lambda () (+ 1 (raise-continuable 1))))")));
    // tail raise inside a NON-tail-called helper is not empty: the continuation
    // is (not []). The immediate tail bit is true here, so this exercises the
    // frame_count baseline that distinguishes it.
    try expect(!types.isTruthy(try ctx.vm.eval("(probe (lambda () (not ((lambda () (raise-continuable 1))))))")));
    // whole call chain is tail -> empty.
    try expect(types.isTruthy(try ctx.vm.eval("(probe (lambda () ((lambda () (raise-continuable 1)))))")));
}

test "srfi 248: extended guard drives a coroutine generator" {
    var ctx: th.TestContext = undefined;
    try ctxWith248(&ctx);
    defer ctx.deinit();

    _ = try ctx.vm.eval(
        \\(define (make-gen proc)
        \\  (define (yield v) (raise-continuable (cons '&y v)))
        \\  (define thunk
        \\    (lambda ()
        \\      (guard (c k ((and (pair? c) (eq? (car c) '&y)) (set! thunk k) (cdr c)))
        \\        (proc yield)
        \\        'done)))
        \\  (lambda () (thunk)))
    );
    _ = try ctx.vm.eval("(define g (make-gen (lambda (y) (y 10) (y 20))))");
    try expectEqual(@as(i64, 10), types.toFixnum(try ctx.vm.eval("(g)")));
    try expectEqual(@as(i64, 20), types.toFixnum(try ctx.vm.eval("(g)")));
    try expect(types.isTruthy(try ctx.vm.eval("(eq? (g) 'done)")));
}

test "srfi 248: one-variable guard keeps R7RS behaviour" {
    var ctx: th.TestContext = undefined;
    try ctxWith248(&ctx);
    defer ctx.deinit();

    try expect(types.isTruthy(try ctx.vm.eval("(equal? (guard (e (#t (list 'caught e))) (raise 'oops)) '(caught oops))")));
    try expect(types.isTruthy(try ctx.vm.eval("(eq? (guard (e (else 'elsed)) (raise 'z)) 'elsed)")));
    // guard must still catch native runtime errors (car of a non-pair).
    try expect(types.isTruthy(try ctx.vm.eval("(eq? (guard (e (#t 'handled)) (car 5)) 'handled)")));
    // no clause matches -> re-raise to the outer handler.
    try expect(types.isTruthy(try ctx.vm.eval(
        \\(equal?
        \\  (with-exception-handler
        \\    (lambda (e) (list 'outer e))
        \\    (lambda () (guard (e ((eq? e 'never) 'no)) (raise-continuable 'boom))))
        \\  '(outer boom))
    )));
}

test "srfi 248: sticky handlers do not disturb ordinary with-exception-handler" {
    var ctx: th.TestContext = undefined;
    try ctxWith248(&ctx);
    defer ctx.deinit();

    // A plain with-exception-handler + raise-continuable still returns the
    // handler's value to the raise point, unaffected by the sticky machinery.
    try expectEqual(@as(i64, 5), try fix(&ctx, "(with-exception-handler (lambda (e) 5) (lambda () (raise-continuable 'x)))"));
}
