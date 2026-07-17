//! Windows pipe substrate (#1608 stage 2: pipe readiness).
//!
//! Pipe fds on Windows have no would-block mode: the CRT layer offers no
//! O_NONBLOCK, anonymous/CRT pipe handles are created without
//! FILE_FLAG_OVERLAPPED (so completion-based I/O — IOCP — is impossible on
//! the handles that actually reach the port layer), and a pipe HANDLE is
//! not a waitable readiness object. What the platform *does* offer is
//! non-destructive state queries: PeekNamedPipe answers "how many bytes
//! could a read return right now", and
//! NtQueryInformationFile(FilePipeLocalInformation) answers "how much
//! buffer space could a write consume right now" (the same query libuv
//! uses for its non-overlapped pipe writes).
//!
//! Those two queries carry the whole design. A pipe port in emulated
//! non-blocking mode (port.nonblocking set with no OS-level flip —
//! maybeSetNonblocking) reads/writes through pipeRead/pipeWrite below,
//! whose pre-checks synthesize the EAGAIN that drives the shared
//! park-and-retry protocol unchanged; the reactor's WindowsEventBackend
//! answers "when is it ready again" by re-running the same checks on a
//! bounded poll cadence (pipePollReady). Sequential programs never set the
//! flag, so their pipe I/O keeps the plain blocking CRT calls and syscall
//! profile.
//!
//! One documented caveat rules the threading story: MSDN warns that
//! PeekNamedPipe "can block thread execution the same way any I/O function
//! can when called on a synchronous handle in a multi-threaded
//! application" — synchronous file objects serialize their I/O, so a peek
//! races a *concurrent blocking read on the same handle from another
//! thread*. That situation is outside this runtime's model: ports never
//! cross OS threads (SRFI-18 threads deep-copy, each owns its VM/GC), so
//! every peek, quota query, and read/write on a pipe handle issues from
//! the one thread that owns the port — and the only *blocking* pipe reads
//! that thread ever makes are sequential-mode (no scheduler, so nothing
//! else runs) or post-peek (bytes known present, returns immediately).
//! Foreign FFI code sharing a pipe handle across threads accepts the same
//! caveat POSIX code sharing an fd across threads always has.
//!
//! Everything here is a comptime no-op off Windows. Split placed beside
//! platform_win_sock.zig (file size policy); platform.zig re-exports the
//! public symbols. Unlike the ws2_32 slice — whose externs live in
//! `platform.win` because reactor.zig and testing_helpers share them —
//! the kernel32/ntdll pipe externs below have this file as their only
//! consumer, so they stay private to it.

const std = @import("std");
const platform = @import("platform.zig");
const win = platform.win;
const E = platform.E;
const fd_t = platform.fd_t;
const is_windows = platform.is_windows;

/// Pipe-readiness syscall surface (#1608 stage 2). PeekNamedPipe answers
/// "how many bytes could a read return right now";
/// NtQueryInformationFile(FilePipeLocalInformation) answers "how much
/// buffer space could a write consume right now" (WriteQuotaAvailable —
/// the same query libuv uses for its non-overlapped pipe writes; stable
/// ntdll ABI since NT4, ntifs.h). Wrapped in the same comptime guard as
/// `platform.win` so nothing Windows-flavored is ever analyzed elsewhere.
const winp = if (is_windows) struct {
    pub extern "kernel32" fn PeekNamedPipe(h: win.HANDLE, buf: ?*anyopaque, buf_size: u32, bytes_read: ?*u32, total_avail: ?*u32, bytes_left_msg: ?*u32) callconv(.winapi) c_int;
    pub extern "ntdll" fn NtQueryInformationFile(h: win.HANDLE, iosb: *IoStatusBlock, info: *anyopaque, len: u32, class: c_int) callconv(.winapi) i32;
    pub const IoStatusBlock = extern struct { status_or_pointer: usize, information: usize };
    /// FILE_INFORMATION_CLASS value for FILE_PIPE_LOCAL_INFORMATION.
    pub const FilePipeLocalInformation: c_int = 24;
    /// ntifs.h FILE_PIPE_LOCAL_INFORMATION (all ULONGs).
    pub const FilePipeLocalInfo = extern struct {
        named_pipe_type: u32,
        named_pipe_configuration: u32,
        maximum_instances: u32,
        current_instances: u32,
        inbound_quota: u32,
        read_data_available: u32,
        outbound_quota: u32,
        write_quota_available: u32,
        named_pipe_state: u32,
        named_pipe_end: u32,
    };
    // named_pipe_configuration values (data-flow direction is fixed at
    // creation; which end may write follows from it + named_pipe_end).
    pub const FILE_PIPE_INBOUND: u32 = 0;
    pub const FILE_PIPE_OUTBOUND: u32 = 1;
    pub const FILE_PIPE_FULL_DUPLEX: u32 = 2;
    // named_pipe_end values.
    pub const FILE_PIPE_CLIENT_END: u32 = 0;
    pub const FILE_PIPE_SERVER_END: u32 = 1;
} else struct {};

/// What a CRT fd wraps, as far as fd readiness is concerned. `.socket`
/// gets event-driven readiness (WSAEventSelect, stage 1), `.pipe` gets
/// polled readiness (this file, stage 2), `.other` — disk files, console,
/// character devices — stays fully blocking, which for regular files is
/// exactly the POSIX baseline (O_NONBLOCK is a no-op on regular files
/// everywhere; epoll rejects them outright).
pub const FdKind = enum { socket, pipe, other };

