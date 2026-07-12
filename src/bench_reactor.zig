// Direct reactor benchmark (KEP-0001 Phase 7): exercises real epoll_ctl/
// kevent registration and wake-all fan-out independent of the VM/Scheme
// layer, following the same pattern as src/tests_reactor.zig (pipe fds +
// fake `Fiber` locals with only `.status` set, driven straight against
// `Reactor.register`/`poll`).
//
// This is the *only* way to measure the reactor's own costs in this
// codebase today: kaappi-net's raw TCP sockets never call into
// Reactor.register/waitForFd at all (see the KEP-0001 Phase 7 write-up),
// so an HTTP-server-level benchmark can't observe these numbers.
//
// Measures:
//   Q3 - ONESHOT re-arm cost (`register()`'s call into `backend.arm`) vs.
//        an adjacent read(2)/write(2) syscall pair on the same fd.
//   Q1 - wake-all fan-out cost: N fake fibers registered as waiters on one
//        shared fd, one real write, how long `poll()` takes to wake all N.
//   Q2 - timer granularity: scheduled deadline vs. actual fire time.
//
// Build/run:  zig build bench-reactor

const std = @import("std");
const reactor_mod = @import("reactor.zig");
const fiber_mod = @import("fiber.zig");
const Reactor = reactor_mod.Reactor;
const Fiber = fiber_mod.Fiber;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn makePipe() [2]std.c.fd_t {
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) unreachable;
    return fds;
}

fn closeFd(fd: std.c.fd_t) void {
    _ = std.posix.system.close(fd);
}

const RearmResult = struct { arm_ns: f64, io_ns: f64 };

