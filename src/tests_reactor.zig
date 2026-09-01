// KEP-0001 Phase 1: reactor core, tested in isolation (no scheduler caller
// yet — that's Phase 2). These are plain Zig tests against real fds; no VM
// or GC is involved. Fake *Fiber values are stack locals with only `status`
// initialized (to .io_waiting, what a genuinely parked fiber carries): the
// reactor stores and returns the pointers without touching execution state,
// but register()'s Debug-build staleness assertion reads the status of
// every already-listed waiter (Phase 3).
//
// The fds come from testing_helpers' cross-platform pairs: pipes and
// AF_UNIX socketpairs on POSIX, loopback TCP pairs on Windows — where this
// suite doubles as the WSAEventSelect socket backend's coverage (#1608
// stage 1). The "#1608:" tests at the bottom use real OS-pipe pairs on
// every platform, covering the polled pipe backend (stage 2) on Windows.
const std = @import("std");
const platform = @import("platform.zig");
const th = @import("testing_helpers.zig");
const reactor_mod = @import("reactor.zig");
const fiber_mod = @import("fiber.zig");
const Reactor = reactor_mod.Reactor;
const Fiber = fiber_mod.Fiber;

const makePipe = th.makeFdPair;
const closeFd = th.closeFd;

fn newReady() std.ArrayList(*Fiber) {
    return .empty;
}

/// Safety bound for `pollUntilReady`. Reached only when the thing under
/// test never fires at all, in which case the caller's own assertion is
/// what reports the failure — so it can afford to be generous.
const poll_retry_bound_ns: u64 = 10_000_000_000;

/// Drives `poll` until at least one fiber is ready, or `bound_ns` of wall
/// time elapses.
///
/// A single `poll()` may legitimately come back with an empty ready list
/// while a timer is still pending. `effectiveTimeout` bounds the wait at
/// the nearest deadline, and an OS wait requested for an interval near the
/// scheduler's tick can return a fraction of a tick early; `clockNs()` then
/// still reads below the deadline, so `popExpiredTimers` finds nothing to
/// move. Windows' `WaitForMultipleObjects` made that observable on CI with
/// the 1ms deadlines below — `WindowsEventBackend.wait` ceils its
/// millisecond conversion so a timer never fires *early*, but nothing can
/// stop the underlying wait from returning early.
///
/// Looping is what the real caller does, not a workaround for the test:
/// `FiberScheduler.parkOnReactor` treats an empty return as ordinary and
/// re-checks after each capped return. Asserting on one `poll()` was the
/// bug.
fn pollUntilReady(reactor: *Reactor, ready: *std.ArrayList(*Fiber), bound_ns: u64) !void {
    const give_up_at = fiber_mod.clockNs() + bound_ns;
    while (true) {
        const now = fiber_mod.clockNs();
        if (now >= give_up_at) return;
        try reactor.poll(give_up_at - now, ready);
        if (ready.items.len > 0) return;
    }
}

/// Writes one byte and asserts it actually landed, so a short write or
/// failure fails loudly at the syscall instead of surfacing later as an
/// unrelated assertion mismatch or poll() timeout.
fn writeByte(fd: platform.fd_t, byte: u8) void {
    const buf = [1]u8{byte};
    const n = th.fdWrite(fd, &buf);
    std.testing.expectEqual(@as(isize, 1), n) catch unreachable;
}

test "register + poll wakes the fiber when the fd becomes readable" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    const start = fiber_mod.clockNs();
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);
    const elapsed_ns = fiber_mod.clockNs() - start;

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
    // Fired no earlier than its deadline. Free of timing risk: popExpiredTimers
    // compares against this same clock, so it cannot legitimately fail.
    try std.testing.expect(fiber_mod.clockNs() >= deadline);
    // Fired *promptly* after it. Retrying alone would let a badly late timer
    // pass (the loop would simply wait it out), so the upper bound has to be
    // stated. 1s is ~60x the coarsest tick that caused the original flake and
    // the same bound the notify test below has used without trouble.
    try std.testing.expect(elapsed_ns < 1_000_000_000);
}

