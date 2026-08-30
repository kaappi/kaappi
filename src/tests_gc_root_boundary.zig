// Root-stack unwinding at the pipeline boundaries (#1855).
//
// The canonical rooting pattern documented in .claude/rules/gc-safety.md
//
//     var a = try gc.allocSomething(...);
//     gc.pushRoot(&a);
//     const result = try gc.allocOther(a, ...);
//     gc.popRoot();
//
// leaks the pushed root when the *protected* call is the one that fails: the
// error unwinds past `popRoot`. Nothing else ever lowers `root_count`, so the
// root stack was left holding a pointer into a dead stack frame, which the
// next collection dereferences (a garbage flonum under NaN-boxing, or a fake
// heap pointer → UB). A leaked entry also breaks LIFO pairing for every
// `defer popRoot()` still to fire above it on the unwind path, so those pops
// start removing the wrong entries.
//
// Rather than an errdefer at each of the ~340 push sites, the boundaries
// snapshot the depth on entry and truncate back to it: the
// `compileExpression*` entry points, `vm.eval`, and `execute` (see
// GC.truncateRoots). These tests sweep a real OutOfMemory across every
// allocation the pipeline makes and assert the depth came back each time.
//
// The lever is `gc.oom_countdown`, not FailingAllocator (documented
// deep-pipeline limitation) and not `gc.memory_limit`: the limit is an
// absolute watermark that only trips once one form *retains* more than the
// headroom, which in practice fails only within the first few allocations and
// never reaches the expander. Pre-fix, the ellipsis sweeps below leaked on
// 10 of 54 and 12 of 48 injected failures respectively.

const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const compiler_mod = @import("compiler.zig");
const reader_mod = @import("reader.zig");

/// Fail the n-th heap allocation of `source`, for every n in 0..=upto, and
/// assert the root stack is exactly as deep afterwards as it was before.
/// Returns how many of the sweeps actually failed, so a caller can assert the
/// sweep was not vacuous.
fn sweepOom(ctx: *th.TestContext, source: []const u8, upto: usize) !usize {
    const base = ctx.gc.root_count;
    var failures: usize = 0;
    var n: usize = 0;
    while (n <= upto) : (n += 1) {
        ctx.gc.oom_countdown = n;
        const result = ctx.vm.eval(source);
        ctx.gc.oom_countdown = null;
        if (result) |_| {} else |_| failures += 1;
        if (base != ctx.gc.root_count) {
            std.debug.print(
                "root depth {d} -> {d} after failing allocation #{d} of: {s}\n",
                .{ base, ctx.gc.root_count, n, source },
            );
            // Put it back before failing so `ctx.deinit()`'s own teardown
            // does not then collect through the dead entry and turn a clear
            // assertion failure into a crash.
            ctx.gc.root_count = base;
            return error.RootStackNotUnwound;
        }
        // A collection with a dead root live is the actual failure mode; run
        // one on every iteration so a leak that slipped through would also
        // trip the use-after-free detection of a -Dgc-stress build.
        ctx.gc.collect();
    }
    return failures;
}

// Macro expansion is where the leak was confirmed: instantiateEllipsis pushes
// a root around the `try gc.allocPair` that builds each expansion element (and
// around the synthetic `(elem ... ...)` template), both flagged in the PR
// #1853 review.
test "root depth is restored when macro expansion OOMs" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval(
        \\(define-syntax m
        \\  (syntax-rules ()
        \\    ((_ x ...) (list (+ x 1) ...))))
    );
    const failures = try sweepOom(&ctx, "(m 1 2 3 4 5)", 200);
    try std.testing.expect(failures > 0);
}

test "root depth is restored when nested-ellipsis expansion OOMs" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval(
        \\(define-syntax n
        \\  (syntax-rules ()
        \\    ((_ (a b ...) ...) (list (list a b ...) ...))))
    );
    const failures = try sweepOom(&ctx, "(n (1 2 3) (4 5 6))", 200);
    try std.testing.expect(failures > 0);
}

