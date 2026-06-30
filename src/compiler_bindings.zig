const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const Value = types.Value;
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;

const MAX_LET_BINDINGS = 256;

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
        if (types.isSymbol(head)) {
            const hname = types.symbolName(head);
            if (std.mem.eql(u8, hname, "quote"))
                return expr;
            if (std.mem.eql(u8, hname, "quasiquote")) {
                const new_tmpl = try renameInQuasiquote(gc, types.cdr(expr), old_name, new_sym);
                if (new_tmpl == types.cdr(expr)) return expr;
                return gc.allocPair(head, new_tmpl) catch return CompileError.OutOfMemory;
            }
        }
        const new_car = try renameInBody(gc, types.car(expr), old_name, new_sym);
        const new_cdr = try renameInBody(gc, types.cdr(expr), old_name, new_sym);
        if (new_car == types.car(expr) and new_cdr == types.cdr(expr)) return expr;
        return gc.allocPair(new_car, new_cdr) catch return CompileError.OutOfMemory;
    }
    return expr;
}

fn renameInQuasiquote(gc: *memory.GC, template: Value, old_name: []const u8, new_sym: Value) CompileError!Value {
    if (!types.isPair(template)) return template;
    const head = types.car(template);
    if (types.isSymbol(head)) {
        const hname = types.symbolName(head);
        if (std.mem.eql(u8, hname, "unquote") or std.mem.eql(u8, hname, "unquote-splicing")) {
            const new_cdr = try renameInBody(gc, types.cdr(template), old_name, new_sym);
            if (new_cdr == types.cdr(template)) return template;
            return gc.allocPair(head, new_cdr) catch return CompileError.OutOfMemory;
        }
    }
    const new_car = try renameInQuasiquote(gc, head, old_name, new_sym);
    const new_cdr = try renameInQuasiquote(gc, types.cdr(template), old_name, new_sym);
    if (new_car == head and new_cdr == types.cdr(template)) return template;
    return gc.allocPair(new_car, new_cdr) catch return CompileError.OutOfMemory;
}

// -- Binding and iteration forms --

pub fn compileLet(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
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
        if (types.isPair(binding) and types.isPair(types.cdr(binding))) {
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
    var slots: [MAX_LET_BINDINGS]u16 = undefined;
    var names: [MAX_LET_BINDINGS][]const u8 = undefined;
    var count: usize = 0;

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;

        const var_name = types.car(binding);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;
        if (!types.isPair(types.cdr(binding))) return CompileError.InvalidSyntax;
        const init_expr = types.car(types.cdr(binding));

        if (count >= MAX_LET_BINDINGS) return CompileError.TooManyLocals;
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

pub fn compileLetStar(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
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
        if (!types.isPair(types.cdr(binding))) return CompileError.InvalidSyntax;
        const init_expr = types.car(types.cdr(binding));

        const slot = try self.allocReg();
        try self.compileExpr(init_expr, slot, false);
        try self.addLocal(types.symbolName(var_name), slot);

        binding_list = types.cdr(binding_list);
    }

    try compileLetBody(self, body, dst, is_tail);
    self.endScope();
}

pub fn compileLetrec(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    return compileLetrecImpl(self, args, dst, is_tail, false);
}

fn compileLetrecImpl(self: *Compiler, args: Value, dst: u16, is_tail: bool, _: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var names: [MAX_LET_BINDINGS][]const u8 = undefined;
    var inits: [MAX_LET_BINDINGS]Value = undefined;
    var slots: [MAX_LET_BINDINGS]u16 = undefined;
    var count: usize = 0;

    // Parse bindings
    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        const var_name = types.car(binding);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;
        if (!types.isPair(types.cdr(binding))) return CompileError.InvalidSyntax;

        if (count >= MAX_LET_BINDINGS) return CompileError.TooManyLocals;
        names[count] = types.symbolName(var_name);
        inits[count] = types.car(types.cdr(binding));
        count += 1;
        binding_list = types.cdr(binding_list);
    }

    self.beginScope();

    // Phase 1: allocate locals initialized to void, box them for closure capture
    for (0..count) |i| {
        const slot = try self.allocReg();
        slots[i] = slot;
        try self.emitOp(.load_void);
        try self.emitU16(slot);
        try self.addLocal(names[i], slot);
        try self.markLocalBoxedBySlot(slot);
    }

    // Phase 2: evaluate inits and assign to boxed locals
    for (0..count) |i| {
        try self.compileExpr(inits[i], dst, false);
        try self.emitOp(.set_box_local);
        try self.emitU16(slots[i]);
        try self.emitU16(dst);
    }

    // Phase 3: compile body
    try compileLetBody(self, body, dst, is_tail);
    self.endScope();
}

