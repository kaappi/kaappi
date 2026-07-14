// Phase 10: Continuations (R7RS 6.10)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");

test "call/cc basic — proc returns normally" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-current-continuation (lambda (k) 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call/cc escape continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 1 (call/cc (lambda (k) (+ 2 (k 10)))))");
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "call/cc alias" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call/cc (lambda (k) (k 99)))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "call/cc continuation is a procedure" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call/cc (lambda (k) (procedure? k)))");
    try std.testing.expectEqual(types.TRUE, result);
}

test "call/cc nested escape" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Escape from nested computation
    const result = try vm.eval(
        \\(* 10 (call/cc (lambda (k)
        \\  (+ 1 (+ 2 (k 5))))))
    );
    try std.testing.expectEqual(@as(i64, 50), types.toFixnum(result));
}

test "call/cc with no invocation of continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Continuation is never invoked — proc returns normally
    const result = try vm.eval("(call/cc (lambda (k) (+ 3 4)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "dynamic-wind basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define log '())");
    _ = try vm.eval(
        \\(dynamic-wind
        \\  (lambda () (set! log (cons 'in log)))
        \\  (lambda () (set! log (cons 'body log)))
        \\  (lambda () (set! log (cons 'out log))))
    );
    const result = try vm.eval("(reverse log)");
    // Should be (in body out)
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqualStrings("in", types.symbolName(types.car(result)));
    try std.testing.expectEqualStrings("body", types.symbolName(types.car(types.cdr(result))));
    try std.testing.expectEqualStrings("out", types.symbolName(types.car(types.cdr(types.cdr(result)))));
}

test "dynamic-wind returns thunk result" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(dynamic-wind
        \\  (lambda () #f)
        \\  (lambda () 42)
        \\  (lambda () #f))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "values single value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(values 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call-with-values basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-values (lambda () (values 1 2 3)) +)");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(result));
}

test "call-with-values with list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-values (lambda () (values 1 2)) list)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
}

test "call-with-values single value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Single value should work like a normal call
    const result = try vm.eval("(call-with-values (lambda () 42) (lambda (x) (+ x 1)))");
    try std.testing.expectEqual(@as(i64, 43), types.toFixnum(result));
}

test "values with zero values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // (values) produces multiple values with zero elements
    const result = try vm.eval("(call-with-values (lambda () (values)) (lambda () 99))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

// Regression: #1169 — invoking a continuation with multiple arguments
// must deliver all values, not just the first.
test "call/cc multi-arg invocation in call-with-values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(call-with-values
        \\  (lambda () (call/cc (lambda (k) (k 1 2))))
        \\  list)
    );
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
    try std.testing.expectEqual(types.NIL, types.cdr(types.cdr(result)));
}

test "call/cc zero-arg invocation in call-with-values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(call-with-values
        \\  (lambda () (call/cc (lambda (k) (k))))
        \\  (lambda () 99))
    );
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "call/ec multi-arg invocation in call-with-values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(call-with-values
        \\  (lambda () (call/ec (lambda (k) (k 10 20 30))))
        \\  list)
    );
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 20), types.toFixnum(types.car(types.cdr(result))));
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(types.car(types.cdr(types.cdr(result)))));
}

test "apply continuation with multiple values (callWithArgs path)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(call-with-values
        \\  (lambda () (call/cc (lambda (k) (car (list (apply k (list 1 2)))))))
        \\  list)
    );
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
}

