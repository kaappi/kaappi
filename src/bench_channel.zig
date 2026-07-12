// KEP-0002 Phase 1 channel benchmark. Two measurements, no automated
// pass/fail threshold -- run before/after and compare by eye, matching
// bench_fibers.zig/bench_reactor.zig:
//
//   1. Local (unpromoted) channel send+receive ns/op -- the invariant-3
//      fast-path regression gate ("An unpromoted channel is today's
//      head/tail pair queue plus one pointer null-check ... 'Unmeasurable'
//      is a Phase 1 benchmark gate, not an assumption"). Runs through a
//      real VM/eval so the measurement includes the actual dispatch path
//      (the new foreign-owner check and ch.shared null-check included).
//   2. Promoted, single-thread channel send+receive ns/op -- the Phase 1
//      installment of research/open-problems.md's P3 envelope-cost harness
//      ("(A) per-message GC struct as specified"). Parameterized over
//      P3's workload shapes (fixnum, small pair, 1 KiB string, 64 KiB
//      bytevector); a 50-deep nested-pair chain stands in for P3's "deep
//      record" shape until a full record-type harness lands. Phase 7 grows
//      this into the full A/B/C/D matrix (arena backing, immediate fast
//      path, immutable side-heap).
//
// Build/run:  zig build bench-channel
//   (best with -Doptimize=ReleaseFast)

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");
const shared_channel = @import("shared_channel.zig");
const Value = types.Value;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn nsPerOp(elapsed_ns: u64, ops: u64) f64 {
    return @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(ops));
}

// Note: VM setup is inlined, not a shared helper -- see bench_fibers.zig's
// identical note (vm_mod.setVMInstance stores the local `vm`'s address in a
// threadlocal; a helper returning `vm` by value would leave that dangling).
fn benchLocalFastPath(iters: u64) !f64 {
    var gc = memory.GC.init(std.heap.c_allocator);
    defer gc.deinit();
    var vm: vm_mod.VM = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    memory.setGCInstance(&gc);
    vm_mod.setVMInstance(&vm);
    try primitives.registerAll(&vm);
    try vm_mod.vm_bootstrap.install(&vm);
    try library.registerStandardLibraries(&vm.libraries, vm.globals);

    var buf: [256]u8 = undefined;
    const src = try std.fmt.bufPrint(&buf,
        \\(import (scheme base) (kaappi fibers))
        \\(define ch (make-channel))
        \\(let loop ((i 0)) (when (< i {d}) (channel-send ch i) (channel-receive ch) (loop (+ i 1))))
    , .{iters});

    const start = nowNs();
    _ = try vm.eval(src);
    const elapsed = nowNs() - start;
    return nsPerOp(elapsed, iters);
}

const Workload = struct {
    name: []const u8,
    iters: u64,
    build: *const fn (gc: *memory.GC) anyerror!Value,
};

fn buildFixnum(_: *memory.GC) anyerror!Value {
    return types.makeFixnum(42);
}

fn buildSmallPair(gc: *memory.GC) anyerror!Value {
    return gc.allocPair(types.makeFixnum(1), types.makeFixnum(2));
}

fn buildString1KiB(gc: *memory.GC) anyerror!Value {
    var data: [1024]u8 = undefined;
    @memset(&data, 'x');
    return gc.allocString(&data);
}

fn buildBytevector64KiB(gc: *memory.GC) anyerror!Value {
    var data: [64 * 1024]u8 = undefined;
    @memset(&data, 0xAB);
    return gc.allocBytevector(&data);
}

/// Stand-in for P3's "deep record" shape: a 50-deep nested-pair chain.
fn buildDeepChain(gc: *memory.GC) anyerror!Value {
    var v: Value = types.NIL;
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        var root = v;
        gc.pushRoot(&root);
        v = try gc.allocPair(types.makeFixnum(i), root);
        gc.popRoot();
    }
    return v;
}

const workloads = [_]Workload{
    .{ .name = "fixnum", .iters = 20_000, .build = buildFixnum },
    .{ .name = "small pair", .iters = 20_000, .build = buildSmallPair },
    .{ .name = "1 KiB string", .iters = 20_000, .build = buildString1KiB },
    .{ .name = "64 KiB bytevector", .iters = 2_000, .build = buildBytevector64KiB },
    .{ .name = "50-deep chain", .iters = 20_000, .build = buildDeepChain },
};

/// Promoted-channel send+receive, single OS thread (no cross-thread wakeup
/// exists until Phase 3) -- measures envelope build/copy-in + copy-out cost
/// in isolation, bypassing the VM entirely.
fn benchPromotedPath(workload: Workload, iters: u64) !f64 {
    const sc = try shared_channel.SharedChannel.create();
    defer sc.release();

    var src_gc = memory.GC.init(std.heap.c_allocator);
    defer src_gc.deinit();
    var dest_gc = memory.GC.init(std.heap.c_allocator);
    defer dest_gc.deinit();

    const payload = try workload.build(&src_gc);

    const start = nowNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        _ = try shared_channel.send(sc, payload, null);
        _ = try shared_channel.receive(sc, &dest_gc, null);
    }
    const elapsed = nowNs() - start;
    return nsPerOp(elapsed, iters);
}

pub fn main() !void {
    std.debug.print("=== KEP-0002 Phase 1: channel benchmarks ===\n\n", .{});

    const local_iters: u64 = 200_000;
    const local_ns = try benchLocalFastPath(local_iters);
    std.debug.print("local (unpromoted) send+receive: {d:.1} ns/op over {d} iters\n\n", .{ local_ns, local_iters });

    std.debug.print("promoted (single-thread) send+receive, by payload shape:\n", .{});
    for (workloads) |wl| {
        const ns = try benchPromotedPath(wl, wl.iters);
        std.debug.print("  {s:<20} {d:>10.1} ns/op over {d} iters\n", .{ wl.name, ns, wl.iters });
    }
}
