//! Integer, boolean, and test expression generators for the R7RS grammar
//! fuzzer (fuzz_gen.zig): `genInt` (the control-form dispatcher — if/cond/
//! case/let/letrec/named-let/do/call-cc/dynamic-wind/guard/…), `genBool`,
//! `genTest`, and their sub-helpers. Split out of fuzz_gen.zig along the
//! expression-domain seam (parallel to fuzz_gen_data.zig's data-kind
//! generators) to stay within the file size policy; fuzz_gen.zig re-exports
//! the public entry points as `Gen` methods, so call sites use
//! `g.genInt(...)` either way. See fuzz_gen.zig for the design notes and
//! bounds.

const std = @import("std");
const gen_mod = @import("fuzz_gen.zig");

const Gen = gen_mod.Gen;
const Error = gen_mod.Error;
const Cands = gen_mod.Cands;
const Kind = gen_mod.Kind;

const bindIsInt = gen_mod.bindIsInt;
const bindIsBool = gen_mod.bindIsBool;
const bindIsProc = gen_mod.bindIsProc;
const bindIsPlainProc = gen_mod.bindIsPlainProc;
const bindIsPlainProc2 = gen_mod.bindIsPlainProc2;
const bindIsVec = gen_mod.bindIsVec;
const bindIsBv = gen_mod.bindIsBv;
const bindIsListIntsExactNonEmpty = gen_mod.bindIsListIntsExactNonEmpty;

const arith_ops = gen_mod.arith_ops;
const div_ops = gen_mod.div_ops;
const cmp_ops = gen_mod.cmp_ops;
const rec_ops = gen_mod.rec_ops;
const fold_ops = gen_mod.fold_ops;
const guard_preds = gen_mod.guard_preds;
const any_preds = gen_mod.any_preds;
const symbol_names = gen_mod.symbol_names;
const real_round_ops = gen_mod.real_round_ops;
const acc_modulus = gen_mod.acc_modulus;

// -- integer expressions --
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
    raise_form,
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
    from_real,
    apply_op,
    fold_op,
};

