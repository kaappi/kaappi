//! Unit tests for the fork + exec spawn route — kaappi#2517.
//!
//! Split out of `tests_process.zig` (at the 1500-line policy ceiling)
//! along the route seam: everything here exercises the POSIX backend's
//! second spawn path and its routing (`process_posix.routeFor`,
//! `spawnChildForkExec`, `childExecSide`) — the mechanism a build takes
//! when its host provides no `posix_spawn_file_actions_addchdir_np`
//! (neither through the comptime link gate nor the weak extern's runtime
//! binding): OpenBSD always, NetBSD and a genuinely pre-2.29 glibc host
//! for `directory:`.
//!
//! The routing table and the mechanism are tested as pure functions and
//! direct calls because a macOS dev host cannot reach the fork route
//! through the dispatch — its own gate is comptime-true, so `routeFor`
//! folds to the posix route for every spawn. The comptime-false dispatch
//! itself is covered by the NetBSD/OpenBSD CI legs (real routing) and by
//! the route-table test below (the decision, every combination).
//!
//! Same POSIX gate as the sibling suites: the fork route exists only on
//! POSIX, and the Windows backend has its own suite in
//! `tests_process_win.zig`.

const std = @import("std");
const builtin = @import("builtin");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");

const is_posix = switch (builtin.os.tag) {
    .windows, .wasi => false,
    else => true,
};

/// expectEvalTrue, but on a caller-owned VM (same split as
/// tests_process.zig: one shared interaction environment per test).
fn expectTrue(vm: *vm_mod.VM, source: []const u8) !void {
    const result = vm.eval(source) catch |e| {
        std.debug.print("eval error from: {s}\n  detail: {s}\n", .{ source, vm.last_error_detail[0..vm.last_error_detail_len] });
        return e;
    };
    if (result != types.TRUE) {
        std.debug.print("expected #t from: {s}\n", .{source});
        return error.TestExpectedTrue;
    }
}

/// Spawn `/bin/sh -c cmd` through the fork + exec route directly (inherit
/// stdio, no directory) and return the child's exit code — the probe driver
/// for the fork route's own tests. Referenced only inside comptime-gated
/// POSIX test bodies, so the backend import is never analyzed elsewhere.
fn forkRouteShExit(gc: anytype, cfg: anytype, cmd: [*:0]const u8) !u32 {
    const posix_backend = @import("process_posix.zig");
    const platform = @import("platform.zig");
    const types_process = @import("types_process.zig");
    var argv_buf = [3:null]?[*:0]const u8{ "/bin/sh", "-c", cmd };
    const argv: [*:null]const ?[*:0]const u8 = &argv_buf;
    const pid = try posix_backend.spawnChildForkExec(
        gc,
        argv,
        null,
        .{ .inherit, .inherit, .inherit },
        .{ -1, -1, -1 },
        cfg,
        null,
    );
    var st: c_int = 0;
    try std.testing.expectEqual(pid, platform.waitPid(pid, &st, 0));
    try std.testing.expect(types_process.ifExited(@bitCast(st)));
    return types_process.exitStatus(@bitCast(st));
}

/// PATH surgery for the walk tests: `spawnChildForkExec` captures the
/// parent's `getenv("PATH")`, so the tests steer the walk through the
/// process environment. Not in Zig 0.16's std.c, hence the extern (POSIX
/// only; referenced solely from comptime-gated test bodies).
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

/// Scoped PATH override: restores the original (copied — setenv may
/// reallocate environ and invalidate the old pointer) on scope exit. A PATH
/// longer than the buffer skips the test rather than truncate — a cut PATH
/// would poison every later test in the run.
const ScopedPath = struct {
    saved: [8192]u8 = undefined,
    saved_len: usize = 0,

    fn install(dir_z: [*:0]const u8) !ScopedPath {
        var self = ScopedPath{};
        if (std.c.getenv("PATH")) |p| {
            const len = std.mem.len(p);
            if (len >= self.saved.len) return error.SkipZigTest;
            self.saved_len = len;
            @memcpy(self.saved[0..len], p[0..len]);
        }
        if (setenv("PATH", dir_z, 1) != 0) return error.SkipZigTest;
        return self;
    }

    fn restore(self: *ScopedPath) void {
        if (self.saved_len == 0) return;
        self.saved[self.saved_len] = 0;
        _ = setenv("PATH", self.saved[0..self.saved_len :0].ptr, 1);
    }
};

