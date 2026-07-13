//! KEP-0002 Phase 3 (#1468): PCT-style randomized scheduling stress helper
//! for shared_object.zig/shared_channel.zig's lock/atomic operations
//! (KEP-0002 research plan, P2 method step 2 -- "seed-controlled yield
//! injection at every lock acquire/release and atomic op ... seed printed
//! on failure for deterministic replay", modeled on Burckhardt et al.'s PCT
//! (ASPLOS 2010) and tokio-rs/loom's "model checking as a unit test"
//! ergonomics).
//!
//! Runtime-gated (not comptime), off by default: `enabled` starts false, so
//! `zig build test`'s ordinary run pays no cost and sees no behavior
//! change -- `maybeYield()` is a single branch that returns immediately
//! unless a stress harness (src/stress_channel.zig) has explicitly turned
//! it on. This deliberately does not touch memory.zig's spinLock/spinUnlock
//! themselves (used throughout the codebase for unrelated locks); the yield
//! points are wired in only at shared_channel.zig's own lock wrappers and
//! shared_object.zig's retain/release, so the coupling stays local to
//! KEP-0002.
const std = @import("std");

pub var enabled: bool = false;

threadlocal var rng: ?std.Random.DefaultPrng = null;

/// Seeds this OS thread's own PRNG deterministically from the harness's
/// single top-level seed plus a thread-distinguishing tag, so an entire
/// multi-thread run replays exactly from one printed seed (CHESS's
/// reproducibility discipline). Call once per thread before it starts
/// hammering shared_channel.zig/shared_object.zig.
pub fn seedThread(base_seed: u64, thread_tag: u64) void {
    rng = std.Random.DefaultPrng.init(base_seed ^ (thread_tag *% 0x9E3779B97F4A7C15));
}

/// Called at curated lock-acquire/release and atomic-op points. A no-op
/// unless `enabled` and this thread has been seeded. PCT randomizes context
/// switches at exactly these points rather than everywhere -- far more
/// effective at surfacing real interleaving bugs than naive, uncontrolled
/// thread scheduling (the point of the technique, not an approximation of
/// it).
pub fn maybeYield() void {
    if (!enabled) return;
    var r = rng orelse return; // an un-seeded thread (e.g. the main test thread) opts out
    defer rng = r;
    if (r.random().boolean()) std.Thread.yield() catch {};
}
