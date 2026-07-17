//! Data-kind expression and statement generators for the portable-subset
//! fuzzer (fuzz_gen_portable.zig): ASCII characters and strings, lists,
//! quasiquote templates, vectors, bytevectors, and the statement layer.
//! Split out along the grammar-domain seam to stay within the file size
//! policy, mirroring the fuzz_gen.zig / fuzz_gen_data.zig split; the
//! portable module re-exports these, so call sites read the same either
//! way. See fuzz_gen_portable.zig for the portability discipline every
//! production here follows.

const std = @import("std");
const gen_mod = @import("fuzz_gen.zig");
const portable = @import("fuzz_gen_portable.zig");

const Gen = gen_mod.Gen;
const Error = gen_mod.Error;
const Cands = gen_mod.Cands;
const Binding = gen_mod.Binding;
const Len = gen_mod.Len;
const StrInfo = gen_mod.StrInfo;
const ListInfo = gen_mod.ListInfo;
const VecInfo = gen_mod.VecInfo;
const ListNeed = gen_mod.ListNeed;

const genInt = portable.genInt;
const genBool = portable.genBool;
const genTest = portable.genTest;
const genIndex = portable.genIndex;
const genClampedInt = portable.genClampedInt;
const genValueOfKind = portable.genValueOfKind;
const pickBindKind = portable.pickBindKind;
const litInt = portable.litInt;

const char_lits = [_][]const u8{ "#\\a", "#\\b", "#\\z", "#\\0", "#\\space", "#\\newline" };
const string_lits = [_]gen_mod.StrLit{
    gen_mod.strLit("\"\""),
    gen_mod.strLit("\"abc\""),
    gen_mod.strLit("\"fuzz\""),
    gen_mod.strLit("\"x y!\""),
};

// ---------------------------------------------------------------------------
// Characters and strings (pure ASCII)
// ---------------------------------------------------------------------------

