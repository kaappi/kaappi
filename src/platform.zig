//! Cross-platform syscall shim (Windows aarch64 target).
//!
//! The runtime's I/O layer is built on integer file descriptors with
//! POSIX read/write/open/close semantics. POSIX targets forward straight
//! to std.posix/std.c. Windows maps the same surface onto the C runtime's
//! low-level io layer (`_open`/`_read`/`_write`: integer fds, 0/1/2
//! preopened by the CRT) plus Win32 for what the CRT lacks (monotonic
//! clock, console modes, self-exe path, process spawning). Paths are
//! UTF-8 at every public boundary; Windows converts to UTF-16 internally
//! and calls the wide CRT entry points so non-ASCII paths work regardless
//! of the active ANSI code page.
//!
//! Fd readiness on Windows is socket-only (#1608 stage 1): ports whose
//! CRT fd wraps a SOCKET (isSocketFd probe) flip to non-blocking via
//! FIONBIO and get reactor-driven fiber suspension through WSAEventSelect
//! (reactor.zig's WindowsEventBackend), reading/writing through
//! sockRecv/sockSend. Pipes and files have no would-block mode at the CRT
//! layer, so their fiber I/O still degrades to blocking reads — the same
//! shape as a WASI host whose NONBLOCK probe fails. Sequential programs
//! and timer-driven fibers are unaffected either way.

const std = @import("std");
const builtin = @import("builtin");

pub const is_windows = builtin.os.tag == .windows;
pub const is_openbsd = builtin.os.tag == .openbsd;
pub const is_netbsd = builtin.os.tag == .netbsd;
const is_wasm = builtin.os.tag == .wasi;

/// CRT file descriptor on Windows; kernel fd elsewhere. i32 on every
/// supported target (std.posix.fd_t is i32 on all POSIX platforms).
pub const fd_t = i32;

/// Classic errno values — std.c.E defines the CRT's set for Windows
/// (INTR=4, AGAIN=11, ...), matching POSIX names for everything the
/// runtime checks.
pub const E = std.c.E;

// ---------------------------------------------------------------------------
// Windows externs live in platform_win.zig (split along the arch-specific
// seam per the file-size policy); re-exported here so call sites keep the
// established `platform.win.X` shape.
// ---------------------------------------------------------------------------

pub const win = @import("platform_win.zig").api;

/// Max path length for the UTF-16 conversion buffers. Windows' classic
/// limit is 260; longer works only with the registry long-path opt-in.
/// The buffer is sized generously — a conversion that doesn't fit fails
/// cleanly (error return) rather than truncating.
pub const wpath_max = 2048;
pub const WPathBuf = [wpath_max]u16;

/// UTF-8 → NUL-terminated UTF-16 for a wide CRT call. Null on invalid
/// UTF-8 or overflow.
pub fn widen(buf: *WPathBuf, path: []const u8) ?[:0]const u16 {
    if (!is_windows) return null;
    if (path.len >= wpath_max) return null;
    const n = std.unicode.wtf8ToWtf16Le(buf[0 .. wpath_max - 1], path) catch return null;
    buf[n] = 0;
    return buf[0..n :0];
}

// ---------------------------------------------------------------------------
// errno
// ---------------------------------------------------------------------------

/// std.posix.errno equivalent that also works on Windows (CRT errno).
/// CRT calls return exactly -1 on failure.
pub fn errno(rc: anytype) E {
    if (comptime is_windows) {
        return if (rc == -1) @enumFromInt(win._errno().*) else .SUCCESS;
    }
    return std.posix.errno(rc);
}

// ---------------------------------------------------------------------------
// read / write / close / isatty / pipe / dup2
// ---------------------------------------------------------------------------

pub fn write(fd: fd_t, buf: [*]const u8, len: usize) isize {
    if (comptime is_windows) {
        const n: c_uint = @intCast(@min(len, std.math.maxInt(c_int)));
        return @intCast(win._write(fd, buf, n));
    }
    return std.posix.system.write(fd, buf, len);
}

pub fn read(fd: fd_t, buf: [*]u8, len: usize) isize {
    if (comptime is_windows) {
        const n: c_uint = @intCast(@min(len, std.math.maxInt(c_int)));
        return @intCast(win._read(fd, buf, n));
    }
    return std.posix.system.read(fd, buf, len);
}

pub fn close(fd: fd_t) void {
    if (comptime is_windows) {
        // _close alone, even for socket-backed fds: the CRT owns the
        // handle (_open_osfhandle transferred it), and a closesocket
        // paired with _close would close the same handle value twice —
        // a TOCTOU where another thread's allocation can receive the
        // value between the two calls and get its handle closed out
        // from under it. CloseHandle (what _close performs) does tear
        // the socket down at the kernel (AFD) level — peers observe
        // FD_CLOSE/EOF normally — but ws2_32's user-mode per-handle
        // bookkeeping is never told, so a stale entry survives until a
        // future socket() reuses that handle value. That staleness is
        // neutralized where it would bite: isSocketFd only trusts
        // ws2_32 after a kernel-verified round-trip (see its comment),
        // so a file or pipe that recycles a dead socket's handle value
        // can never be misclassified as a socket (#1608).
        _ = win._close(fd);
        return;
    }
    _ = std.posix.system.close(fd);
}

pub fn isatty(fd: fd_t) bool {
    if (comptime is_windows) return win._isatty(fd) != 0;
    return std.c.isatty(fd) != 0;
}

pub fn pipe(fds: *[2]fd_t) c_int {
    if (comptime is_windows) return win._pipe(fds, 65536, win.O_BINARY | win.O_NOINHERIT);
    if (comptime is_wasm) return -1;
    return std.c.pipe(fds);
}

pub fn dup2(old: fd_t, new: fd_t) c_int {
    if (comptime is_windows) return win._dup2(old, new);
    return std.c.dup2(old, new);
}

pub fn dup(fd: fd_t) fd_t {
    if (comptime is_windows) return win._dup(fd);
    return std.c.dup(fd);
}

// ---------------------------------------------------------------------------
// Windows sockets (#1608 stage 1: socket readiness) live in
// platform_win_sock.zig — the natural seam once this file crossed the
// 1500-line policy. Re-exported here so this file stays the single public
// platform surface (`platform.sockRecv`, ...); the raw ws2_32/kernel32
// externs remain in `win` above, which reactor.zig, testing_helpers, and
// the socket module itself share.
// ---------------------------------------------------------------------------

const win_sock = @import("platform_win_sock.zig");
pub const ensureWinsock = win_sock.ensureWinsock;
pub const sockFromFd = win_sock.sockFromFd;
pub const isSocketFd = win_sock.isSocketFd;
pub const setSockNonblockingFd = win_sock.setSockNonblockingFd;
pub const sockRecv = win_sock.sockRecv;
pub const sockSend = win_sock.sockSend;

