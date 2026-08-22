//! Bounded-step execution tests (kaappi#2283). Exercise vm_step.Stepper and
//! the beginStep/resumeStep VM entry points: finite programs finish, a paused
//! form resumes to the same result a batch run would produce, the motivating
//! constant-space infinite program runs forever in bounded memory without ever
//! completing, and a host Stop flag ends a running program cleanly.

const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const memory = @import("memory.zig");
const th = @import("testing_helpers.zig");
const Stepper = @import("vm_step.zig").Stepper;
const StepOutcome = @import("vm_step.zig").StepOutcome;

/// Collection-on-every-allocation makes each executed instruction far slower
/// without changing the instruction *count*, so the loop-heavy cases scale
/// their iteration bound down under gc-stress (kaappi#1401 convention) while
/// still exceeding the small step budget enough to force real pauses.
const stress = @import("build_options").gc_stress;
const loop_n: i64 = if (stress) 800 else 40000;

/// Pump `stepper` to completion under `budget`, capping iterations so a bug
/// that fails to make progress fails the test instead of hanging.
fn runToDone(stepper: *Stepper, budget: u64, max_steps: usize) !usize {
    var steps: usize = 0;
    while (steps < max_steps) : (steps += 1) {
        if (stepper.step(budget) == .done) return steps + 1;
    }
    return error.DidNotFinish;
}

test "stepper: finite program finishes and side effects persist" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const src =
        \\(define a 10)
        \\(define b 32)
        \\(define result (+ a b))
    ;
    var stepper: Stepper = undefined;
    stepper.init(vm, src, "<test>");
    defer stepper.deinit();

    // A generous budget finishes every form in a single step.
    const n = try runToDone(&stepper, 1_000_000, 8);
    try testing.expect(n >= 1);
    try testing.expect(!stepper.had_error);

    const result = try vm.eval("result");
    try testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "stepper: a long form pauses, resumes, and yields the batch result" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Enough iterations of real work that, with a small budget, the form cannot
    // finish in one step — so it must pause mid-form and resume across many.
    const src = try std.fmt.allocPrint(testing.allocator,
        \\(define n 0)
        \\(do ((i 0 (+ i 1))) ((= i {d})) (set! n (+ n 1)))
    , .{loop_n});
    defer testing.allocator.free(src);
    var stepper: Stepper = undefined;
    stepper.init(vm, src, "<test>");
    defer stepper.deinit();

    var saw_pause = false;
    var steps: usize = 0;
    while (steps < 1_000_000) : (steps += 1) {
        const outcome = stepper.step(1024);
        if (outcome == .done) break;
        saw_pause = true;
    } else return error.DidNotFinish;

    try testing.expect(saw_pause); // it really did pause mid-form at least once
    try testing.expect(!stepper.had_error);
    const n = try vm.eval("n");
    try testing.expectEqual(loop_n, types.toFixnum(n));
}

test "stepper: a zero budget still makes progress" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // budget 0 must not spin forever returning .running without reading a form.
    var stepper: Stepper = undefined;
    stepper.init(vm, "(define z (+ 2 3))", "<test>");
    defer stepper.deinit();

    var steps: usize = 0;
    while (steps < 1000) : (steps += 1) {
        if (stepper.step(0) == .done) break;
    } else return error.DidNotFinish;
    try testing.expect(!stepper.had_error);
    try testing.expectEqual(@as(i64, 5), types.toFixnum(try vm.eval("z")));
}

test "stepper: constant-space infinite program never completes but keeps stepping" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The motivating case from the issue: runs forever in bounded memory.
    const src = "((call/cc call/cc) (call/cc call/cc))";
    var stepper: Stepper = undefined;
    stepper.init(vm, src, "<test>");
    defer stepper.deinit();

    var prev = vm.instruction_counter;
    var i: usize = 0;
    const rounds: usize = if (stress) 4 else 25;
    while (i < rounds) : (i += 1) {
        const outcome = stepper.step(if (stress) 2048 else 8192);
        try testing.expectEqual(StepOutcome.running, outcome);
        // Each step made forward progress (advanced the instruction counter).
        try testing.expect(vm.instruction_counter > prev);
        prev = vm.instruction_counter;
    }
    try testing.expect(!stepper.finished);
}