pub fn genChar(g: *Gen, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    const CharOp = enum { lit, ref, int_to, str_ref, changecase };
    var c: Cands(CharOp) = .{};
    c.add(.lit, 4);
    if (g.hasVar(gen_mod.bindIsChar)) c.add(.ref, 3);
    if (depth > 0) {
        c.add(.int_to, 2);
        c.add(.changecase, 1);
        if (g.hasVar(gen_mod.bindIsStringIndexable)) c.add(.str_ref, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => try g.emit(char_lits[g.ch.index(.lit_pick, char_lits.len)]),
        .ref => try g.emit(g.pickVar(gen_mod.bindIsChar).?.name),
        .int_to => {
            try g.emit("(integer->char (+ 97 (modulo ");
            try genInt(g, d);
            try g.emit(" 26)))");
        },
        .str_ref => {
            const b = g.pickVar(gen_mod.bindIsStringIndexable).?;
            try g.emitf("(string-ref {s} ", .{b.name});
            try genIndex(g, d, b.kind.string.len.?);
            try g.emit(")");
        },
        .changecase => {
            // ASCII-only sources make case conversion fully portable;
            // beyond ASCII an implementation may support any Unicode subset.
            try g.emit(if (g.ch.chance(.coin, 1, 2)) "(char-upcase " else "(char-downcase ");
            try genChar(g, d);
            try g.emit(")");
        },
    }
}

pub fn genString(g: *Gen, depth_in: u32) Error!StrInfo {
    const depth = g.cap(depth_in);
    const StrOp = enum { lit, ref, make, ctor, append, copy, substr, num2str };
    var c: Cands(StrOp) = .{};
    c.add(.lit, 3);
    if (g.hasVar(gen_mod.bindIsString)) c.add(.ref, 4);
    if (depth > 0) {
        c.add(.make, 2);
        c.add(.ctor, 2);
        c.add(.append, 3);
        c.add(.copy, 1);
        c.add(.num2str, 2);
        if (g.hasVar(gen_mod.bindIsStringExact)) c.add(.substr, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .lit => {
            const l = string_lits[g.ch.index(.lit_pick, string_lits.len)];
            try g.emit(l.text);
            return .{ .len = l.len, .mutable = false };
        },
        .ref => {
            const b = g.pickVar(gen_mod.bindIsString).?;
            try g.emit(b.name);
            return b.kind.string;
        },
        .make => {
            const k: u16 = @intCast(g.ch.range(.len_pick, 0, 8));
            try g.emitf("(make-string {d} ", .{k});
            try genChar(g, d);
            try g.emit(")");
            return .{ .len = k, .mutable = true };
        },
        .ctor => {
            const k: u16 = @intCast(g.ch.range(.len_pick, 1, 4));
            try g.emit("(string");
            for (0..k) |_| {
                try g.emit(" ");
                try genChar(g, d);
            }
            try g.emit(")");
            return .{ .len = k, .mutable = true };
        },
        .append => {
            try g.emit("(string-append ");
            const a = try genString(g, d);
            try g.emit(" ");
            const b = try genString(g, d);
            try g.emit(")");
            const len: ?u16 = if (a.len != null and b.len != null) a.len.? + b.len.? else null;
            return .{ .len = len, .mutable = true };
        },
        .copy => {
            try g.emit("(string-copy ");
            const a = try genString(g, d);
            try g.emit(")");
            return .{ .len = a.len, .mutable = true };
        },
        .substr => {
            const b = g.pickVar(gen_mod.bindIsStringExact).?;
            const len = b.kind.string.len.?;
            const from: u16 = @intCast(g.ch.range(.idx_pick, 0, len));
            const to: u16 = @intCast(g.ch.range(.idx_pick, from, len));
            try g.emitf("(substring {s} {d} {d})", .{ b.name, from, to });
            return .{ .len = to - from, .mutable = true };
        },
        .num2str => {
            try g.emit("(number->string ");
            try genInt(g, d);
            try g.emit(")");
            return .{ .len = null, .mutable = true };
        },
    }
}

// ---------------------------------------------------------------------------
// Lists, quasiquote, vectors, bytevectors (pure)
// ---------------------------------------------------------------------------

pub fn genList(g: *Gen, depth_in: u32, need: ListNeed) Error!ListInfo {
    const depth = g.cap(depth_in);
    const ListOp = enum { ctor, empty_lit, quote_lit, ref, cons_op, cdr_op, append_op, reverse_op, map_op, vec2list, quasi };
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
        if (g.hasVar(gen_mod.bindIsIntVec)) c.add(.vec2list, 2);
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
                try genInt(g, d);
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
                try g.emitf("{d}", .{litInt(g)});
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
            try genInt(g, d);
            try g.emit(" ");
            const tail = try genList(g, d, .{ .ints = need.ints });
            try g.emit(")");
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
            return .{
                .len = .{ .exact = info.len.exactLen().? - 1 },
                .mut = if (info.mut == .all) .all else .none,
                .ints = info.ints,
            };
        },
        .append_op => {
            try g.emit("(append ");
            const a = try genList(g, d, .{ .ints = need.ints });
            try g.emit(" ");
            const b = try genList(g, d, .{ .ints = need.ints, .non_empty = need.non_empty });
            try g.emit(")");
            const mut: @FieldType(ListInfo, "mut") = if (b.mut == .all)
                .all
            else if (a.len.nonEmpty())
                .head
            else
                .none;
            return .{ .len = Len.sum(a.len, b.len), .mut = mut, .ints = a.ints and b.ints };
        },
        .reverse_op => {
            try g.emit("(reverse ");
            const a = try genList(g, d, need);
            try g.emit(")");
            return .{ .len = a.len, .mut = .all, .ints = a.ints };
        },
        .map_op => {
            // Pure lambda body, so map's unspecified application order is
            // unobservable.
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(map (lambda ({s}) ", .{names[0]});
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try genInt(g, d);
            g.scope.shrinkRetainingCapacity(mark);
            try g.emit(") ");
            const src = try genList(g, d, .{ .ints = true, .non_empty = need.non_empty });
            try g.emit(")");
            return .{ .len = src.len, .mut = .all, .ints = true };
        },
        .vec2list => {
            const b = g.pickVar(gen_mod.bindIsIntVec).?;
            try g.emitf("(vector->list {s})", .{b.name});
            return .{ .len = .{ .exact = b.kind.vector.len }, .mut = .all, .ints = true };
        },
        .quasi => return genQuasi(g, depth, need.non_empty),
    }
}

/// Quasiquote template: mixed atoms, unquotes, splices, nested data. Both
/// implementations print nested quote/quasiquote data unabbreviated
/// ("(quasiquote ...)"), so templates are safe to write.
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
                try g.emit(gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)]);
                len = len.plusOne();
            },
            2 => {
                try g.emit(",");
                try genInt(g, d);
                len = len.plusOne();
            },
            3 => {
                if (g.ch.chance(.coin, 1, 3)) {
                    try g.emitf("`({s} ,{s})", .{
                        gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)],
                        gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)],
                    });
                } else {
                    try g.emitf("({s} {d})", .{
                        gen_mod.symbol_names[g.ch.index(.lit_pick, gen_mod.symbol_names.len)],
                        @as(i64, g.ch.range(.lit_pick, 0, 40)) - 20,
                    });
                }
                len = len.plusOne();
            },
            else => {
                try g.emit(",@");
                const inner = try genList(g, d, .{});
                len = Len.sum(len, inner.len);
            },
        }
    }
    try g.emit(")");
    return .{ .len = len, .mut = .none, .ints = false };
}

