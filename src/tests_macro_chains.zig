// Head-position macro expansion chains (kaappi#1796).
//
// A macro whose expansion IS directly another macro use in the same
// position — SRFI 148's CK-machine steps, or a degenerate (loop) → (loop)
// — used to compile by native recursion, one
// expandAndCompileMacroUse → compileExpr → compileForm cycle per link, so
// MAX_MACRO_EXPANSION_DEPTH was implicitly a native-stack guard: raising
// it from 256 to 4096 made a runaway chain overflow the stack, and (in a
// Debug/test build) the segfault fired inside the DebugAllocator's own
// stack capture, whose SelfInfo lock the segfault handler then blocked
// on — the whole test run deadlocked at 0% CPU. The fix iterates chains
// inside expandAndCompileMacroUse at O(1) native stack, bounded by
// MAX_MACRO_EXPANSION_STEPS; the depth cap keeps guarding only genuinely
// nested expansions (which still recurse natively).
//
// These tests pin the two halves of that contract: chains longer than the
// depth cap compile fine, and per-link bookkeeping (hygienic captured
// locals, macro-table state) behaves exactly as the nested recursion did.

const std = @import("std");
const build_options = @import("build_options");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "head-position chain far deeper than the depth cap compiles at O(1) native stack" {
    // Peano countdown: each link consumes one list element, so an
    // N-element argument needs an N-link chain. N is well past
    // MAX_MACRO_EXPANSION_DEPTH (256) — before kaappi#1796's fix this hit
    // MacroExpansionLimit, and any constant large enough for it risked
    // native stack overflow instead. Scaled down under gc-stress: the
    // chain allocates a fresh (shrinking) list copy per link, and a
    // collection per allocation makes the full-size run take minutes.
    const n: usize = if (build_options.gc_stress) 300 else 2000;

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const gpa = std.testing.allocator;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(gpa);
    try src.appendSlice(gpa,
        \\(define-syntax count-down
        \\  (syntax-rules ()
        \\    ((_ ()) 'done)
        \\    ((_ (s . rest)) (count-down rest))))
        \\(count-down (
    );
    for (0..n) |_| try src.appendSlice(gpa, " s");
    try src.appendSlice(gpa, "))");

    const roots_before = ctx.vm.gc.root_count;
    const result = try ctx.vm.eval(src.items);
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("done", types.symbolName(result));
    // The chain roots its links via extra_roots (released by the compile
    // scope), never the fixed root stack — which would overflow its 1024
    // slots at this length.
    try std.testing.expectEqual(roots_before, ctx.vm.gc.root_count);
}

test "hygienic captured-local alias from an early chain link survives to the final form" {
    // (starting) → (finishing (+ secret 1)) → (+ secret 1). The reference
    // to `secret` is introduced by link 1's template and only compiled
    // after link 2 has been processed, so link 1's injected captured-local
    // alias must stay live until the final form compiles — the chain loop
    // must accumulate per-link bookkeeping exactly as the old nested
    // recursion's per-level frames did, not tear it down per link.
    try th.expectEval(
        \\(define (f)
        \\  (define secret 41)
        \\  (define-syntax finishing
        \\    (syntax-rules () ((_ e) e)))
        \\  (define-syntax starting
        \\    (syntax-rules () ((_) (finishing (+ secret 1)))))
        \\  (starting))
        \\(f)
    , 42);
}

test "divergent chain fails with a compile error and leaves the compiler usable" {
    // (kick) → (bad-step gv 2 3): the second link's expansion has no
    // matching pattern. The chain must surface the same compile error the
    // nested recursion produced, and a mid-chain abort must restore all
    // accumulated state. Two observables discriminate the chain-wide
    // unwind: the macro table (bad-step still works afterwards) and the
    // temp-globals hygiene dance — kick's template references `gv`, a
    // non-procedure global, which expansion temporarily marks VOID in the
    // globals map (#1208); a failed restore would leave gv VOID after the
    // aborted compile.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define gv 5)
        \\(define-syntax bad-step
        \\  (syntax-rules () ((_ ok) 'fine)))
        \\(define-syntax kick
        \\  (syntax-rules () ((_) (bad-step gv 2 3))))
    );
    const roots_before = gc.root_count;
    try std.testing.expectError(th.VMError.CompileError, vm.eval("(kick)"));
    try std.testing.expectEqual(roots_before, gc.root_count);

    const gv_after = try vm.eval("gv");
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(gv_after));

    const after = try vm.eval("(bad-step 'x)");
    try std.testing.expect(types.isSymbol(after));
    try std.testing.expectEqualStrings("fine", types.symbolName(after));
}

test "runaway self-expansion is caught by the step limit, not native stack depth" {
    // The tests_robustness twin of this asserts the error; this one pins
    // the kaappi#1796 mechanism: the same runaway must ALSO fail when the
    // chain runs from inside a lambda body (a nested compiler scope with
    // its own locals), where per-link native recursion used to stack the
    // deepest. Nothing here may crash or hang at any depth-cap value.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try std.testing.expectError(th.VMError.CompileError, ctx.vm.eval(
        \\(define-syntax churn
        \\  (syntax-rules ()
        \\    ((_) (churn))))
        \\(define (g) (churn))
        \\(g)
    ));
}
