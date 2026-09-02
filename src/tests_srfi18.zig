const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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

// #1935: GC.initForThread used to point a child at its IMMEDIATE parent's
// symbol table, so a grandchild (child of a child) interned into the middle
// GC's own `symbols` field -- which stays permanently empty, since the
// middle's own internings go to its `shared_symbols` -- a table nothing else
// consults. (eq? 'alpha (string->symbol "alpha")) at thread depth 2 came
// back #f (an R7RS 6.5 violation), the root's mark phase never saw the
// grandchild's symbols, and the owner stamping that makes depth-1 interning
// safe never reached depth 2. Every descendant must chain to the ROOT's
// table, the ROOT's foreign_symbols, and the ROOT's owner id.
test "grandchild GC interns into the root symbol table (#1935)" {
    var root = memory.GC.init(std.testing.allocator);
    defer root.deinit();
    root.enabled = false;

    var child = memory.GC.initForThread(std.testing.allocator, &root);
    defer child.deinit();
    child.enabled = false;

    var grandchild = memory.GC.initForThread(std.testing.allocator, &child);
    defer grandchild.deinit();
    grandchild.enabled = false;

    // The child-of-a-child must reach PAST the middle GC (whose own table
    // is never populated) to the root's table and ownership chain.
    try std.testing.expect(grandchild.shared_symbols == &root.symbols);
    try std.testing.expectEqual(root.id, grandchild.shared_owner_id);
    try std.testing.expect(grandchild.shared_foreign_symbols == &root.foreign_symbols);

    // Intern via the grandchild: the symbol must land in the ROOT's table,
    // stamped with the ROOT's id, appended to the ROOT's foreign_symbols
    // (the root frees it at deinit, so it outlives the grandchild).
    const gc_sym = try grandchild.allocSymbol("alpha");
    try std.testing.expectEqual(root.id, types.toObject(gc_sym).owner);
    try std.testing.expectEqual(@as(usize, 1), root.foreign_symbols.items.len);
    try std.testing.expectEqual(@as(usize, 0), child.foreign_symbols.items.len);
    // The middle and grandchild's own tables stay empty.
    try std.testing.expectEqual(@as(usize, 0), child.symbols.count());
    try std.testing.expectEqual(@as(usize, 0), grandchild.symbols.count());

    // Identity: a root-side intern of the same name finds the grandchild's
    // symbol -- (eq? 'alpha (string->symbol "alpha")) at any depth.
    const root_sym = try root.allocSymbol("alpha");
    try std.testing.expectEqual(root_sym, gc_sym);

    // And a symbol the ROOT interns first is returned to the grandchild.
    const root_sym2 = try root.allocSymbol("beta");
    const gc_sym2 = try grandchild.allocSymbol("beta");
    try std.testing.expectEqual(root_sym2, gc_sym2);
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
    var fiber_val = types.makePointer(&fiber.header);
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
    var fiber_a_val = types.makePointer(&fiber_a.header);
    gc.pushRoot(&fiber_a_val);
    defer gc.popRoot();
    const fiber_b = try gc.allocFiber(types.VOID, 1);
    var fiber_b_val = types.makePointer(&fiber_b.header);
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
    var fiber_val = types.makePointer(&fiber.header);
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
    var fiber_val = types.makePointer(&fiber.header);
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
    var fiber_val = types.makePointer(&fiber.header);
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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

// #2127: the gc-stress free-quarantine (#1687) exists so a dangling value
// still reads the FREED_OWNER sentinel at the next mark instead of a recycled
// object — but a joined child's GC.deinit drained its quarantine straight
// back to the allocator, so the one heap teardown that most often leaves the
// parent holding a dangling value was also the one the detector could not
// see. The child now names the parent as its quarantine heir. With the
// parent's own collector disabled, any quarantined byte it gains across the
// join can only have arrived from the child's teardown; before the fix the
// count did not move at all.
test "a joined child's freed slots pass to the parent's quarantine (#2127)" {
    if (comptime !memory.free_quarantine) return error.SkipZigTest;
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    gc.enabled = false;
    const before = gc.quarantine_bytes; // whatever VM setup already collected

    const result = try vm.eval(
        \\(let ((t (make-thread (lambda () (list 1 2 3)))))
        \\  (thread-start! t)
        \\  (thread-join! t)
        \\  'joined)
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("joined", types.symbolName(result));
    try std.testing.expect(gc.quarantine_bytes > before);
}

// Thread results are deep-copied child->parent at thread-join!, after which
// the child heap is freed. deepCopyValue used to alias NativeFn objects
// instead of copying them, so a result containing a primitive procedure kept
// a raw pointer across the copy (issue #958 follow-up). The joined procedures
// must be fresh parent-heap objects that are still callable.
test "thread result containing primitive procedures is callable after join" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
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

// #1983: unguarded float->int conversions in the SRFI-18 time/timeout paths
// aborted the process -- uncatchably, exit 134 -- on +/-inf.0, NaN, and any
// magnitude past the destination type. seconds->time now raises a catchable
// error for values no time object can represent (it constructs an observable
// value, so saturating would silently build a wrong one); timeouts saturate
// instead, because "so far out it never fires" is the legal SRFI-18 reading
// of a huge deadline (+inf.0 conventionally means "never time out").
test "seconds->time rejects unrepresentable seconds catchably (#1983)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Each of these aborted the whole process before the fix.
    const rejected = [_][]const u8{
        "(guard (e (#t 'caught)) (seconds->time +inf.0))",
        "(guard (e (#t 'caught)) (seconds->time -inf.0))",
        "(guard (e (#t 'caught)) (seconds->time +nan.0))",
        "(guard (e (#t 'caught)) (seconds->time 9.3e18))",
        // 2^63 exactly: the first aborting value. A bound written as
        // @floatFromInt(maxInt(i64)) rounds UP to this very value and would
        // re-admit it -- the off-by-one-ULP guard shape #1907 was made of.
        "(guard (e (#t 'caught)) (seconds->time 9223372036854775808.0))",
    };
    for (rejected) |src| {
        const got = try vm.eval(src);
        try std.testing.expect(types.isSymbol(got));
        try std.testing.expectEqualStrings("caught", types.symbolName(got));
    }

    // Controls: the issue's last-accepted magnitude below 2^63, and the
    // exactly-representable minimum (-2^63 is a valid i64, unlike +2^63).
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 9.2e18 (time->seconds (seconds->time 9.2e18)))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= -9223372036854775808.0 (time->seconds (seconds->time -9223372036854775808.0)))"));
    // Round-trip sanity away from the boundary.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< (abs (- 1.5 (time->seconds (seconds->time 1.5)))) 1e-9)"));
}

