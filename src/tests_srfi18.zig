const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
const primitives = @import("primitives.zig");
const srfi18 = @import("primitives_srfi18.zig");
const vm_mod = @import("vm.zig");

// Regression for the #958 globals read race: VM.initForThread used to share
// the parent's globals map by struct copy, so the child's copied header kept
// pointing at the old bucket array after any parent-side rehash — every
// subsequent child lookup read freed memory and never saw newer bindings.
// Sharing by pointer makes the child's view track the parent's map across
// rehashes. This test is single-threaded on purpose: it checks the sharing
// mechanics deterministically, without depending on race timing.
test "child VM globals view survives parent-side rehash (#958)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    var child_gc = memory.GC.initForThread(std.testing.allocator, &gc);
    defer child_gc.deinit();
    var child_vm = try vm_mod.VM.initForThread(&child_gc, vm);
    defer child_vm.deinit();

    try vm.defineGlobal("race-counter", types.makeFixnum(1));

    // Force the parent's globals map through several rehashes.
    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| std.testing.allocator.free(n);
        names.deinit(std.testing.allocator);
    }
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        const name = try std.fmt.allocPrint(std.testing.allocator, "rehash-global-{d}", .{i});
        try names.append(std.testing.allocator, name);
        try vm.defineGlobal(name, types.makeFixnum(@intCast(i)));
    }

    // A binding added after the rehashes must be visible to the child.
    try vm.defineGlobal("late-global", types.makeFixnum(4242));
    const late = child_vm.globals.get("late-global");
    try std.testing.expect(late != null);
    try std.testing.expectEqual(@as(i64, 4242), types.toFixnum(late.?));

    // An in-place update of a pre-existing binding lands in the parent's
    // current bucket array; the child must read that array, not a stale copy.
    try vm.defineGlobal("race-counter", types.makeFixnum(99));
    const counter = child_vm.globals.get("race-counter");
    try std.testing.expect(counter != null);
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(counter.?));

    // A binding defined mid-rehash-burst must be visible too.
    const mid = child_vm.globals.get(names.items[2000]);
    try std.testing.expect(mid != null);
    try std.testing.expectEqual(@as(i64, 2000), types.toFixnum(mid.?));
}

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

    // Root across allocations: abandonFiberMutexes now dereferences the
    // fiber's owned-mutexes list, so under -Dgc-stress=true the fiber and
    // mutex must survive allocMutex's collection.
    const fiber = try gc.allocFiber(types.VOID, 0);
    var fiber_val = types.makePointer(@ptrCast(&fiber.header));
    gc.pushRoot(&fiber_val);
    defer gc.popRoot();
    var m_val = try gc.allocMutex(types.VOID);
    gc.pushRoot(&m_val);
    defer gc.popRoot();
    const m = types.toMutex(m_val);

    m.locked = true;
    m.owner = fiber_val;
    try fiber.owned_mutexes.append(gc.allocator, m_val);

    fiber_mod.abandonFiberMutexes(fiber, null);

    try std.testing.expect(m.abandoned);
    try std.testing.expect(!m.locked);
    try std.testing.expectEqual(types.VOID, m.owner);
}

// A stale list entry — a mutex still locked but owned by a *different* fiber
// (it was re-acquired after this fiber released it) — must be left alone by
// the defensive `m.owner == fiber_val` guard, not stomped.
test "abandonFiberMutexes skips mutex owned by different fiber" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const fiber_a = try gc.allocFiber(types.VOID, 0);
    var fiber_a_val = types.makePointer(@ptrCast(&fiber_a.header));
    gc.pushRoot(&fiber_a_val);
    defer gc.popRoot();
    const fiber_b = try gc.allocFiber(types.VOID, 1);
    var fiber_b_val = types.makePointer(@ptrCast(&fiber_b.header));
    gc.pushRoot(&fiber_b_val);
    defer gc.popRoot();
    var m_val = try gc.allocMutex(types.VOID);
    gc.pushRoot(&m_val);
    defer gc.popRoot();
    const m = types.toMutex(m_val);

    m.locked = true;
    m.owner = fiber_a_val;
    // Stale entry lingering in fiber_b's list (owner is now fiber_a).
    try fiber_b.owned_mutexes.append(gc.allocator, m_val);

    fiber_mod.abandonFiberMutexes(fiber_b, null);

    try std.testing.expect(!m.abandoned);
    try std.testing.expect(m.locked);
    try std.testing.expectEqual(fiber_a_val, m.owner);
}