test "process: spawn routing honors directory: on every build (kaappi#2517)" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (comptime is_posix) {
        const posix_backend = @import("process_posix.zig");
        const Route = posix_backend.SpawnRoute;

        // OpenBSD's fork key is comptime: always the fork route.
        try std.testing.expectEqual(Route.fork_exec, posix_backend.routeFor(true, true, false));
        try std.testing.expectEqual(Route.fork_exec, posix_backend.routeFor(true, false, true));
        // addchdir available — a comptime-true build everywhere, and (the
        // runtime weak-extern binding) a gnu.2.28-floored release binary on
        // any glibc >= 2.29 host: posix_spawnp for every spawn, `directory:`
        // included. This is the row that keeps the fast path on release
        // binaries instead of paying the fork route per directory: spawn.
        try std.testing.expectEqual(Route.posix_spawn, posix_backend.routeFor(false, true, false));
        try std.testing.expectEqual(Route.posix_spawn, posix_backend.routeFor(false, true, true));
        // No addchdir anywhere (a genuinely pre-2.29 glibc host, NetBSD):
        // only `directory:` diverts to the fork route; everything else keeps
        // the fast path. Before kaappi#2517 these builds rejected
        // `directory:` outright — KP3007 on every Linux host, however new
        // its glibc, because the floor is the build target's.
        try std.testing.expectEqual(Route.posix_spawn, posix_backend.routeFor(false, false, false));
        try std.testing.expectEqual(Route.fork_exec, posix_backend.routeFor(false, false, true));
    }
}

test "process: the fork+exec route chdirs the child before exec (kaappi#2517)" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (comptime is_posix) {
        const posix_backend = @import("process_posix.zig");
        const platform = @import("platform.zig");
        const memory = @import("memory.zig");
        const types_process = @import("types_process.zig");
        const primitives = @import("primitives.zig");
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const vm = ctx.vm;
        const gc = memory.gc_instance.?;

        // The exact function a no-addchdir build runs for a `directory:`
        // spawn, called directly. On a host whose own gate is true (macOS,
        // FreeBSD, CI Linux) the dispatch never routes here, so the
        // mechanism would otherwise have no coverage on the dev platform —
        // and a gnu.2.28 build cannot run on a macOS host at all. /bin/sh
        // prints its working directory into a pipe; the assertion is the
        // directory the child chdir'd to, the behavior `directory:` promises.
        var argv_buf = [3:null]?[*:0]const u8{ "/bin/sh", "-c", "pwd" };
        const argv: [*:null]const ?[*:0]const u8 = &argv_buf;

        // argv[0]'s Value is only the irritant of a failure condition, but the
        // failure call below reaches that raise — so it must be a real string,
        // rooted across the calls (the spawn can raise, and its pipe-exhaustion
        // recovery can collect). The stack array holding the copy is stable,
        // and the collector does not move objects.
        var argv0 = try gc.allocString("/bin/sh");
        gc.pushRoot(&argv0);
        var argv_vals = [_]types.Value{argv0};
        const cfg = types_process.SpawnConfig{ .argv = &argv_vals };

        var out_pipe: [2]platform.fd_t = undefined;
        try std.testing.expectEqual(@as(c_int, 0), platform.pipe(&out_pipe));
        // Lift the write end out of the stdio slots in case the harness's own
        // stdio was closed (spawnChild does the same via
        // normalizePipeAboveStdio; this test calls the route directly).
        if (out_pipe[1] <= 2) {
            const lifted = platform.dupCloexecAtLeast(out_pipe[1], 3);
            try std.testing.expect(lifted >= 3);
            _ = platform.close(out_pipe[1]);
            out_pipe[1] = lifted;
        }
        const redirs = [3]types_process.Redir{ .inherit, .{ .fd = out_pipe[1] }, .inherit };

        const pid = try posix_backend.spawnChildForkExec(
            gc,
            argv,
            null,
            redirs,
            .{ -1, -1, -1 },
            cfg,
            "/",
        );

        // The parent's copy of the write end is ours to drop; closing it is
        // what makes the read see EOF at the child's exit rather than never.
        _ = platform.close(out_pipe[1]);
        var buf: [64]u8 = undefined;
        var out_len: usize = 0;
        while (out_len < buf.len) {
            const n = platform.read(out_pipe[0], buf[out_len..].ptr, buf.len - out_len);
            if (n < 0 and platform.errno(n) == .INTR) continue;
            try std.testing.expect(n >= 0);
            if (n == 0) break;
            out_len += @intCast(n);
        }
        _ = platform.close(out_pipe[0]);
        try std.testing.expectEqualStrings("/\n", buf[0..out_len]);

        var st: c_int = 0;
        try std.testing.expectEqual(pid, platform.waitPid(pid, &st, 0));
        try std.testing.expect(types_process.ifExited(@bitCast(st)));
        try std.testing.expectEqual(@as(u32, 0), types_process.exitStatus(@bitCast(st)));

        // A bad directory reports through the same one-byte error pipe as a
        // failed exec — synchronously, the condition macOS's and FreeBSD's
        // posix_spawn raise for a failed chdir action (glibc's posix route
        // instead exits the child 127, its own action-failure behavior): a
        // file error carrying ENOENT, never a KP3007-style platform
        // rejection and never a silently ignored directory.
        try std.testing.expectError(
            primitives.PrimitiveError.ExceptionRaised,
            posix_backend.spawnChildForkExec(
                gc,
                argv,
                null,
                .{ .inherit, .inherit, .inherit },
                .{ -1, -1, -1 },
                cfg,
                "/no/such/directory/kaappi-2517",
            ),
        );
        const err_obj = types.toObject(vm.current_exception.?).as(types.ErrorObject);
        try std.testing.expect(err_obj.error_type == .file);
        try std.testing.expectEqual(@as(c_int, @intFromEnum(std.c.E.NOENT)), err_obj.posix_errno);
        gc.popRoot();
    }
}

