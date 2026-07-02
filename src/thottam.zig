const std = @import("std");
const builtin = @import("builtin");

const dylib_ext = if (builtin.os.tag == .macos) ".dylib" else ".so";
const version = "0.11.0";

var use_color: bool = false;

const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const green = "\x1b[32m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
    const dim = "\x1b[2m";
};

fn initColor() void {
    use_color = std.c.isatty(1) != 0;
}

const Config = struct {
    home: []const u8,
    org: []const u8,
    lib_dir: []const u8,
    src_dir: []const u8,
    installed: []const u8,
    lockfile: []const u8,
};

const PkgSpec = struct {
    name: []const u8,
    ver: ?[]const u8,
    source: ?[]const u8,
};

const PkgManifest = struct {
    name: ?[]const u8 = null,
    depends: ?[]const u8 = null,
    build_cmd: ?[]const u8 = null,
    source: ?[]const u8 = null,
    owned: bool = false,

    fn deinit(self: PkgManifest, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        if (self.name) |n| allocator.free(n);
        if (self.depends) |d| allocator.free(d);
        if (self.build_cmd) |b| allocator.free(b);
        if (self.source) |s| allocator.free(s);
    }
};

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        if (result <= 0) break;
        total += @as(usize, @intCast(result));
    }
}

fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

fn fatal(msg: []const u8) noreturn {
    if (use_color) writeStderr(Color.red ++ Color.bold);
    writeStderr("error: ");
    if (use_color) writeStderr(Color.reset ++ Color.red);
    writeStderr(msg);
    if (use_color) writeStderr(Color.reset);
    writeStderr("\n");
    std.process.exit(1);
}

fn parsePkgSpec(spec: []const u8) PkgSpec {
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

fn isValidPkgName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') return false;
    }
    return true;
}

fn parseField(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, line, prefix)) {
        return std.mem.trim(u8, line[prefix.len..], " \t\r");
    }
    return null;
}

fn parsePkgManifest(content: []const u8) PkgManifest {
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

const Semver = struct {
    major: u32,
    minor: u32,
    patch: u32,

    fn parse(s: []const u8) ?Semver {
        const ver = if (s.len > 0 and s[0] == 'v') s[1..] else s;
        var it = std.mem.splitScalar(u8, ver, '.');
        const major = std.fmt.parseInt(u32, it.next() orelse return null, 10) catch return null;
        const minor = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch return null;
        const patch = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch return null;
        return .{ .major = major, .minor = minor, .patch = patch };
    }

    fn order(a: Semver, b: Semver) std.math.Order {
        if (a.major != b.major) return std.math.order(a.major, b.major);
        if (a.minor != b.minor) return std.math.order(a.minor, b.minor);
        return std.math.order(a.patch, b.patch);
    }
};

const ConstraintOp = enum { gte, gt, lte, lt, eq, caret, tilde };

const Constraint = struct {
    op: ConstraintOp,
    ver: Semver,

    fn matches(self: Constraint, v: Semver) bool {
        return switch (self.op) {
            .gte => Semver.order(v, self.ver) != .lt,
            .gt => Semver.order(v, self.ver) == .gt,
            .lte => Semver.order(v, self.ver) != .gt,
            .lt => Semver.order(v, self.ver) == .lt,
            .eq => Semver.order(v, self.ver) == .eq,
            .caret => blk: {
                if (Semver.order(v, self.ver) == .lt) break :blk false;
                if (self.ver.major != 0) break :blk v.major == self.ver.major;
                if (self.ver.minor != 0) break :blk v.major == 0 and v.minor == self.ver.minor;
                break :blk v.major == 0 and v.minor == 0 and v.patch == self.ver.patch;
            },
            .tilde => v.major == self.ver.major and v.minor == self.ver.minor and Semver.order(v, self.ver) != .lt,
        };
    }
};

fn parseConstraints(spec: []const u8) ?[4]?Constraint {
    var result: [4]?Constraint = .{ null, null, null, null };
    const clean = std.mem.trim(u8, spec, "\"");
    var it = std.mem.splitScalar(u8, clean, ',');
    var i: usize = 0;
    while (it.next()) |part| {
        if (i >= 4) return null;
        const trimmed = std.mem.trim(u8, part, " ");
        result[i] = parseSingleConstraint(trimmed) orelse return null;
        i += 1;
    }
    if (i == 0) return null;
    return result;
}

fn parseSingleConstraint(s: []const u8) ?Constraint {
    if (s.len == 0) return null;
    if (s[0] == '^') {
        const ver = Semver.parse(s[1..]) orelse return null;
        return .{ .op = .caret, .ver = ver };
    }
    if (s[0] == '~') {
        const ver = Semver.parse(s[1..]) orelse return null;
        return .{ .op = .tilde, .ver = ver };
    }
    if (std.mem.startsWith(u8, s, ">=")) {
        const ver = Semver.parse(s[2..]) orelse return null;
        return .{ .op = .gte, .ver = ver };
    }
    if (std.mem.startsWith(u8, s, "<=")) {
        const ver = Semver.parse(s[2..]) orelse return null;
        return .{ .op = .lte, .ver = ver };
    }
    if (s[0] == '>') {
        const ver = Semver.parse(s[1..]) orelse return null;
        return .{ .op = .gt, .ver = ver };
    }
    if (s[0] == '<') {
        const ver = Semver.parse(s[1..]) orelse return null;
        return .{ .op = .lt, .ver = ver };
    }
    const ver = Semver.parse(s) orelse return null;
    return .{ .op = .eq, .ver = ver };
}

fn matchesAllConstraints(v: Semver, constraints: [4]?Constraint) bool {
    for (constraints) |mc| {
        const c = mc orelse continue;
        if (!c.matches(v)) return false;
    }
    return true;
}

fn resolveVersion(allocator: std.mem.Allocator, clone_url: []const u8, constraint_str: []const u8) ?[]const u8 {
    const constraints = parseConstraints(constraint_str) orelse return null;

    const output = runGitCapture(allocator, &.{ "ls-remote", "--tags", "--", clone_url }) catch return null;
    defer allocator.free(output);

    var best: ?Semver = null;
    var best_tag: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const tab_idx = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const ref = line[tab_idx + 1 ..];
        const tag = if (std.mem.startsWith(u8, ref, "refs/tags/"))
            ref["refs/tags/".len..]
        else
            continue;
        if (std.mem.endsWith(u8, tag, "^{}")) continue;

        const sv = Semver.parse(tag) orelse continue;
        if (!matchesAllConstraints(sv, constraints)) continue;

        if (best) |b| {
            if (Semver.order(sv, b) == .gt) {
                best = sv;
                best_tag = tag;
            }
        } else {
            best = sv;
            best_tag = tag;
        }
    }

    if (best_tag) |bt| {
        return allocator.dupe(u8, bt) catch return null;
    }
    return null;
}

