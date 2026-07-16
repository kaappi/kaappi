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
/// still find `libkaappi_rt.a` or the portable-library `.sld` sources it
/// was built alongside.
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

    return null;
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
