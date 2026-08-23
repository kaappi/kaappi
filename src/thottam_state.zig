const std = @import("std");
const platform = @import("platform.zig");
const thottam = @import("thottam.zig");

pub const PkgSpec = struct {
    name: []const u8,
    ver: ?[]const u8,
    source: ?[]const u8,
};

pub const PkgManifest = struct {
    depends: ?[]const u8 = null,
    build_cmd: ?[]const u8 = null,
    owned: bool = false,

    pub fn deinit(self: PkgManifest, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        if (self.depends) |d| allocator.free(d);
        if (self.build_cmd) |b| allocator.free(b);
    }
};

pub fn parsePkgSpec(spec: []const u8) PkgSpec {
    var name_ver = spec;
    var source: ?[]const u8 = null;
    if (std.mem.indexOf(u8, spec, "::")) |sep| {
        name_ver = spec[0..sep];
        const url = spec[sep + 2 ..];
        if (url.len > 0 and url[0] != '-') {
            source = url;
        }
    }
    if (std.mem.indexOfScalar(u8, name_ver, '@')) |at| {
        const ver = name_ver[at + 1 ..];
        // `pkg@` (trailing @ with nothing after it) means "no version pinned",
        // the same as omitting the @ entirely — an empty string here printed
        // as `Installing pkg@` and then failed at checkout (kaappi#2132).
        return .{ .name = name_ver[0..at], .ver = if (ver.len > 0) ver else null, .source = source };
    }
    return .{ .name = name_ver, .ver = null, .source = source };
}

pub fn isValidPkgName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') return false;
    }
    return true;
}

pub fn parseField(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, line, prefix)) {
        return std.mem.trim(u8, line[prefix.len..], " \t\r");
    }
    return null;
}

pub fn parsePkgManifest(content: []const u8) PkgManifest {
    var result: PkgManifest = .{};
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        if (parseField(line, "depends:")) |val| {
            result.depends = val;
        } else if (parseField(line, "build:")) |val| {
            // An empty `build:` is an absence, not a command — running
            // `/bin/sh -c ""` behind a "Building <pkg>..." banner helped
            // nobody (kaappi#2132).
            if (val.len > 0) result.build_cmd = val;
        }
    }
    return result;
}

pub fn isInstalled(allocator: std.mem.Allocator, installed_path: []const u8, pkg: []const u8) bool {
    const content = thottam.readFile(allocator, installed_path) catch return false;
    defer allocator.free(content);
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, thottam.trimStateLine(line), pkg)) return true;
    }
    return false;
}

/// Record `pkg` in installed.txt unless it is already listed. A re-install
/// that re-checkouts a different version falls through to the full install
/// flow with the package already listed, and must not grow a duplicate line
/// (issue #2134).
pub fn addToInstalled(allocator: std.mem.Allocator, installed_path: []const u8, pkg: []const u8) !void {
    if (isInstalled(allocator, installed_path, pkg)) return;
    try thottam.appendFile(allocator, installed_path, pkg);
}

pub const LockEntry = struct {
    sha: []const u8,
    source: ?[]const u8,
};

pub fn getLockedEntry(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8) ?LockEntry {
    const content = thottam.readFile(allocator, lockfile_path) catch return null;
    defer allocator.free(content);
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const l = thottam.trimStateLine(line);
        if (std.mem.startsWith(u8, l, pkg) and l.len > pkg.len and l[pkg.len] == ' ') {
            const rest = l[pkg.len + 1 ..];
            if (std.mem.indexOfScalar(u8, rest, ' ')) |sp| {
                return .{
                    .sha = allocator.dupe(u8, rest[0..sp]) catch return null,
                    .source = allocator.dupe(u8, rest[sp + 1 ..]) catch null,
                };
            }
            return .{
                .sha = allocator.dupe(u8, rest) catch return null,
                .source = null,
            };
        }
    }
    return null;
}

pub fn appendLockEntry(output: *std.ArrayList(u8), allocator: std.mem.Allocator, pkg: []const u8, sha: []const u8, source: ?[]const u8) !void {
    output.appendSlice(allocator, pkg) catch return error.OutOfMemory;
    output.append(allocator, ' ') catch return error.OutOfMemory;
    output.appendSlice(allocator, sha) catch return error.OutOfMemory;
    if (source) |s| {
        output.append(allocator, ' ') catch return error.OutOfMemory;
        output.appendSlice(allocator, s) catch return error.OutOfMemory;
    }
    output.append(allocator, '\n') catch return error.OutOfMemory;
}

