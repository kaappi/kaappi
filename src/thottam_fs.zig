//! Portable filesystem operations for thottam's install pipeline (#1609).
//!
//! Before the Windows port, install/remove/update shelled out to POSIX
//! userland (`/bin/cp -R`, `/usr/bin/find`, `/bin/mkdir -p`, `/bin/rm -rf`,
//! `/usr/bin/touch`). These helpers reimplement exactly that surface on the
//! platform shim so the pipeline behaves identically on every target —
//! Windows included — and spawns no processes for file work.
//!
//! Symlinks are never traversed (platform.lstatPath): a link inside a
//! package tree can point anywhere, and following one during removal or
//! copy would escape the tree. Removal retries once through
//! platform.makeWritable — git marks object/pack files read-only, which
//! blocks plain unlink on Windows (and unwritable directories block child
//! unlinks on POSIX).

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");

fn isSep(c: u8) bool {
    return c == '/' or (platform.is_windows and c == '\\');
}

fn join(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + 1 + b.len);
    @memcpy(result[0..a.len], a);
    result[a.len] = '/';
    @memcpy(result[a.len + 1 ..], b);
    return result;
}

fn lstat(allocator: std.mem.Allocator, path: []const u8) ?platform.StatInfo {
    const z = allocator.dupeZ(u8, path) catch return null;
    defer allocator.free(z);
    return platform.lstatPath(z);
}

/// `mkdir -p`: creates every missing component, succeeds if the directory
/// already exists. Intermediate mkdir failures are resolved by the final
/// check — the path must be a directory when we're done.
pub fn makeDirRecursive(allocator: std.mem.Allocator, path: []const u8) !void {
    var p = path;
    while (p.len > 1 and isSep(p[p.len - 1])) p = p[0 .. p.len - 1];
    if (p.len == 0) return error.MkdirFailed;

    var end: usize = 0;
    while (end < p.len) {
        while (end < p.len and !isSep(p[end])) end += 1;
        if (end > 0) {
            const prefix = try allocator.dupeZ(u8, p[0..end]);
            defer allocator.free(prefix);
            _ = platform.mkdir(prefix, 0o755);
        }
        while (end < p.len and isSep(p[end])) end += 1;
    }

    const z = try allocator.dupeZ(u8, p);
    defer allocator.free(z);
    if (!platform.isDir(z)) return error.MkdirFailed;
}

/// `touch`: creates the file if missing, never truncates existing content.
pub fn touchFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const z = try allocator.dupeZ(u8, path);
    defer allocator.free(z);
    const fd = platform.openAppend(z, 0o644) catch return error.TouchFailed;
    platform.close(fd);
}

/// Byte-copy src over dst (created 0o644, truncated if present). Opening
/// src follows a symlink — `cp <link> dst` copies the target's content —
/// but a dst that is itself a symlink is unlinked first: writing through
/// it would land outside the tree the caller is installing into.
pub fn copyFile(allocator: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    const src_z = try allocator.dupeZ(u8, src);
    defer allocator.free(src_z);
    const dst_z = try allocator.dupeZ(u8, dst);
    defer allocator.free(dst_z);

    if (platform.lstatPath(dst_z)) |dst_st| {
        if (dst_st.is_symlink) _ = platform.unlink(dst_z);
    }

    const in = platform.openRead(src_z) catch return error.CopyFailed;
    defer platform.close(in);
    const out = platform.openWriteTrunc(dst_z, 0o644) catch return error.CopyFailed;
    defer platform.close(out);

    var buf: [16384]u8 = undefined;
    while (true) {
        const raw = platform.read(in, &buf, buf.len);
        if (raw < 0) {
            if (platform.errno(raw) == .INTR) continue;
            return error.CopyFailed;
        }
        const n: usize = @intCast(raw);
        if (n == 0) return;
        var total: usize = 0;
        while (total < n) {
            const w = platform.write(out, buf[total..].ptr, n - total);
            if (w < 0) {
                if (platform.errno(w) == .INTR) continue;
                return error.CopyFailed;
            }
            if (w == 0) return error.CopyFailed;
            total += @as(usize, @intCast(w));
        }
    }
}

