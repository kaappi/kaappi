// Free-variable and capture analysis for the LLVM native backend's lambda and
// let emitters (split out of llvm_emit_lambda.zig, kaappi#1591). Pure analysis
// over IR nodes and raw S-expressions: nothing is emitted here. Each function
// answers a yes/no — or collects a name set — that the emitters use to decide
// whether a form compiles natively or must fall back to the interpreter.
//
// Entry points consumed by llvm_emit_lambda.zig / llvm_emit_let.zig:
//   sexprNeedsEvalFallback  body has a form the backend can't compile (#827)
//   sexprContainsDefine     body has an internal define (closure-tier reject, #819)
//   bodyHasCapturingLambda  a nested lambda captures a given local (#827)
//   sexprBodySetsName       a set! of a given name appears in the body (#1422/#1497)
//   analyzeBoxedParams      params that are both set! and captured → boxed (#1497)
//   hasFreeVars             the IR body references a name outside `params`
//   collectFreeVars         collect the exact captured-name set (closure upvalues)

const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");

const llvm_emit = @import("llvm_emit.zig");
const LLVMEmitter = llvm_emit.LLVMEmitter;

const Value = types.Value;

// --- Eval-fallback detection helpers ---

// True if `expr` (a raw S-expression) contains any form that the LLVM native
// backend cannot compile and would dispatch to emitSexprEval.  Used by
// emitLet and emitLambdaFunction to reject native compilation of the
// enclosing scope when a sub-form would cross the native/interpreted boundary,
// losing lexical bindings (#827).
pub fn sexprNeedsEvalFallback(expr: Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (isEvalFallbackForm(name)) return true;
        if (std.mem.eql(u8, name, "quote")) return false;
        // Named let: (let <symbol> ...) — not compiled natively.
        if (std.mem.eql(u8, name, "let")) {
            const rest = types.cdr(expr);
            if (rest != types.NIL and types.isPair(rest) and types.isSymbol(types.car(rest))) return true;
        }
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprNeedsEvalFallback(types.car(cur))) return true;
    }
    return false;
}

fn isEvalFallbackForm(name: []const u8) bool {
    for (ir.eval_fallback_form_names) |f| {
        if (std.mem.eql(u8, name, f)) return true;
    }
    return false;
}

// True if `body_list` (a cons list of body expressions) contains a lambda
// whose body references any name in `local_names` (let-bound variables) that
// is not shadowed by the lambda's own formals.  Such a lambda cannot be
// compiled natively inside a let scope: the native closure tiers
// (tryCompileNativeClosure / tryCompilePureLambdaAsNativeClosure) would
// reject it, and emitLambdaViaEval would evaluate it in the global
// environment where the let bindings are invisible (#827).
pub fn bodyHasCapturingLambda(self: *LLVMEmitter, body_list: Value, local_names: []const []const u8) bool {
    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        if (exprHasCapturingLambda(self, types.car(expr), local_names)) return true;
    }
    return false;
}

fn exprHasCapturingLambda(self: *LLVMEmitter, expr: Value, local_names: []const []const u8) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (std.mem.eql(u8, name, "lambda")) {
            const rest = types.cdr(expr);
            if (rest != types.NIL and types.isPair(rest)) {
                const formals = types.car(rest);
                const body = types.cdr(rest);
                // The nested lambda's formals shadow the outer locals: a
                // reference to one of them is not a capture. OOM while gathering
                // them is treated conservatively as "capturing" (fall back).
                var formal_names: std.ArrayList([]const u8) = .empty;
                var flist = formals;
                while (types.isPair(flist)) : (flist = types.cdr(flist)) {
                    const f = types.car(flist);
                    if (types.isSymbol(f)) formal_names.append(self.allocator(), types.symbolName(f)) catch return true;
                }
                // Rest-param symbol after dotted pair or bare symbol formals.
                if (types.isSymbol(flist)) formal_names.append(self.allocator(), types.symbolName(flist)) catch return true;
                if (types.isSymbol(formals)) formal_names.append(self.allocator(), types.symbolName(formals)) catch return true;
                if (sexprReferencesNames(body, local_names, formal_names.items)) return true;
            }
            return false;
        }
        if (std.mem.eql(u8, name, "quote")) return false;
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (exprHasCapturingLambda(self, types.car(cur), local_names)) return true;
    }
    return false;
}