pub fn updateLockfile(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8, sha: []const u8, source: ?[]const u8) !void {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var found = false;

    if (thottam.readFile(allocator, lockfile_path)) |content| {
        defer allocator.free(content);
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const l = thottam.trimStateLine(line);
            if (l.len == 0) continue;
            if (std.mem.startsWith(u8, l, pkg) and l.len > pkg.len and l[pkg.len] == ' ') {
                try appendLockEntry(&output, allocator, pkg, sha, source);
                found = true;
            } else {
                output.appendSlice(allocator, l) catch return error.OutOfMemory;
                output.append(allocator, '\n') catch return error.OutOfMemory;
            }
        }
    } else |_| {}

    if (!found) {
        try appendLockEntry(&output, allocator, pkg, sha, source);
    }

    try thottam.writeFile(allocator, lockfile_path, output.items);
}

pub fn removeFromLockfile(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8) !void {
    const content = thottam.readFile(allocator, lockfile_path) catch return;
    defer allocator.free(content);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const l = thottam.trimStateLine(line);
        if (l.len == 0) continue;
        if (std.mem.startsWith(u8, l, pkg) and l.len > pkg.len and l[pkg.len] == ' ') continue;
        output.appendSlice(allocator, l) catch return error.OutOfMemory;
        output.append(allocator, '\n') catch return error.OutOfMemory;
    }

    try thottam.writeFile(allocator, lockfile_path, output.items);
}

// ---------------------------------------------------------------------------
// Installed-file manifest (`thottam.files`)
// ---------------------------------------------------------------------------
//
// One line per installed file: `<package> <relative-path>`, where the path
// is relative to `$KAAPPI_HOME/lib` and '/'-joined (the spelling
// `collectFilesWithSuffix` produces, and `joinPath` consumes). Written at
// install time so `remove` can unlink only files no other installed package
// claims — before this record existed, removal walked the package's own
// source tree and deleted a shared file out from under a still-installed
// neighbour (issue #2136).

pub fn updateFileManifest(allocator: std.mem.Allocator, manifest_path: []const u8, pkg: []const u8, files: []const []const u8) !void {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    // Drop the package's own stale lines first (a re-install at a new
    // version, or an upstream rename, must not leave old entries behind),
    // then append the current set.
    if (thottam.readFile(allocator, manifest_path)) |content| {
        defer allocator.free(content);
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const l = thottam.trimStateLine(line);
            if (l.len == 0) continue;
            if (std.mem.startsWith(u8, l, pkg) and l.len > pkg.len and l[pkg.len] == ' ') continue;
            output.appendSlice(allocator, l) catch return error.OutOfMemory;
            output.append(allocator, '\n') catch return error.OutOfMemory;
        }
    } else |_| {}

    for (files) |rel| {
        output.appendSlice(allocator, pkg) catch return error.OutOfMemory;
        output.append(allocator, ' ') catch return error.OutOfMemory;
        output.appendSlice(allocator, rel) catch return error.OutOfMemory;
        output.append(allocator, '\n') catch return error.OutOfMemory;
    }

    try thottam.writeFile(allocator, manifest_path, output.items);
}

pub fn removeFromFileManifest(allocator: std.mem.Allocator, manifest_path: []const u8, pkg: []const u8) !void {
    const content = thottam.readFile(allocator, manifest_path) catch return;
    defer allocator.free(content);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const l = thottam.trimStateLine(line);
        if (l.len == 0) continue;
        if (std.mem.startsWith(u8, l, pkg) and l.len > pkg.len and l[pkg.len] == ' ') continue;
        output.appendSlice(allocator, l) catch return error.OutOfMemory;
        output.append(allocator, '\n') catch return error.OutOfMemory;
    }

    try thottam.writeFile(allocator, manifest_path, output.items);
}