// Windows pipes (#1608 stage 2: polled pipe readiness) live in
// platform_win_pipe.zig, the same seam. fdKind is the port layer's
// first-touch classification (socket / pipe / other).
const win_pipe = @import("platform_win_pipe.zig");
pub const FdKind = win_pipe.FdKind;
pub const fdKind = win_pipe.fdKind;
pub const pipeHandleFromFd = win_pipe.pipeHandleFromFd;
pub const pipeRead = win_pipe.pipeRead;
pub const pipeWrite = win_pipe.pipeWrite;
pub const pipePollReady = win_pipe.pipePollReady;
pub const SockReadiness = win_sock.SockReadiness;
pub const sockPollReady = win_sock.sockPollReady;

// ---------------------------------------------------------------------------
// open — semantic wrappers instead of a flags struct: std.posix.O's layout
// is platform-specific and the runtime only ever uses these five shapes.
// ---------------------------------------------------------------------------

pub const OpenError = error{OpenFailed};

fn winOpen(path: []const u8, oflag: c_int, pmode: c_int) OpenError!fd_t {
    var wbuf: WPathBuf = undefined;
    const wpath = widen(&wbuf, path) orelse return error.OpenFailed;
    const fd = win._wopen(wpath.ptr, oflag | win.O_BINARY, pmode);
    if (fd < 0) return error.OpenFailed;
    return fd;
}

pub fn openRead(path: [:0]const u8) OpenError!fd_t {
    if (comptime is_windows) return winOpen(path, win.O_RDONLY, 0);
    return std.posix.openatZ(std.posix.AT.FDCWD, path, .{}, 0) catch error.OpenFailed;
}

pub fn openWriteTrunc(path: [:0]const u8, mode: u16) OpenError!fd_t {
    if (comptime is_windows) return winOpen(path, win.O_WRONLY | win.O_CREAT | win.O_TRUNC, 0o600);
    return std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, mode) catch error.OpenFailed;
}

pub fn openWriteTruncExcl(path: [:0]const u8, mode: u16) OpenError!fd_t {
    if (comptime is_windows) return winOpen(path, win.O_WRONLY | win.O_CREAT | win.O_TRUNC | win.O_EXCL, 0o600);
    return std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .EXCL = true }, mode) catch error.OpenFailed;
}

pub fn openAppend(path: [:0]const u8, mode: u16) OpenError!fd_t {
    if (comptime is_windows) return winOpen(path, win.O_WRONLY | win.O_CREAT | win.O_APPEND, 0o600);
    return std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, mode) catch error.OpenFailed;
}

/// Write-only sink for discarding output (/dev/null, NUL).
pub fn openNullSink() OpenError!fd_t {
    if (comptime is_windows) return winOpen("NUL", win.O_WRONLY, 0);
    return std.posix.openatZ(std.posix.AT.FDCWD, "/dev/null", .{ .ACCMODE = .WRONLY }, 0) catch error.OpenFailed;
}

// ---------------------------------------------------------------------------
// filesystem metadata / manipulation
// ---------------------------------------------------------------------------

pub fn unlink(path: [:0]const u8) c_int {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return -1;
        return win._wunlink(wpath.ptr);
    }
    return @intCast(std.posix.system.unlink(path));
}

pub fn mkdir(path: [:0]const u8, mode: u16) c_int {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return -1;
        return win._wmkdir(wpath.ptr);
    }
    return std.c.mkdir(path, mode);
}

pub fn rmdir(path: [:0]const u8) c_int {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return -1;
        return win._wrmdir(wpath.ptr);
    }
    return @intCast(std.posix.system.rmdir(path));
}

pub fn rename(old: [:0]const u8, new: [:0]const u8) c_int {
    if (comptime is_windows) {
        var wbuf_old: WPathBuf = undefined;
        var wbuf_new: WPathBuf = undefined;
        const wold = widen(&wbuf_old, old) orelse return -1;
        const wnew = widen(&wbuf_new, new) orelse return -1;
        // POSIX rename replaces an existing target and never destroys it
        // on failure. _wrename fails with EEXIST on an existing target,
        // and unlinking the target first would delete it even when the
        // rename then fails (worst case rename(x, x), which POSIX defines
        // as a successful no-op but unlink-first would turn into data
        // loss). MoveFileExW with REPLACE_EXISTING has the POSIX shape:
        // the destination is only replaced when the whole move succeeds.
        return if (win.MoveFileExW(wold.ptr, wnew.ptr, win.MOVEFILE_REPLACE_EXISTING) != 0) 0 else -1;
    }
    return @intCast(std.posix.system.rename(old, new));
}

pub fn chdir(path: [:0]const u8) c_int {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return -1;
        return win._wchdir(wpath.ptr);
    }
    return @intCast(std.posix.system.chdir(path));
}

/// Portable stat result — only the fields the runtime consumes.
pub const StatInfo = struct {
    size: u64,
    mtime_sec: i64,
    is_dir: bool,
    is_file: bool,
    /// Only set by lstatPath. POSIX symlinks report neither is_dir nor
    /// is_file; a Windows directory junction/symlink reports both
    /// is_symlink and is_dir (remove it with rmdir, never by recursing).
    is_symlink: bool = false,
};

pub fn statPath(path: [:0]const u8) ?StatInfo {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return null;
        var st: win.Stat64 = undefined;
        if (win._wstat64(wpath.ptr, &st) != 0) return null;
        const fmt = st.st_mode & win.S_IFMT;
        return .{
            .size = @intCast(@max(st.st_size, 0)),
            .mtime_sec = st.st_mtime,
            .is_dir = fmt == win.S_IFDIR,
            .is_file = fmt == win.S_IFREG,
        };
    }
    // This Zig's std.c has no plain stat(); the codebase's established
    // pattern (primitives_io.fileExistsP) is statx on Linux, fstatat
    // elsewhere.
    if (comptime builtin.os.tag == .linux) {
        const linux = std.os.linux;
        var sx: linux.Statx = undefined;
        const rc = linux.statx(@bitCast(@as(i32, std.posix.AT.FDCWD)), path, 0, linux.STATX.BASIC_STATS, &sx);
        if (rc > @as(usize, std.math.maxInt(isize))) return null;
        return .{
            .size = sx.size,
            .mtime_sec = sx.mtime.sec,
            .is_dir = sx.mode & std.posix.S.IFMT == std.posix.S.IFDIR,
            .is_file = sx.mode & std.posix.S.IFMT == std.posix.S.IFREG,
        };
    }
    var st: std.c.Stat = undefined;
    if (std.c.fstatat(std.posix.AT.FDCWD, path, &st, 0) != 0) return null;
    return .{
        .size = @intCast(@max(st.size, 0)),
        .mtime_sec = @intCast(st.mtime().sec),
        .is_dir = st.mode & std.posix.S.IFMT == std.posix.S.IFDIR,
        .is_file = st.mode & std.posix.S.IFMT == std.posix.S.IFREG,
    };
}

