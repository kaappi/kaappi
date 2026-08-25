//! Audit v2 Phase 5G: reactor **backend parity**.
//!
//! `src/reactor.zig` has four backends behind one `Reactor` API — kqueue
//! (macOS + FreeBSD/OpenBSD/NetBSD), epoll (Linux), WASI `poll_oneoff`,
//! and Windows `WSAEventSelect` + polled pipes — plus one userspace timer
//! heap shared by all four. They must be behaviourally interchangeable.
//!
//! **How this file is the differential.** `Backend` is a comptime switch on
//! `builtin.os.tag`, so no single host can run two backends. What a host
//! *can* do is run the same assertions against whichever backend it has:
//! every test here is written against the backend-independent `Reactor`
//! surface and no test names a backend, so CI's per-OS legs (`zig build
//! test` on ubuntu-latest = epoll, macos = kqueue, and the FreeBSD/OpenBSD/
//! NetBSD/Windows VM legs) *are* the comparison. A property that holds on
//! one leg and fails on another is a parity defect by construction.
//!
//! **What was already covered.** `tests_reactor.zig` (23 tests) pins the
//! core readiness contract — single wake, wake-all, pre-armed readiness,
//! EOF on the read direction, the epoll ADD-vs-MOD bookkeeping, the #1462
//! stale-fire re-arm, and the notifier — and `tests_waitforfd.zig` (unit
//! 5B, #1960) pins the park-vs-drive selector, the #1625 unwind and
//! `close-port`'s wake of parked readers. None of that is repeated here.
//!
//! **What this file adds** are the contracts stated in `reactor.zig`'s own
//! doc comments that nothing asserted:
//!
//!   * the timer heap orders by deadline, not insertion, and an already-due
//!     deadline floors `effectiveTimeout` at 0 rather than blocking;
//!   * `popExpiredTimers` works standalone — the scheduler's per-dispatch
//!     tick calls it without any backend wait;
//!   * `poll`'s documented duplicate-wake ("`ready` may contain the same
//!     fiber twice in one call");
//!   * a hangup wakes waiters on **both** directions, not just the read one;
//!   * `removeWaiter` really silences the removed fiber;
//!   * `msFromNs` — the epoll-only nanoseconds→milliseconds conversion —
//!     never rounds *down*. That is KEP-0001's resolved question 2 ("a timer
//!     may fire slightly late but never early") and it is the one
//!     backend-specific rule that is a pure function, so a kqueue host can
//!     verify epoll's arithmetic directly.
//!
//! Timing discipline (campaign footgun): no test here asserts wall-clock
//! duration. Deadlines are compared against `clockNs()` — the same clock
//! `popExpiredTimers` reads — or asserted as *relative ordering*.
//!
//! **Reach.** Three of the four backends run these assertions in CI:
//! kqueue (the `macos` matrix leg, plus the FreeBSD/OpenBSD/NetBSD VM legs,
//! which execute the cross-compiled binary), epoll (`ubuntu-latest`), and
//! Windows (`windows-arm-test`/`windows-x64-test` run `unit-tests.exe`).
//! WASI is the half-covered fourth: since kaappi#2153 the suite compiles
//! and RUNS for wasm32-wasi (the `wasm` CI job executes the unit-tests
//! binary under wasmtime), so the timer-heap assertions below and
//! `msFromNs` really do run against `WasiPollBackend`'s CLOCK path — but
//! the fd assertions skip there, because WASI p1 under wasmtime cannot
//! construct an EAGAIN-capable fd at all (no pipe/socketpair syscalls,
//! `sock_open` unimplemented; see docs/dev/porting.md Stage 3), so
//! `WasiPollBackend`'s fd branch is still executed by nothing anywhere.
//! `msFromNs` below is the one exception in the other direction, a
//! backend-specific rule any host can check; its Windows twin is a
//! hand-written second copy that no test can reach — kaappi#2154.
//!
//! Both halves of the kqueue/epoll comparison were executed when this file
//! landed, not inferred: macOS aarch64 natively, and aarch64 Linux by
//! cross-compiling the test binary (`zig build test -Dtarget=aarch64-linux`,
//! then `ls -t .zig-cache/o/*/unit-tests | head -1` — the technique the
//! FreeBSD/OpenBSD/NetBSD CI legs already use) and running it in a
//! container with the repo mounted. The mount matters: without `lib/` on
//! disk, eight unrelated tests fail `CompileError`/`ImportFailed` because
//! their `.sld`s cannot resolve, which reads exactly like a backend
//! divergence and is not one.
const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const th = @import("testing_helpers.zig");
const reactor_mod = @import("reactor.zig");
const fiber_mod = @import("fiber.zig");
const Reactor = reactor_mod.Reactor;
const Fiber = fiber_mod.Fiber;