test "process: fork-route chdir failure reports even from a replaced stdio slot (kaappi#2517 review)" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (comptime is_posix) {
        const posix_backend = @import("process_posix.zig");
        const platform = @import("platform.zig");
        const memory = @import("memory.zig");
        const types_process = @import("types_process.zig");
        const primitives = @import("primitives.zig");
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const vm = ctx.vm;
        const gc = memory.gc_instance.?;

        // With the standard descriptors closed, pipe(2) hands back the
        // lowest free fds, so the error pipe used to land IN the stdio
        // range — and the 'null redirection for slot 1 below then REPLACED
        // the child's copy of the write end before the chdir could fail. A
        // failed chdir reported to the replacement, the parent read EOF as
        // a successful exec, and the caller got a child that dies 127. The
        // normalize lift keeps the report path intact, so the spawn must
        // raise the file error the errno names — not "succeed".
        const saved0 = platform.dupCloexecAtLeast(0, 3);
        const saved1 = platform.dupCloexecAtLeast(1, 3);
        const saved2 = platform.dupCloexecAtLeast(2, 3);
        try std.testing.expect(saved0 >= 3);
        try std.testing.expect(saved1 >= 3);
        try std.testing.expect(saved2 >= 3);
        defer {
            // Restore before anything the framework might print.
            _ = std.c.dup2(saved0, 0);
            _ = std.c.dup2(saved1, 1);
            _ = std.c.dup2(saved2, 2);
            _ = platform.close(saved0);
            _ = platform.close(saved1);
            _ = platform.close(saved2);
        }
        _ = platform.close(0);
        _ = platform.close(1);
        _ = platform.close(2);

        var argv_buf = [1:null]?[*:0]const u8{"true"};
        const argv: [*:null]const ?[*:0]const u8 = &argv_buf;
        var argv0 = try gc.allocString("true");
        gc.pushRoot(&argv0);
        var argv_vals = [_]types.Value{argv0};
        const cfg = types_process.SpawnConfig{ .argv = &argv_vals };

        try std.testing.expectError(
            primitives.PrimitiveError.ExceptionRaised,
            posix_backend.spawnChildForkExec(
                gc,
                argv,
                null,
                .{ .inherit, .null_sink, .inherit },
                .{ -1, -1, -1 },
                cfg,
                "/no/such/directory/kaappi-2517",
            ),
        );
        const err_obj = types.toObject(vm.current_exception.?).as(types.ErrorObject);
        try std.testing.expect(err_obj.error_type == .file);
        try std.testing.expectEqual(@as(c_int, @intFromEnum(std.c.E.NOENT)), err_obj.posix_errno);
        gc.popRoot();
    }
}

