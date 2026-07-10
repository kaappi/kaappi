//! Portable-subset program generator for the Kaappi-vs-external-Scheme
//! differential oracle (fuzzing Tier 3, issue #1396).
//!
//! The offline harness (tests/fuzz/oracle-diff.sh) runs each generated
//! program through `kaappi` and through a pinned reference implementation
//! (Chibi Scheme) and diffs stdout. R7RS-small deliberately leaves parts of
//! the language unspecified, so an unrestricted program would diverge
//! without either implementation being wrong. Csmith's core lesson is that
//! most of the engineering goes into generating only the **fully-specified
//! subset**; this module encodes that subset, one rule per unspecified zone:
//!
//! - **Pure expressions** (evaluation order): R7RS leaves argument order,
//!   `let`/`letrec` init order, and `map`/`vector-map` application order
//!   unspecified. Rather than track effect types (Midtgaard et al.'s
//!   "at most one effect per argument list"), expressions here carry NO
//!   externally visible effects at all: no mutation of outer bindings, no
//!   raise, no I/O. Mutation lives only in statement slots whose order the
//!   report fixes: top-level forms, `begin`/`when`/`unless`/`if` statement
//!   bodies, `let`-statement bodies, and `for-each` (which, unlike `map`,
//!   guarantees left-to-right application). One sound exception inside
//!   expressions: mutating a binding or a freshly constructed object that
//!   the expression itself introduced (`(let ((a ...)) (set! a ...) ...)`,
//!   lambda own-parameter `set!`, and the let_mut combinator below) —
//!   invisible to sibling expressions, so order cannot matter.
//! - **Total by construction** (error objects): `guard` always has an
//!   `else` clause; `raise`/`error` appear only at a guard body's root as
//!   `(if <test> <raise> <alt>)` so at most one raise can fire per body
//!   (two raises racing in sibling argument positions would pick their
//!   winner by evaluation order). `call/cc` escapes once through a
//!   structured `(if <test> (k <v>) <v>)` and `k` is never registered as a
//!   general binding for the same reason. Programs therefore never signal:
//!   both sides must exit 0, and the harness compares stdout byte-for-byte.
//! - **Exact integers only** (exactness and flonum printing edges): no
//!   flonums anywhere; division ops take nonzero literal divisors; bignums
//!   are fine (arbitrary-precision printing is exact in both).
//! - **ASCII only** (Unicode support beyond ASCII is optional in
//!   R7RS-small): every emitted byte is < 0x80; `char-upcase`/`downcase`
//!   run only on ASCII sources.
//! - **Library-clean vocabulary**: the program opens with an explicit
//!   `(import (scheme base) (scheme char) (scheme lazy) (scheme write))`
//!   and uses nothing outside those four libraries (no SRFI `fold`, no
//!   extensions). Chibi enforces library boundaries; Kaappi does not, so a
//!   leaked name would surface as a one-sided "undefined variable".
//! - **Specified output only**: Kaappi echoes non-void top-level values in
//!   file mode, Chibi does not — so every top-level form is void-valued
//!   and all observables go through explicit `(write ...)` + `(newline)`,
//!   including an end-of-program echo of every non-procedure global.
//!   Procedures are never written (representation unspecified) and neither
//!   are whole bytevectors (Chibi writes bytes ≥ 8 in hex: `#u8(#xFF)`);
//!   bytevector observables go byte-wise through `bytevector-u8-ref`.
//!   Quote/quasiquote list data is safe: both sides print the unabbreviated
//!   `(quasiquote ...)` form.
//!
//! Everything else mirrors the full grammar (fuzz_gen.zig) so the oracle
//! still covers closures, tail calls, named let / do loops, call/cc,
//! dynamic-wind, guard, quasiquote, syntax-rules, and the mutation forms —
//! conformance breadth is the point of the external oracle. Shares the
//! Smith/PRNG Chooser, scope tracking, and byte-budget infrastructure with
//! the full generator.

const std = @import("std");
const gen_mod = @import("fuzz_gen.zig");

const Gen = gen_mod.Gen;
const Error = gen_mod.Error;
const Cands = gen_mod.Cands;
const Binding = gen_mod.Binding;
const Len = gen_mod.Len;
const StrInfo = gen_mod.StrInfo;
const ListInfo = gen_mod.ListInfo;
const VecInfo = gen_mod.VecInfo;
const ListNeed = gen_mod.ListNeed;

const max_depth: u32 = 5;

// Data-kind and statement generators (split into fuzz_gen_portable_data.zig
// for the file size policy, mirroring the fuzz_gen.zig split).
const data = @import("fuzz_gen_portable_data.zig");
const genChar = data.genChar;
const genString = data.genString;
const genList = data.genList;
const genVector = data.genVector;
const genBytevector = data.genBytevector;
const genStmt = data.genStmt;

pub const import_line = "(import (scheme base) (scheme char) (scheme lazy) (scheme write))\n";

// Vocabulary. Every name is exported by one of the four imported libraries
// (R7RS appendix A); every literal is pure ASCII.
const arith_ops = [_][]const u8{ "+", "-", "*", "min", "max" };
const div_ops = [_][]const u8{ "quotient", "remainder", "modulo" };
const cmp_ops = [_][]const u8{ "<", "<=", "=", ">", ">=" };
const rec_ops = [_][]const u8{ "+", "*", "max" };
const guard_preds = [_][]const u8{ "number?", "symbol?", "string?", "pair?" };
const any_preds = [_][]const u8{ "number?", "string?", "boolean?", "procedure?", "symbol?", "char?", "vector?", "list?" };

