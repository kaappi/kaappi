const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const shared_channel = @import("shared_channel.zig");
const shared_object = @import("shared_object.zig");
const th = @import("testing_helpers.zig");

// KEP-0002 Phase 1 (#1466). Everything here follows tests_deepcopy.zig's
// bare-GC pattern (no VM, no fiber scheduler) except the last regression
// test, which drives a real VM and OS thread. Any test that exercises the
// deepCopy ownership check must save/restore `memory.gc_instance`, a
// process-global threadlocal not reset between Zig tests.
//
// shared_object.liveCount() is a real process-global counter (unlike
// std.testing.allocator, it is NOT reset per test), so every test captures
// its own baseline and asserts a return to that baseline rather than to
// zero -- except the one test that demonstrates the documented refcount
// cycle leak, which asserts a permanent +1.
//
// GC-safety note: SharedChannel/Envelope live outside every GC heap
// (std.heap.c_allocator), so building/tearing them down never risks a
// gc-stress collection. Where a test's own bare GC (gc1, outer_gc, ...)
// performs more than one allocation with an unrooted Channel value live in
// a Zig local across them, that value is rooted via pushRoot/popRoot per
// .claude/rules/gc-safety.md.

var shared_object_test_destroy_count: u32 = 0;
fn testDestroyHook(_: *shared_object.Header) void {
    shared_object_test_destroy_count += 1;
}

