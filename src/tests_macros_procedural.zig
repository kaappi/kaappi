// ---------------------------------------------------------------------------
// SRFI 211 (procedural macro transformers) + SRFI 213 (identifier
// properties) — the issue #1699 closing slice, split out of tests_macros.zig
// (kept that file under the 1500-line policy) as its own natural seam. The
// transformer expression evaluates at macro-definition time (global env); the
// ER rename/compare procedures ride expander.expandProceduralMacro's
// threadlocal context; SRFI 213 lookups arrive through the procedure-result
// re-entry protocol. End-to-end conformance lives in
// tests/scheme/srfi/srfi211.scm and srfi213.scm; these cover the engine
// seams — including the KEP-0006 step 1 forced-GC rooting tests (#2390) at
// the bottom of this file.
// ---------------------------------------------------------------------------
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const compiler = @import("compiler.zig");

test "SRFI 211: er-macro-transformer expands with definition-env resolution" {
    try th.expectEval(
        \\(begin
        \\  (define-syntax add1
        \\    (er-macro-transformer
        \\     (lambda (form rename compare) (list (rename '+) (car (cdr form)) 1))))
        \\  (add1 41))
    , 42);
}

test "SRFI 211: rename gensyms fresh names so introduced binders cannot capture" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax with-t
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'let) (list (list (rename 'er-t) 999))
        \\             (car (cdr form))))))
        \\  (define er-t 'user)
        \\  (eq? (with-t er-t) 'user))
    );
}

test "SRFI 211: rename is consistent within one expansion" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax same?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (eq? (rename 'zzq) (rename 'zzq))))))
        \\  (same?))
    );
}

test "SRFI 211: compare answers free-identifier equality for else" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax is-else?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (compare (car (cdr form)) (rename 'else))))))
        \\  (and (is-else? else) (not (is-else? other))))
    );
}

// kaappi#2388: compare is binding-aware free-identifier=? — the same
// machinery syntax-rules literal matching runs on (literal_bound +
// use_check.resolve), so the KEP-0006 four-quadrant answers hold: a
// use-site local rebinding of a keyword spelling is refused for both the
// reserved (bare-rename) and renamed (global-name) keyword shapes, while
// an unshadowed use still compares equal. End-to-end parity against a
// syntax-rules cond-style transformer is pinned in
// tests/scheme/srfi/srfi211.scm (KEP-0018 UQ6). The macro names carry a
// q2388- prefix because a vm.eval'd define-syntax re-using a keyword
// already defined by an earlier test in this process trips a pre-existing
// quirk unrelated to compare (kaappi#2400).
test "SRFI 211: compare refuses a locally rebound keyword spelling (#2388)" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax q2388-else?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (compare (car (cdr form)) (rename 'else))))))
        \\  (define-syntax q2388-arrow?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (compare (car (cdr form)) (rename '=>))))))
        \\  (and (q2388-else? else)
        \\       (q2388-arrow? =>)
        \\       (not (let ((else 1)) (q2388-else? else)))
        \\       (not (let ((=> 1)) (q2388-arrow? =>)))))
    );
}

test "SRFI 211: compare refuses a locally rebound rename of a global name (#2388)" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax q2388-values?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (compare (car (cdr form)) (rename 'values))))))
        \\  (and (q2388-values? values)
        \\       (not (let ((values 1)) (q2388-values? values)))))
    );
}

// Pairwise comparison of two USE-SITE tokens (the duplicate-key idiom)
// must stay reflexive even when the spelling is locally bound at the use
// site: with no bare rename of that spelling in the invocation, compare
// sees the same identifier on both sides.
test "SRFI 211: compare stays reflexive on plain use-site tokens (#2388)" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax q2388-tok=?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote)
        \\             (compare (car (cdr form)) (car (cddr form)))))))
        \\  (and (q2388-tok=? vv vv)
        \\       (let ((vv 1)) (q2388-tok=? vv vv))))
    );
}

// A macro-INTRODUCED keyword (rename product, gensym-marked) compares
// equal to the definition-side keyword even where a use-site local
// shadows the bare spelling — the hygiene quadrant reserved-form
// spellings cannot express (they stay bare, so both systems refuse under
// shadowing; see the srfi211.scm parity suite).
test "SRFI 211: a macro-introduced keyword stays hygienic under shadowing (#2388)" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax q2388-arrow2?
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (compare (car (cdr form)) (rename '=>))))))
        \\  (define-syntax q2388-probe
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list 'q2388-arrow2? (rename '=>)))))
        \\  (and (q2388-probe) (let ((=> 1)) (q2388-probe))))
    );
}

