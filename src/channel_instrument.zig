//! KEP-0002 Phase 7 gate-campaign instrumentation (kaappi#1472).
//!
//! The frozen protocol (keps `research/benchmarks/README.md`) gates the
//! KEP-0003 acceptance decision on the *copy + reassembly overhead share* of a
//! `parallel-map` section:
//!
//!     share = (T_submit_copy + T_result_copy + T_reassembly) / E
//!
//! This module owns the three parent-side counters and the runtime-selectable
//! envelope elision lever (`none` / `C` / `C+D`) that the campaign sweeps.
//!
//! Two design rules from the protocol are baked in here:
//!
//!   * §3 "the counters ... are compiled out in release builds": the whole
//!     module is a comptime no-op unless built with `-Dchannel-instrument=true`.
//!     `enabled` is `false` in the shipped default and on WASM, and every hook
//!     that touches a wall clock is unreferenced in that case, so the libc
//!     `clock_gettime` never even compiles into a non-instrumented binary.
//!
//!   * §4.4 "one binary: all levers and modes selected by runtime flag, not
//!     rebuild": the lever is a process-global read on every envelope build, set
//!     once (from Scheme, via `%elision-lever-set!`) before a measured section.
//!     The campaign builds a single instrumented binary and compares cells that
//!     differ only in this runtime flag, so code layout is held constant.
//!
//! Attribution (§3): the copy counters are **per-thread**. `T_submit_copy` and
//! `T_result_copy` are the parent's own envelope build (`Envelope.create`) and
//! drain (receive-side `deepCopy`); a worker's build/drain of the *opposite*
//! ends lands in that worker's own threadlocal, which nothing ever reads. Since
//! the parent only ever sends tasks and receives results, every `Envelope.create`
//! it runs is a submit copy and every receive `deepCopy` it runs is a result
//! copy -- no per-call role tagging is needed, only the thread separation the
//! threadlocals give for free.

const std = @import("std");
const build_options = @import("build_options");

/// Compiled in only with `-Dchannel-instrument=true`. Everything below is a
/// comptime no-op otherwise (protocol §3).
pub const enabled: bool = build_options.channel_instrument;

// --------------------------------------------------------------------------
// Parent-side copy-time counters (protocol §3). Per-thread; the parent reads
// its own after a measured section (see `%chan-instr-*` in
// primitives_parallel.zig).
// --------------------------------------------------------------------------
pub threadlocal var t_submit_ns: u64 = 0;
pub threadlocal var t_result_ns: u64 = 0;
pub threadlocal var t_reassembly_ns: u64 = 0;

/// Stashed start for the two-call reassembly bracket (`%chan-instr-reassembly-
/// begin!` / `-end!`). The harness wraps each parent-side `bytevector-copy!` /
/// `vector-copy!` into the output object; worker threads never call the bracket.
threadlocal var reassembly_start: u64 = 0;

/// A live timer handle. `void` when disabled so `begin()` compiles to nothing
/// and the wall-clock read is unreferenced (keeps `clock_gettime` out of the
/// shipped/WASM binary).
pub const Timer = if (enabled) u64 else void;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

/// Start a copy timer. Returns `{}` (and reads no clock) when disabled.
pub inline fn begin() Timer {
    if (comptime !enabled) return {};
    return nowNs();
}

pub inline fn endSubmit(t: Timer) void {
    if (comptime !enabled) return;
    t_submit_ns += nowNs() -% t;
}

pub inline fn endResult(t: Timer) void {
    if (comptime !enabled) return;
    t_result_ns += nowNs() -% t;
}

pub fn reassemblyBegin() void {
    if (comptime !enabled) return;
    reassembly_start = nowNs();
}

pub fn reassemblyEnd() void {
    if (comptime !enabled) return;
    t_reassembly_ns += nowNs() -% reassembly_start;
}

/// Zero this thread's copy counters and the process-wide peak-envelope gauge.
/// Called by the harness right before the timed parallel section.
pub fn reset() void {
    if (comptime !enabled) return;
    t_submit_ns = 0;
    t_result_ns = 0;
    t_reassembly_ns = 0;
    peak_envelope_bytes.store(live_envelope_bytes.load(.monotonic), .monotonic);
}

// --------------------------------------------------------------------------
// Elision lever (protocol §2). Process-global: workers build result envelopes
// and drain task envelopes, so every thread must agree on the active lever for
// a cell. Set once before the measured section; a plain relaxed atomic suffices
// (no ordering is piggybacked on it).
// --------------------------------------------------------------------------
pub const Lever = enum(u8) {
    /// Per-message envelopes exactly as `shared_channel.zig` ships.
    none = 0,
    /// `none` + immediates (fixnums/booleans/chars/flonums/nil) skip the
    /// envelope heap entirely.
    c = 1,
    /// `C` + a refcounted immutable side-heap for large bytevectors/strings
    /// (implemented in a follow-up; selects like `C` until then).
    cd = 2,
};

var active_lever: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(Lever.none));

pub fn setLever(l: Lever) void {
    if (comptime !enabled) return;
    active_lever.store(@intFromEnum(l), .monotonic);
}

pub inline fn lever() Lever {
    if (comptime !enabled) return .none;
    return @enumFromInt(active_lever.load(.monotonic));
}

/// True when the active lever elides immediates from the envelope heap
/// (levers `C` and `C+D`).
pub inline fn immediatesElided() bool {
    if (comptime !enabled) return false;
    return switch (lever()) {
        .none => false,
        .c, .cd => true,
    };
}

// --------------------------------------------------------------------------
// Peak live envelope bytes (protocol §3 secondary metric: the "invisible to
// GC" footprint from KEP-0002's Drawbacks). Process-global, since envelopes are
// created and destroyed across every thread. Non-gating; reported for context.
// --------------------------------------------------------------------------
var live_envelope_bytes: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var peak_envelope_bytes: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

pub fn envelopeBytesAdd(n: usize) void {
    if (comptime !enabled) return;
    const now = live_envelope_bytes.fetchAdd(n, .monotonic) + n;
    // Monotone-max update; a lost race only under-reports the peak slightly,
    // which is acceptable for a non-gating secondary metric.
    var prev = peak_envelope_bytes.load(.monotonic);
    while (now > prev) {
        prev = peak_envelope_bytes.cmpxchgWeak(prev, now, .monotonic, .monotonic) orelse break;
    }
}

pub fn envelopeBytesSub(n: usize) void {
    if (comptime !enabled) return;
    _ = live_envelope_bytes.fetchSub(n, .monotonic);
}

pub fn peakEnvelopeBytes() usize {
    if (comptime !enabled) return 0;
    return peak_envelope_bytes.load(.monotonic);
}
