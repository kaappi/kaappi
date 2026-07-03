const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
const primitives = @import("primitives.zig");
const srfi18 = @import("primitives_srfi18.zig");
const vm_mod = @import("vm.zig");

// Regression test: thread-terminate! on a busy-looping OS thread must stop
// it so thread-join! returns (raising terminated-thread-exception) instead of
// blocking forever in pthread_join. The child VM polls fiber.terminated at
// the dispatch-loop safepoint.
test "thread-terminate! stops busy OS thread and join raises terminated" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let ((t (make-thread (lambda () (let loop () (loop))))))
        \\  (thread-start! t)
        \\  (thread-terminate! t)
        \\  (guard (e (#t (if (terminated-thread-exception? e) 'terminated 'other)))
        \\    (thread-join! t)
        \\    'no-exception))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("terminated", types.symbolName(result));
}

// Regression: symbols first interned by an SRFI-18 child thread go into the
// parent's shared symbol table, but allocSymbol used to skip trackObject for a
// child GC — so those Symbols landed on no GC's object list. The child's
// sweep/deinit never freed them (not on its list) and the parent never knew
// about them, leaking each distinct child-interned symbol's Symbol struct and
// its name dupe. The fix hands such symbols to the parent GC's foreign_symbols
// list, freed at the parent's deinit. std.testing.allocator fails this test if
// any allocation is leaked, so the many distinct child-only symbols below must
// all be reclaimed.
test "child thread interning distinct new symbols does not leak" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let ((t (make-thread
        \\           (lambda ()
        \\             (let loop ((i 0))
        \\               (if (< i 200)
        \\                   (begin
        \\                     (string->symbol
        \\                      (string-append "child-only-" (number->string i)))
        \\                     (loop (+ i 1)))
        \\                   'child-done))))))
        \\  (thread-start! t)
        \\  (thread-join! t))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("child-done", types.symbolName(result));
}

test "abandonFiberMutexes marks owned mutex abandoned" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const fiber = try gc.allocFiber(types.VOID, 0);
    const fiber_val = types.makePointer(@ptrCast(fiber));
    const m_val = try gc.allocMutex(types.VOID);
    const m = types.toMutex(m_val);

    m.locked = true;
    m.owner = fiber_val;

    srfi18.abandonFiberMutexes(&gc, fiber, null);

    try std.testing.expect(m.abandoned);
    try std.testing.expect(!m.locked);
    try std.testing.expectEqual(types.VOID, m.owner);
}

test "abandonFiberMutexes skips mutex owned by different fiber" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const fiber_a = try gc.allocFiber(types.VOID, 0);
    const fiber_b = try gc.allocFiber(types.VOID, 1);
    const fiber_a_val = types.makePointer(@ptrCast(fiber_a));
    const m_val = try gc.allocMutex(types.VOID);
    const m = types.toMutex(m_val);

    m.locked = true;
    m.owner = fiber_a_val;

    srfi18.abandonFiberMutexes(&gc, fiber_b, null);

    try std.testing.expect(!m.abandoned);
    try std.testing.expect(m.locked);
    try std.testing.expectEqual(fiber_a_val, m.owner);
}

test "abandonFiberMutexes skips unlocked mutex" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const fiber = try gc.allocFiber(types.VOID, 0);
    const m_val = try gc.allocMutex(types.VOID);
    const m = types.toMutex(m_val);

    m.locked = false;
    m.owner = types.VOID;

    srfi18.abandonFiberMutexes(&gc, fiber, null);

    try std.testing.expect(!m.abandoned);
}

test "abandonFiberMutexes handles multiple mutexes" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const fiber = try gc.allocFiber(types.VOID, 0);
    const fiber_val = types.makePointer(@ptrCast(fiber));

    const m1_val = try gc.allocMutex(types.VOID);
    const m2_val = try gc.allocMutex(types.VOID);
    const m3_val = try gc.allocMutex(types.VOID);
    const m1 = types.toMutex(m1_val);
    const m2 = types.toMutex(m2_val);
    const m3 = types.toMutex(m3_val);

    m1.locked = true;
    m1.owner = fiber_val;
    m2.locked = false;
    m2.owner = types.VOID;
    m3.locked = true;
    m3.owner = fiber_val;

    srfi18.abandonFiberMutexes(&gc, fiber, null);

    try std.testing.expect(m1.abandoned);
    try std.testing.expect(!m1.locked);
    try std.testing.expect(!m2.abandoned);
    try std.testing.expect(m3.abandoned);
    try std.testing.expect(!m3.locked);
}

test "thread-terminate! on current thread abandons held mutex" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(import (srfi 18))
    );
    _ = try vm.eval(
        \\(define m (make-mutex 'test))
    );
    _ = try vm.eval(
        \\(mutex-lock! m)
    );

    _ = vm.eval(
        \\(thread-terminate! (current-thread))
    ) catch {};

    vm.yielded = false;

    const result = try vm.eval(
        \\(eq? (mutex-state m) 'abandoned)
    );
    try std.testing.expectEqual(types.TRUE, result);
}

test "mutex-lock! on abandoned mutex raises abandoned-mutex-exception" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(import (srfi 18))
    );
    _ = try vm.eval(
        \\(define m (make-mutex 'test))
    );
    _ = try vm.eval(
        \\(mutex-lock! m)
    );

    const m_val = try vm.eval("m");
    const m = types.toMutex(m_val);
    const sched_fiber = vm.current_fiber.?;
    srfi18.abandonFiberMutexes(&gc, sched_fiber, vm.scheduler);

    try std.testing.expect(m.abandoned);

    const result = try vm.eval(
        \\(guard (e (#t (abandoned-mutex-exception? e)))
        \\  (mutex-lock! m)
        \\  #f)
    );
    try std.testing.expectEqual(types.TRUE, result);
}

test "top-level define with yielding body (scheduler created mid-form)" {
    // Regression: spawn creates the scheduler lazily *during* the form's
    // run, so run() had already committed to the non-scheduler path and the
    // subsequent thread-yield! escaped as error.Yielded, aborting the define.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(import (srfi 18))
    );
    _ = try vm.eval(
        \\(define x (let ((f (spawn (lambda () 12345))))
        \\            (thread-yield!)
        \\            (fiber-join f)
        \\            99))
    );
    const result = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "top-level form value is the main fiber's result after nested resume" {
    // Regression: when the main fiber yields and the spawned fiber then
    // blocks in a native primitive (mutex-lock!), the main fiber's form
    // completes inside that primitive's nested scheduler loop. The form's
    // value must be the main fiber's result (99), not the fiber's thunk
    // result (12345), and the mutex the main fiber still holds must not be
    // treated as abandoned.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(import (srfi 18))
        \\(define m (make-mutex))
        \\(mutex-lock! m)
        \\(define f (spawn (lambda () (mutex-lock! m) (mutex-unlock! m) 12345)))
    );
    const result = try vm.eval(
        \\(let () (thread-yield!) (mutex-unlock! m) 99)
    );
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));

    // The fiber saw a normal (not abandoned) mutex and completed.
    const fiber_result = try vm.eval("(fiber-join f)");
    try std.testing.expectEqual(@as(i64, 12345), types.toFixnum(fiber_result));
}

test "parameter set before scheduler creation stays visible" {
    // Regression: values set while no fiber exists live in the VM-level
    // override map; once spawn lazily created the scheduler, parameter
    // reads consulted only the (empty) main fiber's map and fell back to
    // the parameter's default.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define p (make-parameter 1))
        \\(p 2)
        \\(define f (spawn (lambda () (p))))
    );
    const main_val = try vm.eval("(p)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(main_val));

    const fiber_val = try vm.eval("(fiber-join f)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(fiber_val));
}