/// Return an owned copy of the first installed package other than `except`
/// whose manifest claims `rel`, or null when nobody else claims it. The
/// claim record is the manifest, so a package installed before the record
/// existed cannot protect its files — the guarantee holds for installs made
/// after this record is written (issue #2136).
pub fn fileClaimedBy(allocator: std.mem.Allocator, manifest_path: []const u8, rel: []const u8, except: []const u8) ?[]u8 {
    const content = thottam.readFile(allocator, manifest_path) catch return null;
    defer allocator.free(content);
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const l = thottam.trimStateLine(line);
        if (l.len == 0) continue;
        const sp = std.mem.indexOfScalar(u8, l, ' ') orelse continue;
        const owner = l[0..sp];
        if (std.mem.eql(u8, owner, except)) continue;
        if (std.mem.eql(u8, l[sp + 1 ..], rel)) {
            return allocator.dupe(u8, owner) catch null;
        }
    }
    return null;
}

pub fn removeFromInstalled(allocator: std.mem.Allocator, installed_path: []const u8, pkg: []const u8) !void {
    const content = thottam.readFile(allocator, installed_path) catch return;
    defer allocator.free(content);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const l = thottam.trimStateLine(line);
        if (l.len == 0) continue;
        if (std.mem.eql(u8, l, pkg)) continue;
        output.appendSlice(allocator, l) catch return error.OutOfMemory;
        output.append(allocator, '\n') catch return error.OutOfMemory;
    }

    try thottam.writeFile(allocator, installed_path, output.items);
}

test "parsePkgSpec — no version" {
    const spec = parsePkgSpec("kaappi-json");
    try std.testing.expectEqualStrings("kaappi-json", spec.name);
    try std.testing.expect(spec.ver == null);
    try std.testing.expect(spec.source == null);
}

test "parsePkgSpec — with version" {
    const spec = parsePkgSpec("kaappi-web@v1.0.0");
    try std.testing.expectEqualStrings("kaappi-web", spec.name);
    try std.testing.expectEqualStrings("v1.0.0", spec.ver.?);
    try std.testing.expect(spec.source == null);
}

test "parsePkgSpec — with SHA" {
    const spec = parsePkgSpec("foo@abc123");
    try std.testing.expectEqualStrings("foo", spec.name);
    try std.testing.expectEqualStrings("abc123", spec.ver.?);
    try std.testing.expect(spec.source == null);
}

test "parsePkgSpec — with source URL" {
    const spec = parsePkgSpec("kaappi-auth::https://github.com/bob/kaappi-auth");
    try std.testing.expectEqualStrings("kaappi-auth", spec.name);
    try std.testing.expect(spec.ver == null);
    try std.testing.expectEqualStrings("https://github.com/bob/kaappi-auth", spec.source.?);
}

test "parsePkgSpec — version and source URL" {
    const spec = parsePkgSpec("pkg@v1.0::https://github.com/a/b");
    try std.testing.expectEqualStrings("pkg", spec.name);
    try std.testing.expectEqualStrings("v1.0", spec.ver.?);
    try std.testing.expectEqualStrings("https://github.com/a/b", spec.source.?);
}

test "parsePkgManifest — depends and build only" {
    const content = "name: kaappi-web\nsource: https://github.com/alice/kaappi-web\nversion: 9.9.9\ndepends: kaappi-http kaappi-json\nbuild: make\n";
    const m = parsePkgManifest(content);
    // Only depends and build are read; name, source, version and any other
    // key are ignored (issue #2138).
    try std.testing.expectEqualStrings("kaappi-http kaappi-json", m.depends.?);
    try std.testing.expectEqualStrings("make", m.build_cmd.?);
}

test "parsePkgManifest — minimal" {
    const content = "depends: kaappi-json\n";
    const m = parsePkgManifest(content);
    try std.testing.expectEqualStrings("kaappi-json", m.depends.?);
    try std.testing.expect(m.build_cmd == null);
}

test "parsePkgManifest — ignores name, source and version keys" {
    // The fields the manifest grammar no longer documents are ignored like
    // any unknown key (issue #2138).
    const content = "name: WRONG-NAME-ENTIRELY\nsource: https://evil.example.com/not-this-repo\nversion: 99.99.99\ndepends: kaappi-net\n";
    const m = parsePkgManifest(content);
    try std.testing.expectEqualStrings("kaappi-net", m.depends.?);
    try std.testing.expect(m.build_cmd == null);
}