// True if the S-expression references any symbol in `target_names` that is
// not in `excluded_names`.  Does not descend into quoted data.
fn sexprReferencesNames(expr: Value, target_names: []const []const u8, excluded_names: []const []const u8) bool {
    if (types.isSymbol(expr)) {
        const name = types.symbolName(expr);
        for (excluded_names) |e| {
            if (std.mem.eql(u8, name, e)) return false;
        }
        for (target_names) |t| {
            if (std.mem.eql(u8, name, t)) return true;
        }
        return false;
    }
    if (!types.isPair(expr)) return false;
    if (types.isSymbol(types.car(expr)) and std.mem.eql(u8, types.symbolName(types.car(expr)), "quote")) return false;
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprReferencesNames(types.car(cur), target_names, excluded_names)) return true;
    }
    return false;
}

// --- Free variable analysis helpers ---
//
// These take the emitter because classification must respect the enclosing
// emission scope: a name shadowed by an enclosing lexical binding (param,
// let-local, rest parameter, upvalue) is a capture even when a known global
// of the same name exists — `car` inside (lambda (car) ...) is the parameter,
// not the primitive. The shadow check must run before isKnownGlobal.

// True if the raw S-expression contains an internal define anywhere (not
// descending into quoted data). Used to reject closure bodies with an internal
// define, which needs a locals scope the closure tier does not set up. A set!
// is allowed — captured bindings it mutates are boxed by the enclosing frame
// (#1497).
pub fn sexprContainsDefine(expr: types.Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const h = types.symbolName(head);
        if (std.mem.eql(u8, h, "define")) return true;
        if (std.mem.eql(u8, h, "quote")) return false;
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprContainsDefine(types.car(cur))) return true;
    }
    return false;
}

// Per-frame assignment-conversion analysis (#1497). A native function's own
// binding needs boxing when it is BOTH mutated (a set! target somewhere in the
// body, including inside nested lambdas) AND captured by a nested lambda. Such
// a binding is materialized as a heap box so a later set! is visible through
// every closure that captured it — restoring the VM's by-location semantics.
// Bindings that are only mutated, or only captured, keep the by-value fast path.
pub const BoxAnalysis = struct {
    // Arena-allocated, parallel to the param_names passed to analyzeBoxedParams:
    // flags[i] true means fixed parameter i needs a box. Empty when the frame
    // has no fixed params.
    flags: []const bool = &.{},
    // A captured+mutated rest parameter cannot be boxed by the current model;
    // callers must reject native compilation (fall back to the interpreter).
    rest_conflict: bool = false,
    any: bool = false,
};

// Returns null on OOM (the arena allocations below can fail); callers treat that
// as "cannot compile natively" and fall back to the interpreter.
pub fn analyzeBoxedParams(self: *LLVMEmitter, body_list: Value, param_names: []const []const u8, rest_name: ?[]const u8) ?BoxAnalysis {
    if (param_names.len == 0 and rest_name == null) return BoxAnalysis{};

    // Which params / rest are assigned anywhere in the body. Indices 0..len map
    // to the fixed params; the trailing slot (index param_names.len) is the rest
    // parameter.
    const set_flags = self.allocator().alloc(bool, param_names.len + 1) catch return null;
    @memset(set_flags, false);
    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        sexprCollectSetTargets(types.car(expr), param_names, rest_name, set_flags);
    }

    // A binding needs boxing only if it is also captured by a nested lambda.
    const flags = self.allocator().alloc(bool, param_names.len) catch return null;
    @memset(flags, false);
    var any = false;
    for (param_names, 0..) |p, i| {
        if (set_flags[i] and bodyHasCapturingLambda(self, body_list, &.{p})) {
            flags[i] = true;
            any = true;
        }
    }
    var result = BoxAnalysis{ .flags = flags, .any = any };
    if (rest_name) |rn| {
        if (set_flags[param_names.len] and bodyHasCapturingLambda(self, body_list, &.{rn})) {
            result.rest_conflict = true;
        }
    }
    return result;
}

