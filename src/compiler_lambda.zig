const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;
pub fn compileLambda(self: *Compiler, args: Value, dst: u8, name: ?[]const u8) CompileError!void {
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
    try self.emit(dst);
    try self.emitU16(idx);

    // Emit upvalue descriptors
    for (child.upvalues.items) |uv| {
        try self.emit(if (uv.is_local) 1 else 0);
        try self.emit(uv.index);
    }
}

pub fn compileBody(self: *Compiler, body: Value) CompileError!void {
    const saved_body_scope = self.in_body_scope;
    self.in_body_scope = true;

    var current = body;
    var last_dst: u8 = 0;

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
    try self.emit(last_dst);
}

pub fn compileDefine(self: *Compiler, args: Value, dst: u8) CompileError!void {
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
            try self.emit(slot);
            try self.emit(dst);
            self.locals.append(self.gc.allocator, .{
                .name = types.symbolName(target),
                .depth = self.scope_depth,
                .slot = slot,
            }) catch return CompileError.OutOfMemory;
            try self.emitOp(.load_void);
            try self.emit(dst);
            return;
        }
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emit(dst);
        try self.emitOp(.load_void);
        try self.emit(dst);
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
        try self.emit(dst);
        try self.emitOp(.load_void);
        try self.emit(dst);
        return;
    }

    return CompileError.InvalidSyntax;
}

pub fn compileSet(self: *Compiler, args: Value, dst: u8) CompileError!void {
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
            try self.emit(slot);
            try self.emit(dst);
        } else {
            try self.emitOp(.move);
            try self.emit(slot);
            try self.emit(dst);
        }
    } else if (try self.resolveUpvalue(name)) |idx| {
        try self.emitOp(.set_upvalue);
        try self.emit(idx);
        try self.emit(dst);
    } else {
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.set_global);
        try self.emitU16(sym_idx);
        try self.emit(dst);
    }
    try self.emitOp(.load_void);
    try self.emit(dst);
}

/// Compile (delay expr) as: create a promise wrapping (lambda () expr)
pub fn compileDelay(self: *Compiler, args: Value, dst: u8) CompileError!void {
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
    try child.emit(body_dst);

    // Store the lambda as a closure constant and emit closure + upvalue descriptors
    const func_val = types.makePointer(@ptrCast(child.func));
    const closure_idx = try self.addConstant(func_val);
    const thunk_reg = try self.allocReg();
    try self.emitOp(.closure);
    try self.emit(thunk_reg);
    try self.emitU16(closure_idx);

    // Emit upvalue descriptors (critical for capturing variables)
    for (child.upvalues.items) |uv| {
        try self.emit(if (uv.is_local) 1 else 0);
        try self.emit(uv.index);
    }

    // Call %make-promise-lazy(thunk) to create an unforced promise
    const sym = self.gc.allocSymbol("%make-promise-lazy") catch return CompileError.OutOfMemory;
    const sym_idx = try self.addConstant(sym);
    try self.emitOp(.get_global);
    try self.emit(dst);
    try self.emitU16(sym_idx);

    // Set up the call: dst=func, dst+1=arg
    try self.emitOp(.move);
    try self.emit(dst + 1);
    try self.emit(thunk_reg);

    try self.emitOp(.call);
    try self.emit(dst);
    try self.emit(1);

    self.freeReg(); // free thunk_reg
}

/// Compile (delay-force expr) — like delay but the result is itself forced iteratively
pub fn compileDelayForce(self: *Compiler, args: Value, dst: u8) CompileError!void {
    // delay-force is the same as delay for our purposes —
    // the iterative forcing in forceFn handles this correctly
    return compileDelay(self, args, dst);
}

pub fn compileBegin(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_void);
        try self.emit(dst);
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

