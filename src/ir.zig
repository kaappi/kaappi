const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");

const Value = types.Value;
const OpCode = types.OpCode;
pub const CompileError = compiler_mod.CompileError;

pub const NodeTag = enum {
    constant,
    global_ref,
    call,
    @"if",
    begin,
    and_form,
    or_form,
    when_form,
    unless_form,
    passthrough,
};

pub const Node = struct {
    tag: NodeTag,
    data: Data,

    const Data = union {
        constant: Value,
        global_ref: Value,
        call: CallData,
        @"if": IfData,
        begin: []const *Node,
        and_form: []const *Node,
        or_form: []const *Node,
        when_form: CondBodyData,
        unless_form: CondBodyData,
        passthrough: Value,
    };
};

pub const CondBodyData = struct {
    test_expr: *Node,
    body: []const *Node,
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
            .call => self.allocator.free(node.data.call.args),
            .begin => self.allocator.free(node.data.begin),
            .and_form => self.allocator.free(node.data.and_form),
            .or_form => self.allocator.free(node.data.or_form),
            .when_form => self.allocator.free(node.data.when_form.body),
            .unless_form => self.allocator.free(node.data.unless_form.body),
            .constant, .global_ref, .@"if", .passthrough => {},
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

    pub fn makeBegin(self: *IR, exprs: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, exprs.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, exprs);
        return self.allocNode(.begin, .{ .begin = copy });
    }

    pub fn makeAnd(self: *IR, exprs: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, exprs.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, exprs);
        return self.allocNode(.and_form, .{ .and_form = copy });
    }

    pub fn makeOr(self: *IR, exprs: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, exprs.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, exprs);
        return self.allocNode(.or_form, .{ .or_form = copy });
    }

    pub fn makeWhen(self: *IR, test_expr: *Node, body: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, body.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, body);
        return self.allocNode(.when_form, .{ .when_form = .{ .test_expr = test_expr, .body = copy } });
    }

    pub fn makeUnless(self: *IR, test_expr: *Node, body: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, body.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, body);
        return self.allocNode(.unless_form, .{ .unless_form = .{ .test_expr = test_expr, .body = copy } });
    }

    pub fn makePassthrough(self: *IR, expr: Value) CompileError!*Node {
        return self.allocNode(.passthrough, .{ .passthrough = expr });
    }
};

// ---------------------------------------------------------------------------
// AST (S-expression) → IR lowering
// ---------------------------------------------------------------------------

const special_forms = [_][]const u8{
    "quote",         "if",         "lambda",        "define",
    "define-values", "set!",       "begin",         "and",
    "or",            "when",       "unless",        "cond",
    "let",           "let*",       "let-values",    "let*-values",
    "letrec",        "letrec*",    "case",          "case-lambda",
    "cond-expand",   "do",         "guard",         "delay",
    "delay-force",   "quasiquote", "parameterize",  "syntax-error",
    "define-syntax", "let-syntax", "letrec-syntax", "syntax-rules",
    "apply",
};

fn isSpecialForm(name: []const u8) bool {
    for (special_forms) |sf| {
        if (std.mem.eql(u8, name, sf)) return true;
    }
    return false;
}

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

        var effective_name = name;
        while (std.mem.startsWith(u8, effective_name, "__hyg_")) {
            if (std.mem.indexOfScalar(u8, effective_name[6..], '_')) |sep| {
                effective_name = effective_name[6 + sep + 1 ..];
            } else break;
        }

        if (std.mem.eql(u8, effective_name, "if")) return lowerIf(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "quote")) return lowerQuote(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "begin")) return lowerBegin(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "and")) return lowerList(ir, types.cdr(expr), .and_form);
        if (std.mem.eql(u8, effective_name, "or")) return lowerList(ir, types.cdr(expr), .or_form);
        if (std.mem.eql(u8, effective_name, "when")) return lowerCondBody(ir, types.cdr(expr), .when_form);
        if (std.mem.eql(u8, effective_name, "unless")) return lowerCondBody(ir, types.cdr(expr), .unless_form);

        // All other named forms (special forms, macros, user-defined) use
        // passthrough — the compiler handles macro expansion, local-variable
        // shadowing, and dispatch for these.
        if (isSpecialForm(effective_name)) return ir.makePassthrough(expr);
    }

    // For calls where the operator is NOT a known special-form keyword,
    // check if constant folding applies. If not, passthrough to the
    // compiler which handles macro expansion and local shadowing.
    if (types.isSymbol(head)) {
        if (tryFoldFromAST(ir, expr)) |folded| return folded;
    }

    return ir.makePassthrough(expr);
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

fn lowerBegin(ir: *IR, args: Value) CompileError!*Node {
    var buf: [256]*Node = undefined;
    var count: usize = 0;
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        if (count >= 256) return CompileError.InternalLimit;
        buf[count] = try lower(ir, types.car(current));
        count += 1;
        current = types.cdr(current);
    }
    return ir.makeBegin(buf[0..count]);
}

fn lowerList(ir: *IR, args: Value, tag: NodeTag) CompileError!*Node {
    var buf: [256]*Node = undefined;
    var count: usize = 0;
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        if (count >= 256) return CompileError.InternalLimit;
        buf[count] = try lower(ir, types.car(current));
        count += 1;
        current = types.cdr(current);
    }
    return switch (tag) {
        .and_form => ir.makeAnd(buf[0..count]),
        .or_form => ir.makeOr(buf[0..count]),
        else => ir.makeBegin(buf[0..count]),
    };
}

fn lowerCondBody(ir: *IR, args: Value, tag: NodeTag) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = try lower(ir, types.car(args));

    var buf: [256]*Node = undefined;
    var count: usize = 0;
    var current = types.cdr(args);
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        if (count >= 256) return CompileError.InternalLimit;
        buf[count] = try lower(ir, types.car(current));
        count += 1;
        current = types.cdr(current);
    }
    return switch (tag) {
        .when_form => ir.makeWhen(test_expr, buf[0..count]),
        .unless_form => ir.makeUnless(test_expr, buf[0..count]),
        else => unreachable,
    };
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
// IR → bytecode emission (standalone, used by Stage 1 parity tests)
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

    pub fn emitNode(self: *Emitter, node: *Node, dst: u16, is_tail: bool) CompileError!void {
        switch (node.tag) {
            .constant => try self.emitConstant(node.data.constant, dst),
            .global_ref => try self.emitGlobalRef(node.data.global_ref, dst),
            .call => try self.emitCall(node.data.call, dst, is_tail),
            .@"if" => try self.emitIf(node.data.@"if", dst, is_tail),
            .begin => try self.emitBegin(node.data.begin, dst, is_tail),
            .and_form, .or_form, .when_form, .unless_form => return CompileError.NotImplemented,
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
