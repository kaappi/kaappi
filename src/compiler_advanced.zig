const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const conditionals = @import("compiler_conditionals.zig");
const Value = types.Value;
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;

// -- Advanced expression forms --

/// Compile (guard (var clause ...) body ...)
///
/// Transforms into:
///   (with-exception-handler
///     (lambda (var) (cond clause ... [else (raise var)]))
///     (lambda () body ...))
pub fn compileGuard(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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
    gc.no_collect += 1;

    var cond_clauses = clauses;
    if (!has_else) {
        const raise_sym = gc.allocSymbol("raise") catch return CompileError.OutOfMemory;
        const raise_call = gc.allocPair(raise_sym, gc.allocPair(var_sym, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const else_sym = gc.allocSymbol("else") catch return CompileError.OutOfMemory;
        const else_clause = gc.allocPair(else_sym, gc.allocPair(raise_call, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        cond_clauses = appendToList(self, clauses, else_clause) catch return CompileError.OutOfMemory;
    }

    const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
    const gk_counter = struct { var n: u32 = 0; };
    gk_counter.n += 1;
    var gk_buf: [32]u8 = undefined;
    const gk_name = std.fmt.bufPrint(&gk_buf, "__gk{d}", .{gk_counter.n}) catch "__gk";
    const gk = gc.allocSymbol(gk_name) catch return CompileError.OutOfMemory;

    const cond_sym = gc.allocSymbol("cond") catch return CompileError.OutOfMemory;
    const cond_form = gc.allocPair(cond_sym, cond_clauses) catch return CompileError.OutOfMemory;
    const k_call = gc.allocPair(gk, gc.allocPair(cond_form, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    const h_formals = gc.allocPair(var_sym, types.NIL) catch return CompileError.OutOfMemory;
    const handler = gc.allocPair(lambda_sym, gc.allocPair(h_formals, gc.allocPair(k_call, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    const thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    const weh_sym = gc.allocSymbol("with-exception-handler") catch return CompileError.OutOfMemory;
    const weh = gc.allocPair(weh_sym, gc.allocPair(handler, gc.allocPair(thunk, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    const outer = gc.allocPair(lambda_sym, gc.allocPair(gc.allocPair(gk, types.NIL) catch return CompileError.OutOfMemory, gc.allocPair(weh, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    const ec_sym = gc.allocSymbol("call-with-escape-continuation") catch return CompileError.OutOfMemory;
    var form = gc.allocPair(ec_sym, gc.allocPair(outer, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

    gc.no_collect -= 1;
    gc.pushRoot(&form);
    defer gc.popRoot();
    return self.compileExpr(form, dst, is_tail);
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
pub fn compileCase(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const key_expr = types.car(args);
    const clauses = types.cdr(args);

    // Compile key expression into a dedicated register
    const key_reg = try self.allocReg();
    try self.compileExpr(key_expr, key_reg, false);

    var end_jumps: std.ArrayList(usize) = .empty;
    defer end_jumps.deinit(self.gc.allocator);
    var current = clauses;
    var had_else = false;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const clause = types.car(current);
        current = types.cdr(current);
        if (!types.isPair(clause)) return CompileError.InvalidSyntax;

        const datums = types.car(clause);
        const clause_body = types.cdr(clause);

        // Check for else clause
        if (types.isSymbol(datums) and std.mem.eql(u8, types.symbolName(datums), "else")) {
            // (else => proc): apply proc to the key value.
            if (types.isPair(clause_body)) {
                const maybe_arrow = types.car(clause_body);
                if (types.isSymbol(maybe_arrow) and std.mem.eql(u8, types.symbolName(maybe_arrow), "=>")) {
                    const arrow_rest = types.cdr(clause_body);
                    if (!types.isPair(arrow_rest)) return CompileError.InvalidSyntax;
                    const proc_expr = types.car(arrow_rest);
                    const proc_reg = try self.allocReg();
                    const arg_reg = try self.allocReg();
                    try self.emitOp(.move);
                    try self.emit(arg_reg);
                    try self.emit(key_reg);
                    try self.compileExpr(proc_expr, proc_reg, false);
                    try self.emitOp(.move);
                    try self.emit(dst);
                    try self.emit(proc_reg);
                    try self.emitOp(.move);
                    try self.emit(@as(u8, dst) + 1);
                    try self.emit(arg_reg);
                    if (is_tail) try self.emitOp(.tail_call) else try self.emitOp(.call);
                    try self.emit(dst);
                    try self.emit(1);
                    self.freeReg(); // arg_reg
                    self.freeReg(); // proc_reg
                    had_else = true;
                    break;
                }
            }
            try conditionals.compileCondBody(self, clause_body, dst, is_tail);
            had_else = true;
            break;
        }

        // For each datum in the clause, compare with key
        // If any matches, jump to clause body
        if (!types.isPair(datums)) return CompileError.InvalidSyntax;

        var body_jumps: std.ArrayList(usize) = .empty;
        defer body_jumps.deinit(self.gc.allocator);
        var datum_list = datums;

        while (datum_list != types.NIL) {
            if (!types.isPair(datum_list)) return CompileError.InvalidSyntax;
            const datum = types.car(datum_list);
            datum_list = types.cdr(datum_list);

            // Build (eqv? key datum) call inline:
            // Load eqv? into a temp reg, load datum, call, then jump_true
            // Simpler: compile datum as a constant, then emit an eqv? comparison

            // Load the datum as a constant
            const datum_idx = try self.addConstant(datum);
            const datum_reg = try self.allocReg();
            try self.emitOp(.load_const);
            try self.emit(datum_reg);
            try self.emitU16(datum_idx);

            // Load eqv? procedure
            const eqv_sym = self.gc.allocSymbol("eqv?") catch return CompileError.OutOfMemory;
            const eqv_idx = try self.addConstant(eqv_sym);
            const eqv_reg = try self.allocReg();
            try self.emitOp(.get_global);
            try self.emit(eqv_reg);
            try self.emitU16(eqv_idx);

            // Set up call: eqv?(key, datum) in fresh contiguous registers
            // to avoid clobbering live variables near dst.
            const call_base = try self.allocReg();
            const arg1_pos = try self.allocReg();
            const arg2_pos = try self.allocReg();
            try self.emitOp(.move);
            try self.emit(call_base);
            try self.emit(eqv_reg);
            try self.emitOp(.move);
            try self.emit(arg1_pos);
            try self.emit(key_reg);
            try self.emitOp(.move);
            try self.emit(arg2_pos);
            try self.emit(datum_reg);

            try self.emitOp(.call);
            try self.emit(call_base);
            try self.emit(2);

            // Move result to dst
            try self.emitOp(.move);
            try self.emit(dst);
            try self.emit(call_base);

            // Free temp regs
            self.freeReg(); // arg2_pos
            self.freeReg(); // arg1_pos
            self.freeReg(); // call_base
            self.freeReg(); // eqv_reg
            self.freeReg(); // datum_reg

            // jump_true to clause body
            try self.emitOp(.jump_true);
            try self.emit(dst);
            body_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
            try self.emitI16(0);
        }

        // No datum matched — jump to next clause
        try self.emitOp(.jump);
        const next_clause_jump = self.currentOffset();
        try self.emitI16(0);

        // Patch body jumps to here (start of clause body)
        for (body_jumps.items) |j| {
            self.patchJump(j);
        }

        // Check for => form: ((datum ...) => proc)
        if (clause_body != types.NIL and types.isPair(clause_body)) {
            const maybe_arrow = types.car(clause_body);
            if (types.isSymbol(maybe_arrow) and std.mem.eql(u8, types.symbolName(maybe_arrow), "=>")) {
                // Arrow form: compile proc, call with key value
                const arrow_rest = types.cdr(clause_body);
                if (arrow_rest == types.NIL or !types.isPair(arrow_rest)) return CompileError.InvalidSyntax;
                const proc_expr = types.car(arrow_rest);
                const proc_reg = try self.allocReg();
                // Move key value to arg position
                const arg_reg = try self.allocReg();
                try self.emitOp(.move);
                try self.emit(arg_reg);
                try self.emit(key_reg);
                // Compile proc
                try self.compileExpr(proc_expr, proc_reg, false);
                // Move proc to dst (for call base)
                try self.emitOp(.move);
                try self.emit(dst);
                try self.emit(proc_reg);
                // Move arg after dst
                try self.emitOp(.move);
                try self.emit(@as(u8, dst) + 1);
                try self.emit(arg_reg);
                if (is_tail) {
                    try self.emitOp(.tail_call);
                } else {
                    try self.emitOp(.call);
                }
                try self.emit(dst);
                try self.emit(1);
                self.freeReg(); // arg_reg
                self.freeReg(); // proc_reg

                // Jump to end
                try self.emitOp(.jump);
                end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
                try self.emitI16(0);

                // Patch next clause jump
                self.patchJump(next_clause_jump);
                continue;
            }
        }

        // Compile clause body
        try conditionals.compileCondBody(self, clause_body, dst, is_tail);

        // Jump to end
        try self.emitOp(.jump);
        end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
        try self.emitI16(0);

        // Patch next clause jump
        self.patchJump(next_clause_jump);
    }

    // If no else clause, result is void
    if (!had_else) {
        try self.emitOp(.load_void);
        try self.emit(dst);
    }

    // Patch all end jumps
    for (end_jumps.items) |j| {
        self.patchJump(j);
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
pub fn compileQuasiquote(self: *Compiler, args: Value, dst: u8) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const template = types.car(args);
    try compileQQ(self,template, dst, 0);
}

fn compileQQ(self: *Compiler, tmpl: Value, dst: u8, depth: u8) CompileError!void {
    if (types.isVector(tmpl)) {
        // Vector quasiquote: desugar #(a ,b ,@c d) to (list->vector `(a ,b ,@c d))
        const gc = self.gc;
        const vec = types.toVector(tmpl);
        // Convert vector elements to a list
        var list: Value = types.NIL;
        var i = vec.data.len;
        while (i > 0) {
            i -= 1;
            list = gc.allocPair(vec.data[i], list) catch return CompileError.OutOfMemory;
        }
        // Build (list->vector <quasiquoted-list>)
        const l2v_sym = gc.allocSymbol("list->vector") catch return CompileError.OutOfMemory;
        const qq_sym = gc.allocSymbol("quasiquote") catch return CompileError.OutOfMemory;
        const qq_form = gc.allocPair(qq_sym, gc.allocPair(list, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const call = gc.allocPair(l2v_sym, gc.allocPair(qq_form, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        return self.compileExpr(call, dst, false);
    }

    if (!types.isPair(tmpl)) {
        // Atom: treat as quoted constant
        const idx = try self.addConstant(tmpl);
        try self.emitOp(.load_const);
        try self.emit(dst);
        try self.emitU16(idx);
        return;
    }

    const head = types.car(tmpl);

    // Check for (unquote expr)
    if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "unquote")) {
        if (depth == 0) {
            // Evaluate the expression
            const rest = types.cdr(tmpl);
            if (rest == types.NIL) return CompileError.InvalidSyntax;
            try self.compileExpr(types.car(rest), dst, false);
            return;
        } else {
            // Nested unquote: decrement depth, rebuild the form
            const rest = types.cdr(tmpl);
            if (rest == types.NIL) return CompileError.InvalidSyntax;
            // Build (unquote <compiled-inner>) with decremented depth
            const unquote_sym_idx = try self.addConstant(head);
            const sym_reg = try self.allocReg();
            try self.emitOp(.load_const);
            try self.emit(sym_reg);
            try self.emitU16(unquote_sym_idx);

            const inner_reg = try self.allocReg();
            try compileQQ(self,types.car(rest), inner_reg, depth - 1);

            // Build (inner . ())
            const nil_reg = try self.allocReg();
            try self.emitOp(.load_nil);
            try self.emit(nil_reg);
            const inner_pair_reg = try self.allocReg();
            try self.emitOp(.cons);
            try self.emit(inner_pair_reg);
            try self.emit(inner_reg);
            try self.emit(nil_reg);
            self.freeReg(); // nil_reg

            // Build (unquote inner . ())
            try self.emitOp(.cons);
            try self.emit(dst);
            try self.emit(sym_reg);
            try self.emit(inner_pair_reg);

            self.freeReg(); // inner_pair_reg
            self.freeReg(); // inner_reg
            self.freeReg(); // sym_reg
            return;
        }
    }

    // Check for (quasiquote expr) -- nested quasiquote
    if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "quasiquote")) {
        const rest = types.cdr(tmpl);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        // Rebuild (quasiquote <compiled-inner>) with incremented depth
        const qq_sym_idx = try self.addConstant(head);
        const sym_reg = try self.allocReg();
        try self.emitOp(.load_const);
        try self.emit(sym_reg);
        try self.emitU16(qq_sym_idx);

        const inner_reg = try self.allocReg();
        try compileQQ(self,types.car(rest), inner_reg, depth + 1);

        const nil_reg = try self.allocReg();
        try self.emitOp(.load_nil);
        try self.emit(nil_reg);
        const inner_pair_reg = try self.allocReg();
        try self.emitOp(.cons);
        try self.emit(inner_pair_reg);
        try self.emit(inner_reg);
        try self.emit(nil_reg);
        self.freeReg(); // nil_reg

        try self.emitOp(.cons);
        try self.emit(dst);
        try self.emit(sym_reg);
        try self.emit(inner_pair_reg);

        self.freeReg(); // inner_pair_reg
        self.freeReg(); // inner_reg
        self.freeReg(); // sym_reg
        return;
    }

    // Check if any element uses unquote-splicing
    if (hasUnquoteSplicing(tmpl, depth)) {
        try compileQQSplicing(self,tmpl, dst, depth);
        return;
    }

    // Regular pair: cons car and cdr
    const car_reg = try self.allocReg();
    try compileQQ(self,types.car(tmpl), car_reg, depth);

    const cdr_reg = try self.allocReg();
    try compileQQ(self,types.cdr(tmpl), cdr_reg, depth);

    try self.emitOp(.cons);
    try self.emit(dst);
    try self.emit(car_reg);
    try self.emit(cdr_reg);

    self.freeReg(); // cdr_reg
    self.freeReg(); // car_reg
}

/// Check if a list template contains any (unquote-splicing ...) at the current depth.
fn hasUnquoteSplicing(tmpl: Value, depth: u8) bool {
    var current = tmpl;
    while (types.isPair(current)) {
        const elem = types.car(current);
        if (types.isPair(elem)) {
            const elem_head = types.car(elem);
            if (types.isSymbol(elem_head) and
                std.mem.eql(u8, types.symbolName(elem_head), "unquote-splicing") and
                depth == 0)
            {
                return true;
            }
        }
        current = types.cdr(current);
    }
    return false;
}

/// Compile a quasiquote list that contains unquote-splicing.
/// Strategy: desugar into an S-expression (append segment...) at compile time,
/// then compile that S-expression normally. This avoids complex register management.
///
/// `(a ,@(list 1 2) b) desugars to:
///   (append (list (quote a)) (list 1 2) (list (quote b)))
fn compileQQSplicing(self: *Compiler, tmpl: Value, dst: u8, depth: u8) CompileError!void {
    const gc = self.gc;
    gc.no_collect += 1;
    const quote_sym = gc.allocSymbol("quote") catch return CompileError.OutOfMemory;
    const list_sym = gc.allocSymbol("list") catch return CompileError.OutOfMemory;
    const append_sym = gc.allocSymbol("append") catch return CompileError.OutOfMemory;

    // Collect segments as S-expression values
    var segments_buf: [64]Value = undefined;
    var seg_count: usize = 0;

    var current = tmpl;
    var group_buf: [64]Value = undefined;
    var group_count: usize = 0;

    while (types.isPair(current)) {
        const elem = types.car(current);
        current = types.cdr(current);

        // Check if this element is (unquote-splicing expr)
        if (types.isPair(elem) and depth == 0) {
            const elem_head = types.car(elem);
            if (types.isSymbol(elem_head) and
                std.mem.eql(u8, types.symbolName(elem_head), "unquote-splicing"))
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
            if (types.isSymbol(elem_head) and std.mem.eql(u8, types.symbolName(elem_head), "unquote")) {
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
    if (current != types.NIL and !types.isPair(current)) {
        // This shouldn't normally happen with splicing, but handle it
        if (seg_count >= 64) return CompileError.TooManyLocals;
        // Wrap as (quote tail)
        const quoted_tail = gc.allocPair(quote_sym, gc.allocPair(current, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        segments_buf[seg_count] = quoted_tail;
        seg_count += 1;
    }

    if (seg_count == 0) {
        gc.no_collect -= 1;
        try self.emitOp(.load_nil);
        try self.emit(dst);
        return;
    }
    if (seg_count == 1) {
        var seg0 = segments_buf[0];
        gc.no_collect -= 1;
        gc.pushRoot(&seg0);
        defer gc.popRoot();
        return self.compileExpr(seg0, dst, false);
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
    gc.pushRoot(&append_call);
    defer gc.popRoot();
    return self.compileExpr(append_call, dst, false);
}

/// Build an S-expression (list expr1 expr2 ...) where each expr is either
/// (quote elem) for plain data, or the unquote expression for ,expr.
fn buildQQListExpr(gc: *@import("memory.zig").GC, quote_sym: Value, list_sym: Value, elems: []const Value) CompileError!Value {
    // Build args list backwards
    var args: Value = types.NIL;
    var i = elems.len;
    while (i > 0) {
        i -= 1;
        const elem = elems[i];
        // Check if this is an (unquote expr) form -- if so, use expr directly
        if (types.isPair(elem)) {
            const elem_head = types.car(elem);
            if (types.isSymbol(elem_head) and std.mem.eql(u8, types.symbolName(elem_head), "unquote")) {
                const uq_rest = types.cdr(elem);
                if (uq_rest != types.NIL) {
                    args = gc.allocPair(types.car(uq_rest), args) catch return CompileError.OutOfMemory;
                    continue;
                }
            }
        }
        // Wrap in (quote elem)
        const quoted = gc.allocPair(quote_sym, gc.allocPair(elem, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        args = gc.allocPair(quoted, args) catch return CompileError.OutOfMemory;
    }
    return gc.allocPair(list_sym, args) catch return CompileError.OutOfMemory;
}

/// Compile (parameterize ((param1 val1) (param2 val2) ...) body ...)
///
/// Desugars to:
///   (let ((old1 (p1)) (old2 (p2)) ...)
///     (p1 v1) (p2 v2) ...
///     (let ((%result (begin body ...)))
///       (p1 old1) (p2 old2) ...
///       %result))
pub fn compileParameterize(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    const gc = self.gc;
    const let_sym = gc.allocSymbol("let") catch return CompileError.OutOfMemory;
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
        return self.compileExpr(gc.allocPair(begin_sym, body) catch return CompileError.OutOfMemory, dst, is_tail);
    }

    // Collect param/value exprs and generate old-value symbols
    var old_syms: [32]Value = undefined;
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

        var name_buf: [16]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "%pold{d}", .{idx}) catch return CompileError.OutOfMemory;
        old_syms[idx] = gc.allocSymbol(name) catch return CompileError.OutOfMemory;

        b = types.cdr(b);
    }

    gc.no_collect += 1;

    // Build outer let bindings: ((old1 (p1)) (old2 (p2)) ...)
    var let_bindings: Value = types.NIL;
    var i = binding_count;
    while (i > 0) {
        i -= 1;
        const get_call = gc.allocPair(param_exprs[i], types.NIL) catch return CompileError.OutOfMemory;
        const binding_pair = gc.allocPair(old_syms[i], gc.allocPair(get_call, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        let_bindings = gc.allocPair(binding_pair, let_bindings) catch return CompileError.OutOfMemory;
    }

    const dw_sym = gc.allocSymbol("dynamic-wind") catch return CompileError.OutOfMemory;
    const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
    const pset_sym = gc.allocSymbol("%parameter-set!") catch return CompileError.OutOfMemory;

    var before_body: Value = types.NIL;
    i = binding_count;
    while (i > 0) {
        i -= 1;
        const set_call = gc.allocPair(param_exprs[i], gc.allocPair(val_exprs[i], types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        before_body = gc.allocPair(set_call, before_body) catch return CompileError.OutOfMemory;
    }
    const before_thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, before_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

    const body_thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

    var after_body: Value = types.NIL;
    i = binding_count;
    while (i > 0) {
        i -= 1;
        const restore_call = gc.allocPair(pset_sym, gc.allocPair(param_exprs[i], gc.allocPair(old_syms[i], types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        after_body = gc.allocPair(restore_call, after_body) catch return CompileError.OutOfMemory;
    }
    const after_thunk = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, after_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

    const dw_call = gc.allocPair(dw_sym, gc.allocPair(before_thunk, gc.allocPair(body_thunk, gc.allocPair(after_thunk, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

    const outer_body = gc.allocPair(dw_call, types.NIL) catch return CompileError.OutOfMemory;
    var outer_let = gc.allocPair(let_sym, gc.allocPair(let_bindings, outer_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;

    gc.no_collect -= 1;
    gc.pushRoot(&outer_let);
    defer gc.popRoot();
    return self.compileExpr(outer_let, dst, is_tail);
}

/// Compile (case-lambda (formals body ...) ...)
///
/// Desugars to:
/// (lambda args
///   (let ((n (length args)))
///     (cond
///       ((= n arity1) (apply (lambda formals1 body1...) args))
///       ((= n arity2) (apply (lambda formals2 body2...) args))
///       ...
///       (else (error "wrong number of arguments")))))
pub fn compileCaseLambda(self: *Compiler, args: Value, dst: u8) CompileError!void {
    const gc = self.gc;
    gc.no_collect += 1;

    const lambda_sym = try gc.allocSymbol("lambda");
    const let_sym = try gc.allocSymbol("let");
    const cond_sym = try gc.allocSymbol("cond");
    const eq_sym = try gc.allocSymbol("=");
    const ge_sym = try gc.allocSymbol(">=");
    const length_sym = try gc.allocSymbol("length");
    const apply_sym = try gc.allocSymbol("apply");
    const else_sym = try gc.allocSymbol("else");
    const error_sym = try gc.allocSymbol("error");
    const args_sym = try gc.allocSymbol("args");
    const n_sym = try gc.allocSymbol("n");

    var cond_clauses: Value = types.NIL;
    var clause_list = args;

    var clause_buf: [32]Value = undefined;
    var clause_count: usize = 0;

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

        if (clause_count < 32) {
            clause_buf[clause_count] = cond_clause;
            clause_count += 1;
        }
    }

    // Build else clause: (else (error "wrong number of arguments"))
    const err_msg = try gc.allocString("wrong number of arguments");
    const err_call = try gc.allocPair(error_sym, try gc.allocPair(err_msg, types.NIL));
    const else_clause = try gc.allocPair(else_sym, try gc.allocPair(err_call, types.NIL));

    // Build cond clauses list (in order) ending with else
    cond_clauses = try gc.allocPair(else_clause, types.NIL);
    var ci = clause_count;
    while (ci > 0) {
        ci -= 1;
        cond_clauses = try gc.allocPair(clause_buf[ci], cond_clauses);
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
    var outer_lambda = try gc.allocPair(lambda_sym, try gc.allocPair(args_sym, try gc.allocPair(let_form, types.NIL)));

    gc.no_collect -= 1;
    gc.pushRoot(&outer_lambda);
    defer gc.popRoot();
    return self.compileExpr(outer_lambda, dst, false);
}