/// Snapshot a directory's entry names (skipping "." and "..") so the
/// caller can recurse or delete without a live iterator underneath —
/// DirIter yields views into per-iterator state, and mutating a directory
/// mid-iteration is undefined on both readdir and FindNextFileW.
fn collectNames(allocator: std.mem.Allocator, dir_z: [:0]const u8) !?std.ArrayList([]u8) {
    var it = platform.DirIter.open(dir_z) orelse return null;
    defer it.close();
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }
    while (it.next()) |name| {
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        const copy = try allocator.dupe(u8, name);
        names.append(allocator, copy) catch |err| {
            allocator.free(copy);
            return err;
        };
    }
    return names;
}

fn freeNames(allocator: std.mem.Allocator, names: *std.ArrayList([]u8)) void {
    for (names.items) |n| allocator.free(n);
    names.deinit(allocator);
}

/// `cp -R src/. dst/`: recursively merge the *contents* of src into dst,
/// creating dst (and any missing parents) first. Existing files are
/// overwritten, existing subdirectories merged into — `thottam update`
/// relies on both. Symlinks in src are skipped, never followed: reading
/// through a package-controlled link would copy content from outside the
/// package tree (old `cp -R` duplicated links instead of following them,
/// and ecosystem lib/ trees contain none).
pub fn copyTree(allocator: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    try makeDirRecursive(allocator, dst);

    const src_z = try allocator.dupeZ(u8, src);
    defer allocator.free(src_z);
    var names = (try collectNames(allocator, src_z)) orelse return error.CopyFailed;
    defer freeNames(allocator, &names);

    for (names.items) |name| {
        const child_src = try join(allocator, src, name);
        defer allocator.free(child_src);
        const child_dst = try join(allocator, dst, name);
        defer allocator.free(child_dst);

        const st = lstat(allocator, child_src) orelse continue;
        if (st.is_symlink) continue;
        if (st.is_dir) {
            try copyTree(allocator, child_src, child_dst);
        } else if (st.is_file) {
            try copyFile(allocator, child_src, child_dst);
        }
    }
}

/// Unlink with one retry after clearing write protection: the child's
/// read-only attribute blocks unlink on Windows; on POSIX it's the parent
/// directory's write bit that gates unlinking entries.
fn unlinkRetry(child_z: [:0]const u8, parent_z: ?[:0]const u8) !void {
    if (platform.unlink(child_z) == 0) return;
    platform.makeWritable(child_z);
    if (parent_z) |p| platform.makeWritable(p);
    if (platform.unlink(child_z) != 0) return error.RemoveFailed;
}

fn rmdirRetry(dir_z: [:0]const u8) !void {
    if (platform.rmdir(dir_z) == 0) return;
    platform.makeWritable(dir_z);
    if (platform.rmdir(dir_z) != 0) return error.RemoveFailed;
}

/// `rm -rf`: removes path and everything under it; succeeds silently when
/// path doesn't exist. Symlinks are unlinked (POSIX) or rmdir'd (Windows
/// directory junctions), never followed — a link out of the tree must not
/// let removal escape it.
pub fn removeTree(allocator: std.mem.Allocator, path: []const u8) !void {
    const z = try allocator.dupeZ(u8, path);
    defer allocator.free(z);
    const st = platform.lstatPath(z) orelse return;
    if (st.is_symlink) {
        if (st.is_dir) return rmdirRetry(z);
        return unlinkRetry(z, null);
    }
    if (!st.is_dir) return unlinkRetry(z, null);
    return removeTreeInner(allocator, path, z);
}

fn removeTreeInner(allocator: std.mem.Allocator, dir: []const u8, dir_z: [:0]const u8) !void {
    var names = (try collectNames(allocator, dir_z)) orelse blk: {
        // An unreadable directory (POSIX --x or worse): make it
        // traversable and retry once before giving up.
        platform.makeWritable(dir_z);
        break :blk (try collectNames(allocator, dir_z)) orelse return error.RemoveFailed;
    };
    defer freeNames(allocator, &names);

    for (names.items) |name| {
        const child = try join(allocator, dir, name);
        defer allocator.free(child);
        const child_z = try allocator.dupeZ(u8, child);
        defer allocator.free(child_z);

        const st = platform.lstatPath(child_z) orelse continue;
        if (st.is_symlink) {
            if (st.is_dir) {
                try rmdirRetry(child_z);
            } else {
                try unlinkRetry(child_z, dir_z);
            }
        } else if (st.is_dir) {
            try removeTreeInner(allocator, child, child_z);
        } else {
            try unlinkRetry(child_z, dir_z);
        }
    }

    try rmdirRetry(dir_z);
}

