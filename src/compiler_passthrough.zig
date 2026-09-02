const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");
const expander = @import("expander.zig");
const reader_mod = @import("reader.zig");
const memory = @import("memory.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;

// -- Compilation-unit top-level targets (kaappi#2457) ------------------------
//
// `globalBindingStillGenuine` decides the builtin superinstruction fast paths
// (apply / call-with-values in any position, eval / call/cc in tail) by
// reading the live global environment at COMPILE time. That answer is wrong
// for a procedure body compiled BEFORE a later top-level `(define apply ...)`
// runs: R7RS 5.3.1 makes the definition essentially an assignment, so which
// binding a call resolves is a run-time question the compile-time read cannot
// settle in that order. The honest fix is a run-time decision (follow-up); the
// interim is this set: when a driver that knows the whole compilation unit
// (the file runner, stdin scripts, `kaappi compile`, `kaappi check`) sees the
// name defined or assigned at top level ANYWHERE in the unit, every fast-path
// decision in the unit declines, costing the superinstruction only in the
// programs whose semantics it was getting wrong.
//
// Per-form entry points (the REPL, `eval`) have no future knowledge and leave
// this null, keeping the legacy compile-time answer — a redefinition typed
// later in a REPL session still cannot retro-fix an earlier-compiled body,
// exactly as before.

/// Names defined (define / define-values) or assigned (set!) at top level
/// anywhere in the compilation unit currently being compiled. Keys are owned
/// by the driver that populated the set and outlive every compile in the
/// unit. Null on entry points without whole-unit knowledge.
pub threadlocal var unit_top_level_targets: ?*const std.StringHashMap(void) = null;

/// Fill `out` with every name a top-level `define`, `define-values` or `set!`
/// targets anywhere in `source`, recursing into top-level `begin` and
/// `cond-expand` splices (R7RS 5.1 / 4.2.1) like check.zig's lint collector.
/// Names are duped into the map, which must outlive the unit's compiles; the
/// transient datums read here are rooted only for the walk.
///
/// Structure-only, like Part B of the set! pre-scan: a redefinition that only
/// materializes when a macro expands is not seen, so such a unit keeps the
/// legacy behavior. (The per-form pre-scan catches those at the define's own
/// form; a unit-level speculative expansion pass would cost the whole
/// expansion budget on every file for the rare case.) A read error stops the
/// scan — the real run reports it, and nothing past it executes.
pub fn collectUnitTopLevelTargets(out: *std.StringHashMap(void), gc: *memory.GC, source: []const u8) void {
    var r = reader_mod.Reader.init(gc, source);
    defer r.deinit();
    while (r.hasMore() catch false) {
        var expr = r.readDatum() catch return;
        gc.pushRoot(&expr);
        collectTargetsFromUnitForm(out, expr);
        gc.popRoot();
    }
}

fn collectTargetsFromUnitForm(out: *std.StringHashMap(void), expr: Value) void {
    if (!types.isPair(expr) or !types.isSymbol(types.car(expr))) return;
    const head = types.stripHygienicPrefix(types.symbolName(types.car(expr)));
    const rest = types.cdr(expr);

    // Every spine walked below can carry a datum-label cycle in code position
    // (R7RS 7.1.2 `#n=`/`#n#` — `(begin . #0=(1 . #0#))` is a real program
    // the run loop diagnoses as KP2001), so each walk is a guarded SpineWalk,
    // never a bare `while isPair` (the #2405 family).
    if (std.mem.eql(u8, head, "define")) {
        // (define name ...) or (define (name . formals) ...)
        if (types.isPair(rest)) addUnitTarget(out, types.car(rest));
    } else if (std.mem.eql(u8, head, "set!")) {
        if (types.isPair(rest) and types.isSymbol(types.car(rest))) {
            addUnitName(out, types.symbolName(types.car(rest)));
        }
    } else if (std.mem.eql(u8, head, "define-values")) {
        // (define-values (a b . rest) expr) — every formal is bound.
        if (types.isPair(rest)) {
            var f = compiler_mod.SpineWalk.init(types.car(rest));
            while (types.isPair(f.cur)) : (f.next()) {
                if (f.cyclic()) return;
                if (types.isSymbol(types.car(f.cur))) addUnitName(out, types.symbolName(types.car(f.cur)));
            }
            if (types.isSymbol(f.cur)) addUnitName(out, types.symbolName(f.cur));
        }
    } else if (std.mem.eql(u8, head, "begin")) {
        // Top-level begin splices: each child is a top-level form (R7RS 5.1).
        // The walk stops at a cycle rather than reporting it — the real run's
        // own begin handler is the one that diagnoses, and it runs after (and
        // independently of) this scan.
        var cur = compiler_mod.SpineWalk.init(rest);
        while (types.isPair(cur.cur)) : (cur.next()) {
            if (cur.cyclic()) return;
            collectTargetsFromUnitForm(out, types.car(cur.cur));
        }
    } else if (std.mem.eql(u8, head, "cond-expand")) {
        // A top-level cond-expand splices the selected clause's body as
        // top-level forms; without evaluating the feature requirements, take
        // every clause body — the same conservative over-approximation
        // check.zig's collector uses (the safe direction here too: an extra
        // name only declines a fast path).
        var clauses = compiler_mod.SpineWalk.init(rest);
        while (types.isPair(clauses.cur)) : (clauses.next()) {
            if (clauses.cyclic()) return;
            const clause = types.car(clauses.cur);
            if (!types.isPair(clause)) continue;
            var body = compiler_mod.SpineWalk.init(types.cdr(clause));
            while (types.isPair(body.cur)) : (body.next()) {
                if (body.cyclic()) return;
                collectTargetsFromUnitForm(out, types.car(body.cur));
            }
        }
    }
}

/// The target of a `define`: a bare symbol, or the head of a possibly-curried
/// procedure form `((name a) b)` — peel the leading pairs to the name symbol.
/// The peel advances by car, so a car-side datum-label cycle
/// (`(define #0=(#0# 1) ...)`) cannot use a cdr SpineWalk; a step cap bounds
/// it instead (real curried definitions are two or three deep).
fn addUnitTarget(out: *std.StringHashMap(void), target: Value) void {
    var t = target;
    var steps: usize = 0;
    while (types.isPair(t)) : (t = types.car(t)) {
        steps += 1;
        if (steps > 256) return;
    }
    if (types.isSymbol(t)) addUnitName(out, types.symbolName(t));
}

fn addUnitName(out: *std.StringHashMap(void), name: []const u8) void {
    if (out.contains(name)) return;
    const owned = out.allocator.dupe(u8, name) catch return;
    out.put(owned, {}) catch out.allocator.free(owned);
    // Also record the hygiene-stripped spelling: since #2003 a macro
    // template's define/set! target is renamed (__hyg_N_<name>), and the
    // gate compares both the as-written and stripped spellings.
    const stripped = types.stripHygienicPrefix(name);
    if (stripped.len != name.len and !out.contains(stripped)) {
        const owned2 = out.allocator.dupe(u8, stripped) catch return;
        out.put(owned2, {}) catch out.allocator.free(owned2);
    }
}

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "collectUnitTopLevelTargets: define shapes, splices, and non-captures" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    var out = std.StringHashMap(void).init(std.testing.allocator);
    defer {
        var it = out.keyIterator();
        while (it.next()) |k| std.testing.allocator.free(k.*);
        out.deinit();
    }

    collectUnitTopLevelTargets(&out, &gc,
        \\(define (nt) (apply + (list 1 2)))
        \\(define (apply f xs) 'user)
        \\(begin (define (call-with-values p c) 'user) 'ignored)
        \\(cond-expand (kaappi (define eval 'user)) (else (define eval 'other)))
        \\(define-values (call/cc rest-arg . r) (values 1 2 3))
        \\(set! call-with-current-continuation (lambda (k) 'user))
        \\(define (other xs) (apply f (list xs)))
        \\(let ((q (quote (define not-a-target define)))) q)
    );

    // All five #2033 names, via every define shape and splice, plus set!.
    try std.testing.expect(out.contains("apply"));
    try std.testing.expect(out.contains("call-with-values"));
    try std.testing.expect(out.contains("eval"));
    try std.testing.expect(out.contains("call/cc"));
    try std.testing.expect(out.contains("call-with-current-continuation"));
    // define-values formals, including the rest formal.
    try std.testing.expect(out.contains("rest-arg"));
    // A lambda-local define, lambda formals, and quoted data contribute
    // nothing: the walk is top-level-only (through begin/cond-expand
    // splices) and never descends into other forms.
    try std.testing.expect(!out.contains("not-a-target"));
    try std.testing.expect(!out.contains("xs"));
    try std.testing.expect(!out.contains("q"));
}