test "parseField" {
    try std.testing.expectEqualStrings("value", parseField("key: value", "key:").?);
    try std.testing.expectEqualStrings("value", parseField("key:  value  ", "key:").?);
    try std.testing.expect(parseField("other: value", "key:") == null);
    try std.testing.expect(parseField("", "key:") == null);
}

test "addToInstalled is idempotent" {
    const allocator = std.testing.allocator;
    var tmp: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&tmp, "{s}/kaappi-thottam-state-{d}-{s}", .{ platform.tempDir(), platform.getPid(), "addinst" });
    defer thottam.removeDir(allocator, path) catch {};

    try addToInstalled(allocator, path, "kaappi-one");
    try addToInstalled(allocator, path, "kaappi-one");
    const content = try thottam.readFile(allocator, path);
    defer allocator.free(content);
    try std.testing.expectEqualStrings("kaappi-one\n", content);
}

test "updateFileManifest rewrites a package's lines in place" {
    const allocator = std.testing.allocator;
    var tmp: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&tmp, "{s}/kaappi-thottam-state-{d}-{s}", .{ platform.tempDir(), platform.getPid(), "fmanifest" });
    defer thottam.removeDir(allocator, path) catch {};

    try updateFileManifest(allocator, path, "kaappi-one", &.{ "kaappi/one.sld", "kaappi/shared.sld" });
    try updateFileManifest(allocator, path, "kaappi-two", &.{ "kaappi/two.sld", "kaappi/shared.sld" });

    // A re-install at a new version rewrites only the package's own lines.
    try updateFileManifest(allocator, path, "kaappi-two", &.{"kaappi/two.sld"});
    const content = try thottam.readFile(allocator, path);
    defer allocator.free(content);
    try std.testing.expectEqualStrings(
        "kaappi-one kaappi/one.sld\nkaappi-one kaappi/shared.sld\nkaappi-two kaappi/two.sld\n",
        content,
    );

    // An empty file list drops the package's lines entirely (a removal's
    // worth of cleanup), but nobody else's.
    try updateFileManifest(allocator, path, "kaappi-one", &.{});
    const after = try thottam.readFile(allocator, path);
    defer allocator.free(after);
    try std.testing.expectEqualStrings("kaappi-two kaappi/two.sld\n", after);
}

test "fileClaimedBy finds the other claimant and skips the package itself" {
    const allocator = std.testing.allocator;
    var tmp: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&tmp, "{s}/kaappi-thottam-state-{d}-{s}", .{ platform.tempDir(), platform.getPid(), "claim" });
    defer thottam.removeDir(allocator, path) catch {};

    try updateFileManifest(allocator, path, "kaappi-one", &.{ "kaappi/one.sld", "kaappi/shared.sld" });
    try updateFileManifest(allocator, path, "kaappi-two", &.{ "kaappi/two.sld", "kaappi/shared.sld" });

    const other = fileClaimedBy(allocator, path, "kaappi/shared.sld", "kaappi-two").?;
    defer allocator.free(other);
    try std.testing.expectEqualStrings("kaappi-one", other);

    // Excluding the only claimant: nobody else claims it.
    try std.testing.expect(fileClaimedBy(allocator, path, "kaappi/two.sld", "kaappi-two") == null);
    // An unclaimed path is null.
    try std.testing.expect(fileClaimedBy(allocator, path, "kaappi/other.sld", "kaappi-one") == null);
}

test "removeFromFileManifest drops only the named package's lines" {
    const allocator = std.testing.allocator;
    var tmp: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&tmp, "{s}/kaappi-thottam-state-{d}-{s}", .{ platform.tempDir(), platform.getPid(), "rmmanifest" });
    defer thottam.removeDir(allocator, path) catch {};

    try updateFileManifest(allocator, path, "kaappi-one", &.{ "kaappi/one.sld", "kaappi/shared.sld" });
    try updateFileManifest(allocator, path, "kaappi-two", &.{ "kaappi/two.sld", "kaappi/shared.sld" });
    try removeFromFileManifest(allocator, path, "kaappi-two");

    const content = try thottam.readFile(allocator, path);
    defer allocator.free(content);
    try std.testing.expectEqualStrings(
        "kaappi-one kaappi/one.sld\nkaappi-one kaappi/shared.sld\n",
        content,
    );
}
