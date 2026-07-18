//! SRFI-254 (Ephemerons and Guardians) tests.
//!
//! The garbage-collection semantics — ephemeron breaking, guardian
//! resurrection — are exercised against a bare GC with `enabled = false` so
//! collection happens only at explicit `gc.collect()` points (deterministic
//! even under -Dgc-stress=true, which `enabled = false` also gates). The API
//! surface and guardian invocation go through a real VM via eval.

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const th = @import("testing_helpers.zig");

const GC = memory.GC;
const Value = types.Value;
const fix = types.makeFixnum;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// --- Ephemeron GC semantics ------------------------------------------------

test "ephemeron: value retained while key is reachable" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var key = try gc.allocPair(fix(1), types.NIL);
    gc.pushRoot(&key);
    defer gc.popRoot();
    // `val` is referenced only through the ephemeron.
    const val = try gc.allocPair(fix(2), types.NIL);
    var eph = try gc.allocEphemeron(key, val);
    gc.pushRoot(&eph);
    defer gc.popRoot();

    gc.collect();

    try expect(!types.toEphemeron(eph).broken);
    try expectEqual(key, types.toEphemeron(eph).key);
    // The value survived the collection purely because the key is reachable.
    try expectEqual(val, types.toEphemeron(eph).value);
    try expect(types.isPair(types.toEphemeron(eph).value));
    try expectEqual(@as(i64, 2), types.toFixnum(types.car(types.toEphemeron(eph).value)));
}

test "ephemeron: breaks when key becomes unreachable" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var eph = blk: {
        var key = try gc.allocPair(fix(1), types.NIL);
        gc.pushRoot(&key);
        const e = try gc.allocEphemeron(key, try gc.allocPair(fix(2), types.NIL));
        gc.popRoot(); // key now reachable only through the ephemeron (weakly)
        break :blk e;
    };
    gc.pushRoot(&eph);
    defer gc.popRoot();

    gc.collect();

    try expect(types.toEphemeron(eph).broken);
    try expectEqual(types.FALSE, types.toEphemeron(eph).key);
    try expectEqual(types.FALSE, types.toEphemeron(eph).value);
}

test "ephemeron: breaks even when the value references the key" {
    // The case a plain weak-key pair gets wrong: value -> key, key otherwise
    // unreachable. A weak pair would keep value alive, value would keep key
    // alive, and the entry would never be reclaimed. The ephemeron breaks.
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var eph = blk: {
        var key = try gc.allocPair(fix(7), types.NIL);
        gc.pushRoot(&key);
        const value = try gc.allocPair(key, types.NIL); // value.car == key
        const e = try gc.allocEphemeron(key, value);
        gc.popRoot();
        break :blk e;
    };
    gc.pushRoot(&eph);
    defer gc.popRoot();

    gc.collect();

    try expect(types.toEphemeron(eph).broken);
}

test "ephemeron: stays intact across collections while key stays reachable" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var key = try gc.allocPair(fix(5), types.NIL);
    gc.pushRoot(&key);
    defer gc.popRoot();
    var eph = try gc.allocEphemeron(key, try gc.allocPair(fix(6), types.NIL));
    gc.pushRoot(&eph);
    defer gc.popRoot();

    // Several collections, including a full one (every 8th cycle).
    var i: usize = 0;
    while (i < 10) : (i += 1) gc.collect();

    try expect(!types.toEphemeron(eph).broken);
    try expectEqual(@as(i64, 6), types.toFixnum(types.car(types.toEphemeron(eph).value)));
}

// --- Guardian GC semantics -------------------------------------------------

test "guardian: resurrects an unreachable registered object" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var g = try gc.allocGuardian(false);
    gc.pushRoot(&g);
    defer gc.popRoot();

    {
        // Only the guardian's (weak) registered list references this object.
        const obj = try gc.allocPair(fix(42), types.NIL);
        try types.toGuardian(g).registered.append(gc.allocator, .{ .watched = obj, .payload = obj });
    }
    try expectEqual(@as(usize, 1), types.toGuardian(g).registered.items.len);

    gc.collect();

    // Unreachable-except-through-the-guardian → resurrected onto the ready
    // queue, and kept alive there.
    try expectEqual(@as(usize, 0), types.toGuardian(g).registered.items.len);
    try expectEqual(@as(usize, 1), types.toGuardian(g).ready.items.len);
    const readied = types.toGuardian(g).ready.items[0].payload;
    try expect(types.isPair(readied));
    try expectEqual(@as(i64, 42), types.toFixnum(types.car(readied)));
}

test "guardian: keeps a still-reachable registered object registered" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var g = try gc.allocGuardian(false);
    gc.pushRoot(&g);
    var obj = try gc.allocPair(fix(99), types.NIL);
    gc.pushRoot(&obj); // independently reachable
    try types.toGuardian(g).registered.append(gc.allocator, .{ .watched = obj, .payload = obj });

    gc.collect();

    try expectEqual(@as(usize, 1), types.toGuardian(g).registered.items.len);
    try expectEqual(@as(usize, 0), types.toGuardian(g).ready.items.len);

    gc.popRoot(); // obj
    gc.popRoot(); // g
}

test "guardian: representative outlives a resurrected object" {
    // Register (obj, rep) with distinct rep reachable only through the entry;
    // after resurrection the representative must still be valid.
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var g = try gc.allocGuardian(false);
    gc.pushRoot(&g);
    defer gc.popRoot();

    {
        const obj = try gc.allocPair(fix(1), types.NIL);
        const rep = try gc.allocPair(fix(2), types.NIL);
        try types.toGuardian(g).registered.append(gc.allocator, .{ .watched = obj, .payload = rep });
    }

    gc.collect();

    try expectEqual(@as(usize, 1), types.toGuardian(g).ready.items.len);
    const rep = types.toGuardian(g).ready.items[0].payload;
    try expect(types.isPair(rep));
    try expectEqual(@as(i64, 2), types.toFixnum(types.car(rep)));
}