// True if the body ever assigns `name` with (set! name ...), not descending
// into quoted data. Used by the closure tier to verify that a captured
// variable it mutates was actually boxed by the enclosing frame, and by
// emitLet to decide which captured let-locals to box (#1497).
pub fn sexprBodySetsName(body_list: Value, name: []const u8) bool {
    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        if (sexprSetsName(types.car(expr), name)) return true;
    }
    return false;
}

fn sexprSetsName(expr: Value, name: []const u8) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const h = types.symbolName(head);
        if (std.mem.eql(u8, h, "quote")) return false;
        if (std.mem.eql(u8, h, "set!")) {
            const rest = types.cdr(expr);
            if (types.isPair(rest) and types.isSymbol(types.car(rest)) and
                std.mem.eql(u8, types.symbolName(types.car(rest)), name)) return true;
        }
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprSetsName(types.car(cur), name)) return true;
    }
    return false;
}

// flags has one slot per fixed param plus a trailing slot for the rest param
// (length param_names.len + 1), matching analyzeBoxedParams's set_flags.
fn sexprCollectSetTargets(expr: Value, param_names: []const []const u8, rest_name: ?[]const u8, flags: []bool) void {
    if (!types.isPair(expr)) return;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const h = types.symbolName(head);
        if (std.mem.eql(u8, h, "quote")) return;
        if (std.mem.eql(u8, h, "set!")) {
            const rest = types.cdr(expr);
            if (types.isPair(rest)) {
                const target = types.car(rest);
                if (types.isSymbol(target)) {
                    const tname = types.symbolName(target);
                    for (param_names, 0..) |p, i| {
                        if (std.mem.eql(u8, tname, p)) {
                            flags[i] = true;
                            break;
                        }
                    }
                    if (rest_name) |rn| {
                        if (std.mem.eql(u8, tname, rn)) {
                            flags[param_names.len] = true;
                        }
                    }
                }
            }
        }
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        sexprCollectSetTargets(types.car(cur), param_names, rest_name, flags);
    }
}

pub fn hasFreeVars(self: *LLVMEmitter, nodes: []const *ir.Node, params: []const []const u8) bool {
    for (nodes) |node| {
        if (nodeHasFreeVars(self, node, params)) return true;
    }
    return false;
}