test "process: the fork route resolves bare names on the PARENT's PATH (kaappi#2517 review)" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (comptime is_posix) {
        const posix_backend = @import("process_posix.zig");
        const platform = @import("platform.zig");
        const memory = @import("memory.zig");
        const types_process = @import("types_process.zig");
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const gc = memory.gc_instance.?;

        // execvp in the child searched the CHILD's environment — under
        // `env:` with a PATH that does not contain the program, the fork
        // route raised ENOENT where posix_spawnp (parent-side PATH)
        // succeeded; the reviewer measured exactly that divergence. The
        // child now walks the parent-captured PATH, so a bare `sh` must
        // spawn and run even when the child's own PATH points nowhere.
        var argv_buf = [3:null]?[*:0]const u8{ "sh", "-c", "echo fork-path-ok" };
        const argv: [*:null]const ?[*:0]const u8 = &argv_buf;
        var argv0 = try gc.allocString("sh");
        gc.pushRoot(&argv0);
        var argv_vals = [_]types.Value{argv0};
        const cfg = types_process.SpawnConfig{ .argv = &argv_vals };
        var env_buf = [1:null]?[*:0]const u8{"PATH=/nonexistent-kaappi-2517"};
        const env_block: [*:null]const ?[*:0]const u8 = &env_buf;

        var out_pipe: [2]platform.fd_t = undefined;
        try std.testing.expectEqual(@as(c_int, 0), platform.pipe(&out_pipe));
        if (out_pipe[1] <= 2) {
            const lifted = platform.dupCloexecAtLeast(out_pipe[1], 3);
            try std.testing.expect(lifted >= 3);
            _ = platform.close(out_pipe[1]);
            out_pipe[1] = lifted;
        }
        const redirs = [3]types_process.Redir{ .inherit, .{ .fd = out_pipe[1] }, .inherit };

        const pid = try posix_backend.spawnChildForkExec(
            gc,
            argv,
            env_block,
            redirs,
            .{ -1, -1, -1 },
            cfg,
            "/",
        );
        _ = platform.close(out_pipe[1]);
        var buf: [64]u8 = undefined;
        var out_len: usize = 0;
        while (out_len < buf.len) {
            const n = platform.read(out_pipe[0], buf[out_len..].ptr, buf.len - out_len);
            if (n < 0 and platform.errno(n) == .INTR) continue;
            try std.testing.expect(n >= 0);
            if (n == 0) break;
            out_len += @intCast(n);
        }
        _ = platform.close(out_pipe[0]);
        try std.testing.expectEqualStrings("fork-path-ok\n", buf[0..out_len]);

        var st: c_int = 0;
        try std.testing.expectEqual(pid, platform.waitPid(pid, &st, 0));
        try std.testing.expect(types_process.ifExited(@bitCast(st)));
        try std.testing.expectEqual(@as(u32, 0), types_process.exitStatus(@bitCast(st)));
        gc.popRoot();
    }
}