pub fn statFd(fd: fd_t) ?StatInfo {
    if (comptime is_windows) {
        var st: win.Stat64 = undefined;
        if (win._fstat64(fd, &st) != 0) return null;
        const fmt = st.st_mode & win.S_IFMT;
        return .{
            .size = @intCast(@max(st.st_size, 0)),
            .mtime_sec = st.st_mtime,
            .is_dir = fmt == win.S_IFDIR,
            .is_file = fmt == win.S_IFREG,
        };
    }
    if (comptime builtin.os.tag == .linux) {
        const linux = std.os.linux;
        var sx: linux.Statx = undefined;
        const rc = linux.statx(fd, "", linux.AT.EMPTY_PATH, linux.STATX.BASIC_STATS, &sx);
        if (rc > @as(usize, std.math.maxInt(isize))) return null;
        return .{
            .size = sx.size,
            .mtime_sec = sx.mtime.sec,
            .is_dir = sx.mode & std.posix.S.IFMT == std.posix.S.IFDIR,
            .is_file = sx.mode & std.posix.S.IFMT == std.posix.S.IFREG,
        };
    }
    var st: std.c.Stat = undefined;
    if (std.c.fstat(fd, &st) != 0) return null;
    return .{
        .size = @intCast(@max(st.size, 0)),
        .mtime_sec = @intCast(st.mtime().sec),
        .is_dir = st.mode & std.posix.S.IFMT == std.posix.S.IFDIR,
        .is_file = st.mode & std.posix.S.IFMT == std.posix.S.IFREG,
    };
}

/// lstat(2) equivalent: like statPath but never follows a symlink (or, on
/// Windows, a reparse point — junctions and directory symlinks report the
/// link itself). The recursive walkers (thottam_fs.zig) depend on this to
/// never traverse out of the tree they were pointed at. Windows uses
/// FindFirstFileW on the literal path, which reports the reparse point's
/// own attributes; drive roots ("C:/") are not queryable this way, and the
/// walkers never ask. WASI has no symlink-aware path here; it degrades to
/// statPath.
pub fn lstatPath(path: [:0]const u8) ?StatInfo {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return null;
        var data: win.Win32FindDataW = undefined;
        const h = win.FindFirstFileW(wpath.ptr, &data);
        if (h == win.INVALID_HANDLE_VALUE) return null;
        _ = win.FindClose(h);
        const is_dir = data.attributes & win.FILE_ATTRIBUTE_DIRECTORY != 0;
        // FILETIME: 100ns ticks since 1601; Unix epoch offset as in realTime.
        const ticks: i64 = (@as(i64, data.last_write_time.hi) << 32) | @as(i64, data.last_write_time.lo);
        return .{
            .size = (@as(u64, data.file_size_high) << 32) | @as(u64, data.file_size_low),
            .mtime_sec = @divFloor(ticks - 116444736000000000, 10_000_000),
            .is_dir = is_dir,
            .is_file = !is_dir,
            .is_symlink = data.attributes & win.FILE_ATTRIBUTE_REPARSE_POINT != 0,
        };
    }
    if (comptime is_wasm) return statPath(path);
    if (comptime builtin.os.tag == .linux) {
        const linux = std.os.linux;
        var sx: linux.Statx = undefined;
        const rc = linux.statx(@bitCast(@as(i32, std.posix.AT.FDCWD)), path, linux.AT.SYMLINK_NOFOLLOW, linux.STATX.BASIC_STATS, &sx);
        if (rc > @as(usize, std.math.maxInt(isize))) return null;
        return .{
            .size = sx.size,
            .mtime_sec = sx.mtime.sec,
            .is_dir = sx.mode & std.posix.S.IFMT == std.posix.S.IFDIR,
            .is_file = sx.mode & std.posix.S.IFMT == std.posix.S.IFREG,
            .is_symlink = sx.mode & std.posix.S.IFMT == std.posix.S.IFLNK,
        };
    }
    var st: std.c.Stat = undefined;
    if (std.c.fstatat(std.posix.AT.FDCWD, path, &st, std.posix.AT.SYMLINK_NOFOLLOW) != 0) return null;
    return .{
        .size = @intCast(@max(st.size, 0)),
        .mtime_sec = @intCast(st.mtime().sec),
        .is_dir = st.mode & std.posix.S.IFMT == std.posix.S.IFDIR,
        .is_file = st.mode & std.posix.S.IFMT == std.posix.S.IFREG,
        .is_symlink = st.mode & std.posix.S.IFMT == std.posix.S.IFLNK,
    };
}

pub fn pathExists(path: [:0]const u8) bool {
    return statPath(path) != null;
}

extern "c" fn chmod(path: [*:0]const u8, mode: std.c.mode_t) c_int;

/// Best-effort "make deletable/traversable": clears the Windows read-only
/// attribute (git marks pack/object files read-only, which makes _wunlink
/// fail where POSIX unlink succeeds), chmod u+rwx on POSIX (covers
/// unwritable directories, whose entries POSIX refuses to unlink). Used on
/// the retry path of recursive removal; no-op on WASI.
pub fn makeWritable(path: [:0]const u8) void {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return;
        _ = win._wchmod(wpath.ptr, win.S_IREAD | win.S_IWRITE);
        return;
    }
    if (comptime is_wasm) return;
    _ = chmod(path, 0o700);
}

/// Inverse of makeWritable, for tests that reproduce git's read-only
/// object files: sets the Windows read-only attribute / POSIX r-x mode.
pub fn makeReadOnly(path: [:0]const u8) void {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return;
        _ = win._wchmod(wpath.ptr, win.S_IREAD);
        return;
    }
    if (comptime is_wasm) return;
    _ = chmod(path, 0o555);
}

/// access(path, W_OK) equivalent.
pub fn accessWritable(path: [:0]const u8) bool {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return false;
        return win._waccess(wpath.ptr, 2) == 0;
    }
    return std.c.access(path, std.posix.W_OK) == 0;
}

/// Separator between entries of $PATH-style lists.
pub const path_list_sep: u8 = if (is_windows) ';' else ':';

/// Suffix an executable candidate needs on this platform ("" on POSIX).
pub const exe_suffix: []const u8 = if (is_windows) ".exe" else "";

/// File name `zig build lib` gives the native-backend runtime static
/// library on this platform: Zig names COFF archives `<name>.lib`, all
/// others `lib<name>.a`. `-lkaappi_rt` resolves either spelling, but the
/// existence probes (native_compiler.checkLibDir, doctor) must look for
/// the name that is actually on disk (#1610).
pub const rt_lib_name: []const u8 = if (is_windows) "kaappi_rt.lib" else "libkaappi_rt.a";

/// Longest path (bytes, incl. NUL) the canonicalization buffers hold.
pub const PATH_MAX: usize = if (is_windows) 4096 else std.posix.PATH_MAX;

