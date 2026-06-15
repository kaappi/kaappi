const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
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
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.locals.deinit(self.gc.allocator);
        self.upvalues.deinit(self.gc.allocator);
    }

    fn initChild(parent: *Compiler) CompileError!Compiler {
        const func = parent.gc.allocFunction() catch return CompileError.OutOfMemory;
        return .{
            .gc = parent.gc,
            .func = func,
            .locals = .empty,
            .upvalues = .empty,
            .parent = parent,
        };
    }

    fn emit(self: *Compiler, byte: u8) CompileError!void {
        self.func.code.append(self.gc.allocator, byte) catch return CompileError.OutOfMemory;
    }

    fn emitOp(self: *Compiler, op: OpCode) CompileError!void {
        try self.emit(@intFromEnum(op));
    }

    fn emitU16(self: *Compiler, val: u16) CompileError!void {
        try self.emit(@truncate(val >> 8));
        try self.emit(@truncate(val & 0xFF));
    }

    fn emitI16(self: *Compiler, val: i16) CompileError!void {
        const unsigned: u16 = @bitCast(val);
        try self.emitU16(unsigned);
    }

    fn addConstant(self: *Compiler, value: Value) CompileError!u16 {
        // Check if constant already exists
        for (self.func.constants.items, 0..) |c, i| {
            if (c == value) return @intCast(i);
        }
        if (self.func.constants.items.len >= 65535) return CompileError.TooManyConstants;
        self.func.constants.append(self.gc.allocator, value) catch return CompileError.OutOfMemory;
        return @intCast(self.func.constants.items.len - 1);
    }

    fn currentOffset(self: *Compiler) usize {
        return self.func.code.items.len;
    }

    fn patchJump(self: *Compiler, offset: usize) void {
        const jump_dist: i16 = @intCast(@as(isize, @intCast(self.currentOffset())) - @as(isize, @intCast(offset)) - 2);
        const unsigned: u16 = @bitCast(jump_dist);
        self.func.code.items[offset] = @truncate(unsigned >> 8);
        self.func.code.items[offset + 1] = @truncate(unsigned & 0xFF);
    }

    fn allocReg(self: *Compiler) CompileError!u8 {
        if (self.next_register >= 250) return CompileError.TooManyLocals;
        const reg = self.next_register;
        self.next_register += 1;
        return reg;
    }

    fn freeReg(self: *Compiler) void {
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

    fn beginScope(self: *Compiler) void {
        self.scope_depth += 1;
    }

    fn endScope(self: *Compiler) void {
        while (self.locals.items.len > 0 and
            self.locals.items[self.locals.items.len - 1].depth > self.scope_depth)
        {
            _ = self.locals.pop();
            self.freeReg();
        }
        self.scope_depth -= 1;
    }

    fn addLocal(self: *Compiler, name: []const u8, slot: u8) CompileError!void {
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

    fn compileExpr(self: *Compiler, expr: Value, dst: u8, is_tail: bool) CompileError!void {
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

            if (std.mem.eql(u8, name, "quote")) return self.compileQuote(args, dst);
            if (std.mem.eql(u8, name, "if")) return self.compileIf(args, dst, is_tail);
            if (std.mem.eql(u8, name, "lambda")) return self.compileLambda(args, dst);
            if (std.mem.eql(u8, name, "define")) return self.compileDefine(args, dst);
            if (std.mem.eql(u8, name, "set!")) return self.compileSet(args, dst);
            if (std.mem.eql(u8, name, "begin")) return self.compileBegin(args, dst, is_tail);
            if (std.mem.eql(u8, name, "and")) return self.compileAnd(args, dst, is_tail);
            if (std.mem.eql(u8, name, "or")) return self.compileOr(args, dst, is_tail);
            if (std.mem.eql(u8, name, "when")) return self.compileWhen(args, dst);
            if (std.mem.eql(u8, name, "unless")) return self.compileUnless(args, dst);
            if (std.mem.eql(u8, name, "cond")) return self.compileCond(args, dst, is_tail);
            if (std.mem.eql(u8, name, "let")) return self.compileLet(args, dst, is_tail);
            if (std.mem.eql(u8, name, "let*")) return self.compileLetStar(args, dst, is_tail);
            if (std.mem.eql(u8, name, "letrec")) return self.compileLetrec(args, dst, is_tail);
            if (std.mem.eql(u8, name, "letrec*")) return self.compileLetrecStar(args, dst, is_tail);
            if (std.mem.eql(u8, name, "do")) return self.compileDo(args, dst, is_tail);
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

    fn compileLambda(self: *Compiler, args: Value, dst: u8) CompileError!void {
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
            // (lambda x body) — variadic, takes all args as list
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
            const formals = types.cdr(target);

            // Build lambda body list
            const lambda_args = self.gc.allocPair(formals, rest) catch return CompileError.OutOfMemory;
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

    // -- Derived expression forms --

    fn compileAnd(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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
                // Last expression — in tail position if and is
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

    fn compileOr(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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

    fn compileWhen(self: *Compiler, args: Value, dst: u8) CompileError!void {
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

    fn compileUnless(self: *Compiler, args: Value, dst: u8) CompileError!void {
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

    fn compileCond(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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
                try self.compileCondBody(clause_body, dst, is_tail);
                had_else = true;
                break;
            }

            // Compile test
            try self.compileExpr(test_expr, dst, false);

            // Check for => form
            if (clause_body != types.NIL and types.isPair(clause_body)) {
                const maybe_arrow = types.car(clause_body);
                if (types.isSymbol(maybe_arrow) and std.mem.eql(u8, types.symbolName(maybe_arrow), "=>")) {
                    // (test => proc) — call proc with test value
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
                // (test) with no body — return the test value (already in dst)
            } else {
                try self.compileCondBody(clause_body, dst, is_tail);
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

    fn compileCondBody(self: *Compiler, body: Value, dst: u8, is_tail: bool) CompileError!void {
        var current = body;
        while (current != types.NIL) {
            if (!types.isPair(current)) return CompileError.InvalidSyntax;
            const expr = types.car(current);
            current = types.cdr(current);
            const tail = is_tail and current == types.NIL;
            try self.compileExpr(expr, dst, tail);
        }
    }

    fn compileLet(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const first = types.car(args);

        // Check for named let: (let name ((var init) ...) body)
        if (types.isSymbol(first)) {
            return self.compileNamedLet(args, dst, is_tail);
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

        try self.compileLetBody(body, dst, is_tail);
        self.endScope();
    }

    fn compileLetStar(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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

        try self.compileLetBody(body, dst, is_tail);
        self.endScope();
    }

    fn compileLetrec(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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
        try self.compileLetBody(body, dst, is_tail);
    }

    fn compileLetrecStar(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
        // letrec* is the same as letrec in our implementation since we evaluate
        // left-to-right anyway, and each variable is visible during its own init
        return self.compileLetrec(args, dst, is_tail);
    }

    fn compileNamedLet(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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

    fn compileDo(self: *Compiler, args: Value, dst: u8, is_tail: bool) CompileError!void {
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

    fn compileLetBody(self: *Compiler, body: Value, dst: u8, is_tail: bool) CompileError!void {
        var current = body;
        while (current != types.NIL) {
            if (!types.isPair(current)) return CompileError.InvalidSyntax;
            const expr = types.car(current);
            current = types.cdr(current);
            const tail = is_tail and current == types.NIL;
            try self.compileExpr(expr, dst, tail);
        }
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
// Convenience function
// ---------------------------------------------------------------------------

pub fn compileExpression(gc: *memory.GC, expr: Value) CompileError!*types.Function {
    var compiler = try Compiler.init(gc);
    defer compiler.deinit();
    try compiler.compile(expr);
    return compiler.func;
}

pub fn compileProgram(gc: *memory.GC, exprs: []const Value) CompileError!*types.Function {
    var compiler = try Compiler.init(gc);
    defer compiler.deinit();
    try compiler.compileMultiple(exprs);
    return compiler.func;
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
