//! `--timings`: per-stage pipeline wall time + cache HIT/MISS visibility
//! (kaappi#1515, part of the machine-legibility epic kaappi#1503).
//!
//! `--profile` profiles the *user's program*; nothing else reports how long
//! kaappi's own pipeline stages take, or whether a run was served from the
//! `.sbc` bytecode cache (kaappi#1516). This module gives `zig build`-style
//! transparency for kaappi's own work — for humans chasing slow builds, and
//! for CI to catch compiler-performance regressions (`--timings=json`).
//!
//! **Model — a self-time profiler stack.** The pipeline is not a flat sequence:
//! macro expansion is interleaved with emission (a macro use becomes a
//! passthrough IR node that is expanded, then *re-compiled*, during
//! `compileFromNode`), so `emit` legitimately contains nested `expand`, `lower`,
//! `optimize`, and further `emit`. A single accumulator per stage would
//! double-count those nested regions. Instead, every timed region is pushed on
//! a stack; wall time is always credited to the *innermost* active stage, so the
//! buckets are disjoint (they never overlap) regardless of nesting or which
//! caller drives them (run / `--compile` / native / imports). Each begin/end is
//! one `clock_gettime`; when the flag is absent every entry point is a single
//! predicted branch (`if (!enabled) return`), so there is no measurable overhead.
//!
//! **Threading.** `enabled` is `threadlocal` (like `ir.optimize_enabled`): only
//! the main thread — the one that parsed the CLI and drives the top-level
//! pipeline — ever has it set, so SRFI-18 child threads that compile via `eval`
//! neither race on the shared buckets nor get counted. The whole program's
//! pipeline runs on the main thread, so nothing is lost.
//!
//! Output goes to **stderr** (like `--diagnostics=json`), keeping the program's
//! own stdout clean for piping. See `docs/dev/timings.md`.

const std = @import("std");
const builtin = @import("builtin");

const is_wasm = builtin.os.tag == .wasi;

pub const Format = enum { text, json };

/// The invocation whose stages we are reporting. Selects which stages appear
/// (and in which order) and whether a cache line is shown.
pub const Mode = enum { run, compile, native };

/// Pipeline stages. `read`→`execute` are the interpreter run/`--compile` path;
/// `llvm_emit`/`link` are the extra native-backend stages under `kaappi compile`
/// (which has no `execute`). Kept in one enum so a single bucket array indexes
/// all of them.
pub const Stage = enum { read, expand, lower, optimize, emit, llvm_emit, link, execute };

const stage_count = @typeInfo(Stage).@"enum".fields.len;

/// Fixed cap for the copied cache / output paths — comfortably above any real
/// `PATH_MAX`, and platform-independent so this module compiles on WASM too
/// (where timings are never armed anyway).
const max_path = 4096;

// ── State (threadlocal `enabled`; the rest is only ever touched by the main
//    thread, which is the only thread that sets `enabled`) ─────────────────

pub threadlocal var enabled: bool = false;
var format: Format = .text;

/// Nanosecond self-time per stage.
var buckets: [stage_count]u64 = @splat(0);

const Frame = struct { stage: Stage, resumed_ns: u64 };

/// Deep enough for realistic macro-in-macro-output nesting (each level adds
/// ~4 frames: emit→expand, then lower→optimize→emit of the expansion). Beyond
/// this, credit degrades gracefully (frames past the cap aren't recorded) but
/// `depth` still balances so begin/end never corrupt the stack or crash.
var stack: [128]Frame = undefined;
var depth: usize = 0;

// ── Cache outcome (run path) ───────────────────────────────────────────────

pub const CacheOutcome = enum { none, hit, miss, off };

var cache_outcome: CacheOutcome = .none;
var cache_written: bool = false;
/// A static-lifetime reason ("sandbox", "--no-ir-opt", "imports", …) — safe to
/// alias since callers pass string literals.
var cache_reason: []const u8 = "";
var cache_path_buf: [max_path]u8 = undefined;
var cache_path_len: usize = 0;

/// An explicit output artifact path (for `--compile` / native `compile`),
/// copied because the caller's slice is freed before the report runs.
var output_path_buf: [max_path]u8 = undefined;
var output_path_len: usize = 0;

// ── Setup ──────────────────────────────────────────────────────────────────

/// Turn timing on for this (main) thread and reset all accumulators. Called
/// once, right after CLI parsing, only when `--timings` was given.
pub fn enable(fmt: Format) void {
    enabled = true;
    format = fmt;
    buckets = @splat(0);
    depth = 0;
    cache_outcome = .none;
    cache_written = false;
    cache_reason = "";
    cache_path_len = 0;
    output_path_len = 0;
}

// ── Timing primitives ──────────────────────────────────────────────────────

