const std = @import("std");
const platform = @import("platform.zig");

/// execve in the forked child; the only "return" is failure, where it reports
/// why to `err_fd` and exits 127. Shared by runPassthrough (err_fd = the
/// inherited stderr) and runCapture (err_fd = the saved real stderr, since
/// capture silences fd 2) so a missing or unexecutable git is distinguishable
/// from a genuine failure in the logs (#2152).
fn execveOrReport(argv_z: []?[*:0]const u8, err_fd: platform.fd_t) noreturn {
    _ = std.posix.system.execve(
        @ptrCast(argv_z[0].?),
        @ptrCast(argv_z.ptr),
        @ptrCast(std.c.environ),
    );
    // execve only returns on failure.
    var exec_err: [256]u8 = undefined;
    const exec_msg = std.fmt.bufPrint(&exec_err, "thottam: cannot execute {s}: {s}\n", .{ argv_z[0].?, @tagName(platform.errno(-1)) }) catch {
        const fallback = "thottam: cannot execute child process\n";
        _ = platform.write(err_fd, fallback.ptr, fallback.len);
        std.process.exit(127);
    };
    _ = platform.write(err_fd, exec_msg.ptr, exec_msg.len);
    std.process.exit(127);
}

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
    // WASI p1 has no process creation — and wasi-libc does not even provide
    // pipe/fork/execve as symbols, so the POSIX tail below would leave the
    // module with imports no host can resolve (kaappi#2153). Thottam does
    // not ship in the wasm build; this arm exists so the unit-test module
    // compiles as a gate.
    if (comptime platform.is_wasm) return error.ForkFailed;

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
    // CLOEXEC audit (KEP-0022 Phase 1): both pipe ends and the stderr-save
    // dup below are close-on-exec. The child's dup2s onto 0/1/2 clear it on
    // exactly the slots the exec'd child needs, and the saved stderr now
    // survives only a FAILED execve (its whole purpose) instead of leaking
    // into every successfully spawned git.
    _ = platform.setFdCloexec(pipe[0]);
    _ = platform.setFdCloexec(pipe[1]);

    const pid = std.posix.system.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        // Child
        _ = std.c.close(pipe[0]);
        _ = std.c.dup2(pipe[1], 1);
        _ = std.c.close(pipe[1]);
        // Save the real stderr so an execve failure stays audible; the
        // /dev/null dup2 silences only git's own stderr, which is the point
        // of capture (#2152). F_DUPFD_CLOEXEC (fcntl with cmd 6 / arg 0):
        // like dup(2) but close-on-exec.
        const real_stderr = platform.fcntlDupCloexec(2);
        const devnull = std.c.open("/dev/null", .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, @as(c_uint, 0));
        if (devnull >= 0) {
            _ = std.c.dup2(devnull, 2);
            _ = std.c.close(devnull);
        }

        if (cwd_z) |c| {
            _ = std.posix.system.chdir(c);
        }
        execveOrReport(argv_z, real_stderr);
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
    if (comptime platform.is_wasm) return error.ForkFailed; // no process creation on WASI p1 (see runCapture)

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
        // Passthrough inherits stderr, so the diagnostic goes there directly.
        execveOrReport(argv_z, 2);
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
/// The path is dupeZ'd: free the `[:0]` slice with `allocator.free(path)`.
fn findGit(allocator: std.mem.Allocator) ?[:0]const u8 {
    const path_env = platform.getenv("PATH") orelse return null;
    return findInPath(allocator, std.mem.span(path_env), "git");
}

/// Search `path_str` (a PATH-style list, `:` or `;` separated) for an
/// executable named `name` (with the platform suffix, so `git.exe` on
/// Windows, where the resolved absolute path is what CreateProcessW is
/// handed). An explicit path containing '/' is returned as-is. Returns a
/// caller-owned dupeZ'd absolute path, or null when not found — free the
/// `[:0]` slice with `allocator.free(path)`.
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
        if (!isExecutableFile(full_z)) {
            allocator.free(full_z);
            continue;
        }
        return full_z;
    }
    return null;
}

/// Is `path` an executable regular file? The pre-#2152 resolver checked only
/// `openRead`, which accepts a non-executable file or a directory named `git` —
/// either would shadow a later real git and then fail at execve instead of
/// falling through to the next PATH entry the way execvp would. X_OK (not
/// R_OK) also keeps an execute-only git, which openRead would reject. Windows
/// has no execute bit: a regular file (already .exe-suffixed) is executable.
fn isExecutableFile(path: [:0]const u8) bool {
    if (comptime platform.is_windows) {
        const st = platform.statPath(path) orelse return false;
        return st.is_file;
    }
    if (std.c.access(path, std.posix.X_OK) != 0) return false;
    const st = platform.statPath(path) orelse return false;
    return st.is_file;
}

pub fn runGit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    const git = findGit(allocator) orelse return error.GitNotFound;
    defer allocator.free(git);
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
    defer allocator.free(git);
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
        allocator.free(git_path);
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
    defer allocator.free(dir_z);
    _ = platform.mkdir(dir_z, 0o755);
    try thottam.writeFile(allocator, git_path, "#!/bin/sh\nexit 0\n");

    // A readable-but-non-executable file is not a usable git: findInPath must
    // skip it rather than hand execve a path it will reject. POSIX encodes
    // this as the execute bit; Windows has no such bit, so the fresh fixture
    // is already "executable" there. Probe with only the fixture dir on the
    // path, so a real git elsewhere cannot satisfy the search.
    if (!platform.is_windows) {
        try std.testing.expect(findInPath(allocator, dir, "git") == null);
    }

    // Make it executable.
    const git_path_z = try allocator.dupeZ(u8, git_path);
    defer allocator.free(git_path_z);
    platform.makeWritable(git_path_z);

    // The fake git sits in a directory that precedes /usr/bin — the path the
    // pre-#2152 code hardcoded. First match wins, so a resolver that looks in
    // /usr/bin first (or at all) would find the real git or nothing; this
    // resolver must find the fixture's, which is now executable.
    const path_str = try std.fmt.allocPrint(allocator, "{s}{c}{s}{c}{s}", .{ dir, platform.path_list_sep, "/usr/bin", platform.path_list_sep, "/bin" });
    defer allocator.free(path_str);

    const resolved = findInPath(allocator, path_str, "git") orelse return error.TestUnexpectedResult;
    defer allocator.free(resolved);
    try std.testing.expectEqualStrings(git_path, resolved);
    if (!platform.is_windows) {
        const argv = [_][]const u8{resolved};
        try std.testing.expectEqual(@as(u8, 0), try runPassthrough(allocator, &argv, null));
    }

    // A name that is nowhere on the path resolves to null.
    try std.testing.expect(findInPath(allocator, path_str, "kaappi-definitely-not-a-real-tool") == null);
}

test "checkoutVersion rejects option-like versions (issue #736)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", "--force"));
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", "-b"));
    try std.testing.expectError(error.GitFailed, checkoutVersion(allocator, "/nonexistent", ""));
}