test "the nearer of an fd timeout and a timer deadline bounds the wait" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    const start = fiber_mod.clockNs();
    // Bound far larger than the timer: if the cap (not the timer) governed
    // the wait, this would sit here for the full bound instead of ~1ms.
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);
    const elapsed_ns = fiber_mod.clockNs() - start;

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_timer, ready.items[0]);
    // Unlike the test above, this one needs an upper bound to mean anything:
    // retrying until the timer fires would also "pass" against an
    // effectiveTimeout that ignored timers entirely and blocked for the whole
    // cap. Kept 1000x the 1ms deadline and 10x under the bound, so it
    // discriminates a cap-governed wait without gating on exact timing.
    try std.testing.expect(elapsed_ns < 1_000_000_000);
}

test "removeTimer cancels a pending timer so it never fires" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    const deadline = fiber_mod.clockNs() + 1_000_000;
    try reactor.addTimer(deadline, &fiber_a);
    reactor.removeTimer(&fiber_a);

    // Get past the deadline before looking. Polling before it proves
    // nothing — an uncancelled timer would not have fired yet either — and
    // a poll() bounded near the tick can return early (see pollUntilReady),
    // so the 20ms cap this used to rely on could be cut short and pass
    // vacuously.
    while (fiber_mod.clockNs() < deadline) platform.sleepNs(1_000_000);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(20_000_000, &ready); // nothing left to fire

    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
    try std.testing.expect(reactor.isEmpty());
}

test "unregister drops the registration; a later write wakes nobody" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // A port freed by the GC closes its fd without reactor.unregister —
    // the kernel silently drops the fd from the epoll set, but the Reg
    // (kernel_registered=true, empty waiter lists) survives in the map.
    // When the fd number is recycled onto a new port, register() must
    // still succeed: epoll's CTL_MOD hits ENOENT on the untracked fd and
    // must self-heal by retrying as CTL_ADD. kqueue is immune (EV_ADD
    // recreates), so this is a Linux regression guard that also passes
    // on macOS. Skipped on Windows: the forced-number recycling below
    // needs dup2, and CRT _dup2 over a socket-backed fd duplicates the
    // handle without WSA bookkeeping (WSADuplicateSocket territory) — the
    // recycle scenario itself is covered there by arm()'s re-deriving the
    // SOCKET from the fd on every call.
    if (comptime platform.is_windows) return error.SkipZigTest;
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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

const makeSocketPair = th.makeBidiFdPair;

test "one fd with both read and write interest: a fired direction re-arms the other" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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

test "data already buffered when the read interest is registered still wakes" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // The condition predates the arm. kqueue/epoll report a pre-existing
    // condition on a fresh ONESHOT registration natively; the Windows
    // backend must catch it via arm()'s post-WSAEventSelect readiness
    // probe, because (re)issuing WSAEventSelect clears the socket's
    // pending network-event records (#1608).
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    writeByte(pipe[1], 'x'); // readable *before* register

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

test "a peer closed before the read interest is registered still wakes" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // Same pre-arm race as above but for the hangup edge: FD_CLOSE is
    // edge-recorded on Windows, so a peer that closed before the arm
    // would never re-fire — only arm()'s probe can observe it. On
    // kqueue/epoll a fresh registration reports EOF/HUP directly.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pair = makeSocketPair();
    defer closeFd(pair[0]);

    closeFd(pair[1]); // peer gone *before* register

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pair[0], .read, &fiber_a);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

const setNonblocking = th.setFdNonblocking;

/// Shrinks the kernel send buffer so `fillSendBuffer` reaches EAGAIN after
/// a few KB instead of needing megabytes of writes.
fn setSmallSndbuf(fd: platform.fd_t) void {
    th.setSockBufSize(fd, .snd, 2048);
}

/// Writes to `fd` (already non-blocking) until the send buffer is full and
/// a write returns EAGAIN, proving the fd is not writable. Bounded so a
/// platform that doesn't honor the shrunk SO_SNDBUF fails loudly instead of
/// spinning forever.
fn fillSendBuffer(fd: platform.fd_t) void {
    var buf: [4096]u8 = [_]u8{0} ** 4096;
    var iterations: usize = 0;
    while (iterations < 4096) : (iterations += 1) {
        const n = th.fdWrite(fd, &buf);
        if (n < 0) {
            std.testing.expectEqual(platform.E.AGAIN, platform.errno(n)) catch unreachable;
            return;
        }
    }
    @panic("fillSendBuffer: fd never became unwritable (SO_SNDBUF not honored?)");
}

