//! `kaappi features [--json]` — machine-readable capability discovery
//! (kaappi#1517, part of the machine-legibility epic kaappi#1503).
//!
//! An agent's (or a hurried human's) first question is "what am I working
//! with?". KEP-0004 already answers that *inside Scheme* via `cond-expand`
//! feature identifiers; this extends the same philosophy to the CLI boundary so
//! the answer can be had without running a probe program or scraping `--help`.
//!
//! Single source of truth, by construction:
//!   * the compiled-in feature identifiers are `types.platform_features` — the
//!     exact table `cond-expand` and R7RS `(features)` resolve against, so the
//!     three can never disagree (asserted by a test below);
//!   * the built-in SRFIs are derived from the library registry — the `srfi_*`
//!     tags of `primitives.Lib` plus the syntax-only `srfi.*` entries of
//!     `library.extra_std_libraries` — never a second hardcoded list;
//!   * the portable SRFIs are `build_options.portable_srfis`, generated at
//!     build time by scanning `lib/srfi/*.sld`, so shipping a new one updates
//!     this output automatically.
//!
//! Forms:
//!   kaappi features          human-readable capability table
//!   kaappi features --json   one JSON object for structured/agent use
//!
//! Like `kaappi explain`, this is a pure query — no VM, GC, or library setup —
//! so main dispatches it before any of that is created. It is native-only
//! (WASM's entry point just runs a file).

const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const build_options = @import("build_options");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");
const reporting = @import("reporting.zig");
const lsp_diagnostic = @import("lsp_diagnostic.zig");

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

pub const USAGE_ERROR_EXIT: u8 = 2;

/// The target triple this binary was built for, e.g. "aarch64-macos-none".
/// Comptime-built from `builtin` so it costs nothing at runtime.
pub const target_triple = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag) ++ "-" ++ @tagName(builtin.abi);

/// `--sandbox` is a native-only flag: WASM is sandboxed by construction and its
/// entry point never parses CLI flags at all.
const sandbox_available = builtin.os.tag != .wasi;

/// Enough slots for every built-in SRFI (the `srfi_*` tags of `primitives.Lib`
/// plus the `srfi.*` entries of `library.extra_std_libraries`); today that is 8.
const max_builtin_srfis = 32;

// ── Dispatch ───────────────────────────────────────────────────────────

/// If `args` is a `kaappi features …` invocation, handle it fully and return
/// the process exit code; otherwise return null so normal CLI dispatch
/// proceeds.
pub fn maybeRun(allocator: std.mem.Allocator, args: std.process.Args) ?u8 {
    var it = platform.argsIterate(args);
    _ = it.skip(); // argv[0]
    const first = it.next() orelse return null;
    if (!std.mem.eql(u8, first, "features")) return null;

    var json = false;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return 0;
        } else {
            writeStderr("kaappi features: unexpected argument '");
            writeStderr(arg);
            writeStderr("'\nUsage: kaappi features [--json]\n");
            return USAGE_ERROR_EXIT;
        }
    }
    return run(allocator, json);
}

/// Render the report (JSON or text) and print it; returns the process exit code.
pub fn run(allocator: std.mem.Allocator, json: bool) u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;
    (if (json) renderJson(w) else renderText(w)) catch {
        writeStderr("kaappi features: out of memory\n");
        return 1;
    };
    writeStdout(aw.written());
    return 0;
}

// ── Data derivation ────────────────────────────────────────────────────

/// The SRFI number in a canonical library name like "srfi.170", or null for a
/// non-SRFI name ("scheme.base", "kaappi.internal").
fn parseSrfiNumber(canonical: []const u8) ?u16 {
    const prefix = "srfi.";
    if (!std.mem.startsWith(u8, canonical, prefix)) return null;
    return std.fmt.parseInt(u16, canonical[prefix.len..], 10) catch null;
}

/// Built-in SRFI numbers (sorted ascending), derived from the registry: the
/// `srfi_*` tags of `primitives.Lib` (which have Zig primitives) plus the
/// syntax-only `srfi.*` entries of `library.extra_std_libraries` (e.g. srfi.9).
/// Fills `buf` and returns the used prefix of it.
fn builtinSrfis(buf: []u16) []u16 {
    var n: usize = 0;
    for (std.enums.values(primitives.Lib)) |lib| {
        if (parseSrfiNumber(lib.canonicalName())) |num| {
            buf[n] = num;
            n += 1;
        }
    }
    for (library.extra_std_libraries) |name| {
        if (parseSrfiNumber(name)) |num| {
            buf[n] = num;
            n += 1;
        }
    }
    std.mem.sort(u16, buf[0..n], {}, std.sort.asc(u16));
    return buf[0..n];
}