fn isConstraintSpec(ver: []const u8) bool {
    if (ver.len == 0) return false;
    const clean = std.mem.trim(u8, ver, "\"");
    if (clean.len == 0) return false;
    return clean[0] == '>' or clean[0] == '<' or clean[0] == '^' or clean[0] == '~';
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch return error.FileNotFound;
    defer _ = std.posix.system.close(fd);
    var buf: std.ArrayList(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &tmp) catch {
            buf.deinit(allocator);
            return error.ReadFailed;
        };
        if (n == 0) break;
        buf.appendSlice(allocator, tmp[0..n]) catch return error.OutOfMemory;
    }
    return buf.toOwnedSlice(allocator);
}

fn writeFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch return error.CannotOpen;
    defer _ = std.posix.system.close(fd);
    var total: usize = 0;
    while (total < content.len) {
        const result = std.posix.system.write(fd, content.ptr + total, content.len - total);
        if (result <= 0) return error.WriteFailed;
        total += @as(usize, @intCast(result));
    }
}

fn appendFile(allocator: std.mem.Allocator, path: []const u8, line: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .APPEND = true,
    }, 0o644) catch return error.CannotOpen;
    defer _ = std.posix.system.close(fd);
    _ = std.posix.system.write(fd, line.ptr, line.len);
    _ = std.posix.system.write(fd, "\n", 1);
}

fn fileExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch return false;
    _ = std.posix.system.close(fd);
    return true;
}

fn dirExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{ .DIRECTORY = true }, 0) catch return false;
    _ = std.posix.system.close(fd);
    return true;
}

fn joinPath(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + 1 + b.len);
    @memcpy(result[0..a.len], a);
    result[a.len] = '/';
    @memcpy(result[a.len + 1 ..], b);
    return result;
}

fn joinPath3(allocator: std.mem.Allocator, a: []const u8, b: []const u8, c: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + 1 + b.len + 1 + c.len);
    var pos: usize = 0;
    @memcpy(result[pos..][0..a.len], a);
    pos += a.len;
    result[pos] = '/';
    pos += 1;
    @memcpy(result[pos..][0..b.len], b);
    pos += b.len;
    result[pos] = '/';
    pos += 1;
    @memcpy(result[pos..][0..c.len], c);
    return result;
}

fn runCapture(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) ![]u8 {
    const argv_z = try allocator.alloc(?[*:0]const u8, argv.len + 1);
    @memset(argv_z, null);
    defer {
        for (argv_z) |maybe_ptr| {
            if (maybe_ptr) |p| {
                const len = std.mem.len(p);
                const ptr: [*]u8 = @constCast(p);
                allocator.free(ptr[0 .. len + 1]);
            }
        }
        allocator.free(argv_z);
    }
    for (argv, 0..) |arg, i| {
        argv_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
    }
    argv_z[argv.len] = null;

    const cwd_duped = if (cwd) |c| try allocator.dupeZ(u8, c) else null;
    defer if (cwd_duped) |d| allocator.free(d);
    const cwd_z: ?[*:0]const u8 = if (cwd_duped) |d| d.ptr else null;

    var pipe: [2]c_int = undefined;
    if (std.c.pipe(&pipe) != 0) return error.PipeFailed;

    const pid = std.posix.system.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        // Child
        _ = std.c.close(pipe[0]);
        _ = std.c.dup2(pipe[1], 1);
        _ = std.c.close(pipe[1]);
        const devnull = std.c.open("/dev/null", .{ .ACCMODE = .WRONLY }, @as(c_uint, 0));
        if (devnull >= 0) {
            _ = std.c.dup2(devnull, 2);
            _ = std.c.close(devnull);
        }

        if (cwd_z) |c| {
            _ = std.posix.system.chdir(c);
        }
        _ = std.posix.system.execve(
            @ptrCast(argv_z[0].?),
            @ptrCast(argv_z.ptr),
            @ptrCast(std.c.environ),
        );
        std.process.exit(127);
    }

    // Parent
    _ = std.c.close(pipe[1]);
    var output: std.ArrayList(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(pipe[0], &tmp) catch break;
        if (n == 0) break;
        output.appendSlice(allocator, tmp[0..n]) catch break;
    }
    _ = std.c.close(pipe[0]);

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const raw: c_uint = @bitCast(status);
    const wifexited = (raw & 0x7f) == 0;
    const exit_code: u8 = @intCast((raw >> 8) & 0xff);
    if (!wifexited or exit_code != 0) {
        output.deinit(allocator);
        return error.CommandFailed;
    }

    const slice = output.toOwnedSlice(allocator) catch return error.OutOfMemory;
    defer allocator.free(slice);
    const trimmed = std.mem.trim(u8, slice, "\n\r");
    return allocator.dupe(u8, trimmed) catch return error.OutOfMemory;
}

