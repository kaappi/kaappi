const std = @import("std");
const platform = @import("platform.zig");

pub fn runCapture(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) ![]u8 {
    if (comptime platform.is_windows) {
        const raw = platform.winSpawnCapture(allocator, argv, cwd) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.CommandFailed => return error.CommandFailed,
            else => return error.ForkFailed,
        };
        defer allocator.free(raw);
        const trimmed = std.mem.trim(u8, raw, "\n\r");
        return allocator.dupe(u8, trimmed) catch return error.OutOfMemory;
    }

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

pub fn runPassthrough(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) !u8 {
    if (comptime platform.is_windows) {
        return platform.winSpawnPassthrough(allocator, argv, cwd) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ForkFailed,
        };
    }

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
        // execve only returns on failure. Passthrough inherits the child's
        // stderr, so say why instead of exiting 127 silently: a missing or
        // unexecutable git used to surface as "Failed to clone repository"
        // with no cause, indistinguishable from a real clone failure (#2152).
        var exec_err: [256]u8 = undefined;
        const exec_msg = std.fmt.bufPrint(&exec_err, "thottam: cannot execute {s}: {s}\n", .{ argv_z[0].?, @tagName(platform.errno(-1)) }) catch {
            const fallback = "thottam: cannot execute child process\n";
            _ = platform.write(2, fallback.ptr, fallback.len);
            std.process.exit(127);
        };
        _ = platform.write(2, exec_msg.ptr, exec_msg.len);
        std.process.exit(127);
    }

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const raw: c_uint = @bitCast(status);
    const wifexited = (raw & 0x7f) == 0;
    if (!wifexited) return 128 + @as(u8, @intCast(raw & 0x7f));
    return @intCast((raw >> 8) & 0xff);
}

/// Resolve the `git` executable through PATH, like `kaappi compile` does for
/// a C compiler (native_compiler.zig) and test_selection does for its git
/// invocations. The old `/usr/bin/git` hardcode was false on every supported
/// BSD — FreeBSD and OpenBSD install git in /usr/local/bin, NetBSD in
/// /usr/pkg/bin — so every git-backed thottam operation failed there (#2152).
/// Returns a caller-owned absolute path, or null when git is not on PATH.
/// The path is dupeZ'd: free with `path[0 .. path.len + 1]`.
fn findGit(allocator: std.mem.Allocator) ?[:0]const u8 {
    const path_env = platform.getenv("PATH") orelse return null;
    return findInPath(allocator, std.mem.span(path_env), "git");
}

/// Search `path_str` (a PATH-style list, `:` or `;` separated) for an
/// executable named `name` (with the platform suffix, so `git.exe` on
/// Windows, where the resolved absolute path is what CreateProcessW is
/// handed). An explicit path containing '/' is returned as-is. Returns a
/// caller-owned dupeZ'd absolute path, or null when not found — free with
/// `path[0 .. path.len + 1]`.
fn findInPath(allocator: std.mem.Allocator, path_str: []const u8, name: []const u8) ?[:0]const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') != null) {
        return allocator.dupeZ(u8, name) catch null;
    }
    var iter = std.mem.splitScalar(u8, path_str, platform.path_list_sep);
    while (iter.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ dir, name, platform.exe_suffix }) catch continue;
        const full_z = allocator.dupeZ(u8, full) catch {
            allocator.free(full);
            continue;
        };
        allocator.free(full);
        const fd = platform.openRead(full_z) catch {
            allocator.free(full_z[0 .. full_z.len + 1]);
            continue;
        };
        _ = platform.close(fd);
        return full_z;
    }
    return null;
}

pub fn runGit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    const git = findGit(allocator) orelse return error.GitNotFound;
    defer allocator.free(git[0 .. git.len + 1]);
    argv.append(allocator, git) catch return error.OutOfMemory;
    for (args) |a| {
        argv.append(allocator, a) catch return error.OutOfMemory;
    }
    const exit_code = try runPassthrough(allocator, argv.items, null);
    if (exit_code != 0) return error.GitFailed;
}

pub fn runGitCapture(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    const git = findGit(allocator) orelse return error.GitNotFound;
    defer allocator.free(git[0 .. git.len + 1]);
    argv.append(allocator, git) catch return error.OutOfMemory;
    for (args) |a| {
        argv.append(allocator, a) catch return error.OutOfMemory;
    }
    return runCapture(allocator, argv.items, null);
}