/// Q3: register()'s epoll_ctl/kevent call vs. an adjacent read(2)+write(2)
/// pair, on the same pipe, averaged over `iters` cycles.
fn benchRearmVsIo(iters: u32) !RearmResult {
    var reactor = try Reactor.init(std.heap.page_allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    var fiber: Fiber = undefined;
    fiber.status = .io_waiting;

    const arm_start = nowNs();
    var i: u32 = 0;
    while (i < iters) : (i += 1) {
        try reactor.register(pipe[0], .read, &fiber);
        // Reset waiter-list state before the next cycle's register() call,
        // isolating just the kernel arm cost rather than accumulating an
        // ever-growing waiter list.
        reactor.removeWaiter(pipe[0], &fiber);
    }
    const arm_elapsed = nowNs() - arm_start;

    var buf: [1]u8 = .{0};
    const io_start = nowNs();
    i = 0;
    while (i < iters) : (i += 1) {
        const wrote = std.posix.system.write(pipe[1], &buf, 1);
        if (wrote != 1) return error.ShortWrite;
        const bytes_read = std.posix.system.read(pipe[0], &buf, 1);
        if (bytes_read != 1) return error.ShortRead;
    }
    const io_elapsed = nowNs() - io_start;

    return .{
        .arm_ns = @as(f64, @floatFromInt(arm_elapsed)) / @as(f64, @floatFromInt(iters)),
        .io_ns = @as(f64, @floatFromInt(io_elapsed)) / @as(f64, @floatFromInt(iters)),
    };
}

const FanoutResult = struct { n: u32, woken: usize, poll_ns: u64 };

/// Q1: N fake fibers registered as waiters on one shared fd (read
/// interest); one real write; how long poll() takes to wake all N and
/// confirm every one of them actually gets woken (wake-all, not
/// wake-head-only).
fn benchWakeAllFanout(allocator: std.mem.Allocator, n: u32) !FanoutResult {
    var reactor = try Reactor.init(allocator);
    defer reactor.deinit();

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    const fibers = try allocator.alloc(Fiber, n);
    defer allocator.free(fibers);
    for (fibers) |*f| {
        f.status = .io_waiting;
        try reactor.register(pipe[0], .read, f);
    }

    var buf: [1]u8 = .{'x'};
    const wrote = std.posix.system.write(pipe[1], &buf, 1);
    if (wrote != 1) return error.ShortWrite;

    var ready: std.ArrayList(*Fiber) = .empty;
    defer ready.deinit(allocator);
    // Reserve capacity for all N wakeups before starting the clock, so the
    // timed region measures poll()'s own dispatch/fan-out work rather than
    // the result-buffer's growth reallocations.
    try ready.ensureTotalCapacity(allocator, n);

    const start = nowNs();
    try reactor.poll(5_000_000_000, &ready);
    const elapsed = nowNs() - start;

    return .{ .n = n, .woken = ready.items.len, .poll_ns = elapsed };
}

const TimerResult = struct { requested_ns: u64, actual_late_ns: i64 };

/// Q2: schedules one timer at a known deadline and measures how late (or
/// early) the reactor's poll() actually returns relative to it.
fn benchTimerGranularity(requested_ns: u64) !TimerResult {
    var reactor = try Reactor.init(std.heap.page_allocator);
    defer reactor.deinit();

    var fiber: Fiber = undefined;
    fiber.status = .waiting;

    var ready: std.ArrayList(*Fiber) = .empty;
    defer ready.deinit(std.heap.page_allocator);
    try ready.ensureTotalCapacity(std.heap.page_allocator, 1);

    const deadline = nowNs() + requested_ns;
    try reactor.addTimer(deadline, &fiber);
    try reactor.poll(requested_ns + 5_000_000_000, &ready);

    const actual = nowNs();
    var fired = false;
    for (ready.items) |f| {
        if (f == &fiber) fired = true;
    }
    if (!fired) return error.TimerDidNotFire;
    return .{ .requested_ns = requested_ns, .actual_late_ns = @as(i64, @intCast(actual)) - @as(i64, @intCast(deadline)) };
}

pub fn main() !void {
    const target_os = @import("builtin").target.os.tag;
    std.debug.print("reactor backend: {s}\n\n", .{@tagName(target_os)});

    std.debug.print("=== Q3: ONESHOT re-arm cost vs. adjacent read(2)/write(2) ===\n", .{});
    const iters: u32 = 100_000;
    const r = try benchRearmVsIo(iters);
    std.debug.print("register() (arm):    {d:>8.1} ns/call\n", .{r.arm_ns});
    std.debug.print("read+write (io):      {d:>8.1} ns/call\n", .{r.io_ns});
    std.debug.print("arm/io ratio:         {d:>8.2}x\n\n", .{r.arm_ns / r.io_ns});

    std.debug.print("=== Q1: wake-all fan-out cost (N waiters on one shared fd) ===\n", .{});
    std.debug.print("{s:>6} | {s:>8} | {s:>12} | {s:>14}\n", .{ "n", "woken", "poll ns", "ns/woken-fiber" });
    std.debug.print("--------+----------+--------------+----------------\n", .{});
    for ([_]u32{ 2, 10, 100, 1000 }) |n| {
        const fr = try benchWakeAllFanout(std.heap.page_allocator, n);
        std.debug.print("{d:>6} | {d:>8} | {d:>12} | {d:>14.1}\n", .{ fr.n, fr.woken, fr.poll_ns, @as(f64, @floatFromInt(fr.poll_ns)) / @as(f64, @floatFromInt(fr.n)) });
    }

    std.debug.print("\n=== Q2: timer granularity (requested vs. actual fire time) ===\n", .{});
    std.debug.print("{s:>14} | {s:>14}\n", .{ "requested ms", "late by (ns)" });
    std.debug.print("----------------+----------------\n", .{});
    for ([_]u64{ 1_000_000, 5_000_000, 20_000_000, 100_000_000 }) |req_ns| {
        const tr = try benchTimerGranularity(req_ns);
        std.debug.print("{d:>14.1} | {d:>14}\n", .{ @as(f64, @floatFromInt(req_ns)) / 1e6, tr.actual_late_ns });
    }

    std.debug.print("\nname: reactor_arm, time: {d:.9}, status: ok, min: {d:.9}, max: {d:.9}, iterations: {d}\n", .{ r.arm_ns / 1e9, r.arm_ns / 1e9, r.arm_ns / 1e9, iters });
    std.debug.print("name: reactor_io, time: {d:.9}, status: ok, min: {d:.9}, max: {d:.9}, iterations: {d}\n", .{ r.io_ns / 1e9, r.io_ns / 1e9, r.io_ns / 1e9, iters });
}