const makePipe = th.makeFdPair;
const makeSocketPair = th.makeBidiFdPair;
const closeFd = th.closeFd;

fn newReady() std.ArrayList(*Fiber) {
    return .empty;
}

/// A parked fiber, as the reactor sees one: it stores and returns the
/// pointer without touching execution state. `register`'s Debug-build
/// staleness assertion reads `status`, so that field must be real.
fn parkedFiber(f: *Fiber) void {
    f.status = .io_waiting;
}

/// Drives `poll` until `ready` is non-empty or `bound_ns` elapses. A single
/// `poll` may return empty while a timer is still pending — an OS wait
/// requested for an interval near the host's tick can return a fraction of
/// a tick early, leaving `clockNs()` still below the deadline. Looping is
/// what `parkOnReactor` itself does, not a workaround.
fn pollUntilReady(reactor: *Reactor, ready: *std.ArrayList(*Fiber), bound_ns: u64) !void {
    const give_up_at = fiber_mod.clockNs() + bound_ns;
    while (true) {
        const now = fiber_mod.clockNs();
        if (now >= give_up_at) return;
        try reactor.poll(give_up_at - now, ready);
        if (ready.items.len > 0) return;
    }
}

/// Generous safety bound: reached only when the thing under test never
/// fires, in which case the caller's own assertion reports the failure.
const poll_retry_bound_ns: u64 = 10_000_000_000;

fn countOccurrences(ready: []const *Fiber, target: *const Fiber) usize {
    var n: usize = 0;
    for (ready) |f| {
        if (f == target) n += 1;
    }
    return n;
}

fn writeByte(fd: platform.fd_t, byte: u8) void {
    const buf = [1]u8{byte};
    const n = th.fdWrite(fd, &buf);
    std.testing.expectEqual(@as(isize, 1), n) catch unreachable;
}

// ---------------------------------------------------------------------------
// Timer heap — the one piece every backend shares, and the one that bounds
// every backend's wait.
// ---------------------------------------------------------------------------

test "parity: timers fire in deadline order, not insertion order" {
    // The heap is `std.PriorityQueue` ordered by deadline; insertion here is
    // deliberately the reverse. Ordering is asserted relatively (the
    // positions within one drained `ready` list), never against wall clock.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    var last: Fiber = undefined;
    parkedFiber(&last);
    var middle: Fiber = undefined;
    parkedFiber(&middle);
    var first: Fiber = undefined;
    parkedFiber(&first);

    // All three already due, so one drain sees all three and the order in
    // `ready` is the heap's, with no dependence on how fast the host runs.
    const now = fiber_mod.clockNs();
    try reactor.addTimer(now -| 1_000_000, &last); // inserted 1st, due last
    try reactor.addTimer(now -| 2_000_000, &middle);
    try reactor.addTimer(now -| 3_000_000, &first); // inserted last, due 1st

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.popExpiredTimers(&ready);

    try std.testing.expectEqual(@as(usize, 3), ready.items.len);
    try std.testing.expectEqual(&first, ready.items[0]);
    try std.testing.expectEqual(&middle, ready.items[1]);
    try std.testing.expectEqual(&last, ready.items[2]);
    try std.testing.expect(reactor.isEmpty());
}