/// One-shot fd classification for the port layer's first-touch probe and
/// the reactor's arm routing. GetFileType returns PIPE for both sockets
/// and pipes; isSocketFd's kernel-verified gates split those (and defeat
/// stale ws2_32 entries left by handle-value recycling — see its comment).
pub fn fdKind(fd: fd_t) FdKind {
    if (comptime !is_windows) return .other;
    const h = pipeHandleFromFd(fd) orelse return .other;
    if (win.GetFileType(h) != win.FILE_TYPE_PIPE) return .other;
    return if (platform.isSocketFd(fd)) .socket else .pipe;
}

/// The HANDLE behind a CRT fd, or null if the fd is invalid/unassociated
/// (sockFromFd's shape, minus the SOCKET cast).
pub fn pipeHandleFromFd(fd: fd_t) ?win.HANDLE {
    const raw = win._get_osfhandle(fd);
    // -1 is INVALID_HANDLE_VALUE (bad fd), -2 the CRT's "fd has no
    // associated stream" marker.
    if (raw == -1 or raw == -2) return null;
    return @ptrFromInt(@as(usize, @bitCast(raw)));
}

fn queryPipeInfo(h: win.HANDLE) ?winp.FilePipeLocalInfo {
    var iosb: winp.IoStatusBlock = undefined;
    var info: winp.FilePipeLocalInfo = undefined;
    const status = winp.NtQueryInformationFile(h, &iosb, &info, @sizeOf(winp.FilePipeLocalInfo), winp.FilePipeLocalInformation);
    if (status < 0) return null;
    return info;
}

/// Whether this end of the pipe is one data can be written *into*. A pipe's
/// data-flow direction is fixed at creation (named_pipe_configuration) and
/// each handle knows which end it holds (named_pipe_end); CreatePipe's
/// anonymous pipes are INBOUND with the write handle on the client end.
/// Load-bearing for pipeWrite: quota == 0 on a writable end means "full,
/// park until the reader drains", but on a non-writable end it would mean
/// "park forever" — that case must surface the real write error instead.
fn isWritableEnd(info: winp.FilePipeLocalInfo) bool {
    return switch (info.named_pipe_configuration) {
        winp.FILE_PIPE_FULL_DUPLEX => true,
        winp.FILE_PIPE_INBOUND => info.named_pipe_end == winp.FILE_PIPE_CLIENT_END,
        winp.FILE_PIPE_OUTBOUND => info.named_pipe_end == winp.FILE_PIPE_SERVER_END,
        // Unknown layout: claim writable and let the write surface the truth.
        else => true,
    };
}

/// read(2)-shaped, peek-gated read on a pipe fd in emulated non-blocking
/// mode: no data pending synthesizes EAGAIN (the CRT read would block);
/// otherwise the plain blocking CRT read runs and cannot block — a pipe
/// read short-returns whatever is buffered, and a failed peek (broken or
/// non-readable end) means the read itself returns 0/EOF or the real error
/// immediately.
pub fn pipeRead(fd: fd_t, buf: [*]u8, len: usize) isize {
    if (comptime !is_windows) return -1;
    const h = pipeHandleFromFd(fd) orelse {
        win._errno().* = @intFromEnum(E.BADF);
        return -1;
    };
    var avail: u32 = 0;
    if (winp.PeekNamedPipe(h, null, 0, null, &avail, null) != 0 and avail == 0) {
        win._errno().* = @intFromEnum(E.AGAIN);
        return -1;
    }
    return platform.read(fd, buf, len);
}

/// write(2)-shaped, quota-gated write on a pipe fd in emulated non-blocking
/// mode. Byte-mode pipe writes block until *every* requested byte fits, so
/// the request is clamped to the space known to be free — the caller's
/// short-write loop (drainWriteBuffer) handles the remainder. Zero free
/// space on a writable end synthesizes EAGAIN; a failed query or a
/// non-writable end falls through to the plain CRT write, which surfaces
/// the real error (or blocks, exactly as before stage 2 — the graceful
/// degradation, never a wrong result).
pub fn pipeWrite(fd: fd_t, buf: [*]const u8, len: usize) isize {
    if (comptime !is_windows) return -1;
    const h = pipeHandleFromFd(fd) orelse {
        win._errno().* = @intFromEnum(E.BADF);
        return -1;
    };
    const info = queryPipeInfo(h) orelse return platform.write(fd, buf, len);
    if (!isWritableEnd(info)) return platform.write(fd, buf, len);
    if (info.write_quota_available == 0) {
        win._errno().* = @intFromEnum(E.AGAIN);
        return -1;
    }
    return platform.write(fd, buf, @min(len, info.write_quota_available));
}

pub const PipeReadiness = struct { readable: bool = false, writable: bool = false };

/// Snapshot of the pipe's current readiness in the requested directions —
/// the reactor's poll-cadence re-check (level-triggered by construction, so
/// none of WSAEventSelect's edge-record races apply). Any query failure —
/// bad fd, broken pipe, non-readable/non-writable end — reports the
/// requested direction ready: a spurious wake is always safe under the
/// park-and-retry protocol (the retried syscall surfaces the real outcome),
/// a missed one parks the fiber forever.
pub fn pipePollReady(fd: fd_t, want_read: bool, want_write: bool) PipeReadiness {
    if (comptime !is_windows) return .{};
    const h = pipeHandleFromFd(fd) orelse
        return .{ .readable = want_read, .writable = want_write };
    var result: PipeReadiness = .{};
    if (want_read) {
        var avail: u32 = 0;
        if (winp.PeekNamedPipe(h, null, 0, null, &avail, null) == 0) {
            result.readable = true;
        } else {
            result.readable = avail > 0;
        }
    }
    if (want_write) {
        if (queryPipeInfo(h)) |info| {
            result.writable = !isWritableEnd(info) or info.write_quota_available > 0;
        } else {
            result.writable = true;
        }
    }
    return result;
}
