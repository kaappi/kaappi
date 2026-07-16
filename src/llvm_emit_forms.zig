// Native lowering of cond/case/do for the LLVM backend (kaappi#1496).
//
// These three forms desugar into machinery the emitter already lowers well —
// `if`-style block/phi chains for cond and case, and a self-branching loop for
// do — so routing them through `kaappi_eval` (as the generic sexpr-form
// fallback does) is pure overhead. Each entry point first checks that every
// sub-form is emittable in the current lexical scope (`exprNativeEmittable`);
// if not, it either falls back to the interpreter at top level (where a
// global-environment eval is correct) or, inside a native let/lambda body,
// returns an error so the enclosing form abandons native compilation as a
// whole (the #827 discipline — never split a lexical scope across the
// native/interpreted boundary).
//
// The gate deliberately rejects `lambda`, `=>` clauses, and every eval-fallback
// / passthrough special form (letrec, guard, apply, call/cc, …) and any macro
// use. Rejecting lambdas also sidesteps do's fresh-binding-per-iteration
// semantics: with no closure able to capture a loop variable, mutable allocas
// updated in place are observably equivalent.

const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");

const llvm_emit = @import("llvm_emit.zig");
const LLVMEmitter = llvm_emit.LLVMEmitter;
const EmitError = llvm_emit.EmitError;

const Value = types.Value;

const false_bits: i64 = @bitCast(types.FALSE);
const void_bits: i64 = @bitCast(types.VOID);

// Cap on `do` loop variables — bounds the fixed-size scratch arrays below and
// matches emitLet's 32-binding ceiling. A wider `do` falls back to eval.
const MAX_DO_VARS = 32;

fn fmt(self: *LLVMEmitter, comptime f: []const u8, a: anytype) EmitError![]const u8 {
    return std.fmt.allocPrint(self.allocator(), f, a) catch return error.OutOfMemory;
}

// Lower a sub-expression to IR for native emission. The emittability gate has
// already validated the surrounding structure, so a lowering failure here is a
// resource limit or malformed leaf; mapping it to UnsupportedNodeType routes an
// in-scope form to its enclosing form's abandon path (a top-level form has no
// partial state to unwind at this point — the leaf lowers before any branch).
fn lower(self: *LLVMEmitter, expr: Value, tail: bool) EmitError!*ir.Node {
    return ir.lowerSingleExprTail(self.allocator(), expr, tail) catch return error.UnsupportedNodeType;
}

// ---------------------------------------------------------------------------
// cond
// ---------------------------------------------------------------------------

pub fn emitCond(self: *LLVMEmitter, args: Value, is_tail: bool) EmitError![]const u8 {
    if (!condArgsEmittable(self, args)) return fallback(self, args, "cond");
    // (cond) with no clauses is unspecified — yield void.
    if (!types.isPair(args)) return self.emitImm(void_bits);

    const merge = try self.freshLabel("cond_merge_");
    var incomings: std.ArrayList([]const u8) = .empty;
    defer incomings.deinit(self.backing_alloc);

    var clause_list = args;
    var had_else = false;
    while (types.isPair(clause_list)) : (clause_list = types.cdr(clause_list)) {
        const clause = types.car(clause_list);
        const test_expr = types.car(clause);
        const body = types.cdr(clause);

        if (isKeyword(test_expr, "else")) {
            const v = try emitBody(self, body, is_tail);
            try incomings.append(self.backing_alloc, try fmt(self, "[ {s}, %{s} ]", .{ v, self.current_block }));
            try self.print("  br label %{s}\n", .{merge});
            had_else = true;
            break;
        }

        const test_node = try lower(self, test_expr, false);
        const tval = try self.emitNode(test_node);
        const cmp = try self.freshTemp();
        try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, tval, false_bits });
        const test_end = self.current_block;

        if (body == types.NIL) {
            // (test) with no body: the test value is the result when truthy.
            const next = try self.freshLabel("cond_next_");
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, merge, next });
            try incomings.append(self.backing_alloc, try fmt(self, "[ {s}, %{s} ]", .{ tval, test_end }));
            try self.startBlock(next);
        } else {
            const body_lbl = try self.freshLabel("cond_body_");
            const next = try self.freshLabel("cond_next_");
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, body_lbl, next });
            try self.startBlock(body_lbl);
            const v = try emitBody(self, body, is_tail);
            try incomings.append(self.backing_alloc, try fmt(self, "[ {s}, %{s} ]", .{ v, self.current_block }));
            try self.print("  br label %{s}\n", .{merge});
            try self.startBlock(next);
        }
    }

    // No clause matched and there was no else: the value is unspecified.
    if (!had_else) {
        try incomings.append(self.backing_alloc, try fmt(self, "[ {d}, %{s} ]", .{ void_bits, self.current_block }));
        try self.print("  br label %{s}\n", .{merge});
    }

    return emitMergePhi(self, merge, incomings.items);
}