// --- Transport cells are strong on a non-moving collector ------------------

test "transport cell: key and value survive collection, never broken" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var cell = blk: {
        const key = try gc.allocPair(fix(3), types.NIL);
        const value = try gc.allocPair(fix(4), types.NIL);
        break :blk try gc.allocTransportCell(key, value);
    };
    gc.pushRoot(&cell);
    defer gc.popRoot();

    var i: usize = 0;
    while (i < 10) : (i += 1) gc.collect();

    try expect(!types.toTransportCell(cell).broken);
    try expectEqual(@as(i64, 3), types.toFixnum(types.car(types.toTransportCell(cell).key)));
    try expectEqual(@as(i64, 4), types.toFixnum(types.car(types.toTransportCell(cell).value)));
}

// --- API surface via a real VM ---------------------------------------------

test "srfi 254: ephemeron API" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (srfi 254))");
    _ = try ctx.vm.eval("(define e (make-ephemeron 'k 'v))");
    try expect(types.isTruthy(try ctx.vm.eval("(ephemeron? e)")));
    try expect(!types.isTruthy(try ctx.vm.eval("(ephemeron-broken? e)")));
    try expectEqual(try ctx.vm.eval("'v"), try ctx.vm.eval("(ephemeron-value e)"));
    try expectEqual(try ctx.vm.eval("'v"), try ctx.vm.eval("(ephemeron-ref e 'k)"));
    try expectEqual(try ctx.vm.eval("'d"), try ctx.vm.eval("(ephemeron-ref e 'other 'd)"));
    try expect(!types.isTruthy(try ctx.vm.eval("(ephemeron-ref e 'other)")));
}

test "srfi 254: guardian predicates and invocation" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (srfi 254))");
    _ = try ctx.vm.eval("(define g (make-guardian))");
    try expect(types.isTruthy(try ctx.vm.eval("(guardian? g)")));
    try expect(types.isTruthy(try ctx.vm.eval("(procedure? g)")));
    try expect(!types.isTruthy(try ctx.vm.eval("(transport-cell-guardian? g)")));
    // A brand-new guardian with nothing registered yields #f.
    try expect(!types.isTruthy(try ctx.vm.eval("(g)")));
    // Registration accepts both the one- and two-argument forms without error.
    _ = try ctx.vm.eval("(g (list 1 2 3))");
    _ = try ctx.vm.eval("(g (list 4) 'rep)");
}

test "srfi 254: guardian resurrection round-trips through (g)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (srfi 254))");
    _ = try ctx.vm.eval("(define g (make-guardian))");
    // Register an object reachable only through the guardian, then force a
    // collection directly on the VM's GC.
    _ = try ctx.vm.eval("(g (list 'dead))");
    ctx.gc.collect();
    // The resurrected element is now available. Bind it to a global so it is
    // rooted across the subsequent evals (which collect under -Dgc-stress).
    _ = try ctx.vm.eval("(define got (g))");
    try expect(types.isTruthy(try ctx.vm.eval("(pair? got)")));
    try expectEqual(try ctx.vm.eval("'dead"), try ctx.vm.eval("(car got)"));
    // And the queue is empty again.
    try expect(!types.isTruthy(try ctx.vm.eval("(g)")));
}

test "srfi 254: transport cell guardian and current-hash" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (srfi 254))");
    _ = try ctx.vm.eval("(define tg (make-transport-cell-guardian))");
    try expect(types.isTruthy(try ctx.vm.eval("(transport-cell-guardian? tg)")));
    _ = try ctx.vm.eval("(define c (tg 'key 'val))");
    try expect(types.isTruthy(try ctx.vm.eval("(transport-cell? c)")));
    try expectEqual(try ctx.vm.eval("'key"), try ctx.vm.eval("(transport-cell-key c)"));
    try expectEqual(try ctx.vm.eval("'val"), try ctx.vm.eval("(transport-cell-value c)"));
    try expect(!types.isTruthy(try ctx.vm.eval("(transport-cell-broken? c)")));
    // Nothing ever moves on this collector, so the guardian yields nothing.
    try expect(!types.isTruthy(try ctx.vm.eval("(tg)")));
    // current-hash is a stable non-negative integer for eq? objects.
    _ = try ctx.vm.eval("(define o (list 1))");
    try expect(types.isTruthy(try ctx.vm.eval("(integer? (current-hash o))")));
    try expect(types.isTruthy(try ctx.vm.eval("(= (current-hash o) (current-hash o))")));
    try expect(types.isTruthy(try ctx.vm.eval("(>= (current-hash o) 0)")));
}

test "srfi 254: component libraries import in isolation" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(import (srfi 254 ephemerons))");
    _ = try ctx.vm.eval("(import (srfi 254 guardians))");
    _ = try ctx.vm.eval("(import (srfi 254 transport-cell-guardians))");
    _ = try ctx.vm.eval("(import (srfi 254 ephemerons-and-guardians))");
    try expect(types.isTruthy(try ctx.vm.eval("(ephemeron? (make-ephemeron 1 2))")));
    try expect(types.isTruthy(try ctx.vm.eval("(guardian? (make-guardian))")));
    try expect(types.isTruthy(try ctx.vm.eval("(transport-cell-guardian? (make-transport-cell-guardian))")));
    // reference-barrier is exported by both ephemerons and guardians.
    _ = try ctx.vm.eval("(reference-barrier 'x)");
}
