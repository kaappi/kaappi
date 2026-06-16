// call/cc capture micro-benchmark.
//
// Isolates the cost of the continuation *capture path* (captureContinuation +
// allocContinuation + restoreContinuation) by running a tight call/cc loop at
// an elevated call-stack depth. GC is disabled during the timed region so the
// measurement reflects capture/restore copy + allocation cost rather than
// collector overhead (the two capture variants share identical GC behaviour,
// so GC noise would only obscure the comparison).
//
// Build/run:  zig build bench

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");

const Case = struct { depth: u32, iters: u32 };

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn run(allocator: std.mem.Allocator, case: Case) !void {
    var gc = memory.GC.init(allocator);
    defer gc.deinit();
    var vm = vm_mod.VM.init(&gc);
    defer vm.deinit();
    try primitives.registerAll(&vm);
    primitives.setGCInstance(&gc);
    try library.registerStandardLibraries(&vm.libraries, &vm.globals);

    // Definitions: build `depth` real (non-tail) frames so the register base is
    // elevated, then run a tail loop performing `iters` immediately-escaping
    // call/cc captures.
    _ = try vm.eval(
        \\(define (at-depth d t) (if (= d 0) (t) (+ 0 (at-depth (- d 1) t))))
        \\(define (cap n)
        \\  (let loop ((i n) (a 0))
        \\    (if (= i 0) a (loop (- i 1) (+ a (call/cc (lambda (k) (k 1))))))))
    );

    var buf: [128]u8 = undefined;
    const src = try std.fmt.bufPrint(&buf, "(at-depth {d} (lambda () (cap {d})))", .{ case.depth, case.iters });

    // Disable GC so we measure only the capture/restore path.
    gc.enabled = false;

    const start_ns = nowNs();
    const result = try vm.eval(src);
    const elapsed_ns = nowNs() - start_ns;

    if (types.toFixnum(result) != @as(i64, case.iters)) {
        std.debug.print("  !! wrong result: {d}\n", .{types.toFixnum(result)});
    }
    const per = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(case.iters));
    std.debug.print(
        "  depth={d:>3}  iters={d:>7}  total={d:>7.1}ms  per-capture={d:>7.0}ns  heap={d:>5} MB\n",
        .{
            case.depth,
            case.iters,
            @as(f64, @floatFromInt(elapsed_ns)) / 1e6,
            per,
            gc.bytes_allocated / (1024 * 1024),
        },
    );
}

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    std.debug.print("call/cc capture benchmark (GC disabled during timed region)\n", .{});
    const cases = [_]Case{
        .{ .depth = 0, .iters = 100000 },
        .{ .depth = 20, .iters = 100000 },
        .{ .depth = 40, .iters = 100000 },
    };
    for (cases) |c| try run(allocator, c);
}
