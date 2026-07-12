// Per-fiber memory and switch-time benchmark (KEP-0001 Phase 7, Q5 — the one
// design question the KEP left fully open: "per-fiber memory → live-window
// save/restore with small initial capacities; RSS/switch-time magnitude
// measured in P7").
//
// Two things are measured:
//
//   1. RSS delta and per-yield switch time for N concurrently-live fibers
//      (100 / 1k / 10k), each doing a minimal yield loop.
//   2. Whether the 256-register frameWindow() fallback for native frames
//      (types.zig:546-551 — a frame with no attached closure, e.g. mid-`for-each`,
//      reports a flat 256-register window instead of its real usage) measurably
//      inflates a fiber's saved register/frame arrays. Compared by spawning
//      fibers that yield from a pure bytecode tail loop against fibers that
//      yield from inside `for-each`'s native call frame.
//
// Build/run:  zig build bench-fibers
//   (best with -Doptimize=ReleaseFast)

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");
const fiber_mod = @import("fiber.zig");
const Value = types.Value;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

// Matches the layout `getrusage(2)` fills in on both Linux (glibc) and
// Darwin: two `timeval`s (16 bytes each on both platforms' LP64 ABIs, even
// though the field widths inside differ) followed by a run of `long`s. Only
// `ru_maxrss` is read, so the rest is left as opaque padding.
const RUsage = extern struct {
    _times: [32]u8 = undefined,
    ru_maxrss: i64 = 0,
    _rest: [13 * 8]u8 = undefined,
};
extern "c" fn getrusage(who: c_int, usage: *RUsage) c_int;
const RUSAGE_SELF: c_int = 0;

fn rssMb() f64 {
    var ru: RUsage = undefined;
    _ = getrusage(RUSAGE_SELF, &ru);
    // ru_maxrss is bytes on Darwin, KiB on Linux.
    const divisor: f64 = if (builtin.os.tag == .macos) 1024.0 * 1024.0 else 1024.0;
    return @as(f64, @floatFromInt(ru.ru_maxrss)) / divisor;
}

// Note: VM setup is inlined (not a shared helper) because vm_mod.setVMInstance
// stores the address of the local `vm` in a threadlocal — a helper that
// constructed `vm` and returned it by value would leave that threadlocal
// dangling once the helper's stack frame unwound.

const FiberFootprint = struct {
    count: usize = 0,
    registers_bytes_total: u64 = 0,
    frames_bytes_total: u64 = 0,
    registers_len_max: usize = 0,
    frames_len_max: usize = 0,
};

/// Walks a Scheme list of fiber Values (as returned by `spawn-n` below),
/// summing each fiber's *allocated* register/frame array sizes — the
/// steady-state per-fiber footprint saveCurrentFiber grew it to, which
/// persists after the fiber completes (arrays never shrink back down).
fn fiberListFootprint(list: Value) FiberFootprint {
    var fp = FiberFootprint{};
    var cur = list;
    while (types.isPair(cur)) {
        const fiber_val = types.car(cur);
        const fiber = types.toObject(fiber_val).as(fiber_mod.Fiber);
        fp.count += 1;
        fp.registers_bytes_total += fiber.registers.len * @sizeOf(Value);
        fp.frames_bytes_total += fiber.frames.len * @sizeOf(types.CallFrame);
        fp.registers_len_max = @max(fp.registers_len_max, fiber.registers.len);
        fp.frames_len_max = @max(fp.frames_len_max, fiber.frames.len);
        cur = types.cdr(cur);
    }
    return fp;
}

const SwitchBenchResult = struct {
    n: u32,
    rounds: u32,
    elapsed_ns: u64,
    rss_before_mb: f64,
    rss_after_mb: f64,
};