test "parity: an already-due timer floors the wait at zero instead of blocking" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // `effectiveTimeout` reduces a past deadline to 0, so `poll` must return
    // the expired fiber without ever blocking — even with an fd registered
    // that will never fire and a multi-second cap. Asserted as ordering
    // (the poll returns before the cap could have elapsed) rather than as a
    // duration: `clockNs()` is the same clock `popExpiredTimers` reads.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fd_waiter: Fiber = undefined;
    parkedFiber(&fd_waiter);
    try reactor.register(pipe[0], .read, &fd_waiter); // never written to

    var timer_fiber: Fiber = undefined;
    parkedFiber(&timer_fiber);
    try reactor.addTimer(fiber_mod.clockNs() -| 1_000_000, &timer_fiber);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    const before = fiber_mod.clockNs();
    try reactor.poll(30_000_000_000, &ready); // 30s cap that must not apply
    const elapsed = fiber_mod.clockNs() - before;

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&timer_fiber, ready.items[0]);
    // Two orders of magnitude under the cap and three above any plausible
    // syscall: this discriminates "the cap governed the wait" without
    // pinning a duration.
    try std.testing.expect(elapsed < 5_000_000_000);
}

test "parity: popExpiredTimers standalone moves due timers and leaves the rest" {
    // The scheduler calls this on every dispatch tick, with no backend wait
    // involved at all (`FiberScheduler.schedule`), so a timed wait resolves
    // even while busy siblings mean `poll` is never reached. Nothing
    // asserted that path; this is the whole of it.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    var due: Fiber = undefined;
    parkedFiber(&due);
    var not_due: Fiber = undefined;
    parkedFiber(&not_due);

    const now = fiber_mod.clockNs();
    try reactor.addTimer(now -| 1_000_000, &due);
    try reactor.addTimer(now + 60_000_000_000, &not_due); // a minute out

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.popExpiredTimers(&ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&due, ready.items[0]);
    // The far-future timer is still pending, so the reactor still has work.
    try std.testing.expect(!reactor.isEmpty());

    // Idempotent: a second tick with nothing newly due adds nothing.
    try reactor.popExpiredTimers(&ready);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
}

test "parity: isEmpty is false while only a timer is pending" {
    // The complement of tests_reactor.zig's "isEmpty is true after a fired
    // oneshot drains its waiters": a pending timer alone must keep the
    // reactor non-empty, or `parkOnReactor`'s deadlock check would declare
    // a sleeping-only thread deadlocked.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    try std.testing.expect(reactor.isEmpty());

    var sleeper: Fiber = undefined;
    parkedFiber(&sleeper);
    try reactor.addTimer(fiber_mod.clockNs() + 60_000_000_000, &sleeper);
    try std.testing.expect(!reactor.isEmpty());

    reactor.removeTimer(&sleeper);
    try std.testing.expect(reactor.isEmpty());
}

test "parity: removeTimer cancels only the named fiber; a sibling timer still fires" {
    // `removeTimer` scans the heap for one entry and returns at the first
    // match. Nothing asserted that it leaves other fibers' entries alone.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    var cancelled: Fiber = undefined;
    parkedFiber(&cancelled);
    var survivor: Fiber = undefined;
    parkedFiber(&survivor);

    const now = fiber_mod.clockNs();
    try reactor.addTimer(now -| 2_000_000, &cancelled);
    try reactor.addTimer(now -| 1_000_000, &survivor);
    reactor.removeTimer(&cancelled);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.popExpiredTimers(&ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&survivor, ready.items[0]);
    try std.testing.expect(reactor.isEmpty());
}

// ---------------------------------------------------------------------------
// `poll`'s duplicate-wake contract
// ---------------------------------------------------------------------------

test "parity: poll's documented duplicate wake — one fiber, fd and timer, listed twice" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // `Reactor.poll`'s doc comment: "`ready` may contain the same fiber
    // twice in one call ... Callers must tolerate a duplicate wake". The
    // reactor's half of that contract had no test, so a change that
    // silently de-duplicated (or that dropped the second source) would go
    // unnoticed on every backend at once.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var both: Fiber = undefined;
    parkedFiber(&both);
    try reactor.register(pipe[0], .read, &both);
    try reactor.addTimer(fiber_mod.clockNs() -| 1_000_000, &both);

    writeByte(pipe[1], 'x'); // the fd path also fires, in the same call

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 2), ready.items.len);
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(ready.items, &both));
    // Both sources are consumed: nothing is left to fire a third time.
    try std.testing.expect(reactor.isEmpty());
}

