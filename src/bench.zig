// call/cc and call/ec capture micro-benchmark.
//
// Isolates the cost of the continuation *capture path* by running a tight loop
// of immediately-escaping captures at an elevated call-stack depth. GC is
// disabled during the timed region so the measurement reflects capture/restore
// copy + allocation cost rather than collector overhead.
//
//   call/cc -> full snapshot capture (registers + frames), O(stack)
//   call/ec -> escape continuation, O(1) capture (no snapshot)
//
// Build/run:  zig build bench
//   (best with -Doptimize=ReleaseFast)

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

const Result = struct { ns_per: f64, heap_mb: usize };

/// Time `iters` immediately-escaping captures of `prim` (call/cc or call/ec) at
/// stack depth `depth`. Each run uses a fresh VM with GC disabled.
fn measure(allocator: std.mem.Allocator, prim: []const u8, depth: u32, iters: u32) !Result {
    var gc = memory.GC.init(allocator);
    defer gc.deinit();
    var vm = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    try primitives.registerAll(&vm);
    memory.setGCInstance(&gc);
    try library.registerStandardLibraries(&vm.libraries, vm.globals);

    // at-depth builds `depth` real (non-tail) frames to elevate the register
    // base; cap runs a tail loop performing `iters` escaping captures.
    var defs: [256]u8 = undefined;
    const defs_src = try std.fmt.bufPrint(&defs,
        \\(define (at-depth d t) (if (= d 0) (t) (+ 0 (at-depth (- d 1) t))))
        \\(define (cap n)
        \\  (let loop ((i n) (a 0))
        \\    (if (= i 0) a (loop (- i 1) (+ a ({s} (lambda (k) (k 1))))))))
    , .{prim});
    _ = try vm.eval(defs_src);

    var buf: [128]u8 = undefined;
    const src = try std.fmt.bufPrint(&buf, "(at-depth {d} (lambda () (cap {d})))", .{ depth, iters });

    gc.enabled = false; // measure only the capture/restore path

    const start_ns = nowNs();
    const result = try vm.eval(src);
    const elapsed_ns = nowNs() - start_ns;

    if (types.toFixnum(result) != @as(i64, iters)) {
        std.debug.print("  !! wrong result for {s}: {d}\n", .{ prim, types.toFixnum(result) });
    }
    return .{
        .ns_per = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters)),
        .heap_mb = gc.bytes_allocated / (1024 * 1024),
    };
}

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const iters: u32 = 100000;
    const depths = [_]u32{ 0, 20, 40 };

    std.debug.print("capture benchmark: {d} immediately-escaping captures, GC off\n", .{iters});
    std.debug.print("{s:>6} | {s:>22} | {s:>22} | {s:>8}\n", .{ "depth", "call/cc (full)", "call/ec (escape)", "speedup" });
    std.debug.print("-------+------------------------+------------------------+---------\n", .{});
    var cc_d0: Result = undefined;
    var ec_d0: Result = undefined;
    for (depths) |d| {
        const cc = try measure(allocator, "call/cc", d, iters);
        const ec = try measure(allocator, "call/ec", d, iters);
        if (d == 0) {
            cc_d0 = cc;
            ec_d0 = ec;
        }
        std.debug.print(
            "{d:>6} | {d:>9.0} ns  {d:>4} MB | {d:>9.0} ns  {d:>4} MB | {d:>6.1}x\n",
            .{ d, cc.ns_per, cc.heap_mb, ec.ns_per, ec.heap_mb, cc.ns_per / ec.ns_per },
        );
    }

    const cc_secs = cc_d0.ns_per * @as(f64, @floatFromInt(iters)) / 1e9;
    const ec_secs = ec_d0.ns_per * @as(f64, @floatFromInt(iters)) / 1e9;
    std.debug.print("name: call_cc, time: {d:.6}, status: ok, min: {d:.6}, max: {d:.6}, iterations: {d}\n", .{ cc_secs, cc_secs, cc_secs, iters });
    std.debug.print("name: call_ec, time: {d:.6}, status: ok, min: {d:.6}, max: {d:.6}, iterations: {d}\n", .{ ec_secs, ec_secs, ec_secs, iters });
}