fn runPassthrough(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) !u8 {
    const argv_z = try allocator.alloc(?[*:0]const u8, argv.len + 1);
    @memset(argv_z, null);
    defer {
        for (argv_z) |maybe_ptr| {
            if (maybe_ptr) |p| {
                const len = std.mem.len(p);
                const ptr: [*]u8 = @constCast(p);
                allocator.free(ptr[0 .. len + 1]);
            }
        }
        allocator.free(argv_z);
    }
    for (argv, 0..) |arg, i| {
        argv_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
    }
    argv_z[argv.len] = null;

    const cwd_duped = if (cwd) |c| try allocator.dupeZ(u8, c) else null;
    defer if (cwd_duped) |d| allocator.free(d);
    const cwd_z: ?[*:0]const u8 = if (cwd_duped) |d| d.ptr else null;

    const pid = std.posix.system.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        if (cwd_z) |c| {
            _ = std.posix.system.chdir(c);
        }
        _ = std.posix.system.execve(
            @ptrCast(argv_z[0].?),
            @ptrCast(argv_z.ptr),
            @ptrCast(std.c.environ),
        );
        std.process.exit(127);
    }

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const raw: c_uint = @bitCast(status);
    const wifexited = (raw & 0x7f) == 0;
    if (!wifexited) return 128 + @as(u8, @intCast(raw & 0x7f));
    return @intCast((raw >> 8) & 0xff);
}

fn runGit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    argv.append(allocator, "/usr/bin/git") catch return error.OutOfMemory;
    for (args) |a| {
        argv.append(allocator, a) catch return error.OutOfMemory;
    }
    const exit_code = try runPassthrough(allocator, argv.items, null);
    if (exit_code != 0) return error.GitFailed;
}

fn runGitCapture(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    argv.append(allocator, "/usr/bin/git") catch return error.OutOfMemory;
    for (args) |a| {
        argv.append(allocator, a) catch return error.OutOfMemory;
    }
    return runCapture(allocator, argv.items, null);
}

fn isInstalled(allocator: std.mem.Allocator, installed_path: []const u8, pkg: []const u8) bool {
    const content = readFile(allocator, installed_path) catch return false;
    defer allocator.free(content);
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, pkg)) return true;
    }
    return false;
}

const LockEntry = struct {
    sha: []const u8,
    source: ?[]const u8,
};

