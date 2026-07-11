// KEP-0001 Phase 1: reactor core, tested in isolation (no scheduler caller
// yet — that's Phase 2). These are plain Zig tests against real fds; no VM
// or GC is involved. Fake *Fiber values are bare stack locals: reactor.zig
// never dereferences a parked fiber, it only stores and later returns the
// pointer, so distinct addresses are all a test needs.
const std = @import("std");
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
    _ = std.posix.system.close(fd);
}

fn newReady() std.ArrayList(*Fiber) {
    return .empty;
}

test "register + poll wakes the fiber when the fd becomes readable" {
    var reactor = try Reactor.init(std.testing.allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber_a: Fiber = undefined;
    try reactor.register(pipe[0], .read, &fiber_a);

    _ = std.posix.system.write(pipe[1], "x", 1);

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
    var fiber_b: Fiber = undefined;
    try reactor.register(pipe[0], .read, &fiber_a);
    try reactor.register(pipe[0], .read, &fiber_b);

    _ = std.posix.system.write(pipe[1], "x", 1);

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
    var fiber_timer: Fiber = undefined;
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
    try reactor.register(pipe[0], .read, &fiber_a);
    reactor.unregister(pipe[0]);

    _ = std.posix.system.write(pipe[1], "x", 1);

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
    try reactor.register(pipe[0], .read, &fiber_a);
    _ = std.posix.system.write(pipe[1], "x", 1);

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
    try reactor.register(pipe[0], .read, &fiber_a);
    _ = std.posix.system.write(pipe[1], "x", 1);

    var ready = newReady();
    defer ready.deinit(std.testing.allocator);
    try reactor.poll(5_000_000_000, &ready);
    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    ready.clearRetainingCapacity();

    var fiber_b: Fiber = undefined;
    try reactor.register(pipe[0], .read, &fiber_b);
    _ = std.posix.system.write(pipe[1], "y", 1);

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
    var fiber_b: Fiber = undefined;
    try reactor.register(pipe_a[0], .read, &fiber_a);
    try reactor.register(pipe_b[0], .read, &fiber_b);

    _ = std.posix.system.write(pipe_b[1], "x", 1); // only b becomes ready

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
    var fiber_write: Fiber = undefined;
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

    _ = std.posix.system.write(pair[1], "x", 1);
    try reactor.poll(5_000_000_000, &ready);

    try std.testing.expectEqual(@as(usize, 1), ready.items.len);
    try std.testing.expectEqual(&fiber_read, ready.items[0]);
}