// ---------------------------------------------------------------------------
// case
// ---------------------------------------------------------------------------

pub fn emitCase(self: *LLVMEmitter, args: Value, is_tail: bool) EmitError![]const u8 {
    if (!caseArgsEmittable(self, args)) return fallback(self, args, "case");

    const key_expr = types.car(args);
    const clauses = types.cdr(args);

    // Evaluate the key once and keep it rooted across every clause's eqv?
    // comparisons (which may allocate while interning symbol/heap datums).
    // A matched body pops this root at its own entry — the key is dead there
    // (=> clauses, which would need it, are rejected by the gate) — so bodies
    // stay in tail position.
    const key_node = try lower(self, key_expr, false);
    const key_val = try self.emitNode(key_node);
    const key_slot = try self.freshTemp();
    try self.print("  {s} = alloca i64, align 8\n", .{key_slot});
    try self.print("  store i64 {s}, ptr {s}\n", .{ key_val, key_slot });
    try self.emitRootPushAlloca(key_slot);

    const merge = try self.freshLabel("case_merge_");
    var incomings: std.ArrayList([]const u8) = .empty;
    defer incomings.deinit(self.backing_alloc);

    var clause_list = clauses;
    var had_else = false;
    while (types.isPair(clause_list)) : (clause_list = types.cdr(clause_list)) {
        const clause = types.car(clause_list);
        const datums = types.car(clause);
        const body = types.cdr(clause);

        if (isKeyword(datums, "else")) {
            try self.emitPopRoots(1);
            const v = try emitBody(self, body, is_tail);
            try incomings.append(self.backing_alloc, try fmt(self, "[ {s}, %{s} ]", .{ v, self.current_block }));
            try self.print("  br label %{s}\n", .{merge});
            had_else = true;
            break;
        }

        // An empty datum list is a dead clause (R7RS): emit no comparison.
        if (datums == types.NIL) continue;

        const body_lbl = try self.freshLabel("case_body_");
        var datum_list = datums;
        while (types.isPair(datum_list)) : (datum_list = types.cdr(datum_list)) {
            const datum = types.car(datum_list);
            const matched = try emitEqvMatch(self, key_slot, datum);
            if (!types.isPair(types.cdr(datum_list))) {
                const next = try self.freshLabel("case_next_");
                try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ matched, body_lbl, next });
                try self.startBlock(body_lbl);
                try self.emitPopRoots(1);
                const v = try emitBody(self, body, is_tail);
                try incomings.append(self.backing_alloc, try fmt(self, "[ {s}, %{s} ]", .{ v, self.current_block }));
                try self.print("  br label %{s}\n", .{merge});
                try self.startBlock(next);
            } else {
                const check = try self.freshLabel("case_check_");
                try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ matched, body_lbl, check });
                try self.startBlock(check);
            }
        }
    }

    if (!had_else) {
        try self.emitPopRoots(1);
        try incomings.append(self.backing_alloc, try fmt(self, "[ {d}, %{s} ]", .{ void_bits, self.current_block }));
        try self.print("  br label %{s}\n", .{merge});
    }

    return emitMergePhi(self, merge, incomings.items);
}

