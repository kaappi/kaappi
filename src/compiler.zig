const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const expander = @import("expander.zig");
const forms = @import("compiler_forms.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub const CompileError = error{
    OutOfMemory,
    InvalidSyntax,
    UndefinedVariable,
    TooManyConstants,
    TooManyLocals,
    NotImplemented,
};

const Local = struct {
    name: []const u8,
    depth: u16,
    slot: u8,
};

const Upvalue = struct {
    index: u8,
    is_local: bool,
};

pub const Compiler = struct {
    gc: *memory.GC,
    func: *types.Function,
    locals: std.ArrayList(Local),
    upvalues: std.ArrayList(Upvalue),
    macros: std.StringHashMap(Value),
    scope_depth: u16 = 0,
    next_register: u8 = 0,
    parent: ?*Compiler = null,

    pub fn init(gc: *memory.GC) CompileError!Compiler {
        const func = gc.allocFunction() catch return CompileError.OutOfMemory;
        return .{
            .gc = gc,
            .func = func,
            .locals = .empty,
            .upvalues = .empty,
            .macros = std.StringHashMap(Value).init(gc.allocator),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.locals.deinit(self.gc.allocator);
        self.upvalues.deinit(self.gc.allocator);
        self.macros.deinit();
    }

    pub fn initChild(parent: *Compiler) CompileError!Compiler {
        const func = parent.gc.allocFunction() catch return CompileError.OutOfMemory;
        return .{
            .gc = parent.gc,
            .func = func,
            .locals = .empty,
            .upvalues = .empty,
            .macros = std.StringHashMap(Value).init(parent.gc.allocator),
            .parent = parent,
        };
    }

    fn lookupMacro(self: *Compiler, name: []const u8) ?Value {
        // Check this compiler's macros first
        if (self.macros.get(name)) |v| return v;
        // Then check parent chain
        var p = self.parent;
        while (p) |par| {
            if (par.macros.get(name)) |v| return v;
            p = par.parent;
        }
        return null;
    }

    pub fn emit(self: *Compiler, byte: u8) CompileError!void {
        self.func.code.append(self.gc.allocator, byte) catch return CompileError.OutOfMemory;
    }

    pub fn emitOp(self: *Compiler, op: OpCode) CompileError!void {
        try self.emit(@intFromEnum(op));
    }

    pub fn emitU16(self: *Compiler, val: u16) CompileError!void {
        try self.emit(@truncate(val >> 8));
        try self.emit(@truncate(val & 0xFF));
    }

    pub fn emitI16(self: *Compiler, val: i16) CompileError!void {
        const unsigned: u16 = @bitCast(val);
        try self.emitU16(unsigned);
    }

    pub fn addConstant(self: *Compiler, value: Value) CompileError!u16 {
        // Check if constant already exists
        for (self.func.constants.items, 0..) |c, i| {
            if (c == value) return @intCast(i);
        }
        if (self.func.constants.items.len >= 65535) return CompileError.TooManyConstants;
        self.func.constants.append(self.gc.allocator, value) catch return CompileError.OutOfMemory;
        return @intCast(self.func.constants.items.len - 1);
    }

    pub fn currentOffset(self: *Compiler) usize {
        return self.func.code.items.len;
    }

    pub fn patchJump(self: *Compiler, offset: usize) void {
        const jump_dist: i16 = @intCast(@as(isize, @intCast(self.currentOffset())) - @as(isize, @intCast(offset)) - 2);
        const unsigned: u16 = @bitCast(jump_dist);
        self.func.code.items[offset] = @truncate(unsigned >> 8);
        self.func.code.items[offset + 1] = @truncate(unsigned & 0xFF);
    }

    pub fn allocReg(self: *Compiler) CompileError!u8 {
        if (self.next_register >= 250) return CompileError.TooManyLocals;
        const reg = self.next_register;
        self.next_register += 1;
        return reg;
    }

    pub fn freeReg(self: *Compiler) void {
        if (self.next_register > 0) self.next_register -= 1;
    }

    fn resolveLocal(self: *Compiler, name: []const u8) ?u8 {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return self.locals.items[i].slot;
            }
        }
        return null;
    }

    fn resolveUpvalue(self: *Compiler, name: []const u8) CompileError!?u8 {
        if (self.parent) |parent| {
            if (parent.resolveLocal(name)) |local_slot| {
                return try self.addUpvalue(local_slot, true);
            }
            if (try parent.resolveUpvalue(name)) |upvalue_idx| {
                return try self.addUpvalue(upvalue_idx, false);
            }
        }
        return null;
    }

    fn addUpvalue(self: *Compiler, index: u8, is_local: bool) CompileError!u8 {
        for (self.upvalues.items, 0..) |uv, i| {
            if (uv.index == index and uv.is_local == is_local) {
                return @intCast(i);
            }
        }
        self.upvalues.append(self.gc.allocator, .{ .index = index, .is_local = is_local }) catch return CompileError.OutOfMemory;
        self.func.upvalue_count = @intCast(self.upvalues.items.len);
        return @intCast(self.upvalues.items.len - 1);
    }

    // -- Scope management --

    pub fn beginScope(self: *Compiler) void {
        self.scope_depth += 1;
    }

    pub fn endScope(self: *Compiler) void {
        while (self.locals.items.len > 0 and
            self.locals.items[self.locals.items.len - 1].depth > self.scope_depth)
        {
            _ = self.locals.pop();
            self.freeReg();
        }
        self.scope_depth -= 1;
    }

    pub fn addLocal(self: *Compiler, name: []const u8, slot: u8) CompileError!void {
        self.locals.append(self.gc.allocator, .{
            .name = name,
            .depth = self.scope_depth,
            .slot = slot,
        }) catch return CompileError.OutOfMemory;
    }

    // -- Public compilation API --

    pub fn compile(self: *Compiler, expr: Value) CompileError!void {
        const dst = try self.allocReg();
        try self.compileExpr(expr, dst, false);
        try self.emitOp(.@"return");
        try self.emit(dst);
    }

    pub fn compileMultiple(self: *Compiler, exprs: []const Value) CompileError!void {
        if (exprs.len == 0) {
            const dst = try self.allocReg();
            try self.emitOp(.load_void);
            try self.emit(dst);
            try self.emitOp(.@"return");
            try self.emit(dst);
            return;
        }

        var dst: u8 = 0;
        for (exprs, 0..) |expr, i| {
            dst = try self.allocReg();
            try self.compileExpr(expr, dst, false);
            if (i < exprs.len - 1) {
                self.freeReg();
            }
        }
        try self.emitOp(.@"return");
        try self.emit(dst);
    }

    pub fn compileExpr(self: *Compiler, expr: Value, dst: u8, is_tail: bool) CompileError!void {
        if (types.isFixnum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emit(dst);
            try self.emitU16(idx);
            return;
        }

        if (expr == types.TRUE) {
            try self.emitOp(.load_true);
            try self.emit(dst);
            return;
        }
        if (expr == types.FALSE) {
            try self.emitOp(.load_false);
            try self.emit(dst);
            return;
        }
        if (expr == types.NIL) {
            try self.emitOp(.load_nil);
            try self.emit(dst);
            return;
        }

        if (types.isSymbol(expr)) {
            return self.compileVariable(expr, dst);
        }

        if (types.isString(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emit(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isChar(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emit(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isFlonum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emit(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isVector(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emit(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isBytevector(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emit(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isPair(expr)) {
            return self.compileForm(expr, dst, is_tail);
        }

        return CompileError.InvalidSyntax;
    }

    fn compileVariable(self: *Compiler, sym: Value, dst: u8) CompileError!void {
        const name = types.symbolName(sym);

        if (self.resolveLocal(name)) |slot| {
            if (slot != dst) {
                try self.emitOp(.move);
                try self.emit(dst);
                try self.emit(slot);
            }
            return;
        }

        if (try self.resolveUpvalue(name)) |idx| {
            try self.emitOp(.get_upvalue);
            try self.emit(dst);
            try self.emit(idx);
            return;
        }

        const sym_idx = try self.addConstant(sym);
        try self.emitOp(.get_global);
        try self.emit(dst);
        try self.emitU16(sym_idx);
    }

    fn compileForm(self: *Compiler, expr: Value, dst: u8, is_tail: bool) CompileError!void {
        const head = types.car(expr);
        const args = types.cdr(expr);

        if (types.isSymbol(head)) {
            const name = types.symbolName(head);

            // Primitive forms (kept in compiler.zig)
            if (std.mem.eql(u8, name, "quote")) return self.compileQuote(args, dst);
            if (std.mem.eql(u8, name, "if")) return self.compileIf(args, dst, is_tail);
            if (std.mem.eql(u8, name, "lambda")) return self.compileLambda(args, dst);
            if (std.mem.eql(u8, name, "define")) return self.compileDefine(args, dst);
            if (std.mem.eql(u8, name, "set!")) return self.compileSet(args, dst);
            if (std.mem.eql(u8, name, "begin")) return self.compileBegin(args, dst, is_tail);

            // Derived expression forms (in compiler_forms.zig)
            if (std.mem.eql(u8, name, "and")) return forms.compileAnd(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "or")) return forms.compileOr(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "when")) return forms.compileWhen(self, args, dst);
            if (std.mem.eql(u8, name, "unless")) return forms.compileUnless(self, args, dst);
            if (std.mem.eql(u8, name, "cond")) return forms.compileCond(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "let")) return forms.compileLet(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "let*")) return forms.compileLetStar(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "let-values")) return forms.compileLetValues(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "let*-values")) return forms.compileLetStarValues(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "letrec")) return forms.compileLetrec(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "letrec*")) return forms.compileLetrecStar(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "case")) return forms.compileCase(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "case-lambda")) return forms.compileCaseLambda(self, args, dst);
            if (std.mem.eql(u8, name, "cond-expand")) return forms.compileCondExpand(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "do")) return forms.compileDo(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "guard")) return forms.compileGuard(self, args, dst, is_tail);
            if (std.mem.eql(u8, name, "delay")) return self.compileDelay(args, dst);
            if (std.mem.eql(u8, name, "delay-force")) return self.compileDelayForce(args, dst);

            // Macro forms (kept in compiler.zig)
            if (std.mem.eql(u8, name, "define-syntax")) return self.compileDefineSyntax(args, dst);
            if (std.mem.eql(u8, name, "let-syntax")) return self.compileLetSyntax(args, dst, is_tail);
            if (std.mem.eql(u8, name, "letrec-syntax")) return self.compileLetrecSyntax(args, dst, is_tail);
            if (std.mem.eql(u8, name, "syntax-rules")) return CompileError.InvalidSyntax;

            // Check if head is a macro keyword
            if (self.lookupMacro(name)) |transformer| {
                const expanded = expander.expandMacro(self.gc, expr, transformer) catch return CompileError.InvalidSyntax;
                return self.compileExpr(expanded, dst, is_tail);
            }
        }

        return self.compileCall(expr, dst, is_tail);
    }

    fn compileQuote(self: *Compiler, args: Value, dst: u8) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const datum = types.car(args);
        const idx = try self.addConstant(datum);
        try self.emitOp(.load_const);
        try self.emit(dst);
        try self.emitU16(idx);
    }

    fn compileIf(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const test_expr = types.car(args);
        const rest = types.cdr(args);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        const consequent = types.car(rest);
        const rest2 = types.cdr(rest);

        // Compile test (never in tail position)
        try self.compileExpr(test_expr, dst, false);

        // Jump to else if false
        try self.emitOp(.jump_false);
        try self.emit(dst);
        const else_jump = self.currentOffset();
        try self.emitI16(0); // placeholder

        // Compile consequent (in tail position if the if is)
        try self.compileExpr(consequent, dst, is_tail);

        if (rest2 != types.NIL) {
            // Jump over else
            try self.emitOp(.jump);
            const end_jump = self.currentOffset();
            try self.emitI16(0); // placeholder

            // Patch else jump
            self.patchJump(else_jump);

            // Compile alternate (in tail position if the if is)
            const alternate = types.car(rest2);
            try self.compileExpr(alternate, dst, is_tail);

            // Patch end jump
            self.patchJump(end_jump);
        } else {
            // No else: result is void when test is false
            try self.emitOp(.jump);
            const end_jump = self.currentOffset();
            try self.emitI16(0);

            self.patchJump(else_jump);
            try self.emitOp(.load_void);
            try self.emit(dst);

            self.patchJump(end_jump);
        }
    }

    pub fn compileLambda(self: *Compiler, args: Value, dst: u8) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const formals = types.car(args);
        const body = types.cdr(args);
        if (body == types.NIL) return CompileError.InvalidSyntax;

        var child = try initChild(self);
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
        child.scope_depth = 1;

        // Compile body as implicit begin
        try child.compileBody(body);

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

    fn compileBody(self: *Compiler, body: Value) CompileError!void {
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

        try self.emitOp(.@"return");
        try self.emit(last_dst);
    }

    fn compileDefine(self: *Compiler, args: Value, dst: u8) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const target = types.car(args);
        const rest = types.cdr(args);

        if (types.isSymbol(target)) {
            // (define x expr)
            if (rest == types.NIL) return CompileError.InvalidSyntax;
            const value_expr = types.car(rest);
            try self.compileExpr(value_expr, dst, false);
            const sym_idx = try self.addConstant(target);
            try self.emitOp(.set_global);
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

            // Build lambda body list
            const lambda_args = self.gc.allocPair(param_formals, rest) catch return CompileError.OutOfMemory;
            try self.compileLambda(lambda_args, dst);

            // Set name on the function for debugging
            if (types.isClosure(self.func.constants.items[self.func.constants.items.len - 1])) {
                // Can't easily set name here due to timing, skip for now
            }

            const sym_idx = try self.addConstant(name);
            try self.emitOp(.set_global);
            try self.emitU16(sym_idx);
            try self.emit(dst);
            try self.emitOp(.load_void);
            try self.emit(dst);
            return;
        }

        return CompileError.InvalidSyntax;
    }

    fn compileSet(self: *Compiler, args: Value, dst: u8) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const target = types.car(args);
        const rest = types.cdr(args);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        if (!types.isSymbol(target)) return CompileError.InvalidSyntax;

        const value_expr = types.car(rest);
        try self.compileExpr(value_expr, dst, false);

        const name = types.symbolName(target);
        if (self.resolveLocal(name)) |slot| {
            try self.emitOp(.move);
            try self.emit(slot);
            try self.emit(dst);
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
    fn compileDelay(self: *Compiler, args: Value, dst: u8) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const expr = types.car(args);

        // Compile (lambda () expr) using the same pattern as compileLambda
        var child = try initChild(self);
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
    fn compileDelayForce(self: *Compiler, args: Value, dst: u8) CompileError!void {
        // delay-force is the same as delay for our purposes —
        // the iterative forcing in forceFn handles this correctly
        return self.compileDelay(args, dst);
    }

    fn compileBegin(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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

    fn compileDefineSyntax(self: *Compiler, args: Value, dst: u8) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const keyword = types.car(args);
        if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
        const rest = types.cdr(args);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        const transformer_spec = types.car(rest);

        // Parse the syntax-rules form and get a transformer value
        const transformer = self.parseSyntaxRules(transformer_spec) catch return CompileError.InvalidSyntax;

        // Store in macro table
        self.macros.put(types.symbolName(keyword), transformer) catch return CompileError.OutOfMemory;

        // define-syntax returns void
        try self.emitOp(.load_void);
        try self.emit(dst);
    }

    fn parseSyntaxRules(self: *Compiler, spec: Value) CompileError!Value {
        // spec = (syntax-rules (lit1 lit2 ...) (pattern1 template1) ...)
        if (!types.isPair(spec)) return CompileError.InvalidSyntax;
        const head = types.car(spec);
        if (!types.isSymbol(head)) return CompileError.InvalidSyntax;
        if (!std.mem.eql(u8, types.symbolName(head), "syntax-rules")) return CompileError.InvalidSyntax;

        const rest = types.cdr(spec);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        const literals_list = types.car(rest);
        const rules = types.cdr(rest);

        // Collect literals into an array
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

        // Collect patterns and templates
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

        // Allocate transformer
        return self.gc.allocTransformer(
            literals_buf[0..lit_count],
            patterns_buf[0..rule_count],
            templates_buf[0..rule_count],
        ) catch return CompileError.OutOfMemory;
    }

    fn compileLetSyntax(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const bindings = types.car(args);
        const body = types.cdr(args);
        if (body == types.NIL) return CompileError.InvalidSyntax;

        // Save current macro table entries so we can restore
        var saved_names: [16][]const u8 = undefined;
        var saved_values: [16]?Value = undefined;
        var saved_count: usize = 0;

        // Process syntax bindings
        var binding_list = bindings;
        while (binding_list != types.NIL) {
            if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
            const binding = types.car(binding_list);
            if (!types.isPair(binding)) return CompileError.InvalidSyntax;

            const keyword = types.car(binding);
            if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
            const transformer_spec = types.car(types.cdr(binding));
            const transformer = self.parseSyntaxRules(transformer_spec) catch return CompileError.InvalidSyntax;

            const name = types.symbolName(keyword);

            // Save any existing macro with this name
            if (saved_count < 16) {
                saved_names[saved_count] = name;
                saved_values[saved_count] = self.macros.get(name);
                saved_count += 1;
            }

            self.macros.put(name, transformer) catch return CompileError.OutOfMemory;

            binding_list = types.cdr(binding_list);
        }

        // Compile body
        var current = body;
        while (current != types.NIL) {
            if (!types.isPair(current)) return CompileError.InvalidSyntax;
            const expr = types.car(current);
            current = types.cdr(current);
            const tail = is_tail and current == types.NIL;
            try self.compileExpr(expr, dst, tail);
        }

        // Restore macro table
        for (0..saved_count) |i| {
            if (saved_values[i]) |old_val| {
                self.macros.put(saved_names[i], old_val) catch {};
            } else {
                _ = self.macros.remove(saved_names[i]);
            }
        }
    }

    fn compileLetrecSyntax(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
        // letrec-syntax is the same as let-syntax for our purposes since we
        // process all bindings before compiling the body, and the transformer
        // specs can reference each other through the macro table.
        return self.compileLetSyntax(args, dst, is_tail);
    }

    fn compileCall(self: *Compiler, expr: Value, dst: u8, is_tail: bool) CompileError!void {
        // The call instruction expects: operator at base, args at base+1, base+2, ...
        // If dst+1 != next_register (due to locals in scope), we must allocate a
        // fresh contiguous block and copy the result back to dst afterward.
        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else dst;

        // Compile operator (never in tail position)
        try self.compileExpr(types.car(expr), base, false);

        // Compile arguments (never in tail position)
        var nargs: u8 = 0;
        var arg_list = types.cdr(expr);
        while (arg_list != types.NIL) {
            if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
            const arg = types.car(arg_list);
            const arg_reg = try self.allocReg();
            try self.compileExpr(arg, arg_reg, false);
            nargs += 1;
            arg_list = types.cdr(arg_list);
        }

        if (is_tail) {
            try self.emitOp(.tail_call);
        } else {
            try self.emitOp(.call);
        }
        try self.emit(base);
        try self.emit(nargs);

        // Free argument registers
        var i: u8 = 0;
        while (i < nargs) : (i += 1) {
            self.freeReg();
        }

        // If we used a rebased register, copy result back to dst and free the temp
        if (needs_rebase) {
            try self.emitOp(.move);
            try self.emit(dst);
            try self.emit(base);
            self.freeReg(); // free base
        }
    }
};

