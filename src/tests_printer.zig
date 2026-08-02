//! Printer regression tests for the audit-v2 Phase 1D family:
//!   #1953 — a rational leaf at nesting depth 1023 rendered as `.../...`,
//!           a legal symbol datum with the wrong value
//!   #1954 — cycles reached only through error-object irritants or
//!           mutex/condition-variable names hung all four output procedures
//!   #1955 — write-simple was registered as `&write`, so it emitted datum
//!           labels on circular structure
//!   #1902 — (closed, decomposed) the fixed 1024-entry seen[]/shared[]
//!           arrays and MAX_PRINT_DEPTH silently truncated output and
//!           dropped write-shared labels; three distinct cliffs (D1-D4)
//!   #2107 — printing recursed on the native stack, so wasm32 (16 MiB
//!           default stack) trapped at depth 848 before the depth guard
//!           calibrated for the native 64 MB stack could fire
//!
//! The printer is now a single iterative engine over heap-allocated work
//! stacks with hashmap-based cycle/sharing detection: exact output at any
//! depth, any number of labels, and detection covers every container the
//! printer recurses into. The Scheme-level round-trip half of these lives in
//! tests/scheme/compliance/printer-gaps.scm.

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const printer = @import("printer.zig");
const Value = types.Value;
const build_options = @import("build_options");

/// n nested one-element lists around `leaf`: nest(3, x) = (((x)))
fn nest(gc: *memory.GC, n: usize, leaf: Value) !Value {
    var acc = leaf;
    var i: usize = 0;
    // allocPair auto-roots its Value arguments, and nothing else allocates
    // between iterations, so `acc` needs no manual root here.
    while (i < n) : (i += 1) acc = try gc.allocPair(acc, types.NIL);
    return acc;
}

/// The exact expected rendering of nest(n, leaf): n opens, leaf, n closes.
fn expectNested(allocator: std.mem.Allocator, s: []const u8, n: usize, leaf: []const u8) !void {
    try std.testing.expectEqual(2 * n + leaf.len, s.len);
    const expected = try allocator.alloc(u8, 2 * n + leaf.len);
    defer allocator.free(expected);
    @memset(expected[0..n], '(');
    @memcpy(expected[n .. n + leaf.len], leaf);
    @memset(expected[n + leaf.len ..], ')');
    try std.testing.expectEqualStrings(expected, s);
}

fn countLabelDefs(s: []const u8) usize {
    // Datum-label definitions are the only '=' the printer emits in these
    // tests' inputs.
    var n: usize = 0;
    for (s) |c| {
        if (c == '=') n += 1;
    }
    return n;
}

// -- #1902 / #2107: exact output at and far past the old 1024 depth cap ----

test "write is exact at the old depth cliff (1023, 1024, 1025)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    inline for (.{ 1023, 1024, 1025 }) |n| {
        const deep = try nest(&gc, n, types.makeFixnum(42));
        const s = try printer.valueToString(std.testing.allocator, deep, .write);
        defer std.testing.allocator.free(s);
        try expectNested(std.testing.allocator, s, n, "42");
    }
}

test "write is exact far past the old depth cap" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // 200k pairs is the #49 / #2107 regression shape; keep the unit-test
    // copy cheap under -Dgc-stress=true (the Scheme suite runs the big one).
    const n: usize = if (build_options.gc_stress) 2000 else 20000;
    const deep = try nest(&gc, n, types.NIL);
    const s = try printer.valueToString(std.testing.allocator, deep, .write);
    defer std.testing.allocator.free(s);
    try expectNested(std.testing.allocator, s, n, "()");
}

// -- #1953: two-part numeric leaves must never split across a depth seam ---

test "rational leaf at depth 1023 prints exactly (#1953)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const rat = try gc.allocRational(types.makeFixnum(3), types.makeFixnum(4));
    const deep = try nest(&gc, 1023, rat);
    const s = try printer.valueToString(std.testing.allocator, deep, .write);
    defer std.testing.allocator.free(s);
    try expectNested(std.testing.allocator, s, 1023, "3/4");
}

test "negative rational leaf at depth 1024 prints exactly (#1953)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const rat = try gc.allocRational(types.makeFixnum(-7), types.makeFixnum(9));
    const deep = try nest(&gc, 1024, rat);
    const s = try printer.valueToString(std.testing.allocator, deep, .write);
    defer std.testing.allocator.free(s);
    try expectNested(std.testing.allocator, s, 1024, "-7/9");
}

// -- #1954: cycles reached only through non-pair/vector/record containers --

fn makeCyclicList(gc: *memory.GC) !Value {
    // (1 2 3 . <self>)
    const items = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    const c = try gc.makeList(&items);
    const third = types.cdr(types.cdr(c));
    types.setCdr(third, c);
    gc.writeBarrier(types.toObject(third), c);
    return c;
}

