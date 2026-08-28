//! Macro-DEFINING forms, split out of compiler_macro.zig (file size policy):
//! define-syntax / let-syntax / letrec-syntax / define-property compilation,
//! transformer-spec resolution (SRFI 147: macro uses, bare-keyword aliases,
//! and begin-wrapped definitions that expand to a transformer), syntax-rules
//! parsing, and transformer finalization (free-ref capture + R7RS 4.3.1
//! let-syntax peer snapshots). compiler_macro.zig keeps the macro-USE path
//! (expandAndCompileMacroUse and the hygiene injection walks) and re-exports
//! this file's entry points, so callers still go through compiler_macro /
//! compiler_forms unchanged.
//!
//! GC note (.claude/rules/gc-safety.md): resolved transformer specs are
//! rooted with an immediate, explicitly-paired popRoot right after the
//! allocating call being protected — never a `defer` across code that can
//! itself push roots (the SRFI 147 root-stack lesson).

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

const macro = @import("compiler_macro.zig");
const MAX_MACRO_EXPANSION_DEPTH = macro.MAX_MACRO_EXPANSION_DEPTH;
const recordTransformerFailure = macro.recordTransformerFailure;
const resolveLocalSkipAliases = macro.resolveLocalSkipAliases;
const resolveSameFrameLocal = macro.resolveSameFrameLocal;
const expandAndCompileMacroUse = macro.expandAndCompileMacroUse;
const collectFreeRefs = macro.collectFreeRefs;
const collectSymbols = macro.collectSymbols;
const nameInSlice = macro.nameInSlice;

