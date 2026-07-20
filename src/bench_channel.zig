// KEP-0002 channel benchmark. Three measurements, no automated pass/fail
// threshold -- run before/after and compare by eye, matching
// bench_fibers.zig/bench_reactor.zig:
//
//   1. Local (unpromoted) channel send+receive ns/op -- the invariant-3
//      fast-path regression gate ("An unpromoted channel is today's
//      head/tail pair queue plus one pointer null-check ... 'Unmeasurable'
//      is a Phase 1 benchmark gate, not an assumption"). Runs through a
//      real VM/eval so the measurement includes the actual dispatch path
//      (the foreign-owner check and ch.shared null-check included).
//   2. The P3 envelope-cost A/B/C/D matrix (research/open-problems.md P3;
//      research/benchmarks/README.md §7). Grown here from the Phase 1
//      single-lever harness into the four elision levers the Phase 7
//      decision is registered against:
//        (A) per-message GC struct, exactly as src/shared_channel.zig ships;
//        (B) a reusable per-channel arena behind the same envelope interface;
//        (C) A plus the immediate fast path -- non-pointer values (fixnums,
//            booleans, chars) skip the envelope heap entirely;
//        (D) C plus a refcounted immutable side-heap for large bytevectors/
//            strings -- one snapshot copy at creation, zero-copy on receive.
//      Reported per lever x P3 payload shape: ns/message, allocations/message
//      (counted alloc calls), and message heap-object count.
//   3. A reference line: the *real* promoted send+receive through
//      shared_channel (lever A, full lock + queue), so the matrix's lever-A
//      column can be tied back to the shipped path and the Phase 1 numbers.
//
// The pre-registered P3 criteria (open-problems.md P3) are evaluated
// mechanically at the end: (C) ships if immediates are >= 2x (A) on fixnums;
// (B) replaces (A) only if it wins >= 30% on the small-message workloads.
// (D)'s *shipping* decision is deferred to the KEP-0003 gate (kaappi#1474);
// here it is only measured.
//
// Scope note: this is the single-thread envelope-cost micro-benchmark. The
// per-message ns figures deliberately exclude the (lever-invariant) O(1)
// queue push/pop and spin-lock pair -- measurement 3 keeps a real-path line
// so that constant stays visible. The symbol-table lock-contention figure
// (many threads, symbol-heavy records) and the parallel-map scaling curve
// that feeds the gate are separate Phase 7 tasks, not part of this file.
//
// Build/run:  zig build bench-channel
//   (best with -Doptimize=ReleaseFast)

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const memory = @import("memory.zig");
const gc_collect = @import("gc_collect.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");
const shared_channel = @import("shared_channel.zig");
const shared_object = @import("shared_object.zig");
const Value = types.Value;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn nsPerOp(elapsed_ns: u64, ops: u64) f64 {
    return @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(ops));
}

// --------------------------------------------------------------------------
// Counting allocator: wraps a backing allocator and tallies alloc() calls, so
// the matrix can report a true allocations/message figure. This is what makes
// the A-vs-B difference legible in the alloc column -- both deepCopy the same
// object graph, but A allocates a fresh GC struct + its ~8 KiB root buffer per
// message while B amortizes them across the channel's lifetime.
// --------------------------------------------------------------------------
const CountingAllocator = struct {
    backing: std.mem.Allocator,
    allocs: usize = 0,

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = countAlloc,
        .resize = countResize,
        .remap = countRemap,
        .free = countFree,
    };

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn countAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.allocs += 1;
        return self.backing.vtable.alloc(self.backing.ptr, len, alignment, ret_addr);
    }
    fn countResize(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.vtable.resize(self.backing.ptr, mem, alignment, new_len, ret_addr);
    }
    fn countRemap(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.vtable.remap(self.backing.ptr, mem, alignment, new_len, ret_addr);
    }
    fn countFree(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.backing.vtable.free(self.backing.ptr, mem, alignment, ret_addr);
    }
};

