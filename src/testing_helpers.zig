const std = @import("std");
const types = @import("types.zig");
const platform = @import("platform.zig");
pub const memory = @import("memory.zig");
const library_mod = @import("library.zig");
const primitives_mod = @import("primitives.zig");
const vm_mod = @import("vm.zig");
pub const VM = vm_mod.VM;
pub const VMError = vm_mod.VMError;
pub const Value = types.Value;

/// Absolute path of a `std.testing.tmpDir` result, resolved with a
/// path-string `realpath` rather than `Io.Dir.realPathFile`'s fd→path
/// lookup. That lookup is `error.OperationUnsupported` on OpenBSD (no
/// `/proc/self/fd`, no `F_GETPATH`), whereas path-string realpath works on
/// every platform. std.testing places tmp dirs at `.zig-cache/tmp/<sub_path>`
/// relative to the cwd (see `std.testing.tmpDir`), which realpath
/// canonicalizes. Caller owns the returned slice.
pub fn tmpDirRealPathAlloc(tmp: *std.testing.TmpDir, allocator: std.mem.Allocator) ![]const u8 {
    var rel_buf: [platform.PATH_MAX]u8 = undefined;
    const rel = try std.fmt.bufPrintZ(&rel_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var out_buf: [platform.PATH_MAX]u8 = undefined;
    const resolved = platform.realPath(rel, &out_buf) orelse return error.FileNotFound;
    return allocator.dupe(u8, resolved);
}

/// Build a fully bootstrapped VM for a unit test. The VM is heap-allocated
/// and returned by pointer: `vm_instance` and the GC root marker reach the
/// VM by address, so it must never move. Returning the struct by value (as
/// this helper used to) left `vm_instance` pointing at a dead stack frame —
/// harmless while the GC threshold was never reached mid-test, but fatal
/// under -Dgc-stress=true, where every collection between construction and
/// the first execute() then failed to mark the globals and swept live
/// objects (#1401). `vm.deinit()` also destroys the struct (heap_owned).
pub fn makeTestVM(gc: *memory.GC) !*VM {
    const vm = try gc.allocator.create(VM);
    vm.* = VM.init(gc) catch |err| {
        gc.allocator.destroy(vm);
        return err;
    };
    vm.heap_owned = true;
    errdefer vm.deinit();
    memory.setGCInstance(gc);
    // Register before the first primitive allocation: under stress every
    // allocation collects, and only a registered vm_instance lets the root
    // marker keep the globals map alive while it is being populated.
    vm_mod.setVMInstance(vm);
    try primitives_mod.registerAll(vm);
    try vm_mod.vm_bootstrap.install(vm);
    try library_mod.registerStandardLibraries(&vm.libraries, vm.globals);
    return vm;
}

pub const TestContext = struct {
    gc: memory.GC,
    vm: *VM,

    pub fn init(self: *TestContext) !void {
        self.gc = memory.GC.init(std.testing.allocator);
        self.vm = makeTestVM(&self.gc) catch |err| {
            self.gc.deinit();
            return err;
        };
    }

    pub fn deinit(self: *TestContext) void {
        self.vm.deinit();
        self.gc.deinit();
    }
};

pub fn expectEval(source: []const u8, expected: i64) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(expected, types.toFixnum(result));
}

pub fn expectEvalTrue(source: []const u8) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(types.TRUE, result);
}

pub fn expectEvalBool(source: []const u8, expected: bool) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(if (expected) types.TRUE else types.FALSE, result);
}

pub fn expectEvalVoid(source: []const u8) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(types.VOID, result);
}

// ---------------------------------------------------------------------------
// Cross-platform fd pairs for the fd-readiness suites (tests_reactor,
// tests_scheduler, tests_port_io). POSIX targets use the pipes/socketpairs
// the suites were written against. Windows fd readiness is socket-only
// (#1608), so there every pair is a loopback TCP pair wrapped in CRT fds —
// exactly the object the port layer's socket bridge expects — and the raw
// read/write helpers route through sockRecv/sockSend (CRT _read/_write
// cannot operate on SOCKET handles).
// ---------------------------------------------------------------------------

