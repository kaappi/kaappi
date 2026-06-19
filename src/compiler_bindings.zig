const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const Value = types.Value;
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;

var named_let_counter: u32 = 0;

fn makeUniqueLoopName(gc: *memory.GC, original: []const u8) CompileError!Value {
    named_let_counter +%= 1;
    var buf: [128]u8 = undefined;
    const name = std.fmt.bufPrint(&buf, "__nlet_{d}_{s}", .{ named_let_counter, original }) catch
        return CompileError.OutOfMemory;
    return gc.allocSymbol(name) catch return CompileError.OutOfMemory;
}

fn renameInBody(gc: *memory.GC, expr: Value, old_name: []const u8, new_sym: Value) CompileError!Value {
    if (types.isSymbol(expr)) {
        if (std.mem.eql(u8, types.symbolName(expr), old_name)) return new_sym;
        return expr;
    }
    if (types.isPair(expr)) {
        const head = types.car(expr);
        if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "quote"))
            return expr;
        const new_car = try renameInBody(gc, types.car(expr), old_name, new_sym);
        const new_cdr = try renameInBody(gc, types.cdr(expr), old_name, new_sym);
        if (new_car == types.car(expr) and new_cdr == types.cdr(expr)) return expr;
        return gc.allocPair(new_car, new_cdr) catch return CompileError.OutOfMemory;
    }
    return expr;
}

// -- Binding and iteration forms --

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

    // Tail-call optimization for (let ((var init)) var):
    // When the let is in tail position, has exactly one binding, and the body
    // is just a reference to that binding, the init IS the tail expression.
    if (is_tail and types.isPair(bindings) and types.cdr(bindings) == types.NIL) {
        const binding = types.car(bindings);
        if (types.isPair(binding)) {
            const var_name = types.car(binding);
            if (types.isSymbol(var_name) and types.isPair(body) and types.cdr(body) == types.NIL) {
                const body_expr = types.car(body);
                if (types.isSymbol(body_expr) and
                    std.mem.eql(u8, types.symbolName(body_expr), types.symbolName(var_name)))
                {
                    const init_expr = types.car(types.cdr(binding));
                    try self.compileExpr(init_expr, dst, true);
                    return;
                }
            }
        }
    }

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
    var body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    // letrec uses globals for mutually recursive closures. Use gensym'd
    // names to avoid overwriting user-visible globals like even?/odd?.
    var syms: [32]Value = undefined;
    var unique_syms: [32]Value = undefined;
    var inits: [32]Value = undefined;
    var count: usize = 0;

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;

        const var_name = types.car(binding);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;

        syms[count] = var_name;
        unique_syms[count] = try makeUniqueLoopName(self.gc, types.symbolName(var_name));
        inits[count] = types.car(types.cdr(binding));
        count += 1;
        binding_list = types.cdr(binding_list);
    }

    // Rename all letrec variables in inits and body to gensym'd names
    for (0..count) |i| {
        for (0..count) |j| {
            inits[j] = try renameInBody(self.gc, inits[j], types.symbolName(syms[i]), unique_syms[i]);
        }
        body = try renameInBody(self.gc, body, types.symbolName(syms[i]), unique_syms[i]);
    }

    // Phase 1: set all gensym'd variables to void
    for (0..count) |i| {
        try self.emitOp(.load_void);
        try self.emit(dst);
        const sym_idx = try self.addConstant(unique_syms[i]);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emit(dst);
    }

    // Phase 2: evaluate inits and assign to gensym'd globals
    for (0..count) |i| {
        try self.compileExpr(inits[i], dst, false);
        const sym_idx = try self.addConstant(unique_syms[i]);
        try self.emitOp(.define_global);
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

    // Named let uses a global for the loop procedure. Use a unique gensym'd
    // name to prevent collisions when multiple named lets use the same name.
    const unique_sym = try makeUniqueLoopName(self.gc, types.symbolName(loop_name));
    const renamed_body = try renameInBody(self.gc, body, types.symbolName(loop_name), unique_sym);
    const renamed_lambda_args = self.gc.allocPair(formals, renamed_body) catch return CompileError.OutOfMemory;

    // Use a fresh register for the closure to avoid overwriting live locals
    // (e.g., when dst=0 and a parameter is also at register 0).
    const loop_reg = try self.allocReg();

    try self.emitOp(.load_void);
    try self.emit(loop_reg);
    const name_sym_idx = try self.addConstant(unique_sym);
    try self.emitOp(.define_global);
    try self.emitU16(name_sym_idx);
    try self.emit(loop_reg);

    try self.compileLambda(renamed_lambda_args, loop_reg, types.symbolName(unique_sym));

    try self.emitOp(.define_global);
    try self.emitU16(name_sym_idx);
    try self.emit(loop_reg);

    // Compile the initial call
    const call_base = try self.allocReg();
    self.freeReg();

    if (call_base != loop_reg) {
        try self.emitOp(.move);
        try self.emit(call_base);
        try self.emit(loop_reg);
    }

    var nargs: u8 = 0;
    for (0..param_count) |j| {
        const arg_reg = try self.allocReg();
        _ = arg_reg;
        try self.compileExpr(init_exprs[j], call_base + 1 + @as(u8, @intCast(j)), false);
        nargs += 1;
    }

    if (is_tail) {
        try self.emitOp(.tail_call);
    } else {
        try self.emitOp(.call);
    }
    try self.emit(call_base);
    try self.emit(nargs);

    // Result goes to dst
    if (call_base != dst) {
        try self.emitOp(.move);
        try self.emit(dst);
        try self.emit(call_base);
    }

    var k: u8 = 0;
    while (k < nargs) : (k += 1) {
        self.freeReg();
    }
    self.freeReg(); // free loop_reg
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
    try self.patchJump(exit_jump);
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

/// Compile (let-values (((a b) expr) ...) body ...)
/// Desugars to nested call-with-values forms.
pub fn compileLetValues(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var desugared = buildLetValues(self, bindings, body) catch return CompileError.OutOfMemory;
    try self.gc.pushRoot(&desugared);
    defer self.gc.popRoot();
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
pub fn buildLetValues(self: *Compiler, bindings: Value, body: Value) !Value {
    const gc = self.gc;
    gc.no_collect += 1;
    const lambda_sym = try gc.allocSymbol("lambda");
    const cwv_sym = try gc.allocSymbol("call-with-values");

    if (bindings == types.NIL) {
        const begin_sym = try gc.allocSymbol("begin");
        const result = try gc.allocPair(begin_sym, body);
        gc.no_collect -= 1;
        return result;
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
    const result = try gc.allocPair(cwv_sym, try gc.allocPair(producer_lambda, try gc.allocPair(consumer_lambda, types.NIL)));
    gc.no_collect -= 1;
    return result;
}
