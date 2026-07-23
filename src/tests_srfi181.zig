//! SRFI-181 (Custom Ports) tests.
//!
//! Port has never held a Scheme Value field before this SRFI -- these tests
//! exercise the GC-marking foundation directly against a bare GC (mirroring
//! tests_srfi254.zig's style), since that's the exact risk this feature was
//! deferred over. Behavioral tests (actual read!/write!/close invocation)
//! are in tests/scheme/srfi/srfi181.scm, against a real VM.

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");

const GC = memory.GC;
const fix = types.makeFixnum;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "custom port: callback closures survive collection while only the port is reachable" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    // read_proc/close_proc are stand-in heap Values (any GC-tracked object
    // proves markPortValues traces custom_backend correctly; a real
    // invokable closure isn't needed for this GC-focused test).
    var port = blk: {
        var read_proc = try gc.allocPair(fix(1), types.NIL);
        gc.pushRoot(&read_proc);
        var close_proc = try gc.allocPair(fix(2), types.NIL);
        gc.pushRoot(&close_proc);
        const p = try gc.allocCustomPort(true, false, true, read_proc, types.FALSE, types.FALSE, types.FALSE, close_proc, types.FALSE);
        gc.popRoot(); // close_proc
        gc.popRoot(); // read_proc
        break :blk p;
    };
    gc.pushRoot(&port);
    defer gc.popRoot();

    // read_proc/close_proc are now reachable *only* through port.custom_backend.
    gc.collect();

    const cb = types.toObject(port).as(types.Port).custom_backend.?;
    try expect(types.isPair(cb.read_proc));
    try expectEqual(@as(i64, 1), types.toFixnum(types.car(cb.read_proc)));
    try expect(types.isPair(cb.close_proc));
    try expectEqual(@as(i64, 2), types.toFixnum(types.car(cb.close_proc)));
    // Slots that were never given a callback stay the "absent" sentinel.
    try expectEqual(types.FALSE, cb.write_proc);
    try expectEqual(types.FALSE, cb.get_position_proc);
    try expectEqual(types.FALSE, cb.set_position_proc);
    try expectEqual(types.FALSE, cb.flush_proc);
}

test "custom port: unreachable port and its callbacks are fully collected (no leak)" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    {
        var read_proc = try gc.allocPair(fix(1), types.NIL);
        gc.pushRoot(&read_proc);
        var close_proc = try gc.allocPair(fix(2), types.NIL);
        gc.pushRoot(&close_proc);
        _ = try gc.allocCustomPort(true, false, true, read_proc, types.FALSE, types.FALSE, types.FALSE, close_proc, types.FALSE);
        gc.popRoot(); // close_proc
        gc.popRoot(); // read_proc
    }
    // Nothing roots the port or its callbacks now.
    try expectEqual(@as(usize, 3), gc.object_count); // port + 2 pairs

    gc.collect();

    // All three are unreachable and swept. freeObject's .port arm must
    // destroy custom_backend itself, or std.testing.allocator's leak check
    // at gc.deinit() above would fail this test with a real memory leak.
    try expectEqual(@as(usize, 0), gc.object_count);
}

test "custom port: allocCustomPort roots its own callback arguments during allocation-time collection" {
    // The two tests above pre-root read_proc/close_proc with gc.pushRoot
    // before calling allocCustomPort, same as any ordinary caller would --
    // but that means they can't tell whether allocCustomPort's OWN
    // slice_roots protection (the thing that actually matters, since a
    // real caller's args come from VM registers already rooted by a
    // different mechanism) is present or missing. This test passes the
    // callbacks in deliberately UNROOTED (from this test's own
    // perspective) and forces a collection via gc.stress -- a runtime
    // field independent of the -Dgc-stress build flag -- during
    // allocCustomPort's own maybeCollect() call, so only its internal
    // slice_roots usage can keep them alive.
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;
    const read_proc = try gc.allocPair(fix(1), types.NIL);
    const close_proc = try gc.allocPair(fix(2), types.NIL);

    gc.enabled = true;
    gc.stress = true;
    var port = try gc.allocCustomPort(true, false, true, read_proc, types.FALSE, types.FALSE, types.FALSE, close_proc, types.FALSE);
    gc.pushRoot(&port);
    defer gc.popRoot();

    const cb = types.toObject(port).as(types.Port).custom_backend.?;
    try expect(types.isPair(cb.read_proc));
    try expectEqual(@as(i64, 1), types.toFixnum(types.car(cb.read_proc)));
    try expect(types.isPair(cb.close_proc));
    try expectEqual(@as(i64, 2), types.toFixnum(types.car(cb.close_proc)));
}
