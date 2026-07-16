// KEP-0001 Phase 1: reactor core, tested in isolation (no scheduler caller
// yet — that's Phase 2). These are plain Zig tests against real fds; no VM
// or GC is involved. Fake *Fiber values are stack locals with only `status`
// initialized (to .io_waiting, what a genuinely parked fiber carries): the
// reactor stores and returns the pointers without touching execution state,
// but register()'s Debug-build staleness assertion reads the status of
// every already-listed waiter (Phase 3).
const std = @import("std");
const platform = @import("platform.zig");
const reactor_mod = @import("reactor.zig");
const fiber_mod = @import("fiber.zig");
const Reactor = reactor_mod.Reactor;
const Fiber = fiber_mod.Fiber;

fn makePipe() [2]std.c.fd_t {
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) unreachable;
    return fds;
}

fn closeFd(fd: std.c.fd_t) void {
    _ = platform.close(fd);
}

fn newReady() std.ArrayList(*Fiber) {
    return .empty;
}

/// Writes one byte and asserts it actually landed, so a short write or
/// failure fails loudly at the syscall instead of surfacing later as an
/// unrelated assertion mismatch or poll() timeout.
fn writeByte(fd: std.c.fd_t, byte: u8) void {
    const buf = [1]u8{byte};
    const n = platform.write(fd, &buf, 1);
    std.testing.expectEqual(@as(isize, 1), n) catch unreachable;
}

test "register + poll wakes the fiber when the fd becomes readable" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a);

    writeByte(pipe[1], 'x');

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

test "poll times out with an empty ready list when nothing fires" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a); // never written to

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(20_000_000, &ready); // 20ms cap, nothing ready

    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
}

test "multiple waiters on one fd direction are all woken (wake-all)" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    var fiber_b: Fiber = undefined;
    fiber_b.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a);
    try reactor.register(pipe[0], .read, &fiber_b);

    writeByte(pipe[1], 'x');

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 2), ready.items.len);
    var saw_a = false;
    var saw_b = false;
    for (ready.items) |f| {
        if (f == &fiber_a) saw_a = true;
        if (f == &fiber_b) saw_b = true;
    }
    try std.testing.expect(saw_a and saw_b);
}

test "a write end is immediately ready for write interest" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[1], .write, &fiber_a);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

test "addTimer fires when its deadline passes" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    const deadline = fiber_mod.clockNs() + 1_000_000; // 1ms out
    try reactor.addTimer(deadline, &fiber_a);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(2_000_000_000, &ready); // generous cap; timer should win

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

test "the nearer of an fd timeout and a timer deadline bounds the wait" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_fd: Fiber = undefined;
    fiber_fd.status = .io_waiting;
    var fiber_timer: Fiber = undefined;
    fiber_timer.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_fd); // never written to
    try reactor.addTimer(fiber_mod.clockNs() + 1_000_000, &fiber_timer); // 1ms

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    // Cap far larger than the timer: if the cap (not the timer) governed
    // the wait, this test would hang for seconds instead of ~1ms.
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_timer, ready.items[0]);
}

test "removeTimer cancels a pending timer so it never fires" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.addTimer(fiber_mod.clockNs() + 1_000_000, &fiber_a);
    reactor.removeTimer(&fiber_a);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(20_000_000, &ready); // 20ms cap; nothing should fire

    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
    try std.testing.expect(reactor.isEmpty());
}

test "unregister drops the registration; a later write wakes nobody" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a);
    reactor.unregister(pipe[0]);

    writeByte(pipe[1], 'x');

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(20_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
}

test "isEmpty is true after a fired oneshot drains its waiters, even though the fd is still tracked" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a);
    writeByte(pipe[1], 'x');

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);

    // The Reg bookkeeping may still exist (kernel_registered persists so a
    // future re-arm knows ADD vs MOD), but nothing is pending — this must
    // not look like reactor work is still outstanding.
    try std.testing.expect(reactor.isEmpty());
}