fn nodeHasFreeVars(self: *LLVMEmitter, node: *const ir.Node, params: []const []const u8) bool {
    switch (node.tag) {
        .global_ref => {
            if (!types.isSymbol(node.data.global_ref)) return false;
            const name = types.symbolName(node.data.global_ref);
            for (params) |p| {
                if (std.mem.eql(u8, name, p)) return false;
            }
            // An enclosing lexical binding outranks a known global of the
            // same name: this reference is a capture, not the primitive.
            if (self.isNameShadowed(name)) return true;
            // A built-in, or a name reserved for a later top-level define, is a
            // global reference — not a free variable. The reserved case is what
            // lets a forward mutual-recursion call compile natively (#1499).
            if (self.isKnownOrReservedGlobal(name)) return false;
            return true;
        },
        .call => {
            if (nodeHasFreeVars(self, node.data.call.operator, params)) return true;
            for (node.data.call.args) |arg| {
                if (nodeHasFreeVars(self, arg, params)) return true;
            }
            return false;
        },
        .@"if" => {
            if (nodeHasFreeVars(self, node.data.@"if".test_expr, params)) return true;
            if (nodeHasFreeVars(self, node.data.@"if".consequent, params)) return true;
            if (node.data.@"if".alternate) |alt| {
                if (nodeHasFreeVars(self, alt, params)) return true;
            }
            return false;
        },
        .begin => return hasFreeVars(self, node.data.begin, params),
        .and_form => return hasFreeVars(self, node.data.and_form, params),
        .or_form => return hasFreeVars(self, node.data.or_form, params),
        .when_form => {
            if (nodeHasFreeVars(self, node.data.when_form.test_expr, params)) return true;
            return hasFreeVars(self, node.data.when_form.body, params);
        },
        .unless_form => {
            if (nodeHasFreeVars(self, node.data.unless_form.test_expr, params)) return true;
            return hasFreeVars(self, node.data.unless_form.body, params);
        },
        .set_form => {
            // The target and value are raw S-exprs; walk them with binder
            // scoping. A set! of a captured variable is a genuine free
            // reference — the enclosing frame boxes such variables so the
            // closure tier can capture the box pointer (#1497).
            if (sexprHasFreeVars(self, node.data.set_form.name, params)) return true;
            return sexprHasFreeVars(self, node.data.set_form.value, params);
        },
        // An internal define introduces a binding that the native lambda-body
        // emitter cannot install (it has no locals map), so it would leak to a
        // global. Disqualify and fall back to the interpreter.
        .define => return true,
        .constant => return false,
        // let/let* and nested lambdas keep their contents as a raw
        // S-expression, so references hidden inside them are invisible to
        // the node-level cases above. Walk the raw forms with proper binder
        // scoping (#1407, #1410).
        .let_form => return letSexprHasFreeVars(self, node.data.let_form.args, false, params),
        .let_star => return letSexprHasFreeVars(self, node.data.let_star.args, true, params),
        .lambda => return lambdaSexprHasFreeVars(self, node.data.lambda.args, params),
        // cond/case/do keep their clauses as a raw S-expression that the
        // backend now lowers natively (#1496); scope them like let/lambda so a
        // capture hidden in a clause is seen. Other sexpr forms are rejected
        // upstream and never reach a native body, so they report none.
        .sexpr_form => switch (node.data.sexpr_form.form) {
            .cond, .case_form, .do_form => return sexprFormHasFreeVars(self, node.data.sexpr_form.form, node.data.sexpr_form.args, params),
            else => return false,
        },
        .passthrough => return false,
        .letrec, .letrec_star => return false,
    }
}

// Walk a raw S-expression (a set! target or value) with binder scoping,
// reporting whether it references any free variable. Delegates to the shared
// FreeNameWalk so nested let/lambda binders are handled correctly (#1497).
fn sexprHasFreeVars(self: *LLVMEmitter, expr: types.Value, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkSexpr(&w, expr);
    return w.found or w.inexact;
}

fn collectSexprFreeVars(self: *LLVMEmitter, expr: types.Value, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkSexpr(&w, expr);
    return !w.inexact;
}

// Both collectors return false when the analysis could not stay exact (an
// allocation failed, or a let walk met a form it cannot scope). Callers must
// then reject native closure compilation — emitting with an incomplete
// free-variable set would leave the missed name to resolve as a global.
pub fn collectFreeVars(self: *LLVMEmitter, nodes: []const *ir.Node, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    for (nodes) |node| {
        if (!collectNodeFreeVars(self, node, params, list)) return false;
    }
    return true;
}

