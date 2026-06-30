const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const expander = @import("expander.zig");
const forms = @import("compiler_forms.zig");
const advanced = @import("compiler_advanced.zig");
const passthrough = @import("compiler_passthrough.zig");
const ir_mod = @import("ir.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub const CompileError = error{
    OutOfMemory,
    InvalidSyntax,
    UndefinedVariable,
    TooManyConstants,
    TooManyLocals,
    InternalLimit,
    MacroExpansionLimit,
    JumpOutOfRange,
    NotImplemented,
};

const Local = struct {
    name: []const u8,
    depth: u16,
    slot: u16,
    is_boxed: bool = false,
};

const Upvalue = struct {
    index: u16,
    is_local: bool,
};

const build_options = @import("build_options");
const MAX_COMPILER_REGISTERS: u16 = std.math.maxInt(u16);
const MAX_MACRO_EXPANSION_DEPTH: u16 = 256;
const MAX_MACRO_EXPANSION_STEPS: u32 = 10_000;

pub const Compiler = struct {
    gc: *memory.GC,
    func: *types.Function,
    locals: std.ArrayList(Local),
    upvalues: std.ArrayList(Upvalue),
    macros: std.StringHashMap(Value),
    globals: ?*std.StringHashMap(Value) = null,
    lib_env: ?*std.StringHashMap(Value) = null,
    scope_depth: u16 = 0,
    next_register: u16 = 0,
    parent: ?*Compiler = null,
    in_body_scope: bool = false,
    current_line: u32 = 0,
    macro_expansion_depth: u16 = 0,
    macro_expansion_steps: u32 = 0,

    pub fn init(gc: *memory.GC) CompileError!Compiler {
        const func = gc.allocFunction() catch return CompileError.OutOfMemory;
        gc.extra_roots.append(gc.allocator, types.makePointer(@ptrCast(func))) catch return CompileError.OutOfMemory;
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

    pub fn unrootFunction(gc: *memory.GC, func: *types.Function) void {
        const func_val = types.makePointer(@ptrCast(func));
        for (gc.extra_roots.items, 0..) |v, i| {
            if (v == func_val) {
                _ = gc.extra_roots.orderedRemove(i);
                return;
            }
        }
    }

    pub fn initChild(parent: *Compiler) CompileError!Compiler {
        const func = parent.gc.allocFunction() catch return CompileError.OutOfMemory;
        func.env = parent.lib_env;
        func.source_line = parent.func.source_line;
        func.source_name = parent.func.source_name;
        parent.gc.extra_roots.append(parent.gc.allocator, types.makePointer(@ptrCast(func))) catch return CompileError.OutOfMemory;
        return .{
            .gc = parent.gc,
            .func = func,
            .locals = .empty,
            .upvalues = .empty,
            .macros = std.StringHashMap(Value).init(parent.gc.allocator),
            .globals = parent.globals,
            .lib_env = parent.lib_env,
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

    pub fn patchJump(self: *Compiler, offset: usize) CompileError!void {
        const dist = @as(isize, @intCast(self.currentOffset())) - @as(isize, @intCast(offset)) - 2;
        if (dist < std.math.minInt(i16) or dist > std.math.maxInt(i16)) {
            return CompileError.JumpOutOfRange;
        }
        const jump_dist: i16 = @intCast(dist);
        const unsigned: u16 = @bitCast(jump_dist);
        self.func.code.items[offset] = @truncate(unsigned >> 8);
        self.func.code.items[offset + 1] = @truncate(unsigned & 0xFF);
    }

    pub fn allocReg(self: *Compiler) CompileError!u16 {
        if (self.next_register >= MAX_COMPILER_REGISTERS) return CompileError.TooManyLocals;
        const reg = self.next_register;
        self.next_register += 1;
        // Record the high-water mark of register usage for this function.
        // This is the exact count of registers the frame can ever use, which
        // lets continuation capture copy only the live register window instead
        // of a conservative upper bound. All register allocation funnels through
        // here, so next_register's peak is a sound upper bound.
        if (self.next_register > self.func.locals_count) {
            self.func.locals_count = self.next_register;
        }
        return reg;
    }

    pub fn freeReg(self: *Compiler) void {
        if (self.next_register > 0) self.next_register -= 1;
    }

    pub fn resolveLocal(self: *Compiler, name: []const u8) ?u16 {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return self.locals.items[i].slot;
            }
        }
        return null;
    }

    pub fn isLocalBoxed(self: *Compiler, name: []const u8) bool {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return self.locals.items[i].is_boxed;
            }
        }
        return false;
    }

    pub fn markLocalBoxedBySlot(self: *Compiler, slot: u16) CompileError!void {
        for (self.locals.items) |*local| {
            if (local.slot == slot and !local.is_boxed) {
                local.is_boxed = true;
                try self.emitOp(.box_local);
                try self.emitU16(slot);
                return;
            }
        }
    }

    pub fn resolveUpvalue(self: *Compiler, name: []const u8) CompileError!?u16 {
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

    fn addUpvalue(self: *Compiler, index: u16, is_local: bool) CompileError!u16 {
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
            self.locals.items[self.locals.items.len - 1].depth >= self.scope_depth)
        {
            _ = self.locals.pop();
            self.freeReg();
        }
        self.scope_depth -= 1;
    }

    pub fn addLocal(self: *Compiler, name: []const u8, slot: u16) CompileError!void {
        self.locals.append(self.gc.allocator, .{
            .name = name,
            .depth = self.scope_depth,
            .slot = slot,
        }) catch return CompileError.OutOfMemory;
    }

    // -- Public compilation API --

    pub fn compile(self: *Compiler, expr: Value) CompileError!void {
        // Root the source datum for the whole compile: the expander and the
        // derived-form compilers allocate (triggering GC), and the datum tree
        // is otherwise reachable only through this unrooted argument. Without
        // this, not-yet-compiled tails of the form (e.g. string literals) can
        // be swept mid-compilation and end up as dangling constant-pool entries.
        var expr_root = expr;
        try self.gc.pushRoot(&expr_root);
        defer self.gc.popRoot();

        // Lower AST to IR, run analysis and optimizations, then emit bytecode.
        var ir = ir_mod.IR.init(self.gc.allocator);
        defer ir.deinit();
        var root = try ir_mod.lowerWithMacros(&ir, expr_root, &self.macros);

        // Analysis passes
        ir_mod.markTailPositions(root, false);
        ir_mod.identifyPrimitives(root);
        ir_mod.markConstants(root);

        // Optimization passes
        // Optimization passes
        root = ir_mod.foldConstants(&ir, root);
        root = ir_mod.eliminateDeadBranches(&ir, root);
        root = ir_mod.simplifyBooleans(&ir, root);
        root = ir_mod.eliminateIdentity(&ir, root);
        root = ir_mod.simplifyBegin(&ir, root);

        const dst = try self.allocReg();
        try self.compileFromNode(root, dst, false);
        try self.emitOp(.@"return");
        try self.emitU16(dst);

        // Populate debug_locals for the debugger
        if (self.locals.items.len > 0) {
            const debug = self.gc.allocator.alloc(types.DebugLocal, self.locals.items.len) catch null;
            if (debug) |d| {
                for (self.locals.items, 0..) |local, i| {
                    d[i] = .{ .name = local.name, .slot = local.slot };
                }
                self.func.debug_locals = d;
            }
        }
    }

    fn compileFromNode(self: *Compiler, node: *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
        // For directly-handled forms, use the annotation's is_tail when
        // available (set by markTailPositions). For delegated forms that
        // call into the old compiler, pass the parameter through.
        const tail = if (node.ann.is_tail) true else is_tail;
        switch (node.tag) {
            .constant => try self.emitLoadValue(dst, node.data.constant),
            .global_ref => try self.compileVariable(node.data.global_ref, dst),
            .call => try self.compileCallFromIR(node.data.call, dst, tail, node.ann.is_primitive_call),
            .@"if" => try self.compileIfFromIR(node.data.@"if", dst, tail),
            .begin => try self.compileBeginFromIR(node.data.begin, dst, tail),
            .and_form => try self.compileAndFromIR(node.data.and_form, dst, tail),
            .or_form => try self.compileOrFromIR(node.data.or_form, dst, tail),
            .when_form => try self.compileWhenFromIR(node.data.when_form, dst, tail),
            .unless_form => try self.compileUnlessFromIR(node.data.unless_form, dst, tail),
            .define => try self.compileDefineFromIR(node.data.define, dst),
            .set_form => try self.compileSetFromIR(node.data.set_form, dst),
            .lambda => try self.compileLambdaWithIR(node.data.lambda.args, dst, node.data.lambda.name),
            .let_form => try forms.compileLet(self, node.data.let_form.args, dst, tail),
            .let_star => try forms.compileLetStar(self, node.data.let_star.args, dst, tail),
            .letrec => try forms.compileLetrec(self, node.data.letrec.args, dst, tail),
            .letrec_star => try forms.compileLetrecStar(self, node.data.letrec_star.args, dst, tail),
            .do_form => try forms.compileDo(self, node.data.do_form.args, dst, tail),
            .delay => try self.compileDelay(node.data.delay.args, dst),
            .delay_force => try self.compileDelayForce(node.data.delay_force.args, dst),
            .cond => try forms.compileCond(self, node.data.cond.args, dst, tail),
            .case_form => try forms.compileCase(self, node.data.case_form.args, dst, tail),
            .case_lambda => try forms.compileCaseLambda(self, node.data.case_lambda.args, dst),
            .guard => try forms.compileGuard(self, node.data.guard.args, dst, tail),
            .quasiquote => try advanced.compileQuasiquote(self, node.data.quasiquote.args, dst),
            .parameterize => try advanced.compileParameterize(self, node.data.parameterize.args, dst, tail),
            .define_values => try self.compileDefineValues(node.data.define_values.args, dst),
            .let_values => try forms.compileLetValues(self, node.data.let_values.args, dst, tail),
            .let_star_values => try forms.compileLetStarValues(self, node.data.let_star_values.args, dst, tail),
            .define_syntax => try self.compileDefineSyntax(node.data.define_syntax.args, dst),
            .named_let => try forms.compileNamedLet(self, node.data.named_let.args, dst, tail),
            .let_syntax => try self.compileLetSyntax(node.data.let_syntax.args, dst, tail),
            .letrec_syntax => try self.compileLetrecSyntax(node.data.letrec_syntax.args, dst, tail),
            .cond_expand => try forms.compileCondExpand(self, node.data.cond_expand.args, dst, is_tail),
            .passthrough => try self.compileExpr(node.data.passthrough, dst, is_tail),
        }
    }

    fn compileIfFromIR(self: *Compiler, data: ir_mod.IfData, dst: u16, is_tail: bool) CompileError!void {
        try self.compileFromNode(data.test_expr, dst, false);
        try self.emitOp(.jump_false);
        try self.emitU16(dst);
        const else_jump = self.currentOffset();
        try self.emitI16(0);
        try self.compileFromNode(data.consequent, dst, is_tail);
        if (data.alternate) |alt| {
            try self.emitOp(.jump);
            const end_jump = self.currentOffset();
            try self.emitI16(0);
            try self.patchJump(else_jump);
            try self.compileFromNode(alt, dst, is_tail);
            try self.patchJump(end_jump);
        } else {
            try self.emitOp(.jump);
            const end_jump = self.currentOffset();
            try self.emitI16(0);
            try self.patchJump(else_jump);
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            try self.patchJump(end_jump);
        }
    }

    fn compileBeginFromIR(self: *Compiler, exprs: []const *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
        if (exprs.len == 0) {
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        for (exprs, 0..) |expr, i| {
            const tail = is_tail and i == exprs.len - 1;
            try self.compileFromNode(expr, dst, tail);
        }
    }

    fn compileCallFromIR(self: *Compiler, call: ir_mod.CallData, dst: u16, is_tail: bool, is_primitive: bool) CompileError!void {
        _ = is_primitive;
        if (call.args.len > 255) return CompileError.InternalLimit;
        const nargs: u8 = @intCast(call.args.len);

        if (!is_tail and call.operator.tag == .global_ref) {
            const sym = call.operator.data.global_ref;
            if (types.isSymbol(sym)) {
                if (self.resolveLocal(types.symbolName(sym)) == null) {
                    if ((try self.resolveUpvalue(types.symbolName(sym))) == null) {
                        const op_name = types.symbolName(sym);
                        const is_cont = std.mem.eql(u8, op_name, "call-with-current-continuation") or
                            std.mem.eql(u8, op_name, "call/cc") or
                            std.mem.eql(u8, op_name, "call/ec") or
                            std.mem.eql(u8, op_name, "call-with-escape-continuation") or
                            std.mem.eql(u8, op_name, "call-with-values") or
                            std.mem.eql(u8, op_name, "dynamic-wind") or
                            std.mem.eql(u8, op_name, "with-exception-handler");
                        if (!is_cont) {
                            return self.compileCallGlobalFromIR(sym, call.args, dst, nargs, is_tail);
                        }
                    }
                }
            }
        }

        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else dst;

        try self.compileFromNode(call.operator, base, false);

        for (call.args) |arg| {
            const arg_reg = try self.allocReg();
            try self.compileFromNode(arg, arg_reg, false);
        }

        if (is_tail) {
            try self.emitOp(.tail_call);
        } else {
            try self.emitOp(.call);
        }
        try self.emitU16(base);
        try self.emit(nargs);

        var i: u8 = 0;
        while (i < nargs) : (i += 1) {
            self.freeReg();
        }

        if (needs_rebase) {
            try self.emitOp(.move);
            try self.emitU16(dst);
            try self.emitU16(base);
            self.freeReg();
        }
    }

    fn compileCallGlobalFromIR(self: *Compiler, sym: Value, args: []const *ir_mod.Node, dst: u16, nargs: u8, is_tail: bool) CompileError!void {
        const sym_idx = try self.addConstant(sym);

        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else blk: {
            if (self.next_register == dst) {
                _ = try self.allocReg();
            }
            break :blk dst;
        };

        for (args) |arg| {
            const arg_reg = try self.allocReg();
            try self.compileFromNode(arg, arg_reg, false);
        }

        if (is_tail) {
            try self.emitOp(.tail_call_global);
        } else {
            try self.emitOp(.call_global);
        }
        try self.emitU16(base);
        try self.emitU16(sym_idx);
        try self.emit(nargs);

        var i: u8 = 0;
        while (i < nargs) : (i += 1) {
            self.freeReg();
        }

        if (needs_rebase) {
            try self.emitOp(.move);
            try self.emitU16(dst);
            try self.emitU16(base);
            self.freeReg();
        }
    }

    pub fn compileLambdaWithIR(self: *Compiler, args: Value, dst: u16, name: ?[]const u8) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const formals = types.car(args);
        const body = types.cdr(args);
        if (body == types.NIL) return CompileError.InvalidSyntax;

        var child = try Compiler.initChild(self);
        defer child.deinit();

        var arity: u8 = 0;
        var is_variadic = false;
        var param_list = formals;

        if (types.isSymbol(formals)) {
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

        // Compile body with IR lowering for each expression
        const saved_body_scope = child.in_body_scope;
        child.in_body_scope = true;

        var current = body;
        var last_dst: u16 = 0;
        while (current != types.NIL) {
            if (!types.isPair(current)) return CompileError.InvalidSyntax;
            const expr = types.car(current);
            const rest = types.cdr(current);
            last_dst = try child.allocReg();

            // Lower each body expression through IR
            var ir = ir_mod.IR.init(child.gc.allocator);
            defer ir.deinit();
            var root = try ir_mod.lowerWithMacros(&ir, expr, &child.macros);
            ir_mod.markTailPositions(root, rest == types.NIL);
            ir_mod.identifyPrimitives(root);
            ir_mod.markConstants(root);
            root = ir_mod.foldConstants(&ir, root);
            root = ir_mod.eliminateDeadBranches(&ir, root);
            root = ir_mod.simplifyBooleans(&ir, root);
            root = ir_mod.eliminateIdentity(&ir, root);
            root = ir_mod.simplifyBegin(&ir, root);

            if (rest == types.NIL) {
                try child.compileFromNode(root, last_dst, true);
            } else {
                const saved_next = child.next_register;
                try child.compileFromNode(root, last_dst, false);
                if (child.next_register == saved_next) {
                    child.freeReg();
                }
            }
            current = rest;
        }

        child.in_body_scope = saved_body_scope;
        try child.emitOp(.@"return");
        try child.emitU16(last_dst);

        if (child.locals.items.len > 0) {
            const debug = self.gc.allocator.alloc(types.DebugLocal, child.locals.items.len) catch null;
            if (debug) |d| {
                for (child.locals.items, 0..) |local, i| {
                    d[i] = .{ .name = local.name, .slot = local.slot };
                }
                child.func.debug_locals = d;
            }
        }

        for (child.upvalues.items) |uv| {
            if (uv.is_local) {
                try self.markLocalBoxedBySlot(uv.index);
            }
        }

        const func_val = types.makePointer(@ptrCast(child.func));
        const idx = try self.addConstant(func_val);
        try self.emitOp(.closure);
        try self.emitU16(dst);
        try self.emitU16(idx);

        for (child.upvalues.items) |uv| {
            try self.emit(if (uv.is_local) 1 else 0);
            try self.emitU16(uv.index);
        }
    }

    fn compileDefineFromIR(self: *Compiler, data: ir_mod.DefineData, dst: u16) CompileError!void {
        // Lower the value expression through IR for optimization
        var ir = ir_mod.IR.init(self.gc.allocator);
        defer ir.deinit();
        var val_root = try ir_mod.lowerWithMacros(&ir, data.value, &self.macros);
        ir_mod.identifyPrimitives(val_root);
        ir_mod.markConstants(val_root);
        val_root = ir_mod.foldConstants(&ir, val_root);
        val_root = ir_mod.eliminateDeadBranches(&ir, val_root);
        val_root = ir_mod.simplifyBooleans(&ir, val_root);
        val_root = ir_mod.eliminateIdentity(&ir, val_root);
        val_root = ir_mod.simplifyBegin(&ir, val_root);
        try self.compileFromNode(val_root, dst, false);

        if (self.func.constants.items.len > 0) {
            const last_const = self.func.constants.items[self.func.constants.items.len - 1];
            if (types.isFunction(last_const)) {
                const child_func = types.toObject(last_const).as(types.Function);
                if (child_func.name == null) {
                    child_func.name = types.symbolName(data.name);
                }
            }
        }

        if (self.in_body_scope) {
            const slot = try self.allocReg();
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
            self.locals.append(self.gc.allocator, .{
                .name = types.symbolName(data.name),
                .depth = self.scope_depth,
                .slot = slot,
            }) catch return CompileError.OutOfMemory;
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        const sym_idx = try self.addConstant(data.name);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
    }

    fn compileSetFromIR(self: *Compiler, data: ir_mod.SetData, dst: u16) CompileError!void {
        const name = types.symbolName(data.name);

        // Lower the value expression through IR for optimization
        var ir = ir_mod.IR.init(self.gc.allocator);
        defer ir.deinit();
        var val_root = try ir_mod.lowerWithMacros(&ir, data.value, &self.macros);
        ir_mod.identifyPrimitives(val_root);
        ir_mod.markConstants(val_root);
        val_root = ir_mod.foldConstants(&ir, val_root);
        val_root = ir_mod.eliminateDeadBranches(&ir, val_root);
        val_root = ir_mod.simplifyBooleans(&ir, val_root);
        val_root = ir_mod.eliminateIdentity(&ir, val_root);
        val_root = ir_mod.simplifyBegin(&ir, val_root);
        try self.compileFromNode(val_root, dst, false);

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
            const sym_idx = try self.addConstant(data.name);
            try self.emitOp(.set_global);
            try self.emitU16(sym_idx);
            try self.emitU16(dst);
        }
        try self.emitOp(.load_void);
        try self.emitU16(dst);
    }

    fn compileAndFromIR(self: *Compiler, exprs: []const *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
        if (exprs.len == 0) {
            try self.emitOp(.load_true);
            try self.emitU16(dst);
            return;
        }
        var end_jumps: std.ArrayList(usize) = .empty;
        defer end_jumps.deinit(self.gc.allocator);
        for (exprs, 0..) |expr, i| {
            if (i == exprs.len - 1) {
                try self.compileFromNode(expr, dst, is_tail);
            } else {
                try self.compileFromNode(expr, dst, false);
                try self.emitOp(.jump_false);
                try self.emitU16(dst);
                end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
                try self.emitI16(0);
            }
        }
        for (end_jumps.items) |j| {
            try self.patchJump(j);
        }
    }

    fn compileOrFromIR(self: *Compiler, exprs: []const *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
        if (exprs.len == 0) {
            try self.emitOp(.load_false);
            try self.emitU16(dst);
            return;
        }
        var end_jumps: std.ArrayList(usize) = .empty;
        defer end_jumps.deinit(self.gc.allocator);
        for (exprs, 0..) |expr, i| {
            if (i == exprs.len - 1) {
                try self.compileFromNode(expr, dst, is_tail);
            } else {
                try self.compileFromNode(expr, dst, false);
                try self.emitOp(.jump_true);
                try self.emitU16(dst);
                end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
                try self.emitI16(0);
            }
        }
        for (end_jumps.items) |j| {
            try self.patchJump(j);
        }
    }

    fn compileWhenFromIR(self: *Compiler, data: ir_mod.CondBodyData, dst: u16, is_tail: bool) CompileError!void {
        try self.compileFromNode(data.test_expr, dst, false);
        try self.emitOp(.jump_false);
        try self.emitU16(dst);
        const false_jump = self.currentOffset();
        try self.emitI16(0);

        for (data.body, 0..) |expr, i| {
            const tail = is_tail and i == data.body.len - 1;
            try self.compileFromNode(expr, dst, tail);
        }

        try self.emitOp(.jump);
        const end_jump = self.currentOffset();
        try self.emitI16(0);
        try self.patchJump(false_jump);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        try self.patchJump(end_jump);
    }

    fn compileUnlessFromIR(self: *Compiler, data: ir_mod.CondBodyData, dst: u16, is_tail: bool) CompileError!void {
        try self.compileFromNode(data.test_expr, dst, false);
        try self.emitOp(.jump_true);
        try self.emitU16(dst);
        const true_jump = self.currentOffset();
        try self.emitI16(0);

        for (data.body, 0..) |expr, i| {
            const tail = is_tail and i == data.body.len - 1;
            try self.compileFromNode(expr, dst, tail);
        }

        try self.emitOp(.jump);
        const end_jump = self.currentOffset();
        try self.emitI16(0);
        try self.patchJump(true_jump);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        try self.patchJump(end_jump);
    }

    pub fn compileMultiple(self: *Compiler, exprs: []const Value) CompileError!void {
        // Keep all source data rooted across compilation (see compile()).
        const roots_base = self.gc.extra_roots.items.len;
        defer self.gc.extra_roots.shrinkRetainingCapacity(roots_base);
        for (exprs) |e| self.gc.extra_roots.append(self.gc.allocator, e) catch return CompileError.OutOfMemory;

        if (exprs.len == 0) {
            const dst = try self.allocReg();
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            try self.emitOp(.@"return");
            try self.emitU16(dst);
            return;
        }

        var dst: u16 = 0;
        for (exprs, 0..) |expr, i| {
            // Lower each expression through the IR pipeline.
            var ir = ir_mod.IR.init(self.gc.allocator);
            defer ir.deinit();
            var root = try ir_mod.lowerWithMacros(&ir, expr, &self.macros);
            ir_mod.markTailPositions(root, false);
            ir_mod.identifyPrimitives(root);
            ir_mod.markConstants(root);
            root = ir_mod.foldConstants(&ir, root);
            root = ir_mod.eliminateDeadBranches(&ir, root);
            root = ir_mod.simplifyBooleans(&ir, root);
            root = ir_mod.eliminateIdentity(&ir, root);
            root = ir_mod.simplifyBegin(&ir, root);

            dst = try self.allocReg();
            try self.compileFromNode(root, dst, false);
            if (i < exprs.len - 1) {
                self.freeReg();
            }
        }
        try self.emitOp(.@"return");
        try self.emitU16(dst);

        // Populate debug_locals for the debugger
        if (self.locals.items.len > 0) {
            const debug = self.gc.allocator.alloc(types.DebugLocal, self.locals.items.len) catch null;
            if (debug) |d| {
                for (self.locals.items, 0..) |local, i| {
                    d[i] = .{ .name = local.name, .slot = local.slot };
                }
                self.func.debug_locals = d;
            }
        }
    }

    pub fn compileExpr(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
        if (types.isFixnum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (expr == types.TRUE) {
            try self.emitOp(.load_true);
            try self.emitU16(dst);
            return;
        }
        if (expr == types.FALSE) {
            try self.emitOp(.load_false);
            try self.emitU16(dst);
            return;
        }
        if (expr == types.NIL) {
            try self.emitOp(.load_nil);
            try self.emitU16(dst);
            return;
        }

        if (types.isSymbol(expr)) {
            return self.compileVariable(expr, dst);
        }

        if (types.isString(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isChar(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isFlonum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isBignum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isComplex(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isRationalObj(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isVector(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isBytevector(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isPair(expr)) {
            if (self.gc.source_lines.get(expr)) |line| {
                if (line != self.current_line and line > 0) {
                    self.current_line = line;
                    self.func.line_table.append(self.gc.allocator, .{
                        .offset = @intCast(self.func.code.items.len),
                        .line = line,
                    }) catch {};
                }
            }
            return self.compileForm(expr, dst, is_tail);
        }

        return CompileError.InvalidSyntax;
    }

    fn compileVariable(self: *Compiler, sym: Value, dst: u16) CompileError!void {
        const name = types.symbolName(sym);

        if (self.resolveLocal(name)) |slot| {
            if (self.isLocalBoxed(name)) {
                try self.emitOp(.get_box_local);
                try self.emitU16(dst);
                try self.emitU16(slot);
            } else if (slot != dst) {
                try self.emitOp(.move);
                try self.emitU16(dst);
                try self.emitU16(slot);
            }
            return;
        }

        if (try self.resolveUpvalue(name)) |idx| {
            try self.emitOp(.get_upvalue);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        const sym_idx = try self.addConstant(sym);
        try self.emitOp(.get_global);
        try self.emitU16(dst);
        try self.emitU16(sym_idx);
    }

    fn compileForm(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
        const head = types.car(expr);
        const args = types.cdr(expr);

        if (types.isSymbol(head)) {
            const name = types.symbolName(head);

            // Check if this identifier came from a macro template (hygienic rename).
            // Hygienic names like __hyg_N_let or __hyg_N___hyg_M_let should
            // be treated as their base form. Strip all __hyg_N_ prefixes.
            var effective_name = name;
            while (std.mem.startsWith(u8, effective_name, "__hyg_")) {
                if (std.mem.indexOfScalar(u8, effective_name[6..], '_')) |sep| {
                    effective_name = effective_name[6 + sep + 1 ..];
                } else break;
            }

            // If the effective name is a local variable but NOT a hygienic
            // rename, it's a function call, not a special form.
            const is_shadowed = self.resolveLocal(name) != null and
                std.mem.eql(u8, effective_name, name);

            // Primitive forms — only if not shadowed by local binding
            if (!is_shadowed) {
                if (std.mem.eql(u8, effective_name, "quote")) return passthrough.compileQuote(self, args, dst);
                if (std.mem.eql(u8, effective_name, "if")) return passthrough.compileIf(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "lambda")) return self.compileLambda(args, dst, null);
                if (std.mem.eql(u8, effective_name, "define")) return self.compileDefine(args, dst);
                if (std.mem.eql(u8, effective_name, "define-values")) return self.compileDefineValues(args, dst);
                if (std.mem.eql(u8, effective_name, "set!")) return self.compileSet(args, dst);
                if (std.mem.eql(u8, effective_name, "begin")) return self.compileBegin(args, dst, is_tail);

                // Derived expression forms (in compiler_forms.zig)
                if (std.mem.eql(u8, effective_name, "and")) return forms.compileAnd(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "or")) return forms.compileOr(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "when")) return forms.compileWhen(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "unless")) return forms.compileUnless(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "cond")) return forms.compileCond(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let")) return forms.compileLet(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let*")) return forms.compileLetStar(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let-values")) return forms.compileLetValues(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let*-values")) return forms.compileLetStarValues(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "letrec")) return forms.compileLetrec(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "letrec*")) return forms.compileLetrecStar(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "case")) return forms.compileCase(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "case-lambda")) return forms.compileCaseLambda(self, args, dst);
                if (std.mem.eql(u8, effective_name, "cond-expand")) return forms.compileCondExpand(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "do")) return forms.compileDo(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "guard")) return forms.compileGuard(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "delay")) return self.compileDelay(args, dst);
                if (std.mem.eql(u8, effective_name, "delay-force")) return self.compileDelayForce(args, dst);

                // Quasiquote
                if (std.mem.eql(u8, effective_name, "quasiquote")) return advanced.compileQuasiquote(self, args, dst);

                // Parameterize
                if (std.mem.eql(u8, effective_name, "parameterize")) return advanced.compileParameterize(self, args, dst, is_tail);

                // syntax-error
                if (std.mem.eql(u8, effective_name, "syntax-error")) return CompileError.InvalidSyntax;

                // Macro forms (kept in compiler.zig)
                if (std.mem.eql(u8, effective_name, "define-syntax")) return self.compileDefineSyntax(args, dst);
                if (std.mem.eql(u8, effective_name, "let-syntax")) return self.compileLetSyntax(args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "letrec-syntax")) return self.compileLetrecSyntax(args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "syntax-rules")) return CompileError.InvalidSyntax;
            } // end if (!is_local)

            // Check if head is a macro keyword
            if (self.lookupMacro(name)) |transformer| {
                if (self.macro_expansion_depth >= MAX_MACRO_EXPANSION_DEPTH or
                    self.macro_expansion_steps >= MAX_MACRO_EXPANSION_STEPS)
                {
                    return CompileError.MacroExpansionLimit;
                }
                self.macro_expansion_depth += 1;
                self.macro_expansion_steps += 1;
                defer self.macro_expansion_depth -= 1;
                // Build merged macro view including parent scopes
                var merged_macros = std.StringHashMap(Value).init(self.gc.allocator);
                defer merged_macros.deinit();
                var p: ?*Compiler = self.parent;
                while (p) |par| : (p = par.parent) {
                    var it = par.macros.iterator();
                    while (it.next()) |entry| {
                        merged_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
                    }
                }
                var it = self.macros.iterator();
                while (it.next()) |entry| {
                    merged_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
                }
                const tx = types.toObject(transformer).as(types.Transformer);
                // Temporarily add/modify globals so the expander doesn't
                // rename template free references.
                const TempGlobal = struct { name: []const u8, old_val: ?Value, was_present: bool };
                var temp_globals: [128]TempGlobal = undefined;
                var temp_global_count: usize = 0;
                if (self.globals) |g| {
                    for (tx.captured_locals) |cap| {
                        if (!g.contains(cap.name) and temp_global_count < 128) {
                            temp_globals[temp_global_count] = .{ .name = cap.name, .old_val = null, .was_present = false };
                            temp_global_count += 1;
                            g.put(cap.name, types.VOID) catch {};
                        }
                    }
                    if (tx.def_env) |env| {
                        var env_it = env.iterator();
                        while (env_it.next()) |entry| {
                            if (!g.contains(entry.key_ptr.*) and temp_global_count < 128) {
                                temp_globals[temp_global_count] = .{ .name = entry.key_ptr.*, .old_val = null, .was_present = false };
                                temp_global_count += 1;
                                g.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
                            }
                        }
                    }
                    // Temporarily mark non-procedure free globals as VOID so
                    // renameForHygiene preserves them.
                    const vm_mod2 = @import("vm.zig");
                    if (vm_mod2.vm_instance) |vm| {
                        var cand_names: [64][]const u8 = undefined;
                        var cand_count: usize = 0;
                        var pv_names: [64][]const u8 = undefined;
                        var pv_count: usize = 0;
                        for (tx.patterns[0..tx.num_rules]) |pat| {
                            if (!passthrough.collectSymbols(pat, &pv_names, &pv_count)) return CompileError.InternalLimit;
                        }
                        for (tx.templates[0..tx.num_rules]) |tmpl| {
                            if (!passthrough.collectFreeRefs(tmpl, pv_names[0..pv_count], tx.literals, &cand_names, &cand_count)) {
                                return CompileError.InternalLimit;
                            }
                        }
                        for (cand_names[0..cand_count]) |cname| {
                            const in_g = g.get(cname);
                            const in_vm = if (vm.globals.count() > 0) vm.globals.get(cname) else null;
                            const existing = in_g orelse in_vm;
                            if (existing) |val| {
                                if (!types.isProcedure(val) and !types.isTransformer(val) and val != types.VOID) {
                                    if (temp_global_count < 128) {
                                        temp_globals[temp_global_count] = .{ .name = cname, .old_val = in_g, .was_present = in_g != null };
                                        temp_global_count += 1;
                                        g.put(cname, types.VOID) catch {};
                                    }
                                }
                            }
                        }
                    }
                }
                defer if (self.globals) |g| {
                    for (temp_globals[0..temp_global_count]) |tg| {
                        if (tg.was_present) {
                            g.put(tg.name, tg.old_val.?) catch {};
                        } else {
                            _ = g.remove(tg.name);
                        }
                    }
                };
                // Suppress GC during expansion: the expanded form isn't
                // rooted until pushRoot below, so a collection triggered
                // by allocPair inside expandMacro could free AST nodes
                // that the partially-built result references.
                self.gc.no_collect += 1;
                const expanded = expander.expandMacro(self.gc, expr, transformer, self.globals, &merged_macros) catch |err| {
                    self.gc.no_collect -= 1;
                    return switch (err) {
                        error.OutOfMemory => CompileError.OutOfMemory,
                        error.ScopeTableFull, error.PatternTooComplex => CompileError.InternalLimit,
                        error.NoMatchingPattern, error.EllipsisCountMismatch => CompileError.InvalidSyntax,
                    };
                };
                var expanded_root = expanded;
                try self.gc.pushRoot(&expanded_root);
                defer self.gc.popRoot();
                self.gc.no_collect -= 1;
                // Inject captured locals from the macro definition site
                const saved_locals_len = self.locals.items.len;
                for (tx.captured_locals) |cap| {
                    self.locals.append(self.gc.allocator, .{
                        .name = cap.name,
                        .depth = self.scope_depth,
                        .slot = cap.slot,
                    }) catch {};
                }
                const result_err = self.compileExpr(expanded_root, dst, is_tail);
                // Remove injected locals
                while (self.locals.items.len > saved_locals_len) {
                    _ = self.locals.pop();
                }
                return result_err;
            }
        }

        if (is_tail and types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "apply")) {
            if (self.resolveLocal(types.symbolName(head)) == null) {
                return passthrough.compileApplyTail(self, expr, dst);
            }
        }

        return passthrough.compileCall(self, expr, dst, is_tail);
    }

    const compiler_lambda = @import("compiler_lambda.zig");

    pub fn compileLambda(self: *Compiler, args: Value, dst: u16, name: ?[]const u8) CompileError!void {
        return compiler_lambda.compileLambda(self, args, dst, name);
    }

    fn compileBody(self: *Compiler, body: Value) CompileError!void {
        return compiler_lambda.compileBody(self, body);
    }

    fn compileDefine(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDefine(self, args, dst);
    }

    fn compileDefineValues(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDefineValues(self, args, dst);
    }

    fn compileSet(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileSet(self, args, dst);
    }

    fn compileBegin(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
        return compiler_lambda.compileBegin(self, args, dst, is_tail);
    }

    fn compileDelay(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDelay(self, args, dst);
    }

    fn compileDelayForce(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDelayForce(self, args, dst);
    }

    // -- Macro forms --

    fn compileDefineSyntax(self: *Compiler, args: Value, dst: u16) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const keyword = types.car(args);
        if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
        const rest = types.cdr(args);
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        const transformer_spec = types.car(rest);

        // Parse the syntax-rules form and get a transformer value
        const transformer = passthrough.parseSyntaxRules(self, transformer_spec) catch return CompileError.InvalidSyntax;

        const tx = types.toObject(transformer).as(types.Transformer);
        if (self.lib_env) |env| {
            tx.def_env = env;
        }

        // Store in macro table
        self.macros.put(types.symbolName(keyword), transformer) catch return CompileError.OutOfMemory;

        // define-syntax returns void
        try self.emitOp(.load_void);
        try self.emitU16(dst);
    }

    fn compileLetSyntax(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const bindings = types.car(args);
        const body = types.cdr(args);
        if (body == types.NIL) return CompileError.InvalidSyntax;

        // Save current macro table entries so we can restore
        var saved_names: std.ArrayList([]const u8) = .empty;
        defer saved_names.deinit(self.gc.allocator);
        var saved_values: std.ArrayList(?Value) = .empty;
        defer saved_values.deinit(self.gc.allocator);

        // Process syntax bindings
        var binding_list = bindings;
        while (binding_list != types.NIL) {
            if (!types.isPair(binding_list)) return CompileError.InvalidSyntax;
            const binding = types.car(binding_list);
            if (!types.isPair(binding)) return CompileError.InvalidSyntax;

            const keyword = types.car(binding);
            if (!types.isSymbol(keyword)) return CompileError.InvalidSyntax;
            const transformer_spec = types.car(types.cdr(binding));
            const transformer = passthrough.parseSyntaxRules(self, transformer_spec) catch return CompileError.InvalidSyntax;

            const name = types.symbolName(keyword);

            // Save any existing macro with this name
            saved_names.append(self.gc.allocator, name) catch return CompileError.OutOfMemory;
            saved_values.append(self.gc.allocator, self.macros.get(name)) catch return CompileError.OutOfMemory;

            // Capture current locals for referential transparency
            if (self.locals.items.len > 0) {
                const tx = types.toObject(transformer).as(types.Transformer);
                const caps = self.gc.allocator.alloc(types.CapturedLocal, self.locals.items.len) catch return CompileError.OutOfMemory;
                if (caps.len > 0) {
                    for (self.locals.items, 0..) |local, ci| {
                        caps[ci] = .{ .name = local.name, .slot = local.slot };
                    }
                    tx.captured_locals = caps;
                }
            }
            self.macros.put(name, transformer) catch return CompileError.OutOfMemory;

            binding_list = types.cdr(binding_list);
        }

        // Compile body in a new scope
        self.beginScope();
        const saved_body_scope = self.in_body_scope;
        self.in_body_scope = true;
        var current = body;
        while (current != types.NIL) {
            if (!types.isPair(current)) return CompileError.InvalidSyntax;
            const expr = types.car(current);
            current = types.cdr(current);
            const tail = is_tail and current == types.NIL;
            try self.compileExpr(expr, dst, tail);
        }
        self.in_body_scope = saved_body_scope;
        self.endScope();

        // Restore macro table
        for (saved_names.items, saved_values.items) |name, saved_val| {
            if (saved_val) |old_val| {
                self.macros.put(name, old_val) catch {};
            } else {
                _ = self.macros.remove(name);
            }
        }
    }

    fn compileLetrecSyntax(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
        // letrec-syntax is the same as let-syntax for our purposes since we
        // process all bindings before compiling the body, and the transformer
        // specs can reference each other through the macro table.
        return self.compileLetSyntax(args, dst, is_tail);
    }

    pub fn emitLoadValue(self: *Compiler, dst: u16, val: Value) CompileError!void {
        if (val == types.NIL) {
            try self.emitOp(.load_nil);
            try self.emitU16(dst);
        } else if (val == types.TRUE) {
            try self.emitOp(.load_true);
            try self.emitU16(dst);
        } else if (val == types.FALSE) {
            try self.emitOp(.load_false);
            try self.emitU16(dst);
        } else {
            const idx = try self.addConstant(val);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
        }
    }
};

