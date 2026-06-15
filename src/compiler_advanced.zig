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

    var cond_clauses = clauses;
    if (!has_else) {
        // Add (else (raise var)) at the end
        const raise_sym = self.gc.allocSymbol("raise") catch return CompileError.OutOfMemory;
        // Build (raise var)
        const raise_call = self.gc.allocPair(raise_sym, self.gc.allocPair(var_sym, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        // Build (else (raise var))
        const else_sym = self.gc.allocSymbol("else") catch return CompileError.OutOfMemory;
        const else_clause = self.gc.allocPair(else_sym, self.gc.allocPair(raise_call, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        // Append to clauses
        cond_clauses = appendToList(self, clauses, else_clause) catch return CompileError.OutOfMemory;
    }

    // Build handler lambda: (lambda (var) (cond clauses...))
    const cond_sym = self.gc.allocSymbol("cond") catch return CompileError.OutOfMemory;
    const cond_form = self.gc.allocPair(cond_sym, cond_clauses) catch return CompileError.OutOfMemory;
    const handler_formals = self.gc.allocPair(var_sym, types.NIL) catch return CompileError.OutOfMemory;
    const handler_body = self.gc.allocPair(cond_form, types.NIL) catch return CompileError.OutOfMemory;
    const lambda_sym = self.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
    const handler_lambda = self.gc.allocPair(
        lambda_sym,
        self.gc.allocPair(handler_formals, handler_body) catch return CompileError.OutOfMemory,
    ) catch return CompileError.OutOfMemory;

    // Build thunk lambda: (lambda () body...)
    const thunk_formals = types.NIL;
    const thunk_lambda = self.gc.allocPair(
        lambda_sym,
        self.gc.allocPair(thunk_formals, body) catch return CompileError.OutOfMemory,
    ) catch return CompileError.OutOfMemory;

    // Build (with-exception-handler handler thunk)
    const weh_sym = self.gc.allocSymbol("with-exception-handler") catch return CompileError.OutOfMemory;
    const weh_call = self.gc.allocPair(
        weh_sym,
        self.gc.allocPair(
            handler_lambda,
            self.gc.allocPair(thunk_lambda, types.NIL) catch return CompileError.OutOfMemory,
        ) catch return CompileError.OutOfMemory,
    ) catch return CompileError.OutOfMemory;

    // Compile the transformation
    return self.compileExpr(weh_call, dst, is_tail);
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

    var end_jumps: [32]usize = undefined;
    var end_count: usize = 0;
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
            try conditionals.compileCondBody(self, clause_body, dst, is_tail);
            had_else = true;
            break;
        }

        // For each datum in the clause, compare with key
        // If any matches, jump to clause body
        if (!types.isPair(datums)) return CompileError.InvalidSyntax;

        var body_jumps: [32]usize = undefined;
        var body_jump_count: usize = 0;
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

            // Set up call: eqv_reg(key_reg, datum_reg)
            // We need contiguous regs: func, arg1, arg2
            // Move eqv? to dst, key to dst+1, datum to dst+2
            try self.emitOp(.move);
            try self.emit(dst);
            try self.emit(eqv_reg);
            const arg1_reg = try self.allocReg();
            try self.emitOp(.move);
            try self.emit(arg1_reg);
            try self.emit(key_reg);
            const arg2_reg = try self.allocReg();
            try self.emitOp(.move);
            try self.emit(arg2_reg);
            try self.emit(datum_reg);

            try self.emitOp(.call);
            try self.emit(dst);
            try self.emit(2);

            // Free temp regs
            self.freeReg(); // arg2_reg
            self.freeReg(); // arg1_reg
            self.freeReg(); // eqv_reg
            self.freeReg(); // datum_reg

            // jump_true to clause body
            try self.emitOp(.jump_true);
            try self.emit(dst);
            if (body_jump_count < 32) {
                body_jumps[body_jump_count] = self.currentOffset();
                body_jump_count += 1;
            }
            try self.emitI16(0);
        }

        // No datum matched — jump to next clause
        try self.emitOp(.jump);
        const next_clause_jump = self.currentOffset();
        try self.emitI16(0);

        // Patch body jumps to here (start of clause body)
        for (body_jumps[0..body_jump_count]) |j| {
            self.patchJump(j);
        }

        // Compile clause body
        try conditionals.compileCondBody(self, clause_body, dst, is_tail);

        // Jump to end
        try self.emitOp(.jump);
        if (end_count < 32) {
            end_jumps[end_count] = self.currentOffset();
            end_count += 1;
        }
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
    for (end_jumps[0..end_count]) |j| {
        self.patchJump(j);
    }

    // Free the key register
    self.freeReg();
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

    const lambda_sym = try gc.allocSymbol("lambda");
    const let_sym = try gc.allocSymbol("let");
    const cond_sym = try gc.allocSymbol("cond");
    const eq_sym = try gc.allocSymbol("=");
    const length_sym = try gc.allocSymbol("length");
    const apply_sym = try gc.allocSymbol("apply");
    const else_sym = try gc.allocSymbol("else");
    const error_sym = try gc.allocSymbol("error");
    const args_sym = try gc.allocSymbol("args");
    const n_sym = try gc.allocSymbol("n");

    // Build cond clauses from case-lambda clauses
    var cond_clauses: Value = types.NIL;
    var clause_list = args;

    // Collect clauses in reverse, then reverse
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

        // Build: ((= n arity) (apply (lambda formals body...) args))
        const arity_val = types.makeFixnum(arity);
        // (= n arity)
        const test_expr = try gc.allocPair(eq_sym, try gc.allocPair(n_sym, try gc.allocPair(arity_val, types.NIL)));
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
    const outer_lambda = try gc.allocPair(lambda_sym, try gc.allocPair(args_sym, try gc.allocPair(let_form, types.NIL)));

    // Compile the desugared form
    return self.compileExpr(outer_lambda, dst, false);
}
