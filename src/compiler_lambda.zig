const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;
pub fn compileLambda(self: *Compiler, args: Value, dst: u16, name: ?[]const u8) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const formals = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var child = try Compiler.initChild(self);
    defer child.deinit();

    // Parse formals
    var arity: u8 = 0;
    var is_variadic = false;
    var param_list = formals;

    if (types.isSymbol(formals)) {
        // (lambda x body) -- variadic, takes all args as list
        is_variadic = true;
        arity = 0;
        const slot = child.allocReg() catch return CompileError.TooManyLocals;
        child.locals.append(child.gc.allocator, .{
            .name = types.symbolName(formals),
            .depth = 1,
            .slot = slot,
        }) catch return CompileError.OutOfMemory;
    } else {
        while (param_list != types.NIL) {
            if (types.isSymbol(param_list)) {
                // Rest parameter: (lambda (a b . rest) body)
                is_variadic = true;
                const slot = child.allocReg() catch return CompileError.TooManyLocals;
                child.locals.append(child.gc.allocator, .{
                    .name = types.symbolName(param_list),
                    .depth = 1,
                    .slot = slot,
                }) catch return CompileError.OutOfMemory;
                break;
            }
            if (!types.isPair(param_list)) return CompileError.InvalidSyntax;
            const param = types.car(param_list);
            if (!types.isSymbol(param)) return CompileError.InvalidSyntax;

            const slot = child.allocReg() catch return CompileError.TooManyLocals;
            child.locals.append(child.gc.allocator, .{
                .name = types.symbolName(param),
                .depth = 1,
                .slot = slot,
            }) catch return CompileError.OutOfMemory;
            arity += 1;
            param_list = types.cdr(param_list);
        }
    }

    child.func.arity = arity;
    child.func.is_variadic = is_variadic;
    child.func.name = name;
    child.scope_depth = 1;

    // Compile body as implicit begin
    try compileBody(&child, body);

    // Populate debug_locals for the debugger
    if (child.locals.items.len > 0) {
        const debug = self.gc.allocator.alloc(types.DebugLocal, child.locals.items.len) catch null;
        if (debug) |d| {
            for (child.locals.items, 0..) |local, i| {
                d[i] = .{ .name = local.name, .slot = local.slot };
            }
            child.func.debug_locals = d;
        }
    }

    // Box parent locals that are captured as upvalues (enables shared mutation)
    for (child.upvalues.items) |uv| {
        if (uv.is_local) {
            try self.markLocalBoxedBySlot(uv.index);
        }
    }

    // Store child function as constant and emit closure instruction
    const func_val = types.makePointer(@ptrCast(child.func));
    const idx = try self.addConstant(func_val);
    try self.emitOp(.closure);
    try self.emitU16(dst);
    try self.emitU16(idx);

    // Emit upvalue descriptors
    for (child.upvalues.items) |uv| {
        try self.emit(if (uv.is_local) 1 else 0);
        try self.emitU16(uv.index);
    }
}

pub fn compileBody(self: *Compiler, body: Value) CompileError!void {
    const saved_body_scope = self.in_body_scope;
    self.in_body_scope = true;

    // Pre-scan: register define names so macro expansion can see sibling
    // defs. Track additions for cleanup.
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
        if (self.globals) |globals| {
            for (prescan_names[0..prescan_count]) |pn| {
                if (globals.get(pn)) |val| {
                    if (val == types.VOID) _ = globals.remove(pn);
                }
            }
        }
    }

    var current = body;
    var last_dst: u16 = 0;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        const rest = types.cdr(current);

        last_dst = try self.allocReg();

        if (rest == types.NIL) {
            try self.compileExpr(expr, last_dst, true);
        } else {
            try self.compileExpr(expr, last_dst, false);
            self.freeReg();
        }

        current = rest;
    }

    self.in_body_scope = saved_body_scope;
    try self.emitOp(.@"return");
    try self.emitU16(last_dst);
}