pub fn genProgram(g: *Gen) Error!void {
    try g.emit(import_line);
    const nglobals = g.ch.range(.count, 0, gen_mod.global_names.len);
    for (0..nglobals) |_| try genGlobalDefine(g);
    const nfns = g.ch.range(.count, 0, gen_mod.fn_names.len);
    for (0..nfns) |_| try genFnDefine(g);
    const nmacros = g.ch.range(.count, 0, 2);
    for (0..nmacros) |_| try genMacroDefine(g);

    // Top-level statements: the only place effects on globals happen.
    const nstmts = g.ch.range(.count, 0, 2);
    for (0..nstmts) |_| {
        try genStmt(g, g.ch.range(.depth_pick, 1, 3));
        try g.emit("\n");
    }

    const nwrites = g.ch.range(.count, 1, 3);
    for (0..nwrites) |_| try genWrite(g);

    // Echo every observable global so a wrong value stored by a statement
    // is visible even when no write expression touched it. Procedures are
    // skipped (printed representation is unspecified); bytevectors are
    // echoed byte-wise (Chibi writes whole bytevectors with hex bytes).
    // Only top-level bindings remain in scope here.
    for (g.scope.items) |b| {
        switch (b.kind) {
            .proc, .reserved => {},
            .bytevector => |len| for (0..len) |i| {
                try g.emitf("(write (bytevector-u8-ref {s} {d}))\n(newline)\n", .{ b.name, i });
            },
            else => try g.emitf("(write {s})\n(newline)\n", .{b.name}),
        }
    }
}

/// One `(write <pure observable>)` + `(newline)` top-level pair. Everything
/// written has a fully specified textual representation in both
/// implementations (probed: lists, vectors, strings, chars, symbols-in-data,
/// booleans, exact integers of any size).
fn genWrite(g: *Gen) Error!void {
    const depth = g.ch.range(.depth_pick, 2, max_depth);
    const WKind = enum { int, boolean, char, string, list, vector };
    var c: Cands(WKind) = .{};
    c.add(.int, 6);
    c.add(.boolean, 1);
    c.add(.char, 1);
    c.add(.string, 1);
    c.add(.list, 2);
    c.add(.vector, 1);
    try g.emit("(write ");
    switch (c.pick(g.ch)) {
        .int => try genInt(g, depth),
        .boolean => try genBool(g, depth),
        .char => try genChar(g, depth),
        .string => _ = try genString(g, depth),
        .list => _ = try genList(g, depth, .{}),
        .vector => _ = try genVector(g, depth, false),
    }
    try g.emit(")\n(newline)\n");
}

// ---------------------------------------------------------------------------
// Top-level definitions
// ---------------------------------------------------------------------------

const BindKind = enum { int, boolean, char, string, list, vector, bytevector, proc };

pub fn pickBindKind(g: *Gen) BindKind {
    var c: Cands(BindKind) = .{};
    c.add(.int, 6);
    c.add(.proc, 3);
    c.add(.vector, 3);
    c.add(.list, 3);
    c.add(.string, 2);
    c.add(.bytevector, 1);
    c.add(.boolean, 1);
    c.add(.char, 1);
    return c.pick(g.ch);
}

/// Emit a pure expression of the chosen kind; returns the binding Kind.
/// The `Kind` type itself is private to fuzz_gen.zig, so the result type is
/// inferred through pushBinding — mirror of the full generator's
/// genValueOfKind.
pub fn genValueOfKind(g: *Gen, bk: BindKind, depth: u32) Error!@FieldType(Binding, "kind") {
    switch (bk) {
        .int => {
            try genInt(g, depth);
            return .int;
        },
        .boolean => {
            try genBool(g, depth);
            return .boolean;
        },
        .char => {
            try genChar(g, depth);
            return .char;
        },
        .string => return .{ .string = try genString(g, depth) },
        .list => return .{ .list = try genList(g, depth, .{}) },
        .vector => return .{ .vector = try genVector(g, depth, false) },
        .bytevector => return .{ .bytevector = try genBytevector(g, depth) },
        .proc => {
            const variadic = g.ch.chance(.coin, 1, 5);
            const arity: u8 = @intCast(g.ch.range(.arity, if (variadic) 0 else 1, 3));
            try genLambdaInt(g, arity, variadic, depth);
            return .{ .proc = .{ .arity = arity, .variadic = variadic } };
        },
    }
}

fn genGlobalDefine(g: *Gen) Error!void {
    const name = gen_mod.global_names[g.global_count];
    g.global_count += 1;
    try g.emitf("(define {s} ", .{name});
    const kind = try genValueOfKind(g, pickBindKind(g), 2);
    try g.emit(")\n");
    // Registered after the value expression so it cannot reference itself.
    try g.pushBinding(name, kind);
}

