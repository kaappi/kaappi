const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;

pub fn compileQuote(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const datum = types.car(args);
    const idx = try self.addConstant(datum);
    try self.emitOp(.load_const);
    try self.emitU16(dst);
    try self.emitU16(idx);
}

pub fn compileIf(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const consequent = types.car(rest);
    const rest2 = types.cdr(rest);

    try self.compileExprViaIR(test_expr, dst, false);

    try self.emitOp(.jump_false);
    try self.emitU16(dst);
    const else_jump = self.currentOffset();
    try self.emitI16(0);

    try self.compileExprViaIR(consequent, dst, is_tail);

    if (rest2 != types.NIL) {
        try self.emitOp(.jump);
        const end_jump = self.currentOffset();
        try self.emitI16(0);

        try self.patchJump(else_jump);

        const alternate = types.car(rest2);
        try self.compileExprViaIR(alternate, dst, is_tail);

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

pub fn compileCall(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
    const operator = types.car(expr);

    if (types.isSymbol(operator)) {
        if (tryConstantFold(self, expr, dst)) return;
    }

    var nargs_count: usize = 0;
    var arg_list = types.cdr(expr);
    var args_valid = true;
    while (arg_list != types.NIL) {
        if (!types.isPair(arg_list)) {
            args_valid = false;
            break;
        }
        nargs_count += 1;
        arg_list = types.cdr(arg_list);
    }

    if (nargs_count > 255) return CompileError.InternalLimit;
    const nargs: u8 = @intCast(nargs_count);

    if (args_valid and is_tail and types.isSymbol(operator) and self.func.name != null) {
        const op_name = types.symbolName(operator);
        if (std.mem.eql(u8, op_name, self.func.name.?) and !self.func.is_variadic and nargs == self.func.arity) {
            // A named-let loop gensym (__nlet_N_x) is compiler-introduced and
            // unique, so a name match is always a self-reference even though
            // it now resolves as a boxed upvalue (checked first to avoid
            // resolveUpvalue registering a capture the fast path never reads).
            if (std.mem.startsWith(u8, op_name, "__nlet_")) {
                return compileSelfTailCall(self, expr, dst, nargs);
            }
            if (self.resolveLocal(op_name) == null and (try self.resolveUpvalue(op_name)) == null) {
                return compileSelfTailCall(self, expr, dst, nargs);
            }
        }
    }

    if (!is_tail and args_valid and types.isSymbol(operator) and self.resolveLocal(types.symbolName(operator)) == null) {
        if ((try self.resolveUpvalue(types.symbolName(operator))) == null) {
            const op_name = types.symbolName(operator);
            const is_cont = types.isContinuationBarrier(op_name);
            if (!is_cont) {
                return compileCallGlobal(self, expr, operator, dst, is_tail);
            }
        }
    }

    if (!args_valid) return CompileError.InvalidSyntax;

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try self.compileExprViaIR(operator, base, false);

    arg_list = types.cdr(expr);
    while (arg_list != types.NIL) {
        const arg = types.car(arg_list);
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(arg, arg_reg, false);
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

    // A `set!` to this name in the enclosing form may run before this call,
    // so folding would use a stale primitive value. Suppress it.
    if (self.set_targets) |st| {
        if (st.contains(name)) return false;
    }

    if (self.resolveLocal(name) != null) return false;
    if ((self.resolveUpvalue(name) catch null) != null) return false;
    if (self.globals) |globals| {
        const glk = globals_mod.acquireGlobalsRead(globals);
        defer globals_mod.releaseGlobalsRead(glk);
        if (globals.get(name)) |val| {
            if (!types.isPointer(val)) return false;
            const obj = types.toObject(val);
            if (obj.tag != .native_fn) return false;
            if (!std.mem.eql(u8, obj.as(types.NativeFn).name, name)) return false;
        }
    }

    const args_pair = types.cdr(expr);
    if (!types.isPair(args_pair)) return false;
    const a = types.car(args_pair);
    const rest = types.cdr(args_pair);

    if (rest == types.NIL) {
        if (!types.isFixnum(a) and a != types.TRUE and a != types.FALSE) return false;
        const result: ?Value = if (std.mem.eql(u8, name, "not"))
            (if (a == types.FALSE) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, "zero?") and types.isFixnum(a))
            (if (types.toFixnum(a) == 0) types.TRUE else types.FALSE)
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

    if (!types.isPair(rest)) return false;
    const b = types.car(rest);
    if (types.cdr(rest) != types.NIL) return false;

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

fn compileSelfTailCall(self: *Compiler, expr: Value, dst: u16, nargs: u8) CompileError!void {
    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    var arg_list = types.cdr(expr);
    while (arg_list != types.NIL) {
        const arg = types.car(arg_list);
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(arg, arg_reg, false);
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

pub fn compileApplyTail(self: *Compiler, expr: Value, dst: u16) CompileError!void {
    var arg_list = types.cdr(expr);
    if (arg_list == types.NIL) return CompileError.InvalidSyntax;

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try self.compileExprViaIR(types.car(arg_list), base, false);
    arg_list = types.cdr(arg_list);

    var nargs_count: usize = 0;
    while (arg_list != types.NIL) {
        if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(types.car(arg_list), arg_reg, false);
        nargs_count += 1;
        arg_list = types.cdr(arg_list);
    }

    if (nargs_count < 1) return CompileError.InvalidSyntax;
    if (nargs_count > 255) return CompileError.InternalLimit;
    const nargs: u8 = @intCast(nargs_count);

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

pub fn compileCallWithValuesTail(self: *Compiler, expr: Value, dst: u16) CompileError!void {
    // (call-with-values producer consumer) in tail position.
    // Emits bytecode directly: call_global("call-with-values", producer, list) → values,
    // then tail_apply(consumer, values). Uses get_global/call_global to avoid
    // resolving `list`/`call-with-values` in the user's lexical scope.
    const args = types.cdr(expr);
    if (args == types.NIL or !types.isPair(args)) return CompileError.InvalidSyntax;
    const producer = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL or !types.isPair(rest)) return CompileError.InvalidSyntax;
    const consumer = types.car(rest);
    if (types.cdr(rest) != types.NIL) return CompileError.InvalidSyntax;

    const gc = self.gc;
    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try self.compileExprViaIR(consumer, base, false);

    const cwv_base = try self.allocReg();
    const producer_reg = try self.allocReg();
    const list_reg = try self.allocReg();

    try self.compileExprViaIR(producer, producer_reg, false);

    const list_sym = gc.allocSymbol("list") catch return CompileError.OutOfMemory;
    const list_idx = try self.addConstant(list_sym);
    try self.emitOp(.get_global);
    try self.emitU16(list_reg);
    try self.emitU16(list_idx);

    const cwv_sym = gc.allocSymbol("call-with-values") catch return CompileError.OutOfMemory;
    const cwv_idx = try self.addConstant(cwv_sym);
    try self.emitOp(.call_global);
    try self.emitU16(cwv_base);
    try self.emitU16(cwv_idx);
    try self.emit(2);

    self.freeReg(); // list_reg
    self.freeReg(); // producer_reg

    try self.emitOp(.tail_apply);
    try self.emitU16(base);
    try self.emit(1);

    self.freeReg(); // cwv_base
    if (needs_rebase) self.freeReg();
}

pub fn compileCallCCTail(self: *Compiler, expr: Value, dst: u16) CompileError!void {
    const args = types.cdr(expr);
    if (args == types.NIL or !types.isPair(args)) return CompileError.InvalidSyntax;
    const receiver = types.car(args);
    if (types.cdr(args) != types.NIL) return CompileError.InvalidSyntax;

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;
    try self.compileExprViaIR(receiver, base, false);

    try self.emitOp(.tail_call_cc);
    try self.emitU16(base);
    try self.emitU16(dst);

    if (needs_rebase) {
        self.freeReg();
    }
}

pub fn compileEvalTail(self: *Compiler, expr: Value, dst: u16) CompileError!void {
    // (eval expr) or (eval expr env) in tail position
    // Emits tail_eval opcode: compiles expr at runtime and tail-calls the result.
    const args = types.cdr(expr);
    if (args == types.NIL or !types.isPair(args)) return CompileError.InvalidSyntax;

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try self.compileExprViaIR(types.car(args), base, false);
    const rest = types.cdr(args);
    var nargs: u8 = 1;
    if (rest != types.NIL and types.isPair(rest)) {
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(types.car(rest), arg_reg, false);
        nargs = 2;
    }

    try self.emitOp(.tail_eval);
    try self.emitU16(base);
    try self.emit(nargs);

    if (nargs == 2) self.freeReg();
    if (needs_rebase) self.freeReg();
}

fn compileCallGlobal(self: *Compiler, expr: Value, operator: Value, dst: u16, is_tail: bool) CompileError!void {
    const sym_idx = try self.addConstant(operator);

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else blk: {
        if (self.next_register == dst) {
            _ = try self.allocReg();
        }
        break :blk dst;
    };

    var nargs_count: usize = 0;
    var arg_list = types.cdr(expr);
    while (arg_list != types.NIL) {
        if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
        const arg = types.car(arg_list);
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(arg, arg_reg, false);
        nargs_count += 1;
        arg_list = types.cdr(arg_list);
    }
    if (nargs_count > 255) return CompileError.InternalLimit;
    const nargs: u8 = @intCast(nargs_count);

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