fn getLockedEntry(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8) ?LockEntry {
    const content = readFile(allocator, lockfile_path) catch return null;
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

fn getLockedSha(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8) ?[]const u8 {
    const entry = getLockedEntry(allocator, lockfile_path, pkg) orelse return null;
    if (entry.source) |s| allocator.free(s);
    return entry.sha;
}

fn appendLockEntry(output: *std.ArrayList(u8), allocator: std.mem.Allocator, pkg: []const u8, sha: []const u8, source: ?[]const u8) !void {
    output.appendSlice(allocator, pkg) catch return error.OutOfMemory;
    output.append(allocator, ' ') catch return error.OutOfMemory;
    output.appendSlice(allocator, sha) catch return error.OutOfMemory;
    if (source) |s| {
        output.append(allocator, ' ') catch return error.OutOfMemory;
        output.appendSlice(allocator, s) catch return error.OutOfMemory;
    }
    output.append(allocator, '\n') catch return error.OutOfMemory;
}

fn updateLockfile(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8, sha: []const u8, source: ?[]const u8) !void {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var found = false;

    if (readFile(allocator, lockfile_path)) |content| {
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

    try writeFile(allocator, lockfile_path, output.items);
}

fn removeFromLockfile(allocator: std.mem.Allocator, lockfile_path: []const u8, pkg: []const u8) !void {
    const content = readFile(allocator, lockfile_path) catch return;
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

    try writeFile(allocator, lockfile_path, output.items);
}

fn removeFromInstalled(allocator: std.mem.Allocator, installed_path: []const u8, pkg: []const u8) !void {
    const content = readFile(allocator, installed_path) catch return;
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

    try writeFile(allocator, installed_path, output.items);
}

fn getPkgSha(allocator: std.mem.Allocator, src_dir: []const u8, pkg: []const u8) ?[]const u8 {
    const pkg_dir = joinPath(allocator, src_dir, pkg) catch return null;
    defer allocator.free(pkg_dir);
    const git_dir = joinPath(allocator, pkg_dir, ".git") catch return null;
    defer allocator.free(git_dir);
    if (!dirExists(allocator, git_dir)) return null;
    return runGitCapture(allocator, &.{ "-C", pkg_dir, "rev-parse", "HEAD" }) catch null;
}

fn getPkgManifest(allocator: std.mem.Allocator, src_dir: []const u8, pkg: []const u8) ?PkgManifest {
    const pkg_file = joinPath3(allocator, src_dir, pkg, "kaappi.pkg") catch return null;
    defer allocator.free(pkg_file);
    const content = readFile(allocator, pkg_file) catch return null;
    defer allocator.free(content);
    var m = parsePkgManifest(content);
    m.name = if (m.name) |n| allocator.dupe(u8, n) catch null else null;
    m.depends = if (m.depends) |d| allocator.dupe(u8, d) catch null else null;
    m.build_cmd = if (m.build_cmd) |b| allocator.dupe(u8, b) catch null else null;
    m.source = if (m.source) |s| allocator.dupe(u8, s) catch null else null;
    m.owned = true;
    return m;
}

fn copyDir(allocator: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    const exit_code = try runPassthrough(allocator, &.{ "/bin/cp", "-R", src, dst }, null);
    if (exit_code != 0) return error.CopyFailed;
}

fn removeDir(allocator: std.mem.Allocator, path: []const u8) !void {
    _ = try runPassthrough(allocator, &.{ "/bin/rm", "-rf", path }, null);
}

fn copyDylibsFromPkg(allocator: std.mem.Allocator, pkg_dir: []const u8, lib_dir: []const u8) !u32 {
    const pattern = try std.mem.concat(allocator, u8, &.{ "*", dylib_ext });
    defer allocator.free(pattern);
    const output = runCapture(allocator, &.{
        "/usr/bin/find", pkg_dir, "-maxdepth", "1", "-name", pattern, "-print",
    }, null) catch return 0;
    defer allocator.free(output);
    var count: u32 = 0;
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const basename = std.fs.path.basename(line);
        const dst = joinPath(allocator, lib_dir, basename) catch continue;
        defer allocator.free(dst);
        _ = runPassthrough(allocator, &.{ "/bin/cp", line, dst }, null) catch continue;
        count += 1;
    }
    return count;
}

fn removeDylibsFromPkg(allocator: std.mem.Allocator, pkg_dir: []const u8, lib_dir: []const u8) !void {
    const pattern = try std.mem.concat(allocator, u8, &.{ "*", dylib_ext });
    defer allocator.free(pattern);
    const output = runCapture(allocator, &.{
        "/usr/bin/find", pkg_dir, "-maxdepth", "1", "-name", pattern, "-print",
    }, null) catch return;
    defer allocator.free(output);
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const basename = std.fs.path.basename(line);
        const target = joinPath(allocator, lib_dir, basename) catch continue;
        defer allocator.free(target);
        const target_z = allocator.dupeZ(u8, target) catch continue;
        defer allocator.free(target_z);
        _ = std.posix.system.unlink(target_z);
    }
}

fn removeSldFiles(allocator: std.mem.Allocator, pkg_lib_dir: []const u8, lib_dir: []const u8) !void {
    const output = runCapture(allocator, &.{
        "/usr/bin/find", pkg_lib_dir, "-name", "*.sld", "-print",
    }, null) catch return;
    defer allocator.free(output);
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, pkg_lib_dir)) {
            const rel = line[pkg_lib_dir.len..];
            const target = std.mem.concat(allocator, u8, &.{ lib_dir, rel }) catch continue;
            defer allocator.free(target);
            const target_z = allocator.dupeZ(u8, target) catch continue;
            defer allocator.free(target_z);
            _ = std.posix.system.unlink(target_z);
        }
    }
}

fn printBuf(buf: []u8, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(buf, fmt, args) catch return;
    writeStdout(msg);
}

fn printColor(comptime color: []const u8, text: []const u8) void {
    if (use_color) writeStdout(color);
    writeStdout(text);
    if (use_color) writeStdout(Color.reset);
}

fn printErrColor(comptime color: []const u8, text: []const u8) void {
    if (use_color) writeStderr(color);
    writeStderr(text);
    if (use_color) writeStderr(Color.reset);
}