// Emit `(eqv? <key> <datum>)` and return an `i1` that is true when they match.
// Mirrors the interpreter's per-datum eqv? dispatch (compiler_advanced.zig) so
// symbol/number/char keys compare identically.
fn emitEqvMatch(self: *LLVMEmitter, key_slot: []const u8, datum: Value) EmitError![]const u8 {
    const sym = try self.internSymbol("eqv?");
    const callee = try self.freshTemp();
    try self.print("  {s} = call i64 @kaappi_global_lookup(ptr %vm, ptr {s}, i64 4)\n", .{ callee, sym });
    try self.emitRootPush(callee);
    const a = try self.freshTemp();
    try self.print("  {s} = load i64, ptr {s}\n", .{ a, key_slot });
    try self.emitRootPush(a);
    const b = try self.emitConstant(datum);
    try self.emitPopRoots(2);

    const argv = try self.freshTemp();
    try self.print("  {s} = alloca [2 x i64], align 8\n", .{argv});
    const g0 = try self.freshTemp();
    try self.print("  {s} = getelementptr [1 x i64], ptr {s}, i64 0\n", .{ g0, argv });
    try self.print("  store i64 {s}, ptr {s}\n", .{ a, g0 });
    const g1 = try self.freshTemp();
    try self.print("  {s} = getelementptr [1 x i64], ptr {s}, i64 1\n", .{ g1, argv });
    try self.print("  store i64 {s}, ptr {s}\n", .{ b, g1 });
    const res = try self.freshTemp();
    try self.print("  {s} = call i64 @kaappi_call_scheme(ptr %vm, i64 {s}, ptr {s}, i64 2)\n", .{ res, callee, argv });

    const cmp = try self.freshTemp();
    try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, res, false_bits });
    return cmp;
}

// ---------------------------------------------------------------------------
// do
// ---------------------------------------------------------------------------