pub fn compileLetrecStar(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    return compileLetrecImpl(self, args, dst, is_tail, true);
}

pub fn compileNamedLet(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    const loop_name = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(rest);
    const body = types.cdr(rest);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    // Collect var names and init expressions
    var var_names: [MAX_LET_BINDINGS]Value = undefined;
    var init_exprs: [MAX_LET_BINDINGS]Value = undefined;
    var param_count: usize = 0;

    var binding_list = bindings;
    while (binding_list != types.NIL) {
        if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
        const binding = types.car(binding_list);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        if (!types.isPair(types.cdr(binding))) return CompileError.InvalidSyntax;

        if (param_count >= MAX_LET_BINDINGS) return CompileError.TooManyLocals;
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
    try self.emitU16(loop_reg);
    const name_sym_idx = try self.addConstant(unique_sym);
    try self.emitOp(.define_global);
    try self.emitU16(name_sym_idx);
    try self.emitU16(loop_reg);

    try self.compileLambda(renamed_lambda_args, loop_reg, types.symbolName(unique_sym));

    try self.emitOp(.define_global);
    try self.emitU16(name_sym_idx);
    try self.emitU16(loop_reg);

    // Compile the initial call
    const call_base = try self.allocReg();
    self.freeReg();

    if (call_base != loop_reg) {
        try self.emitOp(.move);
        try self.emitU16(call_base);
        try self.emitU16(loop_reg);
    }

    if (param_count > 255) return CompileError.InternalLimit;
    const nargs: u8 = @intCast(param_count);
    for (0..param_count) |j| {
        const arg_reg = try self.allocReg();
        _ = arg_reg;
        try self.compileExpr(init_exprs[j], call_base + 1 + @as(u16, @intCast(j)), false);
    }

    if (is_tail) {
        try self.emitOp(.tail_call);
    } else {
        try self.emitOp(.call);
    }
    try self.emitU16(call_base);
    try self.emit(nargs);

    // Result goes to dst
    if (call_base != dst) {
        try self.emitOp(.move);
        try self.emitU16(dst);
        try self.emitU16(call_base);
    }

    var k: u8 = 0;
    while (k < nargs) : (k += 1) {
        self.freeReg();
    }
    self.freeReg(); // free loop_reg
}

pub fn compileDo(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
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

    // Parse var specs and evaluate inits (two-phase: all inits first, then locals)
    var var_slots: [MAX_LET_BINDINGS]u16 = undefined;
    var var_names: [MAX_LET_BINDINGS][]const u8 = undefined;
    var step_exprs: [MAX_LET_BINDINGS]Value = undefined;
    var has_step: [MAX_LET_BINDINGS]bool = undefined;
    var var_count: usize = 0;

    var spec_list = var_specs;
    while (spec_list != types.NIL) {
        if (!types.isPair(spec_list)) return CompileError.InvalidSyntax;
        const spec = types.car(spec_list);
        if (!types.isPair(spec)) return CompileError.InvalidSyntax;

        const var_name = types.car(spec);
        if (!types.isSymbol(var_name)) return CompileError.InvalidSyntax;
        if (!types.isPair(types.cdr(spec))) return CompileError.InvalidSyntax;
        const init_expr = types.car(types.cdr(spec));

        if (var_count >= MAX_LET_BINDINGS) return CompileError.TooManyLocals;
        const slot = try self.allocReg();
        try self.compileExpr(init_expr, slot, false);
        var_slots[var_count] = slot;
        var_names[var_count] = types.symbolName(var_name);

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

    // Phase 2: add all locals at once (let semantics, not let*)
    for (0..var_count) |vi| {
        try self.addLocal(var_names[vi], var_slots[vi]);
    }

    // Loop start
    const loop_start = self.currentOffset();

    // Test
    try self.compileExpr(test_expr, dst, false);
    try self.emitOp(.jump_true);
    try self.emitU16(dst);
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
    var temp_slots: [MAX_LET_BINDINGS]u16 = undefined;
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
            try self.emitU16(var_slots[j]);
            try self.emitU16(temp_slots[step_idx]);
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
        try self.emitU16(dst);
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

pub fn compileLetBody(self: *Compiler, body: Value, dst: u16, is_tail: bool) CompileError!void {
    // Pre-scan: register define names so macro expansion can see sibling
    // defs. Track which names we add so we can remove them after compilation
    // to avoid polluting the globals map for subsequent expressions.
    var prescan_names: [64][]const u8 = undefined;
    var prescan_count: usize = 0;
    if (self.globals) |globals| {
        var scan = body;
        while (scan != types.NIL and types.isPair(scan)) {
            const form = types.car(scan);
            if (types.isPair(form)) {
                const head = types.car(form);
                if (types.isSymbol(head)) {
                    const form_name = types.symbolName(head);
                    if (std.mem.eql(u8, form_name, "define")) {
                        const form_args = types.cdr(form);
                        if (form_args != types.NIL and types.isPair(form_args)) {
                            const target = types.car(form_args);
                            var def_name: ?[]const u8 = null;
                            if (types.isSymbol(target)) {
                                def_name = types.symbolName(target);
                            } else if (types.isPair(target)) {
                                const fn_name = types.car(target);
                                if (types.isSymbol(fn_name)) def_name = types.symbolName(fn_name);
                            }
                            if (def_name) |dn| {
                                if (!globals.contains(dn)) {
                                    globals.put(dn, types.VOID) catch {};
                                    if (prescan_count < 64) {
                                        prescan_names[prescan_count] = dn;
                                        prescan_count += 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            scan = types.cdr(scan);
        }
    }
    defer {
        // Clean up pre-scanned names that are still VOID (not actually defined)
        if (self.globals) |globals| {
            for (prescan_names[0..prescan_count]) |pn| {
                if (globals.get(pn)) |val| {
                    if (val == types.VOID) {
                        _ = globals.remove(pn);
                    }
                }
            }
        }
    }

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
/// All producers are evaluated in the outer scope (R7RS §4.2.2).
/// Desugars to: evaluate all producers into temp lists, then apply consumers.
pub fn compileLetValues(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    const gc = self.gc;
    gc.no_collect += 1;
    defer gc.no_collect -= 1;

    // Collect all (formals expr) pairs
    const MAX = 64;
    var formals_arr: [MAX]Value = undefined;
    var exprs: [MAX]Value = undefined;
    var count: usize = 0;

    var bl = bindings;
    while (bl != types.NIL) {
        if (!types.isPair(bl)) return CompileError.InvalidSyntax;
        const binding = types.car(bl);
        if (!types.isPair(binding)) return CompileError.InvalidSyntax;
        const expr_rest = types.cdr(binding);
        if (!types.isPair(expr_rest)) return CompileError.InvalidSyntax;
        if (count >= MAX) return CompileError.TooManyLocals;
        formals_arr[count] = types.car(binding);
        exprs[count] = types.car(expr_rest);
        count += 1;
        bl = types.cdr(bl);
    }

    // Evaluate all producers in outer scope into temp list registers
    var temp_slots: [MAX]u16 = undefined;
    const list_sym = gc.allocSymbol("list") catch return CompileError.OutOfMemory;
    const cwv_sym = gc.allocSymbol("call-with-values") catch return CompileError.OutOfMemory;
    const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;

    for (0..count) |i| {
        // Build (call-with-values (lambda () expr) list) and compile it
        const producer_body = gc.allocPair(exprs[i], types.NIL) catch return CompileError.OutOfMemory;
        const producer_lambda = gc.allocPair(lambda_sym, gc.allocPair(types.NIL, producer_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        var cwv_expr = gc.allocPair(cwv_sym, gc.allocPair(producer_lambda, gc.allocPair(list_sym, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        try gc.pushRoot(&cwv_expr);
        const slot = try self.allocReg();
        temp_slots[i] = slot;
        try self.compileExpr(cwv_expr, slot, false);
        gc.popRoot();
    }

    // Now build nested (apply (lambda (formals) ...) temp) from inside out
    self.beginScope();
    var temp_syms: [MAX]Value = undefined;
    for (0..count) |i| {
        named_let_counter +%= 1;
        var buf: [128]u8 = undefined;
        const temp_name = std.fmt.bufPrint(&buf, "__lv_temp_{d}", .{named_let_counter}) catch
            return CompileError.OutOfMemory;
        temp_syms[i] = gc.allocSymbol(temp_name) catch return CompileError.OutOfMemory;
        try self.addLocal(types.symbolName(temp_syms[i]), temp_slots[i]);
    }

    var inner = body;
    const begin_sym = gc.allocSymbol("begin") catch return CompileError.OutOfMemory;
    inner = gc.allocPair(begin_sym, inner) catch return CompileError.OutOfMemory;

    var j = count;
    while (j > 0) {
        j -= 1;
        const apply_sym = gc.allocSymbol("apply") catch return CompileError.OutOfMemory;
        const inner_body = gc.allocPair(inner, types.NIL) catch return CompileError.OutOfMemory;
        const consumer = gc.allocPair(lambda_sym, gc.allocPair(formals_arr[j], inner_body) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        const temp_sym = temp_syms[j];
        inner = gc.allocPair(apply_sym, gc.allocPair(consumer, gc.allocPair(temp_sym, types.NIL) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
    }

    var desugared = inner;
    try gc.pushRoot(&desugared);
    defer gc.popRoot();
    try self.compileExpr(desugared, dst, is_tail);
    self.endScope();
}

/// Compile (let*-values (((a b) expr) ...) body ...)
/// Sequential: each producer sees previous bindings (R7RS §4.2.2).
pub fn compileLetStarValues(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const bindings = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var desugared = buildLetValues(self, bindings, body) catch return CompileError.OutOfMemory;
    try self.gc.pushRoot(&desugared);
    defer self.gc.popRoot();
    return self.compileExpr(desugared, dst, is_tail);
}

/// Build nested call-with-values for a list of bindings.
/// (let-values (((a b) e1) ((c) e2)) body)
/// =>
/// (call-with-values (lambda () e1) (lambda (a b) (call-with-values (lambda () e2) (lambda (c) body))))
pub fn buildLetValues(self: *Compiler, bindings: Value, body: Value) !Value {
    const gc = self.gc;
    gc.no_collect += 1;
    defer gc.no_collect -= 1;
    const lambda_sym = try gc.allocSymbol("lambda");
    const cwv_sym = try gc.allocSymbol("call-with-values");

    if (bindings == types.NIL) {
        const begin_sym = try gc.allocSymbol("begin");
        return try gc.allocPair(begin_sym, body);
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
    return try gc.allocPair(cwv_sym, try gc.allocPair(producer_lambda, try gc.allocPair(consumer_lambda, types.NIL)));
}
