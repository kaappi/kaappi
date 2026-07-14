const std = @import("std");
const shared_object = @import("shared_object.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const reactor_mod = @import("reactor.zig");
const vm_mod = @import("vm.zig");
const pct_stress = @import("pct_stress.zig");
const instrument = @import("channel_instrument.zig");
const Value = types.Value;

/// KEP-0002 Phase 3 (#1468) PCT stress hook: a no-op unless
/// src/stress_channel.zig has enabled pct_stress, in which case it injects
/// a randomized yield point around every SharedChannel lock acquire/release
/// -- exactly the interleavings the model-checked send/receive protocol
/// (§4) needs to survive under real scheduling, not just on paper.
fn lockChannel(sc: *SharedChannel) void {
    pct_stress.maybeYield();
    memory.spinLock(&sc.lock);
    pct_stress.maybeYield();
}

fn unlockChannel(sc: *SharedChannel) void {
    pct_stress.maybeYield();
    memory.spinUnlock(&sc.lock);
}

/// KEP-0002 §5's cross-thread wakeup handle -- defined in reactor.zig (its
/// ring mechanism needs the live kqueue/epoll backend internals that module
/// owns privately). Aliased here under its original name so the rest of
/// this file (registration, dedup, waiter lists, all written against Phase
/// 1) reads unchanged.
const ThreadNotifier = reactor_mod.ThreadNotifier;
const retainNotifier = reactor_mod.retainNotifier;
const releaseNotifier = reactor_mod.releaseNotifier;

/// A message-sized private mini-heap (KEP-0002 §1): the sender's deepCopy
/// fills it once, the receiver's deepCopy drains it once, then it is
/// destroyed wholesale.
pub const Envelope = struct {
    /// null only for a lever-C/C+D immediate envelope (KEP-0002 Phase 7,
    /// kaappi#1472): a fixnum/boolean/char/flonum/nil payload is self-contained,
    /// so no private heap is built and `value` holds the immediate directly.
    /// Always non-null in the shipped default (lever `none`), where every
    /// message gets its own heap exactly as originally specified.
    gc: ?*memory.GC,
    value: Value = types.VOID,
    next: ?*Envelope = null,

    /// Builds a private mini-heap and deep-copies `payload` into it.
    /// Atomic from the caller's perspective: either this returns a fully
    /// built envelope, or it tears down everything it allocated and
    /// propagates deepCopy's error -- callers never have to decide whether
    /// a half-built envelope needs cleanup.
    ///
    /// Deliberate deviation from KEP-0002 §1's "the same way GC.initForThread
    /// does (sharing the process-wide symbol table)": this uses plain
    /// GC.init, a private per-envelope symbol table, so a message's symbols
    /// are copied rather than aliased. An envelope can outlive the thread
    /// that built it (§7: a sender may exit while its message is still
    /// queued), so aliasing that thread's symbol table would leave the
    /// envelope holding Symbol objects the owning GC could already have
    /// freed by the time a receiver -- or destroyHook, on whichever thread
    /// drops the last refcount -- reads the graph: a use-after-free. The
    /// cost is that a symbol crossing a channel is `equal?` but not
    /// necessarily `eq?` to the receiver's own copy of the same name;
    /// revisit only alongside a genuinely process-global (not per-thread
    /// chained) symbol table.
    pub fn create(payload: Value) !*Envelope {
        // Lever C / C+D (kaappi#1472): a non-pointer immediate is self-contained
        // -- deepCopy returns it unchanged -- so skip the per-message heap (and
        // its GC struct + ~8 KiB root buffer) entirely. Comptime-pruned to the
        // shipped path below whenever the instrument build flag is off.
        if (instrument.immediatesElided() and !types.isPointer(payload)) {
            const env = try std.heap.c_allocator.create(Envelope);
            env.* = .{ .gc = null, .value = payload };
            return env;
        }

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
        errdefer std.heap.c_allocator.destroy(env);
        env.* = .{ .gc = gc };
        env.value = try gc.deepCopy(payload);
        // Secondary metric (§3): the live per-message heap footprint invisible
        // to any GC. No-op when the instrument flag is off.
        instrument.envelopeBytesAdd(gc.bytes_allocated);
        return env;
    }

    /// Frees the entire message graph in one sweep -- gc.deinit() walks
    /// every tracked object through gc_collect.freeObject, which releases
    /// any stub refcounts the message holds (e.g. a channel-in-channel
    /// self-send's aliased stub). No separate envelope-specific bookkeeping
    /// exists; this is the same teardown path a real GC uses.
    pub fn deinit(self: *Envelope) void {
        if (self.gc) |gc| {
            instrument.envelopeBytesSub(gc.bytes_allocated);
            gc.deinit();
            std.heap.c_allocator.destroy(gc);
        }
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
    /// null = unbounded (KEP-0002 §6, `make-channel`'s optional capacity
    /// argument). Set once, by promoteChannel, from the local
    /// representation's own `capacity` field -- never mutated after.
    capacity: ?u32 = null,
    /// KEP-0002 §6, `channel-close!`. Set once (true), by promoteChannel
    /// (carried over from an already-closed local channel) or by close().
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

    /// Heuristic-only read (KEP-0002 §5's deadlock-heuristic disjunct:
    /// "wakeup possible whenever refcount > 1"). See
    /// shared_object.loadRefcount's doc comment.
    pub fn refCount(self: *SharedChannel) u32 {
        return shared_object.loadRefcount(&self.header);
    }

    /// Lock-protected peek: true iff a receive() call right now would find a
    /// value or (once Phase 4 adds channel-close!) EOF. Used by
    /// channelReceiveShared's local-drive loop (primitives_fiber.zig) to
    /// decide whether driving local siblings found anything, without
    /// unsafely reading queue_len/closed outside the lock -- unlike a purely
    /// local Channel's queue, this one is genuinely cross-thread-visible.
    pub fn peekReady(self: *SharedChannel) bool {
        lockChannel(self);
        defer unlockChannel(self);
        return self.queue_len != 0 or self.closed;
    }

    /// Send-side counterpart to peekReady: true iff a send() call right now
    /// would be admitted (a slot is free, unbounded, or closed -- a closed
    /// channel "admits" in the sense that send() will immediately raise
    /// rather than park, which is exactly the outcome
    /// channelSendShared's local-drive loop needs to stop waiting on).
    pub fn peekSendReady(self: *SharedChannel) bool {
        lockChannel(self);
        defer unlockChannel(self);
        if (self.closed) return true;
        const cap = self.capacity orelse return true;
        return self.queue_len + self.reserved < cap;
    }

    /// KEP-0002 §6's `channel-closed?`, lock-protected like peekReady --
    /// `closed` is genuinely cross-thread-visible once promoted.
    pub fn isClosed(self: *SharedChannel) bool {
        lockChannel(self);
        defer unlockChannel(self);
        return self.closed;
    }

    /// §1 rule 4 / §7: zero destroys. Drains and deinits every queued
    /// envelope (recursively releasing any stub refcounts those messages
    /// hold -- this is what reclaims a channel that was only kept alive by
    /// a stub inside its own queue, once that queue itself is finally
    /// drained), releases remaining waiter registrations, frees.
    fn destroyHook(header: *shared_object.Header) void {
        const self: *SharedChannel = @fieldParentPtr("header", header);

        lockChannel(self);
        var env = self.queue_head;
        self.queue_head = null;
        self.queue_tail = null;
        self.queue_len = 0;
        unlockChannel(self);

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

    /// §7 opportunistic pruning: while walking for the dedup check anyway,
    /// drop any entry whose notifier has already gone dead (its owning
    /// thread exited) -- "any path holding the lock" covers send, receive,
    /// and promotion migration, since they all route through here. Not a
    /// correctness requirement (a ring or destroy would eventually clear a
    /// dead entry too -- "one harmless spurious sweep"), just keeps
    /// long-lived channels from accumulating dead registrations.
    fn registerSendWaiter(self: *SharedChannel, n: *ThreadNotifier) void {
        var i: usize = 0;
        while (i < self.send_waiters.items.len) {
            const existing = self.send_waiters.items[i];
            if (existing == n) return; // dedup: at most one entry per notifier per list
            if (!existing.alive.load(.acquire)) {
                _ = self.send_waiters.swapRemove(i);
                releaseNotifier(existing);
                continue;
            }
            i += 1;
        }
        self.send_waiters.append(std.heap.c_allocator, n) catch @panic("SharedChannel: send_waiters OOM");
        retainNotifier(n);
    }

    fn registerRecvWaiter(self: *SharedChannel, n: *ThreadNotifier) void {
        var i: usize = 0;
        while (i < self.recv_waiters.items.len) {
            const existing = self.recv_waiters.items[i];
            if (existing == n) return;
            if (!existing.alive.load(.acquire)) {
                _ = self.recv_waiters.swapRemove(i);
                releaseNotifier(existing);
                continue;
            }
            i += 1;
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
/// releasing it -- a live waiter list is never iterated unlocked. notify()
/// runs strictly before releaseNotifier so this thread still holds its own
/// +1 while touching `n` -- see releaseNotifier's doc comment (reactor.zig)
/// for why that ordering is what makes concurrent teardown safe.
fn ring(notifiers: []const *ThreadNotifier) void {
    for (notifiers) |n| {
        n.notify();
        releaseNotifier(n);
    }
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
    // KEP-0002 §6: carried over from the local representation before
    // publishing -- safe either way, since nothing can observe `sc` until
    // `ch.shared` is set below. `sc.queue_len` needs no equivalent copy: the
    // drain loop below derives it correctly via pushBack.
    sc.capacity = ch.capacity;
    sc.closed = ch.closed;
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

    // KEP-0002 §2 step 4: migrate any fiber already parked on the *local*
    // representation before promotion (waiting_on == ch -- a receiver on
    // the empty queue, or, since Phase 4 added local bounded-channel
    // parking, a sender on a full queue). Promotion runs inside a primitive
    // on the owning thread, so the local scheduler is quiescent and this
    // scan is race-free. Without this step a fiber parked before promotion
    // would hang forever: a remote send/receive only rings *registered*
    // notifiers. Enrolled unconditionally, not gated on sc.refCount() > 1
    // -- at this point refcount is still 1 (the caller in gc_deep_copy.zig
    // retains the second stub only after this function returns), so gating
    // here would always see 1 and wrongly skip migration.
    //
    // A migrated fiber's role (parked sender vs. parked receiver) isn't
    // tracked anywhere -- `waiting_on` only records the channel, not why --
    // so rather than adding a Fiber field just for this migration corner,
    // the notifier is registered in *both* waiter lists. A spurious ring on
    // the wrong list is harmless under the existing wake-all/retry
    // discipline (the fiber just re-parks and re-registers correctly, this
    // time through the real shared send()/receive() path); registering in
    // only one risks a permanent hang if that guess is wrong (e.g. a
    // migrated sender registered only in recv_waiters would never be rung
    // by a remote receive freeing a slot).
    if (vm_mod.vm_instance) |vm| {
        if (vm.scheduler) |sched| {
            const ch_val = types.makePointer(@ptrCast(&ch.header));
            // Registers the notifier once, only if something actually
            // matched -- register{Recv,Send}Waiter's own dedup makes
            // calling them once per matching fiber idempotent, but hoisting
            // it out reads clearer and does one lock/unlock pair instead of
            // N per list.
            var migrated_any = false;
            for (sched.fibers.items) |maybe_f| {
                const f = maybe_f orelse continue;
                if (f.status == .waiting and f.waiting_on == ch_val) {
                    // Propagate, don't swallow: registration runs once,
                    // after this loop finishes (not before it), so on an
                    // enrollSharedWaiter OOM mid-loop no notifier is ever
                    // registered for `sc`. Fibers already enrolled by prior
                    // iterations become stale-but-harmless registry entries
                    // -- any future sweep on this scheduler flips them
                    // regardless of channel, and their retry re-registers
                    // per §4 -- while fibers not yet reached stay `.waiting`
                    // with no path left to wake them. Both are OOM-only
                    // corners of an already-failing promotion; accepted
                    // rather than un-enrolling on this error path.
                    try sched.enrollSharedWaiter(f);
                    migrated_any = true;
                }
            }
            if (migrated_any) {
                const notifier = vm.reactor.?.notifyHandle();
                sc.registerRecvWaiter(notifier);
                sc.registerSendWaiter(notifier);
            }
        }
    }

    return sc;
}

pub const SendOutcome = union(enum) {
    sent,
    would_park,
    closed,
};

/// KEP-0002 §4 send, on the shared representation, verbatim. `notifier` is
/// registered only by the full-channel park branch (reachable once a
/// caller passes a bounded channel, KEP-0002 §6); passing null there simply
/// registers nothing (there is nothing yet to wake) rather than panicking,
/// which callers that only ever operate on unbounded/open channels rely on.
pub fn send(sc: *SharedChannel, payload: Value, notifier: ?*ThreadNotifier) !SendOutcome {
    lockChannel(sc);
    if (sc.closed) {
        unlockChannel(sc);
        return .closed;
    }
    if (sc.capacity) |cap| {
        if (sc.queue_len + sc.reserved >= cap) {
            if (notifier) |n| sc.registerSendWaiter(n);
            unlockChannel(sc);
            return .would_park;
        }
    }
    sc.reserved += 1;
    unlockChannel(sc);

    // Built outside the lock: deepCopy allocates and must not hold the
    // channel mutex. A reservation was already taken, so the eventual push
    // (on success) is infallible.
    //
    // T_submit_copy (kaappi#1472 §3): time the parent's envelope build here on
    // the send path only -- a worker returning a result accumulates into its
    // own threadlocal, which the gate never reads. No-op when the instrument
    // build flag is off.
    const copy_timer = instrument.begin();
    const env = Envelope.create(payload) catch |err| {
        lockChannel(sc);
        sc.reserved -= 1;
        var snap: std.ArrayList(*ThreadNotifier) = .empty;
        defer snap.deinit(std.heap.c_allocator);
        sc.snapshotAndClearSendWaiters(&snap);
        // A receiver may be parked waiting out this very reservation
        // (receive step 6's reserved==0 eof guard) if the channel closed
        // while this send was in flight.
        if (sc.closed) sc.snapshotAndClearRecvWaiters(&snap);
        unlockChannel(sc);
        ring(snap.items);
        // Nothing was enqueued ("send fails ⇒ nothing sent"); Envelope
        // .create already tore itself down internally on failure.
        return err;
    };
    instrument.endSubmit(copy_timer);

    lockChannel(sc);
    sc.reserved -= 1;
    sc.pushBack(env);
    var snap: std.ArrayList(*ThreadNotifier) = .empty;
    defer snap.deinit(std.heap.c_allocator);
    sc.snapshotAndClearRecvWaiters(&snap);
    unlockChannel(sc);
    ring(snap.items);
    return .sent;
}

pub const RecvOutcome = union(enum) {
    value: Value,
    would_park,
    eof,
};

/// KEP-0002 §4 receive, on the shared representation, verbatim. `notifier`
/// follows send()'s same null-is-safe convention on the park branch.
pub fn receive(sc: *SharedChannel, dest_gc: *memory.GC, notifier: ?*ThreadNotifier) !RecvOutcome {
    lockChannel(sc);
    if (sc.popFront()) |env| {
        var snap: std.ArrayList(*ThreadNotifier) = .empty;
        defer snap.deinit(std.heap.c_allocator);
        sc.snapshotAndClearSendWaiters(&snap); // a slot opened
        unlockChannel(sc);
        ring(snap.items);

        // T_result_copy (kaappi#1472 §3): the parent copying a result out of a
        // reply envelope, on its critical path. Same per-thread attribution as
        // T_submit_copy; no-op when the instrument build flag is off.
        const copy_timer = instrument.begin();
        const value = dest_gc.deepCopy(env.value) catch |err| {
            // "Receive fails ⇒ nothing received": the envelope is
            // untouched, its stubs keep their refcounts, the message stays
            // deliverable in order. Re-queue at the head, not the tail.
            lockChannel(sc);
            sc.pushFront(env);
            var recv_snap: std.ArrayList(*ThreadNotifier) = .empty;
            defer recv_snap.deinit(std.heap.c_allocator);
            sc.snapshotAndClearRecvWaiters(&recv_snap);
            unlockChannel(sc);
            ring(recv_snap.items);
            return err;
        };
        instrument.endResult(copy_timer);
        env.deinit();
        return .{ .value = value };
    }
    if (sc.closed and sc.reserved == 0) {
        unlockChannel(sc);
        return .eof;
    }
    // Reached with the channel open, or closed with admitted sends still in
    // flight: eof must not race a reservation, so the receiver parks and is
    // rung by the late push (or by send's failure-path closed-channel ring).
    if (notifier) |n| sc.registerRecvWaiter(n);
    unlockChannel(sc);
    return .would_park;
}

/// KEP-0002 §6 close, on the shared representation, verbatim: idempotent,
/// wakes every waiter on both sides at once. A sender that already reserved
/// its slot before this runs is unaffected (the `closed` check runs only at
/// send's admission step) and completes its push normally -- reservation-
/// as-admission is what makes an admitted message survive a concurrent
/// close (model finding 2).
pub fn close(sc: *SharedChannel) void {
    lockChannel(sc);
    if (sc.closed) {
        unlockChannel(sc);
        return;
    }
    sc.closed = true;
    var snap: std.ArrayList(*ThreadNotifier) = .empty;
    defer snap.deinit(std.heap.c_allocator);
    sc.snapshotAndClearRecvWaiters(&snap);
    sc.snapshotAndClearSendWaiters(&snap);
    unlockChannel(sc);
    ring(snap.items);
}