// The other pipeline shapes were balanced already; sweep them so a future
// unbalanced push/pop anywhere under these boundaries is caught here rather
// than by a mystery collection crash.
test "root depth is restored when other pipeline stages OOM" {
    const cases = [_][]const u8{
        "(define-record-type <pt> (mk a b) pt? (a pa) (b pb))",
        "(let-syntax ((f (syntax-rules () ((_ q) (* q q))))) (f 4))",
        "(let ((y 5)) `(a b ,y ,@(list 1 2 3)))",
        "(define-library (probe a) (import (scheme base)) (export z) (begin (define (z) 7)))",
        "(guard (e (#t 'caught)) (vector-ref (vector 1 2) 9))",
        "(guard (e (#t 'x)) (dynamic-wind (lambda () (list 1 2)) (lambda () (car 5)) (lambda () (list 3 4))))",
        "(string-append (number->string 12345) (symbol->string 'abc))",
        "(call-with-current-continuation (lambda (k) (map (lambda (v) (k (list v))) '(1 2 3))))",
    };
    for (cases) |src| {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const failures = try sweepOom(&ctx, src, 150);
        try std.testing.expect(failures > 0);
    }
}

// A failed form must not poison the ones after it: the whole point of putting
// the depth back is that the next collection walks only live roots.
test "eval keeps working after a failed allocation deep in expansion" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval(
        \\(define-syntax m
        \\  (syntax-rules ()
        \\    ((_ x ...) (list (+ x 1) ...))))
    );
    var n: usize = 0;
    while (n <= 60) : (n += 1) {
        ctx.gc.oom_countdown = n;
        _ = ctx.vm.eval("(m 1 2 3 4 5)") catch {};
        ctx.gc.oom_countdown = null;
        ctx.gc.collect();
        const ok = try ctx.vm.eval("(apply + (m 1 2 3 4 5))");
        try std.testing.expectEqual(@as(i64, 20), types.toFixnum(ok));
    }
}

// The boundary must never truncate a root its *caller* still owns: a
// successful compile has to leave the depth exactly where it found it, and a
// caller-pushed root has to survive a failing one.
test "compile boundary preserves caller roots across success and failure" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // A macro use, because that is what makes a *compile* allocate Scheme
    // objects: bytecode, IR and constant pools all use the raw allocator, so
    // only expansion goes through the GC — and only expansion can fail here.
    _ = try ctx.vm.eval(
        \\(define-syntax m
        \\  (syntax-rules ()
        \\    ((_ x ...) (list (+ x 1) ...))))
    );

    var held = try ctx.gc.allocPair(types.makeFixnum(1), types.NIL);
    ctx.gc.pushRoot(&held);
    defer ctx.gc.popRoot();

    var reader = reader_mod.Reader.init(&ctx.gc, "(m 1 2 3)");
    defer reader.deinit();
    var expr = try reader.readDatum();
    ctx.gc.pushRoot(&expr);
    defer ctx.gc.popRoot();
    const base = ctx.gc.root_count;

    const func = try compiler_mod.compileExpressionWithMacros(&ctx.gc, expr, &ctx.vm.macros, ctx.vm.globals);
    compiler_mod.Compiler.unrootFunction(&ctx.gc, func);
    try std.testing.expectEqual(base, ctx.gc.root_count);

    var failures: usize = 0;
    var n: usize = 0;
    while (n <= 60) : (n += 1) {
        ctx.gc.oom_countdown = n;
        const bad = compiler_mod.compileExpressionWithMacros(&ctx.gc, expr, &ctx.vm.macros, ctx.vm.globals);
        ctx.gc.oom_countdown = null;
        if (bad) |f| compiler_mod.Compiler.unrootFunction(&ctx.gc, f) else |_| failures += 1;
        // Never below `base` either: truncating a root the caller still owns
        // would be the same dangling-pointer bug with the blame reversed.
        try std.testing.expectEqual(base, ctx.gc.root_count);
    }
    try std.testing.expect(failures > 0);

    // The caller's roots are still there and still point at live data.
    ctx.gc.collect();
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(held)));
    try std.testing.expect(types.isPair(expr));
}