// ---------------------------------------------------------------------------
// Readiness edges the existing suite does not reach
// ---------------------------------------------------------------------------

test "parity: a hangup wakes waiters on both directions, not only the read side" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // Every backend maps a broken fd to *both* directions — kqueue's EV_EOF
    // (`readable = is_read or broken`, `writable = !is_read or broken`),
    // epoll's `EPOLLERR|EPOLLHUP`, WASI's per-subscription error/HANGUP,
    // Windows' `FD_CLOSE` and its dead-socket arm. tests_reactor.zig covers
    // only a lone read waiter, which passes even if `broken` set nothing but
    // `readable`. A write waiter on the same fd is what discriminates.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pair = makeSocketPair();
    defer closeFd(pair[0]);
    var peer_open = true;
    defer if (peer_open) closeFd(pair[1]);

    var reader: Fiber = undefined;
    parkedFiber(&reader);
    var writer: Fiber = undefined;
    parkedFiber(&writer);
    try reactor.register(pair[0], .read, &reader);
    try reactor.register(pair[0], .write, &writer);

    closeFd(pair[1]);
    peer_open = false;

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);
    // A backend may report the two directions in one event or in two polls;
    // drain once more so the assertion is on the set, not on the batching.
    if (ready.items.len < 2) try reactor.poll(200_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), countOccurrences(ready.items, &reader));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(ready.items, &writer));
    try std.testing.expect(reactor.isEmpty());
}

test "parity: both directions of one ready fd wake in a single poll" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // A socket that is simultaneously readable and writable must wake both
    // waiters. kqueue delivers two independent knotes that `wait` merges by
    // fd; epoll delivers one event with `IN|OUT`; the merge and the split
    // have to agree. Distinct from the existing "a fired direction re-arms
    // the other", where only one direction is ready at a time.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pair = makeSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);

    writeByte(pair[1], 'x'); // pair[0] readable; an empty sndbuf keeps it writable

    var reader: Fiber = undefined;
    parkedFiber(&reader);
    var writer: Fiber = undefined;
    parkedFiber(&writer);
    try reactor.register(pair[0], .read, &reader);
    try reactor.register(pair[0], .write, &writer);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);
    if (ready.items.len < 2) try reactor.poll(200_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), countOccurrences(ready.items, &reader));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(ready.items, &writer));
    try std.testing.expect(reactor.isEmpty());
}

test "parity: removeWaiter silences the removed fiber and keeps the co-waiter" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // `removeWaiter`'s contract is "without waking it or disturbing other
    // waiters". #1462's test covers the *kernel* consequence of a stale
    // fire; this covers the bookkeeping half on the same direction — two
    // waiters on one fd, one removed, the fd then made ready.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var removed: Fiber = undefined;
    parkedFiber(&removed);
    var kept: Fiber = undefined;
    parkedFiber(&kept);
    try reactor.register(pipe[0], .read, &removed);
    try reactor.register(pipe[0], .read, &kept);

    reactor.removeWaiter(pipe[0], &removed);
    writeByte(pipe[1], 'x');

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&kept, ready.items[0]);
    try std.testing.expectEqual(@as(usize, 0), countOccurrences(ready.items, &removed));
}

test "parity: removeWaiter for a fiber that was never registered is a no-op" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // The unwind path (`waitForFd`'s error exit) calls this on fds whose
    // lists may already have been cleared by a fired ONESHOT. It must not
    // disturb the surviving registration.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var listed: Fiber = undefined;
    parkedFiber(&listed);
    var stranger: Fiber = undefined;
    parkedFiber(&stranger);
    try reactor.register(pipe[0], .read, &listed);

    reactor.removeWaiter(pipe[0], &stranger); // not listed
    reactor.removeWaiter(pipe[1], &listed); // fd not registered at all
    try std.testing.expect(!reactor.isEmpty());

    writeByte(pipe[1], 'x');
    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&listed, ready.items[0]);
}