/// Reads `fd` (already non-blocking) to EAGAIN, discarding everything —
/// frees up the peer's send buffer.
fn drainSocket(fd: platform.fd_t) void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = th.fdRead(fd, &buf);
        if (n < 0) {
            std.testing.expectEqual(platform.E.AGAIN, platform.errno(n)) catch unreachable;
            return;
        }
        if (n == 0) return;
    }
}

test "a stale ONESHOT fire on one direction re-arms the fd for the surviving waiter (#1462)" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
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
    if (comptime platform.is_wasm) return error.SkipZigTest; // no OS threads on wasm32-wasi (single-threaded target)
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const Ctx = struct {
        notifier: *reactor_mod.ThreadNotifier,
        fn run(self: @This()) void {
            platform.sleepNs(20_000_000);
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

// ---------------------------------------------------------------------------
// #1608 stage 2: reactor-level coverage over real OS-pipe pairs. On POSIX
// these re-cover the kqueue/epoll pipe paths; on Windows they exercise the
// WindowsEventBackend pipe registry — arm routing via fdKind, the
// poll-quantum-bounded wait, and the pipePollReady sweep.
// ---------------------------------------------------------------------------

test "#1608: pipe pair — register + poll wakes the fiber when the pipe becomes readable" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = th.makePipeFdPair();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a);

    // Raw pipe write (CRT _write works on pipe fds; fdWrite's Windows
    // routing is socket-only).
    try std.testing.expectEqual(@as(isize, 1), platform.write(pipe[1], "x", 1));

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    // One poll call may time out at the pipe quantum before the sweep sees
    // the byte; bound the loop generously instead of assuming one pass.
    var waited_ns: u64 = 0;
    while (ready.items.len == 0 and waited_ns < 5_000_000_000) : (waited_ns += 100_000_000) {
        try reactor.poll(100_000_000, &ready);
    }

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

test "#1608: pipe pair — poll times out empty while the pipe is silent" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = th.makePipeFdPair();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[0], .read, &fiber_a); // never written to

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    // 50ms cap spans several pipe-poll quanta on Windows: every sweep must
    // report the silent pipe not-ready, not just the first.
    try reactor.poll(50_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
}

test "#1608: pipe pair — a write end with buffer space is ready for write interest" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = th.makePipeFdPair();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    fiber_a.status = .io_waiting;
    try reactor.register(pipe[1], .write, &fiber_a);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    var waited_ns: u64 = 0;
    while (ready.items.len == 0 and waited_ns < 5_000_000_000) : (waited_ns += 100_000_000) {
        try reactor.poll(100_000_000, &ready);
    }

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_a, ready.items[0]);
}

// ---------------------------------------------------------------------------
// #2395: the cross-thread wait registry
//
// The SRFI-18 waits resolvable only by another OS thread (thread-join! on a
// running child, mutex-lock!, a condition-variable wait, and a thread-sleep!
// that must still observe thread-terminate!) used to poll their own state at
// 1 ms. They now enrol here and are woken by a notifier ring from whichever
// thread performs the state change. These tests pin the two properties that
// makes correct: enrolment is balanced (a leaked entry would ring a freed
// notifier; a lost one would hang the wait), and a ring really does end a
// blocking poll rather than only setting a flag.
// ---------------------------------------------------------------------------