// ── Text rendering ─────────────────────────────────────────────────────

fn renderText(w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.print("Kaappi Scheme v{s}  (build {s})\n", .{ build_options.version, build_options.git_build_id });
    try w.print("  target      {s}\n", .{target_triple});
    try w.print("  build mode  {s}\n", .{@tagName(builtin.mode)});
    if (build_options.gc_stress)
        try w.writeAll("  gc-stress   on (collection forced on every allocation)\n");
    try w.print("  sandbox     {s}\n", .{if (sandbox_available) "available" else "unavailable"});

    try w.writeAll("\nFeatures (compiled-in subsystems; cond-expand / (features) identifiers):\n  ");
    for (types.platform_features, 0..) |f, i| {
        if (i > 0) try w.writeByte(' ');
        try w.writeAll(f);
    }
    try w.writeByte('\n');

    var buf: [max_builtin_srfis]u16 = undefined;
    const builtin_srfi = builtinSrfis(&buf);
    try w.writeAll("\nSRFIs:\n");
    try w.print("  built-in ({d}): ", .{builtin_srfi.len});
    try writeNumberList(w, builtin_srfi);
    try w.print("\n  portable ({d}): ", .{build_options.portable_srfis.len});
    try writeNumberList(w, build_options.portable_srfis);
    // #1649: every SRFI listed above is also probeable as a cond-expand feature
    // identifier `srfi-<n>`; not re-listed here to avoid duplicating both sets.
    try w.writeAll("\n  (each is also a cond-expand feature id: srfi-<n>)\n");

    try w.writeAll("\nLimits:\n");
    try w.print("  initial frame capacity     {d} (grows to {d})\n", .{ build_options.max_frames, types.MAX_FRAME_LIMIT });
    try w.print("  initial register capacity  {d} (grows to {d})\n", .{ build_options.max_registers, types.MAX_REGISTER_LIMIT });
    try w.print("  gc initial threshold       {d}\n", .{build_options.gc_initial_threshold});
}

fn writeNumberList(w: *std.Io.Writer, nums: []const u16) std.Io.Writer.Error!void {
    for (nums, 0..) |n, i| {
        if (i > 0) try w.writeByte(' ');
        try w.print("{d}", .{n});
    }
}

// ── JSON rendering ─────────────────────────────────────────────────────

/// One JSON object. Keys are the stable machine contract; string values reuse
/// the shared `writeJsonString` escaper so this matches `--diagnostics=json`
/// and `kaappi explain --json` byte-for-byte in how it escapes.
fn renderJson(w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeAll("{\"version\":");
    try lsp_diagnostic.writeJsonString(w, build_options.version);
    try w.writeAll(",\"build_id\":");
    try lsp_diagnostic.writeJsonString(w, build_options.git_build_id);
    try w.writeAll(",\"target\":");
    try lsp_diagnostic.writeJsonString(w, target_triple);
    try w.writeAll(",\"build_mode\":");
    try lsp_diagnostic.writeJsonString(w, @tagName(builtin.mode));
    try w.print(",\"gc_stress\":{s}", .{if (build_options.gc_stress) "true" else "false"});
    try w.print(",\"sandbox_available\":{s}", .{if (sandbox_available) "true" else "false"});

    try w.writeAll(",\"features\":[");
    for (types.platform_features, 0..) |f, i| {
        if (i > 0) try w.writeByte(',');
        try lsp_diagnostic.writeJsonString(w, f);
    }
    try w.writeByte(']');

    var buf: [max_builtin_srfis]u16 = undefined;
    const builtin_srfi = builtinSrfis(&buf);
    try w.writeAll(",\"srfis\":{\"builtin\":");
    try writeJsonNumberArray(w, builtin_srfi);
    try w.writeAll(",\"portable\":");
    try writeJsonNumberArray(w, build_options.portable_srfis);
    try w.writeByte('}');

    try w.print(
        ",\"limits\":{{\"initial_frame_capacity\":{d},\"initial_register_capacity\":{d},\"gc_initial_threshold\":{d}}}",
        .{ build_options.max_frames, build_options.max_registers, build_options.gc_initial_threshold },
    );

    try w.writeAll("}\n");
}

fn writeJsonNumberArray(w: *std.Io.Writer, nums: []const u16) std.Io.Writer.Error!void {
    try w.writeByte('[');
    for (nums, 0..) |n, i| {
        if (i > 0) try w.writeByte(',');
        try w.print("{d}", .{n});
    }
    try w.writeByte(']');
}

// ── Usage ──────────────────────────────────────────────────────────────

