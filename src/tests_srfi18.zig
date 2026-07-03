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