test "#2395: cross-thread waiter enrolment nests and stays balanced" {
    const notifier_baseline = reactor_mod.notifierLiveCount();
    try std.testing.expectEqual(@as(usize, 0), reactor_mod.crossThreadWaiterCount());

    var reactor = try reactor_mod.Reactor.init(std.testing.allocator);
    defer reactor.deinit();
    const n = reactor.notifyHandle();

    try std.testing.expect(reactor_mod.enrollCrossThreadWaiter(n));
    try std.testing.expectEqual(@as(usize, 1), reactor_mod.crossThreadWaiterCount());
    // The registry keys on the THREAD, not the wait: a fiber blocked in
    // mutex-lock! can drive a sibling that blocks in a condvar wait, and both
    // enrol the one reactor. The second enrolment must not add a row, and the
    // inner withdrawal must not unregister the outer wait.
    try std.testing.expect(reactor_mod.enrollCrossThreadWaiter(n));
    try std.testing.expectEqual(@as(usize, 1), reactor_mod.crossThreadWaiterCount());
    // Enrolment holds a reference, so the notifier survives its Reactor.
    try std.testing.expectEqual(notifier_baseline + 1, reactor_mod.notifierLiveCount());

    reactor_mod.withdrawCrossThreadWaiter(n);
    try std.testing.expectEqual(@as(usize, 1), reactor_mod.crossThreadWaiterCount());
    reactor_mod.withdrawCrossThreadWaiter(n);
    try std.testing.expectEqual(@as(usize, 0), reactor_mod.crossThreadWaiterCount());
    try std.testing.expectEqual(notifier_baseline + 1, reactor_mod.notifierLiveCount()); // reactor's own +1
}

test "#2395: wakeCrossThreadWaiters sets wake_pending only for enrolled reactors" {
    var reactor = try reactor_mod.Reactor.init(std.testing.allocator);
    defer reactor.deinit();
    const n = reactor.notifyHandle();

    // Not enrolled: the ring must not touch this reactor at all — an
    // unlock/signal in a program with no cross-thread waiter reaches nobody.
    n.wake_pending.store(false, .release);
    reactor_mod.wakeCrossThreadWaiters();
    try std.testing.expect(!n.wake_pending.load(.acquire));

    try std.testing.expect(reactor_mod.enrollCrossThreadWaiter(n));
    defer reactor_mod.withdrawCrossThreadWaiter(n);
    reactor_mod.wakeCrossThreadWaiters();
    try std.testing.expect(n.wake_pending.load(.acquire));
}

// Split from the bookkeeping assertions above rather than folded into them
// with an early `return`, which would report this half as *passed* on WASI
// while never running it (PR #2428 review). `ThreadNotifier.notify` has no OS
// primitive to ring on WASI (reactor.zig's `.wasi => {}` arm), because
// wasm32-wasi is single-threaded and no other thread can exist to do the
// ringing — so the poll below would genuinely wait out its whole timeout.
test "#2395: a ring is a real OS event that ends a blocking reactor poll" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no notifier primitive on WASI (single-threaded)
    var reactor = try reactor_mod.Reactor.init(std.testing.allocator);
    defer reactor.deinit();
    const n = reactor.notifyHandle();

    try std.testing.expect(reactor_mod.enrollCrossThreadWaiter(n));
    defer reactor_mod.withdrawCrossThreadWaiter(n);
    reactor_mod.wakeCrossThreadWaiters();

    // A poll that would otherwise wait out its whole timeout returns at once.
    // Asserted on elapsed time rather than by blocking forever, so a
    // regression fails the test instead of hanging the suite.
    var ready: std.ArrayList(*fiber_mod.Fiber) = .empty;
    defer ready.deinit(std.testing.allocator);
    const t0 = fiber_mod.clockNs();
    try reactor.poll(5 * std.time.ns_per_s, &ready);
    try std.testing.expect(fiber_mod.clockNs() - t0 < 2 * std.time.ns_per_s);
    // The notifier's own event is filtered out of the ready list (reactor.zig
    // wait()): it is a wakeup, never a runnable fiber.
    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
}

// ---------------------------------------------------------------------------
// Child-exit readiness (KEP-0022 Phase 2, kaappi#2415). Real children via
// std.process.Child (spawn only — the reactor must reap them itself, that
// being the property under test, so no child.wait() anywhere). Fake Process
// values are stack locals like the fake Fibers above: the reactor reads
// pid/wait_handle/status and never touches the header. `memory.gc_instance`
// is nulled per test — an earlier VM test's TestContext.deinit leaves the
// threadlocal dangling (the documented footgun), and the reactor's reap path
// consults it for the unreaped-registry removal.
// ---------------------------------------------------------------------------

const types_mod = @import("types.zig");
const memory_mod = @import("memory.zig");
const builtin_os = @import("builtin").os.tag;