fn collectNodeFreeVars(self: *LLVMEmitter, node: *const ir.Node, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    switch (node.tag) {
        .global_ref => {
            if (!types.isSymbol(node.data.global_ref)) return true;
            const name = types.symbolName(node.data.global_ref);
            for (params) |p| {
                if (std.mem.eql(u8, name, p)) return true;
            }
            // A shadowed known global is a capture; only an unshadowed one
            // may be skipped as a genuine global reference (incl. a name
            // reserved for a later top-level define, #1499).
            if (self.isKnownOrReservedGlobal(name) and !self.isNameShadowed(name)) return true;
            for (list.items) |existing| {
                if (std.mem.eql(u8, name, existing)) return true;
            }
            list.append(self.allocator(), name) catch return false;
            return true;
        },
        .call => {
            if (!collectNodeFreeVars(self, node.data.call.operator, params, list)) return false;
            for (node.data.call.args) |arg| {
                if (!collectNodeFreeVars(self, arg, params, list)) return false;
            }
            return true;
        },
        .@"if" => {
            if (!collectNodeFreeVars(self, node.data.@"if".test_expr, params, list)) return false;
            if (!collectNodeFreeVars(self, node.data.@"if".consequent, params, list)) return false;
            if (node.data.@"if".alternate) |alt| {
                if (!collectNodeFreeVars(self, alt, params, list)) return false;
            }
            return true;
        },
        .begin => return collectFreeVars(self, node.data.begin, params, list),
        .and_form => return collectFreeVars(self, node.data.and_form, params, list),
        .or_form => return collectFreeVars(self, node.data.or_form, params, list),
        .when_form => {
            if (!collectNodeFreeVars(self, node.data.when_form.test_expr, params, list)) return false;
            return collectFreeVars(self, node.data.when_form.body, params, list);
        },
        .unless_form => {
            if (!collectNodeFreeVars(self, node.data.unless_form.test_expr, params, list)) return false;
            return collectFreeVars(self, node.data.unless_form.body, params, list);
        },
        // See nodeHasFreeVars: let/let* and nested lambda contents are raw
        // S-expressions and must be walked with binder scoping, or captures
        // hidden inside them are silently compiled as global lookups
        // (#1407, #1410).
        .let_form => return collectLetSexprFreeVars(self, node.data.let_form.args, false, params, list),
        .let_star => return collectLetSexprFreeVars(self, node.data.let_star.args, true, params, list),
        .lambda => return collectLambdaSexprFreeVars(self, node.data.lambda.args, params, list),
        // A set! of a captured variable must be captured too, or a closure
        // that only writes (never reads) the binding would miss it (#1497).
        .set_form => {
            if (!collectSexprFreeVars(self, node.data.set_form.name, params, list)) return false;
            return collectSexprFreeVars(self, node.data.set_form.value, params, list);
        },
        // cond/case/do are lowered natively (#1496): collect captures hidden in
        // their clauses so a closure over such a variable gets its upvalue.
        // Other sexpr forms never reach a native body (rejected upstream).
        .sexpr_form => switch (node.data.sexpr_form.form) {
            .cond, .case_form, .do_form => return collectSexprFormFreeVars(self, node.data.sexpr_form.form, node.data.sexpr_form.args, params, list),
            else => return true,
        },
        .constant, .define, .passthrough => return true,
        .letrec, .letrec_star => return true,
    }
}

// --- Scope-aware free-name walk over raw let/let*/lambda forms (#1407, #1410) ---
//
// The IR keeps let/let* contents (ir.LetData.args) and lambda contents
// (ir.LambdaData.args) as raw S-expressions, so the node-level free-variable
// analysis cannot see references inside them. This walk descends into the
// raw form tracking binder scopes (let binders, nested lambda formals) and
// reports every referenced name that is neither bound nor a known global —
// the same rule the .global_ref arms apply.
// `inexact` is set when the walk meets something it cannot scope precisely
// (internal define, an eval-fallback form, malformed bindings, overflow);
// callers must then treat the analysis as failed and refuse to compile the
// enclosing lambda natively.

