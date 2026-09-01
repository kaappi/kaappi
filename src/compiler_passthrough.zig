const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");
const expander = @import("expander.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;

pub fn compileQuote(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    // See ir.zig's lowerQuote: strip hygiene renames from a quoted datum's
    // template-introduced identifiers now that it's becoming a real literal
    // Value (#1801).
    const datum = expander.stripHygieneFromDatum(self.gc, types.car(args)) catch return CompileError.OutOfMemory;
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
    var args_valid = true;
    // #2405: a datum-label cycle in the argument spine spun this counting
    // loop forever; the tortoise-and-hare guard names it instead.
    var count_walk = compiler_mod.SpineWalk.init(types.cdr(expr));
    while (count_walk.cur != types.NIL) : (count_walk.next()) {
        if (!types.isPair(count_walk.cur)) {
            args_valid = false;
            break;
        }
        if (count_walk.cyclic()) return compiler_mod.circularFormError();
        nargs_count += 1;
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

    var arg_walk = compiler_mod.SpineWalk.init(types.cdr(expr));
    while (arg_walk.cur != types.NIL) : (arg_walk.next()) {
        const arg = types.car(arg_walk.cur);
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(arg, arg_reg, false);
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
        // set_targets_all: the pre-scan was truncated, so treat every name as
        // possibly reassigned (kaappi#1775).
        if (self.set_targets_all or st.contains(name)) return false;
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

    // #2405: the caller (compileCall) has already proven this spine acyclic
    // with its own guarded count walk, but the guard here is kept too — a
    // SpineWalk without cyclic() would read like a guard that is one
    // (review of PR #2413), and the redundancy is one integer compare.
    var arg_list = compiler_mod.SpineWalk.init(types.cdr(expr));
    while (types.isPair(arg_list.cur)) : (arg_list.next()) {
        if (arg_list.cyclic()) return compiler_mod.circularFormError();
        const arg = types.car(arg_list.cur);
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(arg, arg_reg, false);
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

/// `(apply f a ... lst)` in either position (kaappi#2451). Tail position emits
/// `tail_apply`; non-tail emits the `apply` opcode, which — unlike the native
/// `applyFn` it replaces there — calls the flattened callee with an ordinary VM
/// frame, so a continuation captured inside it survives the call's return.
pub fn compileApplyForm(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
    var arg_list = types.cdr(expr);
    // A *proper* operand list of the wrong length (< 2) is an arity question,
    // not a syntax question: route the form through the ordinary call path so
    // the native apply's runtime arity check reports KP3003 exactly as the
    // same form one position away does (#2036). Only an improper list is
    // malformed syntax. #2405: guarded — a cyclic operand spine spun forever.
    {
        var count: usize = 0;
        var walk = compiler_mod.SpineWalk.init(arg_list);
        while (types.isPair(walk.cur)) : (walk.next()) {
            if (walk.cyclic()) return compiler_mod.circularFormError();
            count += 1;
        }
        if (walk.cur != types.NIL) return CompileError.InvalidSyntax;
        if (count < 2) return compileCall(self, expr, dst, is_tail);
    }

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try self.compileExprViaIR(types.car(arg_list), base, false);
    arg_list = types.cdr(arg_list);

    // The count walk above proved this spine acyclic; cyclic() stays as the
    // self-documenting (and cheap) redundancy — see compileSelfTailCall.
    var rest = compiler_mod.SpineWalk.init(arg_list);
    var nargs_count: usize = 0;
    while (types.isPair(rest.cur)) : (rest.next()) {
        if (rest.cyclic()) return compiler_mod.circularFormError();
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(types.car(rest.cur), arg_reg, false);
        nargs_count += 1;
    }

    if (nargs_count > 255) return CompileError.InternalLimit;
    const nargs: u8 = @intCast(nargs_count);

    try self.emitOp(if (is_tail) .tail_apply else .apply);
    try self.emitU16(base);
    try self.emit(nargs);

    var i: u8 = 0;
    while (i < nargs) : (i += 1) {
        self.freeReg();
    }
    if (needs_rebase) {
        // The non-tail opcode leaves its result in `base`, exactly as `call`
        // does; `tail_apply` never returns here at all.
        if (!is_tail) {
            try self.emitOp(.move);
            try self.emitU16(dst);
            try self.emitU16(base);
        }
        self.freeReg();
    }
}

pub fn compileCallWithValuesForm(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
    // (call-with-values producer consumer), either position.
    // Emits bytecode directly: check both operands, call the producer with an
    // ordinary `call` opcode, spread the produced values into an argument
    // list, then apply/tail_apply the consumer over that list. Both halves of
    // the form now run from the dispatch loop: the consumer since #2451, the
    // producer since #2453 — its frame is a VM frame in this function's
    // bytecode, copied by continuation capture and restored by resume, so a
    // continuation captured inside it is resumable after the form returns in
    // both positions. (Before, the producer ran under a native primitive's
    // Zig frame — `%call-with-values->list`'s, and `callWithValuesFn`'s before
    // that — which the resumed continuation cannot reinstall.)
    //
    // Diagnostic parity is why the sequence starts with a call to
    // `%call-with-values-check`: callWithValuesFn type-checks BOTH operands,
    // producer first, before anything runs, and reports each through
    // `typeError("call-with-values", ...)` — so a bad consumer or producer is
    // still reported as `call-with-values` rather than as the `apply` this
    // compiles into, and still before the other operand's side effects. The
    // internal primitive is loaded via self.emitTrueBuiltinLoad, which marks
    // the reference to resolve through the pristine registry at run time
    // rather than by ordinary name lookup, so neither a lexical shadow NOR a
    // top-level redefinition of anything can divert it (#1715).
    //
    // A *proper* argument list of the wrong length is an arity question, not a
    // syntax question: route the form through the ordinary call path so the
    // runtime arity check reports KP3003 exactly as the same form one position
    // away does (#2036). Only an improper list is malformed syntax. #2405:
    // guarded — a cyclic argument spine spun the count forever.
    {
        var count: usize = 0;
        var walk = compiler_mod.SpineWalk.init(types.cdr(expr));
        while (types.isPair(walk.cur)) : (walk.next()) {
            if (walk.cyclic()) return compiler_mod.circularFormError();
            count += 1;
        }
        if (walk.cur != types.NIL) return CompileError.InvalidSyntax;
        if (count != 2) return compileCall(self, expr, dst, is_tail);
    }
    const args = types.cdr(expr);
    const producer = types.car(args);
    const rest = types.cdr(args);
    const consumer = types.car(rest);

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try self.compileExprViaIR(consumer, base, false);

    const check_base = try self.allocReg();
    const producer_reg = try self.allocReg();
    const consumer_reg = try self.allocReg();

    try self.compileExprViaIR(producer, producer_reg, false);

    // The consumer is already evaluated (in `base`); pass a copy for the
    // type check. check_base/producer_reg/consumer_reg are consecutive, the
    // layout `call check_base, 2` reads its callee and two operands from.
    try self.emitOp(.move);
    try self.emitU16(consumer_reg);
    try self.emitU16(base);
    try self.emitTrueBuiltinLoad("%call-with-values-check", check_base);
    try self.emitOp(.call);
    try self.emitU16(check_base);
    try self.emit(2);

    self.freeReg(); // consumer_reg

    // The producer call: an ordinary `call` opcode, so its frame lives in the
    // copied VM state (#2453). The result (a single value or a MultipleValues
    // object) lands in producer_reg, the register `call` delivers into.
    try self.emitOp(.call);
    try self.emitU16(producer_reg);
    try self.emit(0);

    // Spread the produced value(s) into the consumer's argument list.
    // check_base is dead since the check call returned and is exactly base+1
    // — the register the apply below reads its list operand from.
    try self.emitOp(.values_list);
    try self.emitU16(check_base);
    try self.emitU16(producer_reg);

    self.freeReg(); // producer_reg

    try self.emitOp(if (is_tail) .tail_apply else .apply);
    try self.emitU16(base);
    try self.emit(1);

    self.freeReg(); // check_base
    if (needs_rebase) {
        if (!is_tail) {
            try self.emitOp(.move);
            try self.emitU16(dst);
            try self.emitU16(base);
        }
        self.freeReg();
    }
}

pub fn compileCallCCTail(self: *Compiler, expr: Value, dst: u16) CompileError!void {
    // A *proper* argument list of the wrong length is an arity question, not a
    // syntax question: route the form through the ordinary call path so the
    // runtime arity check reports KP3003 exactly as the same form one position
    // away does (#2036). Only an improper list is malformed syntax. #2405:
    // guarded — a cyclic argument spine spun the count forever.
    {
        var count: usize = 0;
        var walk = compiler_mod.SpineWalk.init(types.cdr(expr));
        while (types.isPair(walk.cur)) : (walk.next()) {
            if (walk.cyclic()) return compiler_mod.circularFormError();
            count += 1;
        }
        if (walk.cur != types.NIL) return CompileError.InvalidSyntax;
        if (count != 1) return compileCall(self, expr, dst, true);
    }
    const receiver = types.car(types.cdr(expr));

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
    var arg_list = compiler_mod.SpineWalk.init(types.cdr(expr));
    while (arg_list.cur != types.NIL) : (arg_list.next()) {
        if (!types.isPair(arg_list.cur)) return CompileError.InvalidSyntax;
        if (arg_list.cyclic()) return compiler_mod.circularFormError();
        const arg = types.car(arg_list.cur);
        const arg_reg = try self.allocReg();
        try self.compileExprViaIR(arg, arg_reg, false);
        nargs_count += 1;
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
