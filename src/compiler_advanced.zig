const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const conditionals = @import("compiler_conditionals.zig");
const expander = @import("expander.zig");
const globals_mod = @import("globals.zig");
const Value = types.Value;
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;

// -- Advanced expression forms --

/// Compile (guard (var clause ...) body ...)
///
/// Transforms into:
///   (call-with-escape-continuation
///     (lambda (gk)
///       (with-exception-handler
///         (lambda (var)
///           (%unwind-to-escape gk)
///           (gk (cond clause ... [else (raise-continuable var)])))
///         (lambda () body ...))))
///
/// The `%unwind-to-escape` is what puts the clauses in the right dynamic
/// environment. R7RS 4.2.7 evaluates them "with the continuation and dynamic
/// environment of the guard expression", but a handler runs at the raise point,
/// where every `parameterize`/`dynamic-wind` extent entered since is still live
/// — so those extents have to be left before the `cond` runs, not after it
/// produces a value (#1988). A plain `raise` hides this by unwinding before the
/// handler is called at all; the `raise-continuable` a declining inner `guard`
/// issues does not, and the intervening extent leaks into the outer guard's
/// clauses.
///
/// Unwinding the dynamic environment without also escaping looks redundant —
/// invoking `gk` would do both — but the escape must come after the clauses,
/// not before: a clause may reinstate a continuation captured inside the guard
/// body, and this VM cannot resume one whose native frame has already returned
/// (`(srfi 255)`'s restarters are exactly that shape). Splitting the two halves
/// keeps those frames alive across the clauses. By the time `gk` is invoked the
/// wind stack is already at its target, so the escape runs no thunk twice.
///
/// Known deviation: when no clause matches, R7RS re-raises in the dynamic
/// environment of the original raise. Here the environment has already been
/// unwound to the guard's, and getting back needs a re-entrant continuation
/// captured under the native raise frame — the resume this VM cannot do. R7RS's
/// own sample implementation relies on precisely that, and ported here verbatim
/// it corrupts the frame it returns into. The re-raise therefore happens in the
/// guard's environment, which is what a plain `raise` already does here.
pub fn compileGuard(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const guard_clause = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;
    if (!types.isPair(guard_clause)) return CompileError.InvalidSyntax;

    const var_sym = types.car(guard_clause);
    if (!types.isSymbol(var_sym)) return CompileError.InvalidSyntax;
    const clauses = types.cdr(guard_clause);

    // Build the cond clauses list, adding (else (raise var)) if no else present
    var has_else = false;
    var clause_check = clauses;
    while (clause_check != types.NIL) {
        if (!types.isPair(clause_check)) break;
        const cl = types.car(clause_check);
        if (types.isPair(cl)) {
            const test_expr = types.car(cl);
            if (types.isSymbol(test_expr) and std.mem.eql(u8, types.symbolName(test_expr), "else")) {
                has_else = true;
                break;
            }
        }
        clause_check = types.cdr(clause_check);
    }

    const gc = self.gc;

    // Build the desugared form with collection disabled: every intermediate
    // below is a fresh unrooted pair. The scoped defer restores the counter
    // on every path; leaking an increment would disable collection for the
    // rest of the process.
    const form: Value = blk: {
        gc.no_collect += 1;
        defer gc.no_collect -= 1;

        var cond_clauses = clauses;
        if (!has_else) {
            const raise_sym = gc.allocSymbol("raise-continuable") catch return CompileError.OutOfMemory;
            const raise_call = gc.allocPair(raise_sym, gc.allocPair(var_sym, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            const else_sym = gc.allocSymbol("else") catch return CompileError.OutOfMemory;
            const else_clause = gc.allocPair(else_sym, gc.allocPair(raise_call, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            cond_clauses = appendToList(self, clauses, else_clause) catch |err| return switch (err) {
                error.InvalidSyntax => CompileError.InvalidSyntax,
                else => CompileError.OutOfMemory,
            };
        }

        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const gk_counter = struct {
            var n: u32 = 0;
        };
        gk_counter.n += 1;
        var gk_buf: [32]u8 = undefined;
        const gk_name = std.fmt.bufPrint(&gk_buf, "__gk{d}", .{gk_counter.n}) catch "__gk";
        const gk = gc.allocSymbol(gk_name) catch return CompileError.OutOfMemory;

        const cond_sym = gc.allocSymbol("cond") catch return CompileError.OutOfMemory;
        const cond_form = gc.allocPair(cond_sym, cond_clauses) catch return CompileError.OutOfMemory;
        const k_call = gc.allocPair(gk, gc.allocPair(cond_form, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        // (%unwind-to-escape gk) — leave every extent entered since the guard
        // before the cond runs, so the clauses see the guard's own dynamic
        // environment (#1988).
        const unwind_sym = globals_mod.baseBindingSymbol(gc, "%unwind-to-escape") catch return CompileError.OutOfMemory;
        const unwind_call = gc.allocPair(unwind_sym, gc.allocPair(gk, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const h_body = gc.allocPair(unwind_call, gc.allocPair(k_call, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const h_formals = gc.allocPair(var_sym, types.NIL) catch return CompileError.OutOfMemory;
        const handler = gc.allocPair(lambda_sym, gc.allocPair(h_formals, h_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const weh_sym = gc.allocSymbol("with-exception-handler") catch return CompileError.OutOfMemory;
        const weh = gc.allocPair(weh_sym, gc.allocPair(handler, gc.allocPair(thunk, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const outer = gc.allocPair(lambda_sym, gc.allocPair(gc.allocPair(gk, types.NIL) catch return CompileError.OutOfMemory, gc.allocPair(weh, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const ec_sym = gc.allocSymbol("call-with-escape-continuation") catch return CompileError.OutOfMemory;
        break :blk gc.allocPair(ec_sym, gc.allocPair(outer, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    };

    return self.compileDesugared(form, dst, is_tail);
}

/// Append an element to the end of a proper list, returning a new list.
pub fn appendToList(self: *Compiler, lst: Value, elem: Value) !Value {
    if (lst == types.NIL) {
        return self.gc.allocPair(elem, types.NIL);
    }
    if (!types.isPair(lst)) return error.InvalidSyntax;
    const head = types.car(lst);
    const tail = try appendToList(self, types.cdr(lst), elem);
    return self.gc.allocPair(head, tail);
}

/// Compile (case key ((datum ...) expr ...) ... [(else expr ...)])
///
/// Strategy: compile key to a temp register, then for each clause
/// compare key against each datum using eqv?, jumping to the clause body
/// on match. After each clause body, jump to end. else clause is unconditional.
pub fn compileCase(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const key_expr = types.car(args);
    const clauses = types.cdr(args);

    // Compile key expression into a dedicated register
    const key_reg = try self.allocReg();
    try self.compileExprViaIR(key_expr, key_reg, false);

    var end_jumps: std.ArrayList(usize) = .empty;
    defer end_jumps.deinit(self.gc.allocator);
    var current = compiler_mod.SpineWalk.init(clauses);
    var had_else = false;

    while (current.cur != types.NIL) : (current.next()) {
        if (!types.isPair(current.cur)) return CompileError.InvalidSyntax;
        if (current.cyclic()) return compiler_mod.circularFormError();
        const clause = types.car(current.cur);
        if (!types.isPair(clause)) return CompileError.InvalidSyntax;

        const datums = types.car(clause);
        const clause_body = types.cdr(clause);

        // Check for else clause
        if (types.isSymbol(datums) and std.mem.eql(u8, types.symbolName(datums), "else")) {
            // (else => proc): apply proc to the key value. `=>` is
            // recognized by its stripped name (a template-introduced arrow
            // is hygiene-renamed, kaappi#2074) and a renamed arrow is
            // always an arrow; a bare `=>` keeps the lexical-shadow check.
            if (types.isPair(clause_body)) {
                const maybe_arrow = types.car(clause_body);
                if (types.isSymbol(maybe_arrow)) {
                    const arrow_raw = types.symbolName(maybe_arrow);
                    const arrow_eff = types.stripHygienicPrefix(arrow_raw);
                    if (std.mem.eql(u8, arrow_eff, "=>") and
                        (arrow_eff.len != arrow_raw.len or
                            (self.resolveLocal(arrow_raw) == null and (try self.resolveUpvalue(arrow_raw)) == null)))
                    {
                        const arrow_rest = types.cdr(clause_body);
                        if (!types.isPair(arrow_rest)) return CompileError.InvalidSyntax;
                        try conditionals.emitArrowCall(self, key_reg, types.car(arrow_rest), dst, is_tail);
                        had_else = true;
                        break;
                    }
                }
            }
            try conditionals.compileCondBody(self, clause_body, dst, is_tail);
            had_else = true;
            break;
        }

        // Empty datum list (() body) is allowed by R7RS — dead code, skip
        if (datums == types.NIL) continue;

        // For each datum in the clause, compare with key
        // If any matches, jump to clause body
        if (!types.isPair(datums)) return CompileError.InvalidSyntax;

        var body_jumps: std.ArrayList(usize) = .empty;
        defer body_jumps.deinit(self.gc.allocator);
        var datum_list = datums;

        // Allocate 3 contiguous temp registers for eqv? calls:
        // cmp_base (function + result), cmp_base+1 (arg1), cmp_base+2 (arg2)
        const eqv_sym = self.gc.allocSymbol("eqv?") catch return CompileError.OutOfMemory;
        const eqv_sym_idx = try self.addConstant(eqv_sym);
        const cmp_base = try self.allocReg();
        const cmp_arg1 = try self.allocReg();
        const cmp_arg2 = try self.allocReg();

        while (datum_list != types.NIL) {
            if (!types.isPair(datum_list)) return CompileError.InvalidSyntax;
            const datum = types.car(datum_list);
            datum_list = types.cdr(datum_list);

            const datum_idx = try self.addConstant(datum);

            // Set up eqv?(key, datum) call using pre-allocated registers
            try self.emitOp(.move);
            try self.emitU16(cmp_arg1);
            try self.emitU16(key_reg);
            try self.emitOp(.load_const);
            try self.emitU16(cmp_arg2);
            try self.emitU16(datum_idx);
            try self.emitOp(.call_global);
            try self.emitU16(cmp_base);
            try self.emitU16(eqv_sym_idx);
            try self.emit(2);

            // jump_true to clause body (result is in cmp_base)
            try self.emitOp(.jump_true);
            try self.emitU16(cmp_base);
            body_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
            try self.emitI16(0);
        }

        self.freeReg(); // cmp_arg2
        self.freeReg(); // cmp_arg1
        self.freeReg(); // cmp_base

        // No datum matched — jump to next clause
        try self.emitOp(.jump);
        const next_clause_jump = self.currentOffset();
        try self.emitI16(0);

        // Patch body jumps to here (start of clause body)
        for (body_jumps.items) |j| {
            try self.patchJump(j);
        }

        // Check for => form: ((datum ...) => proc)
        if (clause_body != types.NIL and types.isPair(clause_body)) {
            const maybe_arrow = types.car(clause_body);
            if (types.isSymbol(maybe_arrow)) {
                const arrow_raw = types.symbolName(maybe_arrow);
                const arrow_eff = types.stripHygienicPrefix(arrow_raw);
                if (std.mem.eql(u8, arrow_eff, "=>") and
                    (arrow_eff.len != arrow_raw.len or
                        (self.resolveLocal(arrow_raw) == null and (try self.resolveUpvalue(arrow_raw)) == null)))
                {
                    const arrow_rest = types.cdr(clause_body);
                    if (arrow_rest == types.NIL or !types.isPair(arrow_rest)) return CompileError.InvalidSyntax;
                    try conditionals.emitArrowCall(self, key_reg, types.car(arrow_rest), dst, is_tail);

                    try self.emitOp(.jump);
                    end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
                    try self.emitI16(0);

                    try self.patchJump(next_clause_jump);
                    continue;
                }
            }
        }

        // Compile clause body
        try conditionals.compileCondBody(self, clause_body, dst, is_tail);

        // Jump to end
        try self.emitOp(.jump);
        end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
        try self.emitI16(0);

        // Patch next clause jump
        try self.patchJump(next_clause_jump);
    }

    // If no else clause, result is void
    if (!had_else) {
        try self.emitOp(.load_void);
        try self.emitU16(dst);
    }

    // Patch all end jumps
    for (end_jumps.items) |j| {
        try self.patchJump(j);
    }

    // Free the key register
    self.freeReg();
}

/// Compile (quasiquote template)
///
/// Walks the template recursively:
/// - Atoms: emit as constants (like quote)
/// - (unquote expr): compile expr normally
/// - (unquote-splicing expr) within a list: build segments, call append
/// - Otherwise: recursively process car/cdr, emit cons
pub fn compileQuasiquote(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const template = types.car(args);
    // #2405: a datum-label cycle in the template recursed through compileQQ's
    // car/cdr (and vector re-wrapping) forever — the template is rebuilt with
    // runtime conses, which a cycle has no finite form of. Active-path set
    // keyed on Object address (stable in this non-moving GC, holds no Values),
    // the erRenameDatum discipline from #2403.
    var path: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer path.deinit(self.gc.allocator);
    try compileQQ(self, template, dst, 0, &path);
}

/// True when `head` is the quasiquote keyword `kw` — recognized through the
/// hygiene strip so a template-introduced head (hygiene-renamed since
/// kaappi#2074, e.g. `__hyg_N_quasiquote`) still drives the depth machinery
/// that decides whether an unquote is data or code.
fn isQQKeyword(head: Value, comptime kw: []const u8) bool {
    if (!types.isSymbol(head)) return false;
    return std.mem.eql(u8, types.stripHygienicPrefix(types.symbolName(head)), kw);
}

fn compileQQ(self: *Compiler, tmpl: Value, dst: u16, depth: u8, path: *std.AutoHashMapUnmanaged(usize, void)) CompileError!void {
    if (types.isVector(tmpl)) {
        // #2405: key the path on the VECTOR too — its fresh list wrapper gets
        // a new address each visit, so only the vector's own address catches
        // the vector↔pair cycle (`#0=#((x . #0#))`).
        const vec_key = @intFromPtr(types.toObject(tmpl));
        if (path.contains(vec_key)) return compiler_mod.circularFormError();
        try path.put(self.gc.allocator, vec_key, {});
        defer _ = path.remove(vec_key);
        // Vector quasiquote: compile elements as a list at the current depth,
        // then call list->vector. This preserves the nesting level so that
        // inner unquotes at depth > 0 remain literal (#850).
        const gc = self.gc;
        const vec = types.toVector(tmpl);
        // Convert vector elements to a list. Built under no_collect (the
        // growing list is fresh unrooted pairs, issue #1010), then rooted
        // across the recursive compile.
        var list: Value = blk: {
            gc.no_collect += 1;
            defer gc.no_collect -= 1;
            var l: Value = types.NIL;
            var i = vec.data.len;
            while (i > 0) {
                i -= 1;
                l = gc.allocPair(vec.data[i], l) catch return CompileError.OutOfMemory;
            }
            break :blk l;
        };
        gc.pushRoot(&list);
        defer gc.popRoot();
        // Compile the list at the current quasiquote depth
        const fn_reg = try self.allocReg();
        const arg_reg = try self.allocReg();
        try compileQQ(self, list, arg_reg, depth, path);
        // Call list->vector on the result
        const l2v_sym = gc.allocSymbol("list->vector") catch return CompileError.OutOfMemory;
        const l2v_idx = try self.addConstant(l2v_sym);
        try self.emitOp(.call_global);
        try self.emitU16(fn_reg);
        try self.emitU16(l2v_idx);
        try self.emit(1);
        if (fn_reg != dst) {
            try self.emitOp(.move);
            try self.emitU16(dst);
            try self.emitU16(fn_reg);
        }
        self.freeReg(); // arg_reg
        self.freeReg(); // fn_reg
        return;
    }

    if (!types.isPair(tmpl)) {
        // Atom: treat as quoted constant. Strip hygiene renames first, same
        // as plain quote (#1801) -- a quasiquote template's literal atoms
        // are quoted data exactly like `quote`'s.
        const stripped = expander.stripHygieneFromDatum(self.gc, tmpl) catch return CompileError.OutOfMemory;
        const idx = try self.addConstant(stripped);
        try self.emitOp(.load_const);
        try self.emitU16(dst);
        try self.emitU16(idx);
        return;
    }

    // #2405: the active-path membership test for the pair branches below —
    // see compileQuasiquote.
    const tmpl_key = @intFromPtr(types.toObject(tmpl));
    if (path.contains(tmpl_key)) return compiler_mod.circularFormError();
    try path.put(self.gc.allocator, tmpl_key, {});
    defer _ = path.remove(tmpl_key);

    const head = types.car(tmpl);

    // Check for (unquote expr)
    if (isQQKeyword(head, "unquote")) {
        if (depth == 0) {
            // Evaluate the expression
            const rest = types.cdr(tmpl);
            if (rest == types.NIL) return CompileError.InvalidSyntax;
            try self.compileExprViaIR(types.car(rest), dst, false);
            return;
        } else {
            // Nested unquote: decrement depth, rebuild the form
            const rest = types.cdr(tmpl);
            if (rest == types.NIL) return CompileError.InvalidSyntax;
            // Build (unquote <compiled-inner>) with decremented depth.
            // A template-introduced head may be hygiene-renamed (#2074);
            // the rebuilt form is data, so strip the rename back off.
            const unquote_sym_stripped = try expander.stripHygieneFromDatum(self.gc, head);
            const unquote_sym_idx = try self.addConstant(unquote_sym_stripped);
            const sym_reg = try self.allocReg();
            try self.emitOp(.load_const);
            try self.emitU16(sym_reg);
            try self.emitU16(unquote_sym_idx);

            const inner_reg = try self.allocReg();
            try compileQQ(self, types.car(rest), inner_reg, depth - 1, path);

            // Build (inner . ())
            const nil_reg = try self.allocReg();
            try self.emitOp(.load_nil);
            try self.emitU16(nil_reg);
            const inner_pair_reg = try self.allocReg();
            try self.emitOp(.cons);
            try self.emitU16(inner_pair_reg);
            try self.emitU16(inner_reg);
            try self.emitU16(nil_reg);
            self.freeReg(); // nil_reg

            // Build (unquote inner . ())
            try self.emitOp(.cons);
            try self.emitU16(dst);
            try self.emitU16(sym_reg);
            try self.emitU16(inner_pair_reg);

            self.freeReg(); // inner_pair_reg
            self.freeReg(); // inner_reg
            self.freeReg(); // sym_reg
            return;
        }
    }

    // Check for (unquote-splicing expr) at non-zero depth (#849).
    // At depth 0, splicing is handled by compileQQSplicing when it appears
    // as a list element. At depth > 0, we rebuild the form literally but
    // compile the subexpression at depth-1 so that inner unquotes at the
    // outermost level are correctly evaluated.
    if (isQQKeyword(head, "unquote-splicing") and depth > 0) {
        const rest = types.cdr(tmpl);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        // Build (unquote-splicing <compiled-inner>) with decremented depth
        const us_sym_stripped = try expander.stripHygieneFromDatum(self.gc, head);
        const us_sym_idx = try self.addConstant(us_sym_stripped);
        const sym_reg = try self.allocReg();
        try self.emitOp(.load_const);
        try self.emitU16(sym_reg);
        try self.emitU16(us_sym_idx);

        const inner_reg = try self.allocReg();
        try compileQQ(self, types.car(rest), inner_reg, depth - 1, path);

        // Build (inner . ())
        const nil_reg = try self.allocReg();
        try self.emitOp(.load_nil);
        try self.emitU16(nil_reg);
        const inner_pair_reg = try self.allocReg();
        try self.emitOp(.cons);
        try self.emitU16(inner_pair_reg);
        try self.emitU16(inner_reg);
        try self.emitU16(nil_reg);
        self.freeReg(); // nil_reg

        // Build (unquote-splicing inner . ())
        try self.emitOp(.cons);
        try self.emitU16(dst);
        try self.emitU16(sym_reg);
        try self.emitU16(inner_pair_reg);

        self.freeReg(); // inner_pair_reg
        self.freeReg(); // inner_reg
        self.freeReg(); // sym_reg
        return;
    }

    // Check for (quasiquote expr) -- nested quasiquote
    if (isQQKeyword(head, "quasiquote")) {
        const rest = types.cdr(tmpl);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        if (depth == std.math.maxInt(u8)) return CompileError.InvalidSyntax;
        // Rebuild (quasiquote <compiled-inner>) with incremented depth.
        // The head may be a template-introduced hygienic rename (#2074);
        // the rebuilt form is data, so strip the rename back off.
        const qq_sym_stripped = try expander.stripHygieneFromDatum(self.gc, head);
        const qq_sym_idx = try self.addConstant(qq_sym_stripped);
        const sym_reg = try self.allocReg();
        try self.emitOp(.load_const);
        try self.emitU16(sym_reg);
        try self.emitU16(qq_sym_idx);

        const inner_reg = try self.allocReg();
        try compileQQ(self, types.car(rest), inner_reg, depth + 1, path);

        const nil_reg = try self.allocReg();
        try self.emitOp(.load_nil);
        try self.emitU16(nil_reg);
        const inner_pair_reg = try self.allocReg();
        try self.emitOp(.cons);
        try self.emitU16(inner_pair_reg);
        try self.emitU16(inner_reg);
        try self.emitU16(nil_reg);
        self.freeReg(); // nil_reg

        try self.emitOp(.cons);
        try self.emitU16(dst);
        try self.emitU16(sym_reg);
        try self.emitU16(inner_pair_reg);

        self.freeReg(); // inner_pair_reg
        self.freeReg(); // inner_reg
        self.freeReg(); // sym_reg
        return;
    }

    // Check if any element uses unquote-splicing
    if (try hasUnquoteSplicing(tmpl, depth)) {
        try compileQQSplicing(self, tmpl, dst, depth);
        return;
    }

    // Regular pair: cons car and cdr
    const car_reg = try self.allocReg();
    try compileQQ(self, types.car(tmpl), car_reg, depth, path);

    const cdr_reg = try self.allocReg();
    try compileQQ(self, types.cdr(tmpl), cdr_reg, depth, path);

    try self.emitOp(.cons);
    try self.emitU16(dst);
    try self.emitU16(car_reg);
    try self.emitU16(cdr_reg);

    self.freeReg(); // cdr_reg
    self.freeReg(); // car_reg
}

/// Check if a list template contains any (unquote-splicing ...) at the current depth.
/// #2405: spine-guarded — a cyclic template spine spun this scan forever.
fn hasUnquoteSplicing(tmpl: Value, depth: u8) CompileError!bool {
    var walk = compiler_mod.SpineWalk.init(tmpl);
    while (types.isPair(walk.cur)) : (walk.next()) {
        if (walk.cyclic()) return compiler_mod.circularFormError();
        const elem = types.car(walk.cur);
        if (types.isPair(elem)) {
            const elem_head = types.car(elem);
            if (types.isSymbol(elem_head) and
                isQQKeyword(elem_head, "unquote-splicing") and
                depth == 0)
            {
                return true;
            }
        }
    }
    return false;
}

/// Compile a quasiquote list that contains unquote-splicing.
/// Strategy: desugar into an S-expression (append segment...) at compile time,
/// then compile that S-expression normally. This avoids complex register management.
///
/// `(a ,@(list 1 2) b) desugars to:
///   (append (list (quote a)) (list 1 2) (list (quote b)))
fn compileQQSplicing(self: *Compiler, tmpl: Value, dst: u16, depth: u8) CompileError!void {
    const gc = self.gc;
    // no_collect protects the fresh segment sexprs (stack buffers the GC
    // cannot see) until the final form is rooted. The flag keeps the counter
    // balanced on the error returns below without extending the window past
    // the explicit decrements before each compileExpr.
    gc.no_collect += 1;
    var nc_held = true;
    defer if (nc_held) {
        gc.no_collect -= 1;
    };
    const quote_sym = gc.allocSymbol("quote") catch return CompileError.OutOfMemory;
    const list_sym = gc.allocSymbol("list") catch return CompileError.OutOfMemory;
    const append_sym = gc.allocSymbol("append") catch return CompileError.OutOfMemory;

    // Collect segments as S-expression values
    var segments_buf: [64]Value = undefined;
    var seg_count: usize = 0;

    var current = compiler_mod.SpineWalk.init(tmpl);
    var group_buf: [64]Value = undefined;
    var group_count: usize = 0;

    while (types.isPair(current.cur)) : (current.next()) {
        // #2405: a cyclic template spine overflowed the 64-segment buffers
        // as a KP9001; name the cycle instead.
        if (current.cyclic()) return compiler_mod.circularFormError();
        // Detect dotted unquote tail (#852): when the current pair looks
        // like (unquote <expr>) — car is the unquote symbol and cdr is a
        // one-element list — this is `. ,<expr>` in the template. Flush
        // the pending group and add the evaluated expression as the final
        // segment so that `append` uses it as the tail.
        if (depth == 0 and types.isSymbol(types.car(current.cur))) {
            const maybe_uq_name = types.symbolName(types.car(current.cur));
            if (std.mem.eql(u8, types.stripHygienicPrefix(maybe_uq_name), "unquote")) {
                const uq_args = types.cdr(current.cur);
                if (types.isPair(uq_args) and types.cdr(uq_args) == types.NIL) {
                    // Flush pending group
                    if (group_count > 0) {
                        if (seg_count >= 64) return CompileError.TooManyLocals;
                        segments_buf[seg_count] = try buildQQListExpr(gc, quote_sym, list_sym, group_buf[0..group_count]);
                        seg_count += 1;
                    }
                    // Add the evaluated tail expression as the final segment
                    if (seg_count >= 64) return CompileError.TooManyLocals;
                    segments_buf[seg_count] = types.car(uq_args);
                    seg_count += 1;
                    current.cur = types.NIL;
                    break;
                }
            }
        }

        const elem = types.car(current.cur);

        // Check if this element is (unquote-splicing expr)
        if (types.isPair(elem) and depth == 0) {
            const elem_head = types.car(elem);
            if (types.isSymbol(elem_head) and
                isQQKeyword(elem_head, "unquote-splicing"))
            {
                // Flush group: build (list (quote e1) (quote e2) ...)
                if (group_count > 0) {
                    if (seg_count >= 64) return CompileError.TooManyLocals;
                    segments_buf[seg_count] = try buildQQListExpr(gc, quote_sym, list_sym, group_buf[0..group_count]);
                    seg_count += 1;
                    group_count = 0;
                }

                // Add the spliced expression directly as a segment
                const splice_rest = types.cdr(elem);
                if (splice_rest == types.NIL) return CompileError.InvalidSyntax;
                if (seg_count >= 64) return CompileError.TooManyLocals;
                segments_buf[seg_count] = types.car(splice_rest);
                seg_count += 1;
                continue;
            }
        }

        // Normal element: add to group (will be wrapped in quote later)
        if (group_count >= 64) return CompileError.TooManyLocals;
        // For unquoted elements within splicing context, we need to recursively
        // expand them. Check if element is (unquote expr) at depth 0
        if (types.isPair(elem) and depth == 0) {
            const elem_head = types.car(elem);
            if (isQQKeyword(elem_head, "unquote")) {
                const uq_rest = types.cdr(elem);
                if (uq_rest == types.NIL) return CompileError.InvalidSyntax;
                // This element should be evaluated, not quoted
                // Store a sentinel: wrap in a special way
                group_buf[group_count] = elem; // keep unquote form
                group_count += 1;
                continue;
            }
        }
        group_buf[group_count] = elem;
        group_count += 1;
    }

    // Flush remaining group
    if (group_count > 0) {
        if (seg_count >= 64) return CompileError.TooManyLocals;
        segments_buf[seg_count] = try buildQQListExpr(gc, quote_sym, list_sym, group_buf[0..group_count]);
        seg_count += 1;
    }

    // Handle dotted tail
    if (current.cur != types.NIL and !types.isPair(current.cur)) {
        // This shouldn't normally happen with splicing, but handle it
        if (seg_count >= 64) return CompileError.TooManyLocals;
        // Wrap as (quote tail)
        const quoted_tail = gc.allocPair(quote_sym, gc.allocPair(current.cur, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        segments_buf[seg_count] = quoted_tail;
        seg_count += 1;
    }

    if (seg_count == 0) {
        gc.no_collect -= 1;
        nc_held = false;
        try self.emitOp(.load_nil);
        try self.emitU16(dst);
        return;
    }
    if (seg_count == 1) {
        var seg0 = segments_buf[0];
        gc.no_collect -= 1;
        nc_held = false;
        gc.pushRoot(&seg0);
        defer gc.popRoot();
        return self.compileExprViaIR(seg0, dst, false);
    }

    // Build (append seg1 seg2 ... segN)
    var args_list: Value = types.NIL;
    var si = seg_count;
    while (si > 0) {
        si -= 1;
        args_list = gc.allocPair(segments_buf[si], args_list) catch return CompileError.OutOfMemory;
    }
    var append_call = gc.allocPair(append_sym, args_list) catch return CompileError.OutOfMemory;
    gc.no_collect -= 1;
    nc_held = false;
    gc.pushRoot(&append_call);
    defer gc.popRoot();
    return self.compileExprViaIR(append_call, dst, false);
}

/// Build an S-expression (list expr1 expr2 ...) where each expr is either
/// (quote elem) for plain data, or the unquote expression for ,expr.
fn buildQQListExpr(gc: *@import("memory.zig").GC, quote_sym: Value, list_sym: Value, elems: []const Value) CompileError!Value {
    const qq_sym = gc.allocSymbol("quasiquote") catch return CompileError.OutOfMemory;
    var args: Value = types.NIL;
    var i = elems.len;
    while (i > 0) {
        i -= 1;
        const elem = elems[i];
        if (types.isPair(elem)) {
            const elem_head = types.car(elem);
            if (isQQKeyword(elem_head, "unquote")) {
                const uq_rest = types.cdr(elem);
                if (uq_rest != types.NIL) {
                    args = gc.allocPair(types.car(uq_rest), args) catch return CompileError.OutOfMemory;
                    continue;
                }
            }
            // Compound element: wrap in (quasiquote elem) so nested unquotes are processed
            const wrapped = gc.allocPair(qq_sym, gc.allocPair(elem, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            args = gc.allocPair(wrapped, args) catch return CompileError.OutOfMemory;
            continue;
        }
        // Vector: wrap in (quasiquote elem) so nested unquotes are processed
        if (types.isVector(elem)) {
            const wrapped = gc.allocPair(qq_sym, gc.allocPair(elem, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            args = gc.allocPair(wrapped, args) catch return CompileError.OutOfMemory;
            continue;
        }
        // Atom: wrap in (quote elem)
        const quoted = gc.allocPair(quote_sym, gc.allocPair(elem, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        args = gc.allocPair(quoted, args) catch return CompileError.OutOfMemory;
    }
    return gc.allocPair(list_sym, args) catch return CompileError.OutOfMemory;
}

/// Compile (parameterize ((param1 val1) (param2 val2) ...) body ...)
///
/// Desugars to:
///   (let ((%pp0 p1) (%pp1 p2) ... (%pv0 v1) (%pv1 v2) ...)
///     (let* ((old0 (%pp0)) (new0 (%parameter-convert %pp0 %pv0))
///            (old1 (%pp1)) (new1 (%parameter-convert %pp1 %pv1)) ...)
///       (dynamic-wind
///         (lambda () (%parameter-set! %pp0 new0) (%parameter-set! %pp1 new1) ...)
///         (lambda () body ...)
///         (lambda () (%parameter-set! %pp0 old0) (%parameter-set! %pp1 old1) ...))))
///
/// The outer `let` evaluates all param and value expressions before any
/// parameter cell is mutated (R7RS §4.2.6, SRFI-39). The inner `let*`
/// saves old values and runs converters without mutating cells.
/// All mutation happens inside `dynamic-wind`, so converter errors and
/// continuation re-entries are safe.
pub fn compileParameterize(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    const gc = self.gc;
    const begin_sym = gc.allocSymbol("begin") catch return CompileError.OutOfMemory;

    // Count bindings
    var binding_count: usize = 0;
    var b = bindings;
    while (b != types.NIL) {
        if (!types.isPair(b)) return CompileError.InvalidSyntax;
        binding_count += 1;
        b = types.cdr(b);
    }

    if (binding_count == 0) {
        // No bindings: just compile the body
        return self.compileDesugared(gc.allocPair(begin_sym, body) catch return CompileError.OutOfMemory, dst, is_tail);
    }

    // Collect param/value exprs and generate symbols
    var old_syms: [32]Value = undefined;
    var new_syms: [32]Value = undefined;
    var param_syms: [32]Value = undefined;
    var val_syms: [32]Value = undefined;
    var param_exprs: [32]Value = undefined;
    var val_exprs: [32]Value = undefined;
    if (binding_count > 32) return CompileError.TooManyLocals;

    b = bindings;
    var idx: usize = 0;
    while (b != types.NIL) : (idx += 1) {
        const binding = types.car(b);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        param_exprs[idx] = types.car(binding);
        const val_rest = types.cdr(binding);
        if (val_rest == types.NIL or !types.isPair(val_rest)) return CompileError.InvalidSyntax;
        val_exprs[idx] = types.car(val_rest);

        var param_buf: [16]u8 = undefined;
        const param_name = std.fmt.bufPrint(&param_buf, "%pp{d}", .{idx}) catch return CompileError.OutOfMemory;
        param_syms[idx] = gc.allocSymbol(param_name) catch return CompileError.OutOfMemory;

        var val_buf: [16]u8 = undefined;
        const val_name = std.fmt.bufPrint(&val_buf, "%pv{d}", .{idx}) catch return CompileError.OutOfMemory;
        val_syms[idx] = gc.allocSymbol(val_name) catch return CompileError.OutOfMemory;

        var old_buf: [16]u8 = undefined;
        const old_name = std.fmt.bufPrint(&old_buf, "%pold{d}", .{idx}) catch return CompileError.OutOfMemory;
        old_syms[idx] = gc.allocSymbol(old_name) catch return CompileError.OutOfMemory;

        var new_buf: [16]u8 = undefined;
        const new_name = std.fmt.bufPrint(&new_buf, "%pnew{d}", .{idx}) catch return CompileError.OutOfMemory;
        new_syms[idx] = gc.allocSymbol(new_name) catch return CompileError.OutOfMemory;

        b = types.cdr(b);
    }

    // Build the desugared form with collection disabled: every intermediate
    // below is a fresh unrooted pair. The scoped defer restores the counter
    // on every path; leaking an increment would disable collection for the
    // rest of the process.
    const outer_let: Value = blk: {
        gc.no_collect += 1;
        defer gc.no_collect -= 1;

        const let_sym = gc.allocSymbol("let") catch return CompileError.OutOfMemory;
        const letstar_sym = gc.allocSymbol("let*") catch return CompileError.OutOfMemory;

        // Outer let: evaluate all param and value expressions before any mutation.
        //   (let ((%pp0 <param-expr0>) (%pp1 <param-expr1>) ...
        //         (%pv0 <val-expr0>)   (%pv1 <val-expr1>) ...)
        //     ...)
        var outer_bindings: Value = types.NIL;
        var i = binding_count;
        while (i > 0) {
            i -= 1;
            const pv_pair = gc.allocPair(val_syms[i], gc.allocPair(val_exprs[i], types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            outer_bindings = gc.allocPair(pv_pair, outer_bindings) catch return CompileError.OutOfMemory;
        }
        i = binding_count;
        while (i > 0) {
            i -= 1;
            const pp_pair = gc.allocPair(param_syms[i], gc.allocPair(param_exprs[i], types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            outer_bindings = gc.allocPair(pp_pair, outer_bindings) catch return CompileError.OutOfMemory;
        }

        // Inner let*: save old values and convert new values without mutation.
        //   (let* ((old0 (%pp0)) (new0 (%parameter-convert %pp0 %pv0))
        //          (old1 (%pp1)) (new1 (%parameter-convert %pp1 %pv1)) ...)
        //     (dynamic-wind ...))
        const pconv_sym = globals_mod.baseBindingSymbol(gc, "%parameter-convert") catch return CompileError.OutOfMemory;
        var inner_bindings: Value = types.NIL;
        i = binding_count;
        while (i > 0) {
            i -= 1;
            // (new_i (%parameter-convert %pp_i %pv_i))
            const conv_call = gc.allocPair(pconv_sym, gc.allocPair(param_syms[i], gc.allocPair(val_syms[i], types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            const new_pair = gc.allocPair(new_syms[i], gc.allocPair(conv_call, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            inner_bindings = gc.allocPair(new_pair, inner_bindings) catch return CompileError.OutOfMemory;

            // (old_i (%pp_i))
            const old_get = gc.allocPair(param_syms[i], types.NIL) catch return CompileError.OutOfMemory;
            const old_pair = gc.allocPair(old_syms[i], gc.allocPair(old_get, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            inner_bindings = gc.allocPair(old_pair, inner_bindings) catch return CompileError.OutOfMemory;
        }

        const dw_sym = gc.allocSymbol("dynamic-wind") catch return CompileError.OutOfMemory;
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const pset_sym = globals_mod.baseBindingSymbol(gc, "%parameter-set!") catch return CompileError.OutOfMemory;

        // before-thunk: (%parameter-set! %pp_i new_i) — install pre-converted values
        var before_body: Value = types.NIL;
        i = binding_count;
        while (i > 0) {
            i -= 1;
            const set_call = gc.allocPair(pset_sym, gc.allocPair(param_syms[i], gc.allocPair(new_syms[i], types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            before_body = gc.allocPair(set_call, before_body) catch return CompileError.OutOfMemory;
        }
        const before_thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, before_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

        const body_thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

        // after-thunk: (%parameter-set! %pp_i old_i) — restore old values
        var after_body: Value = types.NIL;
        i = binding_count;
        while (i > 0) {
            i -= 1;
            const restore_call = gc.allocPair(pset_sym, gc.allocPair(param_syms[i], gc.allocPair(old_syms[i], types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            after_body = gc.allocPair(restore_call, after_body) catch return CompileError.OutOfMemory;
        }
        const after_thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, after_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

        const dw_call = gc.allocPair(dw_sym, gc.allocPair(before_thunk, gc.allocPair(body_thunk, gc.allocPair(after_thunk, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

        const inner_body = gc.allocPair(dw_call, types.NIL) catch return CompileError.OutOfMemory;
        const inner_let = gc.allocPair(letstar_sym, gc.allocPair(inner_bindings, inner_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const outer_body = gc.allocPair(inner_let, types.NIL) catch return CompileError.OutOfMemory;
        break :blk gc.allocPair(let_sym, gc.allocPair(outer_bindings, outer_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    };

    return self.compileDesugared(outer_let, dst, is_tail);
}

/// Compile (case-lambda (formals body ...) ...)
///
/// Desugars to (internal names %-prefixed so clause bodies referencing
/// user variables named `args` or `n` are not captured):
/// (lambda %cl-args
///   (let ((%cl-n (length %cl-args)))
///     (cond
///       ((= %cl-n arity1) (apply (lambda formals1 body1...) %cl-args))
///       ((= %cl-n arity2) (apply (lambda formals2 body2...) %cl-args))
///       ...
///       (else (error "wrong number of arguments")))))
///
/// `length` there is emitted as `length`'s pristine `(scheme base)` binding
/// (`globals_mod.base_binding_prefix`, kaappi#1715), not as the name `length`
/// means at the use site: a scope legitimately shadowing `length` — say, to
/// supply its own for a non-standard list-like type — must not break dispatch
/// here, which needs the real list-length primitive regardless (kaappi#1714).
/// That used to be a dedicated `%length` primitive, but exporting it from
/// `(scheme base)` made a user library defining its own `%length`
/// un-importable outright (kaappi#1856), and being an ordinary global it lost
/// to a top-level redefinition anyway. The prefixed reference has neither
/// problem: it reserves no name and reads from the export table, which no
/// user code can write.
pub fn compileCaseLambda(self: *Compiler, args: Value, dst: u16) CompileError!void {
    const gc = self.gc;

    // Build the desugared form with collection disabled: every intermediate
    // below is a fresh unrooted pair. The scoped defer restores the counter
    // on every path (including the InvalidSyntax returns); leaking an
    // increment would disable collection for the rest of the process.
    const outer_lambda: Value = blk: {
        gc.no_collect += 1;
        defer gc.no_collect -= 1;

        const lambda_sym = try gc.allocSymbol("lambda");
        const let_sym = try gc.allocSymbol("let");
        const cond_sym = try gc.allocSymbol("cond");
        const eq_sym = try gc.allocSymbol("=");
        const ge_sym = try gc.allocSymbol(">=");
        const length_sym = try Compiler.trueBuiltinRefOrSymbol(gc, "length");
        const apply_sym = try Compiler.trueBuiltinRefOrSymbol(gc, "apply");
        const else_sym = try gc.allocSymbol("else");
        const error_sym = try gc.allocSymbol("error");
        const args_sym = try gc.allocSymbol("%cl-args");
        const n_sym = try gc.allocSymbol("%cl-n");

        var cond_clauses: Value = types.NIL;
        var clause_list = args;

        // Values collected here stay reachable because no_collect is held until
        // after the desugared form is fully built.
        var clause_buf: std.ArrayList(Value) = .empty;
        defer clause_buf.deinit(gc.allocator);

        while (clause_list != types.NIL) {
            if (!types.isPair(clause_list)) return CompileError.InvalidSyntax;
            const clause = types.car(clause_list);
            clause_list = types.cdr(clause_list);

            if (!types.isPair(clause)) return CompileError.InvalidSyntax;
            const formals = types.car(clause);
            const body = types.cdr(clause);
            if (body == types.NIL) return CompileError.InvalidSyntax;

            // Count arity from formals
            var arity: i64 = 0;
            var flist = formals;
            while (flist != types.NIL) {
                if (!types.isPair(flist)) break; // rest param
                arity += 1;
                flist = types.cdr(flist);
            }

            const has_rest = flist != types.NIL;
            const arity_val = types.makeFixnum(arity);
            const cmp_sym = if (has_rest) ge_sym else eq_sym;
            const test_expr = try gc.allocPair(cmp_sym, try gc.allocPair(n_sym, try gc.allocPair(arity_val, types.NIL)));
            // (lambda formals body...)
            const inner_lambda = try gc.allocPair(lambda_sym, try gc.allocPair(formals, body));
            // (apply inner_lambda args)
            const apply_call = try gc.allocPair(apply_sym, try gc.allocPair(inner_lambda, try gc.allocPair(args_sym, types.NIL)));
            // ((= n arity) (apply ...))
            const cond_clause = try gc.allocPair(test_expr, try gc.allocPair(apply_call, types.NIL));

            clause_buf.append(gc.allocator, cond_clause) catch return CompileError.OutOfMemory;
        }

        // Build else clause: (else (error "wrong number of arguments"))
        const err_msg = try gc.allocString("wrong number of arguments");
        const err_call = try gc.allocPair(error_sym, try gc.allocPair(err_msg, types.NIL));
        const else_clause = try gc.allocPair(else_sym, try gc.allocPair(err_call, types.NIL));

        // Build cond clauses list (in order) ending with else
        cond_clauses = try gc.allocPair(else_clause, types.NIL);
        var ci = clause_buf.items.len;
        while (ci > 0) {
            ci -= 1;
            cond_clauses = try gc.allocPair(clause_buf.items[ci], cond_clauses);
        }

        // Build: (cond clauses...)
        const cond_form = try gc.allocPair(cond_sym, cond_clauses);

        // Build: (let ((n (length args))) cond_form)
        // (length args)
        const length_call = try gc.allocPair(length_sym, try gc.allocPair(args_sym, types.NIL));
        // ((n (length args)))
        const n_binding = try gc.allocPair(n_sym, try gc.allocPair(length_call, types.NIL));
        const bindings = try gc.allocPair(n_binding, types.NIL);
        // (let bindings cond_form)
        const let_form = try gc.allocPair(let_sym, try gc.allocPair(bindings, try gc.allocPair(cond_form, types.NIL)));

        // Build: (lambda args let_form)
        break :blk try gc.allocPair(lambda_sym, try gc.allocPair(args_sym, try gc.allocPair(let_form, types.NIL)));
    };

    return self.compileDesugared(outer_lambda, dst, false);
}