const FreeNameWalk = struct {
    emitter: *LLVMEmitter,
    params: []const []const u8,
    // Names bound by let/lambda binders currently in scope; grows on the arena.
    // A scope save/restore uses bound.items.len + shrinkRetainingCapacity.
    bound: std.ArrayList([]const u8) = .empty,
    // When non-null, free names are appended here, deduplicated.
    buf: ?*std.ArrayList([]const u8) = null,
    found: bool = false,
    inexact: bool = false,

    fn pushBound(w: *FreeNameWalk, name: []const u8) void {
        w.bound.append(w.emitter.allocator(), name) catch {
            w.inexact = true;
        };
    }

    fn noteRef(w: *FreeNameWalk, name: []const u8) void {
        for (w.params) |p| {
            if (std.mem.eql(u8, name, p)) return;
        }
        for (w.bound.items) |b| {
            if (std.mem.eql(u8, name, b)) return;
        }
        // A shadowed known global is a capture; only an unshadowed one is a
        // genuine global reference (see the section comment above), including a
        // name reserved for a later top-level define (#1499).
        if (w.emitter.isKnownOrReservedGlobal(name) and !w.emitter.isNameShadowed(name)) return;
        w.found = true;
        if (w.buf) |buf| {
            for (buf.items) |existing| {
                if (std.mem.eql(u8, name, existing)) return;
            }
            buf.append(w.emitter.allocator(), name) catch {
                w.inexact = true;
            };
        }
    }
};

fn letSexprHasFreeVars(self: *LLVMEmitter, args: Value, sequential: bool, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkLetSexpr(&w, args, sequential);
    return w.found or w.inexact;
}

fn collectLetSexprFreeVars(self: *LLVMEmitter, args: Value, sequential: bool, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkLetSexpr(&w, args, sequential);
    return !w.inexact;
}

// args is the raw `(formals body ...)` tail of a nested lambda IR node
// (ir.LambdaData.args), the same shape walkLambdaSexpr consumes.
fn lambdaSexprHasFreeVars(self: *LLVMEmitter, args: Value, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkLambdaSexpr(&w, args);
    return w.found or w.inexact;
}

fn collectLambdaSexprFreeVars(self: *LLVMEmitter, args: Value, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkLambdaSexpr(&w, args);
    return !w.inexact;
}

// args is the raw form tail (ir.SexprFormData.args) of a natively lowered
// cond/case/do (#1496). Walks it with the same binder scoping as let/lambda.
fn sexprFormHasFreeVars(self: *LLVMEmitter, form: ir.FormKind, args: Value, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkSexprForm(&w, form, args);
    return w.found or w.inexact;
}

fn collectSexprFormFreeVars(self: *LLVMEmitter, form: ir.FormKind, args: Value, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkSexprForm(&w, form, args);
    return !w.inexact;
}

fn walkSexprForm(w: *FreeNameWalk, form: ir.FormKind, args: Value) void {
    switch (form) {
        .cond => walkCondSexpr(w, args),
        .case_form => walkCaseSexpr(w, args),
        .do_form => walkDoSexpr(w, args),
        else => w.inexact = true,
    }
}

// args is the raw `(bindings body ...)` tail of a let/let* form. For let the
// init expressions see only the enclosing scope; for let* each init also sees
// the binders before it. The binders are in scope for the body either way.
fn walkLetSexpr(w: *FreeNameWalk, args: Value, sequential: bool) void {
    if (!types.isPair(args)) {
        w.inexact = true;
        return;
    }
    const bindings = types.car(args);
    const saved = w.bound.items.len;
    defer w.bound.shrinkRetainingCapacity(saved);

    var blist = bindings;
    while (types.isPair(blist)) : (blist = types.cdr(blist)) {
        const binding = types.car(blist);
        if (!types.isPair(binding)) {
            w.inexact = true;
            return;
        }
        const var_sym = types.car(binding);
        const init_list = types.cdr(binding);
        if (!types.isSymbol(var_sym) or !types.isPair(init_list)) {
            w.inexact = true;
            return;
        }
        walkSexpr(w, types.car(init_list));
        if (sequential) w.pushBound(types.symbolName(var_sym));
    }
    if (blist != types.NIL) {
        w.inexact = true;
        return;
    }
    if (!sequential) {
        blist = bindings;
        while (types.isPair(blist)) : (blist = types.cdr(blist)) {
            w.pushBound(types.symbolName(types.car(types.car(blist))));
        }
    }
    var body_expr = types.cdr(args);
    while (types.isPair(body_expr)) : (body_expr = types.cdr(body_expr)) {
        walkSexpr(w, types.car(body_expr));
    }
}

