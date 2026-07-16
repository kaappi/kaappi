//! Central bytecode cache: location policy + `kaappi cache status|clear`
//! (kaappi#1516, part of the machine-legibility epic kaappi#1503).
//!
//! Plain `kaappi file.scm` runs read and write a compiled-bytecode cache so a
//! second run skips the read→expand→compile pipeline. Historically that cache
//! lived *next to* the source as `file.sbc`, keyed on the source hash and the
//! version *string* — which meant a dev rebuild at the same version silently
//! served the previous binary's bytecode, manufacturing phantom bugs and
//! masking real fixes. Two things fix that here:
//!
//!   * the cache key now folds in the git build id (see
//!     `bytecode_file.compilerHash`), so any recompiled binary misses a cache
//!     the old binary wrote; and
//!   * the cache moves to a single directory — `~/.kaappi/cache/` (honoring
//!     `KAAPPI_HOME`) — with entries keyed by the absolute source path, so it
//!     can be *inspected* (`cache status`) and *wiped* (`cache clear`) through
//!     the CLI without anyone needing to know or hunt for a path.
//!
//! Explicit artifacts (`kaappi --compile file.scm [-o out]`) are unchanged —
//! they are outputs the user asked for by name, not this invisible cache.
//!
//! Like `explain`/`features`/`doctor`, the subcommand is a pure filesystem
//! query — no VM — so main dispatches it before any VM/GC setup. It is
//! native-only; on WASM there is no home dir and no cache (writes no-op'd even
//! under the old layout), so `pathForSource` returns null and callers skip
//! caching entirely.

const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const bytecode_file = @import("bytecode_file.zig");
const kaappi_paths = @import("kaappi_paths.zig");
const file_utils = @import("file_utils.zig");
const reporting = @import("reporting.zig");

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

pub const USAGE_ERROR_EXIT: u8 = 2;

const is_wasm = builtin.os.tag == .wasi;

/// A cache file can't reasonably exceed this; `readWholeFile` needs a ceiling
/// and a genuine entry is far smaller (`MAX_CODE_BYTES` in bytecode_file is
/// 4 MiB), so 16 MiB is comfortable headroom without unbounded reads.
const MAX_CACHE_FILE_BYTES: usize = 16 << 20;

// ── Location policy ────────────────────────────────────────────────────

/// Writes the cache directory path (`<home>/.kaappi/cache`) into `buf` and
/// returns the slice, or null when the home dir can't be resolved (no HOME /
/// KAAPPI_HOME) or the result doesn't fit. `kaappi_paths.getHome` already
/// returns `<home>/.kaappi`, so this only appends `/cache`.
pub fn cacheDir(buf: []u8) ?[]const u8 {
    if (comptime is_wasm) return null;
    var home_buf: [512]u8 = undefined;
    const home = kaappi_paths.getHome(&home_buf) orelse return null;
    const suffix = "/cache";
    if (home.len + suffix.len > buf.len) return null;
    @memcpy(buf[0..home.len], home);
    @memcpy(buf[home.len..][0..suffix.len], suffix);
    return buf[0 .. home.len + suffix.len];
}

/// The `.sbc` cache path for `source_path`, or null when there is nowhere to
/// put it (no home dir, or WASM) — callers then simply skip caching, exactly
/// as the co-located cache silently did. Keyed by the *absolute, canonical*
/// source path (via `realpath`) so the same file resolves to one entry
/// regardless of the caller's CWD, and distinct files never share a key. The
/// directory is not created here — call `ensureDir` before writing.
///
/// A hash collision between two different absolute paths (astronomically
/// unlikely with a 64-bit path hash) is self-correcting, never a correctness
/// bug: the loser's `source_hash` won't match, so the load misses and
/// recompiles, overwriting the entry.
pub fn pathForSource(allocator: std.mem.Allocator, source_path: []const u8) ?[]u8 {
    if (comptime is_wasm) return null;
    var dir_buf: [1024]u8 = undefined;
    const dir = cacheDir(&dir_buf) orelse return null;

    var abs_buf: [platform.PATH_MAX]u8 = undefined;
    const key_path = absPath(source_path, &abs_buf) orelse source_path;
    const key = std.hash.Wyhash.hash(0, key_path);

    return std.fmt.allocPrint(allocator, "{s}/{x:0>16}.sbc", .{ dir, key }) catch null;
}