pub fn genVector(g: *Gen, depth_in: u32, need_ints: bool) Error!VecInfo {
    const depth = g.cap(depth_in);
    const VecOp = enum { ctor, make, ref, vmap, list2vec };
    var c: Cands(VecOp) = .{};
    c.add(.ctor, 4);
    c.add(.make, 3);
    if (need_ints) {
        if (g.hasVar(gen_mod.bindIsIntVec)) c.add(.ref, 4);
    } else {
        if (g.hasVar(gen_mod.bindIsVec)) c.add(.ref, 4);
    }
    if (depth > 0) {
        c.add(.vmap, 2);
        if (g.hasVar(gen_mod.bindIsListIntsExactNonEmpty)) c.add(.list2vec, 2);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .ctor => {
            const n: u16 = @intCast(g.ch.range(.len_pick, 1, 5));
            const boxed = !need_ints and g.ch.chance(.coin, 1, 4);
            try g.emit("(vector");
            for (0..n) |_| {
                try g.emit(" ");
                if (boxed) _ = try genList(g, d, .{ .ints = true, .non_empty = true }) else try genInt(g, d);
            }
            try g.emit(")");
            return .{ .len = n, .boxed = boxed };
        },
        .make => {
            const n: u16 = @intCast(g.ch.range(.len_pick, 1, 6));
            const boxed = !need_ints and g.ch.chance(.coin, 1, 4);
            try g.emitf("(make-vector {d} ", .{n});
            if (boxed) _ = try genList(g, d, .{ .ints = true, .non_empty = true }) else try genInt(g, d);
            try g.emit(")");
            return .{ .len = n, .boxed = boxed };
        },
        .ref => {
            const b = (if (need_ints) g.pickVar(gen_mod.bindIsIntVec) else g.pickVar(gen_mod.bindIsVec)).?;
            try g.emit(b.name);
            return b.kind.vector;
        },
        .vmap => {
            // Pure lambda body: vector-map's application order is
            // unspecified, like map's.
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(vector-map (lambda ({s}) ", .{names[0]});
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            try genInt(g, d);
            g.scope.shrinkRetainingCapacity(mark);
            try g.emit(") ");
            const src = try genVector(g, d, true);
            try g.emit(")");
            return .{ .len = src.len, .boxed = false };
        },
        .list2vec => {
            const b = g.pickVar(gen_mod.bindIsListIntsExactNonEmpty).?;
            try g.emitf("(list->vector {s})", .{b.name});
            return .{ .len = b.kind.list.len.exactLen().?, .boxed = false };
        },
    }
}

pub fn genBytevector(g: *Gen, depth_in: u32) Error!u16 {
    _ = g.cap(depth_in);
    const BvOp = enum { ctor, make, ref };
    var c: Cands(BvOp) = .{};
    c.add(.ctor, 3);
    c.add(.make, 3);
    if (g.hasVar(gen_mod.bindIsBv)) c.add(.ref, 3);
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
            const b = g.pickVar(gen_mod.bindIsBv).?;
            try g.emit(b.name);
            return b.kind.bytevector;
        },
    }
}

// ---------------------------------------------------------------------------
// Statements — the only place effects on visible bindings happen. Reached
// exclusively from top-level statement forms and their statement bodies,
// all of which R7RS evaluates in a specified order. Every statement is
// void-valued (Kaappi echoes non-void top-level values; Chibi does not).
// ---------------------------------------------------------------------------

const StmtOp = enum {
    noop,
    set_var,
    vector_set,
    bv_set,
    string_set,
    setcar,
    foreach,
    when_form,
    if_stmt,
    begin2,
    let_stmt,
};