pub fn emitDo(self: *LLVMEmitter, args: Value, is_tail: bool) EmitError![]const u8 {
    // `do`'s result runs after the loop with the binding roots still live (it
    // may reference the loop variables), so it is emitted non-tail regardless
    // of the enclosing tail position — the roots pop after it computes.
    _ = is_tail;
    if (!doArgsEmittable(self, args)) return fallback(self, args, "do");

    const specs = types.car(args);
    const rest = types.cdr(args);
    const test_clause = types.car(rest);
    const commands = types.cdr(rest);
    const test_expr = types.car(test_clause);
    const result_exprs = types.cdr(test_clause);

    var var_names: [MAX_DO_VARS][]const u8 = undefined;
    var allocas: [MAX_DO_VARS][]const u8 = undefined;
    var steps: [MAX_DO_VARS]Value = undefined;
    var n: usize = 0;

    // Phase 1: evaluate every init in the OUTER scope (do has let semantics —
    // inits do not see the loop bindings), store into a fresh rooted alloca.
    var s = specs;
    while (types.isPair(s)) : (s = types.cdr(s)) {
        const spec = types.car(s);
        const init_expr = types.car(types.cdr(spec));
        const init_node = try lower(self, init_expr, false);
        const init_val = try self.emitNode(init_node);
        const alloca = try self.freshTemp();
        try self.print("  {s} = alloca i64, align 8\n", .{alloca});
        try self.print("  store i64 {s}, ptr {s}\n", .{ init_val, alloca });
        try self.emitRootPushAlloca(alloca);
        var_names[n] = types.symbolName(types.car(spec));
        const step_rest = types.cdr(types.cdr(spec));
        steps[n] = if (types.isPair(step_rest)) types.car(step_rest) else types.VOID;
        allocas[n] = alloca;
        n += 1;
    }

    // Phase 2: bind all loop variables at once (parallel, not sequential).
    const saved_locals = self.locals;
    self.locals = if (saved_locals) |existing|
        existing.clone() catch return error.OutOfMemory
    else
        std.StringHashMap(llvm_emit.LocalBinding).init(self.allocator());
    defer {
        self.locals.?.deinit();
        self.locals = saved_locals;
    }
    for (0..n) |i| self.locals.?.put(var_names[i], .{ .slot = allocas[i] }) catch return error.OutOfMemory;

    const header = try self.freshLabel("do_header_");
    const body_lbl = try self.freshLabel("do_body_");
    const exit_lbl = try self.freshLabel("do_exit_");

    try self.print("  br label %{s}\n", .{header});
    try self.startBlock(header);
    const test_node = try lower(self, test_expr, false);
    const tval = try self.emitNode(test_node);
    const cmp = try self.freshTemp();
    try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, tval, false_bits });
    try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, exit_lbl, body_lbl });

    // Body: commands for effect, then all steps, then loop back.
    try self.startBlock(body_lbl);
    var c = commands;
    while (types.isPair(c)) : (c = types.cdr(c)) {
        const cnode = try lower(self, types.car(c), false);
        _ = try self.emitNode(cnode);
    }

    // Evaluate every step into a temp (rooting each across the next's
    // evaluation, à la emitSelfTailCall), then store them all back — do's
    // steps see the *current* bindings, so no store may precede an evaluation.
    var stepped: [MAX_DO_VARS]usize = undefined;
    var ns: usize = 0;
    for (0..n) |i| {
        if (steps[i] != types.VOID) {
            stepped[ns] = i;
            ns += 1;
        }
    }
    var step_tmps: [MAX_DO_VARS][]const u8 = undefined;
    var roots: usize = 0;
    for (0..ns) |k| {
        const snode = try lower(self, steps[stepped[k]], false);
        step_tmps[k] = try self.emitNode(snode);
        if (k + 1 < ns) {
            try self.emitRootPush(step_tmps[k]);
            roots += 1;
        }
    }
    try self.emitPopRoots(roots);
    for (0..ns) |k| {
        try self.print("  store i64 {s}, ptr {s}\n", .{ step_tmps[k], allocas[stepped[k]] });
    }
    try self.print("  br label %{s}\n", .{header});

    // Exit: evaluate the result expressions (or void), then drop the roots.
    try self.startBlock(exit_lbl);
    const result_val = if (types.isPair(result_exprs))
        try emitBody(self, result_exprs, false)
    else
        try self.emitImm(void_bits);
    try self.emitPopRoots(n);
    return result_val;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

// A form that cannot be lowered natively: at top level a whole-form eval in the
// global environment is correct; inside a native lexical scope, signal the
// enclosing let/lambda to abandon native compilation (it re-evaluates the whole
// enclosing form as one unit, preserving scope).
fn fallback(self: *LLVMEmitter, args: Value, form_name: []const u8) EmitError![]const u8 {
    if (self.inLexicalScope()) return error.UnsupportedNodeType;
    return self.emitFormEval(args, form_name);
}

// Emit a body (a `begin` of expressions), returning the last value. The final
// expression inherits the caller's tail position.
fn emitBody(self: *LLVMEmitter, body: Value, is_tail: bool) EmitError![]const u8 {
    if (!types.isPair(body)) return self.emitImm(void_bits);
    var last: []const u8 = undefined;
    var e = body;
    while (types.isPair(e)) : (e = types.cdr(e)) {
        const rest = types.cdr(e);
        const tail = is_tail and !types.isPair(rest);
        const node = try lower(self, types.car(e), tail);
        last = try self.emitNode(node);
    }
    return last;
}

