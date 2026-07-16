const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const shared_channel = @import("shared_channel.zig");
const shared_object = @import("shared_object.zig");
const th = @import("testing_helpers.zig");

// Rendezvous on the shared representation (KEP-0002 §6 as amended;
// #1600/#1601/#1603, review findings 5-6 from #1604): capacity 0 admits a
// send exactly when a receiver has committed demand. Split out of
// tests_shared_channel.zig along the rendezvous seam (1500-line policy;
// the tests_native.zig split, #1595, is the precedent). Follows the same
// conventions: bare-GC tests for the raw protocol, th.TestContext where a
// VM drives the primitives, and every SharedChannel balanced against a
// liveCount baseline.

test "shared rendezvous: raw protocol admits only against committed demand" {
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();
    sc.capacity = 0;

    // no demand: would_park, nothing enqueued
    try std.testing.expectEqual(shared_channel.SendOutcome.would_park, try shared_channel.send(sc, types.makeFixnum(1), null));

    // one committed receiver: exactly one send admitted
    shared_channel.commitRvDemand(sc);
    try std.testing.expectEqual(shared_channel.SendOutcome.sent, try shared_channel.send(sc, types.makeFixnum(2), null));
    try std.testing.expectEqual(shared_channel.SendOutcome.would_park, try shared_channel.send(sc, types.makeFixnum(3), null));

    // the committed receiver collects the handoff and withdraws
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const got = try shared_channel.receive(sc, &gc, null, false);
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(got.value));
    shared_channel.withdrawRvDemand(sc);

    // demand gone again: back to would_park
    try std.testing.expectEqual(shared_channel.SendOutcome.would_park, try shared_channel.send(sc, types.makeFixnum(4), null));

    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "shared rendezvous: promotion seeds rv_demand from the local counter" {
    // A receiver parked on the local representation before promotion holds
    // a demand token counted in ch.rv_demand; promoteChannel must carry it
    // so a remote sender's admission sees the migrated receiver (§2 step 4
    // + §6 as amended).
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define ch (make-channel 0))");
    const ch_val = try ctx.vm.eval("ch");
    const ch = types.toObject(ch_val).as(types.Channel);

    // Park a fiber receiver locally: it commits a demand token.
    _ = try ctx.vm.eval("(define r (spawn (lambda () (channel-receive ch))))");
    _ = try ctx.vm.eval("(yield)");
    try std.testing.expectEqual(@as(u32, 1), ch.rv_demand);

    const sc = try shared_channel.promoteChannel(&ctx.gc, ch);
    try std.testing.expectEqual(@as(u32, 1), sc.rv_demand);

    // A raw remote-style send is admitted against the migrated demand and
    // the parked receiver collects it through the normal primitive path.
    try std.testing.expectEqual(shared_channel.SendOutcome.sent, try shared_channel.send(sc, types.makeFixnum(9), null));
    const joined = try ctx.vm.eval("(fiber-join r)");
    try std.testing.expectEqual(@as(i64, 9), types.toFixnum(joined));
    try std.testing.expectEqual(@as(u32, 0), sc.rv_demand);
}

test "shared rendezvous: timed-out receive withdraws demand on the promoted channel" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define ch (make-channel 0))");
    const ch_val = try ctx.vm.eval("ch");
    const ch = types.toObject(ch_val).as(types.Channel);
    const sc = try shared_channel.promoteChannel(&ctx.gc, ch);

    const result = try ctx.vm.eval("(channel-receive ch 0.02 'rto)");
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, result, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("rto", s);
    try std.testing.expectEqual(@as(u32, 0), sc.rv_demand);

    // and the send side still refuses admission afterwards
    const sres = try ctx.vm.eval("(channel-send ch 'v 0.02 'sto)");
    const s2 = try printer.valueToString(std.testing.allocator, sres, .write);
    defer std.testing.allocator.free(s2);
    try std.testing.expectEqualStrings("sto", s2);
    try std.testing.expectEqual(@as(u32, 0), sc.queue_len);
}

test "shared rendezvous: cross-thread handoff both directions" {
    // The #1600 scenario on real OS threads, channel captured by the thunk
    // (the KEP-0002 §2 legal sharing path — a top-level global would fail
    // the foreign-owner check instead of promoting).
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const got = try ctx.vm.eval(
        \\(let* ((ch (make-channel 0))
        \\       (t (thread-start! (make-thread (lambda () (channel-send ch 41))))))
        \\  (let ((v (+ 1 (channel-receive ch))))
        \\    (thread-join! t) ; join releases the child VM/GC (child_resources)
        \\    v))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(got));

    const got2 = try ctx.vm.eval(
        \\(let* ((ch (make-channel 0))
        \\       (t (thread-start! (make-thread (lambda () (channel-receive ch))))))
        \\  (channel-send ch 7)
        \\  (thread-join! t))
    );
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(got2));
}

