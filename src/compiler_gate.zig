//! Redefinition-awareness for the compiler (kaappi#2033, #2457, #1775).
//!
//! Two cooperating pieces live here because they answer the same question —
//! "can a compile-time decision that a name still resolves to its built-in
//! survive until the code runs?" — for two different redefinition routes:
//!
//!   * the builtin-bypass gate `globalBindingStillGenuine`, which decides the
//!     `apply` / `call-with-values` / `call/cc` / `eval` superinstructions in
//!     `compiler.zig` and the native tier's `emitApplyForm`, consuming both
//!     the per-form `set!` pre-scan below and the whole-unit target set a
//!     whole-unit driver installs (`compiler_passthrough.unit_top_level_targets`);
//!   * the `set!` pre-scan (`collectSetTargets` and its budget), which
//!     discovers the names a form (or a macro it uses) assigns before the
//!     form compiles, feeding `Compiler.set_targets` and the LLVM backend's
//!     `scanSetTargetsWithoutMacros`.
//!
//! Split out of compiler.zig along this seam (file-size policy, PR #2467
//! review): every decl here is about names that may change under a
//! compile-time binding read, none about emitting bytecode.

const std = @import("std");
const types = @import("types.zig");
const expander = @import("expander.zig");
const macro = @import("compiler_macro.zig");
const globals_mod = @import("globals.zig");
const compiler_mod = @import("compiler.zig");
const passthrough = @import("compiler_passthrough.zig");

const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;

/// Answers whether a free global reference spelled `sym_name` (a bare
/// name like `apply`, or a hygiene-renamed `__hyg_N_apply`) would still
/// resolve to the genuine `(scheme base)` primitive `base_name` at run
/// time — the gate the builtin superinstructions
/// (apply/call-with-values in any position, eval/call/cc in tail
/// position) need so a top-level
/// redefinition of one of those names routes to the user's procedure
/// instead of the baked-in builtin (kaappi#2033). Mirrors
/// IR.isRedefined's fold gate and the resolution order of
/// vm_dispatch_helpers.lookupGlobalLocked so the compile-time decision
/// cannot disagree with what get_global would fetch.
pub fn globalBindingStillGenuine(self: *const Compiler, sym_name: []const u8, base_name: []const u8) bool {
    // A `set!` target in the enclosing top-level form (or a truncated
    // pre-scan) means the global may hold a different value by the time
    // the call executes — the same conservative bias as IR.isRedefined.
    if (self.set_targets_all) return false;
    if (self.set_targets) |st| {
        if (st.contains(sym_name) or st.contains(base_name)) return false;
    }
    // A top-level `define`/`set!` of the name ANYWHERE in the compilation
    // unit (kaappi#2457): a body compiled before the definition runs
    // would otherwise bake the builtin in and silently discard the user's
    // procedure, because this function's compile-time read of the global
    // environment still sees the pristine binding. Whole-unit drivers
    // populate the set; per-form entry points (REPL, eval) leave it null
    // and keep the legacy answer. Declining only ever costs the
    // superinstruction — the by-name call resolves the genuine binding
    // when no redefinition intervenes.
    if (passthrough.unit_top_level_targets) |unit_targets| {
        if (unit_targets.contains(sym_name) or unit_targets.contains(base_name)) return false;
    }

    // No environment info (standalone/unit-test paths): keep the legacy
    // optimistic behavior, mirroring IR.isRedefined's `orelse return false`.
    const g = self.globals orelse return true;
    const glk = globals_mod.acquireGlobalsRead(g);
    defer globals_mod.releaseGlobalsRead(glk);

    // Mirror lookupGlobalLocked's resolution: the name as spelled, then
    // the hygienic-prefix fallback to the bare name.
    var val: ?Value = g.get(sym_name);
    if (val == null and !std.mem.eql(u8, sym_name, base_name)) {
        val = g.get(base_name);
    }
    const v = val orelse {
        // Not bound in the compile-time env. Inside a library (partial
        // lib_env) or restricted environment the runtime may still find
        // it elsewhere — the vm.globals fallback for a library body,
        // nowhere at all for a restricted env — so decline the fast path
        // rather than silently run the builtin for a name the program
        // never bound (mirrors IR.isRedefined's restricted_env arm). At
        // top level the name being absent is the legacy unbound case,
        // which keeps the fast path exactly as before.
        return !self.restricted_env;
    };
    if (!types.isPointer(v)) return false;
    const obj = types.toObject(v);
    if (obj.tag != .native_fn) return false;
    const nfn = obj.as(types.NativeFn);
    return std.mem.eql(u8, nfn.name, base_name);
}