/// `find root [-maxdepth 1] -name '*<suffix>'` for regular files: returns
/// '/'-joined paths relative to root (a top-level match is just the file
/// name). Symlinks to regular files count as matches (find matches names,
/// and the install pipeline copies/removes their content counterpart);
/// directory symlinks are never descended. A missing or unreadable root
/// yields an empty list, like the old `find … | catch return` call sites;
/// unreadable subdirectories are skipped.
pub fn collectFilesWithSuffix(
    allocator: std.mem.Allocator,
    root: []const u8,
    suffix: []const u8,
    recursive: bool,
) !std.ArrayList([]u8) {
    var out: std.ArrayList([]u8) = .empty;
    errdefer freePathList(allocator, &out);
    try collectSuffixInner(allocator, root, "", suffix, recursive, &out);
    return out;
}

pub fn freePathList(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |p| allocator.free(p);
    list.deinit(allocator);
}

fn collectSuffixInner(
    allocator: std.mem.Allocator,
    dir: []const u8,
    rel_prefix: []const u8,
    suffix: []const u8,
    recursive: bool,
    out: *std.ArrayList([]u8),
) !void {
    const dir_z = try allocator.dupeZ(u8, dir);
    defer allocator.free(dir_z);
    var names = (try collectNames(allocator, dir_z)) orelse return;
    defer freeNames(allocator, &names);

    for (names.items) |name| {
        const child = try join(allocator, dir, name);
        defer allocator.free(child);

        const st = lstat(allocator, child) orelse continue;
        if (st.is_dir and !st.is_symlink) {
            if (recursive) {
                const child_prefix = try std.mem.concat(allocator, u8, &.{ rel_prefix, name, "/" });
                defer allocator.free(child_prefix);
                try collectSuffixInner(allocator, child, child_prefix, suffix, recursive, out);
            }
            continue;
        }
        if (!std.mem.endsWith(u8, name, suffix)) continue;

        const is_match = st.is_file or (st.is_symlink and blk: {
            const child_z = try allocator.dupeZ(u8, child);
            defer allocator.free(child_z);
            const target = platform.statPath(child_z) orelse break :blk false;
            break :blk target.is_file;
        });
        if (!is_match) continue;

        const rel = try std.mem.concat(allocator, u8, &.{ rel_prefix, name });
        out.append(allocator, rel) catch |err| {
            allocator.free(rel);
            return err;
        };
    }
}

// ---------------------------------------------------------------------------
// tests — each builds its tree under the platform temp dir and removes it
// via removeTree (which is itself under test).
// ---------------------------------------------------------------------------

const thottam = @import("thottam.zig");

fn testBase(buf: []u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}/kaappi-thottam-fs-{d}-{s}", .{ platform.tempDir(), platform.getPid(), name });
}

test "makeDirRecursive creates nested directories and is idempotent" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const base = try testBase(&buf, "mkdir");
    defer removeTree(allocator, base) catch {};

    const nested = try std.mem.concat(allocator, u8, &.{ base, "/a/b/c" });
    defer allocator.free(nested);

    try makeDirRecursive(allocator, nested);
    const nested_z = try allocator.dupeZ(u8, nested);
    defer allocator.free(nested_z);
    try std.testing.expect(platform.isDir(nested_z));

    // Idempotent on an existing tree.
    try makeDirRecursive(allocator, nested);
}

test "touchFile creates an empty file and preserves existing content" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const base = try testBase(&buf, "touch");
    defer removeTree(allocator, base) catch {};
    try makeDirRecursive(allocator, base);

    const file = try std.mem.concat(allocator, u8, &.{ base, "/installed.txt" });
    defer allocator.free(file);

    try touchFile(allocator, file);
    try std.testing.expect(thottam.fileExists(allocator, file));

    try thottam.writeFile(allocator, file, "kaappi-json\n");
    try touchFile(allocator, file);
    const content = try thottam.readFile(allocator, file);
    defer allocator.free(content);
    try std.testing.expectEqualStrings("kaappi-json\n", content);
}