// A stale list entry for a mutex this fiber has since unlocked must be
// skipped by the `m.locked` guard.
test "abandonFiberMutexes skips unlocked mutex" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const fiber = try gc.allocFiber(types.VOID, 0);
    var fiber_val = types.makePointer(@ptrCast(&fiber.header));
    gc.pushRoot(&fiber_val);
    defer gc.popRoot();
    var m_val = try gc.allocMutex(types.VOID);
    gc.pushRoot(&m_val);
    defer gc.popRoot();
    const m = types.toMutex(m_val);

    m.locked = false;
    m.owner = types.VOID;
    try fiber.owned_mutexes.append(gc.allocator, m_val);

    fiber_mod.abandonFiberMutexes(fiber, null);

    try std.testing.expect(!m.abandoned);
}

test "abandonFiberMutexes handles multiple mutexes" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const fiber = try gc.allocFiber(types.VOID, 0);
    var fiber_val = types.makePointer(@ptrCast(&fiber.header));
    // Root everything across the following allocations: under -Dgc-stress=true
    // each allocMutex collects, and an unrooted fiber/mutex local is swept.
    gc.pushRoot(&fiber_val);
    defer gc.popRoot();

    var m1_val = try gc.allocMutex(types.VOID);
    gc.pushRoot(&m1_val);
    defer gc.popRoot();
    var m2_val = try gc.allocMutex(types.VOID);
    gc.pushRoot(&m2_val);
    defer gc.popRoot();
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
    // m2 is a stale entry (unlocked) — the defensive guard must skip it while
    // still abandoning the two genuinely-held mutexes around it.
    try fiber.owned_mutexes.append(gc.allocator, m1_val);
    try fiber.owned_mutexes.append(gc.allocator, m2_val);
    try fiber.owned_mutexes.append(gc.allocator, m3_val);

    fiber_mod.abandonFiberMutexes(fiber, null);

    try std.testing.expect(m1.abandoned);
    try std.testing.expect(!m1.locked);
    try std.testing.expect(!m2.abandoned);
    try std.testing.expect(m3.abandoned);
    try std.testing.expect(!m3.locked);
}

// Core #1458 fix: a mutex living in *another* thread's heap (the shared,
// top-level-global case) is abandoned when a fiber that locked it dies,
// even though it is not on the dying fiber's own GC object lists. The old
// heap-scanning abandonFiberMutexes scanned only the passed GC's heap and
// so never found a parent-heap mutex from a child fiber's death; walking the
// fiber's owned-mutexes list finds it regardless of which heap owns it.
test "abandonFiberMutexes abandons a mutex from another GC heap (#1458)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Child heap shares the parent's symbol table, like a real SRFI-18 thread.
    var child_gc = memory.GC.initForThread(std.testing.allocator, &gc);
    defer child_gc.deinit();

    // Mutex lives in the parent heap; the fiber that holds it in the child.
    var m_val = try gc.allocMutex(types.VOID);
    gc.pushRoot(&m_val);
    defer gc.popRoot();
    const m = types.toMutex(m_val);

    const fiber = try child_gc.allocFiber(types.VOID, 0);
    var fiber_val = types.makePointer(@ptrCast(&fiber.header));
    child_gc.pushRoot(&fiber_val);
    defer child_gc.popRoot();

    m.locked = true;
    m.owner = fiber_val;
    try fiber.owned_mutexes.append(child_gc.allocator, m_val);

    // Sanity: the parent-heap mutex is not on the child heap's object lists,
    // so the old heap-scan of child_gc would have missed it entirely.
    try std.testing.expect(m.header.owner != child_gc.id);

    fiber_mod.abandonFiberMutexes(fiber, null);

    try std.testing.expect(m.abandoned);
    try std.testing.expect(!m.locked);
    try std.testing.expectEqual(types.VOID, m.owner);
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
    fiber_mod.abandonFiberMutexes(sched_fiber, vm.scheduler);

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