// rest is the raw `(formals body ...)` tail of a lambda form.
fn walkLambdaSexpr(w: *FreeNameWalk, rest: Value) void {
    if (!types.isPair(rest)) {
        w.inexact = true;
        return;
    }
    const saved = w.bound.items.len;
    defer w.bound.shrinkRetainingCapacity(saved);

    var f = types.car(rest);
    while (types.isPair(f)) : (f = types.cdr(f)) {
        const p = types.car(f);
        if (!types.isSymbol(p)) {
            w.inexact = true;
            return;
        }
        w.pushBound(types.symbolName(p));
    }
    // Rest parameter: dotted tail, or bare-symbol formals.
    if (f != types.NIL) {
        if (!types.isSymbol(f)) {
            w.inexact = true;
            return;
        }
        w.pushBound(types.symbolName(f));
    }
    var body_expr = types.cdr(rest);
    while (types.isPair(body_expr)) : (body_expr = types.cdr(body_expr)) {
        walkSexpr(w, types.car(body_expr));
    }
}

// True if `v` is the symbol `name` — cond/case clause markers (else, =>) that
// the walks below must skip rather than treat as variable references.
fn sexprSymEql(v: Value, name: []const u8) bool {
    return types.isSymbol(v) and std.mem.eql(u8, types.symbolName(v), name);
}

// clauses is the raw tail of a `cond`: each clause is `(test body ...)`, with a
// leading `else` or `=> proc` handled structurally (the markers are not refs).
fn walkCondSexpr(w: *FreeNameWalk, clauses: Value) void {
    var cl = clauses;
    while (types.isPair(cl)) : (cl = types.cdr(cl)) {
        const clause = types.car(cl);
        if (!types.isPair(clause)) {
            w.inexact = true;
            return;
        }
        const test_expr = types.car(clause);
        if (!sexprSymEql(test_expr, "else")) walkSexpr(w, test_expr);
        var body = types.cdr(clause);
        if (types.isPair(body) and sexprSymEql(types.car(body), "=>")) body = types.cdr(body);
        while (types.isPair(body)) : (body = types.cdr(body)) {
            walkSexpr(w, types.car(body));
        }
    }
}

// args is the raw tail of a `case`: `(key clause ...)`. The datum list in each
// clause is quoted data (never referenced); only the key and bodies are refs.
fn walkCaseSexpr(w: *FreeNameWalk, args: Value) void {
    if (!types.isPair(args)) {
        w.inexact = true;
        return;
    }
    walkSexpr(w, types.car(args)); // key
    var cl = types.cdr(args);
    while (types.isPair(cl)) : (cl = types.cdr(cl)) {
        const clause = types.car(cl);
        if (!types.isPair(clause)) {
            w.inexact = true;
            return;
        }
        var body = types.cdr(clause); // car is the (literal) datum list
        if (types.isPair(body) and sexprSymEql(types.car(body), "=>")) body = types.cdr(body);
        while (types.isPair(body)) : (body = types.cdr(body)) {
            walkSexpr(w, types.car(body));
        }
    }
}

