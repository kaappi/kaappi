// Phase 2: Tail calls (loop, factorial, mutual, fib, begin)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");

test "tail-recursive loop does not overflow" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (loop n) (if (= n 0) (quote done) (loop (- n 1))))");
    const result = try vm.eval("(loop 1000000)");
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("done", types.symbolName(result));
}

test "tail-recursive factorial with accumulator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc))))");
    const result = try vm.eval("(fact 10 1)");
    try std.testing.expectEqual(@as(i64, 3628800), types.toFixnum(result));
}

test "mutual tail recursion" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))");
    _ = try vm.eval("(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))");
    const result = try vm.eval("(my-even? 10000)");
    try std.testing.expectEqual(types.TRUE, result);
}

test "non-tail recursion still works" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))");
    const result = try vm.eval("(fib 10)");
    try std.testing.expectEqual(@as(i64, 55), types.toFixnum(result));
}

test "tail call in begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (count n) (if (= n 0) 0 (begin (count (- n 1)))))");
    const result = try vm.eval("(count 100000)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result));
}

test "self-tail-recursive loop" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (self-loop n acc) (if (= n 0) acc (self-loop (- n 1) (+ acc n))))");
    const result = try vm.eval("(self-loop 1000 0)");
    try std.testing.expectEqual(@as(i64, 500500), types.toFixnum(result));
}

test "named let self-tail-recursive loop" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let loop ((n 1000) (acc 0)) (if (= n 0) acc (loop (- n 1) (+ acc n))))");
    try std.testing.expectEqual(@as(i64, 500500), types.toFixnum(result));
}

// Regression: a tail call to a global bound to a non-closure callable
// (parameter object) must go through the full tail_call handler, not the
// closure/native-only tail_call_global path. Calling a parameter in tail
// position previously errored with "not a procedure".
test "tail call to a parameter object" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define p (make-parameter 42))");
    _ = try vm.eval("(define (get) (p))");
    const result = try vm.eval("(get)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

// Regression: parameterize desugars to dynamic-wind thunks that tail-call the
// parameter and %parameter-set!. This exercises the same path end to end.
test "parameterize body with tail position calls" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define radix (make-parameter 10))");
    _ = try vm.eval("(define (f) (radix))");
    const result = try vm.eval("(parameterize ((radix 2)) (f))");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

// Regression for #817: the dispatch loop captured `frame` as a pointer into
// self.frames; a tail call to a native that re-enters the VM (map calling its
// lambda) can grow the frames array, freeing the block `frame` points into,
// and the handler then read frame.dst from freed memory. Shrinking the frames
// array makes growth happen at shallow depth; scanning a contiguous depth
// range guarantees the re-entrant push lands exactly on a capacity boundary.
fn shrinkFrames(vm: *th.VM) !void {
    std.testing.allocator.free(vm.frames);
    vm.frames = try std.testing.allocator.alloc(vm_mod.CallFrame, 8);
}

test "tail call to re-entrant native across frames array growth" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    try shrinkFrames(vm);

    _ = try vm.eval(
        \\(define (nest d)
        \\  (if (= d 0)
        \\      (map (lambda (x) (* 2 x)) '(1 2 3))
        \\      (car (list (nest (- d 1))))))
    );
    const result = try vm.eval(
        \\(let loop ((d 0) (ok #t))
        \\  (if (= d 40)
        \\      ok
        \\      (loop (+ d 1) (and ok (equal? (nest d) '(2 4 6))))))
    );
    try std.testing.expectEqual(types.TRUE, result);
}

test "tail apply of re-entrant native across frames array growth" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    try shrinkFrames(vm);

    _ = try vm.eval(
        \\(define (nest d)
        \\  (if (= d 0)
        \\      (apply map (lambda (x) (* 2 x)) '((1 2 3)))
        \\      (car (list (nest (- d 1))))))
    );
    const result = try vm.eval(
        \\(let loop ((d 0) (ok #t))
        \\  (if (= d 40)
        \\      ok
        \\      (loop (+ d 1) (and ok (equal? (nest d) '(2 4 6))))))
    );
    try std.testing.expectEqual(types.TRUE, result);
}

test "tail call to parameter with converter across frames array growth" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    try shrinkFrames(vm);

    _ = try vm.eval("(define p (make-parameter 1 (lambda (v) (* v 10))))");
    _ = try vm.eval(
        \\(define (nest d)
        \\  (if (= d 0)
        \\      (p 5)
        \\      (car (list (nest (- d 1))))))
    );
    _ = try vm.eval(
        \\(let loop ((d 0))
        \\  (unless (= d 40)
        \\    (nest d)
        \\    (loop (+ d 1))))
    );
    const result = try vm.eval("(p)");
    try std.testing.expectEqual(@as(i64, 50), types.toFixnum(result));
}

test "tail-call into larger frame clears extension registers" {
    // Regression test for #1256: when a tail-call switches to a callee with
    // a larger locals_count, registers in [base+args, base+locals_count) must
    // be cleared to UNDEFINED so the GC doesn't scan stale pointers.
    //
    // Strategy: pollute registers with heap pointers, then tail-call into a
    // function whose locals_count is large (due to a branch with many locals)
    // but whose taken branch is trivial and doesn't touch the high registers.
    // After execution, the untouched extension slots should be UNDEFINED (if
    // cleared) not stale heap pointers (if not cleared).
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // 1. Pollute registers: call a function with many locals that allocates
    //    heap objects (strings). After it returns, those register slots retain
    //    stale string pointers.
    _ = try vm.eval(
        \\(define (pollute)
        \\  (let ((a "heap1") (b "heap2") (c "heap3") (d "heap4")
        \\        (e "heap5") (f "heap6") (g "heap7") (h "heap8"))
        \\    (string-length (string-append a b c d e f g h))))
    );
    _ = try vm.eval("(pollute)");

    // 2. small (locals=4) tail-calls big-branch (locals=21). big-branch takes
    //    the #t path which only touches r0-r2, leaving r3-r20 untouched.
    //    With the fix: clearFrameLocals zeros r3-r20 to UNDEFINED before
    //    big-branch's body runs, so stale pointers from pollute are cleared.
    //    Without the fix: r3-r20 retain stale heap pointers from pollute.
    _ = try vm.eval(
        \\(define (small x) (big-branch #t x))
    );
    _ = try vm.eval(
        \\(define (big-branch flag x)
        \\  (if flag
        \\      x
        \\      (let ((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7) (h 8))
        \\        (+ a b c d e f g h x))))
    );

    const result = try vm.eval("(small 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));

    // 3. After eval returns, the register file retains whatever the last
    //    execution left. Scan registers that were in big-branch's frame
    //    window — the extension slots (beyond the 2 args) should be UNDEFINED,
    //    not stale heap pointers from pollute. Frame base is 1 (execute
    //    pushes base=1 for top-level calls), so big-branch's locals span
    //    registers [1, 1+21). The args occupy [1, 3), the extension is [3, 22).
    var stale_pointers: usize = 0;
    for (vm.registers[3..@min(22, vm.registers.len)]) |reg| {
        if (reg != types.UNDEFINED and types.isPointer(reg)) {
            stale_pointers += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), stale_pointers);
}