// --------------------------------------------------------------------------
// Lever B support: free a message graph while keeping the GC's own buffers, so
// one arena GC can back message after message. This is the whole of B's
// "reusable per-channel arena" -- the arena's bookkeeping (root buffer, symbol
// table, object-list head) is retained; only the copied-in message objects are
// released. Precondition: the message graph holds no interned symbols (all
// five P3 workloads are symbol-free), so the symbol table stays empty and no
// freed Symbol can dangle behind a live table entry. A symbol-bearing arena
// would additionally need the symbol table preserved across resets -- out of
// scope for this micro-benchmark (it belongs with the symbol-contention task).
fn freeArena(gc: *memory.GC) void {
    var obj = gc.objects;
    while (obj) |o| {
        const next = o.next;
        gc_collect.freeObject(gc, o);
        obj = next;
    }
    obj = gc.old_objects;
    while (obj) |o| {
        const next = o.next;
        gc_collect.freeObject(gc, o);
        obj = next;
    }
    gc.objects = null;
    gc.old_objects = null;
    gc.object_count = 0;
    gc.bytes_allocated = 0;
    // In gc-stress builds freeObject quarantines each slot (#1687); this
    // arena GC never collects, so nothing else would ever release them.
    gc.quarantineDrain();
}

// --------------------------------------------------------------------------
// Lever D support: a refcounted immutable side-heap buffer, allocated outside
// every GC heap on the same shared_object protocol SharedChannel uses. The
// payload bytes are snapshotted once at creation; crossing the channel is then
// a refcount bump, not a copy. In a 1:1 round trip that halves the byte-copy
// count (create-copy only, vs. copy-in + copy-out for A/C); the larger win --
// one copy shared across an N-worker fan-out instead of N copies -- is what
// the KEP-0003 gate campaign measures, and why D's shipping decision lives
// there, not here.
const SideBuf = struct {
    header: shared_object.Header,
    bytes: []u8,
    alloc: std.mem.Allocator,

    fn destroyHook(h: *shared_object.Header) void {
        const self: *SideBuf = @fieldParentPtr("header", h);
        const a = self.alloc;
        a.free(self.bytes);
        a.destroy(self);
    }

    fn create(a: std.mem.Allocator, src: []const u8) !*SideBuf {
        const self = try a.create(SideBuf);
        errdefer a.destroy(self);
        const buf = try a.alloc(u8, src.len);
        @memcpy(buf, src); // the one snapshot copy into the immutable side-heap
        self.* = .{ .header = undefined, .bytes = buf, .alloc = a };
        shared_object.init(&self.header, destroyHook); // refcount 1: sender's stub
        return self;
    }
};

// --------------------------------------------------------------------------
// The four levers and the envelope strategies they select.
// --------------------------------------------------------------------------
const Lever = enum { a, b, c, d };

fn leverName(l: Lever) []const u8 {
    return switch (l) {
        .a => "A",
        .b => "B",
        .c => "C",
        .d => "D",
    };
}

/// Bytes-backed payload (bytevector or string), for lever D's size gate.
/// Returns null for every other shape.
fn payloadBytes(v: Value) ?[]const u8 {
    if (!types.isPointer(v)) return null;
    const o = types.toObject(v);
    return switch (o.tag) {
        .bytevector => o.as(types.Bytevector).data,
        .string => o.as(types.SchemeString).data,
        else => null,
    };
}

/// BEAM ships refcounted binaries above 64 bytes; the gate campaign sweeps
/// 64 KiB..64 MiB where D dominates. In this micro-matrix an 8 KiB gate keeps
/// D distinct from C on exactly the 64 KiB-bytevector cell (the 1 KiB string
/// stays on the copy path), which is the contrast the matrix exists to show.
const d_side_heap_threshold_bytes: usize = 8192;

const BenchEnv = union(enum) {
    heap: struct { gc: *memory.GC, owns_gc: bool, value: Value },
    immediate: Value,
    side: *SideBuf,
};

const LeverCtx = struct {
    alloc: std.mem.Allocator,
    arena_gc: ?*memory.GC, // lever B's persistent per-channel arena
};

