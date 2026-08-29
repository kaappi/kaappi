const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const expander = @import("expander.zig");
const globals_mod = @import("globals.zig");
const ir_mod = @import("ir.zig");
const check_lint = @import("check_lint.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;

pub const MAX_MACRO_EXPANSION_DEPTH: u16 = 256;
const MAX_MACRO_EXPANSION_STEPS: u32 = 10_000;

/// #1846: a procedural macro transformer (SRFI 211 er-macro-transformer /
/// lisp-transformer) raised, returned a non-datum, or could not run.
/// globals_mod.error_detail_for_macro carries the real Scheme-level condition
/// when there is one (populated by vm.callProcForMacro for a raised exception,
/// or directly by a failing primitive's own type-error call) -- copy it into
/// the same syntax_error_detail channel `syntax-error` already reports
/// through, so the top-level reporter and `kaappi check` show the real
/// message instead of a bare "invalid syntax". Left empty (InvalidSyntax's
/// generic message applies, exactly as before) when there is no VM-side
/// detail -- e.g. no VM registered, or a transformer that returned a bare
/// procedure with nothing left to SRFI 213 capture-lookup.
pub fn recordTransformerFailure() CompileError {
    if (globals_mod.error_detail_for_macro) |getter| {
        const detail = getter();
        if (detail.len > 0) {
            const n = @min(detail.len, compiler_mod.syntax_error_detail.len);
            @memcpy(compiler_mod.syntax_error_detail[0..n], detail[0..n]);
            compiler_mod.syntax_error_detail_len = n;
        }
    }
    return CompileError.InvalidSyntax;
}

/// 128 levels is safe because the expander shares pattern-variable subtrees
/// (a == b short-circuits at the shared node), so only the short template
/// spine is actually traversed.
pub fn valuesStructurallyEqual(a: Value, b: Value, depth: u16) bool {
    if (a == b) return true;
    if (depth == 0) return false;
    if (types.isPair(a) and types.isPair(b))
        return valuesStructurallyEqual(types.car(a), types.car(b), depth - 1) and
            valuesStructurallyEqual(types.cdr(a), types.cdr(b), depth - 1);
    return false;
}

pub fn resolveLocalSkipAliases(ctx: ?*const anyopaque, name: []const u8) u32 {
    const self: *const Compiler = @ptrCast(@alignCast(ctx.?));
    var comp: ?*const Compiler = self;
    while (comp) |c| {
        var i: usize = c.locals.items.len;
        while (i > 0) {
            i -= 1;
            const local = c.locals.items[i];
            if (!local.is_global_alias and std.mem.eql(u8, local.name, name)) return local.binding_id;
        }
        comp = c.parent;
    }
    return expander.LITERAL_UNBOUND;
}

/// Is `name` a local of the compiler's CURRENT frame (this function's
/// register file, not an enclosing lambda's)? Same-frame names keep the
/// rename + captured-locals slot-alias path, which is shadow-proof; only
/// cross-frame definition-site locals are kept unrenamed by the expander.
pub fn resolveSameFrameLocal(ctx: ?*const anyopaque, name: []const u8) bool {
    const self: *const Compiler = @ptrCast(@alignCast(ctx.?));
    for (self.locals.items) |local| {
        if (!local.is_global_alias and std.mem.eql(u8, local.name, name)) return true;
    }
    return false;
}

/// Undo record for one temporarily adjusted global (the hygiene "dance"
/// below); restored LIFO when the expansion chain finishes.
const TempGlobal = struct { name: []const u8, old_val: ?Value, was_present: bool };

/// Undo record for one let-syntax sibling keyword swapped to its outer
/// value (R7RS 4.3.1); restored LIFO when the expansion chain finishes.
const PeerSave = struct { name: []const u8, old: ?Value };

/// Does `form`'s head name a macro that compileForm would expand right
/// back through expandAndCompileMacroUse, in the same position (same dst,
/// same tail flag)? Mirrors compileForm's own macro-dispatch conditions
/// exactly: the usertext-marker safety net, local/upvalue shadowing, and
/// fixed-point suppression (a suppressed name must fall through to
/// compileForm, which consumes the suppression). Non-null means the chain
/// loop in expandAndCompileMacroUse can iterate instead of recursing.
fn chainNextMacroUse(self: *Compiler, form: Value) CompileError!?struct { name: []const u8, transformer: Value } {
    if (!types.isPair(form)) return null;
    const head = types.car(form);
    if (!types.isSymbol(head)) return null;
    const hname = types.symbolName(head);
    if (std.mem.eql(u8, hname, expander.USERTEXT_MARKER)) return null;
    const effective_name = types.stripHygienicPrefix(hname);
    const is_shadowed = std.mem.eql(u8, effective_name, hname) and
        (self.resolveLocal(hname) != null or (try self.resolveUpvalue(hname)) != null);
    if (is_shadowed) return null;
    if (self.suppress_macro_name) |smn| {
        if (std.mem.eql(u8, hname, smn)) return null;
    }
    const t = self.lookupMacro(hname) orelse return null;
    if (self.resolveLocal(hname) != null or (try self.resolveUpvalue(hname)) != null) return null;
    return .{ .name = hname, .transformer = t };
}

pub fn expandAndCompileMacroUse(self: *Compiler, expr: Value, name: []const u8, transformer: Value, dst: u16, is_tail: bool) CompileError!void {
    if (self.macro_expansion_depth >= MAX_MACRO_EXPANSION_DEPTH or
        self.macro_expansion_steps >= MAX_MACRO_EXPANSION_STEPS)
    {
        return CompileError.MacroExpansionLimit;
    }
    // Depth counts NESTED expansions only — a macro use compiled from
    // inside another expansion's result recurses natively through
    // compileExpr, so this cap is what keeps the native stack bounded.
    // Head-position chains (an expansion that IS directly another macro
    // use in the same position — SRFI 148's CK-machine steps, or a
    // degenerate (loop) → (loop)) iterate in the loop below at O(1)
    // native stack and are bounded by MAX_MACRO_EXPANSION_STEPS instead.
    // The two must not be conflated: raising THIS constant to cover deep
    // chains overflows the native stack — and in a Debug/test build the
    // segfault then fires inside the DebugAllocator's own stack capture,
    // whose SelfInfo lock the segfault handler needs, deadlocking the
    // whole test run at 0% CPU (kaappi#1796).
    self.macro_expansion_depth += 1;
    defer self.macro_expansion_depth -= 1;

    const gpa = self.gc.allocator;

    // ---- Chain-accumulated bookkeeping -------------------------------
    // Every link of the chain contributes temporary state that must stay
    // active until the FINAL (non-macro) form finishes compiling —
    // identifiers introduced by link k's template can survive into the
    // final form, so link k's injected locals, adjusted globals, and peer
    // swaps have to be live while it compiles. The old nested recursion
    // kept all of that alive in per-level native frames; these heap-side
    // accumulators keep the same lifetimes with per-link native cost
    // zero, unwound LIFO by the defers below on success and error alike.

    var merged_macros = std.StringHashMap(Value).init(gpa);
    defer merged_macros.deinit();

    var temp_globals: std.ArrayList(TempGlobal) = .empty;
    defer {
        if (self.globals) |g| {
            if (temp_globals.items.len > 0) {
                const glk = globals_mod.acquireGlobalsWrite(g);
                var tgi = temp_globals.items.len;
                while (tgi > 0) {
                    tgi -= 1;
                    const tg = temp_globals.items[tgi];
                    if (tg.was_present) {
                        g.put(tg.name, tg.old_val.?) catch {};
                    } else {
                        _ = g.remove(tg.name);
                    }
                }
                globals_mod.releaseGlobalsWrite(glk);
            }
        }
        temp_globals.deinit(gpa);
    }

    // R7RS 4.3.1: let-syntax transformers resolve free macro references
    // from the definition-site environment, not the use-site environment.
    var peer_saves: std.ArrayList(PeerSave) = .empty;
    defer {
        var pi = peer_saves.items.len;
        while (pi > 0) {
            pi -= 1;
            const ps = peer_saves.items[pi];
            if (ps.old) |old| {
                self.macros.put(ps.name, old) catch {};
            } else {
                _ = self.macros.remove(ps.name);
            }
        }
        peer_saves.deinit(gpa);
    }

    // Injected locals (hygienic captured-local aliases plus non-procedure
    // global aliases) accumulate across links. The chain's result lives in
    // dst by the time this unwinds, so the aliases are dead, and
    // compileExpr is register-balanced, making the LIFO rewind safe.
    // Leaking an alias register would break the balanced-register contract
    // expression compilation relies on — a call site allocates CONTIGUOUS
    // argument registers, so a leak inside one argument shifts every later
    // argument slot while the call still reads the original window (found
    // by the Kaappi-vs-Chibi differential oracle, #1396).
    const saved_locals_len = self.locals.items.len;
    // Set right before the final compileExpr(final_form, ...) call below
    // (kaappi#1800). compileExpr(final_form) can itself append a REAL,
    // sibling-visible local — a body-scope `define` reached through the
    // macro's expansion relies on compileDefine's in_body_scope branch
    // doing exactly that. Anything self.locals gains between
    // saved_locals_len and pre_final_locals_len is still transient chain
    // bookkeeping and must be discarded; anything gained AFTER
    // pre_final_locals_len is final_form's own persistent state and must
    // survive. The cleanup defer below removes only the former, shifting
    // the latter down to close the gap (self.locals is compile-time
    // bookkeeping with no bytecode encoding array position, only each
    // Local's own .slot register — unlike registers, closing the gap here
    // is safe).
    var pre_final_locals_len = saved_locals_len;
    var injected_reg_count: u16 = 0;
    defer {
        const kept = self.locals.items.len -| pre_final_locals_len;
        if (kept > 0) {
            // final_form left real locals behind. Splice out just the
            // transient block [saved_locals_len, pre_final_locals_len),
            // keeping the kept tail's relative order and slots intact.
            var i: usize = 0;
            while (i < kept) : (i += 1) {
                self.locals.items[saved_locals_len + i] = self.locals.items[pre_final_locals_len + i];
            }
            self.locals.shrinkRetainingCapacity(saved_locals_len + kept);
            // The transient block's registers sit BELOW the kept locals'
            // registers (allocated earlier); freeReg only reclaims from
            // the top, so freeing them here would instead free the kept
            // locals' registers out from under them. Leave them reserved
            // — a bounded, rare register leak, not a correctness bug.
            injected_reg_count = 0;
        } else {
            while (self.locals.items.len > saved_locals_len) {
                _ = self.locals.pop();
            }
        }
        while (injected_reg_count > 0) : (injected_reg_count -= 1) {
            self.freeReg();
        }
    }

    const saved_suppress = self.suppress_macro_name;
    defer self.suppress_macro_name = saved_suppress;

    // `kaappi check`: a macro expansion is not the user's direct source, so
    // suppress lint over everything compiled from it (kaappi#1511). Only calls
    // the user wrote outside any macro use are "direct calls to a built-in".
    var lint_enters: usize = 0;
    defer while (lint_enters > 0) : (lint_enters -= 1) check_lint.exitMacroExpansion();

    const use_check = expander.UseSiteBindingCheck{
        .ctx = @ptrCast(self),
        .resolve_fn = &resolveLocalSkipAliases,
        .frame_resolve_fn = &resolveSameFrameLocal,
    };

    var cur_expr = expr;
    var cur_name = name;
    var cur_transformer = transformer;
    var final_form = expr;
    var merged_stale = true;

    while (true) {
        if (self.macro_expansion_steps >= MAX_MACRO_EXPANSION_STEPS) {
            return CompileError.MacroExpansionLimit;
        }
        self.macro_expansion_steps += 1;

        // Merged macro view including parent scopes. Nothing that runs
        // between links can change any macro table except this function's
        // own let-syntax peer swap below (no compilation happens inside
        // the loop), so the view is rebuilt only after a link that
        // actually swapped — keeping a runaway chain's per-link cost flat
        // instead of O(links × macros in scope).
        if (merged_stale) {
            merged_macros.clearRetainingCapacity();
            var p: ?*Compiler = self.parent;
            while (p) |par| : (p = par.parent) {
                var it = par.macros.iterator();
                while (it.next()) |entry| {
                    try merged_macros.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
            var it = self.macros.iterator();
            while (it.next()) |entry| {
                try merged_macros.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            merged_stale = false;
        }

        const tx = types.toObject(cur_transformer).as(types.Transformer);

        // Track non-procedure global free vars that need local injection
        // to prevent shadowing by use-site locals (R7RS 4.3.1). Per-link,
        // consumed by the injection loop right after expansion.
        var global_free_names: [64][]const u8 = undefined;
        var global_free_count: usize = 0;

        // Temporarily add/modify globals so the expander doesn't rename
        // template free references. Undo records accumulate for the whole
        // chain; the per-link cap of 128 preserves the old fixed-array
        // behavior.
        if (self.globals) |g| {
            var level_count: usize = 0;
            // The sentinel puts below structurally mutate the globals
            // map when g is the VM's shared one — exclude SRFI-18
            // child-thread readers for the whole dance (#958). glk is
            // non-null exactly when g is the current thread's shared
            // globals map.
            const glk = globals_mod.acquireGlobalsWrite(g);
            defer globals_mod.releaseGlobalsWrite(glk);
            for (tx.captured_locals) |cap| {
                if (level_count < 128) {
                    if (g.get(cap.name)) |gval| {
                        temp_globals.append(gpa, .{ .name = cap.name, .old_val = gval, .was_present = true }) catch return CompileError.OutOfMemory;
                        level_count += 1;
                        _ = g.remove(cap.name);
                    }
                }
            }
            if (tx.def_env) |env| {
                var env_it = env.iterator();
                while (env_it.next()) |entry| {
                    if (!g.contains(entry.key_ptr.*) and level_count < 128) {
                        temp_globals.append(gpa, .{ .name = entry.key_ptr.*, .old_val = null, .was_present = false }) catch return CompileError.OutOfMemory;
                        level_count += 1;
                        try g.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            }
            // Identify non-procedure free globals that were already bound at
            // macro definition time (bound_free_refs): the template's own
            // reference to one must resolve to THIS SAME variable at the use
            // site regardless of what a use-site local shadows the name with
            // (R7RS 4.3.1 referential transparency). This used to be done by
            // temporarily marking the global VOID so renameForHygiene would
            // preserve the reference's bare name — but a bare, unrenamed
            // reference is textually indistinguishable from an unrelated
            // identifier of the same spelling introduced elsewhere in the
            // SAME expansion (e.g. a pattern-variable substitution of a
            // same-named use-site argument), which is exactly the collision
            // kaappi#1832 reported. So the reference is instead left to be
            // hygiene-renamed like any other template-introduced identifier
            // (#1208's own forward-reference concern still holds: only
            // identifiers bound at macro definition time are collected
            // here), and injectHygienicGlobalAliases (below, after
            // expansion) finds the renamed occurrence(s) in the tree and
            // aliases THEM to the global's current value instead of
            // aliasing the bare name.
            if (globals_mod.globals_ctx) |gctx| {
                for (tx.bound_free_refs) |cname| {
                    // #1812: a name resolvable through the transformer's own
                    // definition-environment library is protected by
                    // renameForHygiene's active_def_env check instead (a
                    // def_env_binding_prefix-marked reference, immune to
                    // whatever this self.globals/vm.globals currently holds
                    // for the same name) — skip the self.globals-based dance
                    // for it entirely so the two mechanisms never both fire
                    // for the same name. Mirrors renameForHygiene's own
                    // exclusion of true (scheme base) bindings (e.g.
                    // call-with-values): those stay on the OLD path here too,
                    // matching whichever mechanism actually protects them.
                    if (tx.def_env) |denv| {
                        if (denv.contains(cname) and globals_mod.lookupBaseBinding(cname) == null) continue;
                    }
                    const in_g = g.get(cname);
                    // glk != null means g IS the shared globals map
                    // and we already hold its exclusive lock; else
                    // this read needs its own child-thread lock.
                    const in_vm = if (glk != null)
                        (if (gctx.globals.count() > 0) gctx.globals.get(cname) else null)
                    else in_vm_blk: {
                        gctx.lockShared();
                        defer gctx.unlockShared();
                        break :in_vm_blk if (gctx.globals.count() > 0) gctx.globals.get(cname) else null;
                    };
                    const existing = in_g orelse in_vm;
                    if (existing) |val| {
                        if (!types.isProcedure(val) and !types.isTransformer(val) and val != types.VOID) {
                            // Track for local injection after expansion —
                            // the global itself is never touched now.
                            if (global_free_count < 64) {
                                global_free_names[global_free_count] = cname;
                                global_free_count += 1;
                            }
                        }
                    }
                }
            }
        }

        // Suppress GC during expansion: the expanded form isn't rooted
        // until the extra_roots append below, so a collection triggered
        // by allocPair inside expandMacro could free AST nodes that the
        // partially-built result references.
        self.gc.no_collect += 1;
        const expanded = expander.expandMacro(self.gc, cur_expr, cur_transformer, self.globals, &merged_macros, use_check) catch |err| {
            self.gc.no_collect -= 1;
            return switch (err) {
                error.OutOfMemory => CompileError.OutOfMemory,
                error.ScopeTableFull, error.PatternTooComplex => CompileError.InternalLimit,
                error.NoMatchingPattern, error.EllipsisCountMismatch, error.EllipsisDepthMismatch, error.EllipsisNoPatternVariable => CompileError.InvalidSyntax,
                error.TransformerFailed => recordTransformerFailure(),
            };
        };
        // Root for the rest of the enclosing compile scope via extra_roots
        // (released by that scope's shrinkRetainingCapacity, exactly like
        // compileDefineSyntax's transformers): the fixed root stack's 1024
        // slots cannot hold one root per chain link, and material from
        // EVERY link (injected local name slices, set!-target keys) must
        // stay reachable until the final form finishes compiling.
        self.gc.extra_roots.append(gpa, expanded) catch {
            self.gc.no_collect -= 1;
            return CompileError.OutOfMemory;
        };
        self.gc.no_collect -= 1;

        var expanded_root = expanded;
        // Unwrap user-text provenance markers before compiling; specs of
        // macros this expansion defines (syntax-rules subtrees) keep
        // theirs.
        if (expander.isUsertextPair(expanded_root)) {
            expanded_root = expander.unwrapUsertext(expanded_root);
        }
        if (types.isPair(expanded_root) or types.isVector(expanded_root)) {
            expander.stripUsertextMarkers(self.gc, expanded_root);
        }
        try self.scanSetTargets(expanded_root);
        try injectHygienicCapturedLocals(self, expanded_root, tx.captured_locals);
        // Inject non-procedure global free vars as locals so use-site
        // locals don't shadow the definition-site global binding (R7RS
        // 4.3.1 referential transparency). The reference was hygienically
        // renamed like any other template-introduced identifier (see the
        // bound_free_refs scan above), so injectHygienicGlobalAliases finds
        // whatever renamed name actually appears in the expansion instead
        // of assuming the bare name — and, since injectHygienicCapturedLocals
        // above already ran on this same tree, a name it already aliased is
        // naturally skipped by the "already in self.locals" check, without
        // needing a separate already-captured pre-filter.
        try injectHygienicGlobalAliases(self, expanded_root, global_free_names[0..global_free_count], &injected_reg_count);
        // Swap let-syntax sibling keywords to their outer values while
        // material from this transformer is live; the undo record is
        // appended before each swap so a mid-chain error restores
        // everything applied so far.
        std.debug.assert(tx.let_syntax_peer_names.len == tx.let_syntax_peer_vals.len);
        for (tx.let_syntax_peer_names, tx.let_syntax_peer_vals) |pn, pv| {
            peer_saves.append(gpa, .{ .name = pn, .old = self.macros.get(pn) }) catch return CompileError.OutOfMemory;
            if (pv != types.NIL) {
                self.macros.put(pn, pv) catch {};
            } else {
                _ = self.macros.remove(pn);
            }
            merged_stale = true;
        }

        check_lint.enterMacroExpansion();
        lint_enters += 1;

        // Fixed-point detection: if the expansion is structurally identical
        // to the input (e.g. SRFI-219 rule 3: (define x e) → (define x e))
        // AND the keyword is a built-in special form, suppress macro
        // re-expansion so the built-in handler takes over — compileForm
        // consumes the suppression, so the chain must break to it. For
        // non-special-form macros (a degenerate (loop) → (loop)), keep
        // chaining and let the step limit catch it.
        if (valuesStructurallyEqual(expanded_root, cur_expr, 128) and
            ir_mod.isSpecialForm(types.stripHygienicPrefix(cur_name)))
        {
            self.suppress_macro_name = cur_name;
            final_form = expanded_root;
            break;
        }

        // Head-position chain: the expansion is itself directly a macro
        // use that compileForm would route straight back here with the
        // same dst and tail flag. Iterate instead of recursing so chain
        // length costs no native stack (kaappi#1796) — the shape both
        // SRFI 148's CK machine and runaway (loop)-style macros have.
        if (try chainNextMacroUse(self, expanded_root)) |next| {
            cur_expr = expanded_root;
            cur_name = next.name;
            cur_transformer = next.transformer;
            continue;
        }

        final_form = expanded_root;
        break;
    }

    // Everything appended to self.locals up to this point (across every
    // link processed above) is transient chain bookkeeping and must still
    // be discarded by the defer above; mark the boundary right before
    // compiling final_form so it can tell that apart from whatever
    // final_form's own compilation appends.
    pre_final_locals_len = self.locals.items.len;
    return self.compileExpr(final_form, dst, is_tail);
}

// ---------------------------------------------------------------------------
// Macro definition forms
// ---------------------------------------------------------------------------

// -- Macro-defining forms (delegated to compiler_define_syntax.zig) --
//
// Aliased under their original names so compiler.zig / compiler_ir.zig /
// compiler_lambda.zig and this file's own references resolve unchanged.
const define_syntax = @import("compiler_define_syntax.zig");
pub const compileDefineSyntax = define_syntax.compileDefineSyntax;
pub const compileDefineProperty = define_syntax.compileDefineProperty;
pub const compileLetSyntax = define_syntax.compileLetSyntax;
pub const compileLetrecSyntax = define_syntax.compileLetrecSyntax;
pub const finalizeTransformer = define_syntax.finalizeTransformer;
pub const captureLocalsOnTransformer = define_syntax.captureLocalsOnTransformer;
pub const parseSyntaxRules = define_syntax.parseSyntaxRules;

pub fn nameInSlice(names: []const []const u8, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn injectHygienicCapturedLocals(self: *Compiler, expr: Value, captured: []const types.CapturedLocal) CompileError!void {
    if (captured.len == 0) return;
    try injectHygCapturedWalk(self, expr, captured);
}

fn injectHygCapturedWalk(self: *Compiler, expr: Value, captured: []const types.CapturedLocal) CompileError!void {
    if (types.isSymbol(expr)) {
        const name = types.symbolName(expr);
        if (!std.mem.startsWith(u8, name, "__hyg_")) return;
        const base = types.stripHygienicPrefix(name);
        if (base.len == name.len) return;
        var best_cap: ?types.CapturedLocal = null;
        for (captured) |cap| {
            if (std.mem.eql(u8, cap.name, base)) best_cap = cap;
        }
        if (best_cap) |cap| {
            // A __hyg_ name that is macro-bound is a renamed let-syntax
            // KEYWORD, not a variable reference — its base name matching a
            // captured local is a coincidence (e.g. SRFI 257's template macro
            // `k` vs a user variable `k`). Injecting the alias would shadow
            // the macro for the rest of the body (compileForm suppresses a
            // macro when a same-named local resolves), rerouting macro calls
            // into the user's variable.
            if (self.lookupMacro(name) != null) return;
            var already = false;
            for (self.locals.items) |loc| {
                if (std.mem.eql(u8, loc.name, name)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                // Keep the definition-time snapshot SLOT (a later same-named
                // binding must not hijack the alias — hygiene points at the
                // def-site binding), but take the CURRENT boxing status of
                // that slot: the variable may have been boxed since the
                // snapshot (a lambda captured it), and the alias must read
                // through the box exactly like a direct reference would.
                var is_boxed = false;
                for (self.locals.items) |live| {
                    if (live.slot == cap.slot and live.is_boxed) {
                        is_boxed = true;
                        break;
                    }
                }
                try self.locals.append(self.gc.allocator, .{
                    .name = name,
                    .depth = self.scope_depth,
                    .slot = cap.slot,
                    .binding_id = compiler_mod.freshBindingId(),
                    .is_boxed = is_boxed,
                });
            }
            return;
        }
        return;
    }
    if (types.isPair(expr)) {
        try injectHygCapturedWalk(self, types.car(expr), captured);
        try injectHygCapturedWalk(self, types.cdr(expr), captured);
    }
}

// ---------------------------------------------------------------------------
// Hygienic global-alias injection
// ---------------------------------------------------------------------------
//
// Companion to injectHygienicCapturedLocals above, for a template's free
// reference to a non-procedure global that was already bound at the macro's
// OWN definition time (bound_free_refs). Since kaappi#1832, such a reference
// is hygiene-renamed like any other template-introduced identifier instead
// of being preserved bare (a bare reference was indistinguishable from an
// unrelated same-spelled identifier introduced elsewhere in the same
// expansion — e.g. a pattern-variable substitution of a same-named use-site
// argument). So, unlike the old bare-name injection, the alias here is
// discovered by walking the expansion for the ACTUAL renamed name rather
// than reconstructed from the pre-expansion candidate list, and it loads a
// FRESH value from the global (there is no existing local slot to share, as
// injectHygCapturedWalk has for a definition-site local).

fn injectHygienicGlobalAliases(self: *Compiler, expr: Value, names: []const []const u8, injected_reg_count: *u16) CompileError!void {
    if (names.len == 0) return;
    try injectHygGlobalWalk(self, expr, names, injected_reg_count);
}

fn injectHygGlobalWalk(self: *Compiler, expr: Value, names: []const []const u8, injected_reg_count: *u16) CompileError!void {
    if (types.isSymbol(expr)) {
        const name = types.symbolName(expr);
        if (!std.mem.startsWith(u8, name, "__hyg_")) return;
        const base = types.stripHygienicPrefix(name);
        if (base.len == name.len or !nameInSlice(names, base)) return;
        // A __hyg_ name that is macro-bound is a renamed let-syntax KEYWORD,
        // not a variable reference (see injectHygCapturedWalk's identical
        // guard).
        if (self.lookupMacro(name) != null) return;
        for (self.locals.items) |loc| {
            if (std.mem.eql(u8, loc.name, name)) return; // already injected
        }
        // Load the global's current value into a fresh register. Register
        // exhaustion skips the injection (non-fatal, matching the old
        // bare-name loop this replaces), but a failure mid-emit must still
        // propagate: swallowing it after emitOp(.get_global) succeeded would
        // leave a truncated instruction in the chunk for the VM to decode
        // as garbage.
        const gslot = self.allocReg() catch return;
        injected_reg_count.* += 1;
        const gsym = try self.gc.allocSymbol(base);
        const gsym_idx = try self.addConstant(gsym);
        try self.emitOp(.get_global);
        try self.emitU16(gslot);
        try self.emitU16(gsym_idx);
        try self.locals.append(self.gc.allocator, .{
            .name = name,
            .depth = self.scope_depth,
            .slot = gslot,
            .binding_id = compiler_mod.freshBindingId(),
            .is_global_alias = true,
            .alias_global_name = base,
        });
        return;
    }
    if (types.isPair(expr)) {
        try injectHygGlobalWalk(self, types.car(expr), names, injected_reg_count);
        try injectHygGlobalWalk(self, types.cdr(expr), names, injected_reg_count);
    }
}

// ---------------------------------------------------------------------------
// Free-reference collection for macro hygiene
// ---------------------------------------------------------------------------

pub fn collectSymbols(expr: Value, out: *[64][]const u8, count: *usize) bool {
    return collectSymbolsDepth(expr, out, count, TEMPLATE_WALK_DEPTH_CAP);
}

/// #2405 (review of PR #2420): patterns of a syntax-rules spec NESTED in a
/// template reach this walk unvalidated (the spec's own patterns were checked
/// by validPatternGrammar at parse time; these were not). A depth cap bounds
/// any cycle: false means "collection failed", the walk's existing
/// set-unknown degradation.
const TEMPLATE_WALK_DEPTH_CAP: u32 = 256;

fn collectSymbolsDepth(expr: Value, out: *[64][]const u8, count: *usize, depth: u32) bool {
    if (depth == 0) return false;
    if (types.isSymbol(expr)) {
        const n = types.symbolName(expr);
        for (out[0..count.*]) |e| {
            if (std.mem.eql(u8, e, n)) return true;
        }
        if (count.* >= 64) return false;
        out[count.*] = n;
        count.* += 1;
        return true;
    }
    if (types.isPair(expr)) {
        if (!collectSymbolsDepth(types.car(expr), out, count, depth - 1)) return false;
        return collectSymbolsDepth(types.cdr(expr), out, count, depth - 1);
    }
    return true;
}

/// #2405 (review of PR #2420): active-path set for the template walk — the
/// free-ref collector recurses through itself on BOTH car and cdr, so every
/// pair it visits passes through the function once and a single
/// address-keyed membership test catches either cycle shape. Fixed-size and
/// allocation-free like every other buffer in this walk: overflow returns
/// false (set-unknown degradation), never a wrong error.
pub const TemplatePath = struct {
    addrs: [TEMPLATE_WALK_DEPTH_CAP]usize = undefined,
    len: usize = 0,

    fn contains(self: *const TemplatePath, key: usize) bool {
        for (self.addrs[0..self.len]) |a| {
            if (a == key) return true;
        }
        return false;
    }

    /// False when the path is full: the caller degrades, not errors.
    fn push(self: *TemplatePath, key: usize) bool {
        if (self.len >= self.addrs.len) return false;
        self.addrs[self.len] = key;
        self.len += 1;
        return true;
    }

    fn pop(self: *TemplatePath) void {
        if (self.len > 0) self.len -= 1;
    }
};

pub fn collectFreeRefs(template: Value, pat_vars: []const []const u8, literals: []const Value, out: *[64][]const u8, count: *usize) CompileError!bool {
    var path: TemplatePath = .{};
    return collectFreeRefsWithLocals(template, pat_vars, literals, &.{}, out, count, &path);
}

fn collectFreeRefsWithLocals(template: Value, pat_vars: []const []const u8, literals: []const Value, local_binds: []const []const u8, out: *[64][]const u8, count: *usize, path: *TemplatePath) CompileError!bool {
    if (types.isSymbol(template)) {
        const name = types.symbolName(template);
        for (pat_vars) |pv| {
            if (std.mem.eql(u8, pv, name)) return true;
        }
        for (local_binds) |lb| {
            if (std.mem.eql(u8, lb, name)) return true;
        }
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) return true;
        }
        if (expander.isWellKnown(name)) return true;
        for (out[0..count.*]) |e| {
            if (std.mem.eql(u8, e, name)) return true;
        }
        if (count.* >= 64) return false;
        out[count.*] = name;
        count.* += 1;
        return true;
    }
    if (!types.isPair(template)) return true;
    // #2405 (review of PR #2420): a cyclic TEMPLATE aborted or hung the
    // definition itself — `(syntax-rules () ((_ x) #0=(f #0#)))` SIGBUSed in
    // this walk before the macro was ever used. The recursion below passes
    // through this function on both the car (last two lines) and the cdr, so
    // one active-path membership test here catches both cycle shapes.
    const path_key = @intFromPtr(types.toObject(template));
    if (path.contains(path_key)) return compiler_mod.circularFormError();
    if (!path.push(path_key)) return false; // path full: set-unknown degradation
    defer path.pop();
    const head = types.car(template);
    const rest = types.cdr(template);
    if (types.isSymbol(head)) {
        const hname = types.symbolName(head);
        if (isLetForm(hname)) {
            if (rest != types.NIL and types.isPair(rest)) {
                var bab = rest;
                if (types.isSymbol(types.car(rest))) bab = types.cdr(rest);
                if (bab != types.NIL and types.isPair(bab)) {
                    var let_names: [16][]const u8 = undefined;
                    var let_count: usize = 0;
                    for (local_binds) |lb| {
                        if (let_count < 16) {
                            let_names[let_count] = lb;
                            let_count += 1;
                        }
                    }
                    var binds = compiler_mod.SpineWalk.init(types.car(bab));
                    while (types.isPair(binds.cur)) : (binds.next()) {
                        if (binds.cyclic()) return compiler_mod.circularFormError();
                        const b = types.car(binds.cur);
                        if (types.isPair(b)) {
                            const bname = types.car(b);
                            if (types.isSymbol(bname) and let_count < 16) {
                                let_names[let_count] = types.symbolName(bname);
                                let_count += 1;
                            }
                            const init_rest2 = types.cdr(b);
                            if (init_rest2 != types.NIL and types.isPair(init_rest2))
                                if (!(try collectFreeRefsWithLocals(types.car(init_rest2), pat_vars, literals, local_binds, out, count, path))) return false;
                        }
                    }
                    if (!(try collectFreeRefsWithLocals(types.cdr(bab), pat_vars, literals, let_names[0..let_count], out, count, path))) return false;
                }
            }
            return true;
        }
        if (std.mem.eql(u8, hname, "lambda")) {
            if (rest != types.NIL and types.isPair(rest)) {
                var lam_names: [16][]const u8 = undefined;
                var lam_count: usize = 0;
                for (local_binds) |lb| {
                    if (lam_count < 16) {
                        lam_names[lam_count] = lb;
                        lam_count += 1;
                    }
                }
                var params = compiler_mod.SpineWalk.init(types.car(rest));
                while (types.isPair(params.cur)) : (params.next()) {
                    if (params.cyclic()) return compiler_mod.circularFormError();
                    const pp = types.car(params.cur);
                    if (types.isSymbol(pp) and lam_count < 16) {
                        lam_names[lam_count] = types.symbolName(pp);
                        lam_count += 1;
                    }
                }
                if (types.isSymbol(params.cur) and lam_count < 16) {
                    lam_names[lam_count] = types.symbolName(params.cur);
                    lam_count += 1;
                }
                if (!(try collectFreeRefsWithLocals(types.cdr(rest), pat_vars, literals, lam_names[0..lam_count], out, count, path))) return false;
            }
            return true;
        }
        if (std.mem.eql(u8, hname, "define")) {
            if (rest != types.NIL and types.isPair(rest))
                if (!(try collectFreeRefsWithLocals(types.cdr(rest), pat_vars, literals, local_binds, out, count, path))) return false;
            return true;
        }
        if (std.mem.eql(u8, hname, "syntax-rules")) {
            if (rest != types.NIL and types.isPair(rest)) {
                var sr_names: [64][]const u8 = undefined;
                var sr_count: usize = 0;
                for (local_binds) |lb| {
                    if (sr_count < 64) {
                        sr_names[sr_count] = lb;
                        sr_count += 1;
                    }
                }
                var sr_rules = compiler_mod.SpineWalk.init(types.cdr(rest));
                while (types.isPair(sr_rules.cur)) : (sr_rules.next()) {
                    if (sr_rules.cyclic()) return compiler_mod.circularFormError();
                    const sr_rule = types.car(sr_rules.cur);
                    if (types.isPair(sr_rule)) {
                        if (!collectSymbols(types.car(sr_rule), @ptrCast(&sr_names), &sr_count)) return false;
                    }
                }
                if (!(try collectFreeRefsWithLocals(rest, pat_vars, literals, sr_names[0..sr_count], out, count, path))) return false;
            }
            return true;
        }
    }
    if (!(try collectFreeRefsWithLocals(head, pat_vars, literals, local_binds, out, count, path))) return false;
    return collectFreeRefsWithLocals(rest, pat_vars, literals, local_binds, out, count, path);
}

fn isLetForm(name: []const u8) bool {
    return std.mem.eql(u8, name, "let") or std.mem.eql(u8, name, "let*") or
        std.mem.eql(u8, name, "letrec") or std.mem.eql(u8, name, "letrec*");
}