// truncateRoots only ever shrinks. `root_count` below the snapshot means an
// over-pop, which re-rooting cannot repair: the slots it would resurrect may
// already have been overwritten by an inner frame that has since returned,
// which is exactly the dangling pointer this mechanism exists to remove.
test "truncateRoots never grows the root stack" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    var a: types.Value = types.NIL;
    var b: types.Value = types.NIL;
    gc.pushRoot(&a);
    gc.pushRoot(&b);
    try std.testing.expectEqual(@as(u32, 2), gc.root_count);

    gc.truncateRoots(5);
    try std.testing.expectEqual(@as(u32, 2), gc.root_count);

    gc.truncateRoots(2);
    try std.testing.expectEqual(@as(u32, 2), gc.root_count);

    gc.truncateRoots(1);
    try std.testing.expectEqual(@as(u32, 1), gc.root_count);
    gc.popRoot();
}

// The reader's complex-number tokenizer rooted its two component slots on the
// LIFO root stack and left them there until Reader.deinit (kaappi#2166). When
// a complex/rational number was an element of a list, that persistent push
// landed *between* the balanced pushRoot/popRoot pairs readList wraps around
// each element, so a later `defer popRoot()` popped the reader's slot instead
// of the list's — orphaning a live list root that dangled until a collection
// marked it. It surfaced as a crash only under specific GC timing (riscv64),
// but the invariant it violates is platform-independent and checkable here:
// reading one datum must leave the root stack exactly as deep as it found it
// (kaappi#2283). Pre-fix, each complex/rational read grew root_count by 2.
test "reader does not leak roots across a complex-number datum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    memory.setGCInstance(&gc);

    const sources = [_][]const u8{
        "1+2i",
        "3/4-5/6i",
        "#xa/b+c/di",
        "(list 1/2 3+4i 5)", // the list-element case that broke LIFO
        "(+ 1+2i (* 3/4 5-6i))",
    };
    for (sources) |src| {
        var r = reader_mod.Reader.init(&gc, src);
        defer r.deinit();
        const before = gc.root_count;
        var expr = try r.readDatum();
        gc.pushRoot(&expr);
        // A forced collection here dereferences every rooted slot; a leaked,
        // now-dangling reader slot would be marked (and crash under the UAF
        // detector) instead of staying balanced.
        gc.collect();
        gc.popRoot();
        try std.testing.expectEqual(before, gc.root_count);
    }
}

// #2435: `gc.oom_countdown`, the lever every sweep above pulls, only sees GC
// (`allocXxx`) allocations — it fires from `maybeCollect`. A whole class of
// error paths allocates straight from the raw allocator and is invisible to
// it: the VM's growable register/frame/handler/wind stacks, the fiber
// snapshot buffers, the reactor timer heap, and the scheduler's
// `driving_waits` list — precisely the allocations behind the fiber
// scheduler's OOM paths (#2429, #2433), whose regression tests this blocked.
// `memory.OomAllocator` is the raw-allocator counterpart, with an independent
// countdown in a wrapper over the backing allocator. This proves it reaches a
// real VM's register-file growth — an `allocSliceNoFill` `oom_countdown`
// cannot touch — while leaving construction untouched until it is armed.
test "OomAllocator injects a raw-allocator OutOfMemory oom_countdown cannot reach" {
    var oom = memory.OomAllocator.init(std.testing.allocator);
    var gc = memory.GC.init(oom.allocator());
    const vm = th.makeTestVM(&gc) catch |err| {
        gc.deinit();
        return err;
    };
    defer {
        vm.deinit();
        gc.deinit();
    }

    // A GC OOM injector cannot reach the register-file realloc: even armed to
    // fail its very next GC allocation, the growth (a raw `allocSliceNoFill`,
    // never routed through `maybeCollect`) still succeeds.
    std.debug.assert(vm.registers.len * 2 <= vm_mod.MAX_REGISTER_LIMIT);
    gc.oom_countdown = 0;
    try vm.ensureRegisterCapacity(vm.registers.len + 1);
    gc.oom_countdown = null;

    // The raw injector does reach it. Armed at 0, the next raw acquisition —
    // the register-file realloc — fails, surfacing as VMError.OutOfMemory.
    const target = vm.registers.len + 1;
    std.debug.assert(target <= vm_mod.MAX_REGISTER_LIMIT);
    oom.countdown = 0;
    try std.testing.expectError(error.OutOfMemory, vm.ensureRegisterCapacity(target));

    // Disarmed, the identical growth succeeds: the failure was the injector,
    // and the VM is otherwise healthy.
    oom.countdown = null;
    try vm.ensureRegisterCapacity(target);
    try std.testing.expect(vm.registers.len >= target);
}