/// Spawns `n` fibers, each yielding `rounds` times in a pure-bytecode tail
/// loop, then joins them all. Measures wall time (-> per-switch time) and
/// RSS delta.
fn benchSwitchTime(allocator: std.mem.Allocator, n: u32, rounds: u32) !SwitchBenchResult {
    var gc = memory.GC.init(allocator);
    defer gc.deinit();
    var vm = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(&vm);
    memory.setGCInstance(&gc);
    try primitives.registerAll(&vm);
    try vm_mod.vm_bootstrap.install(&vm);
    try library.registerStandardLibraries(&vm.libraries, vm.globals);

    const rss_before = rssMb();

    const src = try std.fmt.allocPrint(allocator,
        \\(define (fiber-body)
        \\  (let loop ((k 0)) (if (= k {d}) k (begin (yield) (loop (+ k 1))))))
        \\(define (spawn-n n proc)
        \\  (let loop ((i 0) (acc '()))
        \\    (if (= i n) acc (loop (+ i 1) (cons (spawn proc) acc)))))
        \\(define fibers (spawn-n {d} fiber-body))
        \\(for-each fiber-join fibers)
        \\(length fibers)
    , .{ rounds, n });
    defer allocator.free(src);

    const start_ns = nowNs();
    _ = try vm.eval(src);
    const elapsed_ns = nowNs() - start_ns;

    const rss_after = rssMb();

    return .{ .n = n, .rounds = rounds, .elapsed_ns = elapsed_ns, .rss_before_mb = rss_before, .rss_after_mb = rss_after };
}

/// Spawns `n` fibers with the given body ("bytecode-only tail loop" vs
/// "yields from inside for-each's native frame"), joins them, then inspects
/// the fibers' own register/frame arrays directly (not via RSS, which is
/// noisy at small N) to see whether frameWindow()'s 256-register fallback
/// for native frames actually inflates the saved window.
fn benchFootprint(allocator: std.mem.Allocator, n: u32, native_frame: bool) !FiberFootprint {
    var gc = memory.GC.init(allocator);
    defer gc.deinit();
    var vm = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(&vm);
    memory.setGCInstance(&gc);
    try primitives.registerAll(&vm);
    try vm_mod.vm_bootstrap.install(&vm);
    try library.registerStandardLibraries(&vm.libraries, vm.globals);

    // Non-tail recursion to depth 60 before the yield/native-call, so the
    // active frame's `base` is well above 0 by the time it happens — a
    // fair test needs the native frame's flat 256-register window to
    // compete against a *non-zero* base, otherwise both cases trivially
    // fit inside the 256-register initial capacity and "inflation" never
    // shows up as a real reallocation.
    const body_name = if (native_frame) "native-fiber-body" else "bytecode-fiber-body";
    const src = try std.fmt.allocPrint(allocator,
        \\(define (bytecode-fiber-body)
        \\  (define (level d)
        \\    (if (= d 0)
        \\        (let loop ((k 0)) (if (= k 1) k (begin (yield) (loop (+ k 1)))))
        \\        (begin (level (- d 1)) d)))
        \\  (level 10))
        \\(define (native-fiber-body)
        \\  (define (level d)
        \\    (if (= d 0)
        \\        (for-each (lambda (x) (yield)) (iota 1))
        \\        (begin (level (- d 1)) d)))
        \\  (level 10))
        \\(define (spawn-n n proc)
        \\  (let loop ((i 0) (acc '()))
        \\    (if (= i n) acc (loop (+ i 1) (cons (spawn proc) acc)))))
        \\(define fibers (spawn-n {d} {s}))
        \\(for-each fiber-join fibers)
        \\fibers
    , .{ n, body_name });
    defer allocator.free(src);

    const fibers_list = try vm.eval(src);
    return fiberListFootprint(fibers_list);
}

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    std.debug.print("=== Q5: spawn-only cost (0 yield rounds -- isolates FiberScheduler.addFiber) ===\n", .{});
    std.debug.print("{s:>8} | {s:>14} | {s:>10}\n", .{ "fibers", "ns/spawn+join", "total ms" });
    std.debug.print("---------+----------------+-----------\n", .{});
    for ([_]u32{ 100, 1_000, 10_000 }) |n| {
        const r = try benchSwitchTime(allocator, n, 0);
        const ns_per = @as(f64, @floatFromInt(r.elapsed_ns)) / @as(f64, @floatFromInt(n));
        std.debug.print("{d:>8} | {d:>14.1} | {d:>9.2}\n", .{ n, ns_per, @as(f64, @floatFromInt(r.elapsed_ns)) / 1e6 });
    }

    std.debug.print("\n=== Q5: per-fiber switch time & RSS ===\n", .{});
    std.debug.print("{s:>8} | {s:>8} | {s:>12} | {s:>10} | {s:>10} | {s:>10}\n", .{ "fibers", "rounds", "ns/switch", "rss before", "rss after", "delta MB" });
    std.debug.print("---------+----------+--------------+------------+------------+-----------\n", .{});
    const ns_list = [_]u32{ 100, 1_000, 10_000 };
    var switch_results: [ns_list.len]SwitchBenchResult = undefined;
    for (ns_list, 0..) |n, i| {
        const rounds: u32 = 50;
        const r = try benchSwitchTime(allocator, n, rounds);
        switch_results[i] = r;
        const total_switches = @as(f64, @floatFromInt(n)) * @as(f64, @floatFromInt(rounds));
        const ns_per_switch = @as(f64, @floatFromInt(r.elapsed_ns)) / total_switches;
        std.debug.print("{d:>8} | {d:>8} | {d:>9.1} ns | {d:>7.2} MB | {d:>7.2} MB | {d:>7.2} MB\n", .{ n, rounds, ns_per_switch, r.rss_before_mb, r.rss_after_mb, r.rss_after_mb - r.rss_before_mb });
    }

    std.debug.print("\n=== Q5: does the 256-register native-frame fallback inflate per-fiber windows? ===\n", .{});
    std.debug.print("{s:>8} | {s:>10} | {s:>14} | {s:>14} | {s:>10} | {s:>10}\n", .{ "fibers", "kind", "avg regs/fiber", "avg frames/fbr", "regs KB", "frames KB" });
    std.debug.print("---------+------------+----------------+----------------+------------+-----------\n", .{});
    const footprint_ns = [_]u32{ 100, 1_000 };
    for (footprint_ns) |n| {
        for ([_]bool{ false, true }) |native_frame| {
            const fp = try benchFootprint(allocator, n, native_frame);
            const avg_regs = @as(f64, @floatFromInt(fp.registers_bytes_total / @sizeOf(Value))) / @as(f64, @floatFromInt(fp.count));
            const avg_frames = @as(f64, @floatFromInt(fp.frames_bytes_total / @sizeOf(types.CallFrame))) / @as(f64, @floatFromInt(fp.count));
            std.debug.print("{d:>8} | {s:>10} | {d:>14.1} | {d:>14.1} | {d:>9.1} | {d:>9.1}\n", .{
                n,
                if (native_frame) "native" else "bytecode",
                avg_regs,
                avg_frames,
                @as(f64, @floatFromInt(fp.registers_bytes_total)) / 1024.0,
                @as(f64, @floatFromInt(fp.frames_bytes_total)) / 1024.0,
            });
        }
    }

    // Machine-readable summary lines, matching bench.zig's convention.
    // Reuses the results already collected above instead of re-running the
    // (expensive at 10k fibers -- see the O(n) FiberScheduler.schedule() scan
    // noted in the write-up) switch-time benchmark a second time.
    for (switch_results) |r| {
        const secs = @as(f64, @floatFromInt(r.elapsed_ns)) / 1e9;
        std.debug.print("name: fiber_switch_{d}, time: {d:.6}, status: ok, min: {d:.6}, max: {d:.6}, iterations: {d}\n", .{ r.n, secs, secs, secs, r.n * r.rounds });
    }
}