pub fn genStmt(g: *Gen, depth_in: u32) Error!void {
    const depth = g.cap(depth_in);
    var c: Cands(StmtOp) = .{};
    // Always available: keeps the candidate list non-empty at depth 0 when
    // nothing mutable is in scope.
    c.add(.noop, 1);
    if (g.hasVar(gen_mod.bindIsSettableAtom)) c.add(.set_var, 6);
    if (g.hasVar(gen_mod.bindIsVec)) c.add(.vector_set, 5);
    if (g.hasVar(gen_mod.bindIsBv)) c.add(.bv_set, 3);
    if (g.hasVar(gen_mod.bindIsStringSettable)) c.add(.string_set, 4);
    if (g.hasVar(gen_mod.bindIsListMutNonEmpty)) c.add(.setcar, 3);
    if (depth > 0) {
        if (g.hasVar(gen_mod.bindIsSettableInt)) c.add(.foreach, 2);
        c.add(.when_form, 3);
        c.add(.if_stmt, 2);
        c.add(.begin2, 2);
        c.add(.let_stmt, 3);
    }
    const d = depth -| 1;
    switch (c.pick(g.ch)) {
        .noop => try g.emit("(when #f 0)"),
        .set_var => {
            const b = g.pickVar(gen_mod.bindIsSettableAtom).?;
            try g.emitf("(set! {s} ", .{b.name});
            switch (b.kind) {
                .int => try genClampedInt(g, d),
                .boolean => try genBool(g, d),
                .char => try genChar(g, d),
                else => unreachable,
            }
            try g.emit(")");
        },
        .vector_set => {
            const b = g.pickVar(gen_mod.bindIsVec).?;
            const v = b.kind.vector;
            try g.emitf("(vector-set! {s} ", .{b.name});
            try genIndex(g, d, v.len);
            try g.emit(" ");
            if (v.boxed) {
                _ = try genList(g, d, .{ .ints = true, .non_empty = true });
            } else {
                try genClampedInt(g, d);
            }
            try g.emit(")");
        },
        .bv_set => {
            const b = g.pickVar(gen_mod.bindIsBv).?;
            try g.emitf("(bytevector-u8-set! {s} ", .{b.name});
            try genIndex(g, d, b.kind.bytevector);
            try g.emit(" (modulo ");
            try genInt(g, d);
            try g.emit(" 256))");
        },
        .string_set => {
            const b = g.pickVar(gen_mod.bindIsStringSettable).?;
            try g.emitf("(string-set! {s} ", .{b.name});
            try genIndex(g, d, b.kind.string.len.?);
            try g.emit(" ");
            try genChar(g, d);
            try g.emit(")");
        },
        .setcar => {
            const b = g.pickVar(gen_mod.bindIsListMutNonEmpty).?;
            try g.emitf("(set-car! {s} ", .{b.name});
            try genClampedInt(g, d);
            try g.emit(")");
        },
        .foreach => {
            // for-each guarantees left-to-right application (unlike map),
            // so an accumulating set! in its body is deterministic.
            const tgt = g.pickVar(gen_mod.bindIsSettableInt).?;
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(1, &nb);
            try g.emitf("(for-each (lambda ({s}) (set! {s} (modulo ", .{ names[0], tgt.name });
            const mark = g.scope.items.len;
            try g.pushBinding(names[0], .int);
            g.loop_nest += 1;
            try genInt(g, d);
            g.loop_nest -= 1;
            g.scope.shrinkRetainingCapacity(mark);
            try g.emitf(" {d}))) ", .{gen_mod.acc_modulus});
            _ = try genList(g, d, .{ .ints = true });
            try g.emit(")");
        },
        .when_form => {
            // when/unless live only in statement position: their value on
            // a failed test is unspecified.
            try g.emit(if (g.ch.chance(.coin, 2, 3)) "(when " else "(unless ");
            try genTest(g, d);
            try g.emit(" ");
            try genStmt(g, d);
            if (g.ch.chance(.coin, 1, 2)) {
                try g.emit(" ");
                try genStmt(g, d);
            }
            try g.emit(")");
        },
        .if_stmt => {
            try g.emit("(if ");
            try genTest(g, d);
            try g.emit(" ");
            try genStmt(g, d);
            try g.emit(" ");
            try genStmt(g, d);
            try g.emit(")");
        },
        .begin2 => {
            try g.emit("(begin ");
            try genStmt(g, d);
            try g.emit(" ");
            try genStmt(g, d);
            try g.emit(")");
        },
        .let_stmt => {
            // (let (bindings) stmt+): a lexical scope whose body remains in
            // statement position — the bindings become extra mutation
            // targets, and the let's own value stays void.
            const n = g.ch.range(.count, 1, 2);
            var nb: [4][]const u8 = undefined;
            const names = g.pickNames(n, &nb);
            try g.emit("(let (");
            const mark = g.scope.items.len;
            var stash: [2]@FieldType(Binding, "kind") = undefined;
            for (0..n) |i| {
                try g.emitf("({s} ", .{names[i]});
                stash[i] = try genValueOfKind(g, pickBindKind(g), d);
                try g.emit(") ");
            }
            for (0..n) |i| try g.pushBinding(names[i], stash[i]);
            try g.emit(") ");
            const nstmts = g.ch.range(.count, 1, 2);
            for (0..nstmts) |i| {
                if (i > 0) try g.emit(" ");
                try genStmt(g, d);
            }
            try g.emit(")");
            g.scope.shrinkRetainingCapacity(mark);
        },
    }
}