fn emitMergePhi(self: *LLVMEmitter, merge: []const u8, incomings: []const []const u8) EmitError![]const u8 {
    try self.startBlock(merge);
    const result = try self.freshTemp();
    try self.print("  {s} = phi i64 ", .{result});
    for (incomings, 0..) |inc, i| {
        if (i != 0) try self.write(", ");
        try self.write(inc);
    }
    try self.write("\n");
    return result;
}

fn isKeyword(v: Value, name: []const u8) bool {
    return types.isSymbol(v) and std.mem.eql(u8, types.symbolName(v), name);
}

// ---------------------------------------------------------------------------
// Emittability gate
// ---------------------------------------------------------------------------

// Special-form heads the native backend cannot lower in the current lexical
// scope (they route through eval / passthrough) or deliberately declines to
// handle here (lambda, => markers). A form containing any of these is sent to
// the interpreter as a whole.
fn isRejectedFormHead(name: []const u8) bool {
    const rejected = [_][]const u8{
        "lambda",           "letrec",                         "letrec*",
        "guard",            "quasiquote",                     "delay",
        "delay-force",      "parameterize",                   "define-values",
        "let-values",       "let*-values",                    "define-syntax",
        "let-syntax",       "letrec-syntax",                  "cond-expand",
        "case-lambda",      "define",                         "define-record-type",
        "apply",            "call-with-current-continuation", "call/cc",
        "call-with-values", "eval",                           "import",
        "include",          "include-ci",                     "define-library",
        "syntax-rules",     "syntax-error",                   "unquote",
        "unquote-splicing", "else",                           "=>",
    };
    for (rejected) |r| {
        if (std.mem.eql(u8, name, r)) return true;
    }
    return false;
}

// True if `expr` is an expression the emitter can lower natively while
// respecting the current lexical scope. Conservative by design: anything not
// on the allow-list (a macro use, a rejected special form, an improper list)
// makes the whole enclosing cond/case/do fall back.
fn exprNativeEmittable(self: *LLVMEmitter, expr: Value) bool {
    if (types.isSymbol(expr)) return true; // variable reference
    if (!types.isPair(expr)) return true; // self-evaluating datum
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (self.isMacroName(name)) return false;
        if (std.mem.eql(u8, name, "quote")) return true; // opaque literal
        if (isRejectedFormHead(name)) return false;
        if (std.mem.eql(u8, name, "let")) return letArgsEmittable(self, types.cdr(expr));
        if (std.mem.eql(u8, name, "let*")) return letArgsEmittable(self, types.cdr(expr));
        if (std.mem.eql(u8, name, "cond")) return condArgsEmittable(self, types.cdr(expr));
        if (std.mem.eql(u8, name, "case")) return caseArgsEmittable(self, types.cdr(expr));
        if (std.mem.eql(u8, name, "do")) return doArgsEmittable(self, types.cdr(expr));
        // if/begin/and/or/when/unless/set! and ordinary calls fall through:
        // every list element is itself an expression (the keyword/operator is
        // a harmless symbol), so validating them all covers these forms.
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (!exprNativeEmittable(self, types.car(cur))) return false;
    }
    return cur == types.NIL; // reject dotted/improper lists
}

// `(bindings body ...)` tail of a let/let*. Rejects named let (handled
// elsewhere) and keeps the binding count within emitLet's native ceiling so a
// let that passes here is one emitLet compiles natively rather than abandons.
fn letArgsEmittable(self: *LLVMEmitter, args: Value) bool {
    if (!types.isPair(args)) return false;
    if (types.isSymbol(types.car(args))) return false; // named let
    var count: usize = 0;
    var b = types.car(args);
    while (types.isPair(b)) : (b = types.cdr(b)) {
        const binding = types.car(b);
        if (!types.isPair(binding)) return false;
        if (!types.isSymbol(types.car(binding))) return false;
        const init_list = types.cdr(binding);
        if (!types.isPair(init_list)) return false;
        if (!exprNativeEmittable(self, types.car(init_list))) return false;
        count += 1;
        if (count > 32) return false;
    }
    if (b != types.NIL) return false;
    var body = types.cdr(args);
    if (!types.isPair(body)) return false; // a let needs a body
    while (types.isPair(body)) : (body = types.cdr(body)) {
        if (!exprNativeEmittable(self, types.car(body))) return false;
    }
    return body == types.NIL;
}