/// Test-only clock override so the self-time accounting can be driven on a
/// deterministic timeline (a real elapsed-wall test is flaky — the optimizer can
/// collapse busy-work to nothing). Gated on `builtin.is_test`, so it compiles out
/// of production builds entirely — no branch on the real hot path.
var test_clock: ?u64 = null;

fn nowNs() u64 {
    if (builtin.is_test) {
        if (test_clock) |t| return t;
    }
    if (comptime is_wasm) return 0;
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

/// Enter `stage`. Credits any elapsed time to the (now-frozen) parent stage,
/// then makes `stage` the innermost active one. Pair every `begin` with an
/// `end`, ideally via `defer`.
pub inline fn begin(stage: Stage) void {
    if (!enabled) return;
    beginSlow(stage);
}

fn beginSlow(stage: Stage) void {
    const now = nowNs();
    if (depth > 0 and depth - 1 < stack.len) {
        const parent = &stack[depth - 1];
        buckets[@intFromEnum(parent.stage)] +%= now -% parent.resumed_ns;
    }
    if (depth < stack.len) stack[depth] = .{ .stage = stage, .resumed_ns = now };
    depth += 1;
}

/// Leave the innermost stage, crediting its remaining self-time, and resume its
/// parent.
pub inline fn end() void {
    if (!enabled) return;
    endSlow();
}

fn endSlow() void {
    if (depth == 0) return;
    depth -= 1;
    const now = nowNs();
    if (depth < stack.len) {
        const cur = &stack[depth];
        buckets[@intFromEnum(cur.stage)] +%= now -% cur.resumed_ns;
    }
    if (depth > 0 and depth - 1 < stack.len) stack[depth - 1].resumed_ns = now;
}

// ── Cache / output recording (run + compile paths) ─────────────────────────

fn copyPath(dst: []u8, path: []const u8) usize {
    const n = @min(dst.len, path.len);
    @memcpy(dst[0..n], path[0..n]);
    return n;
}

/// Bytecode served from the cache — the whole read→compile pipeline was skipped.
pub fn cacheHit(path: []const u8) void {
    if (!enabled) return;
    cache_outcome = .hit;
    cache_path_len = copyPath(&cache_path_buf, path);
}

/// Compiled from source; `path` is where the entry will be (best-effort)
/// written. Call `cacheWrote` if the write succeeds, or `cacheReason` to note
/// why it won't be cached (e.g. imports).
pub fn cacheMiss(path: []const u8) void {
    if (!enabled) return;
    cache_outcome = .miss;
    cache_path_len = copyPath(&cache_path_buf, path);
}

/// Record that the miss's bytecode was actually written to the cache.
pub fn cacheWrote() void {
    if (!enabled) return;
    cache_written = true;
}

/// Caching was not attempted at all (sandbox, `--no-ir-opt`, no home dir, WASM).
/// `reason` must be a static string.
pub fn cacheOff(reason: []const u8) void {
    if (!enabled) return;
    cache_outcome = .off;
    cache_reason = reason;
}

/// Annotate the current outcome (typically a miss) with a static-string reason,
/// e.g. why a compiled program won't be cached.
pub fn cacheReason(reason: []const u8) void {
    if (!enabled) return;
    cache_reason = reason;
}

/// Record the explicit output artifact for `--compile` / native `compile`.
pub fn setOutput(path: []const u8) void {
    if (!enabled) return;
    output_path_len = copyPath(&output_path_buf, path);
}

// ── Reporting ──────────────────────────────────────────────────────────────

const run_stages = [_]Stage{ .read, .expand, .lower, .optimize, .emit, .execute };
const compile_stages = [_]Stage{ .read, .expand, .lower, .optimize, .emit };
const native_stages = [_]Stage{ .read, .lower, .optimize, .llvm_emit, .link };

fn stageName(s: Stage) []const u8 {
    return switch (s) {
        .read => "read",
        .expand => "expand",
        .lower => "lower",
        .optimize => "optimize",
        .emit => "emit",
        .llvm_emit => "llvm-emit",
        .link => "link",
        .execute => "execute",
    };
}

/// JSON keys use `_` (llvm-emit → llvm_emit) so they are valid identifiers.
fn stageKey(s: Stage) []const u8 {
    return switch (s) {
        .llvm_emit => "llvm_emit",
        else => stageName(s),
    };
}

fn ms(stage: Stage) f64 {
    return @as(f64, @floatFromInt(buckets[@intFromEnum(stage)])) / 1_000_000.0;
}

fn stagesFor(mode: Mode) []const Stage {
    return switch (mode) {
        .run => &run_stages,
        .compile => &compile_stages,
        .native => &native_stages,
    };
}

/// Emit the timing report to stderr. Safe to call unconditionally — a no-op
/// unless `--timings` enabled this thread.
pub fn report(mode: Mode) void {
    if (!enabled) return;
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    switch (format) {
        .text => renderText(&w, mode),
        .json => renderJson(&w, mode),
    }
    writeStderr(w.buffered());
}

fn renderText(w: *std.Io.Writer, mode: Mode) void {
    // On a cache hit the read→emit stages never ran; show only what did.
    const only_execute = mode == .run and cache_outcome == .hit;
    const stages: []const Stage = if (only_execute) &.{.execute} else stagesFor(mode);

    w.writeAll("timings:") catch {};
    for (stages, 0..) |s, i| {
        w.print("{s} {s} {d:.1}ms", .{ if (i == 0) "" else " |", stageName(s), ms(s) }) catch {};
    }
    w.writeByte('\n') catch {};

    switch (mode) {
        .run => renderCacheLine(w),
        .compile, .native => if (output_path_len > 0) {
            w.print("output: {s}\n", .{output_path_buf[0..output_path_len]}) catch {};
        },
    }
}

fn renderCacheLine(w: *std.Io.Writer) void {
    const path = cache_path_buf[0..cache_path_len];
    switch (cache_outcome) {
        .hit => w.print("cache: HIT ({s})\n", .{path}) catch {},
        .miss => {
            if (cache_written) {
                w.print("cache: MISS (wrote {s})\n", .{path}) catch {};
            } else if (cache_reason.len > 0) {
                w.print("cache: MISS (not cached: {s})\n", .{cache_reason}) catch {};
            } else {
                w.print("cache: MISS ({s})\n", .{path}) catch {};
            }
        },
        .off => w.print("cache: off ({s})\n", .{cache_reason}) catch {},
        .none => w.writeAll("cache: off\n") catch {},
    }
}

fn renderJson(w: *std.Io.Writer, mode: Mode) void {
    w.print("{{\"mode\":\"{s}\",\"stages_ms\":{{", .{@tagName(mode)}) catch {};
    for (stagesFor(mode), 0..) |s, i| {
        w.print("{s}\"{s}\":{d:.3}", .{ if (i == 0) "" else ",", stageKey(s), ms(s) }) catch {};
    }
    w.writeAll("}") catch {};
    switch (mode) {
        .run => renderCacheJson(w),
        .compile, .native => if (output_path_len > 0) {
            w.print(",\"output\":\"", .{}) catch {};
            writeJsonString(w, output_path_buf[0..output_path_len]);
            w.writeAll("\"") catch {};
        },
    }
    w.writeAll("}\n") catch {};
}

fn renderCacheJson(w: *std.Io.Writer) void {
    w.print(",\"cache\":{{\"status\":\"{s}\"", .{@tagName(cache_outcome)}) catch {};
    if (cache_outcome == .hit or cache_outcome == .miss) {
        w.writeAll(",\"path\":\"") catch {};
        writeJsonString(w, cache_path_buf[0..cache_path_len]);
        w.print("\",\"written\":{s}", .{if (cache_written) "true" else "false"}) catch {};
    }
    if (cache_reason.len > 0) {
        w.writeAll(",\"reason\":\"") catch {};
        writeJsonString(w, cache_reason);
        w.writeAll("\"") catch {};
    }
    w.writeAll("}") catch {};
}

/// Minimal JSON string escaping (paths can contain backslashes/quotes on some
/// platforms). Control characters are rare in paths; escape the two that matter.
fn writeJsonString(w: *std.Io.Writer, s: []const u8) void {
    for (s) |c| {
        switch (c) {
            '"' => w.writeAll("\\\"") catch {},
            '\\' => w.writeAll("\\\\") catch {},
            else => w.writeByte(c) catch {},
        }
    }
}

fn writeStderr(bytes: []const u8) void {
    if (comptime is_wasm) {
        _ = std.posix.write(2, bytes) catch 0;
    } else {
        _ = std.posix.system.write(2, bytes.ptr, bytes.len);
    }
}

// ── Tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;

/// Reset to a known state for a test and force `enabled` on. `enabled` is
/// threadlocal, so every enabling test must `defer testTeardown()` to keep it
/// from leaking into unrelated tests that share this thread.
fn testReset(fmt: Format) void {
    enable(fmt);
}

fn testTeardown() void {
    enabled = false;
    depth = 0;
}

test "disabled: begin/end are no-ops and record nothing" {
    enabled = false;
    depth = 0;
    buckets = @splat(0);
    begin(.read);
    end();
    try testing.expectEqual(@as(usize, 0), depth);
    try testing.expectEqual(@as(u64, 0), buckets[@intFromEnum(Stage.read)]);
}

test "self-time stack: a nested stage is not double-counted into its parent" {
    testReset(.text);
    defer testTeardown();
    defer test_clock = null;
    // emit contains a nested expand, on a deterministic timeline. The invariant
    // is that emit's bucket EXCLUDES expand's span — were it double-counted,
    // emit would read 55+45=100 instead of 55.
    test_clock = 100;
    begin(.emit); // emit resumes at 100
    test_clock = 130; // 30ns of emit before the nested call
    begin(.expand); // credits emit += 30; expand resumes at 130
    test_clock = 175; // 45ns of expand
    end(); // credits expand += 45; emit resumes at 175
    test_clock = 200; // 25ns more emit after the nested call
    end(); // credits emit += 25

    try testing.expectEqual(@as(u64, 55), buckets[@intFromEnum(Stage.emit)]);
    try testing.expectEqual(@as(u64, 45), buckets[@intFromEnum(Stage.expand)]);
    try testing.expectEqual(@as(usize, 0), depth);
}

test "self-time stack: sibling stages accumulate independently" {
    testReset(.text);
    defer testTeardown();
    defer test_clock = null;
    // read, then lower, then optimize — three non-nested spans in a row.
    test_clock = 0;
    begin(.read);
    test_clock = 10;
    end(); // read = 10
    begin(.lower);
    test_clock = 40;
    end(); // lower = 30
    begin(.optimize);
    test_clock = 45;
    end(); // optimize = 5
    try testing.expectEqual(@as(u64, 10), buckets[@intFromEnum(Stage.read)]);
    try testing.expectEqual(@as(u64, 30), buckets[@intFromEnum(Stage.lower)]);
    try testing.expectEqual(@as(u64, 5), buckets[@intFromEnum(Stage.optimize)]);
}

test "unbalanced end never underflows depth" {
    testReset(.text);
    defer testTeardown();
    end();
    end();
    try testing.expectEqual(@as(usize, 0), depth);
}

test "overflow past the stack cap balances without crashing" {
    testReset(.text);
    defer testTeardown();
    const over = stack.len + 5;
    var i: usize = 0;
    while (i < over) : (i += 1) begin(.read);
    try testing.expectEqual(over, depth);
    i = 0;
    while (i < over) : (i += 1) end();
    try testing.expectEqual(@as(usize, 0), depth);
}

test "text report: run miss shows all stages and a wrote cache line" {
    testReset(.text);
    defer testTeardown();
    buckets[@intFromEnum(Stage.read)] = 1_200_000;
    buckets[@intFromEnum(Stage.execute)] = 12_100_000;
    cacheMiss("/home/u/.kaappi/cache/abcd.sbc");
    cacheWrote();

    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    renderText(&w, .run);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "read 1.2ms") != null);
    try testing.expect(std.mem.indexOf(u8, out, "execute 12.1ms") != null);
    try testing.expect(std.mem.indexOf(u8, out, "cache: MISS (wrote /home/u/.kaappi/cache/abcd.sbc)") != null);
}