/// Canonicalizes `path` into `buf` via `realpath` (requires the file to exist,
/// which it does on both the cache read and write paths), returning the slice
/// or null on failure so the caller falls back to the raw path.
fn absPath(path: []const u8, buf: []u8) ?[]const u8 {
    if (path.len == 0 or path.len >= platform.PATH_MAX or buf.len < platform.PATH_MAX) return null;
    var z: [platform.PATH_MAX]u8 = undefined;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    return platform.realPath(z[0..path.len :0], buf);
}

/// Best-effort creation of `~/.kaappi` and `~/.kaappi/cache`. Failures are
/// swallowed (EEXIST included): the subsequent cache write is itself
/// best-effort (`catch {}`), so a read-only home just means no caching, never
/// a hard error.
pub fn ensureDir() void {
    if (comptime is_wasm) return;
    var home_buf: [512]u8 = undefined;
    if (kaappi_paths.getHome(&home_buf)) |home| mkdirBestEffort(home);
    var dir_buf: [1024]u8 = undefined;
    if (cacheDir(&dir_buf)) |dir| mkdirBestEffort(dir);
}

fn mkdirBestEffort(path: []const u8) void {
    var z: [1024]u8 = undefined;
    const zpath = zPath(&z, path) orelse return;
    _ = platform.mkdir(zpath, 0o755);
}

/// Copies `path` into `buf` with a NUL terminator, returning a sentinel slice
/// (coercible to the `[*:0]const u8` libc wants), or null if it doesn't fit.
fn zPath(buf: []u8, path: []const u8) ?[:0]const u8 {
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}

// ── Subcommand dispatch ────────────────────────────────────────────────

/// If `args` is a `kaappi cache …` invocation, handle it fully and return the
/// process exit code; otherwise return null so normal CLI dispatch proceeds.
pub fn maybeRun(allocator: std.mem.Allocator, args: std.process.Args) ?u8 {
    var it = platform.argsIterate(args);
    _ = it.skip(); // argv[0]
    const first = it.next() orelse return null;
    if (!std.mem.eql(u8, first, "cache")) return null;

    const sub = it.next() orelse {
        writeStderr("kaappi cache: missing subcommand\n");
        printUsage();
        return USAGE_ERROR_EXIT;
    };

    if (std.mem.eql(u8, sub, "-h") or std.mem.eql(u8, sub, "--help")) {
        printUsage();
        return 0;
    }

    const is_status = std.mem.eql(u8, sub, "status");
    const is_clear = std.mem.eql(u8, sub, "clear");
    if (!is_status and !is_clear) {
        writeStderr("kaappi cache: unknown subcommand '");
        writeStderr(sub);
        writeStderr("'\n");
        printUsage();
        return USAGE_ERROR_EXIT;
    }

    if (it.next()) |extra| {
        writeStderr("kaappi cache ");
        writeStderr(sub);
        writeStderr(": unexpected argument '");
        writeStderr(extra);
        writeStderr("'\n");
        return USAGE_ERROR_EXIT;
    }

    return if (is_status) runStatus(allocator) else runClear(allocator);
}

fn printUsage() void {
    writeStdout(
        \\Usage: kaappi cache <status|clear>
        \\
        \\  status   Show the cache location, entry count, total size, and per-entry
        \\           source path + producing build id.
        \\  clear    Remove every cache entry (the supported way to wipe the cache).
        \\
        \\The cache lives at ~/.kaappi/cache (or $KAAPPI_HOME/cache). Entries are
        \\keyed by source path and the compiling build id, so a rebuilt binary never
        \\reuses an older binary's bytecode. See docs/dev/cache.md.
        \\
    );
}

fn runStatus(allocator: std.mem.Allocator) u8 {
    var dir_buf: [1024]u8 = undefined;
    const dir = cacheDir(&dir_buf) orelse {
        writeStdout("Cache: unavailable (neither KAAPPI_HOME nor HOME is set)\n");
        return 0;
    };

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    renderStatus(allocator, dir, &aw.writer) catch {
        writeStderr("kaappi cache status: out of memory\n");
        return 1;
    };
    writeStdout(aw.written());
    return 0;
}

fn runClear(allocator: std.mem.Allocator) u8 {
    var dir_buf: [1024]u8 = undefined;
    const dir = cacheDir(&dir_buf) orelse {
        writeStdout("Cache: unavailable (neither KAAPPI_HOME nor HOME is set); nothing to clear\n");
        return 0;
    };

    const res = clearDir(allocator, dir);

    var buf: [16]u8 = undefined;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    aw.writer.print("Cleared {d} {s} ({s}) from {s}\n", .{
        res.removed,
        if (res.removed == 1) "entry" else "entries",
        fmtSize(&buf, res.bytes),
        dir,
    }) catch {
        writeStderr("kaappi cache clear: out of memory\n");
        return 1;
    };
    writeStdout(aw.written());
    return 0;
}