/// Canonicalizes `path` into `buf` (which must hold PATH_MAX bytes).
/// POSIX realpath resolves symlinks and requires the file to exist;
/// Windows _wfullpath only normalizes lexically — both are stable
/// canonical keys for the same existing file, which is all the caller
/// (the bytecode cache) needs. Backslashes are normalized to '/' so keys
/// match however the path was spelled.
pub fn realPath(path: [:0]const u8, buf: []u8) ?[]const u8 {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, path) orelse return null;
        var wout: WPathBuf = undefined;
        if (win._wfullpath(&wout, wpath.ptr, wpath_max) == null) return null;
        const wlen = std.mem.indexOfScalar(u16, &wout, 0) orelse return null;
        // wtf16LeToWtf8 assumes the destination fits (it does not bounds
        // check); each u16 code unit expands to at most 3 WTF-8 bytes, so
        // preflight on that worst case.
        if (wlen * 3 > buf.len) return null;
        const n = std.unicode.wtf16LeToWtf8(buf, wout[0..wlen]);
        const out = buf[0..n];
        for (out) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        return out;
    }
    if (buf.len < PATH_MAX) return null;
    if (std.c.realpath(path, buf.ptr) == null) return null;
    const len = std.mem.indexOfScalar(u8, buf[0..PATH_MAX], 0) orelse return null;
    return buf[0..len];
}

pub fn isDir(path: [:0]const u8) bool {
    const st = statPath(path) orelse return false;
    return st.is_dir;
}

// ---------------------------------------------------------------------------
// directory iteration — CRT has no opendir; Windows uses FindFirstFileW.
// ---------------------------------------------------------------------------

/// NetBSD renamed the readdir family when dirent's layout changed in 3.0
/// (u64 d_fileno, wider d_namlen): modern code must call `__opendir30` /
/// `__readdir30`. The plain `opendir`/`readdir` symbols Zig's std.c binds
/// are the pre-3.0 compat pair, whose entries a modern `dirent` read
/// misparses — names come back shifted, so directory listings silently
/// miss every file. (`closedir` was not renamed — no dirent in its
/// signature.) Bind the versioned pair explicitly on NetBSD.
const netbsd_dir = struct {
    extern "c" fn __opendir30(path: [*:0]const u8) ?*std.c.DIR;
    extern "c" fn __readdir30(dir: *std.c.DIR) ?*std.c.dirent;
};
const opendir_sys = if (builtin.os.tag == .netbsd) netbsd_dir.__opendir30 else std.c.opendir;
const readdir_sys = if (builtin.os.tag == .netbsd) netbsd_dir.__readdir30 else std.c.readdir;

/// Minimal readdir-shaped iterator. Yields every entry including "." and
/// ".." (exactly like readdir) as UTF-8 names valid until the next call.
pub const DirIter = struct {
    const WinState = struct {
        handle: win.HANDLE,
        data: win.Win32FindDataW,
        /// First entry is produced by FindFirstFileW itself.
        first_pending: bool,
        name_buf: [1024]u8,
    };
    state: if (is_windows) WinState else *std.c.DIR,

    pub fn open(path: [:0]const u8) ?DirIter {
        if (comptime is_windows) {
            var pattern_buf: [wpath_max]u8 = undefined;
            const pattern = std.fmt.bufPrint(&pattern_buf, "{s}/*", .{path}) catch return null;
            var wbuf: WPathBuf = undefined;
            const wpattern = widen(&wbuf, pattern) orelse return null;
            var st: WinState = undefined;
            st.handle = win.FindFirstFileW(wpattern.ptr, &st.data);
            if (st.handle == win.INVALID_HANDLE_VALUE) return null;
            st.first_pending = true;
            return .{ .state = st };
        }
        const dh = opendir_sys(path) orelse return null;
        return .{ .state = dh };
    }

    pub fn next(self: *DirIter) ?[]const u8 {
        if (comptime is_windows) {
            const st = &self.state;
            if (!st.first_pending) {
                if (win.FindNextFileW(st.handle, &st.data) == 0) return null;
            }
            st.first_pending = false;
            const wname = std.mem.sliceTo(&st.data.file_name, 0);
            const n = std.unicode.wtf16LeToWtf8(&st.name_buf, wname);
            return st.name_buf[0..n];
        }
        const ent = readdir_sys(self.state) orelse return null;
        const name_ptr: [*:0]const u8 = @ptrCast(&ent.name);
        return std.mem.span(name_ptr);
    }

    pub fn close(self: *DirIter) void {
        if (comptime is_windows) {
            _ = win.FindClose(self.state.handle);
            return;
        }
        _ = std.c.closedir(self.state);
    }
};

/// Heap-allocated DirIter for callers that hand the iterator to a
/// GC-managed object (SRFI-170 directory streams): allocated from the
/// c allocator so the GC finalizer can destroy it without allocator
/// plumbing.
pub fn dirIterCreate(path: [:0]const u8) ?*DirIter {
    const it = std.heap.c_allocator.create(DirIter) catch return null;
    it.* = DirIter.open(path) orelse {
        std.heap.c_allocator.destroy(it);
        return null;
    };
    return it;
}

pub fn dirIterDestroy(it: *DirIter) void {
    it.close();
    std.heap.c_allocator.destroy(it);
}

// ---------------------------------------------------------------------------
// sleep
// ---------------------------------------------------------------------------

/// Blocking whole-thread sleep. The fiber layer never calls this (its
/// sleeps go through the reactor's bounded waits); only genuinely
/// synchronous paths do.
pub fn sleepNs(ns: u64) void {
    if (comptime is_windows) {
        const ms = (ns +| 999_999) / 1_000_000;
        win.Sleep(@intCast(@min(ms, win.INFINITE - 1)));
        return;
    }
    var ts: std.c.timespec = .{
        .sec = @intCast(ns / 1_000_000_000),
        .nsec = @intCast(ns % 1_000_000_000),
    };
    while (true) {
        const ret = std.c.nanosleep(&ts, &ts);
        if (ret == 0) break;
        if (errno(ret) != .INTR) break;
    }
}

/// Best-effort raise of the soft stack limit to the hard limit, called once
/// at process startup. OpenBSD's `default` login class caps the soft stack
/// at 4 MiB and NetBSD's defaults at 8 MiB — under the interpreter's
/// deep-recursion needs (the macro expander and nested compile recurse on
/// the machine stack). Both kernels ignore the ELF `PT_GNU_STACK` size hint
/// (`build.zig`'s `--stack`) and bound the main stack's on-demand growth by
/// RLIMIT_STACK at fault time, so raising the soft limit to the hard limit
/// (32 MiB on OpenBSD's default class, 64 MiB on NetBSD's) before any deep
/// recursion lets the stack grow that far. BSD-only and best-effort: a
/// no-op on every other platform — leaving their exact process setup
/// untouched — and silent on any rlimit failure. See docs/dev/openbsd.md
/// and docs/dev/netbsd.md.
pub fn raiseStackLimitBestEffort() void {
    if (comptime builtin.os.tag != .openbsd and builtin.os.tag != .netbsd) return;
    const lim = std.posix.getrlimit(.STACK) catch return;
    if (lim.cur >= lim.max) return;
    std.posix.setrlimit(.STACK, .{ .cur = lim.max, .max = lim.max }) catch {};
}