test "process: the fork route passes ENOEXEC through, no shell fallback (kaappi#2517 review)" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (comptime is_posix) {
        const posix_backend = @import("process_posix.zig");
        const platform = @import("platform.zig");
        const memory = @import("memory.zig");
        const types_process = @import("types_process.zig");
        const primitives = @import("primitives.zig");
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const vm = ctx.vm;
        const gc = memory.gc_instance.?;

        // An executable file with no recognized format, reached by a bare
        // name through the parent-captured PATH. glibc's default
        // posix_spawnp binding passes only SPAWN_XFLAGS_USE_PATH — the
        // /bin/sh fallback belongs to the compat TRY_SHELL path — so the
        // fork route must report ENOEXEC as the spawn's verdict: no shell
        // fallback, no continued search, and no masking it behind a
        // fabricated ENOENT (which is what the walk did before the errno
        // contract was aligned).
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
        defer std.testing.allocator.free(dir_path);
        var dir_buf: [platform.PATH_MAX]u8 = undefined;
        const dir_z = try std.fmt.bufPrintZ(&dir_buf, "{s}", .{dir_path});

        var file_buf: [platform.PATH_MAX]u8 = undefined;
        const file_z = try std.fmt.bufPrintZ(&file_buf, "{s}/kaappi-2517-noexec", .{dir_path});
        const fd = std.c.open(file_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(c_uint, 0o755));
        try std.testing.expect(fd >= 3);
        const body = "not an executable format\n";
        _ = std.c.write(fd, body.ptr, body.len);
        _ = platform.close(fd);

        var path_scope = try ScopedPath.install(dir_z.ptr);
        defer path_scope.restore();

        var argv_buf = [1:null]?[*:0]const u8{"kaappi-2517-noexec"};
        const argv: [*:null]const ?[*:0]const u8 = &argv_buf;
        var argv0 = try gc.allocString("kaappi-2517-noexec");
        gc.pushRoot(&argv0);
        var argv_vals = [_]types.Value{argv0};
        const cfg = types_process.SpawnConfig{ .argv = &argv_vals };

        try std.testing.expectError(
            primitives.PrimitiveError.ExceptionRaised,
            posix_backend.spawnChildForkExec(
                gc,
                argv,
                null,
                .{ .inherit, .inherit, .inherit },
                .{ -1, -1, -1 },
                cfg,
                null,
            ),
        );
        const err_obj = types.toObject(vm.current_exception.?).as(types.ErrorObject);
        try std.testing.expect(err_obj.error_type == .file);
        try std.testing.expectEqual(@as(c_int, @intFromEnum(std.c.E.NOEXEC)), err_obj.posix_errno);
        gc.popRoot();
    }
}

test "process: an all-EACCES PATH search reports EACCES, not ENOENT (kaappi#2517 review)" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (comptime is_posix) {
        const posix_backend = @import("process_posix.zig");
        const platform = @import("platform.zig");
        const memory = @import("memory.zig");
        const types_process = @import("types_process.zig");
        const primitives = @import("primitives.zig");
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const vm = ctx.vm;
        const gc = memory.gc_instance.?;

        // A PATH whose only entry holds the program as a NON-executable
        // file: every candidate fails EACCES, the search runs to the end,
        // and the reported condition is the remembered EACCES — glibc's
        // execvpe contract (an all-EACCES miss must not masquerade as
        // ENOENT).
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
        defer std.testing.allocator.free(dir_path);
        var dir_buf: [platform.PATH_MAX]u8 = undefined;
        const dir_z = try std.fmt.bufPrintZ(&dir_buf, "{s}", .{dir_path});

        var file_buf: [platform.PATH_MAX]u8 = undefined;
        const file_z = try std.fmt.bufPrintZ(&file_buf, "{s}/kaappi-2517-denied", .{dir_path});
        const fd = std.c.open(file_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(c_uint, 0o644));
        try std.testing.expect(fd >= 3);
        const body = "no permission to execute\n";
        _ = std.c.write(fd, body.ptr, body.len);
        _ = platform.close(fd);

        var path_scope = try ScopedPath.install(dir_z.ptr);
        defer path_scope.restore();

        var argv_buf = [1:null]?[*:0]const u8{"kaappi-2517-denied"};
        const argv: [*:null]const ?[*:0]const u8 = &argv_buf;
        var argv0 = try gc.allocString("kaappi-2517-denied");
        gc.pushRoot(&argv0);
        var argv_vals = [_]types.Value{argv0};
        const cfg = types_process.SpawnConfig{ .argv = &argv_vals };

        try std.testing.expectError(
            primitives.PrimitiveError.ExceptionRaised,
            posix_backend.spawnChildForkExec(
                gc,
                argv,
                null,
                .{ .inherit, .inherit, .inherit },
                .{ -1, -1, -1 },
                cfg,
                null,
            ),
        );
        const err_obj = types.toObject(vm.current_exception.?).as(types.ErrorObject);
        try std.testing.expect(err_obj.error_type == .file);
        try std.testing.expectEqual(@as(c_int, @intFromEnum(std.c.E.ACCES)), err_obj.posix_errno);
        gc.popRoot();
    }
}