fn doInstall(
    allocator: std.mem.Allocator,
    config: Config,
    spec: []const u8,
    locked_mode: bool,
    visited: *std.StringHashMap(void),
) !void {
    const parsed = parsePkgSpec(spec);
    const pkg = parsed.name;
    var install_version = parsed.ver;

    if (!isValidPkgName(pkg)) {
        printErrColor(Color.red, "error: ");
        writeStderr("invalid package name '");
        writeStderr(pkg);
        writeStderr("' (only alphanumeric, '-', '_' allowed)\n");
        return error.InvalidPackageName;
    }

    if (visited.get(pkg) != null) return;
    try visited.put(pkg, {});

    if (isInstalled(allocator, config.installed, pkg)) {
        writeStdout("  ");
        printColor(Color.dim, pkg);
        writeStdout(" already installed\n");
        return;
    }

    if (locked_mode) {
        const locked_sha = getLockedSha(allocator, config.lockfile, pkg);
        if (locked_sha == null) {
            var buf: [256]u8 = undefined;
            printErrColor(Color.red, "error: ");
            const msg = std.fmt.bufPrint(&buf, "{s} is not in the lockfile (running in --locked mode)\n", .{pkg}) catch "package not in lockfile\n";
            writeStderr(msg);
            std.process.exit(1);
        }
        install_version = locked_sha;
    }

    if (install_version) |v| {
        if (isConstraintSpec(v)) {
            const clone_url = parsed.source orelse blk: {
                break :blk std.fmt.allocPrint(allocator, "{s}/{s}.git", .{ config.org, pkg }) catch return error.OutOfMemory;
            };
            if (resolveVersion(allocator, clone_url, v)) |resolved| {
                writeStdout("  Resolved ");
                writeStdout(v);
                writeStdout(" -> ");
                writeStdout(resolved);
                writeStdout("\n");
                install_version = resolved;
            } else {
                var buf: [256]u8 = undefined;
                printErrColor(Color.red, "error: ");
                const msg = std.fmt.bufPrint(&buf, "no version matching {s} for {s}\n", .{ v, pkg }) catch "no matching version\n";
                writeStderr(msg);
                return error.GitFailed;
            }
        }
    }

    var buf: [512]u8 = undefined;
    printColor(Color.bold, "Installing ");
    printColor(Color.bold ++ Color.cyan, pkg);
    if (install_version) |v| {
        writeStdout("@");
        writeStdout(v);
    }
    writeStdout("...\n");

    const pkg_dir = try joinPath(allocator, config.src_dir, pkg);
    defer allocator.free(pkg_dir);

    const clone_url = if (parsed.source) |s| s else blk: {
        break :blk std.fmt.bufPrint(&buf, "{s}/{s}.git", .{ config.org, pkg }) catch return error.OutOfMemory;
    };

    if (!dirExists(allocator, pkg_dir)) {
        writeStdout("  Cloning ");
        writeStdout(clone_url);
        writeStdout("...\n");
        const url_copy = try allocator.dupe(u8, clone_url);
        defer allocator.free(url_copy);
        runGit(allocator, &.{ "clone", "--quiet", "--", url_copy, pkg_dir }) catch {
            printErrColor(Color.red, "  Failed to clone repository\n");
            return error.GitFailed;
        };
    }

    if (install_version) |v| {
        printBuf(&buf, "  Checking out {s}...\n", .{v});
        runGit(allocator, &.{ "-C", pkg_dir, "fetch", "--quiet", "--tags" }) catch {};
        runGit(allocator, &.{ "-C", pkg_dir, "checkout", "--quiet", "--", v }) catch {
            printErrColor(Color.red, "  Failed to checkout version\n");
            return error.GitFailed;
        };
    }

    const resolved_sha = getPkgSha(allocator, config.src_dir, pkg) orelse "unknown";
    printBuf(&buf, "  Resolved: {s}\n", .{resolved_sha});

    if (locked_mode) {
        if (getLockedSha(allocator, config.lockfile, pkg)) |locked_sha| {
            defer allocator.free(locked_sha);
            if (!std.mem.eql(u8, resolved_sha, locked_sha)) {
                printErrColor(Color.red, "error: ");
                const msg = std.fmt.bufPrint(&buf, "SHA mismatch for {s} (locked: {s}, got: {s})\n", .{ pkg, locked_sha, resolved_sha }) catch "SHA mismatch\n";
                writeStderr(msg);
                std.process.exit(1);
            }
        }
    }

    if (getPkgManifest(allocator, config.src_dir, pkg)) |manifest| {
        defer manifest.deinit(allocator);
        if (manifest.depends) |deps| {
            var dep_it = std.mem.splitScalar(u8, deps, ' ');
            while (dep_it.next()) |dep| {
                if (dep.len > 0) {
                    try doInstall(allocator, config, dep, locked_mode, visited);
                }
            }
        }

        if (manifest.build_cmd) |build_cmd| {
            printBuf(&buf, "  Building {s}...\n", .{pkg});
            const exit_code = runPassthrough(allocator, &.{ "/bin/sh", "-c", build_cmd }, pkg_dir) catch 1;
            if (exit_code != 0) {
                printErrColor(Color.red, "  Build failed\n");
                return error.BuildFailed;
            }
        }
    }

    const lib_src = try joinPath(allocator, pkg_dir, "lib");
    defer allocator.free(lib_src);
    if (dirExists(allocator, lib_src)) {
        writeStdout("  Installing libraries...\n");
        const src_glob = try std.mem.concat(allocator, u8, &.{ lib_src, "/" });
        defer allocator.free(src_glob);
        const dst_glob = try std.mem.concat(allocator, u8, &.{ config.lib_dir, "/" });
        defer allocator.free(dst_glob);
        _ = runPassthrough(allocator, &.{ "/bin/cp", "-R", src_glob, dst_glob }, null) catch {};
    }

    const dylib_count = try copyDylibsFromPkg(allocator, pkg_dir, config.lib_dir);
    if (dylib_count > 0) {
        printBuf(&buf, "  Installed {d} native library(s)\n", .{dylib_count});
    }

    try appendFile(allocator, config.installed, pkg);
    try updateLockfile(allocator, config.lockfile, pkg, resolved_sha, parsed.source);
    writeStdout("  ");
    printColor(Color.green, pkg);
    printBuf(&buf, " installed (locked at {s})\n", .{resolved_sha});
}