/// NetBSD/aarch64 starts every process with FPCR.FZ|DN set (0x3000000):
/// denormal operands and results flush to zero and NaN results collapse to
/// the default NaN. Flush-to-zero breaks IEEE-754 gradual underflow —
/// Scheme arithmetic visibly loses fl-least-class values (SRFI-144's
/// `(> fl-least 0.0)` turns false) — so reset the FP control register to
/// the all-zero IEEE default state every other platform boots with. FPCR
/// is inherited across pthread_create (verified on NetBSD 10.1), so one
/// call at process startup, before the interpreter worker or any SRFI-18
/// thread spawns, corrects every thread. No-op elsewhere: Linux, the BSDs
/// on x86_64, and macOS all start processes in the IEEE default mode.
pub fn normalizeFpEnvBestEffort() void {
    if (comptime builtin.os.tag == .netbsd and builtin.cpu.arch == .aarch64) {
        asm volatile ("msr fpcr, %[v]"
            :
            : [v] "r" (@as(u64, 0)),
        );
    }
}

// ---------------------------------------------------------------------------
// environment
// ---------------------------------------------------------------------------

/// CRT getenv — works on Windows too (mingw ucrt). Values are in the
/// active code page on Windows; ASCII-safe for the variables the runtime
/// reads (KAAPPI_HOME and friends may contain non-ASCII paths — those
/// round-trip correctly only when the system UTF-8 code page is enabled,
/// a documented Windows limitation for now).
pub fn getenv(name: [*:0]const u8) ?[*:0]const u8 {
    return std.c.getenv(name);
}

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
/// NetBSD renamed unsetenv when its return type changed (void → int,
/// POSIX alignment): the plain symbol is the void compat version, the
/// modern one is `__unsetenv13`. We ignore the return either way, but
/// bind the modern symbol for a correct signature (and to silence
/// NetBSD ld's .gnu.warning on the compat reference). setenv was never
/// renamed — the plain symbol is current there.
const netbsd_env = struct {
    extern "c" fn __unsetenv13(name: [*:0]const u8) c_int;
};
const unsetenv = if (builtin.os.tag == .netbsd) netbsd_env.__unsetenv13 else struct {
    extern "c" fn unsetenv(name: [*:0]const u8) c_int;
}.unsetenv;

/// setenv(3) equivalent. Windows CRT has no setenv; _putenv takes a
/// single "NAME=VALUE" string (which it copies).
pub fn setEnv(allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void {
    if (comptime is_windows) {
        const pair = try std.fmt.allocPrintSentinel(allocator, "{s}={s}", .{ name, value }, 0);
        defer allocator.free(pair);
        _ = win._putenv(pair.ptr);
        return;
    }
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);
    const value_z = try allocator.dupeZ(u8, value);
    defer allocator.free(value_z);
    _ = setenv(name_z, value_z, 1);
}

/// unsetenv(3) equivalent ("NAME=" removes the variable via _putenv).
pub fn unsetEnv(allocator: std.mem.Allocator, name: []const u8) !void {
    if (comptime is_windows) {
        const pair = try std.fmt.allocPrintSentinel(allocator, "{s}=", .{name}, 0);
        defer allocator.free(pair);
        _ = win._putenv(pair.ptr);
        return;
    }
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);
    _ = unsetenv(name_z);
}

extern "c" fn _getpid() c_int;

/// RtlGenRandom — the classic stable alias for cryptographic entropy on
/// Windows, avoiding the bcrypt DLL dance.
extern "advapi32" fn SystemFunction036(buf: [*]u8, len: u32) callconv(.winapi) u8;

/// 64 bits of OS entropy: getrandom on Linux, arc4random elsewhere,
/// RtlGenRandom on Windows. Falls back to the monotonic clock only if
/// the OS source fails.
pub fn randomSeed64() u64 {
    if (comptime is_windows) {
        var buf: [8]u8 = undefined;
        if (SystemFunction036(&buf, buf.len) != 0) return @bitCast(buf);
        return monotonicNs();
    }
    if (comptime builtin.os.tag == .linux) {
        var buf: [8]u8 = undefined;
        const rc = std.os.linux.getrandom(&buf, buf.len, 0);
        if (rc == buf.len) return @bitCast(buf);
        return monotonicNs();
    }
    if (comptime is_wasm) return monotonicNs();
    const arc4 = @extern(*const fn () callconv(.c) u32, .{ .name = "arc4random" });
    const lo: u64 = arc4();
    const hi: u64 = arc4();
    return (hi << 32) | lo;
}

/// Iterates "NAME=VALUE" environment entries as UTF-8 (each valid until
/// the next call). POSIX walks `environ`; Windows walks the wide
/// environment block.
pub const EnvIter = struct {
    const WinState = struct {
        block: ?[*]u16,
        offset: usize,
        buf: [8192]u8,
    };
    state: if (is_windows) WinState else usize,

    pub fn init() EnvIter {
        if (comptime is_windows) {
            const k32 = struct {
                extern "kernel32" fn GetEnvironmentStringsW() callconv(.winapi) ?[*]u16;
            };
            return .{ .state = .{ .block = k32.GetEnvironmentStringsW(), .offset = 0, .buf = undefined } };
        }
        return .{ .state = 0 };
    }

    pub fn next(self: *EnvIter) ?[]const u8 {
        if (comptime is_windows) {
            const st = &self.state;
            const block = st.block orelse return null;
            while (true) {
                const start = st.offset;
                var end = start;
                while (block[end] != 0) end += 1;
                if (end == start) return null; // double NUL: done
                st.offset = end + 1;
                // Preflight: wtf16LeToWtf8 does not bounds check (<= 3
                // bytes per u16 code unit); a pathologically long entry
                // (vars can reach 32 KiB) is skipped rather than
                // overflowing the fixed decode buffer.
                if ((end - start) * 3 > st.buf.len) continue;
                const n = std.unicode.wtf16LeToWtf8(&st.buf, block[start..end]);
                const entry = st.buf[0..n];
                // The block's first entries can be drive-letter cruft
                // starting with '='; skip those like every environ walker.
                if (entry.len > 0 and entry[0] == '=') continue;
                return entry;
            }
        }
        const environ_ptr = @extern(*[*:null]?[*:0]const u8, .{ .name = "environ" });
        const entry = environ_ptr.*[self.state] orelse return null;
        self.state += 1;
        return std.mem.sliceTo(entry, 0);
    }

    pub fn deinit(self: *EnvIter) void {
        if (comptime is_windows) {
            const k32 = struct {
                extern "kernel32" fn FreeEnvironmentStringsW(block: [*]u16) callconv(.winapi) c_int;
            };
            if (self.state.block) |b| _ = k32.FreeEnvironmentStringsW(b);
            self.state.block = null;
        }
    }
};

