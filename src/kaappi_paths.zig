const std = @import("std");
const platform = @import("platform.zig");

/// Returns the kaappi home directory path written into `buf`.
/// Checks `KAAPPI_HOME` env var first; falls back to `$HOME/.kaappi`
/// (`%USERPROFILE%/.kaappi` on Windows, whose shells don't set HOME —
/// git-bash sets both). Returns null if no env var is available or the
/// path exceeds `buf`.
pub fn getHome(buf: []u8) ?[]const u8 {
    if (platform.getenv("KAAPPI_HOME")) |kh| {
        const home = std.mem.sliceTo(kh, 0);
        if (home.len > 0 and home.len <= buf.len) {
            @memcpy(buf[0..home.len], home);
            return buf[0..home.len];
        }
    }
    const home_ptr = platform.getenv("HOME") orelse
        (if (platform.is_windows) platform.getenv("USERPROFILE") else null) orelse
        return null;
    const home = std.mem.sliceTo(home_ptr, 0);
    const suffix = "/.kaappi";
    const total = home.len + suffix.len;
    if (total > buf.len) return null;
    @memcpy(buf[0..home.len], home);
    @memcpy(buf[home.len..][0..suffix.len], suffix);
    return buf[0..total];
}

test "getHome falls back to HOME/.kaappi" {
    var buf: [512]u8 = undefined;
    if (getHome(&buf)) |home| {
        try std.testing.expect(home.len > 0);
        try std.testing.expect(std.mem.endsWith(u8, home, "/.kaappi") or
            platform.getenv("KAAPPI_HOME") != null);
    }
}

/// Computes `<parent-of-bin-dir>/lib` for an executable's own absolute
/// path, written into `buf`. Split out from `getExeRelativeLibDir` so the
/// path arithmetic is unit-testable with synthetic paths, independent of
/// wherever the calling process actually happens to live on disk.
///
/// Returns null if `exe_path` isn't nested at least two directories deep
/// or the resulting path doesn't fit `buf`.
fn siblingLibDir(exe_path: []const u8, buf: []u8) ?[]const u8 {
    if (exe_path.len == 0) return null;

    const last_slash = std.mem.lastIndexOfScalar(u8, exe_path, '/') orelse return null;
    if (last_slash == 0) return null;
    const bin_dir = exe_path[0..last_slash];
    const parent_slash = std.mem.lastIndexOfScalar(u8, bin_dir, '/') orelse return null;
    if (parent_slash == 0) return null;
    const parent = exe_path[0..parent_slash];

    const suffix = "/lib";
    if (parent.len + suffix.len > buf.len) return null;
    @memcpy(buf[0..parent.len], parent);
    @memcpy(buf[parent.len..][0..suffix.len], suffix);
    return buf[0 .. parent.len + suffix.len];
}