/// pidfd_open(2) is ENOSYS on pre-5.3 kernels and under Rosetta's x86_64
/// syscall translation (the podman amd64 leg). The reactor degrades to the
/// primitive layer's polled wait there — covered by tests_process — so the
/// kernel-watch tests below skip rather than fail.
fn processWatchAvailable() bool {
    if (comptime builtin_os != .linux) return true;
    const linux_sys = std.os.linux;
    const rc = linux_sys.pidfd_open(@intCast(linux_sys.getpid()), 0);
    if (linux_sys.errno(rc) != .SUCCESS) return false;
    _ = platform.close(@intCast(rc));
    return true;
}

/// fork() a bare child (the std.process.Child API is Io-based in Zig 0.16;
/// raw fork is the thottam_proc precedent). `.sleeper` loops until the test
/// kills it; `.exit_now` _exits 0 at once — _exit, so the forked copy of the
/// test runner never runs its own epilogue.
fn forkChild(mode: enum { sleeper, exit_now }) i32 {
    const pid = std.posix.system.fork();
    std.debug.assert(pid >= 0);
    if (pid == 0) {
        if (mode == .sleeper) {
            while (true) platform.sleepNs(std.time.ns_per_s);
        }
        std.c._exit(0);
    }
    return @intCast(pid);
}

test "kaappi#2415: child exit wakes the parked waiter and reaps at the reactor" {
    if (comptime !reactor_mod.supports_process_watch) return error.SkipZigTest;
    if (!processWatchAvailable()) return error.SkipZigTest;
    memory_mod.gc_instance = null;
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pid = forkChild(.sleeper);
    var proc: types_mod.Process = .{ .header = undefined, .pid = pid };
    var fiber: Fiber = undefined;
    fiber.status = .waiting;

    try reactor.registerProcess(&proc, &fiber);
    // A watched process is a pending wakeup: the deadlock detector must not
    // read this reactor as empty.
    try std.testing.expect(!reactor.isEmpty());
    // Re-registration of the same waiter is idempotent.
    try reactor.registerProcess(&proc, &fiber);

    try std.testing.expectEqual(@as(c_int, 0), platform.procKill(pid, 9));

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber, ready.items[0]);
    // Reaped at the reactor, exactly once: status stored...
    try std.testing.expect(proc.status != null);
    try std.testing.expect(types_mod.ifWaitSignaled(proc.status.?));
    try std.testing.expectEqual(@as(u32, 9), types_mod.waitTermSig(proc.status.?));
    // ...registration dropped (and, on Linux, the pidfd closed with it)...
    try std.testing.expectEqual(@as(usize, 0), reactor.procs.count());
    try std.testing.expectEqual(@as(platform.fd_t, -1), proc.wait_handle);
    try std.testing.expect(reactor.isEmpty());
    // ...and nothing left for a second waitpid to find.
    var st: c_int = 0;
    try std.testing.expect(platform.waitPid(pid, &st, platform.WNOHANG) < 0);
}

test "kaappi#2415: every waiter parked on one child is woken by its exit" {
    if (comptime !reactor_mod.supports_process_watch) return error.SkipZigTest;
    if (!processWatchAvailable()) return error.SkipZigTest;
    memory_mod.gc_instance = null;
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pid = forkChild(.sleeper);
    var proc: types_mod.Process = .{ .header = undefined, .pid = pid };
    var fiber_a: Fiber = undefined;
    fiber_a.status = .waiting;
    var fiber_b: Fiber = undefined;
    fiber_b.status = .waiting;

    try reactor.registerProcess(&proc, &fiber_a);
    try reactor.registerProcess(&proc, &fiber_b);
    try std.testing.expectEqual(@as(c_int, 0), platform.procKill(pid, 9));

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);

    try std.testing.expectEqual(@as(usize, 2), ready.items.len);
    const both = (ready.items[0] == &fiber_a and ready.items[1] == &fiber_b) or
        (ready.items[0] == &fiber_b and ready.items[1] == &fiber_a);
    try std.testing.expect(both);
    try std.testing.expectEqual(@as(usize, 0), reactor.procs.count());
}