pub fn getPid() i64 {
    if (comptime is_windows) return @intCast(_getpid());
    return @intCast(std.c.getpid());
}

/// getcwd into `buf` (UTF-8; Windows result normalized to '/').
pub fn getCwd(buf: []u8) ?[]const u8 {
    if (comptime is_windows) {
        var wbuf: WPathBuf = undefined;
        if (win._wgetcwd(&wbuf, wpath_max) == null) return null;
        const wlen = std.mem.indexOfScalar(u16, &wbuf, 0) orelse return null;
        // Preflight: wtf16LeToWtf8 does not bounds check (<= 3 bytes per
        // u16 code unit).
        if (wlen * 3 > buf.len) return null;
        const n = std.unicode.wtf16LeToWtf8(buf, wbuf[0..wlen]);
        const out = buf[0..n];
        for (out) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        return out;
    }
    const result = std.c.getcwd(buf.ptr, buf.len) orelse return null;
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(result)), 0);
}

/// The platform scratch directory: $TMPDIR / /tmp on POSIX, $TEMP (with
/// $TMP and a fixed last resort) on Windows — which has no TMPDIR.
pub fn tempDir() []const u8 {
    if (comptime is_windows) {
        inline for (.{ "TEMP", "TMP" }) |name| {
            if (getenv(name)) |t| {
                const s = std.mem.sliceTo(t, 0);
                if (s.len > 0) return s;
            }
        }
        return "C:/Windows/Temp";
    }
    if (getenv("TMPDIR")) |t| {
        const s = std.mem.sliceTo(t, 0);
        if (s.len > 0) return s;
    }
    return "/tmp";
}

/// The platform temp-file *prefix* (directory + name stem) used by
/// SRFI-170's temp-file-prefix / create-temp-file. Written into `buf`
/// on Windows (where the temp dir is an env var); static elsewhere.
pub fn tempFilePrefix(buf: []u8) []const u8 {
    if (comptime is_windows) {
        const dir: []const u8 = blk: {
            if (getenv("TEMP")) |t| {
                const s = std.mem.sliceTo(t, 0);
                if (s.len > 0) break :blk s;
            }
            break :blk "C:/Windows/Temp";
        };
        return std.fmt.bufPrint(buf, "{s}/kaappi-", .{dir}) catch "kaappi-tmp-";
    }
    return "/tmp/kaappi-";
}

// ---------------------------------------------------------------------------
// clocks
// ---------------------------------------------------------------------------

var qpc_freq: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);

