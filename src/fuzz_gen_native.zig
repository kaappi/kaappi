//! Native-compilable-subset program generator for the bytecode-VM vs
//! LLVM-native-backend differential oracle (fuzzing Tier 3, issue #1395).
//!
//! The native backend compiles part of the language natively and falls back
//! to `kaappi_eval` (the interpreter) for the rest, so an unrestricted
//! generated program would make the differential harness compare the VM
//! mostly against itself. This generator emits only forms the backend
//! compiles natively (llvm_emit.zig / llvm_emit_lambda.zig):
//!
//! - primitive calls (2-arg `+ - * < = cons car cdr null?` are inline
//!   fast paths; the rest go through the native `kaappi_call_scheme`
//!   bridge with its own argument-rooting codegen)
//! - if / and / or / when / unless / begin, let / let*
//! - top-level `(define name <literal|lambda>)` and `(define (f ...) body)`
//!   including dotted (variadic) parameter lists, self-tail-calls
//!   (compiled as loops), and non-tail self-recursion
//! - set! (native everywhere, BUT a compound set! value is native only
//!   inside a lexical scope: at top level emitScopedValue routes compound
//!   values through kaappi_eval, so top-level set! uses literal values and
//!   computed mutation happens inside let bodies)
//!
//! Structural rules the backend imposes — violating one silently drops the
//! surrounding form to the interpreter, degrading the oracle to VM-vs-VM:
//!
//! - Function/lambda bodies may reference only their own parameters, their
//!   own name (recursion), and the primitive names in `ir.isKnownGlobal`;
//!   any other free variable makes tryCompileDefineFunction reject the
//!   whole function (hasFreeVars). Outer bindings are hidden while a body
//!   is generated.
//! - Global defines: a compound non-lambda init expression goes through
//!   kaappi_eval (emitDefine), so globals are initialized with literals
//!   and mutated from inside let bodies.
//! - No lambda expressions inside let forms: emitLet falls back to eval
//!   when a body lambda captures a let binding (#827), so the generator
//!   avoids lambdas there entirely. Inline lambdas may nest and capture
//!   int parameters from ANY enclosing function/lambda level (#1420):
//!   since #1410 the closure tiers chain captures through nested closures
//!   (an inner lambda reaches an outer-outer parameter via the enclosing
//!   closure's upvalue array), so chained shapes stay fully native.
//! - Variadic lambdas compile natively only with at least one fixed
//!   parameter (`(lambda (a . rest) ...)`) and only in define position.
//!   Inline variadic lambdas are still emitted occasionally (#1420): no
//!   closure tier accepts a rest parameter, so each one exercises the
//!   emitLambdaViaEval fallback that republishes the enclosing frame —
//!   params, rest parameter, upvalues — as globals (#1410), at the cost
//!   of exactly one kaappi_eval (the tests_native.zig gate counts them).
//!   Their bodies suppress nested lambdas: the body is eval'd as one
//!   source string, so a lambda inside it would be interpreted without
//!   ever reaching the emitter, breaking the gate's accounting.
//! - No set! inside inline-call argument subtrees in function bodies:
//!   native closures snapshot captured parameters by value at creation
//!   (and eval fallbacks read globals republished at that point), while
//!   the VM's closures capture locations — a set! of a captured param in
//!   a sibling argument runs between capture and call and diverges
//!   (#1422).
//! - Cross-function calls appear only in top-level expressions and let
//!   bodies: `f0` inside `f1`'s body would be a free variable (see above).
//!   Inside function bodies this also keeps eval-fallback republication
//!   sound: nothing can re-enter another function (and re-publish its
//!   frame) between a fallback's define-globals and its call.
//!
//! Output discipline: `kaappi f.scm` echoes every non-void top-level value
//! to stdout but a native binary echoes nothing, so EVERY top-level form
//! here is void-valued (define / set! / when / unless / if-with-statement-
//! arms / begin / let-ending-in-set! / write / newline) and all observable
//! output is explicit: `(write ...)` of the final expressions plus of every
//! non-procedure global (procedure values are never written — they print
//! as `#<procedure name>` in the VM but `#<procedure>` natively, a
//! representation difference by design, not a bug).
//!
//! Shares the Smith/PRNG Chooser, scope tracking, and byte-budget
//! infrastructure with the full generator (fuzz_gen.zig).

const std = @import("std");
const gen_mod = @import("fuzz_gen.zig");

const Gen = gen_mod.Gen;
const Error = gen_mod.Error;
const Cands = gen_mod.Cands;
const Binding = gen_mod.Binding;

const max_depth: u32 = 5;

// Primitive vocabulary. Everything here is in ir.isKnownGlobal's primitive
// list, so calls in function bodies do not count as free variables.
const arith_ops = [_][]const u8{ "+", "-", "*", "min", "max" };
const div_ops = [_][]const u8{ "quotient", "remainder", "modulo" };
const cmp_ops = [_][]const u8{ "<", "<=", "=", ">", ">=" };
const rec_ops = [_][]const u8{ "+", "*", "max" };