pub fn compileDefineSyntax(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (types.isEnvironment(self.lib_env_val) and types.toEnvironment(self.lib_env_val).immutable)
        return CompileError.InvalidSyntax;
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const keyword = types.car(args);
    if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const transformer_spec = types.car(rest);

    // resolveTransformerSpec resolves through SRFI 147's macro-use/alias/
    // begin alternatives (if any), bottoming out at a parsed Transformer --
    // freshly allocated and otherwise unrooted, exactly like a direct
    // parseSyntaxRules call used to be here. Root it immediately below via
    // extra_roots.append, with nothing able to allocate via the GC in
    // between.
    const transformer = try resolveTransformerSpec(self, transformer_spec);

    // Root the transformer for the rest of the enclosing compile scope: it
    // lives only in the compiler-local macro map, which the GC cannot see,
    // and a body-local macro must survive collections triggered while
    // compiling sibling forms that use it (#1401). Released by the
    // enclosing scope's extra_roots truncation — compileExpression* at top
    // level, or the lambda-body compile (compileLambdaWithIR /
    // compileLambda) for body scopes.
    self.gc.extra_roots.append(self.gc.allocator, transformer) catch return CompileError.OutOfMemory;

    const tx = types.toObject(transformer).as(types.Transformer);
    if (self.lib_env) |env| {
        tx.def_env = env;
        tx.def_env_val = self.lib_env_val;
        // #1961 (review): resolveTransformerSpec can return a pre-existing
        // (possibly promoted) transformer via the SRFI 147/211 alias paths,
        // so this store may write a young environment into an OLD
        // transformer — an old→young edge the minor mark reaches only
        // through the remembered set. No isEnvironment guard needed:
        // writeBarrier no-ops on the immediate NIL the library-rooted case
        // carries.
        self.gc.writeBarrier(types.toObject(transformer), self.lib_env_val);
        globals_mod.assertEnvMapInvariant(env, self.lib_env_val); // #1962
        // #1812: pairs with def_env so renameForHygiene can build a
        // def_env_binding_prefix-marked reference that survives being
        // imported anywhere, instead of resolving by bare name against
        // whatever vm.globals the use site happens to have.
        tx.def_lib_name = globals_mod.currentLibName();
    }

    try finalizeTransformer(self, transformer);

    const name = types.symbolName(keyword);
    try self.recordBodyMacro(name);
    self.macros.put(name, transformer) catch return CompileError.OutOfMemory;

    // A define-syntax at a library's top level (not nested in a lambda/let
    // body scope) is also stored in the library environment (issue #877).
    if (self.body_macro_depth == 0) {
        if (self.lib_env) |env| {
            env.put(name, transformer) catch return CompileError.OutOfMemory;
            // #1961: the shared envStoreBarrier (mutable eval/environment
            // objects only — the interaction-environment wrapper's map is
            // the root-marked globals and enrolls nothing).
            self.gc.envStoreBarrier(self.lib_env_val, transformer);
        }
    }

    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

/// SRFI 213: `(define-property <identifier> <key> <expression>)`. The
/// expression is evaluated NOW — at macro-expansion time, in the global
/// environment — and the value is attached to the (effective-name-keyed)
/// binding pair in the VM-owned property table, without disturbing either
/// binding's meaning. Procedural transformers read it back through the
/// `lookup` procedure the SRFI 213 capture-lookup re-entry provides
/// (expander.propertyLookupFn).
///
/// v1 scope reduction, documented in lib/srfi/213.sld: only (program or
/// library) top level — a definition context whose region extends to the
/// end of the program, which a global table models faithfully. Body-level
/// definitions would need scoped retraction and are rejected.
pub fn compileDefineProperty(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (self.in_body_scope) return CompileError.InvalidSyntax;
    if (args == types.NIL or !types.isPair(args)) return CompileError.InvalidSyntax;
    const id = types.car(args);
    const rest1 = types.cdr(args);
    if (!types.isPair(rest1)) return CompileError.InvalidSyntax;
    const key = types.car(rest1);
    const rest2 = types.cdr(rest1);
    if (!types.isPair(rest2) or types.cdr(rest2) != types.NIL) return CompileError.InvalidSyntax;
    const expr = types.car(rest2);
    if (!types.isSymbol(id) or !types.isSymbol(key)) return CompileError.InvalidSyntax;

    const eval_fn = globals_mod.eval_datum_for_macro orelse return CompileError.InvalidSyntax;
    const set_fn = globals_mod.syntax_property_set orelse return CompileError.InvalidSyntax;
    const val = eval_fn(expr) catch |err| return switch (err) {
        error.OutOfMemory => CompileError.OutOfMemory,
        else => CompileError.InvalidSyntax,
    };
    // No GC-triggering allocation between the eval's return and the table
    // store (the table and its composite key use the raw allocator), so the
    // unrooted `val` cannot be collected in between; once stored it is
    // marked via markVMRoots.
    set_fn(
        types.stripHygienicPrefix(types.symbolName(id)),
        types.stripHygienicPrefix(types.symbolName(key)),
        val,
    ) catch return CompileError.OutOfMemory;

    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

pub fn compileLetSyntax(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    // Phase 1: Parse ALL transformer specs before registering any.
    // self.macros still has the outer values during this phase.
    //
    // Count bindings first, then pre-allocate tx_vals to exact capacity
    // so pushRoot pointers into its backing buffer stay valid across
    // subsequent appends (GC safety: no reallocation after rooting).
    var bind_count: usize = 0;
    var count_walk = compiler_mod.SpineWalk.init(bindings);
    while (count_walk.cur != types.NIL) : (count_walk.next()) {
        if (!types.isPair(count_walk.cur)) return CompileError.InvalidSyntax;
        if (count_walk.cyclic()) return compiler_mod.circularFormError();
        bind_count += 1;
    }

    var kw_names: std.ArrayList([]const u8) = .empty;
    defer kw_names.deinit(self.gc.allocator);
    kw_names.ensureTotalCapacity(self.gc.allocator, bind_count) catch return CompileError.OutOfMemory;
    var tx_vals: std.ArrayList(Value) = .empty;
    defer tx_vals.deinit(self.gc.allocator);
    tx_vals.ensureTotalCapacity(self.gc.allocator, bind_count) catch return CompileError.OutOfMemory;
    var roots_pushed: usize = 0;
    // Registered before the binding loop so a mid-loop InvalidSyntax (or a
    // failing resolveTransformerSpec) pops what earlier iterations pushed —
    // the pops run before tx_vals.deinit, which the roots point into
    // (PR #1853 review). LIFO-safe: each iteration's push is balanced by
    // exactly one pop here, and nothing after the loop pushes.
    defer for (0..roots_pushed) |_| self.gc.popRoot();

    var binding_list = compiler_mod.SpineWalk.init(bindings);
    while (binding_list.cur != types.NIL) : (binding_list.next()) {
        if (!types.isPair(binding_list.cur)) return CompileError.InvalidSyntax;
        if (binding_list.cyclic()) return compiler_mod.circularFormError();
        const binding = types.car(binding_list.cur);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        const keyword = types.car(binding);
        if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
        const binding_rest = types.cdr(binding);
        if (!types.isPair(binding_rest)) return CompileError.InvalidSyntax;
        const transformer_spec = types.car(binding_rest);
        // resolveTransformerSpec returns an already-parsed, otherwise
        // unrooted Transformer (see compileDefineSyntax) -- root it via
        // tx_vals's own slot immediately after; appendAssumeCapacity
        // doesn't allocate (capacity reserved above), so nothing can
        // trigger a GC in between.
        const transformer = try resolveTransformerSpec(self, transformer_spec);
        tx_vals.appendAssumeCapacity(transformer);
        self.gc.pushRoot(&tx_vals.items[tx_vals.items.len - 1]);
        roots_pushed += 1;
        kw_names.appendAssumeCapacity(types.symbolName(keyword));
    }

    // Build peer snapshot: each keyword's outer macro value (NIL = unbound).
    // Duped per transformer so each owns its own copy.
    const bind_n = kw_names.items.len;
    const peer_snap_names = self.gc.allocator.alloc([]const u8, bind_n) catch return CompileError.OutOfMemory;
    defer self.gc.allocator.free(peer_snap_names);
    const peer_snap_vals = self.gc.allocator.alloc(Value, bind_n) catch return CompileError.OutOfMemory;
    defer self.gc.allocator.free(peer_snap_vals);
    for (kw_names.items, 0..) |name, i| {
        peer_snap_names[i] = name;
        peer_snap_vals[i] = self.macros.get(name) orelse types.NIL;
    }

    // Phase 2: Save outer values and register all bindings.
    var saved_names: std.ArrayList([]const u8) = .empty;
    defer saved_names.deinit(self.gc.allocator);
    var saved_values: std.ArrayList(?Value) = .empty;
    defer saved_values.deinit(self.gc.allocator);

    for (kw_names.items, tx_vals.items) |name, transformer| {
        saved_names.append(self.gc.allocator, name) catch return CompileError.OutOfMemory;
        saved_values.append(self.gc.allocator, self.macros.get(name)) catch return CompileError.OutOfMemory;
        try finalizeTransformer(self, transformer);
        const tx = types.toObject(transformer).as(types.Transformer);

        // R7RS 4.3.1 sibling-suppression snapshot: computed exactly once
        // per Transformer object, permanently, guarded by peers_computed
        // (see its own doc comment in types.zig for why recomputing is a
        // correctness bug, not just a wasted allocation -- a transformer's
        // free references must resolve against its TRUE point of origin,
        // not whatever OTHER let-syntax form later happens to alias it by
        // bare keyword or begin-wrapped reference, SRFI 147). A binding
        // that reaches an already-finalized peer snapshot here is exactly
        // that kind of alias -- reuse it unchanged.
        if (tx.peers_computed) {
            self.macros.put(name, transformer) catch return CompileError.OutOfMemory;
            continue;
        }

        // R7RS 4.3.1 suppresses sibling keywords only for references the
        // transformer's TEMPLATE makes (definition-site free references). A
        // sibling handed to it as an argument is a use-site identifier — not a
        // template free reference — and must stay resolvable (the
        // `classify-nonellipsis-symbol` idiom `(b () k ...)` passes a sibling
        // macro `k` through helper `b`). So keep only siblings this
        // transformer free-references; on overflow, fall back to all siblings.
        var free_names: [64][]const u8 = undefined;
        var free_count: usize = 0;
        const have_free = collectTransformerFreeRefs(transformer, &free_names, &free_count);
        var peer_names_f: std.ArrayList([]const u8) = .empty;
        defer peer_names_f.deinit(self.gc.allocator);
        var peer_vals_f: std.ArrayList(Value) = .empty;
        defer peer_vals_f.deinit(self.gc.allocator);
        for (peer_snap_names, peer_snap_vals) |pn, pv| {
            if (!have_free or nameInSlice(free_names[0..free_count], pn)) {
                peer_names_f.append(self.gc.allocator, pn) catch return CompileError.OutOfMemory;
                peer_vals_f.append(self.gc.allocator, pv) catch return CompileError.OutOfMemory;
            }
        }
        // Dupe both new slices before touching the (always default-empty
        // here, since peers_computed guarantees this runs at most once
        // per object) old fields, so a failure on the second dupe can't
        // leave one field already overwritten and the other freed out
        // from under it (CodeRabbit).
        const new_peer_names = self.gc.allocator.dupe([]const u8, peer_names_f.items) catch return CompileError.OutOfMemory;
        const new_peer_vals = self.gc.allocator.dupe(Value, peer_vals_f.items) catch {
            self.gc.allocator.free(new_peer_names);
            return CompileError.OutOfMemory;
        };
        tx.let_syntax_peer_names = new_peer_names;
        tx.let_syntax_peer_vals = new_peer_vals;
        // #1961 (review): resolveTransformerSpec can hand back a
        // PRE-EXISTING transformer (SRFI 147 alias/bare-symbol specs, SRFI
        // 211 globals) that was promoted long before this let-syntax — the
        // peers_computed guard above does not prove freshness, since plain
        // define-syntax transformers never compute peers. The snapshot is a
        // fresh bundle of old→young edges on such a transformer; barrier
        // each value so the generational minor mark can still reach them.
        for (new_peer_vals) |pv| self.gc.writeBarrier(types.toObject(transformer), pv);
        // Only NOW, once both slices are durably stored, mark this
        // transformer's snapshot complete (CodeRabbit): setting the flag
        // any earlier -- before the fallible appends/dupes above -- would
        // let an OOM leave peers_computed true with the default-empty
        // snapshot never actually filled in, and every later reuse would
        // silently accept that empty snapshot as final instead of retrying.
        tx.peers_computed = true;
        self.macros.put(name, transformer) catch return CompileError.OutOfMemory;
    }

    try compileSyntaxBody(self, body, dst, is_tail);
    restoreMacros(self, saved_names.items, saved_values.items);
}

pub fn compileLetrecSyntax(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var saved_names: std.ArrayList([]const u8) = .empty;
    defer saved_names.deinit(self.gc.allocator);
    var saved_values: std.ArrayList(?Value) = .empty;
    defer saved_values.deinit(self.gc.allocator);

    var binding_list = compiler_mod.SpineWalk.init(bindings);
    while (binding_list.cur != types.NIL) : (binding_list.next()) {
        if (!types.isPair(binding_list.cur)) return CompileError.InvalidSyntax;
        if (binding_list.cyclic()) return compiler_mod.circularFormError();
        const binding = types.car(binding_list.cur);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        const keyword = types.car(binding);
        if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
        const binding_rest = types.cdr(binding);
        if (!types.isPair(binding_rest)) return CompileError.InvalidSyntax;
        const transformer_spec = types.car(binding_rest);
        // resolveTransformerSpec returns an already-parsed, otherwise
        // unrooted Transformer (see compileDefineSyntax) -- root it via
        // extra_roots.append immediately below, nothing allocates via the
        // GC in between.
        const transformer = try resolveTransformerSpec(self, transformer_spec);
        const name = types.symbolName(keyword);

        // Root for the rest of the compile — see compileDefineSyntax (#1401).
        self.gc.extra_roots.append(self.gc.allocator, transformer) catch return CompileError.OutOfMemory;

        saved_names.append(self.gc.allocator, name) catch return CompileError.OutOfMemory;
        saved_values.append(self.gc.allocator, self.macros.get(name)) catch return CompileError.OutOfMemory;
        try finalizeTransformer(self, transformer);
        self.macros.put(name, transformer) catch return CompileError.OutOfMemory;
    }

    try compileSyntaxBody(self, body, dst, is_tail);
    restoreMacros(self, saved_names.items, saved_values.items);
}

/// Runs captureLocalsOnTransformer + computeBoundFreeRefs exactly once per
/// transformer, guarded by Transformer.finalized. Necessary because SRFI
/// 147 resolution (resolveTransformerSpec) can return the SAME Value to
/// more than one binding site -- a bare-keyword alias, or a begin-wrapped
/// helper referenced by name from an outer spec's own tail -- and both
/// wrapped functions allocate and unconditionally overwrite a slice field
/// with no free of whatever was there before; calling them a second time
/// on an already-finalized transformer leaks the first allocation.
pub fn finalizeTransformer(self: *Compiler, transformer: Value) CompileError!void {
    const tx = types.toObject(transformer).as(types.Transformer);
    if (tx.finalized) return;
    tx.finalized = true;
    try captureLocalsOnTransformer(self, transformer);
    try computeBoundFreeRefs(self, transformer);
}

pub fn captureLocalsOnTransformer(self: *Compiler, transformer: Value) CompileError!void {
    if (self.locals.items.len == 0) return;
    const tx = types.toObject(transformer).as(types.Transformer);
    const caps = self.gc.allocator.alloc(types.CapturedLocal, self.locals.items.len) catch return CompileError.OutOfMemory;
    for (self.locals.items, 0..) |local, ci| {
        caps[ci] = .{ .name = local.name, .slot = local.slot };
    }
    tx.captured_locals = caps;
}

fn compileSyntaxBody(self: *Compiler, body: Value, dst: u16, is_tail: bool) CompileError!void {
    self.beginScope();
    const saved_body_scope = self.in_body_scope;
    self.in_body_scope = true;
    const macro_mark = self.beginBodyMacroScope();
    errdefer self.endBodyMacroScope(macro_mark) catch {};
    // #2405: a let-syntax/letrec-syntax body is a raw spine, and a datum-label
    // cycle through it (`#0=(let-syntax () . #0#)`, whose body IS the whole
    // form) used to spin this loop forever, emitting an unbounded instruction
    // stream. The tortoise-and-hare guard names the cycle instead; `tail`
    // peeks one cdr ahead rather than consuming, which the guarded walk needs.
    var current = compiler_mod.SpineWalk.init(body);
    while (current.cur != types.NIL) : (current.next()) {
        if (!types.isPair(current.cur)) return CompileError.InvalidSyntax;
        if (current.cyclic()) return compiler_mod.circularFormError();
        const expr = types.car(current.cur);
        const tail = is_tail and types.cdr(current.cur) == types.NIL;
        try self.compileExprViaIR(expr, dst, tail);
    }
    try self.endBodyMacroScope(macro_mark);
    self.in_body_scope = saved_body_scope;
    self.endScope();
}

fn restoreMacros(self: *Compiler, names: [][]const u8, values: []?Value) void {
    for (names, values) |name, saved_val| {
        if (saved_val) |old_val| {
            self.macros.put(name, old_val) catch {};
        } else {
            _ = self.macros.remove(name);
        }
    }
}

/// Collect the free-reference identifier names in a transformer's templates —
/// identifiers that are neither the rule's pattern variables nor literals.
/// Returns false on overflow (caller should then treat the set as unknown).
fn collectTransformerFreeRefs(transformer: Value, out: *[64][]const u8, count: *usize) bool {
    const tx = types.toObject(transformer).as(types.Transformer);
    var pv_names: [64][]const u8 = undefined;
    var pv_count: usize = 0;
    for (tx.patterns[0..tx.num_rules]) |pat| {
        if (!collectSymbols(pat, &pv_names, &pv_count)) return false;
    }
    for (tx.templates[0..tx.num_rules]) |tmpl| {
        if (!collectFreeRefs(tmpl, pv_names[0..pv_count], tx.literals, out, count)) return false;
    }
    return true;
}

fn computeBoundFreeRefs(self: *Compiler, transformer: Value) CompileError!void {
    const tx = types.toObject(transformer).as(types.Transformer);
    var pv_names: [64][]const u8 = undefined;
    var pv_count: usize = 0;
    for (tx.patterns[0..tx.num_rules]) |pat| {
        if (!collectSymbols(pat, &pv_names, &pv_count)) return;
    }
    var cand_names: [64][]const u8 = undefined;
    var cand_count: usize = 0;
    for (tx.templates[0..tx.num_rules]) |tmpl| {
        if (!collectFreeRefs(tmpl, pv_names[0..pv_count], tx.literals, &cand_names, &cand_count))
            return;
    }
    if (cand_count == 0) return;
    var bound: [64][]const u8 = undefined;
    var bound_count: usize = 0;
    var local_refs: [64][]const u8 = undefined;
    var local_ref_count: usize = 0;
    for (cand_names[0..cand_count]) |cname| {
        const in_globals = if (self.globals) |g| g.contains(cname) else false;
        const in_def_env = if (tx.def_env) |env| env.contains(cname) else false;
        const in_locals = self.isLexicallyBound(cname);
        const in_macros = self.macros.contains(cname);
        if (in_globals or in_def_env or in_locals or in_macros) {
            if (bound_count < 64) {
                bound[bound_count] = cname;
                bound_count += 1;
            }
        }
        if (in_locals and !in_macros and local_ref_count < 64) {
            local_refs[local_ref_count] = cname;
            local_ref_count += 1;
        }
    }
    if (local_ref_count > 0) {
        tx.def_site_local_refs = self.gc.allocator.alloc([]const u8, local_ref_count) catch
            return CompileError.OutOfMemory;
        @memcpy(tx.def_site_local_refs, local_refs[0..local_ref_count]);
    }
    if (bound_count == 0) return;
    tx.bound_free_refs = self.gc.allocator.alloc([]const u8, bound_count) catch
        return CompileError.OutOfMemory;
    @memcpy(tx.bound_free_refs, bound[0..bound_count]);
}

// ---------------------------------------------------------------------------
// Syntax-rules parsing
// ---------------------------------------------------------------------------

/// SRFI 147 (custom macro transformers): R7RS's <transformer spec> only
/// accepts a literal `(syntax-rules ...)` form. This SRFI extends it with
/// three more alternatives, all implemented here:
///
///  1. A macro use that itself expands (possibly through several steps)
///     to a literal `(syntax-rules ...)` form -- letting a library define
///     its own named transformer-generating-transformer, e.g. a
///     `syntax-rules*` that automatically wraps multi-form templates in
///     `begin` (the SRFI's own worked example).
///  2. A bare keyword making the new name an alias for an existing
///     *user-defined* one (resolved via a direct `merged_macros` lookup).
///     A builtin special form is NOT aliasable this way: builtins are
///     recognized structurally in `ir_mod.isSpecialForm`, never stored as
///     `Transformer` values in `merged_macros`, so aliasing one correctly
///     falls through to `InvalidSyntax` -- there's nothing to find.
///  3. A macro use expanding to `(begin <definition>... <transformer
///     spec>)`, letting a transformer-generating-transformer introduce
///     its own private helper macros while building up the final spec.
///
/// SRFI 148's `em-syntax-rules` -- the reason this SRFI was implemented --
/// needs alternatives 2 and 3 together, not just 1: tracing its reference
/// implementation's own `em-syntax-rules-aux1`/`em-syntax-rules-aux2`
/// shows its core expansion mechanism bottoms out through exactly
/// `(begin (define-syntax a spec) a)` -- a begin-wrapped form whose FINAL
/// element is a bare reference to the helper just defined, not a fresh
/// macro use or literal `syntax-rules` form. An initial, shallower
/// research pass wrongly concluded alternatives 2 and 3 weren't needed;
/// this correction shipped once the actual reference implementation
/// (not just the spec prose) was traced through.
fn resolveTransformerSpec(self: *Compiler, spec_in: Value) CompileError!Value {
    // A transformer-spec can be compiled inside a nested child Compiler
    // scope (e.g. a let-syntax whose own body sits inside `guard`'s
    // desugared lambda) whose OWN self.macros doesn't include an
    // enclosing scope's macros -- they're never copied down automatically,
    // only merged on demand.
    //
    // Collect the ancestor chain first, then populate FARTHEST-to-NEAREST
    // (self.macros last of all): std.StringHashMap.put overwrites, so
    // whichever scope is written LAST wins, and correct lexical shadowing
    // requires the NEAREST enclosing definition of a name to win over a
    // FARTHER one. Populating nearest-to-farthest (as
    // expandAndCompileMacroUse's own ancestor-merge does) gets this
    // backwards for a name defined in more than one ancestor generation --
    // confirmed via a 3-level nested-lambda reproduction where an
    // outermost definition wrongly won over a middle one that should have
    // shadowed it. Deliberately not fixed in expandAndCompileMacroUse
    // itself in this same change: it's the most heavily-exercised path in
    // the entire macro system, the scenario needs 2+ ancestor generations
    // redefining the exact same macro name (rare in practice, never
    // observed causing a problem there), and touching it carries real
    // regression risk disproportionate to this PR's actual scope --
    // worth its own dedicated fix.
    var chain: std.ArrayList(*Compiler) = .empty;
    defer chain.deinit(self.gc.allocator);
    var p: ?*Compiler = self.parent;
    while (p) |par| : (p = par.parent) {
        chain.append(self.gc.allocator, par) catch return CompileError.OutOfMemory;
    }
    var merged_macros = std.StringHashMap(Value).init(self.gc.allocator);
    defer merged_macros.deinit();
    var i = chain.items.len;
    while (i > 0) {
        i -= 1;
        var it = chain.items[i].macros.iterator();
        while (it.next()) |entry| {
            merged_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
        }
    }
    var self_it = self.macros.iterator();
    while (self_it.next()) |entry| {
        merged_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }

    var steps: u32 = 0;
    return resolveTransformerSpecRec(self, spec_in, &merged_macros, &steps);
}

/// The actual resolution loop, factored out so a `(begin (define-syntax
/// NAME spec) ...)` alternative can recurse into itself to resolve each
/// internal helper's own spec, sharing the same `merged_macros` (so a
/// later helper, or the final transformer-spec, can reference an earlier
/// one) and the same expansion-step budget (so a pathological chain of
/// nested begins can't bypass MAX_MACRO_EXPANSION_DEPTH). Returns an
/// already-parsed Transformer, not raw `syntax-rules` source -- required
/// because the bare-symbol alias case (below) has no source to hand back,
/// only a Transformer some earlier step already parsed.
fn resolveTransformerSpecRec(self: *Compiler, spec_in: Value, merged_macros: *std.StringHashMap(Value), steps: *u32) CompileError!Value {
    var spec = spec_in;
    self.gc.pushRoot(&spec);
    defer self.gc.popRoot();
    while (true) {
        // Alternative 2: a bare identifier aliases whatever transformer
        // that name already resolves to -- either a helper this same
        // begin-unwrap just registered (the shape SRFI 148 needs:
        // `(begin (define-syntax a spec) a)`) or any other macro already
        // visible here. A name absent from merged_macros (including any
        // builtin special form, never stored there) correctly falls
        // through to InvalidSyntax: there is no Transformer to alias.
        if (types.isSymbol(spec)) {
            const alias_name = types.symbolName(spec);
            if (merged_macros.get(alias_name)) |t| return t;
            // SRFI 211: a global variable holding a transformer object —
            // `(define t (er-macro-transformer proc))` then
            // `(define-syntax foo t)`. Only already-executed defines are
            // visible (top-level and library bodies run form-by-form), which
            // is the same left-to-right visibility every global has.
            var bound_non_transformer = false;
            if (self.globals) |g| {
                const glk = globals_mod.acquireGlobalsRead(g);
                const gv = g.get(alias_name);
                globals_mod.releaseGlobalsRead(glk);
                if (gv) |v| {
                    if (types.isTransformer(v)) return v;
                    // The name resolves to a real value that is NOT a
                    // transformer (e.g. a procedure like `car`): this is
                    // statically wrong at run time too, so keep rejecting it
                    // even under analysis — the placeholder fallback below is
                    // only for names we genuinely cannot resolve.
                    bound_non_transformer = true;
                }
            }
            // kaappi#2007: `kaappi check` (and the LSP) execute nothing, so a
            // define/define-values that would bind this name to a Transformer
            // at run time never ran — the globals lookup above comes back
            // empty even for a program that compiles and runs cleanly. Flagging
            // it KP2001 is a false positive on a valid file. When analysing
            // (check_lint.active != null) rather than really compiling for
            // execution, and only when the name is otherwise unresolvable (not
            // a known non-transformer binding), accept the still-unresolved
            // alias as a benign placeholder macro instead of rejecting it. A
            // normal run never takes this branch: by the time this
            // define-syntax executes, the earlier define has run and the
            // transformer is in globals.
            if (check_lint.active != null and !bound_non_transformer)
                return makeCheckPlaceholderTransformer(self);
            return CompileError.InvalidSyntax;
        }
        if (!types.isPair(spec)) return CompileError.InvalidSyntax;
        const head = types.car(spec);
        if (!types.isSymbol(head)) return CompileError.InvalidSyntax;
        const head_name = types.symbolName(head);
        if (std.mem.eql(u8, head_name, "syntax-rules")) return parseSyntaxRules(self, spec, &.{});
        // SRFI 211: procedural transformer specs. Compared through the
        // hygiene strip like the compiler's other renamed-special-form
        // recognition — a syntax-rules template that emits one of these
        // forms may have renamed the head (it stays unrenamed only when
        // the primitives are visible as globals).
        const stripped_head = types.stripHygienicPrefix(head_name);
        const is_er = std.mem.eql(u8, stripped_head, "er-macro-transformer");
        if (is_er or std.mem.eql(u8, stripped_head, "lisp-transformer")) {
            const rest_spec = types.cdr(spec);
            if (!types.isPair(rest_spec) or types.cdr(rest_spec) != types.NIL)
                return CompileError.InvalidSyntax;
            const eval_fn = globals_mod.eval_datum_for_macro orelse return CompileError.InvalidSyntax;
            // Evaluated NOW, at macro-definition time, in the global
            // environment (phase separation: enclosing runtime locals have
            // no values at expansion time and are deliberately invisible).
            const proc = eval_fn(types.car(rest_spec)) catch |err| switch (err) {
                error.OutOfMemory => return CompileError.OutOfMemory,
                // kaappi#2007: SRFI 211 evaluates the transformer expression at
                // macro-definition time, so it may legally reference a global
                // that only gets bound when the program runs. `kaappi check`
                // executes nothing, so that global is unbound and the eval
                // fails — but the arity-checked spec is structurally valid and
                // the program compiles and runs. Under analysis accept it as a
                // placeholder rather than emit a KP2001 false positive; a real
                // run reaches here only when the eval genuinely succeeds.
                else => if (check_lint.active != null)
                    return makeCheckPlaceholderTransformer(self)
                else
                    return CompileError.InvalidSyntax,
            };
            if (!types.isProcedure(proc)) {
                if (check_lint.active != null) return makeCheckPlaceholderTransformer(self);
                return CompileError.InvalidSyntax;
            }
            var proc_root = proc;
            self.gc.pushRoot(&proc_root);
            const tx_val = self.gc.allocProceduralTransformer(
                if (is_er) .er_macro else .lisp_macro,
                proc_root,
            ) catch {
                self.gc.popRoot();
                return CompileError.OutOfMemory;
            };
            self.gc.popRoot();
            return tx_val;
        }
        if (std.mem.eql(u8, head_name, "begin") or std.mem.eql(u8, types.stripHygienicPrefix(head_name), "begin")) {
            // spec = (begin def1 def2 ... final-spec). Each def must be a
            // literal (define-syntax NAME SPEC); SPEC may itself need
            // further resolution (another macro-use, alias, or nested
            // begin), so it recurses through this same function --
            // yielding an already-parsed Transformer directly, with no
            // separate parse step needed here -- before being registered
            // transiently into `merged_macros`, visible to later defs and
            // the final spec within THIS resolution but never leaking
            // into the enclosing scope.
            var rest = types.cdr(spec);
            if (!types.isPair(rest)) return CompileError.InvalidSyntax;
            while (types.isPair(types.cdr(rest))) {
                const def = types.car(rest);
                if (!types.isPair(def)) return CompileError.InvalidSyntax;
                const def_head = types.car(def);
                if (!types.isSymbol(def_head) or !std.mem.eql(u8, types.symbolName(def_head), "define-syntax"))
                    return CompileError.InvalidSyntax;
                const def_rest1 = types.cdr(def);
                if (!types.isPair(def_rest1)) return CompileError.InvalidSyntax;
                const def_name_sym = types.car(def_rest1);
                if (!types.isSymbol(def_name_sym)) return CompileError.InvalidSyntax;
                const def_rest2 = types.cdr(def_rest1);
                if (!types.isPair(def_rest2)) return CompileError.InvalidSyntax;
                const def_spec_raw = types.car(def_rest2);
                const def_transformer = try resolveTransformerSpecRec(self, def_spec_raw, merged_macros, steps);
                // Root for the rest of this compile scope immediately --
                // it lives only in merged_macros/self.macros (plain Zig
                // hashmaps, not GC-scanned), matching compileDefineSyntax's
                // own top-level transformer rooting (#1401 pattern).
                // Nothing between the recursive call's return and this
                // line allocates via the GC.
                self.gc.extra_roots.append(self.gc.allocator, def_transformer) catch return CompileError.OutOfMemory;
                const def_name = types.symbolName(def_name_sym);
                merged_macros.put(def_name, def_transformer) catch return CompileError.OutOfMemory;

                // A begin-wrapped helper isn't just a resolution-time alias
                // target (the merged_macros entry above) -- its hygienically
                // mangled name can be referenced BY NAME from inside the
                // FINAL transformer's own template (this is exactly what
                // SRFI 148's em-syntax-rules-aux2 needs: it expands to
                // `(begin (define-syntax o spec) o)` where the surrounding
                // syntax-rules body ALSO calls `o` directly, e.g. `(ck s
                // "arg" (o) . q)`). That reference must keep resolving every
                // time the macro being defined here is later invoked, not
                // just while resolving THIS transformer-spec -- merged_macros
                // is local to this call and gone once it returns. So treat
                // this exactly like an ordinary define-syntax at the current
                // nesting depth: register in self.macros (undone at the
                // matching endBodyMacroScope in a body context, permanent at
                // top level -- recordBodyMacro is a no-op there, matching
                // compileDefineSyntax's own comment "define-syntax must
                // persist"), mirror the library-top-level lib_env storage,
                // and finalize hygiene bookkeeping the same way every other
                // Transformer object in this file does.
                if (self.lib_env) |env| {
                    const def_tx = types.toObject(def_transformer).as(types.Transformer);
                    def_tx.def_env = env;
                    def_tx.def_env_val = self.lib_env_val;
                    // #1961 (review): same old→young edge on the transformer
                    // as compileDefineSyntax's own def_env_val store above —
                    // begin-wrapped helper definitions are just as aliased.
                    self.gc.writeBarrier(types.toObject(def_transformer), self.lib_env_val);
                    globals_mod.assertEnvMapInvariant(env, self.lib_env_val); // #1962
                }
                try finalizeTransformer(self, def_transformer);
                try self.recordBodyMacro(def_name);
                self.macros.put(def_name, def_transformer) catch return CompileError.OutOfMemory;
                if (self.body_macro_depth == 0) {
                    if (self.lib_env) |env| {
                        env.put(def_name, def_transformer) catch return CompileError.OutOfMemory;
                        // #1961: same shared rule as compileDefineSyntax's
                        // own lib_env store above.
                        self.gc.envStoreBarrier(self.lib_env_val, def_transformer);
                    }
                }
                rest = types.cdr(rest);
            }
            spec = types.car(rest);
            continue;
        }
        const transformer = merged_macros.get(head_name) orelse return CompileError.InvalidSyntax;
        steps.* += 1;
        if (steps.* > MAX_MACRO_EXPANSION_DEPTH) return CompileError.InvalidSyntax;
        const use_check = expander.UseSiteBindingCheck{
            .ctx = @ptrCast(self),
            .resolve_fn = &resolveLocalSkipAliases,
            .frame_resolve_fn = &resolveSameFrameLocal,
        };
        self.gc.no_collect += 1;
        spec = expander.expandMacro(self.gc, spec, transformer, self.globals, merged_macros, use_check) catch |err| {
            self.gc.no_collect -= 1;
            return switch (err) {
                error.OutOfMemory => CompileError.OutOfMemory,
                error.ScopeTableFull, error.PatternTooComplex => CompileError.InternalLimit,
                error.NoMatchingPattern, error.EllipsisCountMismatch, error.EllipsisDepthMismatch, error.EllipsisNoPatternVariable => CompileError.InvalidSyntax,
                error.TransformerFailed => recordTransformerFailure(),
            };
        };
        self.gc.no_collect -= 1;
        if (expander.isUsertextPair(spec)) spec = expander.unwrapUsertext(spec);
        if (types.isPair(spec) or types.isVector(spec)) expander.stripUsertextMarkers(self.gc, spec);
    }
}

/// kaappi#2007: build a benign catch-all transformer for a transformer-spec
/// that `kaappi check`/the LSP cannot resolve because nothing has executed
/// (a runtime-bound Transformer alias, or an er/lisp-transformer expression
/// that references a not-yet-bound global). Equivalent to
/// `(syntax-rules () ((_ . rest) (if #f #f)))`: every use of the defined
/// keyword expands to void, so the macro use itself compiles cleanly during
/// analysis instead of surfacing as an "undefined variable" downstream. Only
/// ever called under check_lint.active — a normal run resolves the real
/// transformer. The returned Transformer is freshly allocated and unrooted,
/// exactly like parseSyntaxRules' result; compileDefineSyntax roots it via
/// extra_roots with nothing allocating in between (same contract).
fn makeCheckPlaceholderTransformer(self: *Compiler) CompileError!Value {
    const gc = self.gc;
    // Suppress collection while assembling this small transient spec so the
    // intermediate pairs/symbols need no manual rooting (mirrors the
    // no_collect window expandMacro uses); parseSyntaxRules copies every
    // slice with the raw allocator before it could collect anyway.
    gc.no_collect += 1;
    defer gc.no_collect -= 1;
    const underscore = gc.allocSymbol("_") catch return CompileError.OutOfMemory;
    const rest = gc.allocSymbol("rest") catch return CompileError.OutOfMemory;
    const pattern = gc.allocPair(underscore, rest) catch return CompileError.OutOfMemory; // (_ . rest)
    const if_sym = gc.allocSymbol("if") catch return CompileError.OutOfMemory;
    const template = gc.makeList(&.{ if_sym, types.FALSE, types.FALSE }) catch return CompileError.OutOfMemory; // (if #f #f)
    const rule = gc.makeList(&.{ pattern, template }) catch return CompileError.OutOfMemory; // ((_ . rest) (if #f #f))
    const sr = gc.allocSymbol("syntax-rules") catch return CompileError.OutOfMemory;
    const spec = gc.makeList(&.{ sr, types.NIL, rule }) catch return CompileError.OutOfMemory; // (syntax-rules () <rule>)
    return parseSyntaxRules(self, spec, &.{});
}

pub fn parseSyntaxRules(self: *Compiler, spec: Value, extra_bound: []const []const u8) CompileError!Value {
    if (!types.isPair(spec)) return CompileError.InvalidSyntax;
    const head = types.car(spec);
    if (!types.isSymbol(head)) return CompileError.InvalidSyntax;
    if (!std.mem.eql(u8, types.symbolName(head), "syntax-rules")) return CompileError.InvalidSyntax;

    const rest = types.cdr(spec);
    if (rest == types.NIL) return CompileError.InvalidSyntax;

    var custom_ellipsis: ?[]const u8 = null;
    var after_ellipsis = rest;
    // A generating macro may splice a user/pattern-var-supplied ellipsis
    // identifier into this position (mirrors the literals-list unwrap
    // below): when a nested syntax-rules template substitutes an outer
    // pattern variable here, NESTED_SR_FLAG's usertext-marking protocol
    // wraps the value so the generating macro's own expansion doesn't
    // re-walk it as template text. Unwrap it before checking whether this
    // is a bare custom-ellipsis symbol, or it's still a usertext pair (not
    // a symbol) and the ellipsis is silently missed, misparsing everything
    // after it as part of the literals list.
    const first_arg = expander.unwrapUsertext(types.car(rest));
    if (types.isSymbol(first_arg) and !types.isPair(first_arg)) {
        const name_str = types.symbolName(first_arg);
        if (!std.mem.eql(u8, name_str, "_")) {
            custom_ellipsis = name_str;
            after_ellipsis = types.cdr(rest);
            if (after_ellipsis == types.NIL) return CompileError.InvalidSyntax;
        }
    }

    const literals_list = types.car(after_ellipsis);
    const rules = types.cdr(after_ellipsis);

    // R7RS places no bound on a syntax-rules' literal or rule count, so
    // these grow past the old fixed 32-slot stack buffers (kaappi#2184): a
    // 33-rule dispatcher macro is legal and must compile, not fail with a
    // bare KP2001 that reads as "malformed macro". GC safety: the backing
    // stores use the raw allocator (never GC-triggering), nothing between
    // here and allocTransformer triggers a collection (unwrapUsertext /
    // validPatternGrammar / append allocate nothing on the GC heap), and
    // allocTransformer dupes all three slices with the raw allocator
    // before it can collect — so the element Values only need to survive
    // as subparts of the form being parsed. resolveTransformerSpecRec
    // additionally roots `spec`, but the body-scan caller in
    // compiler_lambda.zig does not, so do not add a GC-triggering call to
    // these loops without rooting the spec first.
    var literals: std.ArrayList(Value) = .empty;
    defer literals.deinit(self.gc.allocator);
    var lit = literals_list;
    while (lit != types.NIL) {
        if (!types.isPair(lit)) return CompileError.InvalidSyntax;
        // A generating macro may splice a user identifier into this spec's
        // literal list (SRFI 257's if-new-var) — unwrap the provenance
        // marker so the literal is the bare identifier.
        literals.append(self.gc.allocator, expander.unwrapUsertext(types.car(lit))) catch return CompileError.OutOfMemory;
        lit = types.cdr(lit);
    }

    var patterns: std.ArrayList(Value) = .empty;
    defer patterns.deinit(self.gc.allocator);
    var templates: std.ArrayList(Value) = .empty;
    defer templates.deinit(self.gc.allocator);
    var rule = rules;
    while (rule != types.NIL) {
        if (!types.isPair(rule)) return CompileError.InvalidSyntax;
        const r = types.car(rule);
        if (!types.isPair(r)) return CompileError.InvalidSyntax;
        const rule_pattern = types.car(r);
        // R7RS 4.3.2 (kaappi#2082): the <pattern> grammar admits at
        // most one <ellipsis> per list or vector pattern. A second one
        // at the same level is not in the grammar (SRFI 46 only widens
        // what may FOLLOW the single ellipsis); accepting it previously
        // split the input arbitrarily because the surplus ellipsis
        // tokens were counted as fixed tail elements by the matcher.
        if (!validPatternGrammar(rule_pattern, custom_ellipsis orelse "...", literals.items))
            return CompileError.InvalidSyntax;
        patterns.append(self.gc.allocator, rule_pattern) catch return CompileError.OutOfMemory;
        const r_rest = types.cdr(r);
        if (r_rest == types.NIL) return CompileError.InvalidSyntax;
        templates.append(self.gc.allocator, types.car(r_rest)) catch return CompileError.OutOfMemory;
        rule = types.cdr(rule);
    }

    if (patterns.items.len == 0) return CompileError.InvalidSyntax;

    // Transformer.num_rules is a u16; the old 32-slot cap made an overflow
    // unreachable, so guard the new unbounded path explicitly rather than
    // let allocTransformer's @intCast trap (ReleaseSafe panic) on a
    // 65k+-rule macro. No real program reaches this; it exists only to
    // keep the now-unbounded rule count from becoming a crash.
    if (patterns.items.len > std.math.maxInt(u16)) return CompileError.InvalidSyntax;

    const tx_val = self.gc.allocTransformer(
        literals.items,
        patterns.items,
        templates.items,
    ) catch return CompileError.OutOfMemory;
    const tx = types.toObject(tx_val).as(types.Transformer);
    if (custom_ellipsis) |ce| {
        tx.custom_ellipsis = ce;
    }
    // R7RS 4.3.2: record each literal's def-site binding slot (0xFFFF = unbound).
    // Binding identity — not just bound/unbound — is needed so that two
    // different bindings with the same name don't falsely match.
    if (literals.items.len > 0) {
        const slots = self.gc.allocator.alloc(u32, literals.items.len) catch return CompileError.OutOfMemory;
        for (literals.items, 0..) |lv, li| {
            slots[li] = if (types.isSymbol(lv)) blk: {
                const lname = types.symbolName(lv);
                // Resolve through the full lexical chain with the SAME rules
                // as the use-site check (resolveLocalSkipAliases): a literal
                // bound in an ENCLOSING function frame must record that
                // binding id, or a use in a nested lambda would compare
                // def=unbound vs use=bound and wrongly reject (SRFI 257's
                // if-new-var inside generated backtracking lambdas).
                const bid = resolveLocalSkipAliases(@ptrCast(self), lname);
                if (bid != expander.LITERAL_UNBOUND) break :blk bid;
                for (extra_bound) |eb| {
                    if (std.mem.eql(u8, eb, lname)) break :blk expander.LITERAL_BOUND_PENDING;
                }
                break :blk expander.LITERAL_UNBOUND;
            } else expander.LITERAL_UNBOUND;
        }
        tx.literal_bound = slots;
    }
    return tx_val;
}

/// R7RS 4.3.2 (kaappi#2082): the <pattern> grammar admits at most one
/// <ellipsis> per list or vector pattern; the matcher counts surplus
/// ellipsis tokens as fixed tail elements, so a pattern like `(a ... b ...)`
/// used to match with an arbitrary split instead of failing. Nested
/// list/vector sub-patterns are checked recursively -- an ellipsis inside
/// them belongs to their own level, so `((a ...) ...)` is legal. `ellipsis_name`
/// is the (possibly custom) ellipsis identifier; a symbol of that name listed
/// in `literals` is a literal, not an ellipsis (R7RS: a literal has priority
/// over the ellipsis).
fn validPatternGrammar(v: Value, ellipsis_name: []const u8, literals: []const Value) bool {
    if (types.isPair(v)) {
        var seen_ellipsis = false;
        var cur = v;
        var first = true;
        while (types.isPair(cur)) {
            const elem = expander.unwrapUsertext(types.car(cur));
            if (types.isSymbol(elem)) {
                const name = types.symbolName(elem);
                if (std.mem.eql(u8, name, ellipsis_name) and !literalNamed(literals, name)) {
                    // The ellipsis identifier only functions as the ellipsis
                    // when it FOLLOWS a pattern element -- the matcher checks
                    // element i+1, so a first-position ellipsis token is a
                    // plain pattern variable, never an ellipsis. This is what
                    // keeps srfi136's `(cname field (... ...))` guard and
                    // R7RS 4.3.2's own `(... ...)` escape-as-data legal.
                    if (!first) {
                        if (seen_ellipsis) return false;
                        seen_ellipsis = true;
                    }
                }
            } else if (types.isPair(elem) or types.isVector(elem)) {
                if (!validPatternGrammar(elem, ellipsis_name, literals)) return false;
            }
            first = false;
            cur = types.cdr(cur);
        }
        // Dotted tail: a plain pattern, not a list element. An ellipsis
        // token there (`(a ... . ...)`) is outside the grammar too, and a
        // vector dotted tail (`(_ . #(a ... b ...))`) is a vector pattern
        // the matcher recurses into, so it must be validated like any
        // other vector pattern. (A pair dotted tail is impossible here:
        // the while loop above only exits once cur is no longer a pair.)
        if (cur != types.NIL) {
            if (types.isSymbol(cur)) {
                const name = types.symbolName(cur);
                if (std.mem.eql(u8, name, ellipsis_name) and !literalNamed(literals, name)) return false;
            } else if (types.isVector(cur)) {
                return validPatternGrammar(cur, ellipsis_name, literals);
            }
        }
        return true;
    }
    if (types.isVector(v)) {
        const vec = types.toObject(v).as(types.Vector);
        var seen_ellipsis = false;
        var first = true;
        for (vec.data) |elem_raw| {
            const elem = expander.unwrapUsertext(elem_raw);
            if (types.isSymbol(elem)) {
                const name = types.symbolName(elem);
                if (std.mem.eql(u8, name, ellipsis_name) and !literalNamed(literals, name)) {
                    if (!first) {
                        if (seen_ellipsis) return false;
                        seen_ellipsis = true;
                    }
                }
            } else if (types.isPair(elem) or types.isVector(elem)) {
                if (!validPatternGrammar(elem, ellipsis_name, literals)) return false;
            }
            first = false;
        }
        return true;
    }
    return true;
}

fn literalNamed(literals: []const Value, name: []const u8) bool {
    for (literals) |lit| {
        if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Hygienic captured-local injection
// ---------------------------------------------------------------------------
