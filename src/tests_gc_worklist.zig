//! Mark-worklist memory behavior (#2464).
//!
//! Two properties of `gc.mark_worklist` that the reachability switches in
//! tests_gc_tracing.zig say nothing about, both load-bearing for peak RSS:
//!
//!   * **Immediates are never pushed.** The drain's `markValueInner` returns
//!     at its `isPointer` check, so an immediate on the worklist is popped
//!     and discarded — pushing one is pure transient growth. Before #2464 a
//!     wide container of immediates (the array-copy scratch vector of
//!     fixnums from the issue) peaked the worklist at the container's full
//!     width every full collection.
//!   * **The buffer is retained below the 1M-entry floor.** Releasing it
//!     after every collection made each full mark regrow through the same
//!     realloc chain, and the backing libc malloc does not decommit those
//!     freed large blocks — peak RSS accumulated ~10 MB of resident-dirty
//!     pages per full collection (~65x the live heap) until the program
//!     ended. The old 64K-entry floor cleared exactly the buffers that
//!     churned.
//!
//! Both are asserted through `mark_worklist.capacity`, which persists across
//! collections (see also the older "mark worklist retains capacity across
//! collections" test in memory.zig — that one pins capacity *persistence*,
//! these pin what may grow it and when it is released).

const std = @import("std");
const memory = @import("memory.zig");
const types = @import("types.zig");
const build_options = @import("build_options");

// Sizes chosen against the pre-fix release floor (64K entries), so each
// test's discriminating assertion actually observes the retained buffer:
// 40k pushes grew capacity to ~52k — *under* the old floor, hence retained
// and visible; 70k grew past it, so the old code cleared the buffer to zero
// after every collection. Under gc-stress the collection-per-allocation
// makes the 70k-pair build quadratic, so only that one test skips; the
// other two run there too (the immediate-only case is a single allocation,
// and the pointer-elements case allocates with `enabled = false`, so its
// 1000 allocPairs never collect).
const immediate_len = 40_000;
const wide_len = 70_000;

test "#2464: a wide vector of immediates never grows the mark worklist" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var vec = try gc.allocVectorFill(immediate_len, types.makeFixnum(7));
    gc.pushRoot(&vec);
    defer gc.popRoot();

    gc.collect();
    // Pre-fix: every element was pushed (all but the tail-iterated last,
    // which still grew capacity to ~52k — under the old 64K floor, so
    // retained). Post-fix: no push happens at all, so the threshold has
    // generous margin.
    try std.testing.expect(gc.mark_worklist.capacity <= 4096);
    // The container itself must still be live and intact.
    try std.testing.expect(types.isVector(vec));
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(types.toVector(vec).data[0]));
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(types.toVector(vec).data[immediate_len - 1]));
}

test "#2464: pointer elements still reach the worklist and stay live" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    // Alternating pair/fixnum: only the pairs may be pushed, and they are
    // reachable ONLY through the vector, so survival double-checks that the
    // skip-immediates change never widened into skipping pointers.
    const n = 1000;
    var items: [n]types.Value = undefined;
    for (&items, 0..) |*slot, i| {
        if (i % 2 == 0) {
            slot.* = try gc.allocPair(types.makeFixnum(@intCast(i)), types.NIL);
        } else {
            slot.* = types.makeFixnum(@intCast(i));
        }
    }
    var vec = try gc.allocVector(&items);
    gc.pushRoot(&vec);
    defer gc.popRoot();

    gc.collect();

    for (0..n) |i| {
        if (i % 2 != 0) continue;
        const pair = types.toVector(vec).data[i];
        try std.testing.expect(types.isPair(pair));
        try std.testing.expectEqual(@as(i64, @intCast(i)), types.toFixnum(types.car(pair)));
    }
}

test "#2464: the worklist buffer is retained below the 1M-entry floor" {
    if (comptime build_options.gc_stress) return error.SkipZigTest;
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    // wide_len pair-referents: the vector arm pushes every element except
    // the last (that one is iterated directly), landing above the old 64K
    // floor (which freed the whole buffer) and far below the new 1M floor.
    const n = wide_len;
    var items: [n]types.Value = undefined;
    for (&items, 0..) |*slot, i| {
        slot.* = try gc.allocPair(types.makeFixnum(@intCast(i)), types.NIL);
    }
    var vec = try gc.allocVector(&items);
    gc.pushRoot(&vec);
    defer gc.popRoot();

    gc.collect();
    // n-1 is what the mark path guarantees; capacity today exceeds it by
    // the ~50% growth slack, but the guarantee is the bound to pin.
    try std.testing.expect(gc.mark_worklist.capacity >= n - 1);
    // And a second collection keeps it — no regrowth from zero, which is
    // the churn that left the freed realloc tops resident-dirty.
    const cap_after_first = gc.mark_worklist.capacity;
    gc.collect();
    try std.testing.expectEqual(cap_after_first, gc.mark_worklist.capacity);
}

test "#2464: an over-floor frontier re-reserves exactly the floor" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    // Hardcoded against markValue's max_retained, deliberately: this is
    // the pin for the over-floor branch (clearAndFree + re-reserve), so a
    // future edit that drops the re-reserve — or moves the floor — must
    // fail here, not pass silently.
    const floor = 1024 * 1024;
    var pair = try gc.allocPair(types.makeFixnum(1), types.NIL);
    gc.pushRoot(&pair);
    defer gc.popRoot();
    // One pair, referenced floor+64 times: the vector arm pushes every slot
    // before the drain pops any, so the worklist peaks above the floor with
    // a single heap object behind it.
    var vec = try gc.allocVectorFill(floor + 64, pair);
    gc.pushRoot(&vec);
    defer gc.popRoot();

    gc.collect();
    try std.testing.expectEqual(@as(usize, floor), gc.mark_worklist.capacity);
    gc.collect();
    try std.testing.expectEqual(@as(usize, floor), gc.mark_worklist.capacity);
    try std.testing.expect(types.isPair(types.toVector(vec).data[floor]));
}