test "copyTree merges nested trees and overwrites existing files" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const base = try testBase(&buf, "copytree");
    defer removeTree(allocator, base) catch {};

    const src = try std.mem.concat(allocator, u8, &.{ base, "/src" });
    defer allocator.free(src);
    const dst = try std.mem.concat(allocator, u8, &.{ base, "/dst" });
    defer allocator.free(dst);

    const src_sub = try std.mem.concat(allocator, u8, &.{ src, "/kaappi/deep" });
    defer allocator.free(src_sub);
    try makeDirRecursive(allocator, src_sub);
    const a_src = try std.mem.concat(allocator, u8, &.{ src, "/kaappi/a.sld" });
    defer allocator.free(a_src);
    try thottam.writeFile(allocator, a_src, "A-new");
    const b_src = try std.mem.concat(allocator, u8, &.{ src, "/kaappi/deep/b.sld" });
    defer allocator.free(b_src);
    try thottam.writeFile(allocator, b_src, "B");

    // Pre-existing destination: a stale a.sld to overwrite and an
    // unrelated file that must survive the merge.
    const dst_sub = try std.mem.concat(allocator, u8, &.{ dst, "/kaappi" });
    defer allocator.free(dst_sub);
    try makeDirRecursive(allocator, dst_sub);
    const a_dst = try std.mem.concat(allocator, u8, &.{ dst, "/kaappi/a.sld" });
    defer allocator.free(a_dst);
    try thottam.writeFile(allocator, a_dst, "A-old");
    const keep = try std.mem.concat(allocator, u8, &.{ dst, "/keep.txt" });
    defer allocator.free(keep);
    try thottam.writeFile(allocator, keep, "keep");

    try copyTree(allocator, src, dst);

    const a_after = try thottam.readFile(allocator, a_dst);
    defer allocator.free(a_after);
    try std.testing.expectEqualStrings("A-new", a_after);

    const b_dst = try std.mem.concat(allocator, u8, &.{ dst, "/kaappi/deep/b.sld" });
    defer allocator.free(b_dst);
    const b_after = try thottam.readFile(allocator, b_dst);
    defer allocator.free(b_after);
    try std.testing.expectEqualStrings("B", b_after);

    const keep_after = try thottam.readFile(allocator, keep);
    defer allocator.free(keep_after);
    try std.testing.expectEqualStrings("keep", keep_after);
}

test "removeTree deletes read-only files inside read-only directories (git object shape)" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const base = try testBase(&buf, "rmro");

    const pack_dir = try std.mem.concat(allocator, u8, &.{ base, "/.git/objects/pack" });
    defer allocator.free(pack_dir);
    try makeDirRecursive(allocator, pack_dir);
    const pack_file = try std.mem.concat(allocator, u8, &.{ pack_dir, "/pack-abc.pack" });
    defer allocator.free(pack_file);
    try thottam.writeFile(allocator, pack_file, "P");

    const pack_file_z = try allocator.dupeZ(u8, pack_file);
    defer allocator.free(pack_file_z);
    platform.makeReadOnly(pack_file_z);
    const pack_dir_z = try allocator.dupeZ(u8, pack_dir);
    defer allocator.free(pack_dir_z);
    platform.makeReadOnly(pack_dir_z);

    try removeTree(allocator, base);
    const base_z = try allocator.dupeZ(u8, base);
    defer allocator.free(base_z);
    try std.testing.expect(!platform.pathExists(base_z));
}

test "removeTree on a missing path succeeds like rm -rf" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const base = try testBase(&buf, "rmmissing");
    try removeTree(allocator, base);
}

test "removeTree unlinks symlinks without following them (POSIX)" {
    if (comptime !platform.is_windows and builtin.os.tag != .wasi) {
        const c = struct {
            extern "c" fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int;
        };
        const allocator = std.testing.allocator;
        var buf: [512]u8 = undefined;
        const base = try testBase(&buf, "rmlink");
        defer removeTree(allocator, base) catch {};

        const outside = try std.mem.concat(allocator, u8, &.{ base, "/outside" });
        defer allocator.free(outside);
        try makeDirRecursive(allocator, outside);
        const precious = try std.mem.concat(allocator, u8, &.{ outside, "/precious.txt" });
        defer allocator.free(precious);
        try thottam.writeFile(allocator, precious, "keep me");

        const tree = try std.mem.concat(allocator, u8, &.{ base, "/tree" });
        defer allocator.free(tree);
        try makeDirRecursive(allocator, tree);
        const link = try std.mem.concat(allocator, u8, &.{ tree, "/escape" });
        defer allocator.free(link);
        const outside_z = try allocator.dupeZ(u8, outside);
        defer allocator.free(outside_z);
        const link_z = try allocator.dupeZ(u8, link);
        defer allocator.free(link_z);
        try std.testing.expect(c.symlink(outside_z, link_z) == 0);

        try removeTree(allocator, tree);

        // The link is gone with the tree; its target survived untouched.
        const tree_z = try allocator.dupeZ(u8, tree);
        defer allocator.free(tree_z);
        try std.testing.expect(!platform.pathExists(tree_z));
        try std.testing.expect(thottam.fileExists(allocator, precious));
    } else return error.SkipZigTest;
}