/// Region context threaded through the expression recursion.
const Ctx = struct {
    /// >0 while inside a natively compiled function/lambda body. Governs
    /// what an inline lambda may capture: at depth 0 its body must be
    /// closed (pure native closure tier); deeper, it may reference int
    /// parameters of any enclosing function/lambda (upvalue tier, chained
    /// through nested closures since #1410).
    fn_depth: u8 = 0,
    /// True inside let forms, where emitting a lambda would push the
    /// enclosing let off the native path (#827 capture check), and inside
    /// variadic inline-lambda bodies, which are eval'd as one source
    /// string — a lambda nested there would be interpreted invisibly to
    /// the emitter and break the gate's eval accounting.
    no_lambda: bool = false,
    /// True inside inline-lambda bodies: the capturing closure tier rejects
    /// bodies containing set! ANYWHERE — even of a let-local — via the
    /// blanket syntactic scan sexprContainsSetOrDefine (#819), so a set!
    /// there would drop the lambda to emitLambdaViaEval. (Define-position
    /// lambdas go through tryCompileDefineFunction, whose free-var check
    /// does not descend into let forms, so set! inside their lets is fine.)
    /// Also true inside inline-call ARGUMENT subtrees in function bodies:
    /// arguments run between closure creation (which snapshots captured
    /// params by value) and the call, so a set! of a captured param there
    /// diverges from the VM's location-based capture (#1422).
    /// Note: set! of a define-position function's own params is prevented
    /// separately by pushing those params with settable=false — the #1422
    /// guard rejects functions whose params are both set! and captured.
    no_set: bool = false,
};

/// Shapes a let-bound value can take in native mode. Local mirror of the
/// relevant fuzz_gen Kind cases so binding registration can be deferred
/// (plain `let` inits must not see one another).
const LetKind = union(enum) { int, list: u16, vec: u16 };

pub fn genProgram(g: *Gen) Error!void {
    var ctx: Ctx = .{};
    const nglobals = g.ch.range(.count, 0, gen_mod.global_names.len);
    for (0..nglobals) |_| try genGlobalDefine(g, &ctx);
    const nfns = g.ch.range(.count, 0, gen_mod.fn_names.len);
    for (0..nfns) |_| try genFnDefine(g, &ctx);

    // Statements mutate globals (directly with literal values, or with
    // computed values from inside let scopes). Only meaningful when a
    // settable global exists.
    if (g.hasVar(gen_mod.bindIsSettableAtom)) {
        const nstmts = g.ch.range(.count, 0, 2);
        for (0..nstmts) |_| {
            try genStmt(g, &ctx, g.ch.range(.depth_pick, 1, 3), false);
            try g.emit("\n");
        }
    }

    const nwrites = g.ch.range(.count, 1, 3);
    for (0..nwrites) |_| {
        try g.emit("(write ");
        const depth = g.ch.range(.depth_pick, 2, max_depth);
        if (g.ch.chance(.coin, 1, 5)) {
            try genBool(g, &ctx, depth);
        } else {
            try genInt(g, &ctx, depth);
        }
        try g.emit(")\n(newline)\n");
    }

    // Echo every non-procedure global so a wrong value stored by a set!
    // statement is observable even when no write expression touched it
    // (mirrors the widened observable of the opt-vs-no-opt oracle). Only
    // top-level bindings remain in scope here.
    for (g.scope.items) |b| {
        if (b.kind != .int and b.kind != .boolean) continue;
        try g.emitf("(write {s})\n(newline)\n", .{b.name});
    }
}

// ---------------------------------------------------------------------------
// Top-level definitions
// ---------------------------------------------------------------------------

fn genGlobalDefine(g: *Gen, ctx: *Ctx) Error!void {
    const name = gen_mod.global_names[g.global_count];
    g.global_count += 1;
    const GKind = enum { int_lit, bool_lit, lambda };
    var c: Cands(GKind) = .{};
    c.add(.int_lit, 5);
    c.add(.bool_lit, 2);
    c.add(.lambda, 3);
    switch (c.pick(g.ch)) {
        .int_lit => {
            try g.emitf("(define {s} {d})\n", .{ name, litInt(g) });
            try g.pushBinding(name, .int);
        },
        .bool_lit => {
            try g.emitf("(define {s} {s})\n", .{ name, boolLit(g) });
            try g.pushBinding(name, .boolean);
        },
        .lambda => {
            const variadic = g.ch.chance(.coin, 1, 4);
            const arity: u8 = @intCast(g.ch.range(.arity, if (variadic) 1 else 0, 3));
            try g.emitf("(define {s} ", .{name});
            try genLambda(g, ctx, arity, variadic);
            try g.emit(")\n");
            try g.pushBinding(name, .{ .proc = .{ .arity = arity, .variadic = variadic } });
        },
    }
}