fn genFnDefine(g: *Gen) Error!void {
    const name = gen_mod.fn_names[g.fn_count];
    g.fn_count += 1;
    var nb: [4][]const u8 = undefined;
    switch (g.ch.range(.shape, 0, 2)) {
        0 => { // plain function, pure body (may rebind its own parameters)
            const arity: u8 = @intCast(g.ch.range(.arity, 0, 3));
            const params = g.pickNames(arity, &nb);
            try g.emitf("(define ({s}", .{name});
            const mark = g.scope.items.len;
            for (params) |p| {
                try g.emitf(" {s}", .{p});
                try g.pushBinding(p, .int);
            }
            try g.emit(") ");
            // Own-parameter set! before the body: externally invisible
            // (rebinds the local), exercises boxed-variable paths.
            if (arity > 0 and g.ch.chance(.coin, 1, 3)) {
                try g.emitf("(set! {s} ", .{params[0]});
                try genInt(g, 2);
                try g.emit(") ");
            }
            try genInt(g, 3);
            try g.emit(")\n");
            g.scope.shrinkRetainingCapacity(mark);
            try g.pushBinding(name, .{ .proc = .{ .arity = arity } });
        },
        1 => { // tail-recursive skeleton: bounded countdown, clamped accumulator
            const params = g.pickNames(2, &nb);
            try g.emitf("(define ({s} {s} {s}) (if (<= {s} 0) {s} ({s} (- {s} 1) (modulo ", .{
                name, params[0], params[1], params[0], params[1], name, params[0],
            });
            const mark = g.scope.items.len;
            try g.pushBinding(params[0], .int);
            try g.pushBinding(params[1], .int);
            try genInt(g, 3);
            g.scope.shrinkRetainingCapacity(mark);
            try g.emitf(" {d}))))\n", .{gen_mod.acc_modulus});
            try g.pushBinding(name, .{ .proc = .{ .arity = 2, .bounded_first = true } });
        },
        else => { // non-tail recursive skeleton (stack-frame paths)
            const params = g.pickNames(1, &nb);
            const op = rec_ops[g.ch.index(.op_pick, rec_ops.len)];
            try g.emitf("(define ({s} {s}) (if (<= {s} 0) ", .{ name, params[0], params[0] });
            const mark = g.scope.items.len;
            try g.pushBinding(params[0], .int);
            try genInt(g, 2);
            try g.emitf(" ({s} ", .{op});
            try genInt(g, 2);
            try g.emitf(" ({s} (- {s} 1)))))\n", .{ name, params[0] });
            g.scope.shrinkRetainingCapacity(mark);
            try g.pushBinding(name, .{ .proc = .{ .arity = 1, .bounded_first = true } });
        },
    }
}

fn genMacroDefine(g: *Gen) Error!void {
    // Same shapes as the full generator: templates expand pattern variables
    // (pure caller expressions) into pure arithmetic, so duplicated
    // expansion sites stay order-independent.
    const macro_names = [_][]const u8{ "m0", "m1" };
    const pattern_names = [_][]const u8{ "p", "q", "r" };
    const name = macro_names[g.macro_count];
    g.macro_count += 1;
    try g.emitf("(define-syntax {s} (syntax-rules ()", .{name});
    const shape = g.ch.range(.shape, 0, 2);
    var arity: u8 = 0;
    var variadic = false;
    if (shape == 0 or shape == 2) {
        arity = @intCast(g.ch.range(.arity, 1, 3));
        try g.emit(" ((_");
        const mark = g.scope.items.len;
        for (pattern_names[0..arity]) |pn| {
            try g.emitf(" {s}", .{pn});
            try g.scope.append(g.gpa, .{ .name = pn, .kind = .int, .settable = false });
        }
        try g.emit(") ");
        try genInt(g, 2);
        try g.emit(")");
        g.scope.shrinkRetainingCapacity(mark);
    }
    if (shape == 1 or shape == 2) {
        variadic = true;
        const vop = if (g.ch.chance(.coin, 1, 2)) "+" else "*";
        try g.emitf(" ((_ p ...) ({s} 1 p ...))", .{vop});
    }
    try g.emit("))\n");
    try g.macros.append(g.gpa, .{ .name = name, .arity = arity, .variadic = variadic });
}

// ---------------------------------------------------------------------------
// Integer expressions (pure)
// ---------------------------------------------------------------------------

const IntOp = enum {
    lit,
    ref,
    arith,
    abs_op,
    divmod,
    if_form,
    cond_form,
    case_form,
    and_or,
    let_form,
    let_mut,
    letrec_lambdas,
    inline_call,
    call_proc,
    call_macro,
    named_let,
    do_loop,
    letrec_rec,
    callcc,
    dynwind,
    guard_form,
    begin_form,
    vec_ref,
    bv_ref,
    char_int,
    str_len,
    list_len,
    car_op,
    list_ref_op,
    force_delay,
    cwv,
    let_values,
    num_roundtrip,
    apply_op,
};

