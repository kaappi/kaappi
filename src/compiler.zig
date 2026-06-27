const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const expander = @import("expander.zig");
const forms = @import("compiler_forms.zig");
const advanced = @import("compiler_advanced.zig");
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
const MAX_COMPILER_REGISTERS: u16 = @min(std.math.maxInt(u16), build_options.max_registers);
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

        // Lower AST to IR, then emit bytecode from the IR tree.
        var ir = ir_mod.IR.init(self.gc.allocator);
        defer ir.deinit();
        const root = try ir_mod.lower(&ir, expr_root);

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
        switch (node.tag) {
            .constant => try self.emitLoadValue(dst, node.data.constant),
            .global_ref => try self.compileVariable(node.data.global_ref, dst),
            .call => try self.compileCallFromIR(node.data.call, dst, is_tail),
            .@"if" => try self.compileIfFromIR(node.data.@"if", dst, is_tail),
            .begin => try self.compileBeginFromIR(node.data.begin, dst, is_tail),
            .and_form => try self.compileAndFromIR(node.data.and_form, dst, is_tail),
            .or_form => try self.compileOrFromIR(node.data.or_form, dst, is_tail),
            .when_form => try self.compileWhenFromIR(node.data.when_form, dst, is_tail),
            .unless_form => try self.compileUnlessFromIR(node.data.unless_form, dst, is_tail),
            .define => try self.compileDefineFromIR(node.data.define, dst),
            .set_form => try self.compileSetFromIR(node.data.set_form, dst),
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

    fn compileCallFromIR(self: *Compiler, call: ir_mod.CallData, dst: u16, is_tail: bool) CompileError!void {
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

    fn compileDefineFromIR(self: *Compiler, data: ir_mod.DefineData, dst: u16) CompileError!void {
        try self.compileExpr(data.value, dst, false);

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
        try self.compileExpr(data.value, dst, false);

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
            dst = try self.allocReg();
            try self.compileExpr(expr, dst, false);
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
                if (std.mem.eql(u8, effective_name, "quote")) return self.compileQuote(args, dst);
                if (std.mem.eql(u8, effective_name, "if")) return self.compileIf(args, dst, is_tail);
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
                            if (!collectSymbols(pat, &pv_names, &pv_count)) return CompileError.InternalLimit;
                        }
                        for (tx.templates[0..tx.num_rules]) |tmpl| {
                            if (!collectFreeRefs(tmpl, pv_names[0..pv_count], tx.literals, &cand_names, &cand_count)) {
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
            return self.compileApplyTail(expr, dst);
        }

        return self.compileCall(expr, dst, is_tail);
    }

    fn compileQuote(self: *Compiler, args: Value, dst: u16) CompileError!void {
        if (args == types.NIL) return CompileError.InvalidSyntax;
        const datum = types.car(args);
        const idx = try self.addConstant(datum);
        try self.emitOp(.load_const);
        try self.emitU16(dst);
        try self.emitU16(idx);
    }

    fn compileIf(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
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
        try self.emitU16(dst);
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
            try self.patchJump(else_jump);

            // Compile alternate (in tail position if the if is)
            const alternate = types.car(rest2);
            try self.compileExpr(alternate, dst, is_tail);

            // Patch end jump
            try self.patchJump(end_jump);
        } else {
            // No else: result is void when test is false
            try self.emitOp(.jump);
            const end_jump = self.currentOffset();
            try self.emitI16(0);

            try self.patchJump(else_jump);
            try self.emitOp(.load_void);
            try self.emitU16(dst);

            try self.patchJump(end_jump);
        }
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
        const transformer = self.parseSyntaxRules(transformer_spec) catch return CompileError.InvalidSyntax;

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

    fn parseSyntaxRules(self: *Compiler, spec: Value) CompileError!Value {
        // spec = (syntax-rules (lit1 lit2 ...) (pattern1 template1) ...)
        if (!types.isPair(spec)) return CompileError.InvalidSyntax;
        const head = types.car(spec);
        if (!types.isSymbol(head)) return CompileError.InvalidSyntax;
        if (!std.mem.eql(u8, types.symbolName(head), "syntax-rules")) return CompileError.InvalidSyntax;

        const rest = types.cdr(spec);
        if (rest == types.NIL) return CompileError.InvalidSyntax;

        // R7RS 4.3.2: optional custom ellipsis identifier
        var custom_ellipsis: ?[]const u8 = null;
        var after_ellipsis = rest;
        const first_arg = types.car(rest);
        if (types.isSymbol(first_arg) and !types.isPair(first_arg)) {
            const name_str = types.symbolName(first_arg);
            if (!std.mem.eql(u8, name_str, "_")) {
                custom_ellipsis = name_str;
                after_ellipsis = types.cdr(rest);
                if (after_ellipsis == types.NIL) return CompileError.InvalidSyntax;
            }
        }

        const literals_list = types.car(after_ellipsis);
        const rules = types.cdr(after_ellipsis);

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
        const tx_val = self.gc.allocTransformer(
            literals_buf[0..lit_count],
            patterns_buf[0..rule_count],
            templates_buf[0..rule_count],
        ) catch return CompileError.OutOfMemory;
        if (custom_ellipsis) |ce| {
            types.toObject(tx_val).as(types.Transformer).custom_ellipsis = ce;
        }
        return tx_val;
    }

    fn compileLetSyntax(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
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
        for (0..saved_count) |i| {
            if (saved_values[i]) |old_val| {
                self.macros.put(saved_names[i], old_val) catch {};
            } else {
                _ = self.macros.remove(saved_names[i]);
            }
        }
    }

    fn compileLetrecSyntax(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
        // letrec-syntax is the same as let-syntax for our purposes since we
        // process all bindings before compiling the body, and the transformer
        // specs can reference each other through the macro table.
        return self.compileLetSyntax(args, dst, is_tail);
    }

    fn compileCall(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
        const operator = types.car(expr);

        // --- Constant folding: evaluate (op lit ...) at compile time ---
        if (types.isSymbol(operator)) {
            if (self.tryConstantFold(expr, dst)) return;
        }

        // Count args first to know the arity and support self-tail-call checks
        var nargs: u8 = 0;
        var arg_list = types.cdr(expr);
        var args_valid = true;
        while (arg_list != types.NIL) {
            if (!types.isPair(arg_list)) {
                args_valid = false;
                break;
            }
            nargs += 1;
            arg_list = types.cdr(arg_list);
        }

        // 1. Self-Tail-Call Optimization: when a function tail-calls itself.
        if (args_valid and is_tail and types.isSymbol(operator) and self.func.name != null) {
            const op_name = types.symbolName(operator);
            if (std.mem.eql(u8, op_name, self.func.name.?) and !self.func.is_variadic and nargs == self.func.arity) {
                if (self.resolveLocal(op_name) == null and (try self.resolveUpvalue(op_name)) == null) {
                    return self.compileSelfTailCall(expr, dst, nargs);
                }
            }
        }

        // 2. Global Call Optimization: fuse get_global + call into a single
        // call_global instruction (saves one dispatch vs get_global + call).
        //
        // Restricted to NON-tail calls. tail_call_global only handles closure
        // and native-fn callees; the regular tail_call handler also handles
        // parameter objects, continuations, and FFI functions. Routing tail
        // calls through tail_call_global breaks any tail call to a global that
        // holds one of those values (e.g. `(define (get) (p))` where p is a
        // parameter, or parameterize bodies). Self-recursive tail calls — the
        // common hot case — are already handled above by self_tail_call.
        // Other tail calls fall through to the standard get_global + tail_call.
        if (!is_tail and args_valid and types.isSymbol(operator) and self.resolveLocal(types.symbolName(operator)) == null) {
            if ((try self.resolveUpvalue(types.symbolName(operator))) == null) {
                const op_name = types.symbolName(operator);
                const is_cont = std.mem.eql(u8, op_name, "call-with-current-continuation") or
                    std.mem.eql(u8, op_name, "call/cc") or
                    std.mem.eql(u8, op_name, "call/ec") or
                    std.mem.eql(u8, op_name, "call-with-escape-continuation") or
                    std.mem.eql(u8, op_name, "call-with-values") or
                    std.mem.eql(u8, op_name, "dynamic-wind") or
                    std.mem.eql(u8, op_name, "with-exception-handler");
                if (!is_cont) {
                    return self.compileCallGlobal(expr, operator, dst, is_tail);
                }
            }
        }

        if (!args_valid) return CompileError.InvalidSyntax;

        // The call instruction expects: operator at base, args at base+1, base+2, ...
        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else dst;

        try self.compileExpr(operator, base, false);

        arg_list = types.cdr(expr);
        while (arg_list != types.NIL) {
            const arg = types.car(arg_list);
            const arg_reg = try self.allocReg();
            try self.compileExpr(arg, arg_reg, false);
            arg_list = types.cdr(arg_list);
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

    fn tryConstantFold(self: *Compiler, expr: Value, dst: u16) bool {
        const operator = types.car(expr);
        if (!types.isSymbol(operator)) return false;
        const name = types.symbolName(operator);

        // Don't fold if the operator is shadowed by a local or upvalue binding
        if (self.resolveLocal(name) != null) return false;
        if ((self.resolveUpvalue(name) catch null) != null) return false;

        const args_pair = types.cdr(expr);
        if (!types.isPair(args_pair)) return false;
        const a = types.car(args_pair);
        const rest = types.cdr(args_pair);

        // Unary: (not #t), (zero? 0), (- 5)
        if (rest == types.NIL) {
            if (!types.isFixnum(a) and a != types.TRUE and a != types.FALSE) return false;
            const result: ?Value = if (std.mem.eql(u8, name, "not"))
                (if (a == types.FALSE) types.TRUE else types.FALSE)
            else if (std.mem.eql(u8, name, "zero?"))
                (if (types.isFixnum(a) and types.toFixnum(a) == 0) types.TRUE else types.FALSE)
            else if (std.mem.eql(u8, name, "-") and types.isFixnum(a)) blk: {
                const neg = @subWithOverflow(@as(i64, 0), types.toFixnum(a));
                if (neg[1] != 0) break :blk null;
                if (neg[0] < std.math.minInt(i48) or neg[0] > std.math.maxInt(i48)) break :blk null;
                break :blk types.makeFixnum(neg[0]);
            } else null;
            if (result) |val| {
                self.emitLoadValue(dst, val) catch return false;
                return true;
            }
            return false;
        }

        // Binary: (+ 1 2), (< 3 4), etc.
        if (!types.isPair(rest)) return false;
        const b = types.car(rest);
        if (types.cdr(rest) != types.NIL) return false; // only 2-arg forms

        if (!types.isFixnum(a) or !types.isFixnum(b)) return false;
        const va = types.toFixnum(a);
        const vb = types.toFixnum(b);

        const result: ?Value =
            if (std.mem.eql(u8, name, "+")) blk: {
                const r = @addWithOverflow(va, vb);
                if (r[1] != 0) break :blk null;
                if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
                break :blk types.makeFixnum(r[0]);
            } else if (std.mem.eql(u8, name, "-")) blk: {
                const r = @subWithOverflow(va, vb);
                if (r[1] != 0) break :blk null;
                if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
                break :blk types.makeFixnum(r[0]);
            } else if (std.mem.eql(u8, name, "*")) blk: {
                const r = @mulWithOverflow(va, vb);
                if (r[1] != 0) break :blk null;
                if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
                break :blk types.makeFixnum(r[0]);
            } else if (std.mem.eql(u8, name, "<"))
                (if (va < vb) types.TRUE else types.FALSE)
            else if (std.mem.eql(u8, name, ">"))
                (if (va > vb) types.TRUE else types.FALSE)
            else if (std.mem.eql(u8, name, "<="))
                (if (va <= vb) types.TRUE else types.FALSE)
            else if (std.mem.eql(u8, name, ">="))
                (if (va >= vb) types.TRUE else types.FALSE)
            else if (std.mem.eql(u8, name, "="))
                (if (va == vb) types.TRUE else types.FALSE)
            else
                null;

        if (result) |val| {
            self.emitLoadValue(dst, val) catch return false;
            return true;
        }
        return false;
    }

    fn emitLoadValue(self: *Compiler, dst: u16, val: Value) CompileError!void {
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

    fn compileSelfTailCall(self: *Compiler, expr: Value, dst: u16, nargs: u8) CompileError!void {
        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else dst;

        var arg_list = types.cdr(expr);
        while (arg_list != types.NIL) {
            const arg = types.car(arg_list);
            const arg_reg = try self.allocReg();
            try self.compileExpr(arg, arg_reg, false);
            arg_list = types.cdr(arg_list);
        }

        try self.emitOp(.self_tail_call);
        try self.emitU16(base);
        try self.emit(nargs);

        var i: u8 = 0;
        while (i < nargs) : (i += 1) {
            self.freeReg();
        }

        if (needs_rebase) {
            self.freeReg();
        }
    }

    fn compileApplyTail(self: *Compiler, expr: Value, dst: u16) CompileError!void {
        var arg_list = types.cdr(expr);
        if (arg_list == types.NIL) return CompileError.InvalidSyntax;

        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else dst;

        try self.compileExpr(types.car(arg_list), base, false);
        arg_list = types.cdr(arg_list);

        var nargs: u8 = 0;
        while (arg_list != types.NIL) {
            if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
            const arg_reg = try self.allocReg();
            try self.compileExpr(types.car(arg_list), arg_reg, false);
            nargs += 1;
            arg_list = types.cdr(arg_list);
        }

        if (nargs < 1) return CompileError.InvalidSyntax;

        try self.emitOp(.tail_apply);
        try self.emitU16(base);
        try self.emit(nargs);

        var i: u8 = 0;
        while (i < nargs) : (i += 1) {
            self.freeReg();
        }
        if (needs_rebase) {
            self.freeReg();
        }
    }

    fn compileCallGlobal(self: *Compiler, expr: Value, operator: Value, dst: u16, is_tail: bool) CompileError!void {
        const sym_idx = try self.addConstant(operator);

        // Reserve base register for callee (call_global fills it at runtime)
        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else blk: {
            // Advance next_register past base so args start at base+1
            if (self.next_register == dst) {
                _ = try self.allocReg();
            }
            break :blk dst;
        };

        // Compile arguments contiguously after base
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
        gc.extra_roots.append(gc.allocator, entry.value_ptr.*) catch return CompileError.OutOfMemory;
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
        gc.extra_roots.append(gc.allocator, entry.value_ptr.*) catch return CompileError.OutOfMemory;
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
// Free-reference collection for macro hygiene
// ---------------------------------------------------------------------------

fn collectSymbols(expr: Value, out: *[64][]const u8, count: *usize) bool {
    if (types.isSymbol(expr)) {
        const n = types.symbolName(expr);
        for (out[0..count.*]) |e| {
            if (std.mem.eql(u8, e, n)) return true;
        }
        if (count.* >= 64) return false;
        out[count.*] = n;
        count.* += 1;
        return true;
    }
    if (types.isPair(expr)) {
        if (!collectSymbols(types.car(expr), out, count)) return false;
        return collectSymbols(types.cdr(expr), out, count);
    }
    return true;
}

fn collectFreeRefs(template: Value, pat_vars: []const []const u8, literals: []const Value, out: *[64][]const u8, count: *usize) bool {
    return collectFreeRefsWithLocals(template, pat_vars, literals, &.{}, out, count);
}

fn collectFreeRefsWithLocals(template: Value, pat_vars: []const []const u8, literals: []const Value, local_binds: []const []const u8, out: *[64][]const u8, count: *usize) bool {
    if (types.isSymbol(template)) {
        const name = types.symbolName(template);
        for (pat_vars) |pv| {
            if (std.mem.eql(u8, pv, name)) return true;
        }
        for (local_binds) |lb| {
            if (std.mem.eql(u8, lb, name)) return true;
        }
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) return true;
        }
        if (expander.isWellKnown(name)) return true;
        for (out[0..count.*]) |e| {
            if (std.mem.eql(u8, e, name)) return true;
        }
        if (count.* >= 64) return false;
        out[count.*] = name;
        count.* += 1;
        return true;
    }
    if (!types.isPair(template)) return true;
    const head = types.car(template);
    const rest = types.cdr(template);
    if (types.isSymbol(head)) {
        const hname = types.symbolName(head);
        if (isLetForm(hname)) {
            if (rest != types.NIL and types.isPair(rest)) {
                var bab = rest;
                if (types.isSymbol(types.car(rest))) bab = types.cdr(rest);
                if (bab != types.NIL and types.isPair(bab)) {
                    // Collect let-binding names to exclude from body
                    var let_names: [16][]const u8 = undefined;
                    var let_count: usize = 0;
                    for (local_binds) |lb| {
                        if (let_count < 16) {
                            let_names[let_count] = lb;
                            let_count += 1;
                        }
                    }
                    var binds = types.car(bab);
                    while (types.isPair(binds)) {
                        const b = types.car(binds);
                        if (types.isPair(b)) {
                            const bname = types.car(b);
                            if (types.isSymbol(bname) and let_count < 16) {
                                let_names[let_count] = types.symbolName(bname);
                                let_count += 1;
                            }
                            const init_rest2 = types.cdr(b);
                            if (init_rest2 != types.NIL and types.isPair(init_rest2))
                                if (!collectFreeRefsWithLocals(types.car(init_rest2), pat_vars, literals, local_binds, out, count)) return false;
                        }
                        binds = types.cdr(binds);
                    }
                    if (!collectFreeRefsWithLocals(types.cdr(bab), pat_vars, literals, let_names[0..let_count], out, count)) return false;
                }
            }
            return true;
        }
        if (std.mem.eql(u8, hname, "lambda")) {
            if (rest != types.NIL and types.isPair(rest)) {
                var lam_names: [16][]const u8 = undefined;
                var lam_count: usize = 0;
                for (local_binds) |lb| {
                    if (lam_count < 16) {
                        lam_names[lam_count] = lb;
                        lam_count += 1;
                    }
                }
                var params = types.car(rest);
                while (types.isPair(params)) {
                    const p = types.car(params);
                    if (types.isSymbol(p) and lam_count < 16) {
                        lam_names[lam_count] = types.symbolName(p);
                        lam_count += 1;
                    }
                    params = types.cdr(params);
                }
                if (types.isSymbol(params) and lam_count < 16) {
                    lam_names[lam_count] = types.symbolName(params);
                    lam_count += 1;
                }
                if (!collectFreeRefsWithLocals(types.cdr(rest), pat_vars, literals, lam_names[0..lam_count], out, count)) return false;
            }
            return true;
        }
        if (std.mem.eql(u8, hname, "define")) {
            if (rest != types.NIL and types.isPair(rest))
                if (!collectFreeRefsWithLocals(types.cdr(rest), pat_vars, literals, local_binds, out, count)) return false;
            return true;
        }
        if (std.mem.eql(u8, hname, "syntax-rules")) {
            // Inner syntax-rules: collect pattern variables and exclude them
            if (rest != types.NIL and types.isPair(rest)) {
                var sr_names: [16][]const u8 = undefined;
                var sr_count: usize = 0;
                for (local_binds) |lb| {
                    if (sr_count < 16) {
                        sr_names[sr_count] = lb;
                        sr_count += 1;
                    }
                }
                var rules = types.cdr(rest); // skip literals
                while (types.isPair(rules)) {
                    const rule = types.car(rules);
                    if (types.isPair(rule)) {
                        if (!collectSymbols(types.car(rule), @ptrCast(&sr_names), &sr_count)) return false;
                    }
                    rules = types.cdr(rules);
                }
                if (!collectFreeRefsWithLocals(rest, pat_vars, literals, sr_names[0..sr_count], out, count)) return false;
            }
            return true;
        }
    }
    if (!collectFreeRefsWithLocals(head, pat_vars, literals, local_binds, out, count)) return false;
    return collectFreeRefsWithLocals(rest, pat_vars, literals, local_binds, out, count);
}

fn isLetForm(name: []const u8) bool {
    return std.mem.eql(u8, name, "let") or std.mem.eql(u8, name, "let*") or
        std.mem.eql(u8, name, "letrec") or std.mem.eql(u8, name, "letrec*");
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
