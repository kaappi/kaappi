const std = @import("std");
const types = @import("types.zig");
const expander = @import("expander.zig");
const compiler_mod = @import("compiler.zig");
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

    try self.compileExpr(test_expr, dst, false);

    try self.emitOp(.jump_false);
    try self.emitU16(dst);
    const else_jump = self.currentOffset();
    try self.emitI16(0);

    try self.compileExpr(consequent, dst, is_tail);

    if (rest2 != types.NIL) {
        try self.emitOp(.jump);
        const end_jump = self.currentOffset();
        try self.emitI16(0);

        try self.patchJump(else_jump);

        const alternate = types.car(rest2);
        try self.compileExpr(alternate, dst, is_tail);

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

pub fn parseSyntaxRules(self: *Compiler, spec: Value) CompileError!Value {
    if (!types.isPair(spec)) return CompileError.InvalidSyntax;
    const head = types.car(spec);
    if (!types.isSymbol(head)) return CompileError.InvalidSyntax;
    if (!std.mem.eql(u8, types.symbolName(head), "syntax-rules")) return CompileError.InvalidSyntax;

    const rest = types.cdr(spec);
    if (rest == types.NIL) return CompileError.InvalidSyntax;

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
            if (self.resolveLocal(op_name) == null and (try self.resolveUpvalue(op_name)) == null) {
                return compileSelfTailCall(self, expr, dst, nargs);
            }
        }
    }

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
                return compileCallGlobal(self, expr, operator, dst, is_tail);
            }
        }
    }

    if (!args_valid) return CompileError.InvalidSyntax;

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

    if (self.resolveLocal(name) != null) return false;
    if ((self.resolveUpvalue(name) catch null) != null) return false;

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

pub fn compileApplyTail(self: *Compiler, expr: Value, dst: u16) CompileError!void {
    var arg_list = types.cdr(expr);
    if (arg_list == types.NIL) return CompileError.InvalidSyntax;

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try self.compileExpr(types.car(arg_list), base, false);
    arg_list = types.cdr(arg_list);

    var nargs_count: usize = 0;
    while (arg_list != types.NIL) {
        if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
        const arg_reg = try self.allocReg();
        try self.compileExpr(types.car(arg_list), arg_reg, false);
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
        try self.compileExpr(arg, arg_reg, false);
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

// ---------------------------------------------------------------------------
// Free-reference collection for macro hygiene
// ---------------------------------------------------------------------------

pub fn collectSymbols(expr: Value, out: *[64][]const u8, count: *usize) bool {
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

pub fn collectFreeRefs(template: Value, pat_vars: []const []const u8, literals: []const Value, out: *[64][]const u8, count: *usize) bool {
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
            if (rest != types.NIL and types.isPair(rest)) {
                var sr_names: [64][]const u8 = undefined;
                var sr_count: usize = 0;
                for (local_binds) |lb| {
                    if (sr_count < 64) {
                        sr_names[sr_count] = lb;
                        sr_count += 1;
                    }
                }
                var rules = types.cdr(rest);
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
