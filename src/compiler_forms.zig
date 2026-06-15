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
