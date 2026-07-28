// Regressions for the top-level `set!` pre-scan (compiler.collectSetTargets)
// and its work limit (kaappi#1775).
//
// The pre-scan expands macros so it can see a `set!` a macro template
// introduces, which is what makes #1250's macro-introduced-set! cases box
// correctly. That makes it a speculative evaluator of compile-time macro
// code, and it can explore exponentially many branches the real compiler
// never takes. It is therefore bounded (compiler.prescan_expansion_limit),
// and hitting the bound must fall back to "assume every name is a `set!`
// target" rather than silently returning a partial answer — the tests here
// pin both halves of that contract.
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const compiler = @import("compiler.zig");

/// Evaluate `body` with the pre-scan limit lowered, assert it yields
/// `expected`, and report how many top-level forms truncated meanwhile.
/// The limit is restored even on failure. The result is checked here rather
/// than returned because the VM (and any heap value it produced) is gone
/// once this returns.
fn evalWithPrescanLimit(limit: u32, expected: i64, body: []const u8) !u64 {
    const saved = compiler.prescan_expansion_limit;
    defer compiler.prescan_expansion_limit = saved;
    compiler.prescan_expansion_limit = limit;

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const before = compiler.prescan_truncations;
    const value = try ctx.vm.eval(body);
    try std.testing.expectEqual(expected, types.toFixnum(value));
    return compiler.prescan_truncations - before;
}