fn doRemove(allocator: std.mem.Allocator, config: Config, pkg: []const u8) !void {
    if (!isValidPkgName(pkg)) {
        printErrColor(Color.red, "error: ");
        writeStderr("invalid package name '");
        writeStderr(pkg);
        writeStderr("' (only alphanumeric, '-', '_' allowed)\n");
        return error.InvalidPackageName;
    }

    if (!isInstalled(allocator, config.installed, pkg)) {
        printErrColor(Color.red, pkg);
        writeStderr(" is not installed\n");
        return error.NotInstalled;
    }

    printColor(Color.bold, "Removing ");
    printColor(Color.bold ++ Color.cyan, pkg);
    writeStdout("...\n");

    const pkg_dir = try joinPath(allocator, config.src_dir, pkg);
    defer allocator.free(pkg_dir);
    const pkg_lib = try joinPath(allocator, pkg_dir, "lib");
    defer allocator.free(pkg_lib);

    if (dirExists(allocator, pkg_lib)) {
        try removeSldFiles(allocator, pkg_lib, config.lib_dir);
    }

    try removeDylibsFromPkg(allocator, pkg_dir, config.lib_dir);
    try removeFromInstalled(allocator, config.installed, pkg);
    try removeFromLockfile(allocator, config.lockfile, pkg);
    try removeDir(allocator, pkg_dir);

    writeStdout("  ");
    printColor(Color.green, pkg);
    writeStdout(" removed\n");
}

fn doList(allocator: std.mem.Allocator, config: Config) !void {
    const content = readFile(allocator, config.installed) catch {
        writeStdout("No packages installed\n");
        return;
    };
    defer allocator.free(content);

    if (std.mem.trim(u8, content, " \t\n\r").len == 0) {
        writeStdout("No packages installed\n");
        return;
    }

    writeStdout("Installed packages:\n");
    var buf: [512]u8 = undefined;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |pkg| {
        if (pkg.len == 0) continue;
        const entry = getLockedEntry(allocator, config.lockfile, pkg);
        const sha_short = if (entry) |e| e.sha[0..@min(12, e.sha.len)] else "unknown";
        const source = if (entry) |e| e.source else null;
        defer if (entry) |e| {
            allocator.free(e.sha);
            if (e.source) |s| allocator.free(s);
        };

        writeStdout("  ");
        writeStdout(pkg);
        writeStdout("  ");
        writeStdout(sha_short);

        if (getPkgManifest(allocator, config.src_dir, pkg)) |manifest| {
            defer manifest.deinit(allocator);
            if (manifest.depends) |deps| {
                printBuf(&buf, " (depends: {s})", .{deps});
            }
        }
        if (source) |s| {
            writeStdout(" (from: ");
            writeStdout(s);
            writeStdout(")");
        }
        writeStdout("\n");
    }
}

fn doUpdate(allocator: std.mem.Allocator, config: Config, pkg: ?[]const u8) !void {
    if (pkg) |p| {
        if (!isInstalled(allocator, config.installed, p)) {
            printErrColor(Color.red, p);
            writeStderr(" is not installed\n");
            return error.NotInstalled;
        }

        var buf: [256]u8 = undefined;
        printColor(Color.bold, "Updating ");
        printColor(Color.bold ++ Color.cyan, p);
        writeStdout("...\n");

        const pkg_dir = try joinPath(allocator, config.src_dir, p);
        defer allocator.free(pkg_dir);

        const locked_entry = getLockedEntry(allocator, config.lockfile, p);
        const expected_source = if (locked_entry) |e| e.source else null;
        defer if (locked_entry) |e| {
            allocator.free(e.sha);
            if (e.source) |s| allocator.free(s);
        };

        var url_buf: [512]u8 = undefined;
        const expected_url = expected_source orelse
            (std.fmt.bufPrint(&url_buf, "{s}/{s}.git", .{ config.org, p }) catch p);

        if (runGitCapture(allocator, &.{ "-C", pkg_dir, "config", "remote.origin.url" })) |current_origin| {
            defer allocator.free(current_origin);
            const trimmed = std.mem.trim(u8, current_origin, " \t\r\n");
            if (!std.mem.eql(u8, trimmed, expected_url)) {
                writeStdout("  Updating remote origin...\n");
                runGit(allocator, &.{ "-C", pkg_dir, "remote", "set-url", "origin", expected_url }) catch {};
            }
        } else |_| {}

        runGit(allocator, &.{ "-C", pkg_dir, "pull", "--quiet" }) catch {
            printErrColor(Color.red, "  Failed to pull\n");
            return error.GitFailed;
        };

        if (getPkgManifest(allocator, config.src_dir, p)) |manifest| {
            defer manifest.deinit(allocator);
            if (manifest.build_cmd) |build_cmd| {
                var build_buf: [256]u8 = undefined;
                printBuf(&build_buf, "  Building {s}...\n", .{p});
                const exit_code = runPassthrough(allocator, &.{ "/bin/sh", "-c", build_cmd }, pkg_dir) catch 1;
                if (exit_code != 0) {
                    printErrColor(Color.red, "  Build failed\n");
                    return error.BuildFailed;
                }
            }
        }

        const lib_src = try joinPath(allocator, pkg_dir, "lib");
        defer allocator.free(lib_src);
        if (dirExists(allocator, lib_src)) {
            const src_glob = try std.mem.concat(allocator, u8, &.{ lib_src, "/" });
            defer allocator.free(src_glob);
            const dst_glob = try std.mem.concat(allocator, u8, &.{ config.lib_dir, "/" });
            defer allocator.free(dst_glob);
            _ = runPassthrough(allocator, &.{ "/bin/cp", "-R", src_glob, dst_glob }, null) catch {};
        }

        _ = try copyDylibsFromPkg(allocator, pkg_dir, config.lib_dir);

        const new_sha = getPkgSha(allocator, config.src_dir, p) orelse "unknown";
        try updateLockfile(allocator, config.lockfile, p, new_sha, expected_source);
        writeStdout("  ");
        printColor(Color.green, p);
        printBuf(&buf, " updated (now at {s})\n", .{new_sha});
    } else {
        const content = readFile(allocator, config.installed) catch {
            writeStdout("No packages to update\n");
            return;
        };
        defer allocator.free(content);

        if (std.mem.trim(u8, content, " \t\n\r").len == 0) {
            writeStdout("No packages to update\n");
            return;
        }

        var packages: std.ArrayList([]const u8) = .empty;
        defer packages.deinit(allocator);
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len > 0) {
                const copy = allocator.dupe(u8, line) catch continue;
                packages.append(allocator, copy) catch continue;
            }
        }

        var any_failed = false;
        for (packages.items) |p| {
            doUpdate(allocator, config, p) catch {
                any_failed = true;
            };
        }
        if (any_failed) {
            printErrColor(Color.red, "Some packages failed to update\n");
            std.process.exit(1);
        }
    }
}