test "shared_object: init/retain/release destroys exactly at zero" {
    const baseline = shared_object.liveCount();
    shared_object_test_destroy_count = 0;

    var header: shared_object.Header = undefined;
    shared_object.init(&header, testDestroyHook);
    try std.testing.expectEqual(baseline + 1, shared_object.liveCount());

    shared_object.retain(&header);
    shared_object.retain(&header);
    shared_object.release(&header);
    shared_object.release(&header);
    try std.testing.expectEqual(@as(u32, 0), shared_object_test_destroy_count);
    try std.testing.expectEqual(baseline + 1, shared_object.liveCount());

    shared_object.release(&header);
    try std.testing.expectEqual(@as(u32, 1), shared_object_test_destroy_count);
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "promoteChannel on an empty channel: refcount 1, queue empty, head/tail cleared" {
    const baseline = shared_object.liveCount();
    var gc1 = memory.GC.init(std.testing.allocator);

    const ch_val = try gc1.allocChannel();
    const ch = types.toObject(ch_val).as(types.Channel);

    const sc = try shared_channel.promoteChannel(&gc1, ch);
    try std.testing.expect(ch.shared != null);
    try std.testing.expectEqual(@as(?*shared_channel.Envelope, null), sc.queue_head);
    try std.testing.expectEqual(@as(u32, 0), sc.queue_len);
    try std.testing.expectEqual(types.NIL, ch.head);
    try std.testing.expectEqual(types.NIL, ch.tail);

    // Idempotent: a second call returns the same SharedChannel, no new stub.
    const sc_again = try shared_channel.promoteChannel(&gc1, ch);
    try std.testing.expectEqual(sc, sc_again);

    // `ch` itself is stub #1 (§1: "the promoting object itself becomes the
    // first counted stub") -- gc1.deinit() releases sc's refcount via ch's
    // own freeObject teardown. Do NOT also call sc.release() here: ch is
    // still tracked by gc1, so that would double-release (and, since
    // release() frees at zero, double-free) the same stub.
    gc1.deinit();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "promoteChannel on a non-empty channel: drains FIFO order into envelopes" {
    const baseline = shared_object.liveCount();
    var gc1 = memory.GC.init(std.testing.allocator);

    var ch_val = try gc1.allocChannel();
    gc1.pushRoot(&ch_val);
    const ch = types.toObject(ch_val).as(types.Channel);

    // Enqueue 1, 2, 3 the same way channel-send's local path does.
    var n: i64 = 1;
    while (n <= 3) : (n += 1) {
        const new_pair = try gc1.allocPair(types.makeFixnum(n), types.NIL);
        if (ch.tail != types.NIL) {
            types.toObject(ch.tail).as(types.Pair).cdr = new_pair;
        }
        ch.tail = new_pair;
        if (ch.head == types.NIL) ch.head = new_pair;
        gc1.writeBarrier(types.toObject(ch_val), new_pair);
    }
    gc1.popRoot();

    const sc = try shared_channel.promoteChannel(&gc1, ch);

    var expected: i64 = 1;
    var env = sc.queue_head;
    while (env) |e| : (expected += 1) {
        try std.testing.expectEqual(expected, types.toFixnum(e.value));
        env = e.next;
    }
    try std.testing.expectEqual(@as(i64, 4), expected);
    try std.testing.expectEqual(@as(u32, 3), sc.queue_len);

    // As above: ch owns stub #1, so gc1.deinit() alone releases it (and,
    // recursively, sc's destroyHook then drains and deinits the 3 queued
    // envelopes) -- no separate sc.release() call.
    gc1.deinit();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "deepCopy .channel arm promotes on first encounter and aliases thereafter (channel-in-channel identity)" {
    const baseline = shared_object.liveCount();
    var gc1 = memory.GC.init(std.testing.allocator);
    var gc2 = memory.GC.init(std.testing.allocator);
    var gc3 = memory.GC.init(std.testing.allocator);

    const ch_val = try gc1.allocChannel();
    const ch = types.toObject(ch_val).as(types.Channel);
    try std.testing.expect(ch.shared == null);

    const saved_gc = memory.gc_instance;
    defer memory.gc_instance = saved_gc;
    memory.gc_instance = &gc1; // gc1 is the calling thread's own gc -- legal to promote
    const stub2 = try gc2.deepCopy(ch_val);
    const stub3 = try gc3.deepCopy(ch_val);

    try std.testing.expect(ch.shared != null); // promoted by the first deepCopy

    const sc2 = types.toObject(stub2).as(types.Channel).shared.?;
    const sc3 = types.toObject(stub3).as(types.Channel).shared.?;
    // Same SharedChannel across two independently-copied stubs: identity survives.
    try std.testing.expectEqual(sc2, sc3);
    try std.testing.expect(stub2 != stub3); // distinct heap objects, though

    gc1.deinit();
    gc2.deinit();
    gc3.deinit();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "deepCopy .channel arm rejects a foreign, unpromoted channel" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();
    var gc3 = memory.GC.init(std.testing.allocator);
    defer gc3.deinit();

    const ch_val = try gc1.allocChannel(); // owned by gc1, never promoted

    const saved_gc = memory.gc_instance;
    defer memory.gc_instance = saved_gc;
    memory.gc_instance = &gc3; // gc3 is neither the owner nor the destination

    try std.testing.expectError(error.UncopyableType, gc2.deepCopy(ch_val));
    try std.testing.expect(types.toObject(ch_val).as(types.Channel).shared == null);
}

test "re-entrant promotion: a channel whose own queue contains itself (and the documented cycle leak)" {
    const baseline = shared_object.liveCount();
    var gc1 = memory.GC.init(std.testing.allocator);

    var ch_val = try gc1.allocChannel();
    gc1.pushRoot(&ch_val);
    const ch = types.toObject(ch_val).as(types.Channel);
    // Mirrors (channel-send ch ch) on the local path.
    const self_pair = try gc1.allocPair(ch_val, types.NIL);
    ch.head = self_pair;
    ch.tail = self_pair;
    gc1.writeBarrier(types.toObject(ch_val), self_pair);
    gc1.popRoot();

    const sc = try shared_channel.promoteChannel(&gc1, ch);

    // The drain's own deepCopy meets `ch` again mid-promotion; with `shared`
    // already published (step 2), it must take the alias path, not start a
    // second, competing promotion.
    try std.testing.expectEqual(@as(u32, 1), sc.queue_len);
    const env = sc.queue_head.?;
    const inner_ch = types.toObject(env.value).as(types.Channel);
    try std.testing.expect(inner_ch.shared != null);
    const inner_sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(inner_ch.shared.?));
    try std.testing.expectEqual(sc, inner_sc);

    // Known limitation (§1): the envelope holds a stub of `sc` itself, so
    // dropping ch's own stub can never bring refcount to zero -- the last
    // reference is the stub inside sc's own queue. This is the accepted
    // refcount-cycle leak, not a bug: assert it is *present* and stable, so
    // this test breaks loudly if the leak's behavior ever silently changes.
    gc1.deinit();
    try std.testing.expectEqual(baseline + 1, shared_object.liveCount());
}

test "refcount teardown: a channel-in-channel message drains and destroys recursively when never received" {
    const baseline = shared_object.liveCount();
    var outer_gc = memory.GC.init(std.testing.allocator);
    var inner_gc = memory.GC.init(std.testing.allocator);

    var outer_val = try outer_gc.allocChannel(); // channel A
    outer_gc.pushRoot(&outer_val);
    const outer_ch = types.toObject(outer_val).as(types.Channel);

    const inner_val = try inner_gc.allocChannel(); // channel B, a DIFFERENT SharedChannel

    const saved_gc = memory.gc_instance;
    defer memory.gc_instance = saved_gc;
    memory.gc_instance = &inner_gc; // B's owner, for its promotion
    const b_stub_on_outer = try outer_gc.deepCopy(inner_val); // promotes B, aliases onto outer_gc

    var b_stub_root = b_stub_on_outer;
    outer_gc.pushRoot(&b_stub_root);
    const pair = try outer_gc.allocPair(b_stub_on_outer, types.NIL); // A's local queue holds B's stub
    outer_gc.popRoot();

    outer_ch.head = pair;
    outer_ch.tail = pair;
    outer_gc.writeBarrier(types.toObject(outer_val), pair);
    outer_gc.popRoot(); // outer_val

    memory.gc_instance = &outer_gc; // A's owner, for its own promotion
    const sc_a = try shared_channel.promoteChannel(&outer_gc, outer_ch);

    try std.testing.expectEqual(@as(u32, 1), sc_a.queue_len);

    // Neither channel is ever received. Dropping every stub (both GCs'
    // teardown) must still recursively release B's refcount via A's queued
    // envelope's own teardown -- no separate envelope bookkeeping exists.
    outer_gc.deinit();
    inner_gc.deinit();

    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "reply-to worked example (§1): the received half, with the rc 1->2->3->2 progression" {
    const baseline = shared_object.liveCount();
    var sender_gc = memory.GC.init(std.testing.allocator);
    var dest_gc = memory.GC.init(std.testing.allocator);

    const saved_gc = memory.gc_instance;
    defer memory.gc_instance = saved_gc;
    memory.gc_instance = &sender_gc;

    // "tasks" is already shared before this send, per the KEP's own framing.
    // Rooted for the whole test: nothing else keeps it GC-reachable, and a
    // gc-stress collection triggered by the *next* allocation would
    // otherwise sweep it -- freeObject's .channel arm would then release
    // tasks_sc's only refcount and destroy it out from under this test.
    var tasks_val = try sender_gc.allocChannel();
    sender_gc.pushRoot(&tasks_val);
    const tasks_ch = types.toObject(tasks_val).as(types.Channel);
    const tasks_sc = try shared_channel.promoteChannel(&sender_gc, tasks_ch);

    // "reply" starts local to the sender -- rc 1 (its own stub) once sent.
    var reply_val = try sender_gc.allocChannel();
    sender_gc.pushRoot(&reply_val);
    const reply_ch = types.toObject(reply_val).as(types.Channel);
    try std.testing.expect(reply_ch.shared == null);

    const send_outcome = try shared_channel.send(tasks_sc, reply_val, null);
    try std.testing.expectEqual(shared_channel.SendOutcome.sent, send_outcome);
    try std.testing.expect(reply_ch.shared != null); // promoted as a side effect of the send
    const reply_sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(reply_ch.shared.?));

    // Receive on a *different* heap: the copied-out value's alias arm runs
    // against an envelope-owned stub (obj.owner = the envelope GC's id, not
    // memory.gc_instance) -- exactly why the alias path deliberately skips
    // the ownership check.
    const recv_outcome = try shared_channel.receive(tasks_sc, &dest_gc, null);
    const received_val = switch (recv_outcome) {
        .value => |v| v,
        else => return error.TestUnexpectedResult,
    };
    const received_ch = types.toObject(received_val).as(types.Channel);
    try std.testing.expect(received_ch.shared != null);
    const received_sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(received_ch.shared.?));

    // Identity survives the round trip: a different heap object aliasing
    // the same SharedChannel -- this is what makes reply-to patterns work.
    try std.testing.expectEqual(reply_sc, received_sc);
    try std.testing.expect(received_val != reply_val);

    // rc is now 2 (reply's own stub + the received stub) -- the envelope's
    // own transient stub already released via envelope.deinit() inside
    // receive(). Tear down both remaining stubs (plus tasks' unrelated one).
    sender_gc.popRoot(); // reply_val
    sender_gc.popRoot(); // tasks_val
    sender_gc.deinit();
    dest_gc.deinit();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "primitive dispatch: channel-send/channel-receive route through the shared path once promoted" {
    // th.TestContext doesn't reset memory.gc_instance on deinit (a pre-
    // existing gap shared by every VM-based test); harmless there since
    // nothing else reads the threadlocal outside an active eval, but this
    // test also pokes shared_channel.zig directly, so restore explicitly.
    const saved_gc = memory.gc_instance;
    defer memory.gc_instance = saved_gc;

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define ch (make-channel))");
    const ch_val = try ctx.vm.eval("ch");
    const ch = types.toObject(ch_val).as(types.Channel);

    // White-box promotion: Phase 1 has no Scheme-level way to reach this
    // state (see the module doc comment), but channelSendFn/channelReceiveFn
    // must still dispatch correctly once a channel *is* promoted, since
    // Phases 2/3 build on exactly this contract.
    _ = try shared_channel.promoteChannel(&ctx.gc, ch);
    try std.testing.expect(ch.shared != null);

    const send_result = try ctx.vm.eval("(channel-send ch 1)");
    try std.testing.expectEqual(types.VOID, send_result);

    const recv_result = try ctx.vm.eval("(channel-receive ch)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(recv_result));
}

test "send: succeeds on an unbounded, open channel and pushes an envelope" {
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();

    var src_gc = memory.GC.init(std.testing.allocator);
    const payload = try src_gc.allocPair(types.makeFixnum(7), types.NIL);

    const outcome = try shared_channel.send(sc, payload, null);
    try std.testing.expectEqual(shared_channel.SendOutcome.sent, outcome);
    try std.testing.expectEqual(@as(u32, 1), sc.queue_len);
    try std.testing.expectEqual(@as(u32, 0), sc.reserved);

    src_gc.deinit();
    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "send: payload is deep-copied into an independent envelope heap" {
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();

    var src_gc = memory.GC.init(std.testing.allocator);
    const payload = try src_gc.allocPair(types.makeFixnum(1), types.NIL);

    _ = try shared_channel.send(sc, payload, null);

    // Mutate the original after sending -- the envelope's copy must be unaffected.
    types.toObject(payload).as(types.Pair).car = types.makeFixnum(999);

    const env = sc.queue_head.?;
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(env.value)));

    src_gc.deinit();
    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "send: build failure leaves the queue and reservation untouched (send fails => nothing sent)" {
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();

    var src_gc = memory.GC.init(std.testing.allocator);
    const port = try src_gc.allocStringInputPort("x"); // uncopyable

    try std.testing.expectError(error.UncopyableType, shared_channel.send(sc, port, null));
    try std.testing.expectEqual(@as(u32, 0), sc.queue_len);
    try std.testing.expectEqual(@as(u32, 0), sc.reserved);
    try std.testing.expectEqual(@as(?*shared_channel.Envelope, null), sc.queue_head);

    src_gc.deinit();
    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "send: bounded-and-full channel registers a send waiter and would park" {
    // White-box: no Phase-1 Scheme API constructs a channel with a
    // non-null capacity yet (KEP-0002 Phase 4) -- direct construction only.
    const sc = try shared_channel.SharedChannel.create();
    sc.capacity = 0;

    var notifier = shared_channel.ThreadNotifier{};
    const outcome = try shared_channel.send(sc, types.makeFixnum(1), &notifier);
    try std.testing.expectEqual(shared_channel.SendOutcome.would_park, outcome);
    try std.testing.expectEqual(@as(usize, 1), sc.send_waiters.items.len);
    try std.testing.expectEqual(@as(u32, 1), notifier.refcount.load(.monotonic));

    sc.release();
}

test "send: registering the same waiter twice does not double the refcount (§7 dedup)" {
    const sc = try shared_channel.SharedChannel.create();
    sc.capacity = 0;
    var notifier = shared_channel.ThreadNotifier{};

    _ = try shared_channel.send(sc, types.makeFixnum(1), &notifier);
    _ = try shared_channel.send(sc, types.makeFixnum(2), &notifier);

    try std.testing.expectEqual(@as(usize, 1), sc.send_waiters.items.len);
    try std.testing.expectEqual(@as(u32, 1), notifier.refcount.load(.monotonic));

    sc.release();
}

test "send: on a closed channel returns .closed without mutating the queue" {
    const sc = try shared_channel.SharedChannel.create();
    sc.closed = true;

    const outcome = try shared_channel.send(sc, types.makeFixnum(1), null);
    try std.testing.expectEqual(shared_channel.SendOutcome.closed, outcome);
    try std.testing.expectEqual(@as(u32, 0), sc.queue_len);

    sc.release();
}

test "receive: pops a non-empty queue and deep-copies into the destination gc" {
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();

    var src_gc = memory.GC.init(std.testing.allocator);
    const payload = try src_gc.allocPair(types.makeFixnum(5), types.NIL);
    _ = try shared_channel.send(sc, payload, null);
    src_gc.deinit();

    var dest_gc = memory.GC.init(std.testing.allocator);
    const outcome = try shared_channel.receive(sc, &dest_gc, null);
    const value = switch (outcome) {
        .value => |v| v,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(types.car(value)));
    try std.testing.expectEqual(@as(u32, 0), sc.queue_len);

    dest_gc.deinit();
    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "receive: copy-out failure re-queues the envelope at the head (receive fails => nothing received)" {
    const baseline = shared_object.liveCount();
    const sc = try shared_channel.SharedChannel.create();

    var src_gc = memory.GC.init(std.testing.allocator);
    const payload = try src_gc.allocPair(types.makeFixnum(11), types.NIL);
    _ = try shared_channel.send(sc, payload, null);
    src_gc.deinit();

    var dest_gc = memory.GC.init(std.testing.allocator);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    dest_gc.allocator = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, shared_channel.receive(sc, &dest_gc, null));
    try std.testing.expectEqual(@as(u32, 1), sc.queue_len); // FIFO preserved: still queued

    dest_gc.allocator = std.testing.allocator; // restore before deinit (matches how it was built)
    dest_gc.deinit();

    // The message is still deliverable, in order, on a subsequent receive.
    var dest_gc2 = memory.GC.init(std.testing.allocator);
    const outcome = try shared_channel.receive(sc, &dest_gc2, null);
    const value = switch (outcome) {
        .value => |v| v,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(types.car(value)));

    dest_gc2.deinit();
    sc.release();
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "receive: empty and closed with reserved==0 returns eof" {
    const sc = try shared_channel.SharedChannel.create();
    sc.closed = true;

    var dest_gc = memory.GC.init(std.testing.allocator);
    defer dest_gc.deinit();

    const outcome = try shared_channel.receive(sc, &dest_gc, null);
    try std.testing.expectEqual(shared_channel.RecvOutcome.eof, outcome);

    sc.release();
}

test "receive: empty and open registers a recv waiter and would park" {
    const sc = try shared_channel.SharedChannel.create();

    var dest_gc = memory.GC.init(std.testing.allocator);
    defer dest_gc.deinit();
    var notifier = shared_channel.ThreadNotifier{};

    const outcome = try shared_channel.receive(sc, &dest_gc, &notifier);
    try std.testing.expectEqual(shared_channel.RecvOutcome.would_park, outcome);
    try std.testing.expectEqual(@as(usize, 1), sc.recv_waiters.items.len);
    try std.testing.expectEqual(@as(u32, 1), notifier.refcount.load(.monotonic));

    sc.release();
}

test "Motivation Path 2 regression: a channel reached through a shared global raises instead of corrupting memory" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // Before this fix: the child's channel-send spliced a child-heap pair
    // into the parent-heap channel, and a subsequent channel-receive read
    // freed/garbage memory. After: the foreign-owner check on
    // channel-send raises inside the child, reraised at thread-join!; the
    // channel is left untouched, so channel-receive correctly deadlocks
    // (nothing was ever sent) instead of returning corrupted data.
    const result = try ctx.vm.eval(
        \\(define ch (make-channel))
        \\(define send-result
        \\  (guard (e (#t 'caught))
        \\    (thread-join! (thread-start! (make-thread (lambda () (channel-send ch 42)))))
        \\    'not-caught))
        \\(define recv-result
        \\  (guard (e (#t 'deadlocked))
        \\    (channel-receive ch)))
        \\(list send-result recv-result)
    );
    const send_result = types.car(result);
    const recv_result = types.car(types.cdr(result));
    try std.testing.expect(types.isSymbol(send_result));
    try std.testing.expectEqualStrings("caught", types.symbolName(send_result));
    try std.testing.expect(types.isSymbol(recv_result));
    try std.testing.expectEqualStrings("deadlocked", types.symbolName(recv_result));
}

// ---------------------------------------------------------------------------
// KEP-0002 Phase 2 (#1467): envelopes at thread boundaries.
//
// thread-start! now copies the thunk into an envelope on the *parent*
// thread, before Thread.spawn -- the child copies out of the envelope into
// its own fresh heap instead of deepCopy-ing fiber.thunk directly out of the
// still-running parent heap. thread-join!'s result/exception cross the same
// way, built on the *child* thread right before it exits. Both directions
// are exercised here with real OS threads (make-thread/thread-start!), since
// the whole point of Phase 2 is the parent/child-thread timing -- a
// white-box, single-thread test of Envelope.create (already covered by
// Phase 1's tests above) can't observe the race Phase 2 closes.
// ---------------------------------------------------------------------------

test "KEP-0002 Phase 2: thunk snapshot -- mutation after thread-start! returns is not visible to the child" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // The envelope copy runs synchronously inside thread-start!, before it
    // ever returns -- so this is deterministic, not a race the test might
    // get lucky on. Before Phase 2, the child deepCopy'd fiber.thunk at some
    // arbitrary later point, so this mutation could (nondeterministically)
    // have already been visible.
    const result = try ctx.vm.eval(
        \\(let* ((v (vector 1))
        \\       (t (make-thread (lambda () (vector-ref v 0)))))
        \\  (thread-start! t)
        \\  (vector-set! v 0 999)
        \\  (thread-join! t))
    );
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result));
}

test "KEP-0002 Phase 2: Motivation Path 1 -- a channel captured in the thread thunk now works end-to-end" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // Before Phase 1+2: the child errored with "thread thunk contains
    // uncopyable type" (deepCopy rejected channels outright). Now: `ch` is
    // promoted on the parent thread as part of the envelope build (the only
    // legal place, per invariant 4), aliased into the child's heap on copy-
    // out, and the send completes entirely before thread-join! returns --
    // so the parent's subsequent receive needs no wakeup machinery
    // (Phase 2's scope explicitly excludes a receiver parking first).
    const result = try ctx.vm.eval(
        \\(let* ((ch (make-channel))
        \\       (t (make-thread (lambda () (channel-send ch 42)))))
        \\  (thread-start! t)
        \\  (thread-join! t)
        \\  (channel-receive ch))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "KEP-0002 Phase 2: a channel created and returned by the child promotes correctly" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // The join result now crosses via an envelope built on the CHILD thread
    // (the channel's owner) rather than deepCopy'd by the parent at join
    // time -- which is what makes this legal at all: promotion requires
    // gc_instance to match the channel's owner, true only while the child
    // itself is still running.
    const result = try ctx.vm.eval(
        \\(let* ((t (make-thread (lambda ()
        \\                          (let ((inner (make-channel)))
        \\                            (channel-send inner 'hello)
        \\                            inner)))))
        \\  (thread-start! t)
        \\  (let ((returned-ch (thread-join! t)))
        \\    (channel-receive returned-ch)))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("hello", types.symbolName(result));
}

test "KEP-0002 Phase 2: uncopyable thunk is detected synchronously in thread-start!, never spawns an OS thread" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // `m` must be a genuine lexical upvalue of the thunk (let*-bound, not a
    // top-level define) -- a global mutex reference is the *supported*
    // sharing path (see srfi18.scm's own header comment) and would resolve
    // through vm.globals without ever touching deepCopy at all, defeating
    // the point of this test.
    _ = try ctx.vm.eval(
        \\(define t (let* ((m (make-mutex))) (make-thread (lambda () (mutex-lock! m)))))
    );
    _ = try ctx.vm.eval("(thread-start! t)");

    const t_val = try ctx.vm.eval("t");
    const fiber = types.toObject(t_val).as(@import("fiber.zig").Fiber);
    // White-box: thread-start! caught the UncopyableType error while
    // building the envelope and never called std.Thread.spawn at all.
    try std.testing.expect(fiber.os_thread == null);
    try std.testing.expectEqual(@import("fiber.zig").FiberStatus.errored, fiber.status);

    // Scheme-visible behavior is unchanged: thread-join! still reraises it
    // as an uncaught-exception in the thread (matches
    // tests/scheme/srfi/srfi18.scm's "OS threads cannot capture sync
    // primitives" test).
    const caught = try ctx.vm.eval(
        \\(guard (e (#t (uncaught-exception? e))) (thread-join! t) #f)
    );
    try std.testing.expectEqual(types.TRUE, caught);
}

test "KEP-0002 Phase 2: thread churn -- repeated cross-thread channel round trips leave no refcount leak" {
    const baseline = shared_object.liveCount();
    {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();

        // Each iteration promotes a fresh channel (captured by the thunk),
        // sends across the thread boundary, joins (tearing down the child's
        // heap immediately), and receives -- exercising exactly the
        // "envelope queued by a thread that has already exited its heap"
        // path the KEP's acceptance criteria call out.
        const result = try ctx.vm.eval(
            \\(let loop ((i 0) (acc 0))
            \\  (if (= i 20)
            \\      acc
            \\      (let* ((ch (make-channel))
            \\             (t (make-thread (lambda () (channel-send ch i)))))
            \\        (thread-start! t)
            \\        (thread-join! t)
            \\        (loop (+ i 1) (+ acc (channel-receive ch))))))
        );
        try std.testing.expectEqual(@as(i64, 190), types.toFixnum(result)); // sum 0..19
    }
    // ctx.deinit() above frees every tracked object regardless of Scheme-
    // level reachability, including each iteration's channel stub -- so
    // every promoted SharedChannel's refcount must have already reached
    // zero (destroyed) via ordinary send/receive/envelope teardown well
    // before this point, or it would still show up here.
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}

test "KEP-0002 Phase 2: an exception raised in the child carrying a channel promotes via the exception envelope" {
    const baseline = shared_object.liveCount();
    {
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();

        // The exception object (an error-object wrapping the channel as an
        // irritant) is built into an envelope on the child thread -- the
        // same promotion-legality argument as a returned value, but via the
        // errored path in threadEntryFn instead of the completed path.
        const result = try ctx.vm.eval(
            \\(let* ((t (make-thread (lambda ()
            \\                          (let ((inner (make-channel)))
            \\                            (channel-send inner 'irritant-marker)
            \\                            (error "boom" inner))))))
            \\  (thread-start! t)
            \\  (guard (e (#t (car (error-object-irritants (uncaught-exception-reason e)))))
            \\    (thread-join! t)
            \\    'not-caught))
        );
        const inner_ch = types.toObject(result);
        try std.testing.expectEqual(types.ObjectTag.channel, inner_ch.tag);
        try std.testing.expect(inner_ch.as(types.Channel).shared != null);
    }
    try std.testing.expectEqual(baseline, shared_object.liveCount());
}