// ── Reporting core (directory-injected, so it is unit-testable) ─────────

const Entry = struct {
    source_path: []const u8, // owned
    build_id: []const u8, // owned
    size: u64,
    current_build: bool,
    parsed: bool,
};

/// Renders `cache status` output for the entries in `dir` into `w`. Split from
/// `runStatus` (which resolves the real `~/.kaappi/cache`) so tests can drive a
/// temp directory directly.
pub fn renderStatus(allocator: std.mem.Allocator, dir: []const u8, w: *std.Io.Writer) !void {
    try w.print("Cache: {s}\n", .{dir});

    var entries: std.ArrayList(Entry) = .empty;
    defer {
        for (entries.items) |e| {
            allocator.free(e.source_path);
            allocator.free(e.build_id);
        }
        entries.deinit(allocator);
    }

    var total: u64 = 0;
    var z: [1024]u8 = undefined;
    const dir_z = zPath(&z, dir) orelse {
        try w.writeAll("  (path too long)\n0 entries, 0 B\n");
        return;
    };
    var dh = platform.DirIter.open(dir_z) orelse {
        try w.writeAll("  (empty — no cache directory yet)\n0 entries, 0 B\n");
        return;
    };
    defer dh.close();

    while (dh.next()) |name| {
        if (!std.mem.endsWith(u8, name, ".sbc")) continue;

        const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name }) catch continue;
        defer allocator.free(full);
        const data = file_utils.readWholeFile(allocator, full, MAX_CACHE_FILE_BYTES) catch continue;
        defer allocator.free(data);

        var entry: Entry = .{
            .source_path = &.{},
            .build_id = &.{},
            .size = data.len,
            .current_build = false,
            .parsed = false,
        };
        if (bytecode_file.readHeaderInfo(data)) |info| {
            entry.source_path = allocator.dupe(u8, info.source_path) catch continue;
            entry.build_id = allocator.dupe(u8, info.build_id) catch {
                allocator.free(entry.source_path);
                continue;
            };
            entry.current_build = info.current_build;
            entry.parsed = true;
        } else {
            entry.source_path = allocator.dupe(u8, name) catch continue;
            entry.build_id = allocator.dupe(u8, "?") catch {
                allocator.free(entry.source_path);
                continue;
            };
        }
        entries.append(allocator, entry) catch {
            allocator.free(entry.source_path);
            allocator.free(entry.build_id);
            continue;
        };
        total += data.len;
    }

    if (entries.items.len == 0) {
        try w.writeAll("  (empty)\n0 entries, 0 B\n");
        return;
    }

    // Deterministic order (directory iteration order is unspecified).
    std.mem.sort(Entry, entries.items, {}, lessBySource);

    var szbuf: [16]u8 = undefined;
    var totbuf: [16]u8 = undefined;
    for (entries.items) |e| {
        if (e.parsed) {
            try w.print("  {s:>9}  {s:<18} {s:<7} {s}\n", .{
                fmtSize(&szbuf, e.size),
                e.build_id,
                if (e.current_build) "current" else "stale",
                e.source_path,
            });
        } else {
            try w.print("  {s:>9}  {s:<18} {s:<7} {s}\n", .{
                fmtSize(&szbuf, e.size),
                "?",
                "unknown",
                e.source_path,
            });
        }
    }
    try w.print("{d} {s}, {s}\n", .{
        entries.items.len,
        if (entries.items.len == 1) "entry" else "entries",
        fmtSize(&totbuf, total),
    });
}

fn lessBySource(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.source_path, b.source_path);
}

pub const ClearResult = struct { removed: usize, bytes: u64 };