pub fn genInt(g: *Gen, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    var c: Cands(IntOp) = .{};
    c.add(.lit, 5);
    if (g.hasVar(bindIsInt)) c.add(.ref, 6);
    if (depth > 0) {
        c.add(.arith, 8);
        c.add(.abs_op, 1);
        c.add(.divmod, 3);
        c.add(.if_form, 5);
        c.add(.cond_form, 3);
        c.add(.case_form, 2);
        c.add(.and_or, 2);
        c.add(.let_form, 6);
        c.add(.letrec_lambdas, 2);
        c.add(.inline_call, 2);
        if (g.hasVar(bindIsProc)) c.add(.call_proc, 6);
        if (g.macros.items.len > 0) c.add(.call_macro, 4);
        c.add(.named_let, 4);
        c.add(.do_loop, 3);
        c.add(.letrec_rec, 3);
        c.add(.callcc, 3);
        c.add(.dynwind, 2);
        c.add(.guard_form, 3);
        if (g.guard_depth > 0) c.add(.raise_form, 2);
        c.add(.begin_form, 3);
        if (g.hasVar(bindIsVec)) c.add(.vec_ref, 3);
        if (g.hasVar(bindIsBv)) c.add(.bv_ref, 2);
        c.add(.char_int, 1);
        c.add(.str_len, 1);
        c.add(.list_len, 2);
        c.add(.car_op, 2);
        if (g.hasVar(bindIsListIntsExactNonEmpty)) c.add(.list_ref_op, 2);
        c.add(.force_delay, 1);
        c.add(.cwv, 1);
        c.add(.let_values, 1);
        c.add(.num_roundtrip, 1);
        c.add(.from_real, 1);
        if (g.hasVar(bindIsPlainProc)) c.add(.apply_op, 2);
        c.add(.fold_op, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => try g.emitf("{d}", .{@as(i64, g.ch.range(.lit_pick, 0, 200)) - 100}),
        .ref => try g.emit(g.pickVar(bindIsInt).?.name),
        .arith => {
            const op = arith_ops[g.ch.index(.op_pick, arith_ops.len)];
            const nargs = g.ch.range(.nargs, 2, 3);
            try g.emitf("({s}", .{op});
            for (0..nargs) |_| {
                try g.emit(" ");
                try g.genInt(d);
            }
            try g.emit(")");
        },
        .abs_op => {
            try g.emit("(abs ");
            try g.genInt(d);
            try g.emit(")");
        },
        .divmod => {
            const op = div_ops[g.ch.index(.op_pick, div_ops.len)];
            var divisor: i32 = @intCast(g.ch.range(.lit_pick, 1, 12));
            if (g.ch.chance(.coin, 1, 4)) divisor = -divisor;
            try g.emitf("({s} ", .{op});
            try g.genInt(d);
            try g.emitf(" {d})", .{divisor});
        },
        .if_form => {
            try g.emit("(if ");
            try g.genTest(d);
            try g.emit(" ");
            try g.genInt(d);
            try g.emit(" ");
            try g.genInt(d);
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
                try g.genInt(d);
                try g.emitf(" => (lambda ({s}) ", .{names[0]});
                const mark = g.scope.items.len;
                try g.pushBinding(names[0], .int);
                try g.genInt(d);
                g.scope.shrinkRetainingCapacity(mark);
                try g.emit(")) ");
            } else {
                const nclauses = g.ch.range(.count, 1, 2);
                for (0..nclauses) |_| {
                    try g.emit("(");
                    try g.genTest(d);
                    try g.emit(" ");
                    try g.genInt(d);
                    try g.emit(") ");
                }
            }
            try g.emit("(else ");
            try g.genInt(d);
            try g.emit("))");
        },
        .case_form => {
            try g.emit("(case ");
            try g.genInt(d);
            const nclauses = g.ch.range(.count, 1, 2);
            for (0..nclauses) |_| {
                try g.emit(" ((");
                const ndata = g.ch.range(.count, 1, 3);
                for (0..ndata) |j| {
                    if (j > 0) try g.emit(" ");
                    try g.emitf("{d}", .{@as(i64, g.ch.range(.lit_pick, 0, 40)) - 20});
                }
                try g.emit(") ");
                try g.genInt(d);
                try g.emit(")");
            }
            try g.emit(" (else ");
            try g.genInt(d);
            try g.emit("))");
        },
        .and_or => {
            // With all-integer arguments (never #f), both forms yield an
            // integer while still exercising boolean simplification.
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and" else "(or");
            const nargs = g.ch.range(.nargs, 2, 3);
            for (0..nargs) |_| {
                try g.emit(" ");
                try g.genInt(d);
            }
            try g.emit(")");
        },
        .let_form => try genLetInt(g, d),
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
            try g.genInt(d);
            try g.emit(")");
            g.scope.shrinkRetainingCapacity(mark);
            for (0..arity) |_| {
                try g.emit(" ");
                try g.genInt(d);
            }
            try g.emit(")");
        },
        .call_proc => {
            const b = g.pickVar(bindIsProc).?;
            const info = b.kind.proc;
            var nargs: u32 = info.arity;
            if (info.variadic) nargs += g.ch.range(.nargs, 0, 2);
            try g.emitf("({s}", .{b.name});
            for (0..nargs) |i| {
                try g.emit(" ");
                if (i == 0 and info.bounded_first)
                    try g.emitf("{d}", .{g.ch.range(.iters, 0, 12)})
                else
                    try g.genInt(d);
            }
            try g.emit(")");
        },
        .call_macro => {
            const m = g.macros.items[g.ch.index(.op_pick, g.macros.items.len)];
            const nargs: u32 = if (m.variadic) g.ch.range(.nargs, 0, 3) else m.arity;
            try g.emitf("({s}", .{m.name});
            for (0..nargs) |_| {
                try g.emit(" ");
                try g.genInt(d);
            }
            try g.emit(")");
        },
        .named_let => {
            const iters = g.loopIters();
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emitf("(let lp (({s} {d}) ({s} ", .{ names[0], iters, names[1] });
            try g.genInt(d); // accumulator init: outer scope
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            g.loop_nest += 1;
            try g.emitf(")) (if (<= {s} 0) {s} (lp (- {s} 1) (modulo ", .{ names[0], names[1], names[0] });
            try g.genInt(d);
            try g.emitf(" {d}))))", .{acc_modulus});
            g.loop_nest -= 1;
            g.scope.shrinkRetainingCapacity(mark);
        },
        .do_loop => {
            const iters = g.loopIters();
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emitf("(do (({s} 0 (+ {s} 1)) ({s} ", .{ names[0], names[0], names[1] });
            try g.genInt(d); // accumulator init: outer scope
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            g.loop_nest += 1;
            try g.emit(" (modulo ");
            try g.genInt(d);
            try g.emitf(" {d}))) ((>= {s} {d}) {s})", .{ acc_modulus, names[0], iters, names[1] });
            if (g.ch.chance(.coin, 1, 2)) {
                try g.emit(" ");
                try g.genStmt(d);
            }
            try g.emit(")");
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
            try g.genInt(d);
            try g.emitf(" ({s} ", .{op});
            try g.genInt(d);
            try g.emitf(" ({s} (- {s} 1))))))) ({s} {d}))", .{ names[0], names[1], names[0], g.ch.range(.iters, 0, 12) });
            g.scope.shrinkRetainingCapacity(mark);
        },
        .callcc => {
            const nm = if (g.ch.chance(.coin, 1, 6)) "call-with-current-continuation" else "call/cc";
            try g.emitf("({s} (lambda (k) ", .{nm});
            const mark = g.scope.items.len;
            try g.pushBinding("k", .{ .proc = .{ .arity = 1 } });
            if (g.ch.chance(.coin, 1, 2)) {
                // guaranteed conditional escape
                try g.emit("(if ");
                try g.genTest(d);
                try g.emit(" (k ");
                try g.genInt(d);
                try g.emit(") ");
                try g.genInt(d);
                try g.emit(")");
            } else {
                try g.genInt(d);
            }
            try g.emit("))");
            g.scope.shrinkRetainingCapacity(mark);
        },
        .dynwind => {
            try g.emit("(dynamic-wind (lambda () ");
            try genThunkBody(g, d);
            try g.emit(") (lambda () ");
            try g.genInt(d);
            try g.emit(") (lambda () ");
            try genThunkBody(g, d);
            try g.emit("))");
        },
        .guard_form => {
            try g.emit("(guard (ex");
            const nclauses = g.ch.range(.count, 0, 2);
            for (0..nclauses) |_| {
                const pred = guard_preds[g.ch.index(.op_pick, guard_preds.len)];
                try g.emitf(" (({s} ex) ", .{pred});
                try g.genInt(d);
                try g.emit(")");
            }
            if (nclauses == 0 or g.ch.chance(.coin, 7, 8)) {
                try g.emit(" (else ");
                try g.genInt(d);
                try g.emit(")");
            }
            try g.emit(") ");
            g.guard_depth += 1;
            if (g.ch.chance(.coin, 1, 3)) {
                // guaranteed conditional raise
                try g.emit("(if ");
                try g.genTest(d);
                try g.emit(" ");
                try genRaise(g, d);
                try g.emit(" ");
                try g.genInt(d);
                try g.emit(")");
            } else {
                try g.genInt(d);
            }
            g.guard_depth -= 1;
            try g.emit(")");
        },
        .raise_form => try genRaise(g, d),
        .begin_form => {
            try g.emit("(begin ");
            const n = g.ch.range(.count, 1, 2);
            for (0..n) |_| {
                try g.genStmt(d);
                try g.emit(" ");
            }
            try g.genInt(d);
            try g.emit(")");
        },
        .vec_ref => {
            const b = g.pickVar(bindIsVec).?;
            const v = b.kind.vector;
            // Boxed slots hold non-empty int lists, so car is safe.
            try g.emit(if (v.boxed) "(car (vector-ref " else "(vector-ref ");
            try g.emit(b.name);
            try g.emit(" ");
            try g.genIndex(d, v.len);
            try g.emit(if (v.boxed) "))" else ")");
        },
        .bv_ref => {
            const b = g.pickVar(bindIsBv).?;
            try g.emitf("(bytevector-u8-ref {s} ", .{b.name});
            try g.genIndex(d, b.kind.bytevector);
            try g.emit(")");
        },
        .char_int => {
            try g.emit("(char->integer ");
            try g.genChar(d);
            try g.emit(")");
        },
        .str_len => {
            try g.emit("(string-length ");
            _ = try g.genString(d);
            try g.emit(")");
        },
        .list_len => {
            try g.emit("(length ");
            _ = try g.genList(d, .{});
            try g.emit(")");
        },
        .car_op => {
            try g.emit("(car ");
            _ = try g.genList(d, .{ .ints = true, .non_empty = true });
            try g.emit(")");
        },
        .list_ref_op => {
            const b = g.pickVar(bindIsListIntsExactNonEmpty).?;
            const len = b.kind.list.len.exactLen().?;
            try g.emitf("(list-ref {s} {d})", .{ b.name, g.ch.range(.idx_pick, 0, len - 1) });
        },
        .force_delay => {
            try g.emit("(force (delay ");
            try g.genInt(d);
            try g.emit("))");
        },
        .cwv => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emit("(call-with-values (lambda () (values ");
            try g.genInt(d);
            try g.emit(" ");
            try g.genInt(d);
            try g.emitf(")) (lambda ({s} {s}) ", .{ names[0], names[1] });
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            try g.genInt(d);
            try g.emit("))");
            g.scope.shrinkRetainingCapacity(mark);
        },
        .let_values => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(2, &nb);
            try g.emitf("(let-values ((({s} {s}) (values ", .{ names[0], names[1] });
            try g.genInt(d);
            try g.emit(" ");
            try g.genInt(d);
            try g.emit("))) ");
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.pushBinding(names[1], .int);
            try g.genInt(d);
            try g.emit(")");
            g.scope.shrinkRetainingCapacity(mark);
        },
        .num_roundtrip => {
            try g.emit("(string->number (number->string ");
            try g.genInt(d);
            try g.emit("))");
        },
        .from_real => {
            const op = real_round_ops[g.ch.index(.op_pick, real_round_ops.len)];
            try g.emitf("(exact ({s} ", .{op});
            try g.genReal(2);
            try g.emit("))");
        },
        .apply_op => {
            const b = g.pickVar(bindIsPlainProc).?;
            try g.emitf("(apply {s} (list", .{b.name});
            for (0..b.kind.proc.arity) |_| {
                try g.emit(" ");
                try g.genInt(d);
            }
            try g.emit("))");
        },
        .fold_op => {
            try g.emit("(fold ");
            if (g.hasVar(bindIsPlainProc2) and g.ch.chance(.coin, 1, 2)) {
                try g.emit(g.pickVar(bindIsPlainProc2).?.name);
            } else if (g.ch.chance(.coin, 1, 3)) {
                try g.genLambdaInt(2, false, d);
            } else {
                try g.emit(fold_ops[g.ch.index(.op_pick, fold_ops.len)]);
            }
            try g.emit(" ");
            try g.genInt(d);
            try g.emit(" ");
            _ = try g.genList(d, .{ .ints = true });
            try g.emit(")");
        },
    }
}