// ---------------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------------

pub fn compileExpression(gc: *memory.GC, expr: Value) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    var ok = false;
    defer {
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    try c.compile(expr);
    ok = true;
    return c.func;
}

pub fn compileExpressionWithMacros(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), vm_globals: ?*std.StringHashMap(Value)) CompileError!*types.Function {
    return compileExpressionWithMacrosAt(gc, expr, vm_macros, vm_globals, 0, null);
}

pub fn compileExpressionWithMacrosAt(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), vm_globals: ?*std.StringHashMap(Value), source_line: u32, source_name: ?[]const u8) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    c.globals = vm_globals;
    c.func.source_line = source_line;
    c.func.source_name = source_name;
    var ok = false;
    defer {
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    var it = vm_macros.iterator();
    while (it.next()) |entry| {
        c.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    try c.compile(expr);
    var out_it = c.macros.iterator();
    while (out_it.next()) |entry| {
        vm_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    ok = true;
    return c.func;
}

pub fn compileExpressionInEnv(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), env: *std.StringHashMap(Value)) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    c.globals = env;
    c.lib_env = env;
    var ok = false;
    defer {
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    var it = vm_macros.iterator();
    while (it.next()) |entry| {
        c.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    try c.compile(expr);
    c.func.env = env;
    var out_it = c.macros.iterator();
    while (out_it.next()) |entry| {
        vm_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    ok = true;
    return c.func;
}

pub fn compileProgram(gc: *memory.GC, exprs: []const Value) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    var ok = false;
    defer {
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    try c.compileMultiple(exprs);
    ok = true;
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