test "stepper: host Stop flag ends a running program cleanly" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // An unbounded loop that never terminates on its own.
    const src = "(let loop ((i 0)) (loop (+ i 1)))";
    var stepper: Stepper = undefined;
    stepper.init(vm, src, "<test>");
    defer stepper.deinit();

    try testing.expectEqual(StepOutcome.running, stepper.step(8192));
    stepper.requestStop();
    // The next step observes the flag at the safepoint and unwinds to done.
    try testing.expectEqual(StepOutcome.done, stepper.step(8192));
    try testing.expect(stepper.finished);
    // A cooperative stop is not a program error.
    try testing.expect(!stepper.had_error);
}

test "stepper: a form error is reported but the program still finishes" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const src =
        \\(car 5)
        \\(define after 7)
    ;
    var stepper: Stepper = undefined;
    stepper.init(vm, src, "<test>");
    defer stepper.deinit();

    _ = try runToDone(&stepper, 1_000_000, 8);
    try testing.expect(stepper.had_error);
    // Execution continued past the error to the next form, matching runFile.
    const after = try vm.eval("after");
    try testing.expectEqual(@as(i64, 7), types.toFixnum(after));
}

test "stepper: a form that pauses then raises unwinds roots cleanly" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The loop runs long enough to pause mid-form under the small budget; when
    // it finally exits it raises. The error therefore unwinds a *resumed* form,
    // exercising resumeStep's root-boundary truncation (kaappi#2283). A stale
    // boundary would leave a bogus root the GC later marks — caught here under
    // -Dgc-stress by the next form's allocations and eval.
    const src = try std.fmt.allocPrint(testing.allocator,
        \\(do ((i 0 (+ i 1))) ((= i {d}) (car 5)))
        \\(define recovered (list 1 2 3))
    , .{loop_n});
    defer testing.allocator.free(src);
    var stepper: Stepper = undefined;
    stepper.init(vm, src, "<test>");
    defer stepper.deinit();

    var steps: usize = 0;
    while (steps < 1_000_000) : (steps += 1) {
        if (stepper.step(1024) == .done) break;
    } else return error.DidNotFinish;

    try testing.expect(stepper.had_error);
    // The next form ran on an uncorrupted root stack and built a live list.
    const len = try vm.eval("(length recovered)");
    try testing.expectEqual(@as(i64, 3), types.toFixnum(len));
}

test "beginStep/resumeStep: direct VM API pauses and resumes" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    const vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const compiler = @import("compiler.zig");
    const reader = @import("reader.zig");
    const src = try std.fmt.allocPrint(testing.allocator, "(let loop ((i 0)) (if (= i {d}) i (loop (+ i 1))))", .{loop_n});
    defer testing.allocator.free(src);
    var r = reader.Reader.init(&gc, src);
    defer r.deinit();
    var expr = try r.readDatum();
    gc.pushRoot(&expr);
    // compileExpressionWithMacros leaves `func` rooted in gc.extra_roots on
    // success, so no separate root is needed to keep it alive across beginStep.
    const func = try compiler.compileExpressionWithMacros(&gc, expr, &vm.macros, vm.globals);
    gc.popRoot();

    var out: types.Value = types.VOID;
    var status = try vm.beginStep(func, vm.instruction_counter + 2048, &out);
    var guard: usize = 0;
    while (status == .paused and guard < 100_000) : (guard += 1) {
        status = try vm.resumeStep(vm.instruction_counter + 2048, &out);
    }
    try testing.expect(status == .done);
    try testing.expectEqual(loop_n, types.toFixnum(out));
}