test "write terminates and labels a cyclic error-object irritant (#1954)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    var msg = try gc.allocString("boom");
    gc.pushRoot(&msg);
    defer gc.popRoot();
    var cyc = try makeCyclicList(&gc);
    gc.pushRoot(&cyc);
    const irritants = try gc.allocPair(cyc, types.NIL);
    gc.popRoot();
    const err = try gc.allocErrorObject(msg, irritants);

    const s = try printer.valueToString(std.testing.allocator, err, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("#<error \"boom\" #0=(1 2 3 . #0#)>", s);

    // display has the same R7RS termination obligation.
    const d = try printer.valueToString(std.testing.allocator, err, .display);
    defer std.testing.allocator.free(d);
    try std.testing.expectEqualStrings("#<error boom #0=(1 2 3 . #0#)>", d);

    // write-shared had the same blind spot in its own pre-pass.
    const sh = try printer.valueToString(std.testing.allocator, err, .shared);
    defer std.testing.allocator.free(sh);
    try std.testing.expectEqualStrings("#<error \"boom\" #0=(1 2 3 . #0#)>", sh);
}

test "write terminates on a cyclic mutex / condition-variable name (#1954)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    var cyc = try makeCyclicList(&gc);
    gc.pushRoot(&cyc);
    const m = try gc.allocMutex(cyc);
    gc.popRoot();
    const ms = try printer.valueToString(std.testing.allocator, m, .write);
    defer std.testing.allocator.free(ms);
    try std.testing.expectEqualStrings("#<mutex #0=(1 2 3 . #0#)>", ms);

    var cyc2 = try makeCyclicList(&gc);
    gc.pushRoot(&cyc2);
    const cv = try gc.allocConditionVariable(cyc2);
    gc.popRoot();
    const cs = try printer.valueToString(std.testing.allocator, cv, .write);
    defer std.testing.allocator.free(cs);
    try std.testing.expectEqualStrings("#<condition-variable #0=(1 2 3 . #0#)>", cs);
}

test "every traversable container terminates when it closes a cycle itself" {
    // The mutation lock for "detection covers what printing walks": one
    // self-referential instance per traversable tag — all SEVEN of
    // `isTraversable`, so this one test alone owns the checklist CLAUDE.md
    // points new-container authors at. A new recursive print arm added
    // without its detection edge fails here by hanging (caught by the suite
    // timeout) rather than by silently shipping #1954 again.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // pair: p = (p) — its own car
    {
        const p = try gc.allocPair(types.NIL, types.NIL);
        types.setCar(p, p);
        gc.writeBarrier(types.toObject(p), p);
        const s = try printer.valueToString(std.testing.allocator, p, .write);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualStrings("#0=(#0#)", s);
    }
    // vector: v = #(v)
    {
        const elems = [_]Value{types.NIL};
        const v = try gc.allocVector(&elems);
        types.toObject(v).as(types.Vector).data[0] = v;
        gc.writeBarrier(types.toObject(v), v);
        const s = try printer.valueToString(std.testing.allocator, v, .write);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualStrings("#0=#(#0#)", s);
    }
    // record instance: r = #<cell r> (the #1713 shape; repeated here so the
    // lock alone covers the full isTraversable set)
    {
        const rt_val = try gc.allocRecordType("cell", 1);
        const rt = types.toObject(rt_val).as(types.RecordType);
        const placeholder = [_]Value{types.NIL};
        const ri = try gc.allocRecordInstance(rt, &placeholder);
        types.toObject(ri).as(types.RecordInstance).fields[0] = ri;
        gc.writeBarrier(types.toObject(ri), ri);
        const s = try printer.valueToString(std.testing.allocator, ri, .write);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualStrings("#0=#<cell #0#>", s);
    }
    // error object: e = #<error "m" e>
    {
        var msg = try gc.allocString("m");
        gc.pushRoot(&msg);
        defer gc.popRoot();
        var irritants = try gc.allocPair(types.NIL, types.NIL);
        gc.pushRoot(&irritants);
        const e = try gc.allocErrorObject(msg, irritants);
        gc.popRoot();
        types.setCar(irritants, e);
        gc.writeBarrier(types.toObject(irritants), e);
        const s = try printer.valueToString(std.testing.allocator, e, .write);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualStrings("#0=#<error \"m\" #0#>", s);
    }
    // multiple values: mv = #<values #(mv)>
    {
        const elems = [_]Value{types.NIL};
        var vec = try gc.allocVector(&elems);
        gc.pushRoot(&vec);
        defer gc.popRoot();
        const mvs = [_]Value{vec};
        const mv = try gc.allocMultipleValues(&mvs);
        types.toObject(vec).as(types.Vector).data[0] = mv;
        gc.writeBarrier(types.toObject(vec), mv);
        const s = try printer.valueToString(std.testing.allocator, mv, .write);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualStrings("#0=#<values #(#0#)>", s);
    }
    // mutex named by a pair that points back at the mutex
    {
        var p = try gc.allocPair(types.NIL, types.NIL);
        gc.pushRoot(&p);
        defer gc.popRoot();
        const m = try gc.allocMutex(p);
        types.setCar(p, m);
        gc.writeBarrier(types.toObject(p), m);
        const s = try printer.valueToString(std.testing.allocator, m, .write);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualStrings("#0=#<mutex (#0#)>", s);
    }
    // condition variable, same shape
    {
        var p = try gc.allocPair(types.NIL, types.NIL);
        gc.pushRoot(&p);
        defer gc.popRoot();
        const cv = try gc.allocConditionVariable(p);
        types.setCar(p, cv);
        gc.writeBarrier(types.toObject(p), cv);
        const s = try printer.valueToString(std.testing.allocator, cv, .write);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualStrings("#0=#<condition-variable (#0#)>", s);
    }
}