/// Check out a pinned version (tag or SHA) in an already-cloned package repo.
///
/// Uses `git checkout <v> --`: the trailing `--` makes git parse <v> as a
/// revision even when a file of the same name exists (issue #780) — the
/// reversed `git checkout -- <v>` would treat it as a pathspec. Not
/// `--end-of-options`: `git checkout` only understands it since git 2.43, and
/// older builds (e.g. Apple git on some macOS CI images) treat it as a
/// pathspec and fail (issue #969). Because <v> sits where options are still
/// parsed, reject values starting with '-' to keep the option-injection guard
/// from #736; no valid tag, branch, or SHA starts with '-'.
pub fn checkoutVersion(allocator: std.mem.Allocator, pkg_dir: []const u8, v: []const u8) !void {
    if (v.len == 0 or v[0] == '-') return error.GitFailed;
    return runGit(allocator, &.{ "-C", pkg_dir, "checkout", "--quiet", v, "--" });
}

test "checkoutVersion resolves a pinned tag as a ref, not a pathspec (issue #780)" {
    const thottam = @import("thottam.zig");
    const allocator = std.testing.allocator;

    // The precondition probe is now PATH-based (was: /usr/bin/git), matching
    // how runGit resolves the binary after #2152.
    if (findGit(allocator)) |git_path| {
        allocator.free(git_path[0 .. git_path.len + 1]);
    } else return error.SkipZigTest;

    const repo = try std.fmt.allocPrint(allocator, "{s}/kaappi-thottam-780-{d}", .{ platform.tempDir(), platform.getPid() });
    defer allocator.free(repo);
    defer thottam.removeDir(allocator, repo) catch {};
    thottam.removeDir(allocator, repo) catch {};

    runGit(allocator, &.{ "init", "-q", repo }) catch return error.SkipZigTest;
    try runGit(allocator, &.{ "-C", repo, "-c", "user.email=t@example.com", "-c", "user.name=Test", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "one" });
    try runGit(allocator, &.{ "-C", repo, "tag", "v1.0.0" });
    const decoy = try std.fmt.allocPrint(allocator, "{s}/v1.0.0", .{repo});
    defer allocator.free(decoy);
    try thottam.writeFile(allocator, decoy, "decoy\n");
    try runGit(allocator, &.{ "-C", repo, "add", "v1.0.0" });
    try runGit(allocator, &.{ "-C", repo, "-c", "user.email=t@example.com", "-c", "user.name=Test", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "two" });
    try runGit(allocator, &.{ "-C", repo, "tag", "v1.1.0" });

    try checkoutVersion(allocator, repo, "v1.0.0");

    const head = try runGitCapture(allocator, &.{ "-C", repo, "rev-parse", "HEAD" });
    defer allocator.free(head);
    const want = try runGitCapture(allocator, &.{ "-C", repo, "rev-parse", "v1.0.0^{commit}" });
    defer allocator.free(want);
    try std.testing.expectEqualStrings(want, head);

    const v11 = try runGitCapture(allocator, &.{ "-C", repo, "rev-parse", "v1.1.0^{commit}" });
    defer allocator.free(v11);
    try std.testing.expect(!std.mem.eql(u8, head, v11));
}

test "findInPath resolves an executable through PATH, not a fixed location (issue #2152)" {
    const thottam = @import("thottam.zig");
    const allocator = std.testing.allocator;
    const dir = try std.fmt.allocPrint(allocator, "{s}/kaappi-thottam-2152-{d}", .{ platform.tempDir(), platform.getPid() });
    defer allocator.free(dir);
    defer thottam.removeDir(allocator, dir) catch {};
    thottam.removeDir(allocator, dir) catch {};

    const exe_name = try std.fmt.allocPrint(allocator, "git{s}", .{platform.exe_suffix});
    defer allocator.free(exe_name);
    const git_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, exe_name });
    defer allocator.free(git_path);
    // writeFile does not create parent directories (and cannot run git init
    // the way the #780 test does), so make the fixture dir by hand.
    const dir_z = try allocator.dupeZ(u8, dir);
    defer allocator.free(dir_z[0 .. dir_z.len + 1]);
    _ = platform.mkdir(dir_z, 0o755);
    try thottam.writeFile(allocator, git_path, "#!/bin/sh\n");

    // The fake git sits in a directory that precedes /usr/bin — the path the
    // pre-#2152 code hardcoded. First match wins, so a resolver that looks in
    // /usr/bin first (or at all) would find the real git or nothing; this
    // resolver must find the fixture's.
    const path_str = try std.fmt.allocPrint(allocator, "{s}:/usr/bin:/bin", .{dir});
    defer allocator.free(path_str);

    const resolved = findInPath(allocator, path_str, "git") orelse return error.TestUnexpectedResult;
    defer allocator.free(resolved[0 .. resolved.len + 1]);
    try std.testing.expectEqualStrings(git_path, resolved);

    // A name that is nowhere on the path resolves to null.
    try std.testing.expect(findInPath(allocator, path_str, "kaappi-definitely-not-a-real-tool") == null);
}

test "checkoutVersion rejects option-like versions (issue #736)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", "--force"));
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", "-b"));
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", ""));
}