test "parity: a zero timeout polls without blocking on every backend" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no constructible fd pairs on WASI p1 (kaappi#2153)
    // `effectiveTimeout` floors an already-due deadline at 0 and the
    // scheduler's per-tick probe relies on a 0 wait being a *probe*: kqueue
    // passes a zeroed timespec, epoll `timeout_ms == 0`, WASI a CLOCK
    // subscription with `timeout = 0`, Windows `ms = 0`. A backend that
    // treated 0 as "no bound" (the spelling `null` uses) would convert every
    // tick into an indefinite block.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var waiter: Fiber = undefined;
    parkedFiber(&waiter);
    try reactor.register(pipe[0], .read, &waiter); // never written to

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    const before = fiber_mod.clockNs();
    try reactor.poll(0, &ready);
    const elapsed = fiber_mod.clockNs() - before;

    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
    // Relative, not a duration budget: anything under a second rules out a
    // block, and the registration survives the probe.
    try std.testing.expect(elapsed < 1_000_000_000);
    try std.testing.expect(!reactor.isEmpty());

    // Still armed afterwards — a probe must not consume the registration.
    writeByte(pipe[1], 'x');
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&waiter, ready.items[0]);
}

test "parity: a cross-thread notify interrupts the wait without consuming a timer or an fd arming" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // no OS threads on wasm32-wasi (single-threaded target)
    // tests_reactor.zig pins that `notify()` interrupts an otherwise idle
    // `poll`. What nothing pinned is that it interrupts a wait which has
    // *real* work pending without disturbing it — the case that actually
    // occurs, since a thread with no fibers parked is not in `poll` at all.
    //
    // The two backends recognise their own wakeup differently: kqueue
    // filters the `EVFILT.USER` event by *filter* (deliberately not by
    // ident, which is 0 and would collide with a real fd 0), epoll matches
    // the eventfd by number and must drain it or the next wait spins. Either
    // one misclassifying its own wakeup as fd readiness would drain a
    // waiter list or pop a timer that is not due.
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fd_waiter: Fiber = undefined;
    parkedFiber(&fd_waiter);
    try reactor.register(pipe[0], .read, &fd_waiter); // silent for now

    var sleeper: Fiber = undefined;
    parkedFiber(&sleeper);
    try reactor.addTimer(fiber_mod.clockNs() + 60_000_000_000, &sleeper); // far out

    const Ctx = struct {
        notifier: *reactor_mod.ThreadNotifier,
        fn run(self: @This()) void {
            platform.sleepNs(20_000_000);
            self.notifier.notify();
        }
    };
    const thread = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{ .notifier = reactor.notifyHandle() }});
    defer thread.join();

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    const before = fiber_mod.clockNs();
    try reactor.poll(30_000_000_000, &ready);
    const elapsed = fiber_mod.clockNs() - before;

    // Woke early because of the notify, not because of the 30s cap or the
    // 60s timer — and woke *nobody*.
    try std.testing.expectEqual(@as(usize, 0), ready.items.len);
    try std.testing.expect(reactor.notifier.wake_pending.load(.acquire));
    try std.testing.expect(elapsed < 5_000_000_000);
    // Both pieces of pending work survived the interruption.
    try std.testing.expect(!reactor.isEmpty());
    writeByte(pipe[1], 'x');
    try pollUntilReady(&reactor, &ready, poll_retry_bound_ns);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fd_waiter, ready.items[0]);
    // The far timer is still pending: it was neither popped nor lost.
    try std.testing.expect(!reactor.isEmpty());
    reactor.removeTimer(&sleeper);
    try std.testing.expect(reactor.isEmpty());
}