pub fn compileDefine(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const target = types.car(args);
    const rest = types.cdr(args);

    if (types.isSymbol(target)) {
        // (define x expr)
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        const value_expr = types.car(rest);
        try self.compileExpr(value_expr, dst, false);

        // If the expression compiled to a lambda, set its name for debugging
        if (self.func.constants.items.len > 0) {
            const last_const = self.func.constants.items[self.func.constants.items.len - 1];
            if (types.isFunction(last_const)) {
                const child_func = types.toObject(last_const).as(types.Function);
                if (child_func.name == null) {
                    child_func.name = types.symbolName(target);
                }
            }
        }

        if (self.in_body_scope) {
            const slot = try self.allocReg();
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
            self.locals.append(self.gc.allocator, .{
                .name = types.symbolName(target),
                .depth = self.scope_depth,
                .slot = slot,
            }) catch return CompileError.OutOfMemory;
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    if (types.isPair(target)) {
        // (define (name args...) body) => (define name (lambda (args...) body))
        const name = types.car(target);
        if (!types.isSymbol(name)) return CompileError.InvalidSyntax;
        const param_formals = types.cdr(target);

        // Build lambda body list. compileLambda sets the function's name (used
        // for debugging and for self-tail-call detection in the body).
        const lambda_args = self.gc.allocPair(param_formals, rest) catch return CompileError.OutOfMemory;
        try compileLambda(self, lambda_args, dst, types.symbolName(name));

        const sym_idx = try self.addConstant(name);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    return CompileError.InvalidSyntax;
}

pub fn compileDefineValues(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const formals = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL or !types.isPair(rest)) return CompileError.InvalidSyntax;
    const expr = types.car(rest);

    // Collect formal names and count
    var names_buf: [64][]const u8 = undefined;
    var name_count: usize = 0;
    var rest_name: ?[]const u8 = null;
    var formal = formals;

    if (formals == types.NIL) {
        // (define-values () expr) — no bindings, just evaluate for side effects
        try self.compileExpr(expr, dst, false);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    if (types.isSymbol(formals)) {
        // (define-values x expr) — single symbol collects all values as list
        rest_name = types.symbolName(formals);
    } else {
        while (formal != types.NIL) {
            if (types.isSymbol(formal)) {
                rest_name = types.symbolName(formal);
                break;
            }
            if (!types.isPair(formal)) return CompileError.InvalidSyntax;
            const sym = types.car(formal);
            if (!types.isSymbol(sym)) return CompileError.InvalidSyntax;
            if (name_count >= 64) return CompileError.InvalidSyntax;
            names_buf[name_count] = types.symbolName(sym);
            name_count += 1;
            formal = types.cdr(formal);
        }
    }

    // Build desugared form:
    //   (define x (if #f #f)) ...  ;; pre-define all variables
    //   (call-with-values (lambda () expr) (lambda (a b c ...) (set! x a) (set! y b) ...))
    // Then compile the desugared begin block.

    // Step 1: emit (define name (if #f #f)) for each name
    for (names_buf[0..name_count]) |name| {
        const sym = self.gc.allocSymbol(name) catch return CompileError.OutOfMemory;
        // Build (define name (if #f #f))
        const void_expr = self.gc.allocPair(types.FALSE, types.NIL) catch return CompileError.OutOfMemory;
        const if_args = self.gc.allocPair(types.FALSE, void_expr) catch return CompileError.OutOfMemory;
        const if_sym = self.gc.allocSymbol("if") catch return CompileError.OutOfMemory;
        const if_form = self.gc.allocPair(if_sym, if_args) catch return CompileError.OutOfMemory;
        const def_rest = self.gc.allocPair(if_form, types.NIL) catch return CompileError.OutOfMemory;
        const def_args = self.gc.allocPair(sym, def_rest) catch return CompileError.OutOfMemory;
        try compileDefine(self, def_args, dst);
    }
    if (rest_name) |rn| {
        if (name_count == 0) {
            // Single symbol: (define-values x expr) → define x then set! to list
            const sym = self.gc.allocSymbol(rn) catch return CompileError.OutOfMemory;
            const void_expr = self.gc.allocPair(types.FALSE, types.NIL) catch return CompileError.OutOfMemory;
            const if_args = self.gc.allocPair(types.FALSE, void_expr) catch return CompileError.OutOfMemory;
            const if_sym = self.gc.allocSymbol("if") catch return CompileError.OutOfMemory;
            const if_form = self.gc.allocPair(if_sym, if_args) catch return CompileError.OutOfMemory;
            const def_rest = self.gc.allocPair(if_form, types.NIL) catch return CompileError.OutOfMemory;
            const def_args = self.gc.allocPair(sym, def_rest) catch return CompileError.OutOfMemory;
            try compileDefine(self, def_args, dst);
        } else {
            const sym = self.gc.allocSymbol(rn) catch return CompileError.OutOfMemory;
            const void_expr = self.gc.allocPair(types.FALSE, types.NIL) catch return CompileError.OutOfMemory;
            const if_args = self.gc.allocPair(types.FALSE, void_expr) catch return CompileError.OutOfMemory;
            const if_sym = self.gc.allocSymbol("if") catch return CompileError.OutOfMemory;
            const if_form = self.gc.allocPair(if_sym, if_args) catch return CompileError.OutOfMemory;
            const def_rest = self.gc.allocPair(if_form, types.NIL) catch return CompileError.OutOfMemory;
            const def_args = self.gc.allocPair(sym, def_rest) catch return CompileError.OutOfMemory;
            try compileDefine(self, def_args, dst);
        }
    }

    // Step 2: Build the consumer lambda params and set! body
    // Consumer: (lambda (p0 p1 ... [. prest]) (set! x0 p0) (set! x1 p1) ... )
    var consumer_body: Value = types.NIL;

    // Build set! forms from right to left
    if (rest_name) |rn| {
        if (name_count > 0) {
            const rn_sym = self.gc.allocSymbol(rn) catch return CompileError.OutOfMemory;
            const param_sym = self.gc.allocSymbol("__dv_rest") catch return CompileError.OutOfMemory;
            const set_rest = self.gc.allocPair(param_sym, types.NIL) catch return CompileError.OutOfMemory;
            const set_args = self.gc.allocPair(rn_sym, set_rest) catch return CompileError.OutOfMemory;
            const set_sym = self.gc.allocSymbol("set!") catch return CompileError.OutOfMemory;
            const set_form = self.gc.allocPair(set_sym, set_args) catch return CompileError.OutOfMemory;
            consumer_body = self.gc.allocPair(set_form, consumer_body) catch return CompileError.OutOfMemory;
        }
    }

    var i = name_count;
    while (i > 0) {
        i -= 1;
        const orig_sym = self.gc.allocSymbol(names_buf[i]) catch return CompileError.OutOfMemory;
        var param_name_buf: [32]u8 = undefined;
        const pname = std.fmt.bufPrint(&param_name_buf, "__dv_{d}", .{i}) catch return CompileError.OutOfMemory;
        const param_sym = self.gc.allocSymbol(pname) catch return CompileError.OutOfMemory;
        const set_rest = self.gc.allocPair(param_sym, types.NIL) catch return CompileError.OutOfMemory;
        const set_args = self.gc.allocPair(orig_sym, set_rest) catch return CompileError.OutOfMemory;
        const set_sym = self.gc.allocSymbol("set!") catch return CompileError.OutOfMemory;
        const set_form = self.gc.allocPair(set_sym, set_args) catch return CompileError.OutOfMemory;
        consumer_body = self.gc.allocPair(set_form, consumer_body) catch return CompileError.OutOfMemory;
    }

    // Build consumer params list
    var consumer_params: Value = if (rest_name != null and name_count > 0)
        self.gc.allocSymbol("__dv_rest") catch return CompileError.OutOfMemory
    else
        types.NIL;

    i = name_count;
    while (i > 0) {
        i -= 1;
        var param_name_buf: [32]u8 = undefined;
        const pname = std.fmt.bufPrint(&param_name_buf, "__dv_{d}", .{i}) catch return CompileError.OutOfMemory;
        const param_sym = self.gc.allocSymbol(pname) catch return CompileError.OutOfMemory;
        consumer_params = self.gc.allocPair(param_sym, consumer_params) catch return CompileError.OutOfMemory;
    }

    // Single-symbol case: (define-values x expr) needs list conversion
    if (name_count == 0 and rest_name != null) {
        // Desugar: (define-values x expr) → (set! x (call-with-values (lambda () expr) list))
        const rn_sym = self.gc.allocSymbol(rest_name.?) catch return CompileError.OutOfMemory;
        const list_sym = self.gc.allocSymbol("list") catch return CompileError.OutOfMemory;

        const producer_body = self.gc.allocPair(expr, types.NIL) catch return CompileError.OutOfMemory;
        const producer_lambda = self.gc.allocPair(types.NIL, producer_body) catch return CompileError.OutOfMemory;
        const lambda_sym = self.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const producer = self.gc.allocPair(lambda_sym, producer_lambda) catch return CompileError.OutOfMemory;

        const cwv_sym = self.gc.allocSymbol("call-with-values") catch return CompileError.OutOfMemory;
        const cwv_3 = self.gc.allocPair(list_sym, types.NIL) catch return CompileError.OutOfMemory;
        const cwv_2 = self.gc.allocPair(producer, cwv_3) catch return CompileError.OutOfMemory;
        const cwv_form = self.gc.allocPair(cwv_sym, cwv_2) catch return CompileError.OutOfMemory;

        const set_rest2 = self.gc.allocPair(cwv_form, types.NIL) catch return CompileError.OutOfMemory;
        const set_args2 = self.gc.allocPair(rn_sym, set_rest2) catch return CompileError.OutOfMemory;
        try compileSet(self, set_args2, dst);
        return;
    }

    // Build (lambda consumer_params consumer_body...)
    const consumer_lambda_args = self.gc.allocPair(consumer_params, consumer_body) catch return CompileError.OutOfMemory;
    const lambda_sym = self.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
    const consumer = self.gc.allocPair(lambda_sym, consumer_lambda_args) catch return CompileError.OutOfMemory;

    // Build (lambda () expr)
    const producer_body = self.gc.allocPair(expr, types.NIL) catch return CompileError.OutOfMemory;
    const producer_lambda = self.gc.allocPair(types.NIL, producer_body) catch return CompileError.OutOfMemory;
    const producer = self.gc.allocPair(lambda_sym, producer_lambda) catch return CompileError.OutOfMemory;

    // Build (call-with-values producer consumer)
    const cwv_sym = self.gc.allocSymbol("call-with-values") catch return CompileError.OutOfMemory;
    const cwv_3 = self.gc.allocPair(consumer, types.NIL) catch return CompileError.OutOfMemory;
    const cwv_2 = self.gc.allocPair(producer, cwv_3) catch return CompileError.OutOfMemory;
    const cwv_form = self.gc.allocPair(cwv_sym, cwv_2) catch return CompileError.OutOfMemory;

    // Compile the call-with-values expression
    try self.compileExpr(cwv_form, dst, false);
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

pub fn compileSet(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const target = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    if (!types.isSymbol(target)) return CompileError.InvalidSyntax;

    const value_expr = types.car(rest);
    try self.compileExpr(value_expr, dst, false);

    const name = types.symbolName(target);
    if (self.resolveLocal(name)) |slot| {
        if (self.isLocalBoxed(name)) {
            try self.emitOp(.set_box_local);
            try self.emitU16(slot);
            try self.emitU16(dst);
        } else {
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
        }
    } else if (try self.resolveUpvalue(name)) |idx| {
        try self.emitOp(.set_upvalue);
        try self.emitU16(idx);
        try self.emitU16(dst);
    } else {
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.set_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
    }
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

/// Compile (delay expr) as: create a promise wrapping (lambda () expr)
pub fn compileDelay(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const expr = types.car(args);

    // Compile (lambda () expr) using the same pattern as compileLambda
    var child = try Compiler.initChild(self);
    defer child.deinit();
    child.func.arity = 0;
    child.func.is_variadic = false;
    child.scope_depth = 1;
    const body_dst = child.allocReg() catch return CompileError.TooManyLocals;
    try child.compileExpr(expr, body_dst, true);
    try child.emitOp(.@"return");
    try child.emitU16(body_dst);

    // Store the lambda as a closure constant and emit closure + upvalue descriptors
    const func_val = types.makePointer(@ptrCast(child.func));
    const closure_idx = try self.addConstant(func_val);
    const thunk_reg = try self.allocReg();
    try self.emitOp(.closure);
    try self.emitU16(thunk_reg);
    try self.emitU16(closure_idx);

    // Emit upvalue descriptors (critical for capturing variables)
    for (child.upvalues.items) |uv| {
        try self.emit(if (uv.is_local) 1 else 0);
        try self.emitU16(uv.index);
    }

    // Call %make-promise-lazy(thunk) to create an unforced promise
    const sym = self.gc.allocSymbol("%make-promise-lazy") catch return CompileError.OutOfMemory;
    const sym_idx = try self.addConstant(sym);
    try self.emitOp(.get_global);
    try self.emitU16(dst);
    try self.emitU16(sym_idx);

    // Set up the call: dst=func, dst+1=arg
    try self.emitOp(.move);
    try self.emitU16(dst + 1);
    try self.emitU16(thunk_reg);

    try self.emitOp(.call);
    try self.emitU16(dst);
    try self.emit(1);

    self.freeReg(); // free thunk_reg
}

/// Compile (delay-force expr) — like delay but the result is itself forced iteratively
pub fn compileDelayForce(self: *Compiler, args: Value, dst: u16) CompileError!void {
    // delay-force is the same as delay for our purposes —
    // the iterative forcing in forceFn handles this correctly
    return compileDelay(self, args, dst);
}

pub fn compileBegin(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        current = types.cdr(current);
        const tail = is_tail and current == types.NIL;
        try self.compileExpr(expr, dst, tail);
    }
}

// -- Macro forms --