/// Returns `<exe_dir>/../lib` — the sibling `lib/` directory next to the
/// running executable's own `bin/` directory — written into `buf`. This is
/// the shared layout for both a `zig build` tree (`zig-out/bin/kaappi` +
/// `zig-out/lib/`) and an installed release (`<prefix>/bin/kaappi` +
/// `<prefix>/lib/`), so a from-source binary run from any directory can
/// still find the runtime archive (`libkaappi_rt.a`; `kaappi_rt.lib` on
/// Windows) or the portable-library `.sld` sources it was built alongside.
///
/// Returns null if the platform has no self-exe-path lookup, the
/// executable isn't nested at least two directories deep, or the resulting
/// path doesn't fit `buf`. Does not check whether the directory exists.
/// Resolves the running executable's own absolute path into `buf`, returning
/// the slice (or null if the platform has no self-exe lookup or the path
/// doesn't fit). On Linux this reads `/proc/self/exe`; on macOS it resolves
/// `_NSGetExecutablePath` through `realpath` so a symlinked launch (e.g. a
/// Homebrew Cellar symlink) yields the real binary. Used both to derive the
/// sibling `lib/` dir and, by the `kaappi test` orchestrator, to re-spawn the
/// same binary as a worker regardless of how it was invoked.
pub fn getExePath(buf: []u8) ?[]const u8 {
    if (comptime @import("builtin").os.tag == .windows) {
        return platform.getExePathWindows(buf);
    }

    if (comptime @import("builtin").os.tag == .linux) {
        // /proc/self/exe is a kernel-resolved canonical path already —
        // no realpath needed. Reject a result that fills the whole
        // buffer: readlink doesn't NUL-terminate, and an exact-length
        // return means the real target may have been truncated.
        const n: isize = std.posix.system.readlink("/proc/self/exe", buf.ptr, buf.len);
        if (n > 0 and @as(usize, @intCast(n)) < buf.len) return buf[0..@intCast(n)];
        return null;
    }

    if (comptime @import("builtin").os.tag == .macos) {
        var size: u32 = @intCast(buf.len);
        const rc = std.c._NSGetExecutablePath(buf.ptr, &size);
        if (rc != 0) return null;
        const len = std.mem.indexOfScalar(u8, buf[0..buf.len], 0) orelse return null;
        // _NSGetExecutablePath may return a symlinked or relative path, which
        // would derive ../lib from the wrong tree — resolve it to the real path
        // first. Fall back to the raw path if realpath fails.
        var resolved_buf: [std.posix.PATH_MAX]u8 = undefined;
        if (std.c.realpath(buf[0..len :0], &resolved_buf)) |resolved| {
            const rlen = std.mem.indexOfScalar(u8, resolved[0..resolved_buf.len], 0) orelse resolved_buf.len;
            if (rlen <= buf.len) {
                @memcpy(buf[0..rlen], resolved[0..rlen]);
                return buf[0..rlen];
            }
        }
        return buf[0..len];
    }

    if (comptime @import("builtin").os.tag == .freebsd) {
        // procfs is typically not mounted on FreeBSD; the kernel resolves
        // the canonical executable path via sysctl kern.proc.pathname
        // (pid -1 = calling process), so no realpath pass is needed.
        var mib = [4]c_int{ std.c.CTL.KERN, std.c.KERN.PROC, std.c.KERN.PROC_PATHNAME, -1 };
        var len: usize = buf.len;
        if (std.c.sysctl(&mib, mib.len, buf.ptr, &len, null, 0) != 0) return null;
        if (len <= 1) return null;
        return buf[0 .. len - 1]; // len counts the terminating NUL
    }

    if (comptime @import("builtin").os.tag == .netbsd) {
        // Same kernel-canonical lookup as FreeBSD, but NetBSD files it under
        // the KERN_PROC_ARGS node: {KERN, PROC_ARGS, pid, PROC_PATHNAME},
        // pid -1 = calling process. procfs (which would offer
        // /proc/curproc/exe) is typically not mounted.
        var mib = [4]c_int{ std.c.CTL.KERN, std.c.KERN.PROC_ARGS, -1, std.c.KERN.PROC_PATHNAME };
        var len: usize = buf.len;
        if (std.c.sysctl(&mib, mib.len, buf.ptr, &len, null, 0) != 0) return null;
        if (len <= 1) return null;
        return buf[0 .. len - 1]; // len counts the terminating NUL
    }

    if (comptime @import("builtin").os.tag == .openbsd) {
        return openbsdExePath(buf);
    }

    return null;
}