test "kaappi#2415: the last waiter's withdrawal drops the registration" {
    if (comptime !reactor_mod.supports_process_watch) return error.SkipZigTest;
    if (!processWatchAvailable()) return error.SkipZigTest;
    memory_mod.gc_instance = null;
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pid = forkChild(.sleeper);
    var proc: types_mod.Process = .{ .header = undefined, .pid = pid };
    var fiber_a: Fiber = undefined;
    fiber_a.status = .waiting;
    var fiber_b: Fiber = undefined;
    fiber_b.status = .waiting;

    try reactor.registerProcess(&proc, &fiber_a);
    try reactor.registerProcess(&proc, &fiber_b);
    reactor.removeProcessWaiter(&proc, &fiber_a);
    try std.testing.expectEqual(@as(usize, 1), reactor.procs.count());
    reactor.removeProcessWaiter(&proc, &fiber_b);
    // "armed <=> a waiter is parked": no waiters, no registration, and the
    // reactor reads empty again (Linux: the pidfd went with it).
    try std.testing.expectEqual(@as(usize, 0), reactor.procs.count());
    try std.testing.expectEqual(@as(platform.fd_t, -1), proc.wait_handle);
    try std.testing.expect(reactor.isEmpty());

    // Clean up the sleeper ourselves — nothing watches it any more.
    _ = platform.procKill(pid, 9);
    var st: c_int = 0;
    while (true) {
        const r = platform.waitPid(pid, &st, 0);
        if (r == pid) break;
        // A persistent error (ECHILD) must fail the test, not hang the suite.
        if (r < 0 and std.c._errno().* != @intFromEnum(std.c.E.INTR)) return error.ReapFailed;
    }
}

test "kaappi#2415: registering an already-reaped child fails cleanly" {
    if (comptime !reactor_mod.supports_process_watch) return error.SkipZigTest;
    memory_mod.gc_instance = null;
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pid = forkChild(.exit_now);
    var st: c_int = 0;
    while (true) {
        const r = platform.waitPid(pid, &st, 0);
        if (r == pid) break;
        // A persistent error (ECHILD) must fail the test, not hang the suite.
        if (r < 0 and std.c._errno().* != @intFromEnum(std.c.E.INTR)) return error.ReapFailed;
    } // reap it first

    var proc: types_mod.Process = .{ .header = undefined, .pid = pid };
    var fiber: Fiber = undefined;
    fiber.status = .waiting;
    // EVFILT_PROC EV_ADD and pidfd_open both refuse a reaped pid (ESRCH) —
    // the primitive layer closes this race with its own WNOHANG probe. What
    // matters here is that the failure leaves no registration behind.
    try std.testing.expectError(error.Unexpected, reactor.registerProcess(&proc, &fiber));
    try std.testing.expectEqual(@as(usize, 0), reactor.procs.count());
    try std.testing.expect(reactor.isEmpty());
}

test "kaappi#2415: an exited-but-unreaped child resolves promptly or refuses the arm" {
    if (comptime !reactor_mod.supports_process_watch) return error.SkipZigTest;
    memory_mod.gc_instance = null;
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pid = forkChild(.exit_now);
    // Wait for the exit WITHOUT reaping: poll the zombie via kill(pid, 0)
    // staying deliverable while waitpid is never called.
    platform.sleepNs(50 * std.time.ns_per_ms);

    var proc: types_mod.Process = .{ .header = undefined, .pid = pid };
    var fiber: Fiber = undefined;
    fiber.status = .waiting;
    // Platform-dependent split, both acceptable and both handled by the
    // primitive layer: Linux's pidfd_open on a zombie succeeds and the pidfd
    // is immediately readable; a kqueue EV_ADD on one either delivers
    // NOTE_EXIT at once or refuses with ESRCH. What must never happen is a
    // successful registration that then never fires.
    if (reactor.registerProcess(&proc, &fiber)) |_| {
        var ready = newReady();
        defer ready.deinit(std.testing.allocator);
        try pollUntilReady(&reactor, &ready, 5 * std.time.ns_per_s);
        try std.testing.expectEqual(@as(usize, 1), ready.items.len);
        try std.testing.expect(proc.status != null);
    } else |_| {
        try std.testing.expectEqual(@as(usize, 0), reactor.procs.count());
        var st: c_int = 0;
        try std.testing.expectEqual(pid, platform.waitPid(pid, &st, 0));
    }
}