// ---------------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------------

pub fn compileExpression(gc: *memory.GC, expr: Value) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    defer c.deinit();
    try c.compile(expr);
    return c.func;
}

pub fn compileExpressionWithMacros(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value)) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    defer {
        // Copy any new macros defined during compilation back to the VM
        // and register them as GC extra roots
        var it = c.macros.iterator();
        while (it.next()) |entry| {
            vm_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
            gc.extra_roots.append(gc.allocator, entry.value_ptr.*) catch {};
        }
        c.deinit();
    }
    // Copy existing macros from VM into the compiler
    var it = vm_macros.iterator();
    while (it.next()) |entry| {
        c.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    try c.compile(expr);
    return c.func;
}

pub fn compileProgram(gc: *memory.GC, exprs: []const Value) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    defer c.deinit();
    try c.compileMultiple(exprs);
    return c.func;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "compile integer literal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const expr = types.makeFixnum(42);
    const func = try compileExpression(&gc, expr);
    try std.testing.expect(func.code.items.len > 0);
    try std.testing.expectEqual(OpCode.load_const, @as(OpCode, @enumFromInt(func.code.items[0])));
}

test "compile symbol" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const sym = try gc.allocSymbol("x");
    const func = try compileExpression(&gc, sym);
    try std.testing.expectEqual(OpCode.get_global, @as(OpCode, @enumFromInt(func.code.items[0])));
}

test "compile if expression" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const reader_mod = @import("reader.zig");
    const expr = try reader_mod.readString(&gc, "(if #t 1 2)");
    const func = try compileExpression(&gc, expr);
    try std.testing.expect(func.code.items.len > 0);
}

test "compile lambda" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const reader_mod = @import("reader.zig");
    const expr = try reader_mod.readString(&gc, "(lambda (x) x)");
    const func = try compileExpression(&gc, expr);
    try std.testing.expect(func.code.items.len > 0);
    try std.testing.expectEqual(OpCode.closure, @as(OpCode, @enumFromInt(func.code.items[0])));
}
