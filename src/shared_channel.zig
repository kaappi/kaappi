const std = @import("std");
const shared_object = @import("shared_object.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;

/// KEP-0002 §5's cross-thread wakeup handle. Refcounted, but -- unlike
/// SharedChannel -- NOT an instance of the shared_object protocol: its
/// references come only from SharedChannel waiter lists (§7), never from
/// heap stubs, so it has its own plain refcount and is invisible to
/// shared_object.liveCount()'s leak check.
///
/// Phase 1 wires up only the waiter-list bookkeeping (registration, dedup,
/// snapshot-and-clear) needed to make promotion and send/receive correct
/// and unit-testable. The reactor-backed notify() (kqueue EVFILT.USER /
/// eventfd) is KEP-0002 Phase 3 (#1468); until then `ring` below just
/// releases each registration's refcount.
pub const ThreadNotifier = struct {
    refcount: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};

fn retainNotifier(n: *ThreadNotifier) void {
    _ = n.refcount.fetchAdd(1, .monotonic);
}

fn releaseNotifier(n: *ThreadNotifier) void {
    _ = n.refcount.fetchSub(1, .acq_rel);
}

/// A message-sized private mini-heap (KEP-0002 §1): the sender's deepCopy
/// fills it once, the receiver's deepCopy drains it once, then it is
/// destroyed wholesale.
pub const Envelope = struct {
    gc: *memory.GC,
    value: Value = types.VOID,
    next: ?*Envelope = null,

    /// Builds a private mini-heap and deep-copies `payload` into it.
    /// Atomic from the caller's perspective: either this returns a fully
    /// built envelope, or it tears down everything it allocated and
    /// propagates deepCopy's error -- callers never have to decide whether
    /// a half-built envelope needs cleanup.
    pub fn create(payload: Value) !*Envelope {
        const gc = try std.heap.c_allocator.create(memory.GC);
        gc.* = memory.GC.init(std.heap.c_allocator);
        // Defense in depth: deepCopy's own no_collect guard already
        // suppresses any collection attempt while filling this heap (see
        // gc_deep_copy.zig); this additionally guards against ever running
        // a real collect() on a heap that no other GC's root marker can see.
        gc.enabled = false;
        errdefer {
            gc.deinit();
            std.heap.c_allocator.destroy(gc);
        }

        const env = try std.heap.c_allocator.create(Envelope);
        env.* = .{ .gc = gc };
        env.value = try gc.deepCopy(payload);
        return env;
    }

    /// Frees the entire message graph in one sweep -- gc.deinit() walks
    /// every tracked object through gc_collect.freeObject, which releases
    /// any stub refcounts the message holds (e.g. a channel-in-channel
    /// self-send's aliased stub). No separate envelope-specific bookkeeping
    /// exists; this is the same teardown path a real GC uses.
    pub fn deinit(self: *Envelope) void {
        self.gc.deinit();
        std.heap.c_allocator.destroy(self.gc);
        std.heap.c_allocator.destroy(self);
    }
};

pub const SharedChannel = struct {
    header: shared_object.Header = undefined,
    // Zig 0.16 has no blocking std.Thread.Mutex (std.Io.Mutex needs an Io
    // instance); this codebase's established substitute is memory.zig's
    // lock-free spin mutex (matches memory.symbol_mutex, ChildRegistry.mutex
    // in primitives_srfi18.zig). Held only for O(1) queue/waiter-list
    // operations -- the envelope build always happens with it released.
    lock: std.atomic.Mutex = .unlocked,
    queue_head: ?*Envelope = null,
    queue_tail: ?*Envelope = null,
    queue_len: u32 = 0,
    /// Slots claimed by in-flight sends (§4) -- always 0 outside a send()
    /// call in progress.
    reserved: u32 = 0,
    /// null = unbounded. Always null in Phase 1: no Scheme-level API sets
    /// this yet (make-channel with a capacity argument is Phase 4);
    /// reachable in Phase 1 only via a white-box test that constructs a
    /// SharedChannel directly.
    capacity: ?u32 = null,
    /// Always false in Phase 1: channel-close! is Phase 4.
    closed: bool = false,
    recv_waiters: std.ArrayList(*ThreadNotifier) = .empty,
    send_waiters: std.ArrayList(*ThreadNotifier) = .empty,

    /// §1 refcount state machine: creates with refcount 1 -- the promoting
    /// object itself becomes the first counted stub.
    pub fn create() !*SharedChannel {
        const self = try std.heap.c_allocator.create(SharedChannel);
        self.* = .{};
        shared_object.init(&self.header, destroyHook);
        return self;
    }

    /// +1: a new stub was created (deepCopy's alias arm).
    pub fn retain(self: *SharedChannel) void {
        shared_object.retain(&self.header);
    }

    /// -1: a stub was freed. Destroys at zero.
    pub fn release(self: *SharedChannel) void {
        shared_object.release(&self.header);
    }

    /// §1 rule 4 / §7: zero destroys. Drains and deinits every queued
    /// envelope (recursively releasing any stub refcounts those messages
    /// hold -- this is what reclaims a channel that was only kept alive by
    /// a stub inside its own queue, once that queue itself is finally
    /// drained), releases remaining waiter registrations, frees.
    fn destroyHook(header: *shared_object.Header) void {
        const self: *SharedChannel = @fieldParentPtr("header", header);

        memory.spinLock(&self.lock);
        var env = self.queue_head;
        self.queue_head = null;
        self.queue_tail = null;
        self.queue_len = 0;
        memory.spinUnlock(&self.lock);

        while (env) |e| {
            const next = e.next;
            e.deinit();
            env = next;
        }

        for (self.recv_waiters.items) |n| releaseNotifier(n);
        for (self.send_waiters.items) |n| releaseNotifier(n);
        self.recv_waiters.deinit(std.heap.c_allocator);
        self.send_waiters.deinit(std.heap.c_allocator);
        std.heap.c_allocator.destroy(self);
    }

    // -- intrusive FIFO: caller holds `lock` --

    fn pushBack(self: *SharedChannel, env: *Envelope) void {
        env.next = null;
        if (self.queue_tail) |tail| {
            tail.next = env;
        } else {
            self.queue_head = env;
        }
        self.queue_tail = env;
        self.queue_len += 1;
    }

    fn popFront(self: *SharedChannel) ?*Envelope {
        const env = self.queue_head orelse return null;
        self.queue_head = env.next;
        if (self.queue_head == null) self.queue_tail = null;
        env.next = null;
        self.queue_len -= 1;
        return env;
    }

    /// §4 receive-side copy failure: re-queue at the head, FIFO preserved
    /// ("receive fails ⇒ nothing received").
    fn pushFront(self: *SharedChannel, env: *Envelope) void {
        env.next = self.queue_head;
        if (self.queue_head == null) self.queue_tail = env;
        self.queue_head = env;
        self.queue_len += 1;
    }

    // -- §7 waiter lifecycle: caller holds `lock` --

    fn registerSendWaiter(self: *SharedChannel, n: *ThreadNotifier) void {
        for (self.send_waiters.items) |existing| {
            if (existing == n) return; // dedup: at most one entry per notifier per list
        }
        self.send_waiters.append(std.heap.c_allocator, n) catch @panic("SharedChannel: send_waiters OOM");
        retainNotifier(n);
    }

    fn registerRecvWaiter(self: *SharedChannel, n: *ThreadNotifier) void {
        for (self.recv_waiters.items) |existing| {
            if (existing == n) return;
        }
        self.recv_waiters.append(std.heap.c_allocator, n) catch @panic("SharedChannel: recv_waiters OOM");
        retainNotifier(n);
    }

    fn snapshotAndClearSendWaiters(self: *SharedChannel, out: *std.ArrayList(*ThreadNotifier)) void {
        out.appendSlice(std.heap.c_allocator, self.send_waiters.items) catch @panic("SharedChannel: snapshot OOM");
        self.send_waiters.clearRetainingCapacity();
    }

    fn snapshotAndClearRecvWaiters(self: *SharedChannel, out: *std.ArrayList(*ThreadNotifier)) void {
        out.appendSlice(std.heap.c_allocator, self.recv_waiters.items) catch @panic("SharedChannel: snapshot OOM");
        self.recv_waiters.clearRetainingCapacity();
    }
};

/// §5: ring every notifier in a snapshot taken under the lock, after
/// releasing it -- a live waiter list is never iterated unlocked. Phase 3
/// (#1468) adds the real reactor notify() call here; Phase 1 just releases
/// each registration's refcount, since nothing else consumes the snapshot.
fn ring(notifiers: []const *ThreadNotifier) void {
    for (notifiers) |n| releaseNotifier(n);
}

/// KEP-0002 §2. Promotes `ch` in place -- the existing heap object becomes
/// stub #1, no new allocation for the promoting side. Callable only by the
/// thread that owns the channel (invariant 4); the real, catchable
/// enforcement of that is the ownership check in gc_deep_copy.zig's
/// `.channel` arm, the only caller. This assert documents (and, in Debug/
/// gc-stress builds, guards) the precondition at the one function whose
/// contract depends on it.
pub fn promoteChannel(gc: *memory.GC, ch: *types.Channel) !*SharedChannel {
    if (ch.shared) |raw| {
        return @ptrCast(@alignCast(raw));
    }
    std.debug.assert(ch.header.owner == gc.id);

    const sc = try SharedChannel.create();
    // Publish before draining (§2 step 2): a queued local message may
    // contain this very channel (e.g. (channel-send ch (list ch))). With
    // `shared` already set, the drain's own Envelope.create -> deepCopy
    // sees an already-promoted channel and takes the alias path instead of
    // starting a second, competing promotion that would split the queue.
    ch.shared = sc;

    var cur = ch.head;
    ch.head = types.NIL;
    ch.tail = types.NIL;
    // A queued local message can itself be uncopyable (e.g. a port -- legal
    // to have queued locally, since a purely local channel never copies
    // anything). That propagates the error here with `ch` left promoted and
    // the queue partially drained; not exercised by Phase 1's acceptance
    // tests, and acceptable for a same-thread failure mode with no cross-
    // heap sharing involved yet.
    while (cur != types.NIL) {
        const pair = types.toObject(cur).as(types.Pair);
        const next = pair.cdr;
        const env = try Envelope.create(pair.car);
        sc.pushBack(env);
        cur = next;
    }
    return sc;
}

pub const SendOutcome = union(enum) {
    sent,
    would_park,
    closed,
};

/// KEP-0002 §4 send, on the shared representation, verbatim. `notifier` is
/// registered only by the full-channel park branch, which is provably
/// unreachable through the public Scheme API in Phase 1 (capacity is
/// always null) -- callers that only ever pass unbounded/open channels may
/// pass null.
pub fn send(sc: *SharedChannel, payload: Value, notifier: ?*ThreadNotifier) !SendOutcome {
    memory.spinLock(&sc.lock);
    if (sc.closed) {
        memory.spinUnlock(&sc.lock);
        return .closed;
    }
    if (sc.capacity) |cap| {
        if (sc.queue_len + sc.reserved >= cap) {
            sc.registerSendWaiter(notifier.?);
            memory.spinUnlock(&sc.lock);
            return .would_park;
        }
    }
    sc.reserved += 1;
    memory.spinUnlock(&sc.lock);

    // Built outside the lock: deepCopy allocates and must not hold the
    // channel mutex. A reservation was already taken, so the eventual push
    // (on success) is infallible.
    const env = Envelope.create(payload) catch |err| {
        memory.spinLock(&sc.lock);
        sc.reserved -= 1;
        var snap: std.ArrayList(*ThreadNotifier) = .empty;
        defer snap.deinit(std.heap.c_allocator);
        sc.snapshotAndClearSendWaiters(&snap);
        // A receiver may be parked waiting out this very reservation
        // (receive step 6's reserved==0 eof guard) if the channel closed
        // while this send was in flight.
        if (sc.closed) sc.snapshotAndClearRecvWaiters(&snap);
        memory.spinUnlock(&sc.lock);
        ring(snap.items);
        // Nothing was enqueued ("send fails ⇒ nothing sent"); Envelope
        // .create already tore itself down internally on failure.
        return err;
    };

    memory.spinLock(&sc.lock);
    sc.reserved -= 1;
    sc.pushBack(env);
    var snap: std.ArrayList(*ThreadNotifier) = .empty;
    defer snap.deinit(std.heap.c_allocator);
    sc.snapshotAndClearRecvWaiters(&snap);
    memory.spinUnlock(&sc.lock);
    ring(snap.items);
    return .sent;
}

pub const RecvOutcome = union(enum) {
    value: Value,
    would_park,
    eof,
};

/// KEP-0002 §4 receive, on the shared representation, verbatim.
pub fn receive(sc: *SharedChannel, dest_gc: *memory.GC, notifier: ?*ThreadNotifier) !RecvOutcome {
    memory.spinLock(&sc.lock);
    if (sc.popFront()) |env| {
        var snap: std.ArrayList(*ThreadNotifier) = .empty;
        defer snap.deinit(std.heap.c_allocator);
        sc.snapshotAndClearSendWaiters(&snap); // a slot opened
        memory.spinUnlock(&sc.lock);
        ring(snap.items);

        const value = dest_gc.deepCopy(env.value) catch |err| {
            // "Receive fails ⇒ nothing received": the envelope is
            // untouched, its stubs keep their refcounts, the message stays
            // deliverable in order. Re-queue at the head, not the tail.
            memory.spinLock(&sc.lock);
            sc.pushFront(env);
            var recv_snap: std.ArrayList(*ThreadNotifier) = .empty;
            defer recv_snap.deinit(std.heap.c_allocator);
            sc.snapshotAndClearRecvWaiters(&recv_snap);
            memory.spinUnlock(&sc.lock);
            ring(recv_snap.items);
            return err;
        };
        env.deinit();
        return .{ .value = value };
    }
    if (sc.closed and sc.reserved == 0) {
        memory.spinUnlock(&sc.lock);
        return .eof;
    }
    // Reached with the channel open, or closed with admitted sends still in
    // flight: eof must not race a reservation, so the receiver parks and is
    // rung by the late push (or by send's failure-path closed-channel ring).
    sc.registerRecvWaiter(notifier.?);
    memory.spinUnlock(&sc.lock);
    return .would_park;
}