test "process: env: and directory: resolve bare names identically on both routes" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // The Scheme-level twin of the parent-PATH test above, pinning both
    // routes to the same answer through the public API. Without directory:
    // every build takes posix_spawnp; with directory: the NetBSD/OpenBSD
    // CI legs take the fork route for real (and a gnu.2.28-floored binary
    // on a pre-2.29 host would too) — both must resolve the bare `sh`
    // against the parent's PATH, never the env:-replaced child PATH.
    try expectTrue(vm,
        \\(and (string=? "ok\n" (call-with-values
        \\       (lambda () (run-process '("sh" "-c" "echo ok")
        \\                                'env: '(("PATH" . "/nonexistent-kaappi-2517"))))
        \\       (lambda (st out err) out)))
        \\     (string=? "ok\n" (call-with-values
        \\       (lambda () (run-process '("sh" "-c" "echo ok")
        \\                                'env: '(("PATH" . "/nonexistent-kaappi-2517"))
        \\                                'directory: "/"))
        \\       (lambda (st out err) out))))
    );
}

test "process: the fork route's close-by-default removes inherited descriptors" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (comptime is_posix) {
        // The openness probe needs a live fd inventory: /dev/fd is live on
        // macOS (fdesc) and a /proc/self/fd symlink on Linux, but the other
        // BSDs expose static device nodes that exist whether or not the fd
        // is open — the same reason the posix-route test in
        // tests_process.zig gates its probe per OS. Skip there rather than
        // assert against a probe that cannot report "closed".
        if (comptime (builtin.os.tag != .macos and builtin.os.tag != .ios and
            builtin.os.tag != .linux)) return error.SkipZigTest;
        const platform = @import("platform.zig");
        const memory = @import("memory.zig");
        const types_process = @import("types_process.zig");
        var ctx: th.TestContext = undefined;
        try ctx.init();
        defer ctx.deinit();
        const gc = memory.gc_instance.?;

        // Park an inheritable descriptor and require the fork route's child
        // not to see it. On macOS this exercises the fcntl probe fallback;
        // on the Linux CI legs it exercises the close_range(CLOEXEC) fast
        // path that replaced the probe there (kaappi#2517 review: the probe
        // measured ~80 ms per spawn at soft nofile 524288). The fd-2
        // control proves the child's own probe works before the verdict
        // counts. Same probe shape as the posix-route test in
        // tests_process.zig.
        const extra = std.c.open("/dev/null", .{ .ACCMODE = .RDONLY }, @as(c_uint, 0));
        if (extra < 0) return error.SkipZigTest;
        defer _ = platform.close(extra);
        try std.testing.expect((platform.getFdFlags(extra) & 1) == 0); // inheritable

        var argv0 = try gc.allocString("/bin/sh");
        gc.pushRoot(&argv0);
        var argv_vals = [_]types.Value{argv0};
        const cfg = types_process.SpawnConfig{ .argv = &argv_vals };

        // Control: the child's fd 2 IS open (stdio slots survive).
        try std.testing.expectEqual(@as(u32, 0), try forkRouteShExit(gc, cfg, "if [ -e /dev/fd/2 ]; then exit 0; else exit 1; fi"));

        // Verdict: the parked descriptor must be gone.
        var cmd_buf: [96]u8 = undefined;
        const cmd = try std.fmt.bufPrintZ(&cmd_buf, "if [ -e /dev/fd/{d} ]; then exit 1; else exit 0; fi", .{extra});
        try std.testing.expectEqual(@as(u32, 0), try forkRouteShExit(gc, cfg, cmd.ptr));
        gc.popRoot();
    }
}