/// Send side: build the message representation this lever prescribes.
fn buildEnv(lever: Lever, payload: Value, ctx: *LeverCtx) !BenchEnv {
    // Lever C/D immediate fast path: any non-pointer NaN-boxed value (fixnum,
    // boolean, char, nil, flonum) is self-contained -- deepCopy would return
    // it unchanged -- so it skips the envelope heap entirely.
    if ((lever == .c or lever == .d) and !types.isPointer(payload)) {
        return .{ .immediate = payload };
    }
    // Lever D side-heap: large immutable bytes cross by refcounted reference.
    if (lever == .d) {
        if (payloadBytes(payload)) |bytes| {
            if (bytes.len >= d_side_heap_threshold_bytes) {
                return .{ .side = try SideBuf.create(ctx.alloc, bytes) };
            }
        }
    }
    // Levers A/B, and the fall-through of C/D: a message heap + deepCopy in.
    if (lever == .b) {
        const g = ctx.arena_gc.?;
        const v = try g.deepCopy(payload);
        return .{ .heap = .{ .gc = g, .owns_gc = false, .value = v } };
    }
    const g = try ctx.alloc.create(memory.GC);
    errdefer ctx.alloc.destroy(g);
    g.* = memory.GC.init(ctx.alloc);
    g.enabled = false; // never collect a heap no root marker can see (as Envelope.create)
    const v = try g.deepCopy(payload);
    return .{ .heap = .{ .gc = g, .owns_gc = true, .value = v } };
}

/// Receive side: copy/reference the value out into `dest_gc`, then tear the
/// message representation down (freeing an owned GC, resetting a lever-B
/// arena, or dropping the side-heap refcounts).
fn consumeEnv(env: BenchEnv, dest_gc: *memory.GC, ctx: *LeverCtx) !void {
    switch (env) {
        .immediate => {
            // deepCopy of a non-pointer is identity: nothing to copy out.
        },
        .side => |sb| {
            shared_object.retain(&sb.header); // receiver acquires a reference (no copy)
            shared_object.release(&sb.header); // sender's envelope reference drops
            shared_object.release(&sb.header); // receiver, done with the message, drops its own
        },
        .heap => |h| {
            _ = try dest_gc.deepCopy(h.value); // copy out into the receiver heap
            if (h.owns_gc) {
                h.gc.deinit();
                ctx.alloc.destroy(h.gc);
            } else {
                freeArena(h.gc); // lever B: reset the reusable arena for the next message
            }
        },
    }
}

// --------------------------------------------------------------------------
// P3 workloads: fixnum, small pair, 1 KiB string, 64 KiB bytevector, deep
// record (a 50-deep nested-pair chain stands in for the record shape until a
// full record-type harness lands -- same stand-in the Phase 1 harness used).
// --------------------------------------------------------------------------
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
    .{ .name = "fixnum", .iters = 50_000, .build = buildFixnum },
    .{ .name = "small pair", .iters = 50_000, .build = buildSmallPair },
    .{ .name = "1 KiB string", .iters = 50_000, .build = buildString1KiB },
    .{ .name = "64 KiB bytevector", .iters = 5_000, .build = buildBytevector64KiB },
    .{ .name = "50-deep chain", .iters = 50_000, .build = buildDeepChain },
};

/// The three small-message workloads the P3 (B) criterion is read on -- the
/// shapes where per-message fixed overhead can dominate.
fn isSmallMessage(name: []const u8) bool {
    return std.mem.eql(u8, name, "fixnum") or
        std.mem.eql(u8, name, "small pair") or
        std.mem.eql(u8, name, "1 KiB string");
}

const CellResult = struct {
    ns: f64,
    allocs_per_msg: f64,
    heap_objs: usize,
};