test "re-registering a fd after a fired oneshot re-arms correctly" {
    // Exercises the epoll first_time bookkeeping directly: a second
    // register() on the same fd after a prior fire must use CTL_MOD, not
    // CTL_ADD (which would fail EEXIST on an already-tracked fd). On
    // kqueue this is a plain EV_ADD either way, so this test is only a
    // regression guard on Linux, but it is harmless and passes on both.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a);
    writeByte(pipe[1], 'x');

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    ready.clearRetainingCapacity();

    var fiber_b: Fiber = undefined;
    fiber_b.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_b);
    writeByte(pipe[1], 'y');

    try reactor.poll(5_000_000_000, &ready);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_b, ready.items[0]);
}

test "a recycled fd number registers cleanly over a stale Reg left by a close without unregister" {
    // A port freed by the GC closes its fd without reactor.unregister —
    // the kernel silently drops the fd from the epoll set, but the Reg
    // (kernel_registered=true, empty waiter lists) survives in the map.
    // When the fd number is recycled onto a new port, register() must
    // still succeed: epoll's CTL_MOD hits ENOENT on the untracked fd and
    // must self-heal by retrying as CTL_ADD. kqueue is immune (EV_ADD
    // recreates), so this is a Linux regression guard that also passes
    // on macOS.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe_old = makePipe();
    defer closeFd(pipe_old[1]);
    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe_old[0], .read, &fiber_a);

    // Drain the registration so the waiter lists empty out but the Reg
    // (and its kernel_registered flag) stay behind, then "GC-free" the
    // port: close the fd with no unregister.
    writeByte(pipe_old[1], 'x');
    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    ready.clearRetainingCapacity();
    closeFd(pipe_old[0]);

    // Recycle the exact fd number onto a fresh pipe. POSIX hands out the
    // lowest free fd, so pipe() usually reuses it directly; dup2 forces
    // the number when the allocator happened to pick another.
    const pipe_new = makePipe();
    defer closeFd(pipe_new[1]);
    var recycled: std.c.fd_t = pipe_new[0];
    if (pipe_new[0] != pipe_old[0]) {
        recycled = std.c.dup2(pipe_new[0], pipe_old[0]);
        try std.testing.expectEqual(pipe_old[0], recycled);
        closeFd(pipe_new[0]);
    }
    defer closeFd(recycled);

    var fiber_b: Fiber = undefined;
    fiber_b.status = .io_waiting;
    try reactor.register(recycled, .read, &fiber_b);
    writeByte(pipe_new[1], 'y');

    try reactor.poll(5_000_000_000, &ready);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_b, ready.items[0]);
}

test "two fds: only the one that becomes ready wakes its fiber" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe_a = makePipe();
    defer closeFd(pipe_a[0]);
    defer closeFd(pipe_a[1]);
    const pipe_b = makePipe();
    defer closeFd(pipe_b[0]);
    defer closeFd(pipe_b[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    var fiber_b: Fiber = undefined;
    fiber_b.status = .io_waiting;
    try reactor.register(pipe_a[0], .read, &fiber_a);
    try reactor.register(pipe_b[0], .read, &fiber_b);

    writeByte(pipe_b[1], 'x'); // only b becomes ready

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_b, ready.items[0]);
}

fn makeSocketPair() [2]std.c.fd_t {
    var fds: [2]std.c.fd_t = undefined;
    const rc = std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &fds);
    if (rc != 0) unreachable;
    return fds;
}

test "one fd with both read and write interest: a fired direction re-arms the other" {
    // Regression guard for the epoll-specific bug this design is most at
    // risk of: EPOLLONESHOT disarms the *entire* fd registration on any
    // fire, not just the direction that fired. Without the re-arm-on-
    // partial-fire step in Reactor.poll, the still-pending direction would
    // silently stop being monitored forever.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pair = makeSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);

    var fiber_read: Fiber = undefined;
    fiber_read.status = .io_waiting;
    var fiber_write: Fiber = undefined;
    fiber_write.status = .io_waiting;
    // pair[0] is immediately writable (empty send buffer) but not yet
    // readable (nothing sent from pair[1] yet).
    try reactor.register(pair[0], .write, &fiber_write);
    try reactor.register(pair[0], .read, &fiber_read);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    // Only the write side fired; the read side must still be armed.
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_write, ready.items[0]);
    ready.clearRetainingCapacity();

    writeByte(pair[1], 'x');
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_read, ready.items[0]);
}

