const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const ir = @import("ir.zig");

const Value = types.Value;
const OpCode = types.OpCode;
const Node = ir.Node;
const NodeTag = ir.NodeTag;
const CallData = ir.CallData;
const IfData = ir.IfData;
const CompileError = ir.CompileError;

pub const Emitter = struct {
    gc: *memory.GC,
    func: *types.Function,
    next_register: u16 = 0,

    pub fn init(gc: *memory.GC) CompileError!Emitter {
        const func = gc.allocFunction() catch return CompileError.OutOfMemory;
        return .{ .gc = gc, .func = func };
    }

    pub fn compile(self: *Emitter, node: *Node) CompileError!void {
        const dst = try self.allocReg();
        try self.emitNode(node, dst, false);
        try self.emitOp(.@"return");
        try self.emitU16(dst);
    }

    pub fn emitNode(self: *Emitter, node: *Node, dst: u16, is_tail: bool) CompileError!void {
        switch (node.tag) {
            .constant => try self.emitConstant(node.data.constant, dst),
            .global_ref => try self.emitGlobalRef(node.data.global_ref, dst),
            .call => try self.emitCall(node.data.call, dst, is_tail),
            .@"if" => try self.emitIf(node.data.@"if", dst, is_tail),
            .begin => try self.emitBegin(node.data.begin, dst, is_tail),
            .and_form,
            .or_form,
            .when_form,
            .unless_form,
            .define,
            .set_form,
            .lambda,
            .let_form,
            .let_star,
            .letrec,
            .letrec_star,
            .do_form,
            .delay,
            .delay_force,
            .cond,
            .case_form,
            .case_lambda,
            .guard,
            .quasiquote,
            .parameterize,
            .define_values,
            .let_values,
            .let_star_values,
            .define_syntax,
            .named_let,
            .let_syntax,
            .letrec_syntax,
            .cond_expand,
            => return CompileError.NotImplemented,
            .passthrough => return CompileError.NotImplemented,
        }
    }

    fn emitConstant(self: *Emitter, value: Value, dst: u16) CompileError!void {
        if (value == types.TRUE) {
            try self.emitOp(.load_true);
            try self.emitU16(dst);
        } else if (value == types.FALSE) {
            try self.emitOp(.load_false);
            try self.emitU16(dst);
        } else if (value == types.NIL) {
            try self.emitOp(.load_nil);
            try self.emitU16(dst);
        } else {
            const idx = try self.addConstant(value);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
        }
    }

    fn emitGlobalRef(self: *Emitter, sym: Value, dst: u16) CompileError!void {
        const sym_idx = try self.addConstant(sym);
        try self.emitOp(.get_global);
        try self.emitU16(dst);
        try self.emitU16(sym_idx);
    }

    fn emitCall(self: *Emitter, call: CallData, dst: u16, is_tail: bool) CompileError!void {
        const nargs: u8 = @intCast(call.args.len);

        if (!is_tail and call.operator.tag == .global_ref) {
            const sym = call.operator.data.global_ref;
            if (types.isSymbol(sym)) {
                const op_name = types.symbolName(sym);
                const is_cont = std.mem.eql(u8, op_name, "call-with-current-continuation") or
                    std.mem.eql(u8, op_name, "call/cc") or
                    std.mem.eql(u8, op_name, "call/ec") or
                    std.mem.eql(u8, op_name, "call-with-escape-continuation") or
                    std.mem.eql(u8, op_name, "call-with-values") or
                    std.mem.eql(u8, op_name, "dynamic-wind") or
                    std.mem.eql(u8, op_name, "with-exception-handler");

                if (!is_cont) {
                    return self.emitCallGlobal(sym, call.args, dst, nargs, is_tail);
                }
            }
        }

        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else dst;

        try self.emitNode(call.operator, base, false);

        for (call.args) |arg| {
            const arg_reg = try self.allocReg();
            try self.emitNode(arg, arg_reg, false);
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

    fn emitCallGlobal(self: *Emitter, sym: Value, args: []const *Node, dst: u16, nargs: u8, is_tail: bool) CompileError!void {
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
            try self.emitNode(arg, arg_reg, false);
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

    fn emitIf(self: *Emitter, data: IfData, dst: u16, is_tail: bool) CompileError!void {
        try self.emitNode(data.test_expr, dst, false);

        try self.emitOp(.jump_false);
        try self.emitU16(dst);
        const else_jump = self.currentOffset();
        try self.emitI16(0);

        try self.emitNode(data.consequent, dst, is_tail);

        if (data.alternate) |alt| {
            try self.emitOp(.jump);
            const end_jump = self.currentOffset();
            try self.emitI16(0);

            try self.patchJump(else_jump);

            try self.emitNode(alt, dst, is_tail);

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

    fn emitBegin(self: *Emitter, exprs: []const *Node, dst: u16, is_tail: bool) CompileError!void {
        if (exprs.len == 0) {
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        for (exprs, 0..) |expr, i| {
            const tail = is_tail and i == exprs.len - 1;
            try self.emitNode(expr, dst, tail);
        }
    }

    // -- Low-level emission helpers --

    fn emit(self: *Emitter, byte: u8) CompileError!void {
        self.func.code.append(self.gc.allocator, byte) catch return CompileError.OutOfMemory;
    }

    fn emitOp(self: *Emitter, op: OpCode) CompileError!void {
        try self.emit(@intFromEnum(op));
    }

    fn emitU16(self: *Emitter, val: u16) CompileError!void {
        try self.emit(@truncate(val >> 8));
        try self.emit(@truncate(val & 0xFF));
    }

    fn emitI16(self: *Emitter, val: i16) CompileError!void {
        const unsigned: u16 = @bitCast(val);
        try self.emitU16(unsigned);
    }

    fn addConstant(self: *Emitter, value: Value) CompileError!u16 {
        for (self.func.constants.items, 0..) |c, i| {
            if (c == value) return @intCast(i);
        }
        if (self.func.constants.items.len >= 65535) return CompileError.TooManyConstants;
        self.func.constants.append(self.gc.allocator, value) catch return CompileError.OutOfMemory;
        return @intCast(self.func.constants.items.len - 1);
    }

    fn currentOffset(self: *Emitter) usize {
        return self.func.code.items.len;
    }

    fn patchJump(self: *Emitter, offset: usize) CompileError!void {
        const dist = @as(isize, @intCast(self.currentOffset())) - @as(isize, @intCast(offset)) - 2;
        if (dist < std.math.minInt(i16) or dist > std.math.maxInt(i16)) {
            return CompileError.JumpOutOfRange;
        }
        const jump_dist: i16 = @intCast(dist);
        const unsigned: u16 = @bitCast(jump_dist);
        self.func.code.items[offset] = @truncate(unsigned >> 8);
        self.func.code.items[offset + 1] = @truncate(unsigned & 0xFF);
    }

    fn allocReg(self: *Emitter) CompileError!u16 {
        if (self.next_register >= std.math.maxInt(u16)) return CompileError.TooManyLocals;
        const reg = self.next_register;
        self.next_register += 1;
        if (self.next_register > self.func.locals_count) {
            self.func.locals_count = self.next_register;
        }
        return reg;
    }

    fn freeReg(self: *Emitter) void {
        if (self.next_register > 0) self.next_register -= 1;
    }
};
