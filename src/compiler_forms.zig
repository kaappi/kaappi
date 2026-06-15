const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const Value = types.Value;
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;

// -- Derived expression forms --

pub fn compileAnd(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_true);
        try self.emit(dst);
        return;
    }

    var end_jumps: [32]usize = undefined;
    var jump_count: usize = 0;
    var current = args;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        const rest = types.cdr(current);

        if (rest == types.NIL) {
            // Last expression -- in tail position if and is
            try self.compileExpr(expr, dst, is_tail);
        } else {
            try self.compileExpr(expr, dst, false);
            try self.emitOp(.jump_false);
            try self.emit(dst);
            end_jumps[jump_count] = self.currentOffset();
            jump_count += 1;
            try self.emitI16(0); // placeholder
        }
        current = rest;
    }

    // Patch all early-exit jumps to here
    for (end_jumps[0..jump_count]) |j| {
        self.patchJump(j);
    }
}

pub fn compileOr(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_false);
        try self.emit(dst);
        return;
    }

    var end_jumps: [32]usize = undefined;
    var jump_count: usize = 0;
    var current = args;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        const rest = types.cdr(current);

        if (rest == types.NIL) {
            try self.compileExpr(expr, dst, is_tail);
        } else {
            try self.compileExpr(expr, dst, false);
            try self.emitOp(.jump_true);
            try self.emit(dst);
            end_jumps[jump_count] = self.currentOffset();
            jump_count += 1;
            try self.emitI16(0);
        }
        current = rest;
    }

    for (end_jumps[0..jump_count]) |j| {
        self.patchJump(j);
    }
}

pub fn compileWhen(self: *Compiler, args: Value, dst: u8) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const body = types.cdr(args);

    try self.compileExpr(test_expr, dst, false);
    try self.emitOp(.jump_false);
    try self.emit(dst);
    const skip_jump = self.currentOffset();
    try self.emitI16(0);

    // Compile body expressions for side effects
    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        try self.compileExpr(types.car(current), dst, false);
        current = types.cdr(current);
    }

    self.patchJump(skip_jump);
    try self.emitOp(.load_void);
    try self.emit(dst);
}

pub fn compileUnless(self: *Compiler, args: Value, dst: u8) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const body = types.cdr(args);

    try self.compileExpr(test_expr, dst, false);
    try self.emitOp(.jump_true);
    try self.emit(dst);
    const skip_jump = self.currentOffset();
    try self.emitI16(0);

    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        try self.compileExpr(types.car(current), dst, false);
        current = types.cdr(current);
    }

    self.patchJump(skip_jump);
    try self.emitOp(.load_void);
    try self.emit(dst);
}

pub fn compileCond(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_void);
        try self.emit(dst);
        return;
    }

    var end_jumps: [32]usize = undefined;
    var end_count: usize = 0;
    var current = args;
    var had_else = false;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const clause = types.car(current);
        current = types.cdr(current);
        if (!types.isPair(clause)) return CompileError.InvalidSyntax;

        const test_expr = types.car(clause);
        const clause_body = types.cdr(clause);

        // Check for else clause
        if (types.isSymbol(test_expr) and std.mem.eql(u8, types.symbolName(test_expr), "else")) {
            try compileCondBody(self, clause_body, dst, is_tail);
            had_else = true;
            break;
        }

        // Compile test
        try self.compileExpr(test_expr, dst, false);

        // Check for => form
        if (clause_body != types.NIL and types.isPair(clause_body)) {
            const maybe_arrow = types.car(clause_body);
            if (types.isSymbol(maybe_arrow) and std.mem.eql(u8, types.symbolName(maybe_arrow), "=>")) {
                // (test => proc) -- call proc with test value
                try self.emitOp(.jump_false);
                try self.emit(dst);
                const next_clause = self.currentOffset();
                try self.emitI16(0);

                // test value is in dst, compile proc and call it
                const proc_expr = types.car(types.cdr(clause_body));
                const proc_reg = try self.allocReg();
                // Move test value to arg position
                const arg_reg = try self.allocReg();
                try self.emitOp(.move);
                try self.emit(arg_reg);
                try self.emit(dst);
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

                try self.emitOp(.jump);
                end_jumps[end_count] = self.currentOffset();
                end_count += 1;
                try self.emitI16(0);

                self.patchJump(next_clause);
                continue;
            }
        }

        // Regular clause (test expr ...)
        try self.emitOp(.jump_false);
        try self.emit(dst);
        const next_clause = self.currentOffset();
        try self.emitI16(0);

        if (clause_body == types.NIL) {
            // (test) with no body -- return the test value (already in dst)
        } else {
            try compileCondBody(self, clause_body, dst, is_tail);
        }

        try self.emitOp(.jump);
        end_jumps[end_count] = self.currentOffset();
        end_count += 1;
        try self.emitI16(0);

        self.patchJump(next_clause);
    }

    // If no else clause, result is void when nothing matched
    if (!had_else) {
        try self.emitOp(.load_void);
        try self.emit(dst);
    }

    for (end_jumps[0..end_count]) |j| {
        self.patchJump(j);
    }
}