test "closing the peer wakes a parked read waiter (EOF/HUP mapped to broken)" {
    // Exercises the `broken` mapping on both backends (kqueue's EV_EOF,
    // epoll's EPOLLHUP|EPOLLERR): a peer close must be reported as read
    // (and write) readiness so the parked fiber wakes to observe EOF,
    // rather than waiting forever for bytes that will never arrive.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pair = makeSocketPair();
    defer closeFd(pair[0]);
    var closed_peer = false;
    defer if (!closed_peer) closeFd(pair[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pair[0], .read, &fiber_a);

    closeFd(pair[1]);
    closed_peer = true;

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

fn setNonblocking(fd: std.c.fd_t) void {
    const flags = std.c.fcntl(fd, std.posix.F.GETFL, @as(c_int, 0));
    std.testing.expect(flags >= 0) catch unreachable;
    const nonblock: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
    std.testing.expect(std.c.fcntl(fd, std.posix.F.SETFL, flags | nonblock) >= 0) catch unreachable;
}

/// Shrinks the kernel send buffer so `fillSendBuffer` reaches EAGAIN after
/// a few KB instead of needing megabytes of writes.
fn setSmallSndbuf(fd: std.c.fd_t) void {
    const size: c_int = 2048;
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.SNDBUF, std.mem.asBytes(&size)) catch unreachable;
}

/// Writes to `fd` (already non-blocking) until the send buffer is full and
/// a write returns EAGAIN, proving the fd is not writable. Bounded so a
/// platform that doesn't honor the shrunk SO_SNDBUF fails loudly instead of
/// spinning forever.
fn fillSendBuffer(fd: std.c.fd_t) void {
    var buf: [4096]u8 = [_]u8{0} ** 4096;
    var iterations: usize = 0;
    while (iterations < 4096) : (iterations += 1) {
        const n = platform.write(fd, &buf, buf.len);
        if (n < 0) {
            std.testing.expectEqual(std.posix.E.AGAIN, platform.errno(n)) catch unreachable;
            return;
        }
    }
    @panic("fillSendBuffer: fd never became unwritable (SO_SNDBUF not honored?)");
}

/// Reads `fd` (already non-blocking) to EAGAIN, discarding everything —
/// frees up the peer's send buffer.
fn drainSocket(fd: std.c.fd_t) void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = platform.read(fd, &buf, buf.len);
        if (n < 0) {
            std.testing.expectEqual(std.posix.E.AGAIN, platform.errno(n)) catch unreachable;
            return;
        }
        if (n == 0) return;
    }
}