/// Winsock externs only the loopback-pair construction needs; test-only,
/// so they live here rather than in platform.win.
const winsock_test = if (platform.is_windows) struct {
    const SOCKET = platform.win.SOCKET;
    const SockaddrIn = extern struct {
        family: c_short = 2, // AF_INET
        port: u16 = 0, // network byte order; copied verbatim from getsockname
        addr: [4]u8 = .{ 0, 0, 0, 0 },
        zero: [8]u8 = @splat(0),
    };
    extern "ws2_32" fn socket(af: c_int, sock_type: c_int, protocol: c_int) callconv(.winapi) SOCKET;
    extern "ws2_32" fn bind(s: SOCKET, addr: *const SockaddrIn, len: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn listen(s: SOCKET, backlog: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn connect(s: SOCKET, addr: *const SockaddrIn, len: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn accept(s: SOCKET, addr: ?*SockaddrIn, len: ?*c_int) callconv(.winapi) SOCKET;
    extern "ws2_32" fn getsockname(s: SOCKET, addr: *SockaddrIn, len: *c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn setsockopt(s: SOCKET, level: c_int, optname: c_int, optval: [*]const u8, optlen: c_int) callconv(.winapi) c_int;
} else struct {};

/// A connected fd pair, [0] the read end and [1] the write end by the
/// suites' convention. POSIX: a pipe — the exact object the port layer
/// wraps for process pipes. Windows: a loopback TCP pair (bidirectional,
/// which satisfies every unidirectional use).
pub fn makeFdPair() [2]platform.fd_t {
    if (comptime platform.is_windows) return makeWinLoopbackPair();
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) unreachable;
    return fds;
}

/// A connected *bidirectional* fd pair backed by sockets on every
/// platform: AF_UNIX socketpair on POSIX, the loopback TCP pair on
/// Windows. For tests that need two-way traffic or socket buffer tuning.
pub fn makeBidiFdPair() [2]platform.fd_t {
    if (comptime platform.is_windows) return makeWinLoopbackPair();
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &fds) != 0) unreachable;
    return fds;
}

/// A unidirectional OS *pipe* pair on every platform ([0] read end, [1]
/// write end): pipe(2) on POSIX, CRT _pipe (64 KiB, binary) on Windows.
/// Unlike makeFdPair — which substitutes loopback TCP on Windows because
/// the readiness suites predate pipe readiness there — this is for tests
/// that exercise the pipe kind itself (#1608 stage 2: polled readiness;
/// on POSIX the same tests re-cover native pipe readiness). Raw test-side
/// I/O on these fds must use platform.read/platform.write, not
/// fdRead/fdWrite (whose Windows routing is socket-only).
pub fn makePipeFdPair() [2]platform.fd_t {
    var fds: [2]platform.fd_t = undefined;
    std.debug.assert(platform.pipe(&fds) == 0);
    return fds;
}

fn makeWinLoopbackPair() [2]platform.fd_t {
    platform.ensureWinsock();
    const ws = winsock_test;
    const listener = ws.socket(2, 1, 0); // AF_INET, SOCK_STREAM
    std.debug.assert(listener != platform.win.INVALID_SOCKET);
    defer _ = platform.win.closesocket(listener);
    var addr: ws.SockaddrIn = .{ .addr = .{ 127, 0, 0, 1 } };
    std.debug.assert(ws.bind(listener, &addr, @sizeOf(ws.SockaddrIn)) == 0);
    std.debug.assert(ws.listen(listener, 1) == 0);
    var bound: ws.SockaddrIn = undefined;
    var alen: c_int = @sizeOf(ws.SockaddrIn);
    std.debug.assert(ws.getsockname(listener, &bound, &alen) == 0);

    const client = ws.socket(2, 1, 0);
    std.debug.assert(client != platform.win.INVALID_SOCKET);
    // A blocking connect to a listening loopback endpoint with backlog
    // room completes without the accept having run yet.
    std.debug.assert(ws.connect(client, &bound, @sizeOf(ws.SockaddrIn)) == 0);
    const server = ws.accept(listener, null, null);
    std.debug.assert(server != platform.win.INVALID_SOCKET);

    // CRT fds own the handles from here (#1608 bridge contract): _close —
    // via closeFd, close-port, or GC freeObject — closes the socket.
    const fd0 = platform.win._open_osfhandle(@bitCast(server), 0);
    const fd1 = platform.win._open_osfhandle(@bitCast(client), 0);
    std.debug.assert(fd0 >= 0 and fd1 >= 0);
    return .{ fd0, fd1 };
}

pub fn closeFd(fd: platform.fd_t) void {
    platform.close(fd);
}

/// Test-side raw read on a pair fd; same return/errno contract as read(2).
pub fn fdRead(fd: platform.fd_t, buf: []u8) isize {
    if (comptime platform.is_windows) return platform.sockRecv(fd, buf.ptr, buf.len);
    return platform.read(fd, buf.ptr, buf.len);
}

/// Test-side raw write on a pair fd; same contract as write(2).
pub fn fdWrite(fd: platform.fd_t, bytes: []const u8) isize {
    if (comptime platform.is_windows) return platform.sockSend(fd, bytes.ptr, bytes.len);
    return platform.write(fd, bytes.ptr, bytes.len);
}

/// fdRead that retries a would-block until data arrives (bounded ~2s).
/// For test-side non-blocking reads that assert data *is* present: a pipe
/// write is visible to the very next read, but loopback TCP delivery (the
/// Windows pairs) is asynchronous, so the first read can race the segment.
pub fn fdReadRetry(fd: platform.fd_t, buf: []u8) isize {
    var attempts: usize = 0;
    while (attempts < 2000) : (attempts += 1) {
        const n = fdRead(fd, buf);
        if (n >= 0 or platform.errno(n) != .AGAIN) return n;
        platform.sleepNs(1_000_000);
    }
    return -1;
}

/// Flips a pair fd to non-blocking: fcntl(O_NONBLOCK) / ioctlsocket(FIONBIO).
pub fn setFdNonblocking(fd: platform.fd_t) void {
    if (comptime platform.is_windows) {
        std.debug.assert(platform.setSockNonblockingFd(fd));
        return;
    }
    const flags = std.c.fcntl(fd, std.posix.F.GETFL, @as(c_int, 0));
    std.debug.assert(flags >= 0);
    const nonblock: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
    std.debug.assert(std.c.fcntl(fd, std.posix.F.SETFL, flags | nonblock) >= 0);
}

pub const SockBuf = enum { snd, rcv };

/// Shrinks a socket fd's kernel send/receive buffer so a filler reaches
/// would-block after a few KB instead of megabytes. Only valid on socket
/// fds (a makeBidiFdPair end anywhere; any pair fd on Windows).
pub fn setSockBufSize(fd: platform.fd_t, which: SockBuf, size: c_int) void {
    if (comptime platform.is_windows) {
        const opt: c_int = if (which == .snd) 0x1001 else 0x1002; // SO_SNDBUF / SO_RCVBUF
        const sock = platform.sockFromFd(fd) orelse unreachable;
        std.debug.assert(winsock_test.setsockopt(sock, platform.win.SOL_SOCKET, opt, @ptrCast(&size), @sizeOf(c_int)) == 0);
        return;
    }
    const opt: u32 = if (which == .snd) std.posix.SO.SNDBUF else std.posix.SO.RCVBUF;
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, opt, std.mem.asBytes(&size)) catch unreachable;
}
