// Regressions for #2405: a circular datum in CODE position (an R7RS 7.1.2
// datum-label cycle, no macros needed) must be a diagnosed, catchable compile
// error — "circular form in code position" via the syntax_error_detail
// channel — never a native-stack abort, a hang, or a KP9001 "internal error".
//
// The walks that used to assume acyclic forms live across the compile side:
// IR lowering (lowerWithMacros recursion for car-side cycles, the arg/body
// spine walks), the body scanners (scanBodyDefs, spliceLeadingBegins,
// compileExprSequence), let-syntax's body and bindings, the let/do binding
// and command walks, quasiquote's template walk, and the passthrough tail
// fast paths. Each family member below failed differently on `main` (abort,
// hang, or KP9001); the controls pin the datum shapes that must KEEP working:
// quoted circular data, vector constants, and shared-but-acyclic structure.
const std = @import("std");
const th = @import("testing_helpers.zig");
const compiler = @import("compiler.zig");

/// Compile `src` and assert it fails as a compile error whose recorded
/// detail names the circular form. Returns nothing: the VM (and any error
/// state it holds) is gone once this returns. The detail is read from the
/// compiler's threadlocal syntax_error_detail channel — the same string the
/// CLI reporter renders as syntax-error[KP2002].
fn expectCircular(src: []const u8) !void {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try std.testing.expectError(error.CompileError, ctx.vm.eval(src));
    const detail = compiler.getSyntaxErrorDetail();
    if (std.mem.indexOf(u8, detail, "circular form in code position") == null) {
        std.debug.print("expected circular-form detail, got: {s}\n", .{detail});
        return error.TestExpectedCircularForm;
    }
}

test "#2405 repro A: car-side cycle in an argument is a diagnosed error, not an abort" {
    // The one-liner from the issue: lowerCall recursed into the same car
    // edge until the native stack aborted (uncatchable SIGBUS).
    try expectCircular("(display #1=(p #1# q))");
}

test "#2405 repro B: spine cycle in an argument names the cycle, not KP9001" {
    // The arg-spine walk used to spin until the 256-argument cap reported
    // "internal error"; the tortoise-and-hare guard names the cycle instead.
    try expectCircular("#0=(display 1 . #0#)");
}

test "#2405 repro C: a cyclic let-syntax body terminates with the diagnosis" {
    // compileSyntaxBody's spine walk spun forever compiling an unbounded
    // instruction stream — the body IS the whole form, so the walk never
    // reached a non-pair.
    try expectCircular("#0=(let-syntax () . #0#)");
}

test "#2405: the body/binding walk family terminates with the diagnosis" {
    // and/or/when/unless lower eagerly (lowerList/lowerCondBody); the
    // let-family and lambda bodies bottom out in scanBodyDefs's splice scan;
    // let/letrec/do bindings walk their binding lists; a begin inside an
    // argument walks lowerBegin. Each spun or capped into KP9001 on `main`.
    try expectCircular("#0=(and 1 . #0#)");
    try expectCircular("#0=(or 1 . #0#)");
    try expectCircular("#0=(when 1 . #0#)");
    try expectCircular("#0=(unless 1 . #0#)");
    try expectCircular("#0=(lambda () . #0#)");
    try expectCircular("#0=(let ((x 1)) . #0#)");
    try expectCircular("#0=(let* ((x 1)) . #0#)");
    try expectCircular("#0=(letrec ((x 1)) . #0#)");
    try expectCircular("(let #0=((x 1) . #0#) x)");
    try expectCircular("(letrec #0=((x 1) . #0#) x)");
    try expectCircular("#0=(do ((i 0 (+ i 1))) ((> i 2)) . #0#)");
    try expectCircular("(do #0=((i 0) . #0#) (#t) 1)");
    try expectCircular("(display (begin 1 . #0=(begin 2 . #0#)))");
}

test "#2405: a cyclic named-let body is rejected by the rename walk" {
    // renameInBody rebuilds every pair of the named-let body; a cycle has
    // no leaves to bottom out at, so it recursed forever before the path
    // set.
    try expectCircular("(let loop () #0=(loop . #0#))");
}

test "#2405: cyclic quasiquote templates are rejected, not hung" {
    // compileQQ rebuilds the template with runtime conses — a cycle has no
    // finite form — and the splicing desugar's segment walk overflowed as
    // KP9001. Both now name the cycle.
    try expectCircular("#0=(quasiquote (1 . #0#))");
    try expectCircular("(display `(1 . #0=(2 . #0#)))");
}