/// Vector/bytevector index that is in range by construction: either a
/// literal below `len` or `(modulo <int> len)`.
pub fn genIndex(g: *Gen, d: u32, len: u16) Error!void {
    if (g.ch.chance(.idx_kind, 2, 3)) {
        try g.emitf("{d}", .{g.ch.range(.idx_pick, 0, len - 1)});
    } else {
        try g.emit("(modulo ");
        try g.genInt(@min(d, 1));
        try g.emitf(" {d})", .{len});
    }
}

fn genRaise(g: *Gen, d: u32) Error!void {
    switch (g.ch.range(.shape, 0, 2)) {
        0 => try g.emitf("(raise {d})", .{@as(i64, g.ch.range(.lit_pick, 0, 200)) - 100}),
        1 => try g.emitf("(raise '{s})", .{symbol_names[g.ch.index(.lit_pick, symbol_names.len)]}),
        else => {
            try g.emit("(error \"fuzz\" ");
            try g.genInt(@min(d, 1));
            try g.emit(")");
        },
    }
}

fn genThunkBody(g: *Gen, d: u32) Error!void {
    if (g.ch.chance(.coin, 1, 2)) try g.genStmt(d) else try g.emit("0");
}

fn genLetInt(g: *Gen, d: u32) Error!void {
    const star = g.ch.chance(.coin, 1, 2);
    const n = g.ch.range(.count, 1, 3);
    var nb: [4][]const u8 = undefined;
    const names = g.pickNames(n, &nb);
    try g.emit(if (star) "(let* (" else "(let (");
    const mark = g.scope.items.len;
    var stash: [3]Kind = undefined;
    for (0..n) |i| {
        try g.emitf("({s} ", .{names[i]});
        const kind = try g.genValueOfKind(g.pickBindKind(), d);
        try g.emit(") ");
        // let: inits are evaluated in the outer scope, so bindings only
        // become visible after all of them; let*: immediately.
        if (star) try g.pushBinding(names[i], kind) else stash[i] = kind;
    }
    if (!star) for (0..n) |i| try g.pushBinding(names[i], stash[i]);
    try g.emit(") ");
    if (g.ch.chance(.coin, 1, 3)) {
        try g.genStmt(d);
        try g.emit(" ");
    }
    try g.genInt(d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

fn genLetrecLambdas(g: *Gen, d: u32) Error!void {
    // General letrec with lambda initializers. Bodies see only the outer
    // scope: sibling references would enable unbounded mutual recursion;
    // bounded recursion is exercised by the letrec_rec skeleton instead.
    const n = g.ch.range(.count, 1, 2);
    var nb: [4][]const u8 = undefined;
    const names = g.pickNames(n, &nb);
    try g.emit("(letrec (");
    const mark = g.scope.items.len;
    // letrec scope covers the initializers too: reserve the binder
    // names so lambda bodies can neither pick shadowed outer bindings
    // nor call a sibling (unbounded mutual recursion).
    for (0..n) |i| try g.pushBinding(names[i], .reserved);
    var stash: [2]Kind = undefined;
    for (0..n) |i| {
        const arity: u8 = @intCast(g.ch.range(.arity, 0, 2));
        try g.emitf("({s} ", .{names[i]});
        try g.genLambdaInt(arity, false, d);
        try g.emit(") ");
        stash[i] = .{ .proc = .{ .arity = arity } };
    }
    for (0..n) |i| g.scope.items[mark + i].kind = stash[i];
    try g.emit(") ");
    try g.genInt(d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

/// (lambda (p...) <int body>), optionally variadic: (lambda (p... . rest) ...)
/// or (lambda rest ...) when arity is 0.
pub fn genLambdaInt(g: *Gen, arity: u8, variadic: bool, d: u32) Error!void {
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
    if (g.ch.chance(.coin, 1, 4)) {
        try g.genStmt(d);
        try g.emit(" ");
    }
    try g.genInt(d);
    try g.emit(")");
    g.scope.shrinkRetainingCapacity(mark);
}

// -- booleans and tests --

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
    if (g.hasVar(bindIsBool)) c.add(.ref, 4);
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
        .ref => try g.emit(g.pickVar(bindIsBool).?.name),
        .not_op => {
            try g.emit("(not ");
            try g.genTest(d);
            try g.emit(")");
        },
        .andor => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and " else "(or ");
            try g.genBool(d);
            try g.emit(" ");
            try g.genBool(d);
            try g.emit(")");
        },
        .cmp => {
            const op = cmp_ops[g.ch.index(.op_pick, cmp_ops.len)];
            const real = g.ch.chance(.coin, 1, 4);
            try g.emitf("({s} ", .{op});
            if (real) try g.genReal(d) else try g.genInt(d);
            try g.emit(" ");
            if (real) try g.genReal(d) else try g.genInt(d);
            try g.emit(")");
        },
        .zero_p => {
            try g.emit("(zero? ");
            try g.genInt(d);
            try g.emit(")");
        },
        .evenodd => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(even? " else "(odd? ");
            try g.genInt(d);
            try g.emit(")");
        },
        .null_p => {
            try g.emit("(null? ");
            _ = try g.genList(d, .{});
            try g.emit(")");
        },
        .pair_p => {
            try g.emit("(pair? ");
            _ = try g.genList(d, .{});
            try g.emit(")");
        },
        .eq_sym => {
            try g.emitf("(eq? '{s} '{s})", .{
                symbol_names[g.ch.index(.lit_pick, symbol_names.len)],
                symbol_names[g.ch.index(.lit_pick, symbol_names.len)],
            });
        },
        .eqv_int => {
            try g.emit("(eqv? ");
            try g.genInt(d);
            try g.emit(" ");
            try g.genInt(d);
            try g.emit(")");
        },
        .equal_list => {
            try g.emit("(equal? ");
            _ = try g.genList(d, .{});
            try g.emit(" ");
            _ = try g.genList(d, .{});
            try g.emit(")");
        },
        .string_eq => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(string=? " else "(string<? ");
            _ = try g.genString(d);
            try g.emit(" ");
            _ = try g.genString(d);
            try g.emit(")");
        },
        .char_cmp => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(char=? " else "(char<? ");
            try g.genChar(d);
            try g.emit(" ");
            try g.genChar(d);
            try g.emit(")");
        },
        .pred_any => {
            try g.emitf("({s} ", .{any_preds[g.ch.index(.op_pick, any_preds.len)]});
            try genAny(g, d);
            try g.emit(")");
        },
    }
}

/// Test position: anything goes — only #f is false, so always-truthy
/// tests are deliberate dead-branch fodder for the optimizer.
pub fn genTest(g: *Gen, d: u32) Error!void {
    if (g.ch.chance(.coin, 3, 5)) return g.genBool(d);
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
        .int => try g.genInt(d),
        .boolean => try g.genBool(d),
        .char => try g.genChar(d),
        .sym => try g.emitf("'{s}", .{symbol_names[g.ch.index(.lit_pick, symbol_names.len)]}),
        .string => _ = try g.genString(d),
        .list => _ = try g.genList(d, .{}),
        .vector => _ = try g.genVector(d, false),
        .id_lambda => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(lambda ({s}) {s})", .{ names[0], names[0] });
        },
    }
}

/// Integer write target: inside loops, clamp so repeated self-referencing
/// writes (e.g. squaring an accumulator every iteration) stay bounded.
pub fn genClampedInt(g: *Gen, d: u32) Error!void {
    if (g.loop_nest > 0) {
        try g.emit("(modulo ");
        try g.genInt(d);
        try g.emitf(" {d})", .{acc_modulus});
    } else {
        try g.genInt(d);
    }
}