test "shared rendezvous: a token-holding pop withdraws demand with the pop (finding 5)" {
    // Model finding 5 (rv2_popwindow): with the withdraw deferred to the
    // receiver's own exit, the window between the pop and the withdraw kept
    // the token counted and admitted a second send against an
    // already-satisfied receiver. receive(holds_token = true) must close
    // the window inside the pop's mutex section.
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();
    sc.capacity = 0;

    shared_channel.commitRvDemand(sc);
    try std.testing.expectEqual(shared_channel.SendOutcome.sent, try shared_channel.send(sc, types.makeFixnum(1), null));

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const got = try shared_channel.receive(sc, &gc, null, true);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(got.value));
    // The pop consumed the token: demand is already zero, and a second
    // send is NOT admitted — pre-fix it was, and its value stranded.
    try std.testing.expectEqual(@as(u32, 0), sc.rv_demand);
    try std.testing.expectEqual(shared_channel.SendOutcome.would_park, try shared_channel.send(sc, types.makeFixnum(2), null));
    try std.testing.expectEqual(@as(u32, 0), sc.queue_len);

    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "shared rendezvous: tryTimeoutWithdraw is one lock section (finding 6)" {
    // Model finding 6 (rva_naive): a reservedCount() peek followed by a
    // separate withdraw let a sender reserve against the still-held token
    // in between. The single operation decides queue / reservation /
    // withdraw under one lock; this exercises its three outcomes.
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();
    sc.capacity = 0;

    // (1) idle: withdraws the held token.
    shared_channel.commitRvDemand(sc);
    try std.testing.expectEqual(shared_channel.TimeoutWithdrawOutcome.withdrawn, shared_channel.tryTimeoutWithdraw(sc, true));
    try std.testing.expectEqual(@as(u32, 0), sc.rv_demand);

    // (2) a committed handoff outranks the timer: delivery wins, token kept.
    shared_channel.commitRvDemand(sc);
    try std.testing.expectEqual(shared_channel.SendOutcome.sent, try shared_channel.send(sc, types.makeFixnum(7), null));
    try std.testing.expectEqual(shared_channel.TimeoutWithdrawOutcome.value_ready, shared_channel.tryTimeoutWithdraw(sc, true));
    try std.testing.expectEqual(@as(u32, 1), sc.rv_demand);
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    _ = try shared_channel.receive(sc, &gc, null, true);
    try std.testing.expectEqual(@as(u32, 0), sc.rv_demand);

    // (3) an in-flight reservation defers the decision (the drain rule).
    shared_channel.commitRvDemand(sc);
    memory.spinLock(&sc.lock);
    sc.reserved += 1; // simulate §4 step 7 mid-copy
    memory.spinUnlock(&sc.lock);
    try std.testing.expectEqual(shared_channel.TimeoutWithdrawOutcome.reservation_pending, shared_channel.tryTimeoutWithdraw(sc, true));
    try std.testing.expectEqual(@as(u32, 1), sc.rv_demand); // token retained
    memory.spinLock(&sc.lock);
    sc.reserved -= 1;
    memory.spinUnlock(&sc.lock);
    try std.testing.expectEqual(shared_channel.TimeoutWithdrawOutcome.withdrawn, shared_channel.tryTimeoutWithdraw(sc, true));
    try std.testing.expectEqual(@as(u32, 0), sc.rv_demand);

    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "shared rendezvous: close wakes a parked child-thread receiver (deterministic)" {
    // #1604 review: the Scheme twin of this test synchronizes with
    // thread-sleep!, which cannot prove the child parked before the close.
    // Here the parent polls sc.rv_demand — the child's commitment is
    // exactly the observable the demand counter provides — so the close is
    // guaranteed to exercise waking an already-parked cross-thread
    // receiver, not just a later receive seeing `closed`.
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define ch (make-channel 0))");
    // Capture a let-bound alias so the thunk's deepCopy promotes the
    // channel (a top-level global would fail the child's foreign-owner
    // check instead).
    _ = try ctx.vm.eval(
        \\(define t (thread-start!
        \\  (make-thread (let ((c ch))
        \\                 (lambda () (if (eof-object? (channel-receive c)) 'eof 'val))))))
    );
    const ch_val = try ctx.vm.eval("ch");
    const ch = types.toObject(ch_val).as(types.Channel);
    try std.testing.expect(ch.shared != null);
    const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(ch.shared.?));

    // Wait until the child has committed its demand (i.e. is parked).
    var spins: usize = 0;
    while (spins < 2000) : (spins += 1) {
        memory.spinLock(&sc.lock);
        const demand = sc.rv_demand;
        memory.spinUnlock(&sc.lock);
        if (demand > 0) break;
        platform.sleepNs(1 * std.time.ns_per_ms);
    }
    try std.testing.expect(spins < 2000);

    _ = try ctx.vm.eval("(channel-close! ch)");
    const joined = try ctx.vm.eval("(thread-join! t)");
    const printer = @import("printer.zig");
    const s = try printer.valueToString(std.testing.allocator, joined, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("eof", s);
    // The woken receiver's eof exit released its token.
    memory.spinLock(&sc.lock);
    const final_demand = sc.rv_demand;
    memory.spinUnlock(&sc.lock);
    try std.testing.expectEqual(@as(u32, 0), final_demand);
}