// Regression for #958: an SRFI-18 child thread's GC used to mark (and trace
// through) parent-heap objects reachable from its VM roots — e.g. a parent
// closure the child executes after a shared-globals lookup. Those stale mark
// bits corrupted the parent's next collection: markValueInner saw "already
// marked", skipped tracing children, and sweepYoung freed live objects,
// corrupting the C heap. Marking must never touch an object owned by another
// GC.
test "marking skips objects owned by another GC (#958)" {
    var parent = memory.GC.init(std.testing.allocator);
    defer parent.deinit();
    var child = memory.GC.initForThread(std.testing.allocator, &parent);
    defer child.deinit();

    const parent_pair = try parent.allocPair(types.makeFixnum(1), types.NIL);
    const parent_obj = types.toObject(parent_pair);

    // Marking a foreign object directly is a no-op.
    child.markValue(parent_pair);
    try std.testing.expect(!parent_obj.flags.marked);

    // Tracing a child object must stop at the foreign edge: the child pair
    // itself is marked, the parent pair it references is not.
    const child_pair = try child.allocPair(parent_pair, types.NIL);
    const child_obj = types.toObject(child_pair);
    child.markValue(child_pair);
    try std.testing.expect(child_obj.flags.marked);
    try std.testing.expect(!parent_obj.flags.marked);
    child_obj.flags.marked = false;

    // The owner still marks its own objects.
    parent.markValue(parent_pair);
    try std.testing.expect(parent_obj.flags.marked);
    parent_obj.flags.marked = false;
}

// Regression for #958, end to end: a child OS thread that executes a
// parent-heap closure (looked up via the shared globals map) triggers child
// collections while running. Those collections must leave no stale mark bits
// on the parent heap — between collections every mark bit is false, and the
// parent's next cycle relies on that to trace its full object graph.
test "child thread collections leave no stale marks on parent heap (#958)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The mark-bit scan below detects CHILD-written marks, relying on the
    // parent not collecting during this eval: the parent's own minor
    // collections legitimately leave mark bits on old-gen objects until the
    // next cycle's clearOldMarks. Make the parent quiescent — threshold-
    // driven again, with one forced full cycle to clear every mark bit and
    // recompute the post-bootstrap threshold — while the child GC created
    // by thread-start! still stresses on stress builds, which is the
    // direction this regression test cares about.
    gc.stress = false;
    gc.minor_cycle_count = 8; // force the next collect to be a full cycle
    gc.collect();

    // build-list is a parent-heap closure; 20000 elements exceeds the child
    // GC threshold, so the child collects (and marks its roots — which
    // include the parent-heap build-list closure frame) mid-run.
    const result = try vm.eval(
        \\(define (build-list n)
        \\  (let loop ((i 0) (acc '()))
        \\    (if (= i n) acc (loop (+ i 1) (cons i acc)))))
        \\(let ((t (make-thread (lambda () (length (build-list 20000))))))
        \\  (thread-start! t)
        \\  (thread-join! t))
    );
    try std.testing.expectEqual(@as(i64, 20000), types.toFixnum(result));

    var lists = [_]?*types.Object{ gc.objects, gc.old_objects };
    for (&lists) |*head| {
        var obj = head.*;
        while (obj) |o| : (obj = o.next) {
            try std.testing.expect(!o.flags.marked);
        }
    }
}

// Regression for #958, the write direction: named let used to bind its loop
// procedure to a gensym'd global (__nlet_N_name) via define_global. A child
// OS thread executing a parent function containing a named let then wrote a
// child-heap closure into the shared globals map, which dangled once the
// child heap was freed at thread-join!. Named let now binds the loop
// procedure to a boxed local, so nothing a child thread runs may leave
// child-owned values in the shared globals map.
test "child thread leaves no child-heap values in shared globals (#958)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // sum-to contains a named let; the child executes it via the shared
    // globals map, exercising the loop-procedure binding on the child VM.
    const result = try vm.eval(
        \\(define (sum-to n)
        \\  (let loop ((i 0) (acc 0))
        \\    (if (= i n) acc (loop (+ i 1) (+ acc i)))))
        \\(let ((t (make-thread (lambda () (sum-to 1000)))))
        \\  (thread-start! t)
        \\  (thread-join! t))
    );
    try std.testing.expectEqual(@as(i64, 499500), types.toFixnum(result));

    var it = vm.globals.valueIterator();
    while (it.next()) |v| {
        if (types.isPointer(v.*)) {
            try std.testing.expectEqual(gc.id, types.toObject(v.*).owner);
        }
    }
}