// -- #1902 D2/D3: sharing detection has no capacity or position limits -----

test "write-shared labels all of 1200 repeated cells (old cap: 1023)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const n: usize = if (build_options.gc_stress) 300 else 1200;
    const data = try std.testing.allocator.alloc(Value, 2 * n);
    defer std.testing.allocator.free(data);
    @memset(data, types.NIL);
    var vec = try gc.allocVector(data);
    gc.pushRoot(&vec);
    defer gc.popRoot();
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const cell = try gc.allocPair(types.makeFixnum(@intCast(i)), types.NIL);
        const vd = types.toObject(vec).as(types.Vector).data;
        vd[2 * i] = cell;
        vd[2 * i + 1] = cell;
        gc.writeBarrier(types.toObject(vec), cell);
    }

    const s = try printer.valueToString(std.testing.allocator, vec, .shared);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqual(n, countLabelDefs(s));
}

test "write-shared detects a first occurrence past 1024 distinct nodes (D2)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // 1100 distinct filler cells, with one shared cell first met at index
    // 1050 and repeated at the end — positionally invisible to the old
    // fixed seen[] array.
    const size: usize = 1100;
    const data = try std.testing.allocator.alloc(Value, size);
    defer std.testing.allocator.free(data);
    @memset(data, types.NIL);
    var vec = try gc.allocVector(data);
    gc.pushRoot(&vec);
    defer gc.popRoot();
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const cell = try gc.allocPair(types.makeFixnum(@intCast(i)), types.NIL);
        types.toObject(vec).as(types.Vector).data[i] = cell;
        gc.writeBarrier(types.toObject(vec), cell);
    }
    const vd = types.toObject(vec).as(types.Vector).data;
    vd[size - 1] = vd[1050];
    gc.writeBarrier(types.toObject(vec), vd[1050]);

    const s = try printer.valueToString(std.testing.allocator, vec, .shared);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqual(@as(usize, 1), countLabelDefs(s));
}

// -- #1902 D4: a cycle whose back-edge sits past the old depth cap ---------

test "a 2000-deep nested cycle keeps its datum label (D4)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const depth: usize = if (build_options.gc_stress) 1200 else 2000;
    var outer = try gc.allocPair(types.NIL, types.NIL);
    gc.pushRoot(&outer);
    defer gc.popRoot();
    // outer = ( ( ( ... (inner) ... ) ) ); then inner's car -> outer.
    var inner = outer;
    var i: usize = 1;
    while (i < depth) : (i += 1) {
        const next = try gc.allocPair(types.NIL, types.NIL);
        types.setCar(inner, next);
        gc.writeBarrier(types.toObject(inner), next);
        inner = next;
    }
    types.setCar(inner, outer);
    gc.writeBarrier(types.toObject(inner), outer);

    const s = try printer.valueToString(std.testing.allocator, outer, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expect(std.mem.startsWith(u8, s, "#0=("));
    try std.testing.expect(std.mem.indexOf(u8, s, "#0#") != null);
    // Exact shape: #0= + depth opens + #0# + depth closes.
    try std.testing.expectEqual(3 + depth + 3 + depth, s.len);
}

// -- #1955: write-simple never labels; cyclic input is a loud error --------

test "write-simple output has no labels on acyclic sharing, errors on cycles" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // (d d) with d = (1 2 3): acyclic sharing prints in full, unlabelled.
    const items = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    var d = try gc.makeList(&items);
    gc.pushRoot(&d);
    const shared_items = [_]Value{ d, d };
    const both = try gc.makeList(&shared_items);
    gc.popRoot();

    const s = try printer.valueToStringSimple(std.testing.allocator, both);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("((1 2 3) (1 2 3))", s);

    const cyc = try makeCyclicList(&gc);
    try std.testing.expectError(error.CircularStructure, printer.valueToStringSimple(std.testing.allocator, cyc));
}

// -- Bounded diagnostic printer stays terminating and bounded --------------

test "printValue (diagnostic) truncates deep values and terminates on cycles" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Past the cap it truncates with the `...` sentinel rather than
    // recursing (this is the human-facing diagnostic path only).
    const deep = try nest(&gc, 1500, types.makeFixnum(1));
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    try printer.printValue(&aw.writer, deep, .write);
    const out = try aw.toOwnedSlice();
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "...") != null);

    // An UNlabelled cyclic list terminates: the spine ticks the cap.
    const cyc = try makeCyclicList(&gc);
    var aw2: std.Io.Writer.Allocating = .init(std.testing.allocator);
    try printer.printValue(&aw2.writer, cyc, .write);
    const out2 = try aw2.toOwnedSlice();
    defer std.testing.allocator.free(out2);
    try std.testing.expect(std.mem.endsWith(u8, out2, " ...)"));
}
