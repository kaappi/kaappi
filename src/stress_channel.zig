//! KEP-0002 Phase 3 (#1468): PCT-style randomized scheduling stress test for
//! SharedChannel/ThreadNotifier (the KEP-0002 research plan's P2 method
//! step 2). Spawns N producer / M consumer OS threads hammering one
//! SharedChannel directly (white-box, no VM -- the same layer
//! tests_shared_channel.zig's own stress test exercises, just with
//! pct_stress's randomized yield injection turned on at every lock
//! acquire/release and refcount op). Prints the seed on any failure for
//! deterministic replay.
//!
//! Build/run:  zig build stress-channel
//!             zig build stress-channel -- <seed>
//!             zig build stress-channel -- <seed> <producers> <consumers> <per-producer>

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const shared_channel = @import("shared_channel.zig");
const shared_object = @import("shared_object.zig");
const reactor_mod = @import("reactor.zig");
const pct_stress = @import("pct_stress.zig");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch fmt;
    _ = std.posix.system.write(2, msg.ptr, msg.len);
    std.process.exit(1);
}

const Producer = struct {
    sc: *shared_channel.SharedChannel,
    count: usize,
    start_val: i64,
    thread_tag: u64,

    fn run(self: Producer) void {
        pct_stress.seedThread(seed, self.thread_tag);
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            _ = shared_channel.send(self.sc, types.makeFixnum(self.start_val + @as(i64, @intCast(i))), null) catch |err|
                fail("producer: send failed: {t} (seed={d})\n", .{ err, seed });
        }
    }
};

const Consumer = struct {
    sc: *shared_channel.SharedChannel,
    target_total: usize,
    count: *std.atomic.Value(usize),
    sum: *std.atomic.Value(i64),
    thread_tag: u64,

    fn run(self: Consumer) void {
        pct_stress.seedThread(seed, self.thread_tag);
        var local_reactor = reactor_mod.Reactor.init(std.heap.page_allocator) catch |err|
            fail("consumer: Reactor.init failed: {t} (seed={d})\n", .{ err, seed });
        defer local_reactor.deinit();
        const notifier = local_reactor.notifyHandle();
        var local_gc = memory.GC.init(std.heap.page_allocator);
        defer local_gc.deinit();

        while (self.count.load(.monotonic) < self.target_total) {
            const outcome = shared_channel.receive(self.sc, &local_gc, notifier) catch |err|
                fail("consumer: receive failed: {t} (seed={d})\n", .{ err, seed });
            switch (outcome) {
                .value => |v| {
                    _ = self.sum.fetchAdd(types.toFixnum(v), .monotonic);
                    _ = self.count.fetchAdd(1, .monotonic);
                },
                .would_park => std.Thread.yield() catch {},
                .eof => fail("consumer: unexpected eof (seed={d})\n", .{seed}),
            }
        }
    }
};

var seed: u64 = undefined;

fn defaultSeed() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @bitCast(ts.sec)) ^ @as(u64, @intCast(ts.nsec));
}

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var args = try init.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.skip(); // argv[0]

    seed = if (args.next()) |s|
        std.fmt.parseInt(u64, s, 10) catch fail("invalid seed: {s}\n", .{s})
    else
        defaultSeed();
    const n_producers: usize = if (args.next()) |s| try std.fmt.parseInt(usize, s, 10) else 8;
    const m_consumers: usize = if (args.next()) |s| try std.fmt.parseInt(usize, s, 10) else 8;
    const per_producer: usize = if (args.next()) |s| try std.fmt.parseInt(usize, s, 10) else 500;

    var buf: [256]u8 = undefined;
    const banner = try std.fmt.bufPrint(&buf, "stress-channel: seed={d} producers={d} consumers={d} per_producer={d}\n", .{ seed, n_producers, m_consumers, per_producer });
    _ = std.posix.system.write(1, banner.ptr, banner.len);

    pct_stress.enabled = true;

    const baseline = shared_object.liveCount();
    const notifier_baseline = reactor_mod.notifierLiveCount();

    const sc = try shared_channel.SharedChannel.create();
    var received_count = std.atomic.Value(usize).init(0);
    var received_sum = std.atomic.Value(i64).init(0);
    const total = n_producers * per_producer;

    const allocator = std.heap.page_allocator;
    const producers = try allocator.alloc(std.Thread, n_producers);
    defer allocator.free(producers);
    const consumers = try allocator.alloc(std.Thread, m_consumers);
    defer allocator.free(consumers);

    for (0..n_producers) |i| {
        producers[i] = try std.Thread.spawn(.{}, Producer.run, .{Producer{
            .sc = sc,
            .count = per_producer,
            .start_val = @as(i64, @intCast(i * 1_000_000)),
            .thread_tag = i,
        }});
    }
    for (0..m_consumers) |i| {
        consumers[i] = try std.Thread.spawn(.{}, Consumer.run, .{Consumer{
            .sc = sc,
            .target_total = total,
            .count = &received_count,
            .sum = &received_sum,
            .thread_tag = n_producers + i,
        }});
    }
    for (producers) |p| p.join();
    for (consumers) |c| c.join();

    pct_stress.enabled = false;

    if (received_count.load(.monotonic) != total)
        fail("FAIL: expected {d} deliveries, got {d} (seed={d})\n", .{ total, received_count.load(.monotonic), seed });

    var expected_sum: i64 = 0;
    for (0..n_producers) |i| {
        var j: usize = 0;
        while (j < per_producer) : (j += 1)
            expected_sum += @as(i64, @intCast(i * 1_000_000)) + @as(i64, @intCast(j));
    }
    if (received_sum.load(.monotonic) != expected_sum)
        fail("FAIL: expected sum {d}, got {d} -- duplicated or corrupted delivery (seed={d})\n", .{ expected_sum, received_sum.load(.monotonic), seed });

    sc.release();
    if (shared_object.liveCount() != baseline)
        fail("FAIL: shared_object leak: baseline={d} now={d} (seed={d})\n", .{ baseline, shared_object.liveCount(), seed });
    if (reactor_mod.notifierLiveCount() != notifier_baseline)
        fail("FAIL: notifier leak: baseline={d} now={d} (seed={d})\n", .{ notifier_baseline, reactor_mod.notifierLiveCount(), seed });

    const ok_msg = "stress-channel: PASS\n";
    _ = std.posix.system.write(1, ok_msg.ptr, ok_msg.len);
}