pub fn compileCondBody(self: *Compiler, body: Value, dst: u8, is_tail: bool) CompileError!void {
    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        current = types.cdr(current);
        const tail = is_tail and current == types.NIL;
        try self.compileExpr(expr, dst, tail);
    }
}

pub fn compileLet(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const first = types.car(args);

    // Check for named let: (let name ((var init) ...) body)
    if (types.isSymbol(first)) {
        return compileNamedLet(self, args, dst, is_tail);
    }

    const bindings = first;
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    // Phase 1: evaluate all inits (no new locals visible yet)
    var slots: [32]u8 = undefined;
    var names: [32][]const u8 = undefined;
    var count: usize = 0;

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;

        const var_name = types.car(binding);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;
        const init_expr = types.car(types.cdr(binding));

        const slot = try self.allocReg();
        try self.compileExpr(init_expr, slot, false);
        slots[count] = slot;
        names[count] = types.symbolName(var_name);
        count += 1;

        binding_list = types.cdr(binding_list);
    }

    // Phase 2: add all locals at once
    self.beginScope();
    for (0..count) |i| {
        try self.addLocal(names[i], slots[i]);
    }

    try compileLetBody(self, body, dst, is_tail);
    self.endScope();
}

pub fn compileLetStar(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    self.beginScope();

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;

        const var_name = types.car(binding);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;
        const init_expr = types.car(types.cdr(binding));

        const slot = try self.allocReg();
        try self.compileExpr(init_expr, slot, false);
        try self.addLocal(types.symbolName(var_name), slot);

        binding_list = types.cdr(binding_list);
    }

    try compileLetBody(self, body, dst, is_tail);
    self.endScope();
}

pub fn compileLetrec(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    // letrec uses globals so that recursive closures can reference each other.
    // This is correct because closures capture global references by name at
    // call time (via get_global), not at closure-creation time.
    //
    // Phase 1: set all variables to void in the global environment
    var syms: [32]Value = undefined;
    var inits: [32]Value = undefined;
    var count: usize = 0;

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;

        const var_name = types.car(binding);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;

        // Set to void initially
        try self.emitOp(.load_void);
        try self.emit(dst);
        const sym_idx = try self.addConstant(var_name);
        try self.emitOp(.set_global);
        try self.emitU16(sym_idx);
        try self.emit(dst);

        syms[count] = var_name;
        inits[count] = types.car(types.cdr(binding));
        count += 1;

        binding_list = types.cdr(binding_list);
    }

    // Phase 2: evaluate inits and assign to globals (variables visible during evaluation)
    for (0..count) |i| {
        try self.compileExpr(inits[i], dst, false);
        const sym_idx = try self.addConstant(syms[i]);
        try self.emitOp(.set_global);
        try self.emitU16(sym_idx);
        try self.emit(dst);
    }

    // Phase 3: compile body
    try compileLetBody(self, body, dst, is_tail);
}