/// `(lambda (p... [. rest]) <int body>)` in define position, body generated
/// under a hidden outer scope (only its own parameters are referenceable).
fn genLambda(g: *Gen, ctx: *Ctx, arity: u8, variadic: bool) Error!void {
    var nb: [4][]const u8 = undefined;
    const params = g.pickNames(arity, &nb);
    try g.emit("(lambda (");
    var saved = try enterBody(g, false);
    defer leaveBody(g, &saved);
    for (params, 0..) |p, i| {
        if (i > 0) try g.emit(" ");
        try g.emit(p);
        try g.scope.append(g.gpa, .{ .name = p, .kind = .int, .settable = false });
    }
    if (variadic) {
        try g.emit(" . rest");
        try g.pushBinding("rest", .{ .list = .{ .len = .unknown, .mut = .all, .ints = true } });
    }
    try g.emit(") ");
    var body_ctx: Ctx = .{ .fn_depth = ctx.fn_depth + 1 };
    try genFnBody(g, &body_ctx, variadic, g.ch.range(.depth_pick, 2, 4));
    try g.emit(")");
}

/// Function/lambda body: an int expression, with an optional null?-guarded
/// use of the rest list when variadic (rest has no static length, so access
/// must be guarded — and this exercises the native rest-list builder loop).
fn genFnBody(g: *Gen, ctx: *Ctx, variadic: bool, depth: u32) Error!void {
    if (variadic and g.ch.chance(.coin, 1, 2)) {
        try g.emit("(if (null? rest) ");
        try genInt(g, ctx, depth -| 1);
        try g.emit(" (+ (car rest) ");
        try genInt(g, ctx, depth -| 1);
        try g.emit("))");
    } else {
        try genInt(g, ctx, depth);
    }
}

fn genFnDefine(g: *Gen, ctx: *Ctx) Error!void {
    _ = ctx;
    const name = gen_mod.fn_names[g.fn_count];
    g.fn_count += 1;
    var nb: [4][]const u8 = undefined;
    switch (g.ch.range(.shape, 0, 2)) {
        0 => { // plain function, optionally variadic
            const variadic = g.ch.chance(.coin, 1, 4);
            const arity: u8 = @intCast(g.ch.range(.arity, if (variadic) 1 else 0, 3));
            const params = g.pickNames(arity, &nb);
            try g.emitf("(define ({s}", .{name});
            var saved = try enterBody(g, false);
            for (params) |p| {
                try g.emitf(" {s}", .{p});
                // Non-settable: inline lambdas in the body may capture these
                // params, and set! of a captured param triggers the #1422
                // guard, rejecting the whole function for native compilation.
                try g.scope.append(g.gpa, .{ .name = p, .kind = .int, .settable = false });
            }
            if (variadic) {
                try g.emit(" . rest");
                try g.pushBinding("rest", .{ .list = .{ .len = .unknown, .mut = .all, .ints = true } });
            }
            try g.emit(") ");
            var body_ctx: Ctx = .{ .fn_depth = 1 };
            try genFnBody(g, &body_ctx, variadic, 3);
            try g.emit(")\n");
            leaveBody(g, &saved);
            try g.pushBinding(name, .{ .proc = .{ .arity = arity, .variadic = variadic } });
        },
        1 => { // self-tail-recursive countdown: compiled as a native loop
            const params = g.pickNames(2, &nb);
            try g.emitf("(define ({s} {s} {s}) (if (<= {s} 0) {s} ({s} (- {s} 1) (modulo ", .{
                name, params[0], params[1], params[0], params[1], name, params[0],
            });
            var saved = try enterBody(g, false);
            try g.scope.append(g.gpa, .{ .name = params[0], .kind = .int, .settable = false });
            try g.scope.append(g.gpa, .{ .name = params[1], .kind = .int, .settable = false });
            var body_ctx: Ctx = .{ .fn_depth = 1 };
            try genInt(g, &body_ctx, 3);
            leaveBody(g, &saved);
            try g.emitf(" {d}))))\n", .{gen_mod.acc_modulus});
            try g.pushBinding(name, .{ .proc = .{ .arity = 2, .bounded_first = true } });
        },
        else => { // non-tail self-recursion: native call-stack frames
            const params = g.pickNames(1, &nb);
            const op = rec_ops[g.ch.index(.op_pick, rec_ops.len)];
            try g.emitf("(define ({s} {s}) (if (<= {s} 0) ", .{ name, params[0], params[0] });
            var saved = try enterBody(g, false);
            try g.scope.append(g.gpa, .{ .name = params[0], .kind = .int, .settable = false });
            var body_ctx: Ctx = .{ .fn_depth = 1 };
            try genInt(g, &body_ctx, 2);
            try g.emitf(" ({s} ", .{op});
            try genInt(g, &body_ctx, 2);
            leaveBody(g, &saved);
            try g.emitf(" ({s} (- {s} 1)))))\n", .{ name, params[0] });
            try g.pushBinding(name, .{ .proc = .{ .arity = 1, .bounded_first = true } });
        },
    }
}