pub fn genInt(g: *Gen, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    var c: Cands(IntOp) = .{};
    c.add(.lit, 5);
    if (g.hasVar(gen_mod.bindIsInt)) c.add(.ref, 6);
    if (depth > 0) {
        c.add(.arith, 8);
        c.add(.abs_op, 1);
        c.add(.divmod, 3);
        c.add(.if_form, 5);
        c.add(.cond_form, 3);
        c.add(.case_form, 2);
        c.add(.and_or, 2);
        c.add(.let_form, 6);
        c.add(.let_mut, 3);
        c.add(.letrec_lambdas, 2);
        c.add(.inline_call, 2);
        if (g.hasVar(gen_mod.bindIsProc)) c.add(.call_proc, 6);
        if (g.macros.items.len > 0) c.add(.call_macro, 4);
        c.add(.named_let, 4);
        c.add(.do_loop, 3);
        c.add(.letrec_rec, 3);
        c.add(.callcc, 3);
        c.add(.dynwind, 2);
        c.add(.guard_form, 3);
        c.add(.begin_form, 2);
        if (g.hasVar(gen_mod.bindIsVec)) c.add(.vec_ref, 3);
        if (g.hasVar(gen_mod.bindIsBv)) c.add(.bv_ref, 2);
        c.add(.char_int, 1);
        c.add(.str_len, 1);
        c.add(.list_len, 2);
        c.add(.car_op, 2);
        if (g.hasVar(gen_mod.bindIsListIntsExactNonEmpty)) c.add(.list_ref_op, 2);
        c.add(.force_delay, 1);
        c.add(.cwv, 1);
        c.add(.let_values, 1);
        c.add(.num_roundtrip, 1);
        if (g.hasVar(gen_mod.bindIsPlainProc)) c.add(.apply_op, 2);
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
                try genInt(g, d);
            }
            try g.emit(")");
        },
        .abs_op => {
            try g.emit("(abs ");
            try genInt(g, d);
            try g.emit(")");
        },
        .divmod => {
            const op = div_ops[g.ch.index(.op_pick, div_ops.len)];
            var divisor: i32 = @intCast(g.ch.range(.lit_pick, 1, 12));
            if (g.ch.chance(.coin, 1, 4)) divisor = -divisor;
            try g.emitf("({s} ", .{op});
            try genInt(g, d);
            try g.emitf(" {d})", .{divisor});
        },
        .if_form => {
            try g.emit("(if ");
            try genTest(g, d);
            try g.emit(" ");
            try genInt(g, d);
            try g.emit(" ");
            try genInt(g, d);
            try g.emit(")");
        },
        .cond_form => {
            try g.emit("(cond ");
            if (g.ch.chance(.coin, 1, 4)) {
                // (cond (EXPR => (lambda (x) ...)) ...): ints are truthy,
                // so the arrow receives the test value.
                var nb: [4][]const u8 = undefined;
                const names = g.pickNames(1, &nb);
                try g.emit("(");
                try genInt(g, d);
                try g.emitf(" => (lambda ({s}) ", .{names[0]});
                const mark = g.scope.items.len;
                try g.pushBinding(names[0], .int);
                try genInt(g, d);
                g.scope.shrinkRetainingCapacity(mark);
                try g.emit(")) ");
            } else {
                const nclauses = g.ch.range(.count, 1, 2);
                for (0..nclauses) |_| {
                    try g.emit("(");
                    try genTest(g, d);
                    try g.emit(" ");
                    try genInt(g, d);
                    try g.emit(") ");
                }
            }
            try g.emit("(else ");
            try genInt(g, d);
            try g.emit("))");
        },
        .case_form => {
            try g.emit("(case ");
            try genInt(g, d);
            const nclauses = g.ch.range(.count, 1, 2);
            for (0..nclauses) |_| {
                try g.emit(" ((");
                const ndata = g.ch.range(.count, 1, 3);
                for (0..ndata) |j| {
                    if (j > 0) try g.emit(" ");
                    try g.emitf("{d}", .{@as(i64, g.ch.range(.lit_pick, 0, 40)) - 20});
                }
                try g.emit(") ");
                try genInt(g, d);
                try g.emit(")");
            }
            try g.emit(" (else ");
            try genInt(g, d);
            try g.emit("))");
        },
        .and_or => {
            // All-integer arguments (never #f): both forms yield an integer.
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and" else "(or");
            const nargs = g.ch.range(.nargs, 2, 3);
            for (0..nargs) |_| {
                try g.emit(" ");
                try genInt(g, d);
            }
            try g.emit(")");
        },
        .let_form => try genLetInt(g, d),
        .let_mut => try genLetMut(g, d),
        .letrec_lambdas => try genLetrecLambdas(g, d),
        .inline_call => {
            const arity = g.ch.range(.arity, 0, 2);
            var nb: [4][]const u8 = undefined;
            const params = g.pickNames(arity, &nb);
            try g.emit("((lambda (");
            const mark = g.scope.items.len;
            for (params, 0..) |p, i| {
                if (i > 0) try g.emit(" ");
                try g.emit(p);
                try g.pushBinding(p, .int);
            }
            try g.emit(") ");
            try genInt(g, d);
            try g.emit(")");
            g.scope.shrinkRetainingCapacity(mark);
            for (0..arity) |_| {
                try g.emit(" ");
                try genInt(g, d);
            }
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
                if (i == 0 and info.bounded_first)
                    try g.emitf("{d}", .{g.ch.range(.iters, 0, 12)})
                else
                    try genInt(g, d);
            }
            try g.emit(")");
        },
        .call_macro => {
            const m = g.macros.items[g.ch.index(.op_pick, g.macros.items.len)];
            const nargs: u32 = if (m.variadic) g.ch.range(.nargs, 0, 3) else m.arity;
            try g.emitf("({s}", .{m.name});
            for (0..nargs) |_| {
                try g.emit(" ");
                try genInt(g, d);
            }
            try g.emit(")");
        },
        .named_let => {
            const iters = loopIters(g);
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emitf("(let lp (({s} {d}) ({s} ", .{ names[0], iters, names[1] });
            try genInt(g, d); // accumulator init: outer scope
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            g.loop_nest += 1;
            try g.emitf(")) (if (<= {s} 0) {s} (lp (- {s} 1) (modulo ", .{ names[0], names[1], names[0] });
            try genInt(g, d);
            try g.emitf(" {d}))))", .{gen_mod.acc_modulus});
            g.loop_nest -= 1;
            g.scope.shrinkRetainingCapacity(mark);
        },
        .do_loop => {
            // No body commands: a command mutating an outer binding would
            // make the whole do-expression impure. Steps are pure.
            const iters = loopIters(g);
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emitf("(do (({s} 0 (+ {s} 1)) ({s} ", .{ names[0], names[0], names[1] });
            try genInt(g, d); // accumulator init: outer scope
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            g.loop_nest += 1;
            try g.emit(" (modulo ");
            try genInt(g, d);
            try g.emitf(" {d}))) ((>= {s} {d}) {s}))", .{ gen_mod.acc_modulus, names[0], iters, names[1] });
            g.loop_nest -= 1;
            g.scope.shrinkRetainingCapacity(mark);
        },
        .letrec_rec => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb); // recursive proc, counter
            const op = rec_ops[g.ch.index(.op_pick, rec_ops.len)];
            try g.emitf("(letrec (({s} (lambda ({s}) (if (<= {s} 0) ", .{ names[0], names[1], names[1] });
            const mark = g.scope.items.len;
            // The proc name shadows any outer binding throughout the
            // letrec; reserve it so the body can't pick the outer one.
            try g.pushBinding(names[0], .reserved);
            try g.pushBinding(names[1], .int);
            try genInt(g, d);
            try g.emitf(" ({s} ", .{op});
            try genInt(g, d);
            try g.emitf(" ({s} (- {s} 1))))))) ({s} {d}))", .{ names[0], names[1], names[0], g.ch.range(.iters, 0, 12) });
            g.scope.shrinkRetainingCapacity(mark);
        },
        .callcc => {
            // Structured single escape; k is never registered as a general
            // binding (two escapes racing in sibling arguments would pick
            // their winner by evaluation order).
            const nm = if (g.ch.chance(.coin, 1, 6)) "call-with-current-continuation" else "call/cc";
            try g.emitf("({s} (lambda (k) (if ", .{nm});
            try genTest(g, d);
            try g.emit(" (k ");
            try genInt(g, d);
            try g.emit(") ");
            try genInt(g, d);
            try g.emit(")))");
        },
        .dynwind => {
            // Pure thunks: an effectful before/after would leak the effect
            // into expression position.
            try g.emit("(dynamic-wind (lambda () 0) (lambda () ");
            try genInt(g, d);
            try g.emit(") (lambda () 0))");
        },
        .guard_form => {
            try g.emit("(guard (ex");
            const nclauses = g.ch.range(.count, 0, 2);
            for (0..nclauses) |_| {
                const pred = guard_preds[g.ch.index(.op_pick, guard_preds.len)];
                try g.emitf(" (({s} ex) ", .{pred});
                try genInt(g, d);
                try g.emit(")");
            }
            // else is mandatory: an unmatched condition would re-raise to
            // the top level, and uncaught errors leave the specified subset
            // (error output and exit path differ legitimately).
            try g.emit(" (else ");
            try genInt(g, d);
            try g.emit(")) ");
            if (g.ch.chance(.coin, 1, 2)) {
                // Conditional raise at the body root — the only raise site,
                // so at most one raise can fire per guard body.
                try g.emit("(if ");
                try genTest(g, d);
                try g.emit(" ");
                try genRaise(g, d);
                try g.emit(" ");
                try genInt(g, d);
                try g.emit(")");
            } else {
                try genInt(g, d);
            }
            try g.emit(")");
        },
        .begin_form => {
            // Pure begin: the leading expression is dead code (discard
            // paths), never a statement.
            try g.emit("(begin ");
            try genInt(g, d);
            try g.emit(" ");
            try genInt(g, d);
            try g.emit(")");
        },
        .vec_ref => {
            const b = g.pickVar(gen_mod.bindIsVec).?;
            const v = b.kind.vector;
            // Boxed slots hold non-empty int lists, so car is safe.
            try g.emit(if (v.boxed) "(car (vector-ref " else "(vector-ref ");
            try g.emit(b.name);
            try g.emit(" ");
            try genIndex(g, d, v.len);
            try g.emit(if (v.boxed) "))" else ")");
        },
        .bv_ref => {
            const b = g.pickVar(gen_mod.bindIsBv).?;
            try g.emitf("(bytevector-u8-ref {s} ", .{b.name});
            try genIndex(g, d, b.kind.bytevector);
            try g.emit(")");
        },
        .char_int => {
            try g.emit("(char->integer ");
            try genChar(g, d);
            try g.emit(")");
        },
        .str_len => {
            try g.emit("(string-length ");
            _ = try genString(g, d);
            try g.emit(")");
        },
        .list_len => {
            try g.emit("(length ");
            _ = try genList(g, d, .{});
            try g.emit(")");
        },
        .car_op => {
            try g.emit("(car ");
            _ = try genList(g, d, .{ .ints = true, .non_empty = true });
            try g.emit(")");
        },
        .list_ref_op => {
            const b = g.pickVar(gen_mod.bindIsListIntsExactNonEmpty).?;
            const len = b.kind.list.len.exactLen().?;
            try g.emitf("(list-ref {s} {d})", .{ b.name, g.ch.range(.idx_pick, 0, len - 1) });
        },
        .force_delay => {
            try g.emit("(force (delay ");
            try genInt(g, d);
            try g.emit("))");
        },
        .cwv => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emit("(call-with-values (lambda () (values ");
            try genInt(g, d);
            try g.emit(" ");
            try genInt(g, d);
            try g.emitf(")) (lambda ({s} {s}) ", .{ names[0], names[1] });
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            try genInt(g, d);
            try g.emit("))");
            g.scope.shrinkRetainingCapacity(mark);
        },
        .let_values => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emitf("(let-values ((({s} {s}) (values ", .{ names[0], names[1] });
            try genInt(g, d);
            try g.emit(" ");
            try genInt(g, d);
            try g.emit("))) ");
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            try genInt(g, d);
            try g.emit(")");
            g.scope.shrinkRetainingCapacity(mark);
        },
        .num_roundtrip => {
            try g.emit("(string->number (number->string ");
            try genInt(g, d);
            try g.emit("))");
        },
        .apply_op => {
            const b = g.pickVar(gen_mod.bindIsPlainProc).?;
            try g.emitf("(apply {s} (list", .{b.name});
            for (0..b.kind.proc.arity) |_| {
                try g.emit(" ");
                try genInt(g, d);
            }
            try g.emit("))");
        },
    }
}

