//! Windows syscall externs: the CRT low-level io layer (ucrt via zig's
//! bundled mingw-w64) plus the handful of Win32 calls the runtime needs.
//! Split out of platform.zig along the file-size policy's natural
//! arch-specific seam; platform.zig re-exports this namespace as
//! `platform.win`, so call sites are unchanged. Public so reactor.zig
//! (event backend) and repl.zig can reach the raw primitives without
//! re-declaring them. On non-Windows targets the namespace is an empty
//! struct and nothing here is analyzed or linked.
const std = @import("std");
const builtin = @import("builtin");

pub const api = if (builtin.os.tag == .windows) struct {
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
    pub extern "c" fn _setmode(fd: c_int, mode: c_int) c_int;
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
    pub extern "c" fn _wchmod(path: [*:0]const u16, mode: c_int) c_int;

    // CRT _wchmod permission bits (sys/stat.h). Windows only honors the
    // write bit — clearing it sets FILE_ATTRIBUTE_READONLY.
    pub const S_IREAD: c_int = 0x0100;
    pub const S_IWRITE: c_int = 0x0080;

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
    /// ioctlsocket command: FIONREAD (_IOR('f', 127, u_long)).
    pub const FIONREAD: c_long = @bitCast(@as(u32, 0x4004667F));

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
    pub const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;

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
