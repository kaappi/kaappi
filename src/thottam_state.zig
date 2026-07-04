const std = @import("std");
const thottam = @import("thottam.zig");

pub const PkgSpec = struct {
    name: []const u8,
    ver: ?[]const u8,
    source: ?[]const u8,
};

pub const PkgManifest = struct {
    name: ?[]const u8 = null,
    depends: ?[]const u8 = null,
    build_cmd: ?[]const u8 = null,
    source: ?[]const u8 = null,
    owned: bool = false,

    pub fn deinit(self: PkgManifest, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        if (self.name) |n| allocator.free(n);
        if (self.depends) |d| allocator.free(d);
        if (self.build_cmd) |b| allocator.free(b);
        if (self.source) |s| allocator.free(s);
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
        return .{ .name = name_ver[0..at], .ver = name_ver[at + 1 ..], .source = source };
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
        if (parseField(line, "name:")) |val| {
            result.name = val;
        } else if (parseField(line, "depends:")) |val| {
            result.depends = val;
        } else if (parseField(line, "build:")) |val| {
            result.build_cmd = val;
        } else if (parseField(line, "source:")) |val| {
            if (val.len > 0 and val[0] != '-') result.source = val;
        }
    }
    return result;
}

pub fn isInstalled(allocator: std.mem.Allocator, installed_path: []const u8, pkg: []const u8) bool {
    const content = thottam.readFile(allocator, installed_path) catch return false;
    defer allocator.free(content);
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, pkg)) return true;
    }
    return false;
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
        if (std.mem.startsWith(u8, line, pkg) and line.len > pkg.len and line[pkg.len] == ' ') {
            const rest = line[pkg.len + 1 ..];
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

pub fn getLockedSha(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8) ?[]const u8 {
    const entry = getLockedEntry(allocator, lockfile_path, pkg) orelse return null;
    if (entry.source) |s| allocator.free(s);
    return entry.sha;
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
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, pkg) and line.len > pkg.len and line[pkg.len] == ' ') {
                try appendLockEntry(&output, allocator, pkg, sha, source);
                found = true;
            } else {
                output.appendSlice(allocator, line) catch return error.OutOfMemory;
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
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, pkg) and line.len > pkg.len and line[pkg.len] == ' ') continue;
        output.appendSlice(allocator, line) catch return error.OutOfMemory;
        output.append(allocator, '\n') catch return error.OutOfMemory;
    }

    try thottam.writeFile(allocator, lockfile_path, output.items);
}

pub fn removeFromInstalled(allocator: std.mem.Allocator, installed_path: []const u8, pkg: []const u8) !void {
    const content = thottam.readFile(allocator, installed_path) catch return;
    defer allocator.free(content);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, pkg)) continue;
        output.appendSlice(allocator, line) catch return error.OutOfMemory;
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

test "parsePkgManifest — full" {
    const content = "name: kaappi-web\ndepends: kaappi-http kaappi-json\nbuild: make\n";
    const m = parsePkgManifest(content);
    try std.testing.expectEqualStrings("kaappi-web", m.name.?);
    try std.testing.expectEqualStrings("kaappi-http kaappi-json", m.depends.?);
    try std.testing.expectEqualStrings("make", m.build_cmd.?);
    try std.testing.expect(m.source == null);
}

test "parsePkgManifest — minimal" {
    const content = "name: kaappi-json\n";
    const m = parsePkgManifest(content);
    try std.testing.expectEqualStrings("kaappi-json", m.name.?);
    try std.testing.expect(m.depends == null);
    try std.testing.expect(m.build_cmd == null);
    try std.testing.expect(m.source == null);
}

test "parsePkgManifest — with source" {
    const content = "name: kaappi-matrix\ndepends: kaappi-net\nsource: https://github.com/alice/kaappi-matrix\n";
    const m = parsePkgManifest(content);
    try std.testing.expectEqualStrings("kaappi-matrix", m.name.?);
    try std.testing.expectEqualStrings("kaappi-net", m.depends.?);
    try std.testing.expectEqualStrings("https://github.com/alice/kaappi-matrix", m.source.?);
}

test "parseField" {
    try std.testing.expectEqualStrings("value", parseField("key: value", "key:").?);
    try std.testing.expectEqualStrings("value", parseField("key:  value  ", "key:").?);
    try std.testing.expect(parseField("other: value", "key:") == null);
    try std.testing.expect(parseField("", "key:") == null);
}