fn doVerify(allocator: std.mem.Allocator, config: Config) !void {
    const content = readFile(allocator, config.lockfile) catch {
        writeStdout("No lockfile found\n");
        return error.NoLockfile;
    };
    defer allocator.free(content);

    writeStdout("Verifying installed packages against lockfile...\n");
    var buf: [512]u8 = undefined;
    var ok = true;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const space = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const pkg = line[0..space];
        const rest = line[space + 1 ..];
        const locked_sha = if (std.mem.indexOfScalar(u8, rest, ' ')) |sp2| rest[0..sp2] else rest;

        const current_sha = getPkgSha(allocator, config.src_dir, pkg);
        if (current_sha == null) {
            writeStdout("  ");
            printColor(Color.red, "MISSING");
            printBuf(&buf, ": {s} (not cloned)\n", .{pkg});
            ok = false;
        } else if (!std.mem.eql(u8, current_sha.?, locked_sha)) {
            const cur_short = current_sha.?[0..@min(12, current_sha.?.len)];
            const lock_short = locked_sha[0..@min(12, locked_sha.len)];
            writeStdout("  ");
            printColor(Color.yellow, "MISMATCH");
            printBuf(&buf, ": {s} (locked: {s}, actual: {s})\n", .{ pkg, lock_short, cur_short });
            ok = false;
        } else {
            const lock_short = locked_sha[0..@min(12, locked_sha.len)];
            writeStdout("  ");
            printColor(Color.green, "OK");
            printBuf(&buf, ": {s} ({s})\n", .{ pkg, lock_short });
        }
    }

    if (ok) {
        printColor(Color.green, "All packages verified.\n");
    } else {
        printColor(Color.red, "Verification failed.\n");
        return error.VerifyFailed;
    }
}

fn printUsage() void {
    writeStdout(
        "thottam v" ++ version ++ " — package manager for Kaappi Scheme\n" ++
            "\n" ++
            "Usage: thottam [--locked] <command> [args]\n" ++
            "\n" ++
            "Commands:\n" ++
            "  install <pkg>[@<ver>][::url]        Install a package (optionally pinned/sourced)\n" ++
            "  remove <package>                   Remove a package\n" ++
            "  list                               List installed packages with commit SHAs\n" ++
            "  update [package]                   Update one or all packages\n" ++
            "  verify                             Check installs match the lockfile\n" ++
            "\n" ++
            "Flags:\n" ++
            "  --locked     Refuse to install packages not in the lockfile\n" ++
            "  -h, --help   Show this help message\n" ++
            "  --version    Show version\n" ++
            "  --completions <shell> Output completion script (bash, zsh, fish)\n" ++
            "\n" ++
            "Packages are installed to ~/.kaappi/lib/\n" ++
            "Lockfile: ~/.kaappi/thottam.lock\n" ++
            "\n" ++
            "Security: thottam runs the build: command from kaappi.pkg and copies\n" ++
            "native libraries to ~/.kaappi/lib/ (auto-loaded by ffi-open). Review\n" ++
            "package manifests before installing from untrusted sources.\n",
    );
}

fn getenv(name: [*:0]const u8) ?[]const u8 {
    const val = std.c.getenv(name) orelse return null;
    return std.mem.sliceTo(val, 0);
}

fn buildConfig(allocator: std.mem.Allocator) !Config {
    const home = getenv("KAAPPI_HOME") orelse blk: {
        const user_home = getenv("HOME") orelse fatal("HOME not set");
        break :blk try std.mem.concat(allocator, u8, &.{ user_home, "/.kaappi" });
    };
    const org = getenv("KAAPPI_ORG") orelse "https://github.com/kaappi";

    return .{
        .home = home,
        .org = org,
        .lib_dir = try std.mem.concat(allocator, u8, &.{ home, "/lib" }),
        .src_dir = try std.mem.concat(allocator, u8, &.{ home, "/src" }),
        .installed = try std.mem.concat(allocator, u8, &.{ home, "/installed.txt" }),
        .lockfile = try std.mem.concat(allocator, u8, &.{ home, "/thottam.lock" }),
    };
}