test "huge and infinite timeouts saturate instead of aborting (#1983)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // OS threads are unregistered on wasm (thread-start! is native-only)
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Uncontended mutex: the timeout is converted eagerly (the old abort
    // site) and then never consulted, because the lock is free. 1e300
    // exercises the float branch's multiply overflow; +inf.0 the infinity
    // path. Control from the issue: 1.8e10 was already fine.
    _ = try vm.eval("(define m (make-mutex))");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(mutex-lock! m 1.8e10)"));
    _ = try vm.eval("(mutex-unlock! m)");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(mutex-lock! m 1e300)"));
    _ = try vm.eval("(mutex-unlock! m)");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(mutex-lock! m +inf.0)"));
    _ = try vm.eval("(mutex-unlock! m)");

    // Far-future TIME OBJECT: timeoutToDeadlineNs' other branch, whose u64
    // seconds*1e9 multiply was a separate "integer overflow" panic.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(mutex-lock! m (seconds->time 9.2e18))"));
    _ = try vm.eval("(mutex-unlock! m)");

    // thread-join! with an infinite timeout on a thread that finishes.
    _ = try vm.eval("(define t (thread-start! (make-thread (lambda () 42))))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try vm.eval("(thread-join! t +inf.0)")));
}

// ---------------------------------------------------------------------------
// A park that errors out must leave the fiber runnable (#2430)
// ---------------------------------------------------------------------------
//
// thread-join!'s fiber path, mutex-lock! and mutex-unlock!'s condition-
// variable branch each arm the parked state — `.waiting`, `timed_out`,
// `waiting_on`, a waiter_index enrolment and (when timed) a reactor timer —
// and then reached both `try ctx.reactor.addTimer` and `try runSchedulerStep`
// with nothing to undo it. Both failure sources return catchable errors, so a
// Scheme `guard` could resume on a fiber the scheduler still believed was
// parked: the "running fiber marked parked" state that is the precondition
// for the #1487 dispatch-from-stale-snapshot corruption, and exactly what
// defeats the waiter_index's deliberate tolerance of a stale entry.
//
// The probe is a SRFI 181 custom port whose read! callback blocks. That is a
// real program reaching a real catchable error (runSchedulerStep's
// custom-port-callback guard, which exists because such a callback may not
// block) rather than an injected OOM — and it is deterministic, where the OOM
// the issue describes has no reproducer. `waiting_on` is what discriminates
// here: that guard already restores `status`/`timed_out` and drops the timer
// for its own return, so it is the one armed field left lying pre-fix. The
// assertions cover the rest anyway, since the sites' other error sources
// (addTimer, and mutex-lock!'s awaitCrossThreadRing) reach no such guard.
//
// A stale `waiting_on` is not cosmetic: thread-join! and mutex-lock! report
// it as the irritant of their deadlock errors, and it is a GC-traced field.
//
// `status` is deliberately not asserted. It is the field the issue names, but
// it is not observable from here: `vm_calls.prepareTopLevelFrame` documents
// that the main fiber is left `.completed` when its form finishes, so by the
// time eval returns every run says `.completed` whether the park was undone or
// not. The armed state that survives to be seen is `waiting_on` and the timer.

fn expectUnparked(vm: *vm_mod.VM, me: *fiber_mod.Fiber, label: []const u8) !void {
    var pending_timer = false;
    if (vm.reactor) |r| {
        for (r.timers.items) |entry| {
            if (entry.fiber == me) pending_timer = true;
        }
    }
    // The abandoned park must also be out of the #1530 waiter_index. Nothing
    // else would remove it: only a later wake naming the same key compacts
    // stale entries, and these probes abandon the wait on an object that is
    // never woken (PR #2432 review).
    var indexed = false;
    if (vm.scheduler) |sched| {
        var it = sched.waiter_index.valueIterator();
        while (it.next()) |list| {
            for (list.items) |idx| {
                if (idx == me.sched_idx) indexed = true;
            }
        }
    }
    if (me.waiting_on == types.VOID and me.deadline_ns == null and
        !me.timed_out and !pending_timer and !indexed) return;

    std.debug.print(
        "{s}: fiber still parked after a failed park — " ++
            "waiting_on=0x{x} deadline_ns={?d} timed_out={} pending_timer={} indexed={} status={s}\n",
        .{ label, me.waiting_on, me.deadline_ns, me.timed_out, pending_timer, indexed, @tagName(me.status) },
    );
    return error.FiberLeftParked;
}

fn expectUnparkedAfterBlockedCallback(setup: []const u8, probe: []const u8, label: []const u8) !void {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // Split from the probe so the waiter_index baseline is measured with the
    // fixtures already in place: mutex-lock!'s holder fiber is legitimately
    // parked on a channel by now and owns a key of its own, so the assertion
    // has to be "the failed park added none", not "the index is empty".
    // Scheduler-optional: the condvar probe's setup never spawns, so nothing
    // has forced one into existence yet.
    _ = try ctx.vm.eval(setup);
    const baseline = if (ctx.vm.scheduler) |s| s.waiter_index.count() else 0;

    // The guard catches and the program runs on — which is the hazard, not
    // an incidental detail of the probe.
    const msg_val = try ctx.vm.eval(probe);
    try std.testing.expect(types.isString(msg_val));
    const msg = types.toObject(msg_val).as(types.SchemeString);
    try std.testing.expect(std.mem.startsWith(u8, msg.data[0..msg.len], "custom port callback blocked"));

    // Index 0, not vm.current_fiber: the callback runs on the main fiber, but
    // a probe that dispatched a sibling can leave the VM pointing at that one.
    const sched = ctx.vm.scheduler.?;
    try expectUnparked(ctx.vm, sched.fibers.items[0].?, label);

    if (sched.waiter_index.count() != baseline) {
        std.debug.print(
            "{s}: waiter_index grew from {d} to {d} key(s) across the failed park\n",
            .{ label, baseline, sched.waiter_index.count() },
        );
        return error.WaiterIndexLeaked;
    }
}

test "a thread-join! park that errors out leaves the fiber runnable (#2430)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // custom ports need the reactor
    try expectUnparkedAfterBlockedCallback(
        \\(define blocked (spawn (lambda () (channel-receive (make-channel)))))
        \\(define p (make-custom-binary-input-port "cb"
        \\  (lambda (bv start count) (thread-join! blocked 10) 0) #f #f #f))
    ,
        \\(guard (e (#t (error-object-message e))) (read-bytevector 4 p))
    , "thread-join!");
}

test "a mutex-lock! park that errors out leaves the fiber runnable (#2430)" {
    if (comptime platform.is_wasm) return error.SkipZigTest;
    // A live holder keeps the mutex locked, so mutex-lock! takes the slow
    // path that arms the park instead of claiming it outright.
    try expectUnparkedAfterBlockedCallback(
        \\(define m (make-mutex))
        \\(define holder (spawn (lambda () (mutex-lock! m) (channel-receive (make-channel)))))
        \\(thread-yield!)
        \\(define p (make-custom-binary-input-port "cb"
        \\  (lambda (bv start count) (mutex-lock! m 10) 0) #f #f #f))
    ,
        \\(guard (e (#t (error-object-message e))) (read-bytevector 4 p))
    , "mutex-lock!");
}

test "a condition-variable park that errors out leaves the fiber runnable (#2430)" {
    if (comptime platform.is_wasm) return error.SkipZigTest;
    try expectUnparkedAfterBlockedCallback(
        \\(define m (make-mutex))
        \\(define cv (make-condition-variable))
        \\(mutex-lock! m)
        \\(define p (make-custom-binary-input-port "cb"
        \\  (lambda (bv start count) (mutex-unlock! m cv 10) 0) #f #f #f))
    ,
        \\(guard (e (#t (error-object-message e))) (read-bytevector 4 p))
    , "condition-variable");
}

// ---------------------------------------------------------------------------
// The same two defects at the local-channel park sites (#2433)
// ---------------------------------------------------------------------------
//
// primitives_fiber.zig's local channel waits share #2430's shape.
// channelSendLocal's timed in-call park (Site B) armed .waiting/waiting_on, a
// #1530 waiter_index enrolment and a reactor timer and then reached both
// `try addTimer` and `try runSchedulerStep` with no error-path unpark — the
// send side was the odd one out; the receive side already had catch blocks but
// none of them withdrew the waiter_index entry (Gap 2), which only a later wake
// naming the same key would otherwise compact, stranding a map key and list per
// abandoned park.
//
// Same probe as the #2430 tests above: a SRFI 181 custom port whose read!
// callback blocks on a timed local-channel wait, so runSchedulerStep's
// custom-port-callback guard raises a real catchable error from inside the
// armed park — exercising channelSendLocal's and channelReceiveLocal's in-call
// runSchedulerStep sites on the main fiber. (The dispatched-fiber flat-park
// re-park sites arm no runSchedulerStep — only addTimer — so their error path
// is OOM-only, which gc.oom_countdown cannot reach here either, #2435.)
// `expectUnparkedAfterBlockedCallback` asserts both halves: the park state is
// restored AND the waiter_index entry is withdrawn.

test "a channel-receive park that errors out leaves the fiber runnable (#2433)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // custom ports need the reactor
    // An empty unbounded local channel: the timed receive arms the in-call
    // park (channelReceiveLocal Site D) before its runSchedulerStep drive.
    try expectUnparkedAfterBlockedCallback(
        \\(define ch (make-channel))
        \\(define p (make-custom-binary-input-port "cb"
        \\  (lambda (bv start count) (channel-receive ch 10) 0) #f #f #f))
    ,
        \\(guard (e (#t (error-object-message e))) (read-bytevector 4 p))
    , "channel-receive");
}

test "a channel-send park that errors out leaves the fiber runnable (#2433)" {
    if (comptime platform.is_wasm) return error.SkipZigTest;
    // A capacity-1 channel filled to the brim, so the timed send blocks on the
    // in-call park (channelSendLocal Site B) instead of being admitted.
    try expectUnparkedAfterBlockedCallback(
        \\(define ch (make-channel 1))
        \\(channel-send ch 'x)
        \\(define p (make-custom-binary-input-port "cb"
        \\  (lambda (bv start count) (channel-send ch 'y 10) 0) #f #f #f))
    ,
        \\(guard (e (#t (error-object-message e))) (read-bytevector 4 p))
    , "channel-send");
}

// ---------------------------------------------------------------------------
// kaappi#2446: waiting on a held spin lock must not burn CPU
// ---------------------------------------------------------------------------

fn processCpuNs() !u64 {
    var ts: std.c.timespec = undefined;
    // Every current POSIX target supports this clock; a future one that
    // rejects it must skip loudly, not compare against an undefined `ts`.
    if (std.c.clock_gettime(.PROCESS_CPUTIME_ID, &ts) != 0) return error.SkipZigTest;
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

// A thread that finds a spin lock held must stop consuming CPU while it
// waits. On NetBSD's 4BSD scheduler a crowd of pure spinners outranks the
// preempted holder for good -- the holder's priority is decayed by the work
// it did, the spinners' is not, and sched_yield never requeues behind a
// lower priority -- so srfi18-join-spawn-grandchild-2129.scm hung at 290%
// CPU with 17 threads in withdrawCrossThreadWaiter's spinLock and the
// holder runnable but never run. That scheduler-level hang cannot be
// reproduced on a fair scheduler, so this pins the property that prevents
// it: contenders on a held lock burn (almost) no CPU. Pre-fix, four
// contenders spinning through a 120 ms hold cost the process ~4 x 120 ms of
// CPU time (all of one CPU for the whole hold on a single-core box); with
// platform.spinBackoff they spin for microseconds, yield a few dozen times
// and then sleep, so the process gains a few milliseconds at most.
test "kaappi#2446: contenders on a held spin lock sleep instead of burning CPU" {
    if (comptime (platform.is_wasm or platform.is_windows or builtin.single_threaded)) return error.SkipZigTest;
    const Ctx = struct {
        lock: std.atomic.Mutex = .unlocked,
        contending: std.atomic.Value(u32) = .init(0),
        acquired: std.atomic.Value(u32) = .init(0),
        fn contend(self: *@This()) void {
            _ = self.contending.fetchAdd(1, .release);
            memory.spinLock(&self.lock);
            _ = self.acquired.fetchAdd(1, .acq_rel);
            memory.spinUnlock(&self.lock);
        }
    };
    var ctx: Ctx = .{};
    const hold_ns: u64 = 120_000_000;
    memory.spinLock(&ctx.lock);
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Ctx.contend, .{&ctx});
    // Under load a worker may not run until after the hold ends, and would
    // then acquire the lock uncontended -- passing without exercising the
    // held-lock path. Start the clock only once every worker has reached
    // the lock call.
    while (ctx.contending.load(.acquire) != @as(u32, threads.len)) std.Thread.yield() catch {};
    const cpu_before = try processCpuNs();
    platform.sleepNs(hold_ns);
    memory.spinUnlock(&ctx.lock);
    for (threads) |t| t.join();
    const cpu_ns = (try processCpuNs()) - cpu_before;
    try std.testing.expectEqual(@as(u32, 4), ctx.acquired.load(.acquire));
    // 60 ms: half of what even ONE pure spinner burns through the hold, so a
    // regression to spinning fails regardless of how many CPUs the box has.
    if (cpu_ns > 60_000_000) {
        std.debug.print("contenders burned {d} ms of CPU across a {d} ms hold\n", .{ cpu_ns / 1_000_000, hold_ns / 1_000_000 });
        return error.SpinLockContendersBurnCpu;
    }
}

// kaappi#2446: OS threads are detached at spawn and thread-join! waits on
// the spawn's exit flag instead of pthread_join. That flag is raised after
// the thread's very last defer, so by the time a join returns the child has
// released its live-thread count and every registry entry: hasLiveChildThreads
// is false again immediately, never "still true for a few microseconds while
// the LWP finishes". A reap that returned early (or a defer accidentally
// declared after the flag's) shows up here as a true reading.
test "kaappi#2446: thread-join! returns only after the child's whole epilogue" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // thread-start! is unregistered on wasm
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const v = try ctx.vm.eval(
            \\(let ((t (make-thread (lambda () (thread-sleep! 0.001) 'done))))
            \\  (thread-start! t)
            \\  (thread-join! t))
        );
        try std.testing.expect(types.isSymbol(v));
        try std.testing.expect(!srfi18.hasLiveChildThreads());
    }
}

// kaappi#2473: the two pre-spawn failure paths after the extra_roots append
// (the exit-flag create and std.Thread.spawn) used to unwind the counters and
// the envelope but leave the fiber rooted in extra_roots forever -- its status
// never returned to .created, so no thread-join! ever reached reapOsThread,
// the only other remover. This forces the exit-flag allocation to fail via an
// OomAllocator countdown (std.Thread.spawn failure has no injection point)
// and asserts the root count comes back down. Single-threaded by design: the
// injector is thread-affine, and no child is ever spawned.
test "kaappi#2473: thread-start! unwinds extra_roots when the spawn setup fails" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // thread-start! is unregistered on wasm
    // The injector wraps ONLY the exit-flag seam allocator: a countdown on
    // the GC's own allocator would fire during compilation of the form,
    // before thread-start! is ever reached.
    var oom = memory.OomAllocator.init(std.testing.allocator);
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Build the handle without starting it.
    _ = try vm.eval("(define leak-t (make-thread (lambda () 1)))");
    // extra_roots doubles as the VM's scratch during execution, so compare
    // relative to the post-define baseline, not to zero.
    const before = gc.extra_roots.items.len;

    // Route the exit-flag create through the armed injector: the very next
    // raw allocation on this thread fails, which is the OsThreadExit create.
    const saved = srfi18.os_thread_exit_allocator;
    srfi18.os_thread_exit_allocator = oom.allocator();
    defer srfi18.os_thread_exit_allocator = saved;
    oom.countdown = 0;
    const result = vm.eval("(thread-start! leak-t)");
    oom.countdown = null;
    try std.testing.expectError(error.OutOfMemory, result);

    // The fiber must no longer be rooted: without the fix the failed spawn
    // leaves one extra entry, which stays for the life of the GC.
    try std.testing.expectEqual(before, gc.extra_roots.items.len);
}