test "#2405: the passthrough tail fast paths terminate" {
    // apply/call-with-values/eval in tail position count their operand
    // spine first; that count spun forever on a cycle.
    try expectCircular("#0=(apply + . #0#)");
    try expectCircular("#0=(call-with-values . #0#)");
    try expectCircular("#0=(eval (quote 1) . #0#)");
}

/// Compile `src` and assert only that it fails as a compile error — for
/// shapes whose exact diagnosis depends on which guard fires first (a
/// cyclic clause rotation may hit a non-pair clause check before the
/// tortoise meets). Termination is the contract under test.
fn expectCompileError(src: []const u8) !void {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try std.testing.expectError(error.CompileError, ctx.vm.eval(src));
}

test "#2405 review: the SRFI-17 set! target spine is guarded" {
    // CodeRabbit on PR #2413: the generalized-set! setter desugar walked
    // the target's operand spine without a guard — this exact form hung.
    try expectCircular("(set! #0=(f 1 . #0#) 3)");
}

test "#2405 review: a cyclic syntax-rules pattern is invalid grammar, not a hang" {
    // The pattern validator's spine loop and recursion had no bounds; a
    // cyclic pattern is not valid grammar, which is the truthful verdict.
    try expectCompileError("(define-syntax m (syntax-rules () ((_ #0=(a . #0#)) 1)))");
}

test "#2405 review: clause-list cycles terminate whatever the clause contents" {
    // cond/cond-expand/case terminate on a clause list whose own spine
    // cycles, whatever the clause contents (a matched clause elsewhere in
    // the rotation only exits early by luck).
    try expectCircular("(cond . #0=((1 1) . #0#))");
    try expectCompileError("(case 1 . #0=((2) . #0#))");
    // The top-level cond-expand selector (vm_eval.selectCondExpandBody)
    // reports through the VM's own detail channel, not the compiler's —
    // a separate reporter path with the same named diagnosis.
    {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        try std.testing.expectError(error.CompileError, ctx.vm.eval("(cond-expand . #0=((no-such-feature) . #0#))"));
        try std.testing.expect(std.mem.indexOf(u8, ctx.vm.getErrorDetail(), "circular form in code position") != null);
    }
    // A cyclic improper tail after a fixed-arity form's last operand: `if`
    // historically accepted it silently and compiled garbage; now the
    // cycle at least is named (extra non-cyclic forms stay accepted).
    try expectCircular("#0=(if #t 1 . #0#)");
    // The legacy begin path (passthrough/compileForm) carries the same guard
    // as the IR's lowerBegin.
    try expectCompileError("(define-syntax b (syntax-rules () ((_ . xs) (begin . xs)))) (b . #0=(1 . #0#))");
}

test "#2405 control: quoted circular data still evaluates and prints" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // The #1954/#1955 printer cycle handling is untouched — quoting makes
    // the datum a constant, and no code-position walk ever enters it.
    const value = try ctx.vm.eval("(car (cdr '#0=(zz . #0#)))");
    try std.testing.expectEqualStrings("zz", @import("types.zig").symbolName(value));
}

test "#2405 control: shared-but-acyclic code still compiles" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // Path membership, not prior visitation: the same #1= sub-form used
    // twice as SIBLINGS renews legitimately on both walks (lowerBegin here,
    // and the expander shares pattern-variable subtrees the same way).
    try th.expectEvalTrue("(= 3 (begin #1=(+ 1 2) #1#))");
    // A vector containing itself is a constant in code position: no walk
    // enters it, so it compiles and evaluates like any other datum.
    try th.expectEvalTrue("(let ((v #0=#(1 #0#))) (eq? v (vector-ref v 1)))");
}

test "#2405: the circular-form detail survives to the reporting channel and resets on the next compile" {
    // The diagnosis travels through the threadlocal syntax_error_detail
    // channel, which the compile entry points clear at entry: a failing
    // compile leaves it set for the reporter, and the next compile starts
    // clean — no unrelated error can be misreported as a syntax error.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try std.testing.expectError(error.CompileError, ctx.vm.eval("(display #1=(p #1# q))"));
    try std.testing.expect(std.mem.indexOf(u8, compiler.getSyntaxErrorDetail(), "circular form in code position") != null);
    _ = try ctx.vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(usize, 0), compiler.getSyntaxErrorDetail().len);
}
