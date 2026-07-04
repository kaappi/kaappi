const std = @import("std");

pub fn runCapture(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) ![]u8 {
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

pub fn runGit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    argv.append(allocator, "/usr/bin/git") catch return error.OutOfMemory;
    for (args) |a| {
        argv.append(allocator, a) catch return error.OutOfMemory;
    }
    const exit_code = try runPassthrough(allocator, argv.items, null);
    if (exit_code != 0) return error.GitFailed;
}

pub fn runGitCapture(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    argv.append(allocator, "/usr/bin/git") catch return error.OutOfMemory;
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

    if (!thottam.fileExists(allocator, "/usr/bin/git")) return error.SkipZigTest;

    const base = thottam.getenv("TMPDIR") orelse "/tmp";
    const repo = try std.fmt.allocPrint(allocator, "{s}/kaappi-thottam-780-{d}", .{ base, std.c.getpid() });
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

test "checkoutVersion rejects option-like versions (issue #736)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", "--force"));
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", "-b"));
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", ""));
}