/// Work limit for one top-level `set!` pre-scan (kaappi#1775).
///
/// The pre-scan expands macros so it can see a `set!` a template introduces
/// (#1250). That makes it a speculative *evaluator* of compile-time macro
/// code, and it explores branches the real compiler never takes: at
/// `(m kt kf)`, where `m` is a helper the enclosing expansion defined with
/// `define-syntax`, the scan has no binding for `m`, so it treats `kt` and
/// `kf` as ordinary sub-forms and expands macros inside *both*. The real
/// compiler registers `m`, expands it, and follows exactly one. Every such
/// fork doubles the work, so macros that generate macros — SRFI 148's
/// `em-syntax-rules`, SRFI 257's CK-machine combinators — cost time
/// exponential in the number of forks.
///
/// Exceeding the limit is safe by construction: the scan sets `truncated`,
/// and Compiler.set_targets_all makes both consumers assume every name is a
/// `set!` target. A truncated scan therefore loses optimization, never
/// correctness.
///
/// 4096 is ~2.5x the highest count any non-pathological top-level form in
/// this repo's Scheme suites reaches (p99.99 = 1649 expansions; 87% of forms
/// need none at all) and well under the 6299+ the macro-generating cases
/// start at. That headroom matters: a truncated scan boxes every local in the
/// form, measured at ~2x runtime on compute-heavy code, so ordinary programs
/// must never reach the limit.
///
/// A `var` only so tests can lower it and exercise the truncation path
/// without a multi-second pathological program; nothing in the compiler
/// writes it. Threadlocal for the same reason as `ir.optimize_enabled`: an
/// SRFI-18 child thread compiling concurrently keeps the default rather than
/// racing on whatever a test left in a shared global.
pub threadlocal var prescan_expansion_limit: u32 = 4096;

/// Number of top-level forms whose `set!` pre-scan truncated. Diagnostic
/// only — read by tests to assert the guard did (or did not) engage.
pub threadlocal var prescan_truncations: u64 = 0;

pub const SetScanBudget = struct {
    expansions_left: u32,
    /// False for structure-only scans (Part B, the native backend): walk
    /// and report truncation like any budgeted scan, but never speculatively
    /// expand macros — expansion is the top-level pre-scan's job. With this
    /// flag, a non-null budget no longer implies "expanding scan", so the
    /// old null-vs-non-null distinction collapses to expand-vs-not and the
    /// depth/spine caps report truncation on every caller (#2401 review:
    /// a partial target set from a silently-truncated scan could leave a
    /// `set!`-ed local unboxed and foldable).
    expand: bool = true,
    /// Set when the scan stopped early (budget exhausted or a cap hit),
    /// meaning `out` is an under-approximation of the real target set.
    truncated: bool = false,
};

/// Step cap on the let-syntax/letrec-syntax BINDINGS loop inside
/// collectSetTargets (#2404) — the one cdr-spine the main walk's
/// tortoise-and-hare guard below does not cover. A datum-label cycle
/// (`#0=(let-syntax #1=(#1#) body)`, R7RS §7.1.2) makes that inner spine
/// infinite; exhausting the cap marks the scan truncated — the same
/// loses-optimization-never-correctness degradation the expansion budget
/// takes. One million steps is far beyond any real form (the whole repo's
/// suites stay under ~1.7k expansions per top-level form). Every caller
/// propagates truncation: the pre-scan via set_targets_all, Part B via
/// scanSetTargets, the native backend by eval-falling-back the form. The
/// define-syntax/let-syntax spec walks still pass a structure-only budget
/// with no propagation: a `set!` that only materializes when the spec's
/// own macros run is caught at the macro's real use site, the same
/// correct-late path as before.
const SET_SCAN_SPINE_CAP: usize = 1_000_000;