test "copyTree skips symlinks instead of following them (POSIX)" {
    if (comptime !platform.is_windows and builtin.os.tag != .wasi) {
        const c = struct {
            extern "c" fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int;
        };
        const allocator = std.testing.allocator;
        var buf: [512]u8 = undefined;
        const base = try testBase(&buf, "cplink");
        defer removeTree(allocator, base) catch {};

        const outside = try std.mem.concat(allocator, u8, &.{ base, "/outside.txt" });
        defer allocator.free(outside);
        try makeDirRecursive(allocator, base);
        try thottam.writeFile(allocator, outside, "secret");

        const src = try std.mem.concat(allocator, u8, &.{ base, "/src" });
        defer allocator.free(src);
        try makeDirRecursive(allocator, src);
        const real = try std.mem.concat(allocator, u8, &.{ src, "/real.sld" });
        defer allocator.free(real);
        try thottam.writeFile(allocator, real, "R");
        const link = try std.mem.concat(allocator, u8, &.{ src, "/leak.sld" });
        defer allocator.free(link);
        const outside_z = try allocator.dupeZ(u8, outside);
        defer allocator.free(outside_z);
        const link_z = try allocator.dupeZ(u8, link);
        defer allocator.free(link_z);
        try std.testing.expect(c.symlink(outside_z, link_z) == 0);

        const dst = try std.mem.concat(allocator, u8, &.{ base, "/dst" });
        defer allocator.free(dst);
        try copyTree(allocator, src, dst);

        const real_dst = try std.mem.concat(allocator, u8, &.{ dst, "/real.sld" });
        defer allocator.free(real_dst);
        try std.testing.expect(thottam.fileExists(allocator, real_dst));
        const leak_dst = try std.mem.concat(allocator, u8, &.{ dst, "/leak.sld" });
        defer allocator.free(leak_dst);
        try std.testing.expect(!thottam.fileExists(allocator, leak_dst));
    } else return error.SkipZigTest;
}

test "collectFilesWithSuffix: recursive relative paths and top-level-only mode" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const base = try testBase(&buf, "collect");
    defer removeTree(allocator, base) catch {};

    const sub = try std.mem.concat(allocator, u8, &.{ base, "/kaappi/net" });
    defer allocator.free(sub);
    try makeDirRecursive(allocator, sub);
    inline for (.{ "top.sld", "kaappi/json.sld", "kaappi/net/tls.sld", "kaappi/readme.txt" }) |rel| {
        const p = try std.mem.concat(allocator, u8, &.{ base, "/", rel });
        defer allocator.free(p);
        try thottam.writeFile(allocator, p, "x");
    }

    var found = try collectFilesWithSuffix(allocator, base, ".sld", true);
    defer freePathList(allocator, &found);
    try std.testing.expectEqual(@as(usize, 3), found.items.len);
    for ([_][]const u8{ "top.sld", "kaappi/json.sld", "kaappi/net/tls.sld" }) |want| {
        var seen = false;
        for (found.items) |got| {
            if (std.mem.eql(u8, got, want)) seen = true;
        }
        try std.testing.expect(seen);
    }

    var top_only = try collectFilesWithSuffix(allocator, base, ".sld", false);
    defer freePathList(allocator, &top_only);
    try std.testing.expectEqual(@as(usize, 1), top_only.items.len);
    try std.testing.expectEqualStrings("top.sld", top_only.items[0]);

    var missing = try collectFilesWithSuffix(allocator, "/nonexistent/kaappi-fs-test", ".sld", true);
    defer freePathList(allocator, &missing);
    try std.testing.expectEqual(@as(usize, 0), missing.items.len);
}