test "a stale ONESHOT fire on one direction re-arms the fd for the surviving waiter (#1462)" {
    // removeWaiter only edits the waiter lists — it never touches the
    // kernel registration (see its doc comment). If the removed waiter's
    // direction fires before the surviving direction does, epoll's
    // EPOLLONESHOT disarms the *whole* fd, not just the direction that
    // fired. poll() must re-arm for whatever waiters remain even when the
    // fired event matched none of them ("stale"), or the surviving waiter
    // is left parked on an fd the kernel no longer watches — a permanent,
    // silent hang with no timers pending to bound the wait.
    //
    // kqueue's independent per-direction knotes make this scenario
    // impossible to strand there, so this test can only demonstrate the
    // bug on Linux (epoll); it still passes on macOS/kqueue as a no-op
    // regression guard.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pair = makeSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);

    setNonblocking(pair[0]);
    setSmallSndbuf(pair[0]);
    fillSendBuffer(pair[0]); // pair[0] is now not writable

    var fiber_r: Fiber = undefined;
    fiber_r.status = .io_waiting;
    var fiber_w: Fiber = undefined;
    fiber_w.status = .io_waiting;
    try reactor.register(pair[0], .read, &fiber_r);
    try reactor.register(pair[0], .write, &fiber_w); // kernel armed IN|OUT|ONESHOT

    reactor.removeWaiter(pair[0], &fiber_r); // read waiter gone; kernel stays armed for IN

    writeByte(pair[1], 'x'); // pair[0] becomes readable -> a stale IN fire

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(300_000_000, &ready); // the stale fire is dropped
    try std.testing.expectEqual(@as(usize, 0), ready.items.len);

    // Free up pair[0]'s send buffer so it becomes writable, then confirm
    // the surviving write waiter still wakes. Without the fix this poll
    // times out on Linux: the stale fire above left the fd disarmed in
    // the kernel and nothing ever re-registers it.
    setNonblocking(pair[1]);
    drainSocket(pair[1]);
    try reactor.poll(300_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_w, ready.items[0]);
}

// KEP-0002 Phase 3 (#1468): ThreadNotifier, the cross-thread wakeup handle
// every Reactor now owns. notifierLiveCount() is a real process-global
// counter (like shared_object.liveCount()), not reset between Zig tests --
// every test captures its own baseline and asserts a return to it.

test "notifierLiveCount tracks Reactor.init/deinit" {
    const baseline = reactor_mod.notifierLiveCount();
    var reactor = try Reactor.init(std.testing.allocator);
    try std.testing.expectEqual(baseline + 1, reactor_mod.notifierLiveCount());
    reactor.deinit();
    try std.testing.expectEqual(baseline, reactor_mod.notifierLiveCount());
}

test "retainNotifier keeps the notifier alive past Reactor.deinit; releasing the last ref frees it" {
    const baseline = reactor_mod.notifierLiveCount();
    var reactor = try Reactor.init(std.testing.allocator);
    const notifier = reactor.notifyHandle();

    // Simulates a SharedChannel registration outliving this thread's own
    // Reactor (KEP-0002 §7: "the refcount keeps the struct itself valid
    // until the last entry is released").
    reactor_mod.retainNotifier(notifier);

    reactor.deinit(); // drops the base ref; one registration ref remains
    try std.testing.expectEqual(baseline + 1, reactor_mod.notifierLiveCount());
    try std.testing.expect(!notifier.alive.load(.acquire));

    // notify() on a dead handle is a documented no-op -- must not touch the
    // (already-closed-if-it-had-hit-zero, but here still-open) backend fd.
    notifier.notify();
    try std.testing.expect(notifier.wake_pending.load(.acquire));

    reactor_mod.releaseNotifier(notifier); // last ref: frees + closes backend
    try std.testing.expectEqual(baseline, reactor_mod.notifierLiveCount());
}

test "notify() from another OS thread interrupts a blocking poll()" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const Ctx = struct {
        notifier: *reactor_mod.ThreadNotifier,
        fn run(self: @This()) void {
            var ts: std.c.timespec = .{ .sec = 0, .nsec = 20_000_000 };
            _ = std.c.nanosleep(&ts, &ts);
            self.notifier.notify();
        }
    };
    const thread = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{ .notifier = reactor.notifyHandle() }});
    defer thread.join();

    const start = fiber_mod.clockNs();
    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    // A generous upper bound: if notify() failed to interrupt poll(), this
    // would time out at 5s instead of returning promptly after ~20ms.
    try reactor.poll(5_000_000_000, &ready);
    const elapsed_ns = fiber_mod.clockNs() - start;

    // Nothing fd-related fired; the notifier's own event is filtered out of
    // ReadyEvent entirely (reactor.zig's wait() implementations).
    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
    try std.testing.expect(reactor.notifier.wake_pending.load(.acquire));
    try std.testing.expect(elapsed_ns < 1_000_000_000);
}