pub fn compileLetrecStar(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    // letrec* is the same as letrec in our implementation since we evaluate
    // left-to-right anyway, and each variable is visible during its own init
    return compileLetrec(self, args, dst, is_tail);
}

pub fn compileNamedLet(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    const loop_name = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(rest);
    const body = types.cdr(rest);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    // Collect var names and init expressions
    var var_names: [32]Value = undefined;
    var init_exprs: [32]Value = undefined;
    var param_count: usize = 0;

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;

        var_names[param_count] = types.car(binding);
        init_exprs[param_count] = types.car(types.cdr(binding));
        param_count += 1;
        binding_list = types.cdr(binding_list);
    }

    // Build formals list (var1 var2 ...)
    var formals: Value = types.NIL;
    var i = param_count;
    while (i > 0) {
        i -= 1;
        formals = self.gc.allocPair(var_names[i], formals) catch return CompileError.OutOfMemory;
    }

    // Build lambda args: (formals body...)
    const lambda_args = self.gc.allocPair(formals, body) catch return CompileError.OutOfMemory;

    // Named let uses a global for the loop procedure so that the recursive
    // reference works (our upvalues are copy-based, not reference-based).

    // Set loop name to void in globals first
    try self.emitOp(.load_void);
    try self.emit(dst);
    const name_sym_idx = try self.addConstant(loop_name);
    try self.emitOp(.set_global);
    try self.emitU16(name_sym_idx);
    try self.emit(dst);

    // Compile the lambda to dst
    try self.compileLambda(lambda_args, dst);

    // Store the closure as a global
    try self.emitOp(.set_global);
    try self.emitU16(name_sym_idx);
    try self.emit(dst);

    // Now compile the initial call: (name init1 init2 ...)
    // dst already has the closure
    var nargs: u8 = 0;
    for (0..param_count) |j| {
        const arg_reg = try self.allocReg();
        try self.compileExpr(init_exprs[j], arg_reg, false);
        nargs += 1;
    }

    if (is_tail) {
        try self.emitOp(.tail_call);
    } else {
        try self.emitOp(.call);
    }
    try self.emit(dst);
    try self.emit(nargs);

    var k: u8 = 0;
    while (k < nargs) : (k += 1) {
        self.freeReg();
    }
}