/// Recursively collect the symbol names that appear as the target of a
/// `(set! <name> ...)` anywhere in `expr` into `out`. Used to suppress
/// constant folding of those names within the enclosing form (see
/// Compiler.set_targets) and to box locals for correct continuation
/// semantics (R7RS §3.4). Conservative: it scans every sub-form except
/// the interior of `quote`d data. When `budget` is non-null and a known
/// macro is encountered, it is expanded and the expansion is scanned
/// (#1250). Only the top-level pre-scan expands; the per-expansion Part B
/// scan passes null (see scanSetTargets).
///
/// `self` is needed only to expand macros, i.e. only when `budget` is
/// non-null — a null `budget` makes the whole walk a pure function of `expr`,
/// which is what `scanSetTargetsWithoutMacros` below exposes to the LLVM
/// native backend (it has no Compiler at all).
pub fn collectSetTargets(self: ?*Compiler, expr: Value, out: *std.StringHashMap(void), depth: u16, budget: ?*SetScanBudget) CompileError!void {
    // This is the scan's *own* recursion cap, deliberately not shared with
    // compiler_macro.MAX_MACRO_EXPANSION_DEPTH despite both being 256: they
    // count different things. That one bounds the real expansion of code that
    // will be compiled, and exceeding it is a user-visible error (KP2003).
    // This one bounds a speculative walk that also descends into branches the
    // compiler discards, so it is reached by programs whose real expansion
    // depth never comes close — measured: every SRFI 257 suite trips this cap
    // several times per run while compiling and passing normally. Tying the
    // two together would assert an equivalence the measurements contradict.
    if (depth > 256) {
        if (budget) |b| b.truncated = true;
        return;
    }
    // #2403: the spine walk must terminate on circular data — R7RS datum
    // labels can put a genuine cycle in code position. Every body path
    // that resumes iteration does so via the continue expression, which
    // advances exactly one cdr, so Floyd's tortoise-and-hare is exact: a
    // tortoise advancing every other step can only re-meet `cur` on a
    // real cycle, and an acyclic spine costs just one extra cdr per
    // element. On detection the scan stops early exactly as the depth cap
    // does — an under-approximation the truncated flag already models.
    var cur = expr;
    var tortoise = expr;
    var step: usize = 0;
    while (types.isPair(cur)) : ({
        cur = types.cdr(cur);
        step += 1;
        if (step % 2 == 0) tortoise = types.cdr(tortoise);
    }) {
        if (step > 0 and cur == tortoise) {
            if (budget) |b| b.truncated = true;
            return;
        }
        const head = types.car(cur);
        if (types.isSymbol(head)) {
            const hname = types.stripHygienicPrefix(types.symbolName(head));
            if (std.mem.eql(u8, hname, "quote")) return; // literal data, not code
            if (std.mem.eql(u8, hname, "set!")) {
                const rest = types.cdr(cur);
                if (types.isPair(rest)) {
                    const target = types.car(rest);
                    if (types.isSymbol(target)) {
                        out.put(types.symbolName(target), {}) catch return CompileError.OutOfMemory;
                    }
                }
            } else if (budget) |b| {
                // Only an expanding scan looks macros up, and only an
                // expanding scan is ever handed a Compiler — so `self.?`
                // below is reached only when `maybe_macro` was non-null,
                // which requires one. Structure-only scans (b.expand ==
                // false) never take this branch and keep walking the form
                // literally.
                const maybe_macro = if (b.expand) blk: {
                    const c = self orelse break :blk null;
                    break :blk c.lookupMacro(types.symbolName(head));
                } else null;
                if (maybe_macro) |transformer| {
                    if (b.expansions_left == 0) {
                        b.truncated = true;
                        return;
                    }
                    b.expansions_left -= 1;
                    const c = self.?;
                    // Best-effort expansion: uses an empty UseSiteBindingCheck
                    // (no locals exist at pre-scan time), so patterns with
                    // literals may diverge from the real expansion.  Part B
                    // (scanSetTargets in expandAndCompileMacroUse) corrects
                    // any misses at real-expansion time.
                    c.gc.no_collect += 1;
                    const expanded = expander.expandMacro(
                        c.gc,
                        cur,
                        transformer,
                        c.globals,
                        &c.macros,
                        .{},
                    ) catch {
                        c.gc.no_collect -= 1;
                        continue;
                    };
                    var expanded_root = expanded;
                    c.gc.pushRoot(&expanded_root);
                    defer c.gc.popRoot();
                    c.gc.no_collect -= 1;
                    // Fixed point (e.g. SRFI 219 rule 3: (define x e) →
                    // (define x e)): the expansion is the input, so scanning
                    // it again can only repeat what this pass already did.
                    // expandAndCompileMacroUse detects the same case to hand
                    // the form to its built-in handler; here it just stops the
                    // scan from re-expanding until the depth cap (kaappi#1775).
                    // Fall through to the sub-form walk below, which is what
                    // compiling the built-in form will visit anyway.
                    if (macro.valuesStructurallyEqual(expanded_root, cur, 128)) {
                        continue;
                    }
                    try collectSetTargets(self, expanded_root, out, depth + 1, budget);
                    return;
                } else if (std.mem.eql(u8, hname, "define-syntax")) {
                    // (define-syntax name <transformer-spec>): the spec is
                    // compile-time data — it resolves to a transformer object
                    // and never contributes a runtime `set!` to THIS form —
                    // so walk it for literal `set!`s in templates but never
                    // macro-expand inside it. Speculatively running a
                    // SRFI 147 spec like SRFI 148's `(em-syntax-rules ...)`
                    // drove the whole CK machine per definition, burning the
                    // entire budget (and with it set_targets_all boxing) on
                    // forms with no runtime code at all (kaappi#1802). A
                    // `set!` that only materializes when the spec's own
                    // macros run is caught at the macro's real use site —
                    // its own form's pre-scan, or Part B — the same
                    // correct-late path every divergent best-effort
                    // expansion above already takes.
                    const rest = types.cdr(cur);
                    if (types.isPair(rest)) {
                        // Skip the macro name; walk the spec without a budget.
                        try collectSetTargets(self, types.cdr(rest), out, depth + 1, null);
                    }
                    return;
                } else if (std.mem.eql(u8, hname, "let-syntax") or
                    std.mem.eql(u8, hname, "letrec-syntax"))
                {
                    // ((name <transformer-spec>) ...) bindings are compile-time
                    // data like define-syntax specs; the body is real code and
                    // keeps the budgeted scan. Walk each spec individually,
                    // skipping the binding NAME, so a binding pair is never
                    // misread as a form: a macro bound under a special-form
                    // name (R7RS lets a binding shadow `quote`, `set!`, ...)
                    // would otherwise derail the walk — a binding literally
                    // named `quote` early-returns before its own spec is
                    // scanned. Verified unobservable end-to-end today (the
                    // let-syntax body compiles via passthrough, where the
                    // folder doesn't engage, and a late-discovered target is
                    // still boxed via the box_local transition — pinned by
                    // tests/scheme/hygiene/quote-shadow-boxing.scm), so this
                    // is scan hygiene, not a bug fix.
                    const rest = types.cdr(cur);
                    if (!types.isPair(rest)) return;
                    var bindings_cur = types.car(rest);
                    var binding_steps: usize = 0;
                    while (types.isPair(bindings_cur)) {
                        binding_steps += 1;
                        if (binding_steps > SET_SCAN_SPINE_CAP) {
                            budget.?.truncated = true;
                            return;
                        }
                        const binding = types.car(bindings_cur);
                        if (types.isPair(binding)) {
                            try collectSetTargets(self, types.cdr(binding), out, depth + 1, null);
                        }
                        bindings_cur = types.cdr(bindings_cur);
                    }
                    // The body keeps the budgeted scan. A sub-walk, not the
                    // old two-cdr jump (`cur = cdr(rest); continue`): the
                    // tortoise-and-hare spine guard above is exact only when
                    // every iteration advances exactly one cdr, and a cycle
                    // through the body (`#0=(let-syntax () . #0#)`) must hit
                    // the depth cap as recursion, not loop forever (#2403).
                    try collectSetTargets(self, types.cdr(rest), out, depth + 1, budget);
                    return;
                }
            }
        }
        // depth+1, not depth: a sub-form is nesting like any other, and the
        // same-depth recursion this used to make was unbounded — reader-cap
        // fine for acyclic data, infinite on a car-side cycle
        // (`(display #1=(p #1# q))`), which the spine guard above cannot
        // see (#2403). The scan's depth cap now bounds it, at the same
        // conservative-truncation cost the cap already charges elsewhere.
        try collectSetTargets(self, head, out, depth + 1, budget);
    }
}