/// One matrix cell: `iters` send+receive round trips for `lever` x `wl`.
fn benchCell(lever: Lever, wl: Workload) !CellResult {
    var src_gc = memory.GC.init(std.heap.c_allocator);
    src_gc.enabled = false;
    defer src_gc.deinit();
    const payload = try wl.build(&src_gc);

    var counter = CountingAllocator{ .backing = std.heap.c_allocator };
    const ca = counter.allocator();

    var dest_gc = memory.GC.init(ca);
    dest_gc.enabled = false;
    defer dest_gc.deinit();

    var arena_storage: memory.GC = undefined;
    var arena_ptr: ?*memory.GC = null;
    if (lever == .b) {
        arena_storage = memory.GC.init(ca);
        arena_storage.enabled = false;
        arena_ptr = &arena_storage;
    }
    defer if (arena_ptr) |g| g.deinit();

    var ctx = LeverCtx{ .alloc = ca, .arena_gc = arena_ptr };

    // Probe the message's heap-object count once, outside the timing loop.
    const probe = try buildEnv(lever, payload, &ctx);
    const heap_objs: usize = switch (probe) {
        .heap => |h| h.gc.object_count,
        else => 0,
    };
    try consumeEnv(probe, &dest_gc, &ctx);
    freeArena(&dest_gc);

    // Warm up so one-time capacity growth (dest heap, arena) doesn't land in
    // the measured allocation tally.
    const warmup = @min(wl.iters / 10, 1000);
    var w: u64 = 0;
    while (w < warmup) : (w += 1) {
        const e = try buildEnv(lever, payload, &ctx);
        try consumeEnv(e, &dest_gc, &ctx);
        freeArena(&dest_gc);
    }

    const allocs_before = counter.allocs;
    const start = nowNs();
    var i: u64 = 0;
    while (i < wl.iters) : (i += 1) {
        const e = try buildEnv(lever, payload, &ctx);
        try consumeEnv(e, &dest_gc, &ctx);
        freeArena(&dest_gc); // free the received value; equal cost across levers
    }
    const elapsed = nowNs() - start;
    const allocs = counter.allocs - allocs_before;

    return .{
        .ns = nsPerOp(elapsed, wl.iters),
        .allocs_per_msg = @as(f64, @floatFromInt(allocs)) / @as(f64, @floatFromInt(wl.iters)),
        .heap_objs = heap_objs,
    };
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

/// Reference line: real promoted send+receive through shared_channel (lever A,
/// full spin-lock + queue), so the matrix's lever-A column can be tied back to
/// the shipped path. Uses the real Envelope.create, not the matrix builders.
fn benchRealPromoted(workload: Workload, iters: u64) !f64 {
    const sc = try shared_channel.SharedChannel.create();
    defer sc.release();

    var src_gc = memory.GC.init(std.heap.c_allocator);
    src_gc.enabled = false; // keep the payload alive; never collect it
    defer src_gc.deinit();
    var dest_gc = memory.GC.init(std.heap.c_allocator);
    dest_gc.enabled = false;
    defer dest_gc.deinit();

    const payload = try workload.build(&src_gc);

    const start = nowNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        _ = try shared_channel.send(sc, payload, null);
        _ = try shared_channel.receive(sc, &dest_gc, null, false);
        freeArena(&dest_gc); // bound the receiver heap, matching the matrix harness
    }
    const elapsed = nowNs() - start;
    return nsPerOp(elapsed, iters);
}