fn printUsage() void {
    writeStdout(
        \\Usage: kaappi features [--json]
        \\
        \\Report this build's capabilities: version and git build id, target and
        \\build mode, the compiled-in subsystems (the cond-expand feature
        \\identifiers), the built-in and portable SRFIs, and the initial VM/GC
        \\limits.
        \\
        \\  --json   Emit one JSON object instead of the human-readable table.
        \\
    );
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

fn renderJsonToOwned(allocator: std.mem.Allocator) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    try renderJson(&aw.writer);
    return aw.toOwnedSlice();
}

fn renderTextToOwned(allocator: std.mem.Allocator) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    try renderText(&aw.writer);
    return aw.toOwnedSlice();
}

fn contains(nums: []const u16, target: u16) bool {
    for (nums) |n| if (n == target) return true;
    return false;
}

test "features json shares exactly the cond-expand feature table" {
    // The acceptance guarantee (kaappi#1517): the `features` list is the very
    // table `cond-expand`/`(features)` resolve against — same members, same
    // order — so the CLI and the language can never report different subsystems.
    const out = try renderJsonToOwned(testing.allocator);
    defer testing.allocator.free(out);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out, .{});
    defer parsed.deinit();

    const feats = parsed.value.object.get("features").?.array;
    try testing.expectEqual(types.platform_features.len, feats.items.len);
    for (types.platform_features, 0..) |f, i| {
        try testing.expectEqualStrings(f, feats.items[i].string);
    }
}

test "features json is one object with the documented keys and limit values" {
    const out = try renderJsonToOwned(testing.allocator);
    defer testing.allocator.free(out);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;

    try testing.expectEqualStrings(build_options.version, obj.get("version").?.string);
    try testing.expect(obj.get("build_id").?.string.len > 0);
    try testing.expectEqualStrings(target_triple, obj.get("target").?.string);
    try testing.expect(obj.get("build_mode").?.string.len > 0);
    // Unit tests never build for WASM, so sandbox is available here.
    try testing.expect(obj.get("sandbox_available").?.bool);

    const limits = obj.get("limits").?.object;
    try testing.expectEqual(@as(i64, build_options.max_frames), limits.get("initial_frame_capacity").?.integer);
    try testing.expectEqual(@as(i64, build_options.max_registers), limits.get("initial_register_capacity").?.integer);
    try testing.expectEqual(@as(i64, build_options.gc_initial_threshold), limits.get("gc_initial_threshold").?.integer);
}

test "builtin srfis are registry-derived, sorted, and include srfi.9" {
    var buf: [max_builtin_srfis]u16 = undefined;
    const list = builtinSrfis(&buf);
    try testing.expect(list.len > 0);
    var prev: u16 = 0;
    for (list) |n| {
        try testing.expect(n >= prev); // sorted ascending
        prev = n;
    }
    try testing.expect(contains(list, 1)); // srfi_1 (Lib enum tag)
    try testing.expect(contains(list, 9)); // srfi.9 (syntax-only extra lib)
    try testing.expect(contains(list, 170)); // srfi_170 (Lib enum tag)
}

test "portable srfis come from the build-time lib/srfi scan" {
    const out = try renderJsonToOwned(testing.allocator);
    defer testing.allocator.free(out);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out, .{});
    defer parsed.deinit();

    const portable = parsed.value.object.get("srfis").?.object.get("portable").?.array;
    // The output list *is* the generated table, not a second copy.
    try testing.expectEqual(build_options.portable_srfis.len, portable.items.len);
    // A couple of SRFIs that ship as lib/srfi/*.sld, proving the scan populated.
    try testing.expect(contains(build_options.portable_srfis, 64)); // (srfi 64) test suite
    try testing.expect(contains(build_options.portable_srfis, 158)); // (srfi 158) generators
}

test "features text carries version, target, and the srfi sections" {
    const out = try renderTextToOwned(testing.allocator);
    defer testing.allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, build_options.version) != null);
    try testing.expect(std.mem.indexOf(u8, out, target_triple) != null);
    try testing.expect(std.mem.indexOf(u8, out, "built-in") != null);
    try testing.expect(std.mem.indexOf(u8, out, "portable") != null);
    try testing.expect(std.mem.indexOf(u8, out, "kaappi-fibers") != null);
}

test "parseSrfiNumber accepts srfi.N and rejects everything else" {
    try testing.expectEqual(@as(?u16, 170), parseSrfiNumber("srfi.170"));
    try testing.expectEqual(@as(?u16, 9), parseSrfiNumber("srfi.9"));
    try testing.expect(parseSrfiNumber("scheme.base") == null);
    try testing.expect(parseSrfiNumber("kaappi.internal") == null);
    try testing.expect(parseSrfiNumber("scheme.case-lambda") == null);
    try testing.expect(parseSrfiNumber("srfi.") == null);
}
