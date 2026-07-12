// Per-fiber memory and switch-time benchmark (KEP-0001 Phase 7, Q5 — the one
// design question the KEP left fully open: "per-fiber memory → live-window
// save/restore with small initial capacities; RSS/switch-time magnitude
// measured in P7").
//
// Two things are measured:
//
//   1. RSS delta and per-yield switch time for N concurrently-live fibers
//      (100 / 1k / 10k), each doing a minimal yield loop. RSS is reported
//      via `ru_maxrss`, which is a *process-lifetime high-water mark*, not
//      a per-call-site peak -- later rows in the same process run only show
//      a nonzero delta once they need more than any earlier row already
//      reached. Read the deltas as "additional peak RSS beyond what the
//      largest case measured so far already required", not as independent
//      per-N measurements.
//   2. Whether the 256-register frameWindow() fallback for native frames
//      (types.zig:546-551 — a frame with no attached closure) measurably
//      inflates a fiber's saved register/frame arrays. Compared by spawning
//      fibers that suspend (via thread-sleep!) from plain bytecode against
//      fibers that suspend from inside a genuinely native call frame
//      (with-exception-handler's thunk invocation — see benchFootprint's
//      doc comment for why `for-each` doesn't work for this).
//
// Build/run:  zig build bench-fibers
//   (best with -Doptimize=ReleaseFast)

const std = @import("std");
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

fn rssMb() f64 {
    const ru = std.posix.getrusage(std.posix.rusage.SELF);
    // ru_maxrss is bytes on Darwin, KiB on Linux.
    const divisor: f64 = if (@import("builtin").os.tag == .macos) 1024.0 * 1024.0 else 1024.0;
    return @as(f64, @floatFromInt(ru.maxrss)) / divisor;
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

/// Spawns `n` fibers with the given body ("bytecode-only" vs. "suspends
/// from inside a genuinely native call frame"), joins them, then inspects
/// the fibers' own register/frame arrays directly (not via RSS, which is
/// noisy at small N) to see whether frameWindow()'s 256-register fallback
/// for native frames actually inflates the saved window.
///
/// `for-each` was tried first and discarded: it's pure bootstrap Scheme
/// (`src/vm_bootstrap.zig`), not a Zig primitive, so calling its callback
/// never pushes a native (`locals_count == 0`-flavored, see
/// `CallFrame.frameWindow()`) frame at all -- both "bytecode" and "native"
/// cases were exercising identical bytecode paths, which is why they always
/// measured identically regardless of recursion depth.
/// `with-exception-handler` (`src/primitives_control.zig`) is a genuine
/// native primitive that calls its thunk via `vm.callThunk` ->
/// `callReentrant` (`src/vm_calls.zig`), which pushes a real frame for the
/// thunk closure and increments `native_reentry_depth`. `yield` deliberately
/// no-ops under `native_reentry_depth > 0` (`src/primitives_fiber.zig`, the
/// #1184 limitation), so `thread-sleep!` is used as the suspension point
/// instead -- it has no such re-entrancy guard.
///
/// This still did not demonstrate measurable inflation, for two compounding
/// reasons found during development (kept here rather than in the doc,
/// since they're implementation-level detail about *this benchmark*, not a
/// KEP-0001 finding): (1) at low concurrency and shallow recursion (N=1-5,
/// depth 10) `liveRegisterSpan` never exceeds the 256-register initial
/// floor for either case, so `registers.len` reads identically regardless
/// of what's "really" needed underneath that floor; (2) pushing recursion
/// deep enough to force a real reallocation (depth 100+) makes
/// `thread-sleep!` inside `with-exception-handler`'s thunk crash with a
/// native stack overflow even at just N=2 concurrently-dispatched fibers --
/// nested `runUntil` calls clear `dispatched_from_scheduler`
/// (`src/vm_dispatch.zig:80-87`) for their extent the same way they make
/// `yield` no-op, so a blocking `thread-sleep!` there always drives the
/// scheduler recursively rather than flat-unwinding, and concurrently-
/// dispatched fibers each doing this chain-nest. This is a *different*,
/// narrower version of the same class of problem #1463 fixed -- narrower
/// because it needs a blocking call nested inside a re-entrant native frame
/// specifically, not just any retry loop -- and is left unfixed here as
/// out of scope for a measurement phase. Given this, N=1 and a shallow
/// depth were kept as the only combination confirmed safe to run; the
/// "no inflation observed" result below should be read as inconclusive
/// (blind spot 1) rather than a clean negative.
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

    // Non-tail recursion to depth 10 before the suspension point, so the
    // active frame's `base` is above 0 by the time it happens. Kept shallow
    // deliberately -- see the doc comment above for why deeper recursion
    // here is unsafe to run.
    const body_name = if (native_frame) "native-fiber-body" else "bytecode-fiber-body";
    const src = try std.fmt.allocPrint(allocator,
        \\(define (bytecode-fiber-body)
        \\  (define (level d)
        \\    (if (= d 0)
        \\        (thread-sleep! 0.0001)
        \\        (begin (level (- d 1)) d)))
        \\  (level 10))
        \\(define (native-fiber-body)
        \\  (define (level d)
        \\    (if (= d 0)
        \\        (with-exception-handler
        \\          (lambda (e) #f)
        \\          (lambda () (thread-sleep! 0.0001)))
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
    // Not DebugAllocator: its per-allocation bookkeeping (stack-trace
    // capture, canaries) would contaminate both the timing and RSS numbers
    // this benchmark exists to measure.
    const allocator = std.heap.c_allocator;

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
    // N=1 only -- see benchFootprint's doc comment. Concurrent fibers each
    // suspending inside with-exception-handler's thunk chain-nest the
    // native stack (confirmed crashing at N=2 with deep-enough recursion);
    // the footprint question only needs one fiber's own array sizes, not
    // concurrency, so N=1 sidesteps that entirely.
    const footprint_ns = [_]u32{1};
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