/// Monotonic clock in nanoseconds. QueryPerformanceCounter on Windows,
/// CLOCK_MONOTONIC elsewhere.
pub fn monotonicNs() u64 {
    if (comptime is_windows) {
        var freq = qpc_freq.load(.monotonic);
        if (freq == 0) {
            _ = win.QueryPerformanceFrequency(&freq);
            if (freq <= 0) freq = 1;
            qpc_freq.store(freq, .monotonic);
        }
        var counter: i64 = 0;
        _ = win.QueryPerformanceCounter(&counter);
        return @intCast(@divTrunc(@as(i128, counter) * std.time.ns_per_s, @as(i128, freq)));
    }
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

/// Wall clock as (seconds, nanoseconds) since the Unix epoch.
pub const RealTime = struct { sec: i64, nsec: i64 };

pub fn realTime() RealTime {
    if (comptime is_windows) {
        // FILETIME: 100ns ticks since 1601-01-01; the offset to the Unix
        // epoch is 11644473600 seconds.
        var ft: u64 = 0;
        win.GetSystemTimePreciseAsFileTime(&ft);
        const unix_ticks: i64 = @as(i64, @intCast(ft)) - 116444736000000000;
        return .{
            .sec = @divFloor(unix_ticks, 10_000_000),
            .nsec = @mod(unix_ticks, 10_000_000) * 100,
        };
    }
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    return .{ .sec = @intCast(ts.sec), .nsec = @intCast(ts.nsec) };
}

// ---------------------------------------------------------------------------
// console / terminal
// ---------------------------------------------------------------------------

/// One-time standard-stream setup, called at the top of every binary's
/// main. Windows only (no-op elsewhere):
///
/// * Put the CRT's preopened fds in binary mode. They default to text
///   mode, which rewrites `\n` to `\r\n` on write and strips `\r` /
///   treats ^Z as EOF on read — translations R7RS ports must never see
///   (files already open O_BINARY for the same reason, kaappi#1612).
///   The interactive console keeps rendering bare `\n` correctly (the
///   console's newline auto-return is independent of the CRT fd mode).
///   stdin is flipped only when it is NOT the interactive console: the
///   plain REPL's line reader relies on console text-mode input
///   (`\r\n` → `\n`, ^Z+Enter = EOF), while piped/redirected stdin gets
///   the byte-faithful POSIX behavior tests observe.
/// * Switch the console to UTF-8 in both directions and enable VT (ANSI
///   escape) processing so colored diagnostics and the REPL prompt render.
pub fn initStandardStreams() void {
    if (comptime !is_windows) return;
    _ = win._setmode(1, win.O_BINARY);
    _ = win._setmode(2, win.O_BINARY);
    if (!isatty(0)) _ = win._setmode(0, win.O_BINARY);
    _ = win.SetConsoleOutputCP(65001);
    _ = win.SetConsoleCP(65001);
    inline for (.{ win.STD_OUTPUT_HANDLE, win.STD_ERROR_HANDLE }) |which| {
        if (win.GetStdHandle(which)) |h| {
            if (h != win.INVALID_HANDLE_VALUE) {
                var mode: u32 = 0;
                if (win.GetConsoleMode(h, &mode) != 0) {
                    _ = win.SetConsoleMode(h, mode | win.ENABLE_VIRTUAL_TERMINAL_PROCESSING);
                }
            }
        }
    }
}

/// Terminal width in columns, or null when stdout isn't a terminal (or
/// the platform can't say).
pub fn terminalWidth() ?u16 {
    if (comptime is_windows) {
        const h = win.GetStdHandle(win.STD_OUTPUT_HANDLE) orelse return null;
        if (h == win.INVALID_HANDLE_VALUE) return null;
        var info: win.ConsoleScreenBufferInfo = undefined;
        if (win.GetConsoleScreenBufferInfo(h, &info) == 0) return null;
        const width = info.window.right - info.window.left + 1;
        if (width <= 0) return null;
        return @intCast(width);
    }
    if (comptime is_wasm) return null;
    var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const ret = std.c.ioctl(1, std.c.T.IOCGWINSZ, @intFromPtr(&ws));
    if (ret != 0 or ws.col == 0) return null;
    return ws.col;
}

// ---------------------------------------------------------------------------
// self-exe path
// ---------------------------------------------------------------------------

/// The running executable's absolute path, UTF-8, written into `buf`.
/// Windows: GetModuleFileNameW, with backslashes normalized to '/' so
/// every downstream path split/join (all written for '/') keeps working —
/// Win32 accepts forward slashes everywhere the runtime passes paths.
pub fn getExePathWindows(buf: []u8) ?[]const u8 {
    if (comptime !is_windows) return null;
    var wbuf: [wpath_max]u16 = undefined;
    const wlen = win.GetModuleFileNameW(null, &wbuf, wpath_max);
    if (wlen == 0 or wlen >= wpath_max) return null;
    // Preflight: wtf16LeToWtf8 does not bounds check (<= 3 bytes per u16
    // code unit), and callers pass buffers as small as 1024 bytes.
    if (wlen * 3 > buf.len) return null;
    const n = std.unicode.wtf16LeToWtf8(buf, wbuf[0..wlen]);
    const path = buf[0..n];
    for (path) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
    return path;
}

// ---------------------------------------------------------------------------
// dynamic library loading (C FFI)
// ---------------------------------------------------------------------------

/// Shared-library suffixes to probe, most specific first. ".so.6" covers
/// glibc's core libraries, where the unversioned .so is a linker script
/// dlopen cannot load.
pub const dl_suffixes: []const []const u8 = if (is_windows)
    &.{".dll"}
else
    &.{ ".dylib", ".so", ".so.6" };

var dl_error_buf: [128]u8 = undefined;
var dl_error_pending: bool = false;

/// dlopen(3). A null path opens the running process (POSIX self-handle /
/// GetModuleHandleW(null)); dlClose knows not to free that one, and on
/// Windows dlSym gives it dlopen(NULL) semantics by searching every
/// loaded module — so CRT symbols resolve even though they live in
/// ucrtbase.dll rather than the exe.
pub fn dlOpen(path: ?[*:0]const u8) ?*anyopaque {
    if (comptime is_windows) {
        const p = path orelse return win.GetModuleHandleW(null);
        var wbuf: WPathBuf = undefined;
        const wpath = widen(&wbuf, std.mem.sliceTo(p, 0)) orelse return null;
        const handle = win.LoadLibraryW(wpath.ptr);
        if (handle == null) dl_error_pending = true;
        return handle;
    }
    return std.c.dlopen(path, .{ .LAZY = true });
}

pub fn dlSym(handle: *anyopaque, name: [*:0]const u8) ?*anyopaque {
    if (comptime is_windows) {
        // The process self-handle from dlOpen(null): GetProcAddress on the
        // exe module alone finds nothing useful — mingw exes export no
        // symbols, and the CRT lives in ucrtbase.dll — so mirror POSIX
        // dlsym on the dlopen(NULL) global handle by probing every loaded
        // module in load order (exe first, like the ELF global scope).
        if (handle == win.GetModuleHandleW(null)) {
            var mods: [1024]win.HANDLE = undefined; // enough for any real process
            var needed: u32 = 0;
            if (win.K32EnumProcessModules(win.GetCurrentProcess(), &mods, @sizeOf(@TypeOf(mods)), &needed) != 0) {
                const count = @min(mods.len, needed / @sizeOf(win.HANDLE));
                for (mods[0..count]) |mod| {
                    if (win.GetProcAddress(mod, name)) |sym| return sym;
                }
            }
            dl_error_pending = true;
            return null;
        }
        const sym = win.GetProcAddress(handle, name);
        if (sym == null) dl_error_pending = true;
        return sym;
    }
    return std.c.dlsym(handle, name);
}

pub fn dlClose(handle: *anyopaque) void {
    if (comptime is_windows) {
        // The process self-handle (dlOpen(null)) takes no reference on
        // Windows; FreeLibrary on it would corrupt the exe module count.
        if (handle == win.GetModuleHandleW(null)) return;
        _ = win.FreeLibrary(handle);
        return;
    }
    _ = std.c.dlclose(handle);
}

/// dlerror(3): the last dlOpen/dlSym failure message, or null. Windows
/// reports the numeric GetLastError code (single-threaded consumer, same
/// as dlerror's own contract).
pub fn dlError() ?[*:0]const u8 {
    if (comptime is_windows) {
        if (!dl_error_pending) return null;
        dl_error_pending = false;
        const msg = std.fmt.bufPrintZ(&dl_error_buf, "Win32 error {d}", .{win.GetLastError()}) catch return null;
        return msg.ptr;
    }
    return std.c.dlerror();
}

// ---------------------------------------------------------------------------
// command-line args
// ---------------------------------------------------------------------------

/// Uniform argv iteration. POSIX/WASI iterate the raw argv block;
/// Windows must parse the process command line, which allocates. That
/// decode is process-lifetime by nature (yielded slices escape into
/// Options and library paths that live as long as argv would), so it
/// comes from the c allocator and is deliberately never freed — each
/// call site parses once per process, so nothing accumulates, and
/// leak-tracking test allocators never see it.
pub fn argsIterate(args: std.process.Args) std.process.Args.Iterator {
    if (comptime is_windows) {
        return args.iterateAllocator(std.heap.c_allocator) catch @panic("out of memory parsing command line");
    }
    return args.iterate();
}

// ---------------------------------------------------------------------------
// process spawning (Windows). POSIX keeps its fork/exec paths in
// thottam_proc.zig / native_compiler.zig / test_runner.zig — this is the
// CreateProcessW analogue those files call on Windows.
// ---------------------------------------------------------------------------

/// Quotes one argument per CommandLineToArgvW's rules (the inverse parse
/// every C runtime uses): wrap in quotes when it contains whitespace/
/// quotes or is empty; backslashes immediately before a quote (or the
/// closing quote) are doubled; embedded quotes get a backslash.
/// Pub (with buildCommandLineW) only for tests_platform.zig.
pub fn appendQuotedArg(list: *std.ArrayList(u8), allocator: std.mem.Allocator, arg: []const u8) !void {
    const needs_quotes = arg.len == 0 or std.mem.indexOfAny(u8, arg, " \t\"") != null;
    if (!needs_quotes) {
        try list.appendSlice(allocator, arg);
        return;
    }
    try list.append(allocator, '"');
    var backslashes: usize = 0;
    for (arg) |ch| {
        switch (ch) {
            '\\' => backslashes += 1,
            '"' => {
                try list.appendNTimes(allocator, '\\', backslashes * 2 + 1);
                backslashes = 0;
                try list.append(allocator, '"');
            },
            else => {
                try list.appendNTimes(allocator, '\\', backslashes);
                backslashes = 0;
                try list.append(allocator, ch);
            },
        }
    }
    try list.appendNTimes(allocator, '\\', backslashes * 2);
    try list.append(allocator, '"');
}

pub fn buildCommandLineW(allocator: std.mem.Allocator, argv: []const []const u8) ![:0]u16 {
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    for (argv, 0..) |arg, i| {
        if (i > 0) try line.append(allocator, ' ');
        try appendQuotedArg(&line, allocator, arg);
    }
    const wlen = std.unicode.calcWtf16LeLen(line.items) catch return error.InvalidName;
    const wline = try allocator.allocSentinel(u16, wlen, 0);
    errdefer allocator.free(wline);
    _ = std.unicode.wtf8ToWtf16Le(wline, line.items) catch return error.InvalidName;
    return wline;
}

pub const SpawnError = error{ SpawnFailed, CommandFailed, OutOfMemory, InvalidName };

/// Runs argv (argv[0] searched on PATH, .exe implied), waits, and returns
/// the exit code. Child inherits stdin/stdout/stderr.
pub fn winSpawnPassthrough(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) SpawnError!u8 {
    if (comptime !is_windows) unreachable;
    return winSpawnInner(allocator, argv, cwd, null, false);
}

const WinCapture = struct {
    list: *std.ArrayList(u8),
    /// Bytes kept; the read loop drains the pipe past this so the child
    /// never stalls on a full pipe.
    cap: usize = std.math.maxInt(usize),
};

/// Runs argv with stdout captured into the returned buffer (caller
/// frees); stderr is discarded. error.CommandFailed on nonzero exit.
pub fn winSpawnCapture(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) SpawnError![]u8 {
    if (comptime !is_windows) unreachable;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    const code = try winSpawnInner(allocator, argv, cwd, .{ .list = &out }, false);
    if (code != 0) return error.CommandFailed;
    return out.toOwnedSlice(allocator);
}

pub const WinSpawnResult = struct { output: []u8, exit_code: u8 };

/// Runs argv capturing combined stdout+stderr (the fork/dup2-both shape
/// test_runner's worker spawn uses); never errors on a nonzero exit —
/// the caller inspects the code. Output is capped at `cap` bytes (the
/// pipe keeps draining past it, so the child never blocks on a full
/// pipe), mirroring the POSIX call sites' in-loop caps.
pub fn winSpawnCaptureMerged(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, cap: usize) SpawnError!WinSpawnResult {
    if (comptime !is_windows) unreachable;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    const code = try winSpawnInner(allocator, argv, cwd, .{ .list = &out, .cap = cap }, true);
    return .{ .output = try out.toOwnedSlice(allocator), .exit_code = code };
}

fn winSpawnInner(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, capture: ?WinCapture, merge_stderr: bool) SpawnError!u8 {
    if (comptime !is_windows) unreachable;
    const cmdline = buildCommandLineW(allocator, argv) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidName,
    };
    defer allocator.free(cmdline);

    var wcwd_buf: WPathBuf = undefined;
    const wcwd: ?[*:0]const u16 = if (cwd) |c|
        (widen(&wcwd_buf, c) orelse return error.InvalidName).ptr
    else
        null;

    var si: win.StartupInfoW = .{ .cb = @sizeOf(win.StartupInfoW) };
    var pi: win.ProcessInformation = undefined;

    // Capture mode routes the child's stdout through a CRT pipe: the
    // write end is made inheritable via a dup (CRT pipes are created
    // NOINHERIT so the read end never leaks). stderr merges into the
    // same pipe or goes to NUL, per `merge_stderr`.
    var pipe_fds: [2]fd_t = undefined;
    var read_fd: fd_t = -1;
    var inherit: c_int = 0;
    var write_dup: fd_t = -1;
    var null_fd: fd_t = -1;
    if (capture != null) {
        if (win._pipe(&pipe_fds, 65536, win.O_BINARY | win.O_NOINHERIT) != 0) return error.SpawnFailed;
        read_fd = pipe_fds[0];
        write_dup = win._dup(pipe_fds[1]);
        _ = win._close(pipe_fds[1]);
        if (write_dup < 0) {
            _ = win._close(read_fd);
            return error.SpawnFailed;
        }
        si.flags = win.STARTF_USESTDHANDLES;
        si.std_input = @ptrFromInt(@as(usize, @bitCast(win._get_osfhandle(0))));
        si.std_output = @ptrFromInt(@as(usize, @bitCast(win._get_osfhandle(write_dup))));
        if (merge_stderr) {
            si.std_error = si.std_output;
        } else {
            null_fd = win._wopen(std.unicode.wtf8ToWtf16LeStringLiteral("NUL"), win.O_WRONLY, @as(c_int, 0));
            si.std_error = if (null_fd >= 0) @ptrFromInt(@as(usize, @bitCast(win._get_osfhandle(null_fd)))) else si.std_output;
        }
        inherit = 1;
    }

    const created = win.CreateProcessW(null, cmdline.ptr, null, null, inherit, 0, null, wcwd, &si, &pi);
    if (capture != null) {
        // Parent must drop its write end (and NUL) or the read loop
        // below never sees EOF.
        _ = win._close(write_dup);
        if (null_fd >= 0) _ = win._close(null_fd);
    }
    if (created == 0) {
        if (read_fd >= 0) _ = win._close(read_fd);
        return error.SpawnFailed;
    }

    if (capture) |cap| {
        var tmp: [4096]u8 = undefined;
        var read_err: ?SpawnError = null;
        while (true) {
            const n = win._read(read_fd, &tmp, tmp.len);
            if (n <= 0) break;
            const got: usize = @intCast(n);
            if (cap.list.items.len < cap.cap) {
                const room = cap.cap - cap.list.items.len;
                cap.list.appendSlice(allocator, tmp[0..@min(got, room)]) catch {
                    // Keep draining so the child can exit, but report the
                    // failure instead of returning truncated output as
                    // success.
                    read_err = error.OutOfMemory;
                    break;
                };
            }
        }
        if (read_err != null) {
            // Drain the remainder without buffering, then reap the child
            // before propagating.
            while (win._read(read_fd, &tmp, tmp.len) > 0) {}
        }
        _ = win._close(read_fd);
        if (read_err) |e| {
            _ = win.WaitForSingleObject(pi.process, win.INFINITE);
            _ = win.CloseHandle(pi.thread);
            _ = win.CloseHandle(pi.process);
            return e;
        }
    }

    _ = win.WaitForSingleObject(pi.process, win.INFINITE);
    var code: u32 = 0;
    _ = win.GetExitCodeProcess(pi.process, &code);
    _ = win.CloseHandle(pi.thread);
    _ = win.CloseHandle(pi.process);
    return @truncate(code);
}

// Tests live in tests_platform.zig (extracted when this file outgrew the
// 1500-line policy); appendQuotedArg/buildCommandLineW are pub for them.