fn ensureDirs(allocator: std.mem.Allocator, config: Config) void {
    const lib_z = allocator.dupeZ(u8, config.lib_dir) catch return;
    defer allocator.free(lib_z);
    const src_z = allocator.dupeZ(u8, config.src_dir) catch return;
    defer allocator.free(src_z);
    _ = runPassthrough(allocator, &.{ "/bin/mkdir", "-p", config.lib_dir, config.src_dir }, null) catch {};
    if (!fileExists(allocator, config.installed)) {
        _ = runPassthrough(allocator, &.{ "/usr/bin/touch", config.installed }, null) catch {};
    }
}

pub fn main(init: std.process.Init.Minimal) !void {
    var da = if (@import("builtin").mode == .Debug) std.heap.DebugAllocator(.{}).init;
    defer if (@import("builtin").mode == .Debug) {
        _ = da.deinit();
    };
    const allocator = if (@import("builtin").mode == .Debug) da.allocator() else std.heap.c_allocator;

    initColor();

    var args = init.args.iterate();
    _ = args.skip();

    var locked_mode = false;
    var subcommand: ?[]const u8 = null;
    var sub_arg: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--locked")) {
            locked_mode = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            writeStdout("thottam v" ++ version ++ "\n");
            return;
        } else if (std.mem.eql(u8, arg, "--completions")) {
            if (args.next()) |shell| {
                if (@import("completions.zig").thottam(shell)) |script| {
                    writeStdout(script);
                } else {
                    writeStderr("unknown shell: ");
                    writeStderr(shell);
                    writeStderr("\nSupported: bash, zsh, fish\n");
                }
            } else {
                writeStderr("--completions requires a shell name (bash, zsh, fish)\n");
            }
            return;
        } else if (subcommand == null) {
            subcommand = arg;
        } else if (sub_arg == null) {
            sub_arg = arg;
        }
    }

    const config = try buildConfig(allocator);
    ensureDirs(allocator, config);

    const cmd = subcommand orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, cmd, "install")) {
        const spec = sub_arg orelse {
            writeStderr("Usage: thottam install <package>[@<version>][::url]\n");
            std.process.exit(1);
        };
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();
        doInstall(allocator, config, spec, locked_mode, &visited) catch |err| {
            if (err == error.GitFailed or err == error.BuildFailed) std.process.exit(1);
            return err;
        };
    } else if (std.mem.eql(u8, cmd, "remove")) {
        const pkg = sub_arg orelse {
            writeStderr("Usage: thottam remove <package>\n");
            std.process.exit(1);
        };
        doRemove(allocator, config, pkg) catch |err| {
            if (err == error.NotInstalled) std.process.exit(1);
            return err;
        };
    } else if (std.mem.eql(u8, cmd, "list")) {
        try doList(allocator, config);
    } else if (std.mem.eql(u8, cmd, "update")) {
        doUpdate(allocator, config, sub_arg) catch |err| {
            if (err == error.NotInstalled or err == error.GitFailed) std.process.exit(1);
            return err;
        };
    } else if (std.mem.eql(u8, cmd, "verify")) {
        doVerify(allocator, config) catch |err| {
            if (err == error.VerifyFailed or err == error.NoLockfile) std.process.exit(1);
            return err;
        };
    } else {
        printUsage();
    }
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

test "caret constraint: major > 0 locks major" {
    const c = Constraint{ .op = .caret, .ver = .{ .major = 1, .minor = 2, .patch = 3 } };
    try std.testing.expect(c.matches(.{ .major = 1, .minor = 2, .patch = 3 }));
    try std.testing.expect(c.matches(.{ .major = 1, .minor = 9, .patch = 0 }));
    try std.testing.expect(!c.matches(.{ .major = 2, .minor = 0, .patch = 0 }));
    try std.testing.expect(!c.matches(.{ .major = 1, .minor = 2, .patch = 2 }));
}

test "caret constraint: major=0 minor>0 locks minor" {
    const c = Constraint{ .op = .caret, .ver = .{ .major = 0, .minor = 2, .patch = 3 } };
    try std.testing.expect(c.matches(.{ .major = 0, .minor = 2, .patch = 3 }));
    try std.testing.expect(c.matches(.{ .major = 0, .minor = 2, .patch = 9 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 3, .patch = 0 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 2, .patch = 2 }));
    try std.testing.expect(!c.matches(.{ .major = 1, .minor = 0, .patch = 0 }));
}

test "caret constraint: major=0 minor=0 locks patch" {
    const c = Constraint{ .op = .caret, .ver = .{ .major = 0, .minor = 0, .patch = 3 } };
    try std.testing.expect(c.matches(.{ .major = 0, .minor = 0, .patch = 3 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 0, .patch = 4 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 0, .patch = 2 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 1, .patch = 0 }));
}

test "dylib_ext is correct for platform" {
    if (builtin.os.tag == .macos) {
        try std.testing.expectEqualStrings(".dylib", dylib_ext);
    } else {
        try std.testing.expectEqualStrings(".so", dylib_ext);
    }
}