// args is the raw tail of a `do`: `(specs (test result ...) command ...)`. The
// loop variables are bound for the steps, test, results, and commands, but the
// init expressions are evaluated in the enclosing scope.
fn walkDoSexpr(w: *FreeNameWalk, args: Value) void {
    if (!types.isPair(args)) {
        w.inexact = true;
        return;
    }
    const specs = types.car(args);
    const rest = types.cdr(args);
    if (!types.isPair(rest) or !types.isPair(types.car(rest))) {
        w.inexact = true;
        return;
    }
    const test_clause = types.car(rest);
    const commands = types.cdr(rest);

    const saved = w.bound.items.len;
    defer w.bound.shrinkRetainingCapacity(saved);

    // Inits are evaluated before the loop variables are bound.
    var s = specs;
    while (types.isPair(s)) : (s = types.cdr(s)) {
        const spec = types.car(s);
        if (!types.isPair(spec) or !types.isSymbol(types.car(spec)) or !types.isPair(types.cdr(spec))) {
            w.inexact = true;
            return;
        }
        walkSexpr(w, types.car(types.cdr(spec)));
    }
    if (s != types.NIL) {
        w.inexact = true;
        return;
    }
    // Bind the loop variables for the rest of the form.
    s = specs;
    while (types.isPair(s)) : (s = types.cdr(s)) {
        w.pushBound(types.symbolName(types.car(types.car(s))));
    }
    // Steps see the loop bindings.
    s = specs;
    while (types.isPair(s)) : (s = types.cdr(s)) {
        const step_rest = types.cdr(types.cdr(types.car(s)));
        if (types.isPair(step_rest)) walkSexpr(w, types.car(step_rest));
    }
    walkSexpr(w, types.car(test_clause));
    var r = types.cdr(test_clause);
    while (types.isPair(r)) : (r = types.cdr(r)) walkSexpr(w, types.car(r));
    var c = commands;
    while (types.isPair(c)) : (c = types.cdr(c)) walkSexpr(w, types.car(c));
}

fn walkSexpr(w: *FreeNameWalk, expr: Value) void {
    if (w.inexact) return;
    if (types.isSymbol(expr)) {
        w.noteRef(types.symbolName(expr));
        return;
    }
    if (!types.isPair(expr)) return;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (std.mem.eql(u8, name, "quote")) return;
        if (std.mem.eql(u8, name, "lambda")) return walkLambdaSexpr(w, types.cdr(expr));
        const is_let = std.mem.eql(u8, name, "let");
        if (is_let or std.mem.eql(u8, name, "let*")) {
            const rest = types.cdr(expr);
            // Named let is rejected upstream by sexprNeedsEvalFallback; if
            // one shows up anyway, give up rather than mis-scope its binders.
            if (is_let and types.isPair(rest) and types.isSymbol(types.car(rest))) {
                w.inexact = true;
                return;
            }
            return walkLetSexpr(w, rest, !is_let);
        }
        // cond/case/do are natively lowered (#1496); scope their clauses so a
        // capture inside one is seen. (They are no longer isEvalFallbackForm.)
        if (std.mem.eql(u8, name, "cond")) return walkCondSexpr(w, types.cdr(expr));
        if (std.mem.eql(u8, name, "case")) return walkCaseSexpr(w, types.cdr(expr));
        if (std.mem.eql(u8, name, "do")) return walkDoSexpr(w, types.cdr(expr));
        // An internal define introduces a binding this walk does not model.
        if (std.mem.eql(u8, name, "define")) {
            w.inexact = true;
            return;
        }
        // Forms the backend sends to eval fallback (cond, do, letrec, ...)
        // are rejected upstream before this analysis runs; if one appears
        // anyway, its binder structure is unknown — give up.
        if (isEvalFallbackForm(name)) {
            w.inexact = true;
            return;
        }
    }
    // Everything else (calls, if/begin/and/or/when/unless/set!, ...) is a
    // plain expression tree: every symbol in it is a reference, and keyword
    // heads are filtered out by isKnownGlobal inside noteRef.
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        walkSexpr(w, types.car(cur));
    }
}