// ---------------------------------------------------------------------------
// epoll's nanoseconds→milliseconds conversion, verified from any host.
//
// `msFromNs` began epoll-only (`epoll_wait` takes `int` milliseconds) but is
// now the single ceil-to-ms rule for both millisecond backends: the Windows
// backend calls it too (kaappi#2154) rather than restating the arithmetic. It
// is a pure function at file scope in reactor.zig, so it compiles and runs on
// every target. That makes it the one piece of a *foreign* backend a kqueue
// host can verify directly — and its rule is a documented KEP-0001
// resolution, not an implementation detail: "Rounds up (ceil) so a timer may
// fire slightly late but never early (resolved question 2)."
// ---------------------------------------------------------------------------

test "parity: msFromNs never rounds down — a timer may fire late, never early" {
    // The property, stated without reference to the formula: the millisecond
    // bound handed to epoll_wait must cover the requested nanoseconds. A
    // floor-rounding conversion would let epoll return *before* the deadline
    // and pop nothing, which on the other three backends cannot happen —
    // kqueue and WASI are nanosecond-native and Windows ceils too.
    const cases = [_]u64{
        1,
        999_999,
        1_000_000,
        1_000_001,
        1_999_999,
        2_000_000,
        2_000_001,
        999_999_999,
        1_000_000_000,
        1_500_000_000,
        60_000_000_000,
    };
    for (cases) |ns| {
        const ms = reactor_mod.msFromNs(ns);
        try std.testing.expect(ms > 0); // a nonzero wait never becomes a poll
        const covered: u64 = @as(u64, @intCast(ms)) * 1_000_000;
        try std.testing.expect(covered >= ns); // never early
        // ...and no more than one whole millisecond late: the tightest
        // covering bound, so "ceil" is pinned rather than merely "≥".
        try std.testing.expect(covered - ns < 1_000_000);
    }
}

test "parity: msFromNs maps the two sentinel waits — block forever, and do not block" {
    // `null` is "no bound" on every backend (kqueue passes a null timespec,
    // WASI omits the CLOCK subscription, Windows passes INFINITE); epoll
    // spells it -1. Zero must stay zero — `effectiveTimeout` floors an
    // already-due deadline at 0 precisely so the next wait does not block,
    // and a ceil applied to 0 would turn that into a 1ms sleep on every
    // dispatch tick.
    try std.testing.expectEqual(@as(i32, -1), reactor_mod.msFromNs(null));
    try std.testing.expectEqual(@as(i32, 0), reactor_mod.msFromNs(0));
}

test "parity: msFromNs saturates instead of overflowing into a negative timeout" {
    // epoll_wait reads the timeout as a signed int, where any negative value
    // means "block forever". An unsaturated conversion of a huge nanosecond
    // bound would wrap to a negative and silently convert a bounded wait
    // into an unbounded one — the exact shape of a hang that no timer could
    // ever release.
    const huge = [_]u64{
        std.math.maxInt(u64),
        std.math.maxInt(u64) - 999_999,
        @as(u64, std.math.maxInt(i32)) * 1_000_000 + 1,
    };
    for (huge) |ns| {
        const ms = reactor_mod.msFromNs(ns);
        try std.testing.expect(ms > 0);
        try std.testing.expectEqual(std.math.maxInt(i32), ms);
    }
}

test "parity: msFromNs pins the exact ceil mapping the Windows backend now shares" {
    // The Windows backend calls msFromNs (kaappi#2154) instead of restating
    // the ceil, so these exact mappings are the contract both millisecond
    // backends observe. Each row is a value from the issue's own table.
    try std.testing.expectEqual(@as(i32, -1), reactor_mod.msFromNs(null)); // no bound
    try std.testing.expectEqual(@as(i32, 0), reactor_mod.msFromNs(0)); // do not block
    try std.testing.expectEqual(@as(i32, 1), reactor_mod.msFromNs(1)); // 1 ns ceils to 1 ms
    try std.testing.expectEqual(@as(i32, 1), reactor_mod.msFromNs(1_000_000)); // exact 1 ms
    try std.testing.expectEqual(@as(i32, 2), reactor_mod.msFromNs(1_500_000)); // ceils to 2 ms
    try std.testing.expectEqual(std.math.maxInt(i32), reactor_mod.msFromNs(std.math.maxInt(u64))); // clamp
}