/// OpenBSD self-exe resolution. Unlike FreeBSD/NetBSD, OpenBSD has no
/// `KERN_PROC_PATHNAME` — and no procfs — so there is no kernel-canonical
/// executable path to read. The portable route is the process's own
/// argv[0] (via `sysctl KERN_PROC_ARGS / KERN_PROC_ARGV`), resolved to an
/// absolute, canonical path with `realpath`:
///   - argv[0] containing a '/'  → realpath resolves it (absolute, or
///     relative to the cwd)
///   - a bare command name       → search `$PATH` for the first executable
///     match, then realpath it
/// Returns null if argv[0] is unavailable or nothing resolves; callers
/// (exe-relative lib discovery, `kaappi test` worker respawn) degrade to
/// other lib paths / argv[0], exactly as on a platform with no self-exe
/// lookup at all.
fn openbsdExePath(buf: []u8) ?[]const u8 {
    // KERN_PROC_ARGV returns an array of `char *` (relocated by the kernel
    // to point within the buffer we pass, NUL-terminated) followed by the
    // string data; the first pointer is argv[0]. A bounded scratch buffer
    // covers an ordinary argv — an oversized one returns ENOMEM here and we
    // degrade to null. Aligned so the pointer array can be read directly.
    var scratch: [16 * 1024]u8 align(@alignOf(usize)) = undefined;
    var mib = [4]c_int{
        std.c.CTL.KERN,
        std.c.KERN.PROC_ARGS,
        @intCast(std.c.getpid()),
        std.c.KERN.PROC_ARGV,
    };
    var len: usize = scratch.len;
    if (std.c.sysctl(&mib, mib.len, &scratch, &len, null, 0) != 0) return null;

    const argv: [*]const ?[*:0]const u8 = @ptrCast(&scratch);
    const arg0 = argv[0] orelse return null;
    if (std.mem.sliceTo(arg0, 0).len == 0) return null;

    var real: [std.posix.PATH_MAX]u8 = undefined;

    if (std.mem.indexOfScalar(u8, std.mem.sliceTo(arg0, 0), '/') != null) {
        // Absolute, or relative to the cwd — realpath handles both.
        return realpathInto(arg0, &real, buf);
    }

    // Bare command name: resolve against $PATH, first executable wins.
    const path_env = platform.getenv("PATH") orelse return null;
    const path = std.mem.sliceTo(path_env, 0);
    const name = std.mem.sliceTo(arg0, 0);
    const X_OK: c_int = 1; // execute permission (POSIX, universal)
    var it = std.mem.splitScalar(u8, path, ':');
    var cand: [std.posix.PATH_MAX]u8 = undefined;
    while (it.next()) |dir| {
        const d = if (dir.len == 0) "." else dir; // empty PATH entry == cwd
        const total = d.len + 1 + name.len;
        if (total + 1 > cand.len) continue;
        @memcpy(cand[0..d.len], d);
        cand[d.len] = '/';
        @memcpy(cand[d.len + 1 ..][0..name.len], name);
        cand[total] = 0;
        const cpath = cand[0..total :0];
        // access(X_OK) also succeeds for a searchable directory, and realpath
        // would then return that directory — require a regular file so a
        // $PATH entry that is a directory named like the program is skipped.
        if (std.c.access(cpath.ptr, X_OK) != 0 or platform.isDir(cpath)) continue;
        return realpathInto(cpath.ptr, &real, buf);
    }
    return null;
}

/// Canonicalizes a NUL-terminated `path` with `realpath` into `real`, then
/// copies the result into `buf`. Returns null if realpath fails or the
/// result doesn't fit. Split out so both the argv[0] and the $PATH branch
/// of `openbsdExePath` share one copy of the fit/NUL handling.
fn realpathInto(path: [*:0]const u8, real: *[std.posix.PATH_MAX]u8, buf: []u8) ?[]const u8 {
    const resolved = std.c.realpath(path, real) orelse return null;
    const rlen = std.mem.sliceTo(resolved, 0).len;
    if (rlen == 0 or rlen > buf.len) return null;
    @memcpy(buf[0..rlen], resolved[0..rlen]);
    return buf[0..rlen];
}

pub fn getExeRelativeLibDir(buf: []u8) ?[]const u8 {
    var path_buf: [1024]u8 = undefined;
    const exe_path: []const u8 = getExePath(&path_buf) orelse "";
    return siblingLibDir(exe_path, buf);
}

test "siblingLibDir computes the parent-of-bin lib dir" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("/opt/kaappi/lib", siblingLibDir("/opt/kaappi/bin/kaappi", &buf).?);
}

test "siblingLibDir returns null for a bare filename with no directory" {
    var buf: [128]u8 = undefined;
    try std.testing.expect(siblingLibDir("kaappi", &buf) == null);
}

test "siblingLibDir returns null when the exe has no parent-of-parent dir" {
    var buf: [128]u8 = undefined;
    try std.testing.expect(siblingLibDir("/kaappi", &buf) == null);
}

test "siblingLibDir returns null for an exe only two levels below root" {
    // "/opt" has no further parent — must not collapse to a bare "/lib".
    var buf: [128]u8 = undefined;
    try std.testing.expect(siblingLibDir("/opt/kaappi", &buf) == null);
}

test "siblingLibDir returns null when the result doesn't fit the buffer" {
    var buf: [4]u8 = undefined;
    try std.testing.expect(siblingLibDir("/opt/kaappi/bin/kaappi", &buf) == null);
}

test "getExeRelativeLibDir returns a lib dir sibling to the exe's bin dir" {
    // The test binary itself is always deeply nested (zig-cache output
    // dirs on every supported platform), so this must not return null —
    // asserting that keeps a regression in the platform probe from
    // silently passing.
    var buf: [1024]u8 = undefined;
    const dir = getExeRelativeLibDir(&buf) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.endsWith(u8, dir, "/lib"));
}