test "SRFI 211: lisp-transformer receives the whole use datum, unhygienically" {
    try th.expectEval(
        \\(begin
        \\  (define-syntax lt
        \\    (lisp-transformer
        \\     (lambda (form) (list '+ (length form) (car (cdr form))))))
        \\  (lt 40))
    , 42);
}

test "SRFI 211: transformer spec evaluating to a non-procedure is a compile error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval("(define-syntax bad (er-macro-transformer 42))");
    try std.testing.expectError(error.CompileError, result);
}

test "SRFI 211: transformer raising at expansion time is a compile error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(define-syntax boom
        \\  (er-macro-transformer (lambda (f r c) (error "expansion refused"))))
    );
    const result = ctx.vm.eval("(boom)");
    try std.testing.expectError(error.CompileError, result);
}

// #1846: the condition a procedural transformer raises used to be computed,
// stored on the VM, and then discarded -- CompileError.InvalidSyntax carried
// no detail, so the top-level reporter fell back to a bare "invalid syntax"
// with no hint of the real cause (see #1831, where this hid the actual
// "undefined variable 'cadar'" message for days). It now reaches the same
// compiler.syntax_error_detail channel `syntax-error` reports through, via
// the globals.error_detail_for_macro hook vm.callProcForMacro/errorDetailForMacro
// populate. `eval` returns CompileError directly without consuming that
// buffer (unlike the CLI's reportCompileError/kaappi check paths), so it is
// still readable here immediately after.
test "SRFI 211: transformer's raised condition reaches syntax_error_detail (#1846)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(define-syntax boom
        \\  (er-macro-transformer (lambda (f r c) (error "expansion refused" 'x 42))))
    );
    const result = ctx.vm.eval("(boom)");
    try std.testing.expectError(error.CompileError, result);
    try std.testing.expectEqualStrings("expansion refused x 42", compiler.getSyntaxErrorDetail());
}

test "SRFI 211: a failing primitive call inside a transformer reaches syntax_error_detail (#1846)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(define-syntax boom2
        \\  (er-macro-transformer (lambda (f r c) (car 7))))
    );
    const result = ctx.vm.eval("(boom2)");
    try std.testing.expectError(error.CompileError, result);
    try std.testing.expectEqualStrings("type error in 'car': expected pair, got 7", compiler.getSyntaxErrorDetail());
}

test "SRFI 211: syntax-rules NoMatchingPattern still has no detail (#1846 scope note)" {
    // TransformerFailed is the only ExpandError arm #1846 changes -- an
    // ordinary syntax-rules rejection has no VM-side condition to recover
    // (see the ExpandError.TransformerFailed doc comment in expander.zig)
    // and must keep reporting the generic InvalidSyntax message.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(define-syntax only-one-arg (syntax-rules () ((_ x) x)))
    );
    const result = ctx.vm.eval("(only-one-arg 1 2 3)");
    try std.testing.expectError(error.CompileError, result);
    try std.testing.expectEqual(@as(usize, 0), compiler.getSyntaxErrorDetail().len);
}

test "SRFI 211: a global transformer value works as a bare-symbol spec" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define tx-val (er-macro-transformer (lambda (f r c) (list (r 'quote) 'ok))))
        \\  (define-syntax via tx-val)
        \\  (eq? (via) 'ok))
    );
}

test "SRFI 213: define-property evaluates now and lookup reads it back" {
    try th.expectEval(
        \\(begin
        \\  (define pk 'the-key)
        \\  (define pv 40)
        \\  (define-property pv pk (+ 2 40))
        \\  (define-syntax getp
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (lambda (lookup)
        \\         (lookup (car (cdr form)) (car (cdr (cdr form))))))))
        \\  (getp pv pk))
    , 42);
}