pub fn compileDo(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const var_specs = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const test_clause = types.car(rest);
    const commands = types.cdr(rest);

    if (!types.isPair(test_clause)) return CompileError.InvalidSyntax;
    const test_expr = types.car(test_clause);
    const result_exprs = types.cdr(test_clause);

    self.beginScope();

    // Parse var specs and evaluate inits
    var var_slots: [32]u8 = undefined;
    var step_exprs: [32]Value = undefined;
    var has_step: [32]bool = undefined;
    var var_count: usize = 0;

    var spec_list = var_specs;
    while (spec_list != types.NIL) {
        if (!types.isPair(spec_list)) return CompileError.InvalidSyntax;
        const spec = types.car(spec_list);
        if (!types.isPair(spec)) return CompileError.InvalidSyntax;

        const var_name = types.car(spec);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;
        const init_expr = types.car(types.cdr(spec));

        const slot = try self.allocReg();
        try self.compileExpr(init_expr, slot, false);
        try self.addLocal(types.symbolName(var_name), slot);
        var_slots[var_count] = slot;

        const step_rest = types.cdr(types.cdr(spec));
        if (step_rest != types.NIL) {
            step_exprs[var_count] = types.car(step_rest);
            has_step[var_count] = true;
        } else {
            step_exprs[var_count] = types.VOID;
            has_step[var_count] = false;
        }

        var_count += 1;
        spec_list = types.cdr(spec_list);
    }

    // Loop start
    const loop_start = self.currentOffset();

    // Test
    try self.compileExpr(test_expr, dst, false);
    try self.emitOp(.jump_true);
    try self.emit(dst);
    const exit_jump = self.currentOffset();
    try self.emitI16(0);

    // Commands
    var cmd = commands;
    while (cmd != types.NIL) {
        if (!types.isPair(cmd)) return CompileError.InvalidSyntax;
        try self.compileExpr(types.car(cmd), dst, false);
        cmd = types.cdr(cmd);
    }

    // Step: evaluate all steps to temp registers, then assign back
    var temp_slots: [32]u8 = undefined;
    var step_count: usize = 0;
    for (0..var_count) |j| {
        if (has_step[j]) {
            const temp = try self.allocReg();
            try self.compileExpr(step_exprs[j], temp, false);
            temp_slots[step_count] = temp;
            step_count += 1;
        }
    }
    // Assign temps back to var slots
    var step_idx: usize = 0;
    for (0..var_count) |j| {
        if (has_step[j]) {
            try self.emitOp(.move);
            try self.emit(var_slots[j]);
            try self.emit(temp_slots[step_idx]);
            step_idx += 1;
        }
    }
    // Free temp registers
    for (0..step_count) |_| {
        self.freeReg();
    }

    // Jump back to loop start
    const back_offset: i16 = @intCast(@as(isize, @intCast(loop_start)) - @as(isize, @intCast(self.currentOffset())) - 3);
    try self.emitOp(.jump);
    try self.emitI16(back_offset);

    // Exit: compile result expressions
    self.patchJump(exit_jump);
    if (result_exprs == types.NIL) {
        try self.emitOp(.load_void);
        try self.emit(dst);
    } else {
        var result = result_exprs;
        while (result != types.NIL) {
            if (!types.isPair(result)) return CompileError.InvalidSyntax;
            const expr = types.car(result);
            result = types.cdr(result);
            const tail = is_tail and result == types.NIL;
            try self.compileExpr(expr, dst, tail);
        }
    }

    self.endScope();
}

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
fn appendToList(self: *Compiler, lst: Value, elem: Value) !Value {
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
            try compileCondBody(self, clause_body, dst, is_tail);
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
        try compileCondBody(self, clause_body, dst, is_tail);

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

/// Compile (let-values (((a b) expr) ...) body ...)
/// Desugars to nested call-with-values forms.
pub fn compileLetValues(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    const desugared = buildLetValues(self, bindings, body) catch return CompileError.OutOfMemory;
    return self.compileExpr(desugared, dst, is_tail);
}

/// Compile (let*-values (((a b) expr) ...) body ...)
/// Same as let-values since the nesting is inherently sequential.
pub fn compileLetStarValues(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    return compileLetValues(self, args, dst, is_tail);
}

/// Build nested call-with-values for a list of bindings.
/// (let-values (((a b) e1) ((c) e2)) body)
/// =>
/// (call-with-values (lambda () e1) (lambda (a b) (call-with-values (lambda () e2) (lambda (c) body))))
fn buildLetValues(self: *Compiler, bindings: Value, body: Value) !Value {
    const gc = self.gc;
    const lambda_sym = try gc.allocSymbol("lambda");
    const cwv_sym = try gc.allocSymbol("call-with-values");

    if (bindings == types.NIL) {
        // No more bindings — build (begin body...)
        const begin_sym = try gc.allocSymbol("begin");
        return gc.allocPair(begin_sym, body);
    }

    if (!types.isPair(bindings)) return error.InvalidSyntax;
    const binding = types.car(bindings);
    const rest_bindings = types.cdr(bindings);

    if (!types.isPair(binding)) return error.InvalidSyntax;
    const formals = types.car(binding);
    const expr_rest = types.cdr(binding);
    if (!types.isPair(expr_rest)) return error.InvalidSyntax;
    const expr = types.car(expr_rest);

    // Build the inner expression recursively
    const inner = try buildLetValues(self, rest_bindings, body);

    // Build (lambda () expr)
    const producer_body = try gc.allocPair(expr, types.NIL);
    const producer_lambda = try gc.allocPair(lambda_sym, try gc.allocPair(types.NIL, producer_body));

    // Build (lambda (formals) inner)
    const consumer_body = try gc.allocPair(inner, types.NIL);
    const consumer_lambda = try gc.allocPair(lambda_sym, try gc.allocPair(formals, consumer_body));

    // Build (call-with-values producer consumer)
    return gc.allocPair(cwv_sym, try gc.allocPair(producer_lambda, try gc.allocPair(consumer_lambda, types.NIL)));
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

/// Compile (cond-expand (feature-req expr ...) ... [(else expr ...)])
///
/// Evaluates feature requirements at compile time and compiles the body
/// of the first matching clause. Features are checked against a hardcoded
/// list and the library registry.
pub fn compileCondExpand(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const clause = types.car(current);
        current = types.cdr(current);

        if (!types.isPair(clause)) return CompileError.InvalidSyntax;
        const feature_req = types.car(clause);
        const clause_body = types.cdr(clause);

        // Check for else clause
        if (types.isSymbol(feature_req) and std.mem.eql(u8, types.symbolName(feature_req), "else")) {
            return compileCondBody(self, clause_body, dst, is_tail);
        }

        // Evaluate the feature requirement
        if (evalFeatureReq(self, feature_req)) {
            return compileCondBody(self, clause_body, dst, is_tail);
        }
    }

    // No clause matched — void
    try self.emitOp(.load_void);
    try self.emit(dst);
}

/// Evaluate a feature requirement at compile time.
fn evalFeatureReq(self: *Compiler, req: Value) bool {
    if (types.isSymbol(req)) {
        const name = types.symbolName(req);
        // Hardcoded feature identifiers
        const known_features = [_][]const u8{
            "r7rs",
            "kaappi",
            "ieee-float",
            "posix",
            "exact-closed",
        };
        for (known_features) |f| {
            if (std.mem.eql(u8, name, f)) return true;
        }
        return false;
    }

    if (types.isPair(req)) {
        const head = types.car(req);
        if (!types.isSymbol(head)) return false;
        const op = types.symbolName(head);

        if (std.mem.eql(u8, op, "and")) {
            var rest = types.cdr(req);
            while (rest != types.NIL) {
                if (!types.isPair(rest)) return false;
                if (!evalFeatureReq(self, types.car(rest))) return false;
                rest = types.cdr(rest);
            }
            return true;
        }

        if (std.mem.eql(u8, op, "or")) {
            var rest = types.cdr(req);
            while (rest != types.NIL) {
                if (!types.isPair(rest)) return false;
                if (evalFeatureReq(self, types.car(rest))) return true;
                rest = types.cdr(rest);
            }
            return false;
        }

        if (std.mem.eql(u8, op, "not")) {
            const rest = types.cdr(req);
            if (!types.isPair(rest)) return false;
            return !evalFeatureReq(self, types.car(rest));
        }

        if (std.mem.eql(u8, op, "library")) {
            // (library (name ...)) — check if library exists
            // We don't have direct access to the library registry from the compiler,
            // but we can check against known standard libraries
            const rest = types.cdr(req);
            if (!types.isPair(rest)) return false;
            const lib_name_list = types.car(rest);

            // Convert library name list to canonical string
            const lib_name = @import("library.zig").libraryNameToString(self.gc.allocator, lib_name_list) catch return false;
            defer self.gc.allocator.free(lib_name);

            // Check against known libraries
            const known_libs = [_][]const u8{
                "scheme.base",    "scheme.write",   "scheme.read",
                "scheme.inexact", "scheme.char",    "scheme.lazy",
                "scheme.time",    "scheme.file",    "scheme.cxr",
                "scheme.complex", "scheme.process-context",
            };
            for (known_libs) |l| {
                if (std.mem.eql(u8, lib_name, l)) return true;
            }
            return false;
        }
    }

    return false;
}

pub fn compileLetBody(self: *Compiler, body: Value, dst: u8, is_tail: bool) CompileError!void {
    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        current = types.cdr(current);
        const tail = is_tail and current == types.NIL;
        try self.compileExpr(expr, dst, tail);
    }
}
