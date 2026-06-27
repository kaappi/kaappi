const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");

const Value = types.Value;
const OpCode = types.OpCode;
const CompileError = compiler_mod.CompileError;

pub const NodeTag = enum {
    constant,
    global_ref,
    call,
    @"if",
};

pub const Node = struct {
    tag: NodeTag,
    data: Data,

    const Data = union {
        constant: Value,
        global_ref: Value,
        call: CallData,
        @"if": IfData,
    };
};

pub const CallData = struct {
    operator: *Node,
    args: []const *Node,
};

pub const IfData = struct {
    test_expr: *Node,
    consequent: *Node,
    alternate: ?*Node,
};

pub const IR = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(*Node),

    pub fn init(allocator: std.mem.Allocator) IR {
        return .{
            .allocator = allocator,
            .nodes = .empty,
        };
    }

    pub fn deinit(self: *IR) void {
        for (self.nodes.items) |node| {
            self.freeNode(node);
        }
        self.nodes.deinit(self.allocator);
    }

    fn freeNode(self: *IR, node: *Node) void {
        switch (node.tag) {
            .call => {
                self.allocator.free(node.data.call.args);
            },
            .constant, .global_ref, .@"if" => {},
        }
        self.allocator.destroy(node);
    }

    fn allocNode(self: *IR, tag: NodeTag, data: Node.Data) CompileError!*Node {
        const node = self.allocator.create(Node) catch return CompileError.OutOfMemory;
        node.* = .{ .tag = tag, .data = data };
        self.nodes.append(self.allocator, node) catch return CompileError.OutOfMemory;
        return node;
    }

    pub fn makeConst(self: *IR, value: Value) CompileError!*Node {
        return self.allocNode(.constant, .{ .constant = value });
    }

    pub fn makeGlobalRef(self: *IR, sym: Value) CompileError!*Node {
        return self.allocNode(.global_ref, .{ .global_ref = sym });
    }

    pub fn makeCall(self: *IR, operator: *Node, args: []const *Node) CompileError!*Node {
        const args_copy = self.allocator.alloc(*Node, args.len) catch return CompileError.OutOfMemory;
        @memcpy(args_copy, args);
        return self.allocNode(.call, .{ .call = .{ .operator = operator, .args = args_copy } });
    }

    pub fn makeIf(self: *IR, test_expr: *Node, consequent: *Node, alternate: ?*Node) CompileError!*Node {
        return self.allocNode(.@"if", .{ .@"if" = .{ .test_expr = test_expr, .consequent = consequent, .alternate = alternate } });
    }
};

// ---------------------------------------------------------------------------
// AST (S-expression) → IR lowering
// ---------------------------------------------------------------------------

pub fn lower(ir: *IR, expr: Value) CompileError!*Node {
    if (types.isFixnum(expr) or types.isFlonum(expr) or types.isBignum(expr) or
        types.isComplex(expr) or types.isRationalObj(expr) or types.isString(expr) or
        types.isChar(expr) or types.isVector(expr) or types.isBytevector(expr))
    {
        return ir.makeConst(expr);
    }

    if (expr == types.TRUE or expr == types.FALSE or expr == types.NIL) {
        return ir.makeConst(expr);
    }

    if (types.isSymbol(expr)) {
        return ir.makeGlobalRef(expr);
    }

    if (types.isPair(expr)) {
        return lowerForm(ir, expr);
    }

    return CompileError.InvalidSyntax;
}

fn lowerForm(ir: *IR, expr: Value) CompileError!*Node {
    const head = types.car(expr);

    if (types.isSymbol(head)) {
        const name = types.symbolName(head);

        if (std.mem.eql(u8, name, "if")) {
            return lowerIf(ir, types.cdr(expr));
        }
        if (std.mem.eql(u8, name, "quote")) {
            return lowerQuote(ir, types.cdr(expr));
        }
    }

    return lowerCall(ir, expr);
}

fn lowerIf(ir: *IR, args: Value) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const consequent = types.car(rest);
    const rest2 = types.cdr(rest);

    const test_node = try lower(ir, test_expr);
    const cons_node = try lower(ir, consequent);
    const alt_node: ?*Node = if (rest2 != types.NIL)
        try lower(ir, types.car(rest2))
    else
        null;

    return ir.makeIf(test_node, cons_node, alt_node);
}

fn lowerQuote(ir: *IR, args: Value) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    return ir.makeConst(types.car(args));
}

fn lowerCall(ir: *IR, expr: Value) CompileError!*Node {
    if (tryFoldFromAST(ir, expr)) |folded| return folded;

    const operator = types.car(expr);
    const op_node = try lower(ir, operator);

    var arg_buf: [256]*Node = undefined;
    var nargs: usize = 0;
    var arg_list = types.cdr(expr);
    while (arg_list != types.NIL) {
        if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
        if (nargs >= 256) return CompileError.InternalLimit;
        arg_buf[nargs] = try lower(ir, types.car(arg_list));
        nargs += 1;
        arg_list = types.cdr(arg_list);
    }

    return ir.makeCall(op_node, arg_buf[0..nargs]);
}

fn tryFoldFromAST(ir: *IR, expr: Value) ?*Node {
    const operator = types.car(expr);
    if (!types.isSymbol(operator)) return null;
    const name = types.symbolName(operator);

    const args_pair = types.cdr(expr);
    if (!types.isPair(args_pair)) return null;
    const a = types.car(args_pair);
    const rest = types.cdr(args_pair);

    if (rest == types.NIL) {
        if (!types.isFixnum(a) and a != types.TRUE and a != types.FALSE) return null;

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

        if (result) |val| return ir.makeConst(val) catch null;
        return null;
    }

    if (!types.isPair(rest)) return null;
    const b = types.car(rest);
    if (types.cdr(rest) != types.NIL) return null;

    if (!types.isFixnum(a) or !types.isFixnum(b)) return null;
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

    if (result) |val| return ir.makeConst(val) catch null;
    return null;
}

// ---------------------------------------------------------------------------
// IR → bytecode emission
// ---------------------------------------------------------------------------

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

    fn emitNode(self: *Emitter, node: *Node, dst: u16, is_tail: bool) CompileError!void {
        switch (node.tag) {
            .constant => try self.emitConstant(node.data.constant, dst),
            .global_ref => try self.emitGlobalRef(node.data.global_ref, dst),
            .call => try self.emitCall(node.data.call, dst, is_tail),
            .@"if" => try self.emitIf(node.data.@"if", dst, is_tail),
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

    // -- Low-level emission helpers (mirror compiler.zig) --

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