/// The `set!`-target scan for callers with no Compiler — the LLVM native
/// backend, which re-lowers each lambda/let body through a scratch IR and
/// needs the same suppression set the interpreter's per-form pre-scan builds
/// (#2117). Macros are not expanded, since that needs a Compiler.
///
/// For the body case that limit costs nothing: the backend declines native
/// compilation of any body containing a macro use (`sexprHasMacroUse`,
/// #1807), so a `set!` only a macro would reveal is in a body the
/// interpreter — and its macro-expanding pre-scan — has already taken over.
///
/// At *top level across forms* the same is NOT true, and this scan does not
/// close that: a macro use in form N that expands to `(set! + -)` leaves `+`
/// unrecorded, so form N+1 can still fold it. That is kaappi#2212 — the
/// pre-existing macro-blindness of #822's `collectRedefinedNames`, which this
/// scan runs alongside rather than replaces. The interpreter is immune for an
/// unrelated reason (it has already *executed* form N, so the globals check in
/// isRedefined sees the rebound value), which is why only the compiled tier
/// diverges.
/// Returns true when the scan truncated (depth cap, spine cap, or — never,
/// for this structure-only caller — expansion budget): `out` is then a
/// partial answer, and the caller must not trust it to gate folding or
/// boxing (the LLVM backend's conservative action is to eval-fallback the
/// whole form; see native_compiler).
pub fn scanSetTargetsWithoutMacros(expr: Value, out: *std.StringHashMap(void)) CompileError!bool {
    var b = SetScanBudget{ .expansions_left = 0, .expand = false };
    try collectSetTargets(null, expr, out, 0, &b);
    return b.truncated;
}