// ---------------------------------------------------------------------------
// Scope hiding for function/lambda bodies
// ---------------------------------------------------------------------------

/// Swap in a fresh scope for a function/lambda body. With `keep_ints`, int
/// bindings stay visible (an inline lambda inside a function body may
/// capture int parameters of any enclosing level as native closure
/// upvalues, chained since #1410; a list-typed rest parameter must NOT
/// leak in — the closure tiers only capture fixed parameters and chained
/// upvalues, so a rest reference would reject them and take an eval
/// fallback the tests_native.zig gate does not account for, and nested
/// two or more levels down it would read an unbound global at run time).
fn enterBody(g: *Gen, keep_ints: bool) Error!std.ArrayList(Binding) {
    const saved = g.scope;
    g.scope = .empty;
    if (keep_ints) {
        for (saved.items) |b| {
            if (b.kind == .int) g.scope.append(g.gpa, b) catch return error.OutOfMemory;
        }
    }
    return saved;
}

fn leaveBody(g: *Gen, saved: *std.ArrayList(Binding)) void {
    g.scope.deinit(g.gpa);
    g.scope = saved.*;
}

// ---------------------------------------------------------------------------
// Integer expressions
// ---------------------------------------------------------------------------

fn litInt(g: *Gen) i64 {
    return @as(i64, g.ch.range(.lit_pick, 0, 200)) - 100;
}

fn boolLit(g: *Gen) []const u8 {
    return if (g.ch.chance(.coin, 1, 2)) "#t" else "#f";
}

const IntOp = enum {
    lit,
    ref,
    arith,
    abs_op,
    divmod,
    if_form,
    and_or,
    let_form,
    begin_form,
    call_proc,
    inline_call,
    car_op,
    cadr_op,
    list_len,
    list_ref_op,
    vec_ref,
};

