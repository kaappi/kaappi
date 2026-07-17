//! Windows socket substrate (#1608 stage 1: socket readiness).
//!
//! The runtime's contract on Windows: a socket enters the port layer as a
//! CRT fd created with `_open_osfhandle((intptr_t)sock, 0)` — the fd both
//! closes uniformly through platform.close (plain `_close`; see its
//! single-owner comment) and recovers its SOCKET via `_get_osfhandle` for
//! the calls below. CRT `_read`/`_write` cannot operate on SOCKET handles
//! at all (sockets are OVERLAPPED by default, which plain
//! ReadFile/WriteFile rejects), so socket ports read and write through
//! sockRecv/sockSend instead — blocking or not — which translate Winsock
//! errors onto the CRT errno values the shared port paths already check
//! (EAGAIN/EINTR). Everything here is a comptime no-op off Windows.
//!
//! Split out of platform.zig along this natural seam (file size policy);
//! platform.zig re-exports every public symbol, so callers keep the
//! `platform.sockRecv`-style names. The raw ws2_32/kernel32 externs stay
//! in `platform.win` — reactor.zig and testing_helpers reach them there.

const std = @import("std");
const platform = @import("platform.zig");
const win = platform.win;
const E = platform.E;
const fd_t = platform.fd_t;
const is_windows = platform.is_windows;

var winsock_ready = std.atomic.Value(bool).init(false);
var winsock_mutex: std.atomic.Mutex = .unlocked;

/// Idempotent, thread-safe WSAStartup. Never paired with WSACleanup — the
/// socket layer lives for the process, the same lifetime discipline as the
/// CRT fd table itself. The spinlock (the symbol_mutex pattern) only ever
/// spins on the one-time first call racing another thread. `ready` is
/// published only on WSAStartup success; a failure leaves it unset so the
/// next call retries instead of every later socket op running against an
/// uninitialized Winsock (they would all fail WSANOTINITIALISED, which
/// callers treat as "not a socket" — a silent capability downgrade).
pub fn ensureWinsock() void {
    if (comptime !is_windows) return;
    if (winsock_ready.load(.acquire)) return;
    while (!winsock_mutex.tryLock()) std.atomic.spinLoopHint();
    defer winsock_mutex.unlock();
    if (winsock_ready.load(.acquire)) return;
    var data: win.WSAData = undefined;
    if (win.WSAStartup(0x0202, &data) != 0) return;
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

/// Whether the CRT fd wraps a live SOCKET. This is the port layer's
/// one-time readiness capability check (maybeSetNonblocking), the Windows
/// analogue of WASI's fd_fdstat_set_flags probe. Three gates, each
/// load-bearing:
///
/// 1. GetFileType must report PIPE — what sockets report; disk files
///    report DISK. Cheap rejection of the overwhelmingly common case.
/// 2. getsockopt(SO_TYPE) must succeed — non-sockets fail WSAENOTSOCK.
///    NOT sufficient alone: ws2_32 answers SO_TYPE from user-mode state
///    keyed by handle value, and a socket closed without closesocket
///    (platform.close's _close, or foreign FFI code) leaves a stale
///    entry that "succeeds" for whatever later recycles that handle
///    value (#1608: observed as silently dropped writes on a file port
///    whose fd recycled a dead socket's handle).
/// 3. ioctlsocket(FIONREAD) must succeed — unlike SO_TYPE this round-trips
///    to the kernel (AFD), so only a handle that is a socket *right now*
///    passes; a stale ws2_32 entry pointing at a recycled pipe/file
///    handle errors out here.
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
    if (win.getsockopt(sock, win.SOL_SOCKET, win.SO_TYPE, @ptrCast(&sotype), &optlen) != 0) return false;
    var pending: c_ulong = 0;
    return win.ioctlsocket(sock, win.FIONREAD, &pending) == 0;
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