/// Deletes every `*.sbc` entry in `dir` (and only those — never the directory
/// itself or unrelated files), returning how many were removed and their total
/// size. Names are collected before any deletion so mutating the directory
/// can't disturb the iterator.
pub fn clearDir(allocator: std.mem.Allocator, dir: []const u8) ClearResult {
    var res: ClearResult = .{ .removed = 0, .bytes = 0 };

    var z: [1024]u8 = undefined;
    const dir_z = zPath(&z, dir) orelse return res;
    var dh = platform.DirIter.open(dir_z) orelse return res;

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }

    while (dh.next()) |name| {
        if (!std.mem.endsWith(u8, name, ".sbc")) continue;
        const dup = allocator.dupe(u8, name) catch continue;
        names.append(allocator, dup) catch {
            allocator.free(dup);
            continue;
        };
    }
    dh.close();

    for (names.items) |name| {
        const full = std.fmt.allocPrintSentinel(allocator, "{s}/{s}", .{ dir, name }, 0) catch continue;
        defer allocator.free(full);
        // Size before unlink, so the reported total reflects what was freed.
        // Read the length rather than stat: this Zig's `std.c` stat family isn't
        // callable on Linux (glibc's `__xstat` indirection leaves `std.c.fstatat`
        // typed `void`), so reading small cache files through the same portable
        // path `renderStatus` uses avoids per-OS stat code.
        const size: u64 = if (file_utils.readWholeFile(allocator, full, MAX_CACHE_FILE_BYTES)) |d| blk: {
            defer allocator.free(d);
            break :blk d.len;
        } else |_| 0;
        if (platform.unlink(full) != 0) continue;
        res.removed += 1;
        res.bytes += size;
    }

    return res;
}

// ── Helpers ────────────────────────────────────────────────────────────

/// Formats a byte count into `buf` as B / KB / MB (1024-based). Returns the
/// slice of `buf` used; `buf` must be at least 16 bytes.
fn fmtSize(buf: []u8, bytes: u64) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    if (bytes < 1024) {
        w.print("{d} B", .{bytes}) catch return buf[0..0];
    } else if (bytes < 1024 * 1024) {
        const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
        w.print("{d:.1} KB", .{kb}) catch return buf[0..0];
    } else {
        const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
        w.print("{d:.1} MB", .{mb}) catch return buf[0..0];
    }
    return w.buffered();
}

// ── Tests ──────────────────────────────────────────────────────────────

const memory = @import("memory.zig");
const types = @import("types.zig");

test "fmtSize renders B/KB/MB" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("0 B", fmtSize(&buf, 0));
    try std.testing.expectEqualStrings("512 B", fmtSize(&buf, 512));
    try std.testing.expectEqualStrings("1.0 KB", fmtSize(&buf, 1024));
    try std.testing.expectEqualStrings("1.5 KB", fmtSize(&buf, 1536));
    try std.testing.expectEqualStrings("2.0 MB", fmtSize(&buf, 2 * 1024 * 1024));
}

/// Writes a minimal but real `.sbc` (via the actual serializer, so the header
/// is genuine) at `dir/<name>` recording `source_path`.
fn writeTestCacheEntry(allocator: std.mem.Allocator, dir: []const u8, name: []const u8, source_path: []const u8) !void {
    var gc = memory.GC.init(allocator);
    defer gc.deinit();
    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.arity = 0;
    func.locals_count = 1;
    var funcs = [_]*types.Function{func};
    const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name });
    defer allocator.free(full);
    try bytecode_file.writeFileWithTopLevel(allocator, &funcs, 0xABCD, source_path, full);
}

test "renderStatus and clearDir over a temp cache dir" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(dir);

    try writeTestCacheEntry(allocator, dir, "aaaa.sbc", "/home/u/one.scm");
    try writeTestCacheEntry(allocator, dir, "bbbb.sbc", "/home/u/two.scm");
    // A non-.sbc file must be ignored by both status and clear.
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "keep.txt", .data = "not a cache file" });

    // status lists both entries, their source paths, and a 2-entry total.
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try renderStatus(allocator, dir, &aw.writer);
    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "/home/u/one.scm") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/home/u/two.scm") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "2 entries") != null);
    // Written by this binary, so both are the current build.
    try std.testing.expect(std.mem.indexOf(u8, out, "current") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "keep.txt") == null);

    // clear removes exactly the two .sbc files, not keep.txt.
    const res = clearDir(allocator, dir);
    try std.testing.expectEqual(@as(usize, 2), res.removed);
    try std.testing.expect(res.bytes > 0);
    try tmp.dir.access(std.testing.io, "keep.txt", .{}); // still there → no error
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "aaaa.sbc", .{}));

    // status on the now-empty dir reports zero entries.
    var aw2: std.Io.Writer.Allocating = .init(allocator);
    defer aw2.deinit();
    try renderStatus(allocator, dir, &aw2.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw2.written(), "0 entries") != null);
}

test "clearDir on a missing directory is a no-op" {
    const allocator = std.testing.allocator;
    const res = clearDir(allocator, "/nonexistent/kaappi/cache/path/xyzzy");
    try std.testing.expectEqual(@as(usize, 0), res.removed);
    try std.testing.expectEqual(@as(u64, 0), res.bytes);
}