test "#1775: a truncated set! pre-scan still boxes a macro-introduced set! target" {
    // #1250's shape: `inc!` introduces the `set!`, and a continuation
    // captured before it re-enters the `let`. `n` must be boxed, or the
    // register snapshot rolls the mutation back on every resume and the loop
    // never terminates (#1168).
    //
    // With the limit at 0 the pre-scan cannot expand `inc!`, so it never sees
    // that `set!` at all. The only thing that keeps this correct is the
    // truncation fallback marking *every* name a target. Before #1775 the
    // scan just stopped and returned what it had, so an over-budget form
    // silently reintroduced the #1250 bug.
    const truncations = try evalWithPrescanLimit(0, 3,
        \\(begin
        \\  (define-syntax inc! (syntax-rules () ((_ v) (set! v (+ v 1)))))
        \\  (let ((n 0) (k* #f))
        \\    (call/cc (lambda (k) (set! k* k)))
        \\    (inc! n)
        \\    (if (< n 3) (k* #f))
        \\    n))
    );
    // The test is only meaningful if the guard actually engaged.
    try std.testing.expect(truncations > 0);
}

test "#1775: truncated pre-scan boxes a lambda parameter that a macro set!s" {
    // Same contract for a parameter rather than a `let` binding — a separate
    // boxing path (boxIfSetTarget is called per binding site).
    const truncations = try evalWithPrescanLimit(0, 3,
        \\(begin
        \\  (define-syntax inc! (syntax-rules () ((_ v) (set! v (+ v 1)))))
        \\  ((lambda (n)
        \\     (let ((k* #f))
        \\       (call/cc (lambda (k) (set! k* k)))
        \\       (inc! n)
        \\       (if (< n 3) (k* #f))
        \\       n))
        \\   0))
    );
    try std.testing.expect(truncations > 0);
}

test "#1775: truncated pre-scan suppresses constant folding of a set! primitive" {
    // The other consumer of set_targets: folding `(+ 5 2)` to 7 is unsound
    // once `+` has been reassigned before the call runs. A truncated scan has
    // no list of reassigned names, so it must suppress every fold.
    //
    // `f` is compiled — and its body folded or not — before `rebind` is ever
    // expanded, so Part B (scanSetTargets, which records the target when the
    // macro is really expanded) is too late here. Only the pre-scan can catch
    // it, and at limit 0 only its truncation fallback can.
    const truncations = try evalWithPrescanLimit(0, 3,
        \\(begin
        \\  (define-syntax rebind (syntax-rules () ((_ a b) (set! a b))))
        \\  ((lambda ()
        \\     (define (f) (+ 5 2))
        \\     (rebind + -)
        \\     (f))))
    );
    try std.testing.expect(truncations > 0);
}

test "#1775: a fixed-point macro does not exhaust the pre-scan budget" {
    // SRFI 219 rule 3 is `(define name expr)` → `(define name expr)`: the
    // expansion IS the input. expandAndCompileMacroUse detects that and hands
    // the form to the built-in `define`; the pre-scan did not, so it
    // re-expanded the same form until the 256-level depth cap — 257 wasted
    // expansions for every plain `define` in a program importing SRFI 219,
    // and (once truncation became meaningful) a spurious fall back to boxing
    // everything.
    //
    // The macro must shadow `define` itself, exactly as SRFI 219 does: the
    // fixed point only terminates because the keyword is also a built-in
    // special form, which is what expandAndCompileMacroUse falls back to. A
    // fixed point on any other name is a diverging macro the expansion-step
    // limit rejects outright.
    //
    // A budget of 8 is far below the depth cap, so without the fixed-point
    // check this truncates; with it, one expansion settles the form.
    const truncations = try evalWithPrescanLimit(8, 42,
        \\(begin
        \\  (define-syntax define
        \\    (syntax-rules ()
        \\      ((define ((name . outer) . args) . body)
        \\       (define (name . outer) (lambda args . body)))
        \\      ((define (name . args) . body)
        \\       (define name (lambda args . body)))
        \\      ((define name expr)
        \\       (define name expr))))
        \\  (define answer 42)
        \\  answer)
    );
    try std.testing.expectEqual(@as(u64, 0), truncations);
}

test "#1802: a macro use in transformer-spec position does not consume the pre-scan budget" {
    // SRFI 147/148 shape: the transformer spec is itself a macro use that
    // resolveTransformerSpec expands to a literal syntax-rules at real
    // compile time. The pre-scan used to treat the spec as ordinary code and
    // speculatively expand it too — for SRFI 148's `em-syntax-rules` that ran
    // the whole CK machine once per *definition*, burning the entire budget
    // (and, via truncation, boxing every local) on forms with no runtime
    // code at all (kaappi#1802). A spec never contributes a runtime `set!`
    // to its own form, so the scan must walk it without expanding.
    //
    // With the limit at 0, ANY spec expansion truncates, so this fails
    // without the fix.
    const saved = compiler.prescan_expansion_limit;
    defer compiler.prescan_expansion_limit = saved;

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // Defined at the default limit; its own spec is a literal syntax-rules.
    _ = try ctx.vm.eval(
        \\(define-syntax gen (syntax-rules () ((_) (syntax-rules () ((_ x) x)))))
    );

    compiler.prescan_expansion_limit = 0;
    const before = compiler.prescan_truncations;
    _ = try ctx.vm.eval("(define-syntax my-id (gen))");
    try std.testing.expectEqual(@as(u64, 0), compiler.prescan_truncations - before);
    compiler.prescan_expansion_limit = saved;

    // The real SRFI 147 resolution must be unaffected by the pre-scan skip.
    const result = try ctx.vm.eval("(my-id 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "#1802: let-syntax specs are skipped but the body keeps the budgeted scan" {
    // Three failure modes distinguished by one form, compiled with a budget
    // of exactly 1:
    //   - spec still consumes budget (no fix): `(gen)` eats the single
    //     expansion, `rebind` then truncates the scan => truncations 1.
    //   - body wrongly walked without the budget (over-broad fix): `rebind`
    //     is never expanded, `+` never enters set_targets, `(+ 5 2)` folds
    //     to 7 before the reassignment runs => result 7.
    //   - correct: the one expansion goes to the body's `rebind`, `+` is a
    //     known target, the fold is suppressed => result 3, truncations 0.
    const saved = compiler.prescan_expansion_limit;
    defer compiler.prescan_expansion_limit = saved;

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval(
        \\(define-syntax gen (syntax-rules () ((_) (syntax-rules () ((_ x) x)))))
    );
    _ = try ctx.vm.eval(
        \\(define-syntax rebind (syntax-rules () ((_ a b) (set! a b))))
    );

    compiler.prescan_expansion_limit = 1;
    const before = compiler.prescan_truncations;
    const result = try ctx.vm.eval(
        \\(let-syntax ((local-id (gen)))
        \\  (define (f) (+ 5 2))
        \\  (rebind + -)
        \\  (local-id (f)))
    );
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
    try std.testing.expectEqual(@as(u64, 0), compiler.prescan_truncations - before);
}

test "#1775: ordinary code does not trigger the pre-scan fallback" {
    // The default limit must leave normal programs alone: truncation costs
    // ~2x runtime (every local boxed, nothing folded), so it has to stay a
    // pathological-input backstop, not something ordinary macro use reaches.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const before = compiler.prescan_truncations;
    const result = try ctx.vm.eval(
        \\(begin
        \\  (define-syntax swap!
        \\    (syntax-rules () ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
        \\  (define-syntax twice (syntax-rules () ((_ e) (begin e e))))
        \\  (let ((x 1) (y 2))
        \\    (twice (swap! x y))
        \\    (+ (* 10 x) y)))
    );
    try std.testing.expectEqual(@as(i64, 12), types.toFixnum(result));
    try std.testing.expectEqual(@as(u64, 0), compiler.prescan_truncations - before);
}
