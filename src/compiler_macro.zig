const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const expander = @import("expander.zig");
const globals_mod = @import("globals.zig");
const ir_mod = @import("ir.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;

const MAX_MACRO_EXPANSION_DEPTH: u16 = 256;
const MAX_MACRO_EXPANSION_STEPS: u32 = 10_000;

/// 128 levels is safe because the expander shares pattern-variable subtrees
/// (a == b short-circuits at the shared node), so only the short template
/// spine is actually traversed.
fn valuesStructurallyEqual(a: Value, b: Value, depth: u16) bool {
    if (a == b) return true;
    if (depth == 0) return false;
    if (types.isPair(a) and types.isPair(b))
        return valuesStructurallyEqual(types.car(a), types.car(b), depth - 1) and
            valuesStructurallyEqual(types.cdr(a), types.cdr(b), depth - 1);
    return false;
}

fn resolveLocalSkipAliases(ctx: ?*const anyopaque, name: []const u8) u32 {
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

pub fn expandAndCompileMacroUse(self: *Compiler, expr: Value, name: []const u8, transformer: Value, dst: u16, is_tail: bool) CompileError!void {
    if (self.macro_expansion_depth >= MAX_MACRO_EXPANSION_DEPTH or
        self.macro_expansion_steps >= MAX_MACRO_EXPANSION_STEPS)
    {
        return CompileError.MacroExpansionLimit;
    }
    self.macro_expansion_depth += 1;
    self.macro_expansion_steps += 1;
    defer self.macro_expansion_depth -= 1;
    // Build merged macro view including parent scopes
    var merged_macros = std.StringHashMap(Value).init(self.gc.allocator);
    defer merged_macros.deinit();
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
    const tx = types.toObject(transformer).as(types.Transformer);
    // Temporarily add/modify globals so the expander doesn't
    // rename template free references.
    const TempGlobal = struct { name: []const u8, old_val: ?Value, was_present: bool };
    var temp_globals: [128]TempGlobal = undefined;
    var temp_global_count: usize = 0;
    // Track non-procedure global free vars that need local injection
    // to prevent shadowing by use-site locals (R7RS 4.3.1).
    var global_free_names: [64][]const u8 = undefined;
    var global_free_count: usize = 0;
    if (self.globals) |g| {
        // The sentinel puts below structurally mutate the globals
        // map when g is the VM's shared one — exclude SRFI-18
        // child-thread readers for the whole dance (#958). glk is
        // non-null exactly when g is the current thread's shared
        // globals map.
        const glk = globals_mod.acquireGlobalsWrite(g);
        defer globals_mod.releaseGlobalsWrite(glk);
        for (tx.captured_locals) |cap| {
            if (temp_global_count < 128) {
                if (g.get(cap.name)) |gval| {
                    temp_globals[temp_global_count] = .{ .name = cap.name, .old_val = gval, .was_present = true };
                    temp_global_count += 1;
                    _ = g.remove(cap.name);
                }
            }
        }
        if (tx.def_env) |env| {
            var env_it = env.iterator();
            while (env_it.next()) |entry| {
                if (!g.contains(entry.key_ptr.*) and temp_global_count < 128) {
                    temp_globals[temp_global_count] = .{ .name = entry.key_ptr.*, .old_val = null, .was_present = false };
                    temp_global_count += 1;
                    try g.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
        // Temporarily mark non-procedure free globals as VOID so
        // renameForHygiene preserves them. Only mark identifiers that
        // were bound at macro definition time (bound_free_refs) —
        // template-introduced identifiers that coincidentally share a
        // name with a later user define must still be renamed (#1208).
        if (globals_mod.globals_ctx) |gctx| {
            for (tx.bound_free_refs) |cname| {
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
                        if (temp_global_count < 128) {
                            temp_globals[temp_global_count] = .{ .name = cname, .old_val = in_g, .was_present = in_g != null };
                            temp_global_count += 1;
                            try g.put(cname, types.VOID);
                        }
                        // Track for local injection after expansion
                        if (global_free_count < 64) {
                            global_free_names[global_free_count] = cname;
                            global_free_count += 1;
                        }
                    }
                }
            }
        }
    }
    defer if (self.globals) |g| {
        const glk = globals_mod.acquireGlobalsWrite(g);
        var tgi = temp_global_count;
        while (tgi > 0) {
            tgi -= 1;
            const tg = temp_globals[tgi];
            if (tg.was_present) {
                g.put(tg.name, tg.old_val.?) catch {};
            } else {
                _ = g.remove(tg.name);
            }
        }
        globals_mod.releaseGlobalsWrite(glk);
    };
    // Suppress GC during expansion: the expanded form isn't
    // rooted until pushRoot below, so a collection triggered
    // by allocPair inside expandMacro could free AST nodes
    // that the partially-built result references.
    self.gc.no_collect += 1;
    const use_check = expander.UseSiteBindingCheck{
        .ctx = @ptrCast(self),
        .resolve_fn = &resolveLocalSkipAliases,
    };
    const expanded = expander.expandMacro(self.gc, expr, transformer, self.globals, &merged_macros, use_check) catch |err| {
        self.gc.no_collect -= 1;
        return switch (err) {
            error.OutOfMemory => CompileError.OutOfMemory,
            error.ScopeTableFull, error.PatternTooComplex => CompileError.InternalLimit,
            error.NoMatchingPattern, error.EllipsisCountMismatch, error.EllipsisDepthMismatch => CompileError.InvalidSyntax,
        };
    };
    var expanded_root = expanded;
    self.gc.pushRoot(&expanded_root);
    defer self.gc.popRoot();
    self.gc.no_collect -= 1;
    try self.scanSetTargets(expanded_root);
    const saved_locals_len = self.locals.items.len;
    try injectHygienicCapturedLocals(self, expanded_root, tx.captured_locals);
    // Inject non-procedure global free vars as locals so
    // use-site locals don't shadow the definition-site
    // global binding (R7RS 4.3.1 referential transparency).
    // Alias registers are freed after the expansion is compiled: leaking
    // them breaks the balanced-register contract expression compilation
    // relies on — a call site allocates CONTIGUOUS argument registers, so
    // a leak inside one argument shifts every later argument slot while
    // the call still reads the original window (found by the Kaappi-vs-
    // Chibi differential oracle, #1396).
    var injected_reg_count: u16 = 0;
    for (global_free_names[0..global_free_count]) |gname| {
        // Skip if already covered by captured_locals
        var already_captured = false;
        for (tx.captured_locals) |cap| {
            if (std.mem.eql(u8, cap.name, gname)) {
                already_captured = true;
                break;
            }
        }
        if (already_captured) continue;
        // Load the global value into a fresh register
        const gslot = self.allocReg() catch continue;
        injected_reg_count += 1;
        const gsym = self.gc.allocSymbol(gname) catch continue;
        const gsym_idx = self.addConstant(gsym) catch continue;
        self.emitOp(.get_global) catch continue;
        self.emitU16(gslot) catch continue;
        self.emitU16(gsym_idx) catch continue;
        try self.locals.append(self.gc.allocator, .{
            .name = gname,
            .depth = self.scope_depth,
            .slot = gslot,
            .binding_id = compiler_mod.freshBindingId(),
            .is_global_alias = true,
        });
    }
    // R7RS 4.3.1: let-syntax transformers resolve free macro references
    // from the definition-site environment, not the use-site environment.
    // Temporarily swap sibling keywords to their outer values.
    const peer_names = tx.let_syntax_peer_names;
    const peer_outer = tx.let_syntax_peer_vals;
    std.debug.assert(peer_names.len == peer_outer.len);
    const saved_peer = if (peer_names.len > 0)
        self.gc.allocator.alloc(?Value, peer_names.len) catch return CompileError.OutOfMemory
    else
        null;
    defer if (saved_peer) |sp| self.gc.allocator.free(sp);
    if (saved_peer) |sp| {
        for (peer_names, peer_outer, 0..) |pn, pv, i| {
            sp[i] = self.macros.get(pn);
            if (pv != types.NIL) {
                self.macros.put(pn, pv) catch {};
            } else {
                _ = self.macros.remove(pn);
            }
        }
    }
    // Fixed-point detection: if the expansion is structurally identical to
    // the input (e.g. SRFI-219 rule 3: (define x e) → (define x e)) AND the
    // keyword is a built-in special form, suppress macro re-expansion so the
    // built-in handler takes over.  For non-special-form macros (e.g. a
    // degenerate (loop) → (loop)), let the expansion-limit catch it instead.
    const is_fixed_point = valuesStructurallyEqual(expanded_root, expr, 128) and
        ir_mod.isSpecialForm(types.stripHygienicPrefix(name));
    const saved_suppress = self.suppress_macro_name;
    if (is_fixed_point) self.suppress_macro_name = name;
    defer self.suppress_macro_name = saved_suppress;

    const result_err = self.compileExpr(expanded_root, dst, is_tail);
    if (saved_peer) |sp| {
        for (peer_names, 0..) |pn, i| {
            if (sp[i]) |old| {
                self.macros.put(pn, old) catch {};
            } else {
                _ = self.macros.remove(pn);
            }
        }
    }
    // Remove injected locals and rewind their alias registers: the
    // expansion's result now lives in dst, so the aliases are dead, and
    // compileExpr itself is register-balanced, making the LIFO rewind safe.
    while (self.locals.items.len > saved_locals_len) {
        _ = self.locals.pop();
    }
    while (injected_reg_count > 0) : (injected_reg_count -= 1) {
        self.freeReg();
    }
    return result_err;
}

// ---------------------------------------------------------------------------
// Macro definition forms
// ---------------------------------------------------------------------------

pub fn compileDefineSyntax(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (types.isEnvironment(self.lib_env_val) and types.toEnvironment(self.lib_env_val).immutable)
        return CompileError.InvalidSyntax;
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const keyword = types.car(args);
    if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const transformer_spec = types.car(rest);

    const transformer = parseSyntaxRules(self, transformer_spec, &.{}) catch return CompileError.InvalidSyntax;

    // Root the transformer for the rest of this top-level compile: it lives
    // only in the compiler-local macro map, which the GC cannot see, and a
    // body-local macro must survive collections triggered while compiling
    // sibling forms that use it (#1401). Released by the extra_roots
    // truncation in compileExpression* when compilation finishes.
    self.gc.extra_roots.append(self.gc.allocator, transformer) catch return CompileError.OutOfMemory;

    const tx = types.toObject(transformer).as(types.Transformer);
    if (self.lib_env) |env| {
        tx.def_env = env;
        tx.def_env_val = self.lib_env_val;
    }

    try captureLocalsOnTransformer(self, transformer);
    try computeBoundFreeRefs(self, transformer);

    const name = types.symbolName(keyword);
    try self.recordBodyMacro(name);
    self.macros.put(name, transformer) catch return CompileError.OutOfMemory;

    // A define-syntax at a library's top level (not nested in a lambda/let
    // body scope) is also stored in the library environment (issue #877).
    if (self.body_macro_depth == 0) {
        if (self.lib_env) |env| {
            env.put(name, transformer) catch return CompileError.OutOfMemory;
        }
    }

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
    var count_list = bindings;
    while (count_list != types.NIL) {
        if (!types.isPair(count_list)) return CompileError.InvalidSyntax;
        bind_count += 1;
        count_list = types.cdr(count_list);
    }

    var kw_names: std.ArrayList([]const u8) = .empty;
    defer kw_names.deinit(self.gc.allocator);
    kw_names.ensureTotalCapacity(self.gc.allocator, bind_count) catch return CompileError.OutOfMemory;
    var tx_vals: std.ArrayList(Value) = .empty;
    defer tx_vals.deinit(self.gc.allocator);
    tx_vals.ensureTotalCapacity(self.gc.allocator, bind_count) catch return CompileError.OutOfMemory;
    var roots_pushed: usize = 0;

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        const keyword = types.car(binding);
        if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
        const binding_rest = types.cdr(binding);
        if (!types.isPair(binding_rest)) return CompileError.InvalidSyntax;
        const transformer_spec = types.car(binding_rest);
        tx_vals.appendAssumeCapacity(parseSyntaxRules(self, transformer_spec, &.{}) catch
            return CompileError.InvalidSyntax);
        self.gc.pushRoot(&tx_vals.items[tx_vals.items.len - 1]);
        roots_pushed += 1;
        kw_names.appendAssumeCapacity(types.symbolName(keyword));
        binding_list = types.cdr(binding_list);
    }
    defer for (0..roots_pushed) |_| self.gc.popRoot();

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
        try captureLocalsOnTransformer(self, transformer);
        try computeBoundFreeRefs(self, transformer);
        const tx = types.toObject(transformer).as(types.Transformer);
        tx.let_syntax_peer_names = self.gc.allocator.dupe([]const u8, peer_snap_names) catch return CompileError.OutOfMemory;
        tx.let_syntax_peer_vals = self.gc.allocator.dupe(Value, peer_snap_vals) catch return CompileError.OutOfMemory;
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

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        const keyword = types.car(binding);
        if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
        const binding_rest = types.cdr(binding);
        if (!types.isPair(binding_rest)) return CompileError.InvalidSyntax;
        const transformer_spec = types.car(binding_rest);
        const transformer = parseSyntaxRules(self, transformer_spec, &.{}) catch return CompileError.InvalidSyntax;
        const name = types.symbolName(keyword);

        // Root for the rest of the compile — see compileDefineSyntax (#1401).
        self.gc.extra_roots.append(self.gc.allocator, transformer) catch return CompileError.OutOfMemory;

        saved_names.append(self.gc.allocator, name) catch return CompileError.OutOfMemory;
        saved_values.append(self.gc.allocator, self.macros.get(name)) catch return CompileError.OutOfMemory;
        try captureLocalsOnTransformer(self, transformer);
        try computeBoundFreeRefs(self, transformer);
        self.macros.put(name, transformer) catch return CompileError.OutOfMemory;
        binding_list = types.cdr(binding_list);
    }

    try compileSyntaxBody(self, body, dst, is_tail);
    restoreMacros(self, saved_names.items, saved_values.items);
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
    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        current = types.cdr(current);
        const tail = is_tail and current == types.NIL;
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
    }
    if (bound_count == 0) return;
    tx.bound_free_refs = self.gc.allocator.alloc([]const u8, bound_count) catch
        return CompileError.OutOfMemory;
    @memcpy(tx.bound_free_refs, bound[0..bound_count]);
}