test "apply continuation with zero values (callWithArgs path)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(call-with-values
        \\  (lambda () (call/cc (lambda (k) (car (list (apply k '()))))))
        \\  (lambda () 99))
    );
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "first-class call-with-values continuation (callWithArgs path)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(define cwv call-with-values)
        \\(call-with-values
        \\  (lambda () (call/cc (lambda (k0) (cwv (lambda () (values 1 2)) k0))))
        \\  list)
    );
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
}

test "dynamic-wind with escape continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define log '())");
    const result = try vm.eval(
        \\(call/cc (lambda (k)
        \\  (dynamic-wind
        \\    (lambda () (set! log (cons 'in log)))
        \\    (lambda () (k 42))
        \\    (lambda () (set! log (cons 'out log))))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
    // After should have been called even though we escaped
    const log = try vm.eval("(reverse log)");
    try std.testing.expect(types.isPair(log));
    try std.testing.expectEqualStrings("in", types.symbolName(types.car(log)));
    try std.testing.expectEqualStrings("out", types.symbolName(types.car(types.cdr(log))));
}

test "nested call/cc — inner continuation escapes" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Inner continuation escapes while captured inside an outer call/cc.
    // Regression: previously returned NotAProcedure because the call/cc proc
    // frame was restored with dst=0 instead of the call/cc result register.
    const r1 = try vm.eval("(call/cc (lambda (o) (call/cc (lambda (i) (i 5)))))");
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(r1));

    const r2 = try vm.eval("(call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (i 5))))))");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(r2));

    const r3 = try vm.eval("(call/cc (lambda (o) (let ((x (call/cc (lambda (i) (i 5))))) (+ 1 x))))");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(r3));
}

test "nested call/cc — outer continuation escapes from inner" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r = try vm.eval("(call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (o 7))))))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r));
}

test "triple nested call/cc — innermost escapes" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r = try vm.eval(
        \\(call/cc (lambda (a)
        \\  (+ 1 (call/cc (lambda (b)
        \\    (+ 10 (call/cc (lambda (c) (c 100)))))))))
    );
    try std.testing.expectEqual(@as(i64, 111), types.toFixnum(r));
}

test "nested call/ec — inner escapes inside outer" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r = try vm.eval("(call/ec (lambda (o) (+ 1 (call/ec (lambda (i) (i 5))))))");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(r));
}

test "call/cc escape inside with-exception-handler thunk" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Regression: a continuation restored inside a re-entrant native call
    // (with-exception-handler runs its thunk via callThunk) used to unwind
    // to the outermost dispatch loop, abandoning the native's pending
    // result-register write — the expression returned the
    // with-exception-handler builtin instead of the escaped value.

    // call/cc in tail position of the thunk, k in tail position
    const r1 = try vm.eval(
        \\(with-exception-handler (lambda (e) 'err)
        \\  (lambda () (call/cc (lambda (k) (k 42)))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r1));

    // call/cc in tail position, k in non-tail position
    const r2 = try vm.eval(
        \\(with-exception-handler (lambda (e) 'err)
        \\  (lambda () (call/cc (lambda (k) (+ 0 (k 42))))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r2));

    // call/cc in non-tail position
    const r3 = try vm.eval(
        \\(with-exception-handler (lambda (e) 'err)
        \\  (lambda () (+ 1 (call/cc (lambda (k) (k 41))))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r3));
}

test "call/cc deep non-tail escape inside guard" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define (sum-to n k)
        \\  (if (= n 0) (k 'done) (+ n (sum-to (- n 1) k))))
    );
    const r = try vm.eval(
        \\(guard (e (#t 'caught))
        \\  (call/cc (lambda (k) (sum-to 20 k))))
    );
    try std.testing.expect(types.isSymbol(r));
    try std.testing.expectEqualStrings("done", types.symbolName(r));
}

test "nested call/cc escapes inside guard" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval(
        \\(guard (e (#t 'caught))
        \\  (call/cc (lambda (o) (call/cc (lambda (i) (i 5))))))
    );
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(r1));

    const r2 = try vm.eval(
        \\(guard (e (#t 'caught))
        \\  (call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (o 7)))))))
    );
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r2));
}

test "out-of-lineage restore inside dynamic-wind thunk" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The continuation captured in (deep 5) predates the dynamic-wind, so
    // invoking it inside the wind thunk must NOT be treated as the thunk
    // returning normally — the resumesHere birth-id check propagates it out
    // of dynamicWindFn instead (previously: wind_count underflow panic).
    const r = try vm.eval(
        \\(let ((k #f) (done (vector #f)))
        \\  (define (deep n)
        \\    (if (= n 0)
        \\        (call/cc (lambda (c) (set! k c) 0))
        \\        (+ 1 (deep (- n 1)))))
        \\  (deep 5)
        \\  (if (not (vector-ref done 0))
        \\      (begin
        \\        (vector-set! done 0 #t)
        \\        (dynamic-wind (lambda () #f) (lambda () (k 0)) (lambda () #f))))
        \\  'ok)
    );
    try std.testing.expect(types.isSymbol(r));
    try std.testing.expectEqualStrings("ok", types.symbolName(r));
}

test "dynamic-wind after-thunk runs on nested escape under guard" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define trace '())");
    const r = try vm.eval(
        \\(guard (e (#t 'caught))
        \\  (call/cc
        \\   (lambda (k)
        \\     (dynamic-wind
        \\       (lambda () (set! trace (cons 'before trace)))
        \\       (lambda () (set! trace (cons 'during trace)) (k 'out) (set! trace (cons 'never trace)))
        \\       (lambda () (set! trace (cons 'after trace)))))))
    );
    try std.testing.expectEqualStrings("out", types.symbolName(r));
    const log = try vm.eval("(reverse trace)");
    try std.testing.expectEqualStrings("before", types.symbolName(types.car(log)));
    try std.testing.expectEqualStrings("during", types.symbolName(types.car(types.cdr(log))));
    try std.testing.expectEqualStrings("after", types.symbolName(types.car(types.cdr(types.cdr(log)))));
}

test "dynamic-wind tail-called from a native-driven callback (#1377)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // member invokes the predicate via callWithArgs, which pushes a
    // returns_to_native frame; the predicate tail-calls dynamic-wind,
    // reusing that frame, so the wind pushed by dynamic-wind's own
    // bytecode sits above the frame's saved_wind_count. The Return
    // opcode's caller-wind cleanup used to unwind it as soon as the
    // wound thunk returned, making the subsequent %pop-wind underflow
    // (#1377 — same failure as dynamic-wind inside an SRFI-18 thread
    // thunk). The thunk must yield its value through a real `return`
    // opcode (not a native tail call) to reach that path.
    _ = try vm.eval("(define trace '())");
    _ = try vm.eval(
        \\(define result
        \\  (member 2 '(1 2 3)
        \\    (lambda (x y)
        \\      (dynamic-wind
        \\        (lambda () (set! trace (cons 'b trace)))
        \\        (lambda () (if (equal? x y) #t #f))
        \\        (lambda () (set! trace (cons 'a trace)))))))
    );
    // Predicate ran for 1 (no match) then 2 (match): before/after fired
    // exactly once per call and member returned the tail from the match.
    const ok = try vm.eval("(and (equal? result '(2 3)) (equal? trace '(a b a b)))");
    try std.testing.expectEqual(types.TRUE, ok);
}

test "full continuation re-entry inside map — generator-style" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Capture a full continuation inside a map callback, then reinvoke it
    // from a separate eval to resume the iteration with a different value.
    // This proves generator-style re-entry works: the continuation, when
    // invoked, resumes inside the map loop and map produces a new result.
    _ = try vm.eval("(define saved-k #f)");

    // First run: map directly (not inside define, so the continuation
    // captures a context whose return value is the map result itself).
    const result = try vm.eval(
        \\(map (lambda (x)
        \\       (if (= x 2)
        \\           (call/cc (lambda (k) (set! saved-k k) 20))
        \\           (* x 10)))
        \\     '(1 2 3))
    );
    // First run: (10 20 30) — call/cc returns 20 normally
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 20), types.toFixnum(types.car(types.cdr(result))));
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(types.car(types.cdr(types.cdr(result)))));

    // Re-invoke the saved continuation with 99 — resumes inside map,
    // which finishes with element 2 replaced by 99.
    const result2 = try vm.eval("(saved-k 99)");
    try std.testing.expect(types.isPair(result2));
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(types.car(result2)));
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(types.car(types.cdr(result2))));
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(types.car(types.cdr(types.cdr(result2)))));
}

test "escape continuation from inside map exits map early" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // map is now a Scheme closure — callbacks execute as regular bytecode
    // calls, so call/cc inside map works freely: an escape continuation
    // can abort the iteration and deliver a value to the outer context.
    const result = try vm.eval(
        \\(call/cc (lambda (return)
        \\  (map (lambda (x) (if (= x 2) (return 'escaped) x))
        \\       '(1 2 3))
        \\  'not-reached))
    );
    try std.testing.expectEqualStrings("escaped", types.symbolName(result));
}

// Regression (#1464, fuzz-derived): call/cc must not snapshot stale pointers
// left in dead "gap" registers between live frame windows. The first form
// leaves heap pointers in low registers; the guard/call/cc form then captures
// a contiguous register range spanning those now-dead slots. Under gc-stress
// the collector frees the stale targets — markVMRoots walks only per-frame
// windows, so nothing keeps them alive — and marking the continuation's
// snapshot would dereference a freed object without the gap-clearing fix.
test "call/cc does not capture stale gap registers (#1464)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Evaluating without a crash (especially under -Dgc-stress=true) is the
    // assertion; the second form's value (1) is incidental.
    const result = try vm.eval(
        \\(define g0 (let* ((h '(1 2 3)) (u (lambda (a b c) c))) 0))
        \\(guard (e (#t 1)) (call/cc (lambda (k) (let ((u (lambda (a b) b)) (v 1)) v))))
    );
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result));
}
