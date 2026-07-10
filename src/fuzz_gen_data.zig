//! Data-kind expression generators for the R7RS grammar fuzzer
//! (fuzz_gen.zig): characters, strings, lists, quasiquote templates,
//! vectors, bytevectors, and inexact reals. Split out of fuzz_gen.zig
//! along the grammar-domain seam to stay within the file size policy;
//! fuzz_gen.zig re-exports these as `Gen` methods, so call sites use
//! `g.genList(...)` either way. See fuzz_gen.zig for the design notes
//! and bounds.

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
const bindIsChar = gen_mod.bindIsChar;
const bindIsString = gen_mod.bindIsString;
const bindIsStringIndexable = gen_mod.bindIsStringIndexable;
const bindIsStringExact = gen_mod.bindIsStringExact;
const bindIsIntVec = gen_mod.bindIsIntVec;
const bindIsVec = gen_mod.bindIsVec;
const bindIsBv = gen_mod.bindIsBv;
const bindIsListIntsExactNonEmpty = gen_mod.bindIsListIntsExactNonEmpty;
const bindIsListMutNonEmpty = gen_mod.bindIsListMutNonEmpty;
const bindIsSettableAtom = gen_mod.bindIsSettableAtom;
const bindIsSettableInt = gen_mod.bindIsSettableInt;
const bindIsStringSettable = gen_mod.bindIsStringSettable;
const symbol_names = gen_mod.symbol_names;
const real_round_ops = gen_mod.real_round_ops;
const acc_modulus = gen_mod.acc_modulus;

const char_lits = [_][]const u8{ "#\\a", "#\\b", "#\\z", "#\\0", "#\\space", "#\\newline", "#\\x3BB" };
const string_lits = [_]struct { text: []const u8, len: u16 }{
    .{ .text = "\"\"", .len = 0 },
    .{ .text = "\"abc\"", .len = 3 },
    .{ .text = "\"fuzz\"", .len = 4 },
    .{ .text = "\"aλb\"", .len = 3 }, // multi-byte codepoint: UTF-8 index paths
    .{ .text = "\"x y!\"", .len = 5 },
};
const flonum_lits = [_][]const u8{ "0.5", "-1.5", "2.25", "3.5", "-0.25", "100.0", "0.0" };
const flonum_divisors = [_][]const u8{ "2.0", "4.0", "-8.0", "0.5" };
const real_arith_ops = [_][]const u8{ "+", "-", "*", "min", "max" };

fn listVarPred(comptime ints: bool, comptime non_empty: bool) fn (Binding) bool {
    return struct {
        fn match(b: Binding) bool {
            return switch (b.kind) {
                .list => |l| (!ints or l.ints) and (!non_empty or l.len.nonEmpty()),
                else => false,
            };
        }
    }.match;
}
fn cdrVarPred(comptime ints: bool, comptime non_empty: bool) fn (Binding) bool {
    return struct {
        fn match(b: Binding) bool {
            return switch (b.kind) {
                .list => |l| (!ints or l.ints) and
                    l.len.exactLen() != null and
                    l.len.exactLen().? >= (if (non_empty) @as(u16, 2) else 1),
                else => false,
            };
        }
    }.match;
}
// -- characters --