// Thread results are deep-copied child->parent at thread-join!, after which
// the child heap is freed. deepCopyValue used to alias NativeFn objects
// instead of copying them, so a result containing a primitive procedure kept
// a raw pointer across the copy (issue #958 follow-up). The joined procedures
// must be fresh parent-heap objects that are still callable.
test "thread result containing primitive procedures is callable after join" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let ((t (make-thread (lambda () (list car cdr)))))
        \\  (thread-start! t)
        \\  (let ((procs (thread-join! t)))
        \\    (+ ((car procs) '(30 40))
        \\       (car ((car (cdr procs)) '(30 12))))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

// thread-yield! in a schedulerless child OS thread used to be a silent no-op,
// causing busy-spin at 100% CPU. After the fix it calls std.Thread.yield()
// (sched_yield). This test verifies that the yield path coexists with
// thread-terminate! without leaking error.Yielded (#948).
test "thread-yield! in child OS thread does not busy-spin or leak Yielded" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(let ((t (make-thread (lambda () (let loop () (thread-yield!) (loop))))))
        \\  (thread-start! t)
        \\  (thread-terminate! t)
        \\  (guard (e (#t (terminated-thread-exception? e)))
        \\    (thread-join! t)))
    );
    try std.testing.expectEqual(types.TRUE, result);
}

// Regression for #1463: threadSleepFn used to always drive the scheduler in
// place (a nested runSchedulerStep call) regardless of how the calling fiber
// was dispatched, unlike fiber.waitForFd's dispatched_from_scheduler-aware
// flat unwind. Two scheduler-dispatched fibers each retrying through many
// short thread-sleep! calls — one polling for a flag the other sets after a
// bounded number of iterations — nested one more native stack frame per
// hand-off, growing without bound until the underlying condition resolved.
// This test's fiber count and iteration bound are large enough that the
// pre-fix nesting would run deep; it must complete promptly rather than
// crash or stall.
test "concurrent thread-sleep! retries across fibers resolve without unbounded stack growth (#1463)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // gc-stress collects on every allocation, so the full retry count adds
    // wall time and allocator churn without more coverage -- scale it down,
    // like tests_robustness.zig does for its own iteration-heavy loops.
    const n: i64 = if (@import("build_options").gc_stress) 300 else 3000;

    _ = try vm.eval("(import (srfi 18))");
    const result = try vm.eval(if (@import("build_options").gc_stress)
        \\(define signal #f)
        \\(define (poll-until-signal)
        \\  (let loop ((n 0))
        \\    (if signal
        \\        n
        \\        (begin (thread-sleep! 0.0001) (loop (+ n 1))))))
        \\(define setter
        \\  (spawn (lambda ()
        \\    (let loop ((n 0))
        \\      (if (>= n 300)
        \\          (begin (set! signal #t) n)
        \\          (begin (thread-sleep! 0.0001) (loop (+ n 1))))))))
        \\(define waiter (spawn poll-until-signal))
        \\(define setter-result (fiber-join setter))
        \\(define waiter-result (fiber-join waiter))
        \\(list setter-result waiter-result signal)
    else
        \\(define signal #f)
        \\(define (poll-until-signal)
        \\  (let loop ((n 0))
        \\    (if signal
        \\        n
        \\        (begin (thread-sleep! 0.0001) (loop (+ n 1))))))
        \\(define setter
        \\  (spawn (lambda ()
        \\    (let loop ((n 0))
        \\      (if (>= n 3000)
        \\          (begin (set! signal #t) n)
        \\          (begin (thread-sleep! 0.0001) (loop (+ n 1))))))))
        \\(define waiter (spawn poll-until-signal))
        \\(define setter-result (fiber-join setter))
        \\(define waiter-result (fiber-join waiter))
        \\(list setter-result waiter-result signal)
    );

    const setter_result = types.toFixnum(types.car(result));
    const rest = types.cdr(result);
    const waiter_result = types.toFixnum(types.car(rest));
    const signal = types.car(types.cdr(rest));

    try std.testing.expectEqual(n, setter_result);
    // The waiter must have actually retried through thread-sleep! at least
    // once (the regression this test exists to catch is specifically about
    // *repeated* retries) -- `(>= waiter-result 0)` would be vacuously true
    // for any non-negative starting value and prove nothing.
    try std.testing.expect(waiter_result > 0);
    // A loose sanity ceiling only, not `<= n`: that tighter bound holds today
    // solely because the O(fiber count) round-robin scheduler happens to
    // dispatch the setter before the waiter every wake round (#1477) -- once
    // that scan is replaced with a ready queue, dispatch order within a wake
    // round is no longer guaranteed, and the waiter could legitimately run
    // more retries than the setter without indicating any regression.
    try std.testing.expect(waiter_result < 100_000);
    try std.testing.expectEqual(types.TRUE, signal);
}