// Reject a clause whose body is a `=> proc` tail: native arrow clauses are not
// implemented yet, so such a cond/case falls back to the interpreter.
fn hasArrowBody(body: Value) bool {
    return types.isPair(body) and isKeyword(types.car(body), "=>");
}

fn bodyEmittable(self: *LLVMEmitter, body: Value) bool {
    var b = body;
    while (types.isPair(b)) : (b = types.cdr(b)) {
        if (!exprNativeEmittable(self, types.car(b))) return false;
    }
    return b == types.NIL;
}

fn condArgsEmittable(self: *LLVMEmitter, clauses: Value) bool {
    var cl = clauses;
    while (types.isPair(cl)) : (cl = types.cdr(cl)) {
        const clause = types.car(cl);
        if (!types.isPair(clause)) return false;
        const test_expr = types.car(clause);
        const body = types.cdr(clause);
        if (isKeyword(test_expr, "else")) {
            if (types.isPair(types.cdr(cl))) return false; // else must be last
        } else if (!exprNativeEmittable(self, test_expr)) {
            return false;
        }
        if (hasArrowBody(body)) return false;
        if (!bodyEmittable(self, body)) return false;
    }
    return cl == types.NIL;
}

fn caseArgsEmittable(self: *LLVMEmitter, args: Value) bool {
    if (!types.isPair(args)) return false; // need a key
    if (!exprNativeEmittable(self, types.car(args))) return false;
    var cl = types.cdr(args);
    while (types.isPair(cl)) : (cl = types.cdr(cl)) {
        const clause = types.car(cl);
        if (!types.isPair(clause)) return false;
        const datums = types.car(clause);
        const body = types.cdr(clause);
        if (isKeyword(datums, "else")) {
            if (types.isPair(types.cdr(cl))) return false; // else must be last
        } else {
            // Datums are literals (never evaluated), but the list must be proper.
            var d = datums;
            while (types.isPair(d)) : (d = types.cdr(d)) {}
            if (d != types.NIL) return false;
        }
        if (hasArrowBody(body)) return false;
        if (!bodyEmittable(self, body)) return false;
    }
    return cl == types.NIL;
}

fn doArgsEmittable(self: *LLVMEmitter, args: Value) bool {
    if (!types.isPair(args)) return false;
    const rest = types.cdr(args);
    if (!types.isPair(rest)) return false;
    const test_clause = types.car(rest);
    if (!types.isPair(test_clause)) return false;

    var count: usize = 0;
    var s = types.car(args);
    while (types.isPair(s)) : (s = types.cdr(s)) {
        const spec = types.car(s);
        if (!types.isPair(spec)) return false;
        if (!types.isSymbol(types.car(spec))) return false;
        const init_list = types.cdr(spec);
        if (!types.isPair(init_list)) return false;
        if (!exprNativeEmittable(self, types.car(init_list))) return false;
        const step_rest = types.cdr(init_list);
        if (types.isPair(step_rest)) {
            if (!exprNativeEmittable(self, types.car(step_rest))) return false;
            if (types.cdr(step_rest) != types.NIL) return false; // one step only
        } else if (step_rest != types.NIL) {
            return false;
        }
        count += 1;
        if (count > MAX_DO_VARS) return false;
    }
    if (s != types.NIL) return false;

    if (!exprNativeEmittable(self, types.car(test_clause))) return false;
    if (!bodyEmittable(self, types.cdr(test_clause))) return false; // result exprs
    return bodyEmittable(self, types.cdr(rest)); // commands
}