pub fn genChar(g: *Gen, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    const CharOp = enum { lit, ref, int_to, str_ref, changecase };
    var c: Cands(CharOp) = .{};
    c.add(.lit, 4);
    if (g.hasVar(bindIsChar)) c.add(.ref, 3);
    if (depth > 0) {
        c.add(.int_to, 2);
        c.add(.changecase, 1);
        if (g.hasVar(bindIsStringIndexable)) c.add(.str_ref, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => try g.emit(char_lits[g.ch.index(.lit_pick, char_lits.len)]),
        .ref => try g.emit(g.pickVar(bindIsChar).?.name),
        .int_to => {
            try g.emit("(integer->char (+ 97 (modulo ");
            try g.genInt(d);
            try g.emit(" 26)))");
        },
        .str_ref => {
            const b = g.pickVar(bindIsStringIndexable).?;
            try g.emitf("(string-ref {s} ", .{b.name});
            try g.genIndex(d, b.kind.string.len.?);
            try g.emit(")");
        },
        .changecase => {
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(char-upcase " else "(char-downcase ");
            try g.genChar(d);
            try g.emit(")");
        },
    }
}

// -- strings --

pub fn genString(g: *Gen, depth_in: u32) Error!StrInfo {
    const depth = g.cap(depth_in);
    const StrOp = enum { lit, ref, make, ctor, append, copy, substr, num2str };
    var c: Cands(StrOp) = .{};
    c.add(.lit, 3);
    if (g.hasVar(bindIsString)) c.add(.ref, 4);
    if (depth > 0) {
        c.add(.make, 2);
        c.add(.ctor, 2);
        c.add(.append, 3);
        c.add(.copy, 1);
        c.add(.num2str, 2);
        if (g.hasVar(bindIsStringExact)) c.add(.substr, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => {
            const l = string_lits[g.ch.index(.lit_pick, string_lits.len)];
            try g.emit(l.text);
            return .{ .len = l.len, .mutable = false };
        },
        .ref => {
            const b = g.pickVar(bindIsString).?;
            try g.emit(b.name);
            return b.kind.string;
        },
        .make => {
            const k: u16 = @intCast(g.ch.range(.len_pick, 0, 8));
            try g.emitf("(make-string {d} ", .{k});
            try g.genChar(d);
            try g.emit(")");
            return .{ .len = k, .mutable = true };
        },
        .ctor => {
            const k: u16 = @intCast(g.ch.range(.len_pick, 1, 4));
            try g.emit("(string");
            for (0..k) |_| {
                try g.emit(" ");
                try g.genChar(d);
            }
            try g.emit(")");
            return .{ .len = k, .mutable = true };
        },
        .append => {
            try g.emit("(string-append ");
            const a = try g.genString(d);
            try g.emit(" ");
            const b = try g.genString(d);
            try g.emit(")");
            const len: ?u16 = if (a.len != null and b.len != null) a.len.? + b.len.? else null;
            return .{ .len = len, .mutable = true };
        },
        .copy => {
            try g.emit("(string-copy ");
            const a = try g.genString(d);
            try g.emit(")");
            return .{ .len = a.len, .mutable = true };
        },
        .substr => {
            const b = g.pickVar(bindIsStringExact).?;
            const len = b.kind.string.len.?;
            const from: u16 = @intCast(g.ch.range(.idx_pick, 0, len));
            const to: u16 = @intCast(g.ch.range(.idx_pick, from, len));
            try g.emitf("(substring {s} {d} {d})", .{ b.name, from, to });
            return .{ .len = to - from, .mutable = true };
        },
        .num2str => {
            try g.emit("(number->string ");
            try g.genInt(d);
            try g.emit(")");
            return .{ .len = null, .mutable = true };
        },
    }
}

// -- lists --

pub fn pickListVar(g: *Gen, need: ListNeed) ?Binding {
    if (need.ints) {
        if (need.non_empty) return g.pickVar(listVarPred(true, true));
        return g.pickVar(listVarPred(true, false));
    }
    if (need.non_empty) return g.pickVar(listVarPred(false, true));
    return g.pickVar(listVarPred(false, false));
}

pub fn listVarAvail(g: *Gen, need: ListNeed) bool {
    if (need.ints) {
        if (need.non_empty) return g.hasVar(listVarPred(true, true));
        return g.hasVar(listVarPred(true, false));
    }
    if (need.non_empty) return g.hasVar(listVarPred(false, true));
    return g.hasVar(listVarPred(false, false));
}

pub fn pickCdrVar(g: *Gen, need: ListNeed) ?Binding {
    if (need.ints) {
        if (need.non_empty) return g.pickVar(cdrVarPred(true, true));
        return g.pickVar(cdrVarPred(true, false));
    }
    if (need.non_empty) return g.pickVar(cdrVarPred(false, true));
    return g.pickVar(cdrVarPred(false, false));
}

pub fn cdrVarAvail(g: *Gen, need: ListNeed) bool {
    if (need.ints) {
        if (need.non_empty) return g.hasVar(cdrVarPred(true, true));
        return g.hasVar(cdrVarPred(true, false));
    }
    if (need.non_empty) return g.hasVar(cdrVarPred(false, true));
    return g.hasVar(cdrVarPred(false, false));
}

pub fn genList(g: *Gen, depth_in: u32, need: ListNeed) Error!ListInfo {
    const depth = g.cap(depth_in);
    const ListOp = enum {
        ctor,
        empty_lit,
        quote_lit,
        ref,
        cons_op,
        cdr_op,
        append_op,
        reverse_op,
        map_op,
        vec2list,
        quasi,
    };
    var c: Cands(ListOp) = .{};
    c.add(.ctor, 5);
    if (!need.non_empty) c.add(.empty_lit, 1);
    c.add(.quote_lit, 2);
    if (g.listVarAvail(need)) c.add(.ref, 4);
    if (depth > 0) {
        c.add(.cons_op, 3);
        if (g.cdrVarAvail(need)) c.add(.cdr_op, 2);
        c.add(.append_op, 2);
        c.add(.reverse_op, 2);
        c.add(.map_op, 3);
        if (g.hasVar(bindIsIntVec)) c.add(.vec2list, 2);
        if (!need.ints) c.add(.quasi, 3);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .ctor => {
            const min: u32 = if (need.non_empty) 1 else 0;
            const n = g.ch.range(.len_pick, min, 4);
            try g.emit("(list");
            for (0..n) |_| {
                try g.emit(" ");
                try g.genInt(d);
            }
            try g.emit(")");
            return .{ .len = .{ .exact = @intCast(n) }, .mut = .all, .ints = true };
        },
        .empty_lit => {
            try g.emit("'()");
            return .{ .len = .{ .exact = 0 }, .mut = .none, .ints = true };
        },
        .quote_lit => {
            const n = g.ch.range(.len_pick, 1, 5);
            try g.emit("'(");
            for (0..n) |j| {
                if (j > 0) try g.emit(" ");
                try g.emitf("{d}", .{@as(i64, g.ch.range(.lit_pick, 0, 200)) - 100});
            }
            try g.emit(")");
            return .{ .len = .{ .exact = @intCast(n) }, .mut = .none, .ints = true };
        },
        .ref => {
            const b = g.pickListVar(need).?;
            try g.emit(b.name);
            return b.kind.list;
        },
        .cons_op => {
            try g.emit("(cons ");
            try g.genInt(d);
            try g.emit(" ");
            const tail = try g.genList(d, .{ .ints = need.ints });
            try g.emit(")");
            // The head cell is fresh (set-car! safe), but the spine is the
            // tail's cells: cdr onto it stays writable only if the tail was
            // fully fresh (review finding on PR #1403).
            return .{
                .len = tail.len.plusOne(),
                .mut = if (tail.mut == .all) .all else .head,
                .ints = tail.ints,
            };
        },
        .cdr_op => {
            const b = g.pickCdrVar(need).?;
            const info = b.kind.list;
            try g.emitf("(cdr {s})", .{b.name});
            // The result's first cell is the source's second: writable only
            // when every source cell is known-fresh.
            return .{
                .len = .{ .exact = info.len.exactLen().? - 1 },
                .mut = if (info.mut == .all) .all else .none,
                .ints = info.ints,
            };
        },
        .append_op => {
            try g.emit("(append ");
            const a = try g.genList(d, .{ .ints = need.ints });
            try g.emit(" ");
            const b = try g.genList(d, .{ .ints = need.ints, .non_empty = need.non_empty });
            try g.emit(")");
            // append copies every argument except the last and shares the
            // last (R7RS 6.4): all cells are fresh iff the shared tail's
            // are; the head cell is fresh iff the first list is known
            // non-empty (otherwise the result may BE the second list).
            const mut: gen_mod.Mut = if (b.mut == .all)
                .all
            else if (a.len.nonEmpty())
                .head
            else
                .none;
            return .{ .len = Len.sum(a.len, b.len), .mut = mut, .ints = a.ints and b.ints };
        },
        .reverse_op => {
            try g.emit("(reverse ");
            const a = try g.genList(d, need);
            try g.emit(")");
            return .{ .len = a.len, .mut = .all, .ints = a.ints };
        },
        .map_op => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(map (lambda ({s}) ", .{names[0]});
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.genInt(d);
            g.scope.shrinkRetainingCapacity(mark);
            try g.emit(") ");
            const src = try g.genList(d, .{ .ints = true, .non_empty = need.non_empty });
            try g.emit(")");
            return .{ .len = src.len, .mut = .all, .ints = true };
        },
        .vec2list => {
            const b = g.pickVar(bindIsIntVec).?;
            try g.emitf("(vector->list {s})", .{b.name});
            return .{ .len = .{ .exact = b.kind.vector.len }, .mut = .all, .ints = true };
        },
        .quasi => return genQuasi(g, depth, need.non_empty),
    }
}

/// Quasiquote template: mixed atoms, unquotes, splices, nested data.
/// Result is a proper list, but heterogeneous and conservatively
/// immutable — usable for length/reverse/append/equal?.
pub fn genQuasi(g: *Gen, depth: u32, non_empty: bool) Error!ListInfo {
    const d = depth -| 1;
    const n = g.ch.range(.len_pick, if (non_empty) 1 else 0, 4);
    try g.emit("`(");
    var len: Len = .{ .exact = 0 };
    for (0..n) |i| {
        if (i > 0) try g.emit(" ");
        // The first element of a non-empty template must not be a splice
        // (a splice can contribute zero elements).
        const hi: u32 = if (i == 0 and non_empty) 3 else 4;
        switch (g.ch.range(.shape, 0, hi)) {
            0 => {
                try g.emitf("{d}", .{@as(i64, g.ch.range(.lit_pick, 0, 40)) - 20});
                len = len.plusOne();
            },
            1 => {
                try g.emit(symbol_names[g.ch.index(.lit_pick, symbol_names.len)]);
                len = len.plusOne();
            },
            2 => {
                try g.emit(",");
                try g.genInt(d);
                len = len.plusOne();
            },
            3 => {
                // nested data: sub-list or a level-2 quasiquote whose
                // inner unquote is never evaluated (any symbol is fine)
                if (g.ch.chance(.coin, 1, 3)) {
                    try g.emitf("`({s} ,{s})", .{
                        symbol_names[g.ch.index(.lit_pick, symbol_names.len)],
                        symbol_names[g.ch.index(.lit_pick, symbol_names.len)],
                    });
                } else {
                    try g.emitf("({s} {d})", .{
                        symbol_names[g.ch.index(.lit_pick, symbol_names.len)],
                        @as(i64, g.ch.range(.lit_pick, 0, 40)) - 20,
                    });
                }
                len = len.plusOne();
            },
            else => {
                try g.emit(",@");
                const inner = try g.genList(d, .{});
                len = Len.sum(len, inner.len);
            },
        }
    }
    try g.emit(")");
    return .{ .len = len, .mut = .none, .ints = false };
}

// -- vectors --

pub fn genVector(g: *Gen, depth_in: u32, need_ints: bool) Error!VecInfo {
    const depth = g.cap(depth_in);
    const VecOp = enum { ctor, make, ref, vmap, list2vec };
    var c: Cands(VecOp) = .{};
    c.add(.ctor, 4);
    c.add(.make, 3);
    if (need_ints) {
        if (g.hasVar(bindIsIntVec)) c.add(.ref, 4);
    } else {
        if (g.hasVar(bindIsVec)) c.add(.ref, 4);
    }
    if (depth > 0) {
        c.add(.vmap, 2);
        if (g.hasVar(bindIsListIntsExactNonEmpty)) c.add(.list2vec, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .ctor => {
            const n: u16 = @intCast(g.ch.range(.len_pick, 1, 5));
            const boxed = !need_ints and g.ch.chance(.coin, 1, 4);
            try g.emit("(vector");
            for (0..n) |_| {
                try g.emit(" ");
                if (boxed) _ = try g.genList(d, .{ .ints = true, .non_empty = true }) else try g.genInt(d);
            }
            try g.emit(")");
            return .{ .len = n, .boxed = boxed };
        },
        .make => {
            const n: u16 = @intCast(g.ch.range(.len_pick, 1, 6));
            const boxed = !need_ints and g.ch.chance(.coin, 1, 4);
            try g.emitf("(make-vector {d} ", .{n});
            if (boxed) _ = try g.genList(d, .{ .ints = true, .non_empty = true }) else try g.genInt(d);
            try g.emit(")");
            return .{ .len = n, .boxed = boxed };
        },
        .ref => {
            const b = (if (need_ints) g.pickVar(bindIsIntVec) else g.pickVar(bindIsVec)).?;
            try g.emit(b.name);
            return b.kind.vector;
        },
        .vmap => {
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(vector-map (lambda ({s}) ", .{names[0]});
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try g.genInt(d);
            g.scope.shrinkRetainingCapacity(mark);
            try g.emit(") ");
            const src = try g.genVector(d, true);
            try g.emit(")");
            return .{ .len = src.len, .boxed = false };
        },
        .list2vec => {
            const b = g.pickVar(bindIsListIntsExactNonEmpty).?;
            try g.emitf("(list->vector {s})", .{b.name});
            return .{ .len = b.kind.list.len.exactLen().?, .boxed = false };
        },
    }
}

// -- bytevectors --

pub fn genBytevector(g: *Gen, depth_in: u32) Error!u16 {
    const depth = g.cap(depth_in);
    const BvOp = enum { ctor, make, ref };
    var c: Cands(BvOp) = .{};
    c.add(.ctor, 3);
    c.add(.make, 3);
    if (g.hasVar(bindIsBv)) c.add(.ref, 3);
    _ = depth;
    switch (c.pick(g.ch)) {
        .ctor => {
            const n: u16 = @intCast(g.ch.range(.len_pick, 1, 6));
            try g.emit("(bytevector");
            for (0..n) |_| {
                try g.emitf(" {d}", .{g.ch.range(.lit_pick, 0, 255)});
            }
            try g.emit(")");
            return n;
        },
        .make => {
            const n: u16 = @intCast(g.ch.range(.len_pick, 1, 8));
            try g.emitf("(make-bytevector {d} {d})", .{ n, g.ch.range(.lit_pick, 0, 255) });
            return n;
        },
        .ref => {
            const b = g.pickVar(bindIsBv).?;
            try g.emit(b.name);
            return b.kind.bytevector;
        },
    }
}

// -- reals (flonum paths) --

pub fn genReal(g: *Gen, depth_in: u32) Error!void {
    // Shallow by design: keeps magnitudes finite so `(exact (round ...))`
    // upstream never sees an infinity.
    const depth = @min(g.cap(depth_in), 2);
    const RealOp = enum { lit, from_int, arith, div, sqrt_abs, round_op };
    var c: Cands(RealOp) = .{};
    c.add(.lit, 3);
    c.add(.from_int, 3);
    if (depth > 0) {
        c.add(.arith, 3);
        c.add(.div, 2);
        c.add(.sqrt_abs, 1);
        c.add(.round_op, 1);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => try g.emit(flonum_lits[g.ch.index(.lit_pick, flonum_lits.len)]),
        .from_int => {
            try g.emit("(inexact ");
            try g.genInt(d);
            try g.emit(")");
        },
        .arith => {
            const op = real_arith_ops[g.ch.index(.op_pick, real_arith_ops.len)];
            try g.emitf("({s} ", .{op});
            try g.genReal(d);
            try g.emit(" ");
            try g.genReal(d);
            try g.emit(")");
        },
        .div => {
            // Flonum divisor: division is total (no exact zero divide).
            try g.emit("(/ ");
            try g.genReal(d);
            try g.emitf(" {s})", .{flonum_divisors[g.ch.index(.lit_pick, flonum_divisors.len)]});
        },
        .sqrt_abs => {
            try g.emit("(sqrt (abs ");
            try g.genReal(d);
            try g.emit("))");
        },
        .round_op => {
            try g.emitf("({s} ", .{real_round_ops[g.ch.index(.op_pick, real_round_ops.len)]});
            try g.genReal(d);
            try g.emit(")");
        },
    }
}

// -- statements (side effects) --

pub fn genStmt(g: *Gen, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    const StmtOp = enum {
        expr_stmt,
        set_var,
        vector_set,
        bv_set,
        string_set,
        setcar,
        foreach,
        when_form,
        begin2,
    };
    var c: Cands(StmtOp) = .{};
    c.add(.expr_stmt, 2);
    if (g.hasVar(bindIsSettableAtom)) c.add(.set_var, 6);
    if (g.hasVar(bindIsVec)) c.add(.vector_set, 5);
    if (g.hasVar(bindIsBv)) c.add(.bv_set, 3);
    if (g.hasVar(bindIsStringSettable)) c.add(.string_set, 4);
    if (g.hasVar(bindIsListMutNonEmpty)) c.add(.setcar, 3);
    if (depth > 0) {
        if (g.hasVar(bindIsSettableInt)) c.add(.foreach, 2);
        c.add(.when_form, 3);
        c.add(.begin2, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .expr_stmt => try g.genInt(depth),
        .set_var => {
            const b = g.pickVar(bindIsSettableAtom).?;
            try g.emitf("(set! {s} ", .{b.name});
            switch (b.kind) {
                .int => try g.genClampedInt(d),
                .boolean => try g.genBool(d),
                .char => try g.genChar(d),
                else => unreachable,
            }
            try g.emit(")");
        },
        .vector_set => {
            const b = g.pickVar(bindIsVec).?;
            const v = b.kind.vector;
            try g.emitf("(vector-set! {s} ", .{b.name});
            try g.genIndex(d, v.len);
            try g.emit(" ");
            if (v.boxed) {
                _ = try g.genList(d, .{ .ints = true, .non_empty = true });
            } else {
                try g.genClampedInt(d);
            }
            try g.emit(")");
        },
        .bv_set => {
            const b = g.pickVar(bindIsBv).?;
            try g.emitf("(bytevector-u8-set! {s} ", .{b.name});
            try g.genIndex(d, b.kind.bytevector);
            try g.emit(" (modulo ");
            try g.genInt(d);
            try g.emit(" 256))");
        },
        .string_set => {
            const b = g.pickVar(bindIsStringSettable).?;
            try g.emitf("(string-set! {s} ", .{b.name});
            try g.genIndex(d, b.kind.string.len.?);
            try g.emit(" ");
            try g.genChar(d);
            try g.emit(")");
        },
        .setcar => {
            const b = g.pickVar(bindIsListMutNonEmpty).?;
            try g.emitf("(set-car! {s} ", .{b.name});
            try g.genClampedInt(d);
            try g.emit(")");
        },
        .foreach => {
            const tgt = g.pickVar(bindIsSettableInt).?;
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(for-each (lambda ({s}) (set! {s} (modulo ", .{ names[0], tgt.name });
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            g.loop_nest += 1;
            try g.genInt(d);
            g.loop_nest -= 1;
            g.scope.shrinkRetainingCapacity(mark);
            try g.emitf(" {d}))) ", .{acc_modulus});
            _ = try g.genList(d, .{ .ints = true });
            try g.emit(")");
        },
        .when_form => {
            try g.emit(if (g.ch.chance(.coin, 2, 3)) "(when " else "(unless ");
            try g.genTest(d);
            try g.emit(" ");
            try g.genStmt(d);
            if (g.ch.chance(.coin, 1, 2)) {
                try g.emit(" ");
                try g.genStmt(d);
            }
            try g.emit(")");
        },
        .begin2 => {
            try g.emit("(begin ");
            try g.genStmt(d);
            try g.emit(" ");
            try g.genStmt(d);
            try g.emit(")");
        },
    }
}