test "SRFI 213: missing property is #f and the binding keeps its meaning" {
    try th.expectEvalTrue(
        \\(begin
        \\  (define qk 'k2)
        \\  (define qv 7)
        \\  (define-property qv qk 'present)
        \\  (define-syntax getp2
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (lambda (lookup)
        \\         (list (rename 'quote) (lookup (car (cdr form)) (car (cdr (cdr form)))))))))
        \\  (and (eq? (getp2 qv qk) 'present)
        \\       (eq? (getp2 qv missing) #f)
        \\       (= qv 7)))
    );
}

test "SRFI 213: define-property in a body scope is rejected" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = ctx.vm.eval(
        \\(define (f)
        \\  (define-property f f 1)
        \\  1)
    );
    try std.testing.expectError(error.CompileError, result);
}

// ---------------------------------------------------------------------------
// KEP-0006 step 1 exit criterion (#2390): the reentrant-VM-during-compile
// machinery must keep every live value rooted when collections fire around a
// procedural-transformer call.
//
// What these tests pin, precisely (mutation-tested in the PR #2399 review):
// the PRIMARY protection is the no-collect window compiler_macro.zig opens
// across expandMacro — a use-path transformer call defers collections, and
// the deferred storm then fires on the first allocation after the window
// closes. Bypassing that window (maybeCollect's no_collect guard forced
// off) makes all three tests below panic with "GC: marking freed object",
// so the window, and the overall invariant that no in-flight intermediate
// is left exposed while collections are live, are genuinely pinned.
//
// The individually-named explicit roots — the extra_roots append in
// compiler_macro.zig, the input-form pushRoot in
// expander.expandProceduralMacro (plus the rename/compare/lookup NativeFn
// roots across the SRFI 213 re-entry hops), and the expr_root push in
// vm.evalDatumForMacro — are defense-in-depth these tests corroborate but
// do NOT isolate: the same mutation testing showed that, with the window
// intact, removing all three at once still passes, because at the instant
// collections fire each value is also reachable through a redundant cover
// (the compile boundary's rooting of the source tree for the input/spec
// datums, and the allocators' argument auto-rooting as the expansion is
// handed from one allocating step to the next — not the VM register file,
// which markVmRoots only marks for live frames, all popped by then). A test
// that flips on any ONE of those roots alone would need the value provably
// unreachable from every such cover at the collection instant, which
// depends on compiler-internal allocation ordering and cannot be arranged
// from Scheme-level test code; keep the roots anyway — the covers are
// incidental to the current code shape, the roots are the contract.
//
// Without -Dgc-stress=true the allocation counts below exceed the
// 8192-object GC threshold, so real collections still fire mid-eval on the
// define-time path and immediately after each use-path window. Counts scale
// down under stress (collection-per-allocation) like
// tests_robustness.zig's loops.
// ---------------------------------------------------------------------------

/// Allocations per transformer-body loop: each iteration conses a pair and
/// builds a fresh string, so `churn_n` iterations comfortably exceed the
/// default 8192-object collection threshold in normal builds.
const churn_n: i64 = if (@import("build_options").gc_stress) 300 else 10000;

test "SRFI 211 gc-stress: heavily-allocating er transformer keeps input form and expansion rooted (#2390)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // The transformer conses up a churn_n-element list of fresh strings,
    // then — only AFTER the allocation storm — re-reads the use-site form
    // (both literal args), splices the raw `(+ 1 2)` subform into the
    // expansion for the compiler to compile afterwards, and embeds the
    // freshly-built list itself as quoted literal data. If the input AST or
    // any freshly-expanded material were unrooted, the storm (or the
    // deferred collections that fire right after the no-collect window
    // closes, while the compiler is still walking the expansion) would free
    // it — a gc-stress build panics on the dangling reference rather than
    // returning the checked value.
    var buf: [768]u8 = undefined;
    const def_src = try std.fmt.bufPrint(&buf,
        \\(define-syntax churn
        \\  (er-macro-transformer
        \\   (lambda (form rename compare)
        \\     (let loop ((i 0) (acc '()))
        \\       (if (< i {d})
        \\           (loop (+ i 1) (cons (number->string i) acc))
        \\           (list (rename '+)
        \\                 (length acc)
        \\                 (car (cdr form))
        \\                 (car (cdr (cdr form)))
        \\                 (list (rename 'length)
        \\                       (list (rename 'quote) acc))))))))
    , .{churn_n});
    _ = try ctx.vm.eval(def_src);
    // Expansion: (+ churn_n 4 (+ 1 2) (length '(<churn_n strings>))).
    const result = try ctx.vm.eval("(churn 4 (+ 1 2))");
    try std.testing.expectEqual(churn_n + 4 + 3 + churn_n, types.toFixnum(result));
    // Reentrancy survival, not a one-shot fluke: the same transformer must
    // expand again after the deferred collection storm from the first use.
    const again = try ctx.vm.eval("(churn 5 (+ 2 3))");
    try std.testing.expectEqual(churn_n + 5 + 5 + churn_n, types.toFixnum(again));
}

test "SRFI 211 gc-stress: transformer-spec eval allocating heavily at define time stays rooted (#2390)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // The define-time path (vm.evalDatumForMacro) runs with collections
    // LIVE — no no-collect window. The spec expression builds a
    // churn_n-element list before producing the transformer procedure, so
    // collections fire mid-eval; the returned closure captures that list,
    // and the use site reads it back through transformer.proc's GC trace.
    var buf: [512]u8 = undefined;
    const def_src = try std.fmt.bufPrint(&buf,
        \\(define-syntax dtime
        \\  (er-macro-transformer
        \\   (let loop ((i 0) (acc '()))
        \\     (if (< i {d})
        \\         (loop (+ i 1) (cons (number->string i) acc))
        \\         (lambda (form rename compare)
        \\           (list (rename 'quote) (length acc)))))))
    , .{churn_n});
    _ = try ctx.vm.eval(def_src);
    const result = try ctx.vm.eval("(dtime)");
    try std.testing.expectEqual(churn_n, types.toFixnum(result));
}

test "SRFI 213 gc-stress: allocation across the lookup re-entry hop keeps form and lookup rooted (#2390)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // The procedure-result re-entry protocol calls the transformer's result
    // again with the property-lookup NativeFn. Both hops allocate a storm;
    // the second hop then re-reads the ORIGINAL use-site form (captured
    // across the first hop's allocations) and consults the SRFI 213
    // property table through `lookup`. This exercises the
    // res_root/lookup_root rooting in expandProceduralMacro's hop loop plus
    // the input_root that must span every hop.
    var buf: [768]u8 = undefined;
    const def_src = try std.fmt.bufPrint(&buf,
        \\(begin
        \\  (define hop-key 'hk)
        \\  (define hop-var 5)
        \\  (define-property hop-var hop-key 17)
        \\  (define-syntax hop
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (let loop ((i 0) (acc '()))
        \\         (if (< i {d})
        \\             (loop (+ i 1) (cons (number->string i) acc))
        \\             (lambda (lookup)
        \\               (let loop2 ((j 0) (acc2 '()))
        \\                 (if (< j {d})
        \\                     (loop2 (+ j 1) (cons (number->string j) acc2))
        \\                     (list (rename '+)
        \\                           (length acc)
        \\                           (length acc2)
        \\                           (lookup (car (cdr form))
        \\                                   (car (cdr (cdr form))))))))))))))
    , .{ churn_n, churn_n });
    _ = try ctx.vm.eval(def_src);
    const result = try ctx.vm.eval("(hop hop-var hop-key)");
    try std.testing.expectEqual(churn_n + churn_n + 17, types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// #2403: rename on a circular datum. R7RS datum labels put genuine cycles
// in macro-use inputs; erRenameDatum used to walk them with unbounded
// recursion, pushing two roots per level until the GC root stack panicked
// — uncatchable, process gone. The regression contract pinned here:
// rejection as a normal (guard-able, diagnosed) syntax error, exact cycle
// detection (shared-but-acyclic data still renames), and the pre-scan
// guards that let the diagnosis reach the user instead of a hang.
// ---------------------------------------------------------------------------

test "#2403: rename on a circular macro-use datum is a diagnosed error, not an abort" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    // The five-line repro from the issue.
    const result = ctx.vm.eval(
        \\(begin
        \\  (define-syntax m
        \\    (er-macro-transformer
        \\     (lambda (form rename compare) (rename (car (cdr form))))))
        \\  (m #0=(zz . #0#)))
    );
    try std.testing.expectError(error.CompileError, result);
    try std.testing.expect(std.mem.indexOf(u8, ctx.vm.getErrorDetail(), "circular") != null);
}

test "#2403: rename cycle rejection covers car-edge and vector cycles" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval(
        \\(define-syntax d
        \\  (er-macro-transformer
        \\   (lambda (form rename compare) (rename (car (cdr form))))))
    );
    // A cycle through the car of the renamed datum (spine guard alone
    // cannot see this shape) and a self-referential vector.
    try std.testing.expectError(error.CompileError, ctx.vm.eval("(d #1=(p #1# q))"));
    try std.testing.expect(std.mem.indexOf(u8, ctx.vm.getErrorDetail(), "circular") != null);
    try std.testing.expectError(error.CompileError, ctx.vm.eval("(d #0=#(1 #0#))"));
    try std.testing.expect(std.mem.indexOf(u8, ctx.vm.getErrorDetail(), "circular") != null);
}

test "#2403: a transformer's guard catches the circular-datum rejection" {
    // The whole point of rejecting through the normal error channel: the
    // transformer can intercept it and recover, which no uncatchable
    // root-stack panic ever allowed.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax g
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (guard (e (#t (list (rename 'quote) 'caught)))
        \\         (rename (car (cdr form)))))))
        \\  (eq? 'caught (g #0=(zz . #0#))))
    );
}

test "#2403: shared-but-acyclic datum still renames (no false cycle)" {
    // `#1=` reuse is sharing, not a cycle: the same sub-datum appears twice
    // but the walk never revisits a node on its own path. Renaming it must
    // succeed — only a back-edge may be rejected.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax s
        \\    (er-macro-transformer
        \\     (lambda (form rename compare)
        \\       (list (rename 'quote) (rename (car (cdr form)))))))
        \\  ((lambda (x) (and (= 2 (length x))
        \\                     (pair? (car x))
        \\                     (pair? (car (cdr x)))))
        \\   (s (#1=(b c) #1#))))
    );
}