fn genInt(g: *Gen, ctx: *Ctx, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    var c: Cands(IntOp) = .{};
    c.add(.lit, 5);
    if (g.hasVar(gen_mod.bindIsInt)) c.add(.ref, 6);
    if (depth > 0) {
        c.add(.arith, 8);
        c.add(.abs_op, 1);
        c.add(.divmod, 3);
        c.add(.if_form, 5);
        c.add(.and_or, 2);
        c.add(.let_form, 6);
        c.add(.begin_form, 2);
        if (g.hasVar(gen_mod.bindIsProc)) c.add(.call_proc, 6);
        if (!ctx.no_lambda) c.add(.inline_call, 3);
        if (g.hasVar(gen_mod.bindIsListIntsExactNonEmpty)) {
            c.add(.car_op, 2);
            c.add(.list_len, 1);
            c.add(.list_ref_op, 2);
        }
        if (g.cdrVarAvail(.{ .ints = true, .non_empty = true })) c.add(.cadr_op, 1);
        if (g.hasVar(gen_mod.bindIsIntVec)) c.add(.vec_ref, 3);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => try g.emitf("{d}", .{litInt(g)}),
        .ref => try g.emit(g.pickVar(gen_mod.bindIsInt).?.name),
        .arith => {
            const op = arith_ops[g.ch.index(.op_pick, arith_ops.len)];
            const nargs = g.ch.range(.nargs, 2, 3);
            try g.emitf("({s}", .{op});
            for (0..nargs) |_| {
                try g.emit(" ");
                try genInt(g, ctx, d);
            }
            try g.emit(")");
        },
        .abs_op => {
            try g.emit("(abs ");
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .divmod => {
            const op = div_ops[g.ch.index(.op_pick, div_ops.len)];
            var divisor: i32 = @intCast(g.ch.range(.lit_pick, 1, 12));
            if (g.ch.chance(.coin, 1, 4)) divisor = -divisor;
            try g.emitf("({s} ", .{op});
            try genInt(g, ctx, d);
            try g.emitf(" {d})", .{divisor});
        },
        .if_form => {
            try g.emit("(if ");
            try genTest(g, ctx, d);
            try g.emit(" ");
            try genInt(g, ctx, d);
            try g.emit(" ");
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .and_or => {
            // All-integer arguments (never #f): both forms yield an integer
            // while exercising the native short-circuit emission.
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and" else "(or");
            const nargs = g.ch.range(.nargs, 2, 3);
            for (0..nargs) |_| {
                try g.emit(" ");
                try genInt(g, ctx, d);
            }
            try g.emit(")");
        },
        .let_form => try genLetInt(g, ctx, d),
        .begin_form => {
            try g.emit("(begin ");
            try genInt(g, ctx, d);
            try g.emit(" ");
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .call_proc => {
            const b = g.pickVar(gen_mod.bindIsProc).?;
            const info = b.kind.proc;
            var nargs: u32 = info.arity;
            if (info.variadic) nargs += g.ch.range(.nargs, 0, 2);
            try g.emitf("({s}", .{b.name});
            for (0..nargs) |i| {
                try g.emit(" ");
                if (i == 0 and info.bounded_first) {
                    try g.emitf("{d}", .{g.ch.range(.iters, 0, 12)});
                } else {
                    try genInt(g, ctx, d);
                }
            }
            try g.emit(")");
        },
        .inline_call => {
            // A variadic inline lambda can never be a native closure (no
            // tier accepts a rest parameter): it takes the emitLambdaViaEval
            // fallback, which first republishes the enclosing frame —
            // params, rest parameter, upvalues — as globals (#1410). Each
            // one costs exactly one kaappi_eval, counted by the
            // tests_native.zig gate.
            const variadic = g.ch.chance(.coin, 1, 5);
            const arity = g.ch.range(.arity, if (variadic) 1 else 0, 2);
            var nb: [4][]const u8 = undefined;
            const params = g.pickNames(arity, &nb);
            try g.emit("((lambda (");
            // At top level the body must be closed over its own params (pure
            // tier); inside a function body it may capture int parameters
            // from any enclosing level — the closure tiers chain such
            // captures through nested closures since #1410 (#1420).
            var saved = try enterBody(g, ctx.fn_depth > 0);
            for (params, 0..) |p, i| {
                if (i > 0) try g.emit(" ");
                try g.emit(p);
                try g.pushBinding(p, .int);
            }
            if (variadic) {
                try g.emit(" . rest");
                try g.pushBinding("rest", .{ .list = .{ .len = .unknown, .mut = .all, .ints = true } });
            }
            try g.emit(") ");
            // Variadic bodies are eval'd as one source string, so a lambda
            // nested inside one would never reach the emitter — suppress
            // nesting there to keep the gate's eval accounting exact.
            var body_ctx: Ctx = .{ .fn_depth = ctx.fn_depth + 1, .no_lambda = variadic, .no_set = true };
            try genFnBody(g, &body_ctx, variadic, d);
            try g.emit(")");
            leaveBody(g, &saved);
            // Arguments run between closure creation (captured params are
            // snapshotted by value, or republished as globals) and the call:
            // a set! of a captured param in an argument would be visible to
            // the VM's location-based capture but not to the snapshot, so
            // ban set! in argument subtrees whenever a capture is possible
            // (#1422). At top level the body is closed — nothing to capture.
            var arg_ctx = ctx.*;
            if (ctx.fn_depth > 0) arg_ctx.no_set = true;
            var nargs: u32 = arity;
            if (variadic) nargs += g.ch.range(.nargs, 0, 2);
            for (0..nargs) |_| {
                try g.emit(" ");
                try genInt(g, &arg_ctx, d);
            }
            try g.emit(")");
        },
        .car_op => {
            const b = g.pickVar(gen_mod.bindIsListIntsExactNonEmpty).?;
            try g.emitf("(car {s})", .{b.name});
        },
        .cadr_op => {
            const b = g.pickCdrVar(.{ .ints = true, .non_empty = true }).?;
            try g.emitf("(car (cdr {s}))", .{b.name});
        },
        .list_len => {
            const b = g.pickVar(gen_mod.bindIsListIntsExactNonEmpty).?;
            try g.emitf("(length {s})", .{b.name});
        },
        .list_ref_op => {
            const b = g.pickVar(gen_mod.bindIsListIntsExactNonEmpty).?;
            const len = b.kind.list.len.exactLen().?;
            try g.emitf("(list-ref {s} {d})", .{ b.name, g.ch.range(.idx_pick, 0, len - 1) });
        },
        .vec_ref => {
            const b = g.pickVar(gen_mod.bindIsIntVec).?;
            try g.emitf("(vector-ref {s} ", .{b.name});
            try genIndex(g, ctx, d, b.kind.vector.len);
            try g.emit(")");
        },
    }
}

/// In-range vector index: literal below `len` or `(modulo <int> len)`
/// (modulo is never negative for a positive modulus).
fn genIndex(g: *Gen, ctx: *Ctx, d: u32, len: u16) Error!void {
    if (g.ch.chance(.idx_kind, 2, 3)) {
        try g.emitf("{d}", .{g.ch.range(.idx_pick, 0, len - 1)});
    } else {
        try g.emit("(modulo ");
        try genInt(g, ctx, @min(d, 1));
        try g.emitf(" {d})", .{len});
    }
}

fn genLetInt(g: *Gen, ctx: *Ctx, d: u32) Error!void {
    const star = g.ch.chance(.coin, 1, 2);
    const n = g.ch.range(.count, 1, 3);
    var nb: [4][]const u8 = undefined;
    const names = g.pickNames(n, &nb);
    try g.emit(if (star) "(let* (" else "(let (");
    const mark = g.scope.items.len;
    var let_ctx: Ctx = .{ .fn_depth = ctx.fn_depth, .no_lambda = true, .no_set = ctx.no_set };
    var stash: [3]LetKind = undefined;
    for (0..n) |i| {
        try g.emitf("({s} ", .{names[i]});
        const lk = try genLetInit(g, &let_ctx, d);
        try g.emit(") ");
        // let: inits are evaluated in the outer scope, so bindings become
        // visible only after all of them; let*: immediately.
        stash[i] = lk;
        if (star) try pushLetBinding(g, names[i], lk);
    }
    if (!star) for (0..n) |i| try pushLetBinding(g, names[i], stash[i]);
    try g.emit(") ");
    if (g.ch.chance(.coin, 1, 2)) {
        try genStmt(g, &let_ctx, d, true);
        try g.emit(" ");
    }
    try genInt(g, &let_ctx, d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

/// A let-binding initializer. Lists and vectors live only as let locals in
/// native mode: their construction is native here (cons is an inline
/// primitive; list/vector/make-vector go through kaappi_call_scheme),
/// whereas a compound global define init would route through kaappi_eval.
fn genLetInit(g: *Gen, ctx: *Ctx, d: u32) Error!LetKind {
    const K = enum { int, list, vec };
    var c: Cands(K) = .{};
    c.add(.int, 6);
    if (d > 0) {
        c.add(.list, 2);
        c.add(.vec, 2);
    }
    switch (c.pick(g.ch)) {
        .int => {
            try genInt(g, ctx, d);
            return .int;
        },
        .list => {
            const len: u16 = @intCast(g.ch.range(.len_pick, 0, 4));
            if (g.ch.chance(.coin, 1, 2)) {
                try g.emit("(list");
                for (0..len) |_| {
                    try g.emit(" ");
                    try genInt(g, ctx, d -| 1);
                }
                try g.emit(")");
            } else {
                for (0..len) |_| {
                    try g.emit("(cons ");
                    try genInt(g, ctx, d -| 1);
                    try g.emit(" ");
                }
                try g.emit("'()");
                for (0..len) |_| try g.emit(")");
            }
            return .{ .list = len };
        },
        .vec => {
            const len: u16 = @intCast(g.ch.range(.len_pick, 1, 5));
            if (g.ch.chance(.coin, 1, 2)) {
                try g.emit("(vector");
                for (0..len) |_| {
                    try g.emit(" ");
                    try genInt(g, ctx, d -| 1);
                }
                try g.emit(")");
            } else {
                try g.emitf("(make-vector {d} ", .{len});
                try genInt(g, ctx, d -| 1);
                try g.emit(")");
            }
            return .{ .vec = len };
        },
    }
}

fn pushLetBinding(g: *Gen, name: []const u8, lk: LetKind) Error!void {
    switch (lk) {
        .int => try g.pushBinding(name, .int),
        .list => |len| try g.pushBinding(name, .{ .list = .{ .len = .{ .exact = len }, .mut = .all, .ints = true } }),
        .vec => |len| try g.pushBinding(name, .{ .vector = .{ .len = len, .boxed = false } }),
    }
}

// ---------------------------------------------------------------------------
// Booleans and tests
// ---------------------------------------------------------------------------

const BoolOp = enum { lit, ref, not_op, andor, cmp, zero_p, evenodd, null_p, pair_p };

fn genBool(g: *Gen, ctx: *Ctx, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    var c: Cands(BoolOp) = .{};
    c.add(.lit, 3);
    if (g.hasVar(gen_mod.bindIsBool)) c.add(.ref, 4);
    if (depth > 0) {
        c.add(.not_op, 2);
        c.add(.andor, 3);
        c.add(.cmp, 7);
        c.add(.zero_p, 2);
        c.add(.evenodd, 2);
        if (g.listVarAvail(.{})) {
            c.add(.null_p, 2);
            c.add(.pair_p, 1);
        }
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => try g.emit(boolLit(g)),
        .ref => try g.emit(g.pickVar(gen_mod.bindIsBool).?.name),
        .not_op => {
            try g.emit("(not ");
            try genTest(g, ctx, d);
            try g.emit(")");
        },
        .andor => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and " else "(or ");
            try genBool(g, ctx, d);
            try g.emit(" ");
            try genBool(g, ctx, d);
            try g.emit(")");
        },
        .cmp => {
            const op = cmp_ops[g.ch.index(.op_pick, cmp_ops.len)];
            try g.emitf("({s} ", .{op});
            try genInt(g, ctx, d);
            try g.emit(" ");
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .zero_p => {
            try g.emit("(zero? ");
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .evenodd => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(even? " else "(odd? ");
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .null_p => try g.emitf("(null? {s})", .{g.pickListVar(.{}).?.name}),
        .pair_p => try g.emitf("(pair? {s})", .{g.pickListVar(.{}).?.name}),
    }
}

/// Test position: only #f is false, so always-truthy int tests are
/// deliberate dead-branch fodder for the native if/and/or emission.
fn genTest(g: *Gen, ctx: *Ctx, d: u32) Error!void {
    if (g.ch.chance(.coin, 3, 5)) return genBool(g, ctx, d);
    try genInt(g, ctx, d);
}

// ---------------------------------------------------------------------------
// Statements — every statement is void-valued (see output discipline above)
// ---------------------------------------------------------------------------

const StmtOp = enum { noop, set_lit, set_expr, vec_set, let_stmt, when_form, if_stmt, begin2 };

fn genStmt(g: *Gen, ctx: *Ctx, depth_in: u32, in_scope: bool) Error!void {
    const depth = g.cap(depth_in);
    var c: Cands(StmtOp) = .{};
    // Always available: keeps the candidate list non-empty at depth 0 when
    // nothing is settable in scope.
    c.add(.noop, 1);
    // set! with a literal value compiles natively even at top level; a
    // compound value does so only inside a lexical scope (emitScopedValue).
    if (!ctx.no_set and g.hasVar(gen_mod.bindIsSettableAtom)) c.add(.set_lit, 3);
    if (!ctx.no_set and in_scope and g.hasVar(gen_mod.bindIsSettableInt)) c.add(.set_expr, 6);
    if (in_scope and g.hasVar(gen_mod.bindIsIntVec)) c.add(.vec_set, 5);
    if (depth > 0) {
        if (!in_scope) c.add(.let_stmt, 5);
        c.add(.when_form, 3);
        c.add(.if_stmt, 2);
        c.add(.begin2, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .noop => try g.emit("(when #f 0)"),
        .set_lit => {
            const b = g.pickVar(gen_mod.bindIsSettableAtom).?;
            if (b.kind == .boolean) {
                try g.emitf("(set! {s} {s})", .{ b.name, boolLit(g) });
            } else {
                try g.emitf("(set! {s} {d})", .{ b.name, litInt(g) });
            }
        },
        .set_expr => {
            const b = g.pickVar(gen_mod.bindIsSettableInt).?;
            try g.emitf("(set! {s} ", .{b.name});
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .vec_set => {
            const b = g.pickVar(gen_mod.bindIsIntVec).?;
            try g.emitf("(vector-set! {s} ", .{b.name});
            try genIndex(g, ctx, d, b.kind.vector.len);
            try g.emit(" ");
            try genInt(g, ctx, d);
            try g.emit(")");
        },
        .let_stmt => {
            // (let (bindings) stmt+): ends in a statement, so the let's own
            // value stays void (no top-level echo) while set!/vector-set!
            // get a lexical scope where compound values compile natively.
            const n = g.ch.range(.count, 1, 2);
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(n, &nb);
            try g.emit("(let (");
            const mark = g.scope.items.len;
            var let_ctx: Ctx = .{ .fn_depth = ctx.fn_depth, .no_lambda = true, .no_set = ctx.no_set };
            var stash: [3]LetKind = undefined;
            for (0..n) |i| {
                try g.emitf("({s} ", .{names[i]});
                stash[i] = try genLetInit(g, &let_ctx, d);
                try g.emit(") ");
            }
            for (0..n) |i| try pushLetBinding(g, names[i], stash[i]);
            try g.emit(") ");
            const nstmts = g.ch.range(.count, 1, 2);
            for (0..nstmts) |i| {
                if (i > 0) try g.emit(" ");
                try genStmt(g, &let_ctx, d, true);
            }
            try g.emit(")");
            g.scope.shrinkRetainingCapacity(mark);
        },
        .when_form => {
            try g.emit(if (g.ch.chance(.coin, 2, 3)) "(when " else "(unless ");
            try genTest(g, ctx, d);
            try g.emit(" ");
            try genStmt(g, ctx, d, in_scope);
            try g.emit(")");
        },
        .if_stmt => {
            try g.emit("(if ");
            try genTest(g, ctx, d);
            try g.emit(" ");
            try genStmt(g, ctx, d, in_scope);
            try g.emit(" ");
            try genStmt(g, ctx, d, in_scope);
            try g.emit(")");
        },
        .begin2 => {
            try g.emit("(begin ");
            try genStmt(g, ctx, d, in_scope);
            try g.emit(" ");
            try genStmt(g, ctx, d, in_scope);
            try g.emit(")");
        },
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Forms/procedures whose presence would mean the program left the
/// native-compilable subset (each would compile to a kaappi_eval fallback).
const forbidden_fragments = [_][]const u8{
    "(cond",          "(case",
    "(do ",           "(letrec",
    "(guard",         "(raise",
    "(delay",         "(force",
    "call/cc",        "call-with",
    "dynamic-wind",   "(map",
    "(apply",         "(fold",
    "(for-each",      "quasiquote",
    "`",              "define-syntax",
    "(string",        "(char",
    "bytevector",     "(let lp",
    "(lambda rest",   "(quote",
    "(values",        "(let-values",
    "(define-values",
};

/// Top-level forms must all be void-valued; these are the only heads the
/// generator may emit at line start (one top-level form per line).
const allowed_top_prefixes = [_][]const u8{
    "(define ", "(set! ", "(when ",  "(unless ", "(if ",
    "(begin ",  "(let (", "(let* (", "(write ",  "(newline)",
};

/// Occurrence facts about inline lambdas in a generated program (#1420). A
/// lambda is "inline" unless it is the define-position value of a
/// `(define name (lambda ...))` line — the generator emits one top-level
/// form per line, so define position is line-syntactic.
const InlineLambdaFacts = struct { nested: bool = false, variadic: bool = false };

fn scanInlineLambdas(src: []const u8) InlineLambdaFacts {
    var facts: InlineLambdaFacts = .{};
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        var from: usize = 0;
        if (std.mem.startsWith(u8, line, "(define ") and !std.mem.startsWith(u8, line, "(define (")) {
            // The first lambda on such a line is the define-position value.
            if (std.mem.indexOf(u8, line, "(lambda (")) |pos| from = pos + "(lambda (".len;
        }
        while (std.mem.indexOfPos(u8, line, from, "(lambda (")) |pos| {
            from = pos + "(lambda (".len;
            // The parameter list is flat, so it ends at the first ')'.
            const plist_end = std.mem.indexOfScalarPos(u8, line, from, ')') orelse line.len;
            if (std.mem.indexOf(u8, line[from..plist_end], " . ") != null) facts.variadic = true;
            // Nested: another lambda inside this one's paren extent. The
            // native subset has no strings, chars, or comments, so paren
            // counting is exact.
            var depth: usize = 0;
            var j = pos;
            const end = while (j < line.len) : (j += 1) {
                switch (line[j]) {
                    '(' => depth += 1,
                    ')' => {
                        depth -= 1;
                        if (depth == 0) break j;
                    },
                    else => {},
                }
            } else line.len;
            if (std.mem.indexOfPos(u8, line, pos + 1, "(lambda (")) |inner| {
                if (inner < end) facts.nested = true;
            }
        }
    }
    return facts;
}

fn assertNativeSubset(src: []const u8) !void {
    for (forbidden_fragments) |f| {
        try std.testing.expect(std.mem.indexOf(u8, src, f) == null);
    }
    // The only quote character allowed is the empty-list literal '() —
    // any other quoted datum would be a pointer constant that emitConstant
    // routes through kaappi_eval.
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, src, i, '\'')) |pos| {
        try std.testing.expect(pos + 2 < src.len);
        try std.testing.expect(src[pos + 1] == '(' and src[pos + 2] == ')');
        i = pos + 1;
    }
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var ok = false;
        for (allowed_top_prefixes) |p| {
            if (std.mem.startsWith(u8, line, p)) {
                ok = true;
                break;
            }
        }
        try std.testing.expect(ok);
    }
}

test "native-mode fixed-seed programs parse, compile, stay bounded and in subset" {
    const memory = @import("memory.zig");
    const reader_mod = @import("reader.zig");
    const compiler_mod = @import("compiler.zig");
    const types = @import("types.zig");
    const gpa = std.testing.allocator;

    var saw_nested_inline = false;
    var saw_variadic_inline = false;
    var seed: u64 = 0;
    while (seed < 2000) : (seed += 1) {
        const src = try gen_mod.generateNativeSeeded(seed, gpa);
        defer gpa.free(src);
        errdefer std.debug.print("seed {d} program:\n{s}\n", .{ seed, src });
        try std.testing.expect(src.len < gen_mod.expected_max_bytes);
        try assertNativeSubset(src);
        const facts = scanInlineLambdas(src);
        if (facts.nested) saw_nested_inline = true;
        if (facts.variadic) saw_variadic_inline = true;

        var gc = memory.GC.init(gpa);
        defer gc.deinit();
        // No VM marks compile-time temporaries as roots here; suppress
        // collection (bounded allocation per seed) as the full-mode test does.
        gc.no_collect += 1;
        var macros = std.StringHashMap(types.Value).init(gpa);
        defer macros.deinit();
        var globals = std.StringHashMap(types.Value).init(gpa);
        defer globals.deinit();
        var r = reader_mod.Reader.init(&gc, src);
        defer r.deinit();
        while (try r.hasMore()) {
            var expr = try r.readDatum();
            gc.pushRoot(&expr);
            defer gc.popRoot();
            _ = try compiler_mod.compileExpressionWithMacros(&gc, expr, &macros, &globals);
        }
    }
    // The #1420 shapes must actually occur in the seed corpus: nested
    // inline lambdas (chained-capture coverage) and inline variadic
    // lambdas (eval-fallback frame-republication coverage). A failure here
    // means a generator change silently disabled a shape family the
    // VM-vs-native oracle depends on.
    try std.testing.expect(saw_nested_inline);
    try std.testing.expect(saw_variadic_inline);
}

test "native-mode generation is deterministic per seed" {
    const gpa = std.testing.allocator;
    const a = try gen_mod.generateNativeSeeded(97, gpa);
    defer gpa.free(a);
    const b = try gen_mod.generateNativeSeeded(97, gpa);
    defer gpa.free(b);
    try std.testing.expectEqualStrings(a, b);
}