test "text report: run hit shows only execute + a HIT line" {
    testReset(.text);
    defer testTeardown();
    buckets[@intFromEnum(Stage.execute)] = 5_000_000;
    cacheHit("/home/u/.kaappi/cache/abcd.sbc");

    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    renderText(&w, .run);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "execute 5.0ms") != null);
    try testing.expect(std.mem.indexOf(u8, out, "read") == null); // compile stages hidden on a hit
    try testing.expect(std.mem.indexOf(u8, out, "cache: HIT (") != null);
}

test "json report: run mode has stable shape with all keys" {
    testReset(.json);
    defer testTeardown();
    buckets[@intFromEnum(Stage.read)] = 1_200_000;
    cacheMiss("/tmp/x.sbc");
    cacheWrote();

    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    renderJson(&w, .run);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "\"mode\":\"run\"") != null);
    inline for (.{ "read", "expand", "lower", "optimize", "emit", "execute" }) |k| {
        try testing.expect(std.mem.indexOf(u8, out, "\"" ++ k ++ "\":") != null);
    }
    try testing.expect(std.mem.indexOf(u8, out, "\"cache\":{\"status\":\"miss\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"written\":true") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"read\":1.200") != null);
}

test "json report: native mode lists llvm_emit and link, no cache" {
    testReset(.json);
    defer testTeardown();
    setOutput("/tmp/prog");
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    renderJson(&w, .native);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "\"mode\":\"native\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"llvm_emit\":") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"link\":") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"output\":\"/tmp/prog\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"cache\"") == null);
}

test "json string escaping for paths with quotes and backslashes" {
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    writeJsonString(&w, "a\\b\"c");
    try testing.expectEqualStrings("a\\\\b\\\"c", w.buffered());
}
