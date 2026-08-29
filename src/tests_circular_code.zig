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

test "#2405 review: cycles crossing the lower/emit re-entry boundary are diagnosed" {
    // baijum's review of PR #2413: lowering a sub-form and emitting its node
    // are separate phases, and each compileExprViaIR builds a fresh IR — so
    // a cycle whose back-edge crosses that boundary (`#0=(let ((x #0#)) x)`:
    // the let's init IS the let) never re-meets itself in one lowering and
    // used to recurse through compileLet → compileExprViaIR → ... until the
    // native stack aborted. The guard now spans the boundary on the
    // Compiler: a root stays live across lower+emit (code_roots, through the
    // child-compiler chain), and a form embedded in a fresh wrapper
    // (let-values producers) keeps its own span on the shared lowering path.
    try expectCircular("(display #0=(let ((x #0#)) x))");
    try expectCircular("(display #0=(letrec ((x #0#)) x))");
    try expectCircular("(display #0=(let* ((x #0#)) x))");
    try expectCircular("(display ((lambda () #0=(lambda () . #0#))))");
    try expectCircular("(define f #0=(f . #0#))");
    try expectCircular("(display #0=(cond (#0# #t)))");
    try expectCircular("(display #0=(do () (#0#) 1))");
    try expectCircular("(display #0=(let-values (((a) #0#)) a))");
    // The quasiquote splicing desugar re-wraps a template element as a
    // fresh `(quasiquote elem)` pair per round — the wrapper's fresh address
    // hides the repeat, so the element itself carries the span. This used to
    // bottom out in KP9001.
    try expectCircular("(display `#0=(x ,@(list 1) #0#))");
}

test "#2405 review round 2: case datums, syntax-rules outer lists, top-level begin" {
    // CodeRabbit's re-review of PR #2413 found three more walks in the
    // family: the datum list inside a case clause, the literals/rules lists
    // of a syntax-rules spec (before pattern validation ever runs), and the
    // top-level begin splicer — which compiled AND executed its rotation
    // forever. The and/or/when/unless and cond-expand feature-operand
    // findings from the same round do not reproduce: those forms lower
    // through the guarded IR paths, and a feature-requirement cycle always
    // rotates through the operator symbol, which evaluates as an
    // unrecognized (false) feature.
    try expectCircular("(case 1 (#0=(1 . #0#) (quote a)))");
    try expectCircular("(define-syntax m (syntax-rules #0=((). #0#) ((_ x) x)))");
    // The top-level begin reports through the VM's detail channel.
    {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        try std.testing.expectError(error.CompileError, ctx.vm.eval("(begin . #0=(1 . #0#))"));
        try std.testing.expect(std.mem.indexOf(u8, ctx.vm.getErrorDetail(), "circular form in code position") != null);
    }
}

test "#2405 review round 3: define-values, parameterize, cyclic syntax-rules TEMPLATES" {
    // baijum's review of PR #2420: three more members of the family, plus
    // the one that mattered most — a cyclic TEMPLATE aborted the definition
    // itself (`((_ x) #0=(f #0#))` SIGBUSed in the free-ref walk, the
    // uncatchable class #2405 was filed for, from a define-syntax never
    // used). The free-ref collector now carries the active-path discipline
    // (its recursion funnels through one function on both car and cdr, so a
    // single membership test catches both shapes) plus tortoises on the
    // binding/params/nested-rules spines it iterates directly. The
    // top-level define-values formals walk reports through the VM detail
    // channel like the other top-level handlers.
    try expectCircular("(parameterize #0=((p 1) . #0#) 1)");
    try expectCircular("(define-syntax m (syntax-rules () ((_ x) #0=(begin . #0#))))");
    try expectCircular("(define-syntax m (syntax-rules () ((_ x) #0=(f #0#))))");
    // Nested binding/params walks inside a template.
    try expectCircular("(define-syntax m (syntax-rules () ((_ x) (let #0=((y 1) . #0#) y))))");
    try expectCircular("(define-syntax m (syntax-rules () ((_ x) (lambda #0=(a . #0#) 1))))");
    // Top-level define-values formals — VM detail channel (KP2001 path).
    {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        try std.testing.expectError(error.CompileError, ctx.vm.eval("(define-values #0=(a . #0#) (values 1))"));
        try std.testing.expect(std.mem.indexOf(u8, ctx.vm.getErrorDetail(), "circular form in code position") != null);
        try std.testing.expectError(error.CompileError, ctx.vm.eval("(define-values (a . #0=(b . #0#)) (values 1 2))"));
        try std.testing.expect(std.mem.indexOf(u8, ctx.vm.getErrorDetail(), "circular form in code position") != null);
    }
}

test "#2405 review control: shared sub-forms in sibling positions still compile" {
    // The other half of the same review: an #N= sub-form used in a let init
    // AND the body renews as a sibling (sequential compile units), which is
    // legal and must keep working.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try th.expectEvalTrue("(= 3 (let ((x #1=(+ 1 2))) #1#))");
    // A lambda body compiled by a CHILD compiler — the parent-chain lookup
    // must not misread ordinary nesting as a cycle.
    try th.expectEvalTrue("(= 7 ((lambda () (let ((x 3)) (+ x 4)))))");
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