// ---------------------------------------------------------------------------
// Syntax-rules parsing
// ---------------------------------------------------------------------------

pub fn parseSyntaxRules(self: *Compiler, spec: Value, extra_bound: []const []const u8) CompileError!Value {
    if (!types.isPair(spec)) return CompileError.InvalidSyntax;
    const head = types.car(spec);
    if (!types.isSymbol(head)) return CompileError.InvalidSyntax;
    if (!std.mem.eql(u8, types.symbolName(head), "syntax-rules")) return CompileError.InvalidSyntax;

    const rest = types.cdr(spec);
    if (rest == types.NIL) return CompileError.InvalidSyntax;

    var custom_ellipsis: ?[]const u8 = null;
    var after_ellipsis = rest;
    const first_arg = types.car(rest);
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

    var literals_buf: [32]Value = undefined;
    var lit_count: usize = 0;
    var lit = literals_list;
    while (lit != types.NIL) {
        if (!types.isPair(lit)) return CompileError.InvalidSyntax;
        if (lit_count >= 32) return CompileError.InvalidSyntax;
        literals_buf[lit_count] = types.car(lit);
        lit_count += 1;
        lit = types.cdr(lit);
    }

    var patterns_buf: [32]Value = undefined;
    var templates_buf: [32]Value = undefined;
    var rule_count: usize = 0;
    var rule = rules;
    while (rule != types.NIL) {
        if (!types.isPair(rule)) return CompileError.InvalidSyntax;
        const r = types.car(rule);
        if (!types.isPair(r)) return CompileError.InvalidSyntax;
        if (rule_count >= 32) return CompileError.InvalidSyntax;
        patterns_buf[rule_count] = types.car(r);
        const r_rest = types.cdr(r);
        if (r_rest == types.NIL) return CompileError.InvalidSyntax;
        templates_buf[rule_count] = types.car(r_rest);
        rule_count += 1;
        rule = types.cdr(rule);
    }

    if (rule_count == 0) return CompileError.InvalidSyntax;

    const tx_val = self.gc.allocTransformer(
        literals_buf[0..lit_count],
        patterns_buf[0..rule_count],
        templates_buf[0..rule_count],
    ) catch return CompileError.OutOfMemory;
    const tx = types.toObject(tx_val).as(types.Transformer);
    if (custom_ellipsis) |ce| {
        tx.custom_ellipsis = ce;
    }
    // R7RS 4.3.2: record each literal's def-site binding slot (0xFFFF = unbound).
    // Binding identity — not just bound/unbound — is needed so that two
    // different bindings with the same name don't falsely match.
    if (lit_count > 0) {
        const slots = self.gc.allocator.alloc(u32, lit_count) catch return CompileError.OutOfMemory;
        for (literals_buf[0..lit_count], 0..) |lv, li| {
            slots[li] = if (types.isSymbol(lv)) blk: {
                const lname = types.symbolName(lv);
                if (self.resolveBindingId(lname)) |bid| break :blk bid;
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

// ---------------------------------------------------------------------------
// Hygienic captured-local injection
// ---------------------------------------------------------------------------

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
            var already = false;
            for (self.locals.items) |loc| {
                if (std.mem.eql(u8, loc.name, name)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                try self.locals.append(self.gc.allocator, .{
                    .name = name,
                    .depth = self.scope_depth,
                    .slot = cap.slot,
                    .binding_id = compiler_mod.freshBindingId(),
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
// Free-reference collection for macro hygiene
// ---------------------------------------------------------------------------

pub fn collectSymbols(expr: Value, out: *[64][]const u8, count: *usize) bool {
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
        if (!collectSymbols(types.car(expr), out, count)) return false;
        return collectSymbols(types.cdr(expr), out, count);
    }
    return true;
}

pub fn collectFreeRefs(template: Value, pat_vars: []const []const u8, literals: []const Value, out: *[64][]const u8, count: *usize) bool {
    return collectFreeRefsWithLocals(template, pat_vars, literals, &.{}, out, count);
}

fn collectFreeRefsWithLocals(template: Value, pat_vars: []const []const u8, literals: []const Value, local_binds: []const []const u8, out: *[64][]const u8, count: *usize) bool {
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
                    var binds = types.car(bab);
                    while (types.isPair(binds)) {
                        const b = types.car(binds);
                        if (types.isPair(b)) {
                            const bname = types.car(b);
                            if (types.isSymbol(bname) and let_count < 16) {
                                let_names[let_count] = types.symbolName(bname);
                                let_count += 1;
                            }
                            const init_rest2 = types.cdr(b);
                            if (init_rest2 != types.NIL and types.isPair(init_rest2))
                                if (!collectFreeRefsWithLocals(types.car(init_rest2), pat_vars, literals, local_binds, out, count)) return false;
                        }
                        binds = types.cdr(binds);
                    }
                    if (!collectFreeRefsWithLocals(types.cdr(bab), pat_vars, literals, let_names[0..let_count], out, count)) return false;
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
                var params = types.car(rest);
                while (types.isPair(params)) {
                    const pp = types.car(params);
                    if (types.isSymbol(pp) and lam_count < 16) {
                        lam_names[lam_count] = types.symbolName(pp);
                        lam_count += 1;
                    }
                    params = types.cdr(params);
                }
                if (types.isSymbol(params) and lam_count < 16) {
                    lam_names[lam_count] = types.symbolName(params);
                    lam_count += 1;
                }
                if (!collectFreeRefsWithLocals(types.cdr(rest), pat_vars, literals, lam_names[0..lam_count], out, count)) return false;
            }
            return true;
        }
        if (std.mem.eql(u8, hname, "define")) {
            if (rest != types.NIL and types.isPair(rest))
                if (!collectFreeRefsWithLocals(types.cdr(rest), pat_vars, literals, local_binds, out, count)) return false;
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
                var sr_rules = types.cdr(rest);
                while (types.isPair(sr_rules)) {
                    const sr_rule = types.car(sr_rules);
                    if (types.isPair(sr_rule)) {
                        if (!collectSymbols(types.car(sr_rule), @ptrCast(&sr_names), &sr_count)) return false;
                    }
                    sr_rules = types.cdr(sr_rules);
                }
                if (!collectFreeRefsWithLocals(rest, pat_vars, literals, sr_names[0..sr_count], out, count)) return false;
            }
            return true;
        }
    }
    if (!collectFreeRefsWithLocals(head, pat_vars, literals, local_binds, out, count)) return false;
    return collectFreeRefsWithLocals(rest, pat_vars, literals, local_binds, out, count);
}

fn isLetForm(name: []const u8) bool {
    return std.mem.eql(u8, name, "let") or std.mem.eql(u8, name, "let*") or
        std.mem.eql(u8, name, "letrec") or std.mem.eql(u8, name, "letrec*");
}