pub fn main() !void {
    std.debug.print("=== KEP-0002 channel benchmarks ===\n", .{});
    // The P3 (B) decision is build-mode sensitive: safety checks make lever
    // A's per-message GC-struct + root-buffer alloc/free relatively costlier,
    // so B's amortization wins more under ReleaseSafe than ReleaseFast. The
    // protocol's shipped default (research/benchmarks/README.md §4.5) is
    // ReleaseSafe, so that is the operative build for the ship decision.
    std.debug.print("build: {s} (shipped default is ReleaseSafe; decision reads this build)\n\n", .{@tagName(builtin.mode)});

    const local_iters: u64 = 200_000;
    const local_ns = try benchLocalFastPath(local_iters);
    std.debug.print("1. local (unpromoted) send+receive: {d:.1} ns/op over {d} iters\n\n", .{ local_ns, local_iters });

    // Run the whole matrix up front so the decision summary can read it.
    const levers = [_]Lever{ .a, .b, .c, .d };
    var results: [workloads.len][levers.len]CellResult = undefined;
    for (workloads, 0..) |wl, wi| {
        for (levers, 0..) |lever, li| {
            results[wi][li] = try benchCell(lever, wl);
        }
    }

    std.debug.print("2. P3 envelope-cost matrix (build + copy-out round trip), single thread.\n\n", .{});

    std.debug.print("   ns/op by lever:\n", .{});
    std.debug.print("   {s:<20}{s:>11}{s:>11}{s:>11}{s:>11}\n", .{ "payload shape", "A", "B", "C", "D" });
    for (workloads, 0..) |wl, wi| {
        std.debug.print("   {s:<20}{d:>11.1}{d:>11.1}{d:>11.1}{d:>11.1}\n", .{
            wl.name,
            results[wi][0].ns,
            results[wi][1].ns,
            results[wi][2].ns,
            results[wi][3].ns,
        });
    }

    std.debug.print("\n   allocations/message by lever (counted alloc calls):\n", .{});
    std.debug.print("   {s:<20}{s:>11}{s:>11}{s:>11}{s:>11}\n", .{ "payload shape", "A", "B", "C", "D" });
    for (workloads, 0..) |wl, wi| {
        std.debug.print("   {s:<20}{d:>11.2}{d:>11.2}{d:>11.2}{d:>11.2}\n", .{
            wl.name,
            results[wi][0].allocs_per_msg,
            results[wi][1].allocs_per_msg,
            results[wi][2].allocs_per_msg,
            results[wi][3].allocs_per_msg,
        });
    }

    std.debug.print("\n   message heap objects (deepCopy graph size, lever A):\n", .{});
    for (workloads, 0..) |wl, wi| {
        std.debug.print("   {s:<20}{d:>6}\n", .{ wl.name, results[wi][0].heap_objs });
    }

    std.debug.print("\n3. reference: real promoted send+receive (shared_channel, lever A, full lock+queue):\n", .{});
    for (workloads) |wl| {
        const ns = try benchRealPromoted(wl, wl.iters);
        std.debug.print("   {s:<20}{d:>11.1} ns/op\n", .{ wl.name, ns });
    }

    // ----------------------------------------------------------------------
    // Mechanical evaluation of the pre-registered P3 criteria.
    // ----------------------------------------------------------------------
    std.debug.print("\n=== P3 decision (open-problems.md P3, pre-registered) ===\n\n", .{});

    // (C) ships if immediates are >= 2x (A) on fixnums.
    const a_fixnum = results[0][0].ns; // workloads[0] == fixnum, levers[0] == A
    const c_fixnum = results[0][2].ns; // levers[2] == C
    const c_speedup = a_fixnum / c_fixnum;
    std.debug.print("(C) immediate fast path: fixnum A={d:.1} ns, C={d:.1} ns -> {d:.1}x\n", .{ a_fixnum, c_fixnum, c_speedup });
    std.debug.print("    criterion: C ships iff immediates >= 2x A on fixnums -> {s}\n\n", .{
        if (c_speedup >= 2.0) "SHIP C" else "hold",
    });

    // (B) replaces (A) only if it wins >= 30% on the small-message workloads.
    std.debug.print("(B) reusable arena vs. A, improvement = (A-B)/A:\n", .{});
    var b_all_small_win = true;
    var b_any_small = false;
    for (workloads, 0..) |wl, wi| {
        const a_ns = results[wi][0].ns;
        const b_ns = results[wi][1].ns;
        const impr = (a_ns - b_ns) / a_ns * 100.0;
        const small = isSmallMessage(wl.name);
        std.debug.print("    {s:<20} {d:>6.1}%{s}\n", .{
            wl.name,
            impr,
            if (small) "   (small-message: gates the B decision)" else "",
        });
        if (small) {
            b_any_small = true;
            if (impr < 30.0) b_all_small_win = false;
        }
    }
    std.debug.print("    criterion: B replaces A iff >= 30% on ALL small-message workloads\n", .{});
    std.debug.print("               (and no new lifetime rules leak outside shared_channel.zig) -> {s}\n\n", .{
        if (b_any_small and b_all_small_win) "REPLACE A with B (pending leak/gc-stress review)" else "keep A",
    });

    // (D) measured only; shipping decision belongs to the KEP-0003 gate.
    const a_bv = results[3][0].ns; // workloads[3] == 64 KiB bytevector
    const d_bv = results[3][3].ns; // levers[3] == D
    const d_speedup = a_bv / d_bv;
    std.debug.print("(D) side-heap (64 KiB bytevector): A={d:.1} ns, D={d:.1} ns -> {d:.1}x\n", .{ a_bv, d_bv, d_speedup });
    std.debug.print("    measured only; D's shipping decision is the KEP-0003 gate (kaappi#1474).\n", .{});
}
