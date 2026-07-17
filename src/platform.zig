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
const is_wasm = builtin.os.tag == .wasi;

/// CRT file descriptor on Windows; kernel fd elsewhere. i32 on every
/// supported target (std.posix.fd_t is i32 on all POSIX platforms).
pub const fd_t = i32;

/// Classic errno values — std.c.E defines the CRT's set for Windows
/// (INTR=4, AGAIN=11, ...), matching POSIX names for everything the
/// runtime checks.
pub const E = std.c.E;

// ---------------------------------------------------------------------------
// Windows externs: CRT low-level io + the handful of Win32 calls we need.
// Public so reactor.zig (event backend) and repl.zig can reach the raw
// primitives without re-declaring them.
// ---------------------------------------------------------------------------

pub const win = if (is_windows) struct {
    pub const HANDLE = *anyopaque;
    pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));
    pub const INFINITE: u32 = 0xFFFF_FFFF;
    pub const WAIT_OBJECT_0: u32 = 0;
    pub const WAIT_TIMEOUT: u32 = 0x102;

    // --- CRT (ucrt via zig's bundled mingw-w64) ---
    pub extern "c" fn _write(fd: c_int, buf: [*]const u8, count: c_uint) c_int;
    pub extern "c" fn _read(fd: c_int, buf: [*]u8, count: c_uint) c_int;
    pub extern "c" fn _close(fd: c_int) c_int;
    pub extern "c" fn _isatty(fd: c_int) c_int;
    pub extern "c" fn _wopen(path: [*:0]const u16, oflag: c_int, ...) c_int;
    pub extern "c" fn _pipe(fds: *[2]c_int, size: c_uint, mode: c_int) c_int;
    pub extern "c" fn _dup(fd: c_int) c_int;
    pub extern "c" fn _dup2(old: c_int, new: c_int) c_int;
    pub extern "c" fn _errno() *c_int;
    pub extern "c" fn _wunlink(path: [*:0]const u16) c_int;
    pub extern "c" fn _wmkdir(path: [*:0]const u16) c_int;
    pub extern "c" fn _wrmdir(path: [*:0]const u16) c_int;
    pub extern "c" fn _wrename(old: [*:0]const u16, new: [*:0]const u16) c_int;
    pub extern "c" fn _wchdir(path: [*:0]const u16) c_int;
    pub extern "c" fn _wgetcwd(buf: [*]u16, size: c_int) ?[*:0]u16;
    pub extern "c" fn _wstat64(path: [*:0]const u16, st: *Stat64) c_int;
    pub extern "c" fn _fstat64(fd: c_int, st: *Stat64) c_int;
    pub extern "c" fn _lseeki64(fd: c_int, offset: i64, whence: c_int) i64;
    pub extern "c" fn _putenv(pair: [*:0]const u8) c_int;
    pub extern "c" fn _open_osfhandle(h: isize, flags: c_int) c_int;
    pub extern "c" fn _get_osfhandle(fd: c_int) isize;
    pub extern "c" fn _wfullpath(out: ?[*]u16, path: [*:0]const u16, size: usize) ?[*:0]u16;
    pub extern "c" fn _waccess(path: [*:0]const u16, mode: c_int) c_int;

    /// mingw ucrt `struct _stat64`. Field types (not manual offsets)
    /// reproduce the C layout: 2 bytes of tail padding after st_gid and 4
    /// before st_size fall out of natural alignment in an extern struct.
    pub const Stat64 = extern struct {
        st_dev: c_uint,
        st_ino: c_ushort,
        st_mode: c_ushort,
        st_nlink: c_short,
        st_uid: c_short,
        st_gid: c_short,
        st_rdev: c_uint,
        st_size: i64,
        st_atime: i64,
        st_mtime: i64,
        st_ctime: i64,
    };

    // CRT _open flags (io.h). O_BINARY everywhere: the CRT defaults to
    // text mode, which silently rewrites \n <-> \r\n and treats ^Z as EOF
    // — R7RS ports must see raw bytes.
    pub const O_RDONLY: c_int = 0x0000;
    pub const O_WRONLY: c_int = 0x0001;
    pub const O_RDWR: c_int = 0x0002;
    pub const O_APPEND: c_int = 0x0008;
    pub const O_CREAT: c_int = 0x0100;
    pub const O_TRUNC: c_int = 0x0200;
    pub const O_EXCL: c_int = 0x0400;
    pub const O_BINARY: c_int = 0x8000;
    pub const O_NOINHERIT: c_int = 0x0080;

    pub const S_IFMT: c_ushort = 0xF000;
    pub const S_IFDIR: c_ushort = 0x4000;
    pub const S_IFREG: c_ushort = 0x8000;

    // --- kernel32 ---
    pub extern "kernel32" fn CreateEventW(attrs: ?*anyopaque, manual_reset: c_int, initial_state: c_int, name: ?[*:0]const u16) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn SetEvent(h: HANDLE) callconv(.winapi) c_int;
    pub extern "kernel32" fn WaitForSingleObject(h: HANDLE, ms: u32) callconv(.winapi) u32;
    pub extern "kernel32" fn CloseHandle(h: HANDLE) callconv(.winapi) c_int;
    pub extern "kernel32" fn QueryPerformanceCounter(count: *i64) callconv(.winapi) c_int;
    pub extern "kernel32" fn QueryPerformanceFrequency(freq: *i64) callconv(.winapi) c_int;
    pub extern "kernel32" fn Sleep(ms: u32) callconv(.winapi) void;
    pub extern "kernel32" fn GetSystemTimePreciseAsFileTime(ft: *u64) callconv(.winapi) void;
    pub extern "kernel32" fn SetConsoleOutputCP(cp: u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn SetConsoleCP(cp: u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetStdHandle(which: u32) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn GetConsoleMode(h: HANDLE, mode: *u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn SetConsoleMode(h: HANDLE, mode: u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetConsoleScreenBufferInfo(h: HANDLE, info: *ConsoleScreenBufferInfo) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetModuleFileNameW(mod: ?*anyopaque, buf: [*]u16, size: u32) callconv(.winapi) u32;
    pub extern "kernel32" fn CreateProcessW(app: ?[*:0]const u16, cmdline: ?[*:0]u16, pattrs: ?*anyopaque, tattrs: ?*anyopaque, inherit: c_int, flags: u32, env: ?*anyopaque, cwd: ?[*:0]const u16, si: *StartupInfoW, pi: *ProcessInformation) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetExitCodeProcess(h: HANDLE, code: *u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn LoadLibraryW(name: [*:0]const u16) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn GetProcAddress(mod: HANDLE, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    pub extern "kernel32" fn FreeLibrary(mod: HANDLE) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetCurrentProcess() callconv(.winapi) HANDLE;
    // Exported from kernel32 since Windows 7 (the psapi.dll re-export era
    // predates every supported target).
    pub extern "kernel32" fn K32EnumProcessModules(process: HANDLE, modules: [*]HANDLE, cb: u32, needed: *u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    pub extern "kernel32" fn MoveFileExW(old: [*:0]const u16, new: [*:0]const u16, flags: u32) callconv(.winapi) c_int;
    pub const MOVEFILE_REPLACE_EXISTING: u32 = 0x1;
    pub extern "kernel32" fn FindFirstFileW(path: [*:0]const u16, data: *Win32FindDataW) callconv(.winapi) HANDLE;
    pub extern "kernel32" fn FindNextFileW(h: HANDLE, data: *Win32FindDataW) callconv(.winapi) c_int;
    pub extern "kernel32" fn FindClose(h: HANDLE) callconv(.winapi) c_int;
    pub extern "kernel32" fn WaitForMultipleObjects(count: u32, handles: [*]const HANDLE, wait_all: c_int, ms: u32) callconv(.winapi) u32;
    pub extern "kernel32" fn ResetEvent(h: HANDLE) callconv(.winapi) c_int;

    // --- ws2_32 (Winsock): the socket-readiness slice of #1608. SOCKETs
    // reach the runtime as CRT fds (`_open_osfhandle`); these calls operate
    // on the underlying SOCKET recovered via `_get_osfhandle`. ---
    pub const SOCKET = usize;
    pub const INVALID_SOCKET: SOCKET = ~@as(SOCKET, 0);
    pub const SOCKET_ERROR: c_int = -1;

    // WSAEventSelect network-event mask bits and their WSANETWORKEVENTS
    // iErrorCode indices (winsock2.h).
    pub const FD_READ: c_long = 0x01;
    pub const FD_WRITE: c_long = 0x02;
    pub const FD_OOB: c_long = 0x04;
    pub const FD_ACCEPT: c_long = 0x08;
    pub const FD_CONNECT: c_long = 0x10;
    pub const FD_CLOSE: c_long = 0x20;

    pub const SOL_SOCKET: c_int = 0xFFFF;
    pub const SO_TYPE: c_int = 0x1008;
    /// ioctlsocket command: FIONBIO (_IOW('f', 126, u_long)).
    pub const FIONBIO: c_long = @bitCast(@as(u32, 0x8004667E));

    pub const WSAEINTR: c_int = 10004;
    pub const WSAEWOULDBLOCK: c_int = 10035;
    pub const WSAENOTSOCK: c_int = 10038;
    pub const WSAENETRESET: c_int = 10052;
    pub const WSAECONNABORTED: c_int = 10053;
    pub const WSAECONNRESET: c_int = 10054;
    pub const WSAESHUTDOWN: c_int = 10058;

    /// WSADATA is only ever written by WSAStartup and never read back by
    /// the runtime; an opaque, generously sized buffer avoids reproducing
    /// its per-arch layout (~400 bytes on 64-bit).
    pub const WSAData = extern struct { opaque_bytes: [512]u8 align(8) };

    pub const WSANetworkEvents = extern struct {
        network_events: c_long,
        error_codes: [10]c_int,
    };

    /// Single-socket fd_set: the runtime only ever selects one socket at a
    /// time (the post-arm readiness probe), so the 64-slot winsock2.h
    /// layout is declared but never filled past count = 1.
    pub const FdSet = extern struct { count: c_uint, array: [64]SOCKET };
    pub const Timeval = extern struct { sec: c_long, usec: c_long };

    pub const FILE_TYPE_DISK: u32 = 0x1;
    pub const FILE_TYPE_PIPE: u32 = 0x3;
    pub extern "kernel32" fn GetFileType(h: HANDLE) callconv(.winapi) u32;

    pub extern "ws2_32" fn WSAStartup(version: u16, data: *WSAData) callconv(.winapi) c_int;
    pub extern "ws2_32" fn closesocket(s: SOCKET) callconv(.winapi) c_int;
    pub extern "ws2_32" fn WSAGetLastError() callconv(.winapi) c_int;
    pub extern "ws2_32" fn WSAEventSelect(s: SOCKET, event: ?HANDLE, events: c_long) callconv(.winapi) c_int;
    pub extern "ws2_32" fn WSAEnumNetworkEvents(s: SOCKET, event: ?HANDLE, ne: *WSANetworkEvents) callconv(.winapi) c_int;
    pub extern "ws2_32" fn recv(s: SOCKET, buf: [*]u8, len: c_int, flags: c_int) callconv(.winapi) c_int;
    pub extern "ws2_32" fn send(s: SOCKET, buf: [*]const u8, len: c_int, flags: c_int) callconv(.winapi) c_int;
    pub extern "ws2_32" fn ioctlsocket(s: SOCKET, cmd: c_long, argp: *c_ulong) callconv(.winapi) c_int;
    pub extern "ws2_32" fn getsockopt(s: SOCKET, level: c_int, optname: c_int, optval: [*]u8, optlen: *c_int) callconv(.winapi) c_int;
    pub extern "ws2_32" fn select(nfds: c_int, readfds: ?*FdSet, writefds: ?*FdSet, exceptfds: ?*FdSet, timeout: ?*const Timeval) callconv(.winapi) c_int;

    pub const FileTime = extern struct { lo: u32, hi: u32 };
    pub const Win32FindDataW = extern struct {
        attributes: u32,
        creation_time: FileTime,
        last_access_time: FileTime,
        last_write_time: FileTime,
        file_size_high: u32,
        file_size_low: u32,
        reserved0: u32,
        reserved1: u32,
        file_name: [260]u16,
        alternate_file_name: [14]u16,
    };
    pub const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;

    pub const STD_OUTPUT_HANDLE: u32 = @bitCast(@as(i32, -11));
    pub const STD_ERROR_HANDLE: u32 = @bitCast(@as(i32, -12));
    pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;

    pub const Coord = extern struct { x: i16, y: i16 };
    pub const SmallRect = extern struct { left: i16, top: i16, right: i16, bottom: i16 };
    pub const ConsoleScreenBufferInfo = extern struct {
        size: Coord,
        cursor_position: Coord,
        attributes: u16,
        window: SmallRect,
        maximum_window_size: Coord,
    };

    pub const StartupInfoW = extern struct {
        cb: u32,
        reserved: ?[*:0]u16 = null,
        desktop: ?[*:0]u16 = null,
        title: ?[*:0]u16 = null,
        x: u32 = 0,
        y: u32 = 0,
        x_size: u32 = 0,
        y_size: u32 = 0,
        x_count_chars: u32 = 0,
        y_count_chars: u32 = 0,
        fill_attribute: u32 = 0,
        flags: u32 = 0,
        show_window: u16 = 0,
        reserved2: u16 = 0,
        reserved3: ?*anyopaque = null,
        std_input: ?HANDLE = null,
        std_output: ?HANDLE = null,
        std_error: ?HANDLE = null,
    };
    pub const STARTF_USESTDHANDLES: u32 = 0x0100;

    pub const ProcessInformation = extern struct {
        process: HANDLE,
        thread: HANDLE,
        process_id: u32,
        thread_id: u32,
    };
} else struct {};

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
        // Try closesocket first, unconditionally: a socket must NOT be
        // closed by CloseHandle alone (_close's mechanism) — ws2_32's
        // user-mode per-handle state is never told, and once the OS
        // recycles the handle value for an ordinary file, that stale
        // entry makes getsockopt falsely claim the file is a socket
        // (observed: silently dropped writes on a file port whose fd
        // recycled a socket's, #1608). On a non-socket fd closesocket
        // returns WSAENOTSOCK without touching the handle; on a socket
        // it both frees the ws2_32 state and closes the handle, leaving
        // _close to release the CRT fd slot (its CloseHandle failing
        // benignly).
        const h = win._get_osfhandle(fd);
        if (h != -1 and h != -2) _ = win.closesocket(@bitCast(h));
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
// Windows sockets (#1608 stage 1: socket readiness).
//
// The runtime's contract on Windows: a socket enters the port layer as a
// CRT fd created with `_open_osfhandle((intptr_t)sock, 0)` — the fd both
// closes uniformly through platform.close (which handles the
// closesocket/_close split; see its comment) and recovers its SOCKET via
// `_get_osfhandle` for the calls below. CRT `_read`/`_write` cannot
// operate on SOCKET handles at all (sockets are OVERLAPPED by default,
// which plain ReadFile/WriteFile rejects), so socket ports read and
// write through sockRecv/sockSend instead — blocking or not — which
// translate Winsock errors onto the CRT errno values the shared port
// paths already check (EAGAIN/EINTR). Everything here is a comptime
// no-op off Windows.
// ---------------------------------------------------------------------------

var winsock_ready = std.atomic.Value(bool).init(false);
var winsock_mutex: std.atomic.Mutex = .unlocked;

/// Idempotent, thread-safe WSAStartup. Never paired with WSACleanup — the
/// socket layer lives for the process, the same lifetime discipline as the
/// CRT fd table itself. The spinlock (the symbol_mutex pattern) only ever
/// spins on the one-time first call racing another thread.
pub fn ensureWinsock() void {
    if (comptime !is_windows) return;
    if (winsock_ready.load(.acquire)) return;
    while (!winsock_mutex.tryLock()) std.atomic.spinLoopHint();
    defer winsock_mutex.unlock();
    if (winsock_ready.load(.acquire)) return;
    var data: win.WSAData = undefined;
    _ = win.WSAStartup(0x0202, &data);
    winsock_ready.store(true, .release);
}

/// The SOCKET behind a CRT fd, or null if the fd is invalid/unassociated.
/// Callers must have established that the fd wraps a socket (isSocketFd)
/// before treating the handle as one.
pub fn sockFromFd(fd: fd_t) ?win.SOCKET {
    const h = win._get_osfhandle(fd);
    // -1 is INVALID_HANDLE_VALUE (bad fd), -2 the CRT's "fd has no
    // associated stream" marker.
    if (h == -1 or h == -2) return null;
    return @bitCast(h);
}

/// Whether the CRT fd wraps a SOCKET: GetFileType must report PIPE (what
/// sockets report; disk files report DISK) AND getsockopt(SO_TYPE) must
/// succeed — non-sockets fail WSAENOTSOCK. This is the port layer's
/// one-time readiness capability check (maybeSetNonblocking), the Windows
/// analogue of WASI's fd_fdstat_set_flags probe. The GetFileType
/// cross-check is load-bearing, not belt-and-braces: ws2_32 keys its
/// per-socket state by handle value, so a socket closed behind its back
/// (CloseHandle without closesocket — e.g. by foreign FFI code) leaves a
/// stale entry that makes getsockopt "succeed" for whatever ordinary file
/// later recycles that handle value (#1608). platform.close prevents the
/// runtime itself from creating such entries.
pub fn isSocketFd(fd: fd_t) bool {
    if (comptime !is_windows) return false;
    ensureWinsock();
    const raw = win._get_osfhandle(fd);
    if (raw == -1 or raw == -2) return false;
    const handle: win.HANDLE = @ptrFromInt(@as(usize, @bitCast(raw)));
    if (win.GetFileType(handle) != win.FILE_TYPE_PIPE) return false;
    const sock: win.SOCKET = @bitCast(raw);
    var sotype: c_int = 0;
    var optlen: c_int = @sizeOf(c_int);
    return win.getsockopt(sock, win.SOL_SOCKET, win.SO_TYPE, @ptrCast(&sotype), &optlen) == 0;
}

/// Flips the socket behind `fd` to non-blocking (FIONBIO). Returns false
/// if the fd is not a live socket.
pub fn setSockNonblockingFd(fd: fd_t) bool {
    if (comptime !is_windows) return false;
    ensureWinsock();
    const sock = sockFromFd(fd) orelse return false;
    var one: c_ulong = 1;
    return win.ioctlsocket(sock, win.FIONBIO, &one) == 0;
}

/// Winsock error → CRT errno value, covering what the shared port paths
/// distinguish (AGAIN parks the fiber, INTR retries); everything else only
/// needs to be recognizably "some other error".
fn crtErrnoFromWsa(wsa_err: c_int) c_int {
    const e: E = switch (wsa_err) {
        win.WSAEWOULDBLOCK => .AGAIN,
        win.WSAEINTR => .INTR,
        win.WSAECONNRESET, win.WSAECONNABORTED, win.WSAENETRESET => .CONNRESET,
        win.WSAESHUTDOWN => .PIPE,
        win.WSAENOTSOCK => .BADF,
        else => .IO,
    };
    return @intFromEnum(e);
}

/// read(2)-shaped recv() on the socket behind a CRT fd: returns bytes read,
/// 0 at orderly shutdown (EOF), or -1 with the CRT errno set so
/// platform.errno() reports .AGAIN/.INTR exactly like a POSIX socket read.
pub fn sockRecv(fd: fd_t, buf: [*]u8, len: usize) isize {
    if (comptime !is_windows) return -1;
    const sock = sockFromFd(fd) orelse {
        win._errno().* = @intFromEnum(E.BADF);
        return -1;
    };
    const n: c_int = @intCast(@min(len, std.math.maxInt(c_int)));
    const rc = win.recv(sock, buf, n, 0);
    if (rc == win.SOCKET_ERROR) {
        win._errno().* = crtErrnoFromWsa(win.WSAGetLastError());
        return -1;
    }
    return rc;
}

/// write(2)-shaped send() on the socket behind a CRT fd; error contract as
/// sockRecv.
pub fn sockSend(fd: fd_t, buf: [*]const u8, len: usize) isize {
    if (comptime !is_windows) return -1;
    const sock = sockFromFd(fd) orelse {
        win._errno().* = @intFromEnum(E.BADF);
        return -1;
    };
    const n: c_int = @intCast(@min(len, std.math.maxInt(c_int)));
    const rc = win.send(sock, buf, n, 0);
    if (rc == win.SOCKET_ERROR) {
        win._errno().* = crtErrnoFromWsa(win.WSAGetLastError());
        return -1;
    }
    return rc;
}

pub const SockReadiness = struct { readable: bool = false, writable: bool = false };

/// 0-timeout select() snapshot of the socket's current readiness in the
/// requested directions. An exceptional condition — or select() itself
/// failing on a dead socket — reports every requested direction ready:
/// a spurious wake is always safe under the park-and-retry protocol (the
/// retried syscall surfaces the real outcome), a missed one hangs forever.
pub fn sockPollReady(sock: win.SOCKET, want_read: bool, want_write: bool) SockReadiness {
    var rset: win.FdSet = .{ .count = 1, .array = undefined };
    rset.array[0] = sock;
    var wset = rset;
    var xset = rset;
    var tv: win.Timeval = .{ .sec = 0, .usec = 0 };
    const rc = win.select(
        0, // nfds is ignored on Windows
        if (want_read) &rset else null,
        if (want_write) &wset else null,
        &xset,
        &tv,
    );
    if (rc == win.SOCKET_ERROR) return .{ .readable = want_read, .writable = want_write };
    const broken = xset.count > 0;
    return .{
        .readable = want_read and (broken or rset.count > 0),
        .writable = want_write and (broken or wset.count > 0),
    };
}

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

pub fn pathExists(path: [:0]const u8) bool {
    return statPath(path) != null;
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
        const dh = std.c.opendir(path) orelse return null;
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
        const ent = std.c.readdir(self.state) orelse return null;
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
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

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

/// One-time console setup. Windows: switch the console to UTF-8 in both
/// directions and enable VT (ANSI escape) processing so colored
/// diagnostics and the REPL prompt render. No-op elsewhere.
pub fn initConsole() void {
    if (comptime !is_windows) return;
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
fn appendQuotedArg(list: *std.ArrayList(u8), allocator: std.mem.Allocator, arg: []const u8) !void {
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

fn buildCommandLineW(allocator: std.mem.Allocator, argv: []const []const u8) ![:0]u16 {
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

// ---------------------------------------------------------------------------
// tests (run on the host platform; the Windows arms are exercised by the
// cross-compiled unit-test binary on a Windows machine)
// ---------------------------------------------------------------------------

fn expectQuoted(expected: []const u8, arg: []const u8) !void {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try appendQuotedArg(&list, std.testing.allocator, arg);
    try std.testing.expectEqualStrings(expected, list.items);
}

// CommandLineToArgvW-inverse quoting: these are the canonical cases from
// the Windows command-line parsing rules; the child's CRT must parse each
// quoted form back to the original argument.
test "appendQuotedArg: plain arg unquoted" {
    try expectQuoted("abc", "abc");
}

test "appendQuotedArg: spaces force quotes" {
    try expectQuoted("\"two words\"", "two words");
}

test "appendQuotedArg: empty arg becomes empty quotes" {
    try expectQuoted("\"\"", "");
}

test "appendQuotedArg: embedded quote gets a backslash" {
    try expectQuoted("\"say \\\" it\"", "say \" it");
}

test "appendQuotedArg: backslashes before a quote double" {
    // arg: a\"b  →  "a\\\"b" (the two backslashes encode one literal \,
    // the third escapes the quote)
    try expectQuoted("\"a\\\\\\\"b\"", "a\\\"b");
}

test "appendQuotedArg: trailing backslashes double before the closing quote" {
    // arg: dir\ with a space → "dir \\" so the closing quote isn't eaten
    try expectQuoted("\"dir \\\\\"", "dir \\");
}

test "appendQuotedArg: backslashes not before a quote stay literal" {
    // Windows paths with spaces: no doubling mid-string
    try expectQuoted("\"C:\\Program Files\\kaappi\"", "C:\\Program Files\\kaappi");
}

test "buildCommandLineW joins and round-trips through WTF-16" {
    const argv = [_][]const u8{ "git", "-C", "C:\\repo dir", "checkout", "v1.0.0", "--" };
    const wline = try buildCommandLineW(std.testing.allocator, &argv);
    defer std.testing.allocator.free(wline);
    var narrow: [256]u8 = undefined;
    const n = std.unicode.wtf16LeToWtf8(&narrow, wline);
    try std.testing.expectEqualStrings("git -C \"C:\\repo dir\" checkout v1.0.0 --", narrow[0..n]);
}

test "monotonicNs advances" {
    const a = monotonicNs();
    const b = monotonicNs();
    try std.testing.expect(b >= a);
}

test "realTime is after 2020" {
    const rt = realTime();
    try std.testing.expect(rt.sec > 1577836800); // 2020-01-01
    try std.testing.expect(rt.nsec >= 0 and rt.nsec < 1_000_000_000);
}

test "statPath reports a directory" {
    if (comptime is_wasm) return error.SkipZigTest;
    const cwd_path = if (is_windows) "." else "/tmp";
    const st = statPath(cwd_path) orelse return error.TestUnexpectedResult;
    try std.testing.expect(st.is_dir);
    try std.testing.expect(!st.is_file);
}

test "write to stdout-like sink via openNullSink" {
    if (comptime is_wasm) return error.SkipZigTest;
    const fd = try openNullSink();
    defer close(fd);
    const msg = "platform shim probe\n";
    const rc = write(fd, msg.ptr, msg.len);
    try std.testing.expect(rc == @as(isize, @intCast(msg.len)));
}

test "dlSym on the dlOpen(null) process handle finds CRT symbols (#1611)" {
    // The (ffi-open #f) contract: the process handle resolves C runtime
    // symbols — on Windows via the all-loaded-modules search (abs lives in
    // ucrtbase.dll, never in the exe's export table), on POSIX via dlsym's
    // global symbol scope.
    if (comptime is_wasm) return error.SkipZigTest;
    if (comptime builtin.target.abi.isMusl()) return error.SkipZigTest; // static libc: no dynamic loading
    const proc = dlOpen(null) orelse return error.TestUnexpectedResult;
    defer dlClose(proc);
    try std.testing.expect(dlSym(proc, "abs") != null);
    // A miss reports failure without poisoning later lookups.
    try std.testing.expect(dlSym(proc, "kaappi_no_such_symbol_1611") == null);
    _ = dlError();
    try std.testing.expect(dlSym(proc, "abs") != null);
}