pub fn litInt(g: *Gen) i64 {
    return @as(i64, g.ch.range(.lit_pick, 0, 200)) - 100;
}

fn loopIters(g: *Gen) u32 {
    const hi: u32 = if (g.loop_nest == 0) 16 else 5;
    return g.ch.range(.iters, 0, hi);
}

/// In-range index: literal below `len` or `(modulo <int> len)` (modulo of a
/// positive modulus is never negative).
pub fn genIndex(g: *Gen, d: u32, len: u16) Error!void {
    if (g.ch.chance(.idx_kind, 2, 3)) {
        try g.emitf("{d}", .{g.ch.range(.idx_pick, 0, len - 1)});
    } else {
        try g.emit("(modulo ");
        try genInt(g, @min(d, 1));
        try g.emitf(" {d})", .{len});
    }
}

fn genRaise(g: *Gen, d: u32) Error!void {
    switch (g.ch.range(.shape, 0, 2)) {
        0 => try g.emitf("(raise {d})", .{litInt(g)}),
        1 => try g.emitf("(raise '{s})", .{gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)]}),
        else => {
            try g.emit("(error \"fuzz\" ");
            try genInt(g, @min(d, 1));
            try g.emit(")");
        },
    }
}

fn genLetInt(g: *Gen, d: u32) Error!void {
    const star = g.ch.chance(.coin, 1, 2);
    const n = g.ch.range(.count, 1, 3);
    var nb: [4][]const u8 = undefined;
    const names = g.pickNames(n, &nb);
    try g.emit(if (star) "(let* (" else "(let (");
    const mark = g.scope.items.len;
    var stash: [3]@FieldType(Binding, "kind") = undefined;
    for (0..n) |i| {
        try g.emitf("({s} ", .{names[i]});
        const kind = try genValueOfKind(g, pickBindKind(g), d);
        try g.emit(") ");
        // let: inits are evaluated in the outer scope, so bindings only
        // become visible after all of them; let*: immediately.
        if (star) try g.pushBinding(names[i], kind) else stash[i] = kind;
    }
    if (!star) for (0..n) |i| try g.pushBinding(names[i], stash[i]);
    try g.emit(") ");
    // Rebinding one of the let's own variables is externally invisible, so
    // this set! keeps the whole let-expression pure while exercising
    // mutable-binding compilation.
    if (g.ch.chance(.coin, 1, 4)) {
        const i = g.ch.index(.var_pick, n);
        switch (if (star) g.scope.items[mark + i].kind else stash[i]) {
            .int => {
                try g.emitf("(set! {s} ", .{names[i]});
                try genClampedInt(g, d);
                try g.emit(") ");
            },
            .boolean => {
                try g.emitf("(set! {s} ", .{names[i]});
                try genBool(g, d);
                try g.emit(") ");
            },
            else => {},
        }
    }
    try genInt(g, d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

/// Fresh-object mutation inside an expression, sound by construction: the
/// let binds a freshly constructed object (constructor emitted right here,
/// never a reference to an outer binding), mutates it, and computes an int
/// from it — no sibling expression can observe the mutation. This is the
/// only structure mutation allowed in expression position.
fn genLetMut(g: *Gen, d: u32) Error!void {
    var nb: [4][]const u8 = undefined;
    const names = g.pickNames(1, &nb);
    const name = names[0];
    const mark = g.scope.items.len;
    const MK = enum { vec, str, list, bv };
    var c: Cands(MK) = .{};
    c.add(.vec, 3);
    c.add(.str, 2);
    c.add(.list, 3);
    c.add(.bv, 1);
    switch (c.pick(g.ch)) {
        .vec => {
            const len: u16 = @intCast(g.ch.range(.len_pick, 1, 5));
            try g.emitf("(let (({s} (make-vector {d} ", .{ name, len });
            try genInt(g, d);
            try g.emitf("))) (vector-set! {s} ", .{name});
            try genIndex(g, d, len);
            try g.emit(" ");
            try genInt(g, d);
            try g.emit(") ");
            try g.pushBinding(name, .{ .vector = .{ .len = len, .boxed = false } });
        },
        .str => {
            const len: u16 = @intCast(g.ch.range(.len_pick, 1, 6));
            try g.emitf("(let (({s} (make-string {d} ", .{ name, len });
            try genChar(g, d);
            try g.emitf("))) (string-set! {s} ", .{name});
            try genIndex(g, d, len);
            try g.emit(" ");
            try genChar(g, d);
            try g.emit(") ");
            try g.pushBinding(name, .{ .string = .{ .len = len, .mutable = true } });
        },
        .list => {
            const len: u16 = @intCast(g.ch.range(.len_pick, 1, 4));
            try g.emitf("(let (({s} (list", .{name});
            for (0..len) |_| {
                try g.emit(" ");
                try genInt(g, d);
            }
            try g.emitf("))) (set-car! {s} ", .{name});
            try genInt(g, d);
            try g.emit(") ");
            try g.pushBinding(name, .{ .list = .{ .len = .{ .exact = len }, .mut = .all, .ints = true } });
        },
        .bv => {
            const len: u16 = @intCast(g.ch.range(.len_pick, 1, 6));
            try g.emitf("(let (({s} (make-bytevector {d} {d}))) (bytevector-u8-set! {s} ", .{
                name, len, g.ch.range(.lit_pick, 0, 255), name,
            });
            try genIndex(g, d, len);
            try g.emit(" (modulo ");
            try genInt(g, d);
            try g.emit(" 256)) ");
            try g.pushBinding(name, .{ .bytevector = len });
        },
    }
    try genInt(g, d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

fn genLetrecLambdas(g: *Gen, d: u32) Error!void {
    // General letrec with lambda initializers (pure: evaluating a lambda
    // has no effect, so unspecified init order is harmless). Bodies see
    // only the outer scope: sibling references would enable unbounded
    // mutual recursion.
    const n = g.ch.range(.count, 1, 2);
    var nb: [4][]const u8 = undefined;
    const names = g.pickNames(n, &nb);
    try g.emit("(letrec (");
    const mark = g.scope.items.len;
    for (0..n) |i| try g.pushBinding(names[i], .reserved);
    var stash: [2]@FieldType(Binding, "kind") = undefined;
    for (0..n) |i| {
        const arity: u8 = @intCast(g.ch.range(.arity, 0, 2));
        try g.emitf("({s} ", .{names[i]});
        try genLambdaInt(g, arity, false, d);
        try g.emit(") ");
        stash[i] = .{ .proc = .{ .arity = arity } };
    }
    for (0..n) |i| g.scope.items[mark + i].kind = stash[i];
    try g.emit(") ");
    try genInt(g, d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

/// (lambda (p...) <pure int body>), optionally variadic. The body may
/// rebind its own parameters (externally invisible) but nothing else.
fn genLambdaInt(g: *Gen, arity: u8, variadic: bool, d: u32) Error!void {
    var nb: [4][]const u8 = undefined;
    const params = g.pickNames(arity, &nb);
    const mark = g.scope.items.len;
    if (variadic and arity == 0) {
        try g.emit("(lambda rest ");
        try g.pushBinding("rest", .{ .list = .{ .len = .unknown, .mut = .all, .ints = true } });
    } else {
        try g.emit("(lambda (");
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
    }
    if (arity > 0 and g.ch.chance(.coin, 1, 4)) {
        try g.emitf("(set! {s} ", .{params[0]});
        try genInt(g, d);
        try g.emit(") ");
    }
    try genInt(g, d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

/// Integer write target: inside loops, clamp so repeated self-referencing
/// writes stay bounded.
pub fn genClampedInt(g: *Gen, d: u32) Error!void {
    if (g.loop_nest > 0) {
        try g.emit("(modulo ");
        try genInt(g, d);
        try g.emitf(" {d})", .{gen_mod.acc_modulus});
    } else {
        try genInt(g, d);
    }
}

// ---------------------------------------------------------------------------
// Booleans and tests (pure)
// ---------------------------------------------------------------------------

const BoolOp = enum {
    lit,
    ref,
    not_op,
    andor,
    cmp,
    zero_p,
    evenodd,
    null_p,
    pair_p,
    eq_sym,
    eqv_int,
    equal_list,
    string_eq,
    char_cmp,
    pred_any,
};

pub fn genBool(g: *Gen, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    var c: Cands(BoolOp) = .{};
    c.add(.lit, 3);
    if (g.hasVar(gen_mod.bindIsBool)) c.add(.ref, 4);
    if (depth > 0) {
        c.add(.not_op, 2);
        c.add(.andor, 3);
        c.add(.cmp, 6);
        c.add(.zero_p, 2);
        c.add(.evenodd, 2);
        c.add(.null_p, 2);
        c.add(.pair_p, 1);
        c.add(.eq_sym, 1);
        c.add(.eqv_int, 2);
        c.add(.equal_list, 2);
        c.add(.string_eq, 1);
        c.add(.char_cmp, 1);
        c.add(.pred_any, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => try g.emit(if (g.ch.chance(.coin, 1, 2)) "#t" else "#f"),
        .ref => try g.emit(g.pickVar(gen_mod.bindIsBool).?.name),
        .not_op => {
            try g.emit("(not ");
            try genTest(g, d);
            try g.emit(")");
        },
        .andor => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and " else "(or ");
            try genBool(g, d);
            try g.emit(" ");
            try genBool(g, d);
            try g.emit(")");
        },
        .cmp => {
            // Exact integers only (flonum comparison would be portable,
            // but keeping flonums out of the grammar entirely is simpler
            // to audit).
            const op = cmp_ops[g.ch.index(.op_pick, cmp_ops.len)];
            try g.emitf("({s} ", .{op});
            try genInt(g, d);
            try g.emit(" ");
            try genInt(g, d);
            try g.emit(")");
        },
        .zero_p => {
            try g.emit("(zero? ");
            try genInt(g, d);
            try g.emit(")");
        },
        .evenodd => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(even? " else "(odd? ");
            try genInt(g, d);
            try g.emit(")");
        },
        .null_p => {
            try g.emit("(null? ");
            _ = try genList(g, d, .{});
            try g.emit(")");
        },
        .pair_p => {
            try g.emit("(pair? ");
            _ = try genList(g, d, .{});
            try g.emit(")");
        },
        .eq_sym => {
            // eq? only on symbols (specified); on numbers it is unspecified.
            try g.emitf("(eq? '{s} '{s})", .{
                gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)],
                gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)],
            });
        },
        .eqv_int => {
            try g.emit("(eqv? ");
            try genInt(g, d);
            try g.emit(" ");
            try genInt(g, d);
            try g.emit(")");
        },
        .equal_list => {
            try g.emit("(equal? ");
            _ = try genList(g, d, .{});
            try g.emit(" ");
            _ = try genList(g, d, .{});
            try g.emit(")");
        },
        .string_eq => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(string=? " else "(string<? ");
            _ = try genString(g, d);
            try g.emit(" ");
            _ = try genString(g, d);
            try g.emit(")");
        },
        .char_cmp => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(char=? " else "(char<? ");
            try genChar(g, d);
            try g.emit(" ");
            try genChar(g, d);
            try g.emit(")");
        },
        .pred_any => {
            try g.emitf("({s} ", .{any_preds[g.ch.index(.op_pick, any_preds.len)]});
            try genAny(g, d);
            try g.emit(")");
        },
    }
}

/// Test position: anything goes — only #f is false, so always-truthy tests
/// are deliberate dead-branch fodder for the optimizer.
pub fn genTest(g: *Gen, d: u32) Error!void {
    if (g.ch.chance(.coin, 3, 5)) return genBool(g, d);
    try genAny(g, d);
}

fn genAny(g: *Gen, d: u32) Error!void {
    const AnyKind = enum { int, boolean, char, sym, string, list, vector, id_lambda };
    var c: Cands(AnyKind) = .{};
    c.add(.int, 4);
    c.add(.boolean, 2);
    c.add(.char, 1);
    c.add(.sym, 1);
    if (d > 0) {
        c.add(.string, 1);
        c.add(.list, 1);
        c.add(.vector, 1);
        c.add(.id_lambda, 1);
    }
    switch (c.pick(g.ch)) {
        .int => try genInt(g, d),
        .boolean => try genBool(g, d),
        .char => try genChar(g, d),
        .sym => try g.emitf("'{s}", .{gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)]}),
        .string => _ = try genString(g, d),
        .list => _ = try genList(g, d, .{}),
        .vector => _ = try genVector(g, d, false),
        .id_lambda => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(lambda ({s}) {s})", .{ names[0], names[0] });
        },
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Names that would mean the program left the four imported libraries or
/// the fully-specified subset (see the module doc for each rule).
const forbidden_fragments = [_][]const u8{
    "(fold", // SRFI-1, not (scheme base)
    "(sqrt", // (scheme inexact)
    "(exact", // only needed for flonum paths, which are out
    "inexact", // no flonums anywhere
    "(raise-continuable",
    "with-exception-handler",
    "(display", // only write/newline produce output
    "(read", // no input
    "current-input", // no port procedures ("current-" alone would match
    "current-output", // call-with-CURRENT-continuation)
    "current-error",
    "(eq? 0", // eq? on numbers is unspecified (symbols only; a literal
    "(eq? 1", // int argument would be a generator bug)
    "(exit",
};

/// Every top-level form must be void-valued; these are the only heads the
/// generator may emit at line start (one top-level form per line).
const allowed_top_prefixes = [_][]const u8{
    "(import ",        "(define ",
    "(define-syntax ", "(set! ",
    "(when ",          "(unless ",
    "(if ",            "(begin ",
    "(let (",          "(write ",
    "(newline)",       "(for-each ",
    "(vector-set! ",   "(string-set! ",
    "(set-car! ",      "(bytevector-u8-set! ",
};

fn assertPortableSubset(src: []const u8) !void {
    // ASCII only: Unicode beyond ASCII is optional in R7RS-small, so any
    // high byte is a portability leak.
    for (src) |byte| try std.testing.expect(byte < 0x80);
    for (forbidden_fragments) |f| {
        try std.testing.expect(std.mem.indexOf(u8, src, f) == null);
    }
    // No flonum literals: a digit is never followed by a decimal point.
    var j: usize = 0;
    while (std.mem.indexOfScalarPos(u8, src, j, '.')) |pos| {
        try std.testing.expect(pos == 0 or !std.ascii.isDigit(src[pos - 1]));
        j = pos + 1;
    }
    var lines = std.mem.splitScalar(u8, src, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (first) {
            try std.testing.expect(std.mem.startsWith(u8, line, "(import "));
            first = false;
        }
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

test "portable-mode fixed-seed programs parse, compile, stay bounded and in subset" {
    const memory = @import("memory.zig");
    const reader_mod = @import("reader.zig");
    const compiler_mod = @import("compiler.zig");
    const types = @import("types.zig");
    const gpa = std.testing.allocator;

    var seed: u64 = 0;
    while (seed < 2000) : (seed += 1) {
        const src = try gen_mod.generatePortableSeeded(seed, gpa);
        defer gpa.free(src);
        errdefer std.debug.print("seed {d} program:\n{s}\n", .{ seed, src });
        try std.testing.expect(src.len < gen_mod.expected_max_bytes);
        try assertPortableSubset(src);

        var gc = memory.GC.init(gpa);
        defer gc.deinit();
        // No VM marks compile-time temporaries as roots here; suppress
        // collection (bounded allocation per seed) as the full-mode test
        // does.
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
            // import is a top-level form handled by vm_eval, not the
            // compiler; skip it (the eval-clean gate in tests_fuzz.zig
            // covers it end to end).
            if (types.isPair(expr) and types.isSymbol(types.car(expr)) and
                std.mem.eql(u8, types.symbolName(types.car(expr)), "import")) continue;
            _ = try compiler_mod.compileExpressionWithMacros(&gc, expr, &macros, &globals);
        }
    }
}

test "portable-mode generation is deterministic per seed" {
    const gpa = std.testing.allocator;
    const a = try gen_mod.generatePortableSeeded(123, gpa);
    defer gpa.free(a);
    const b = try gen_mod.generatePortableSeeded(123, gpa);
    defer gpa.free(b);
    try std.testing.expectEqualStrings(a, b);
}
