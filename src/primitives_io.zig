const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const printer = @import("printer.zig");
const reader_mod = @import("reader.zig");
const primitives_control = @import("primitives_control.zig");
const fiber_mod = @import("fiber.zig");
const reactor_mod = @import("reactor.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "display", .func = &display, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .scheme_write }) },
    .{ .name = "write", .func = &write, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .scheme_write }) },
    .{ .name = "newline", .func = &newline, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "port?", .func = &portP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "input-port?", .func = &inputPortP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "output-port?", .func = &outputPortP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "textual-port?", .func = &textualPortP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "binary-port?", .func = &binaryPortP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "input-port-open?", .func = &inputPortOpenP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "output-port-open?", .func = &outputPortOpenP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "open-input-file", .func = &openInputFile, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_file, .scheme_r5rs }), .sandbox = false },
    .{ .name = "open-output-file", .func = &openOutputFile, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_file, .scheme_r5rs }), .sandbox = false },
    .{ .name = "close-port", .func = &closePort, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "close-input-port", .func = &closePort, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "close-output-port", .func = &closePort, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "read-char", .func = &readCharFn, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "peek-char", .func = &peekCharFn, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "read-line", .func = &readLineFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "char-ready?", .func = &charReadyP, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "write-char", .func = &writeCharFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "write-string", .func = &writeStringFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "read", .func = &readDatumFn, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_r5rs, .scheme_read }) },
    .{ .name = "file-exists?", .func = &fileExistsP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_file), .sandbox = false },
    .{ .name = "eof-object?", .func = &eofObjectP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "eof-object", .func = &eofObjectFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "open-input-string", .func = &openInputString, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "open-output-string", .func = &openOutputString, .arity = .{ .exact = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "get-output-string", .func = &getOutputString, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "read-string", .func = &readStringFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "flush-output-port", .func = &flushOutputPort, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "delete-file", .func = &deleteFile, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_file), .sandbox = false },
    .{ .name = "write-shared", .func = &writeShared, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_write) },
    .{ .name = "write-simple", .func = &write, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_write) },
    .{ .name = "call-with-input-file", .func = &callWithInputFile, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_file, .scheme_r5rs }), .sandbox = false },
    .{ .name = "call-with-output-file", .func = &callWithOutputFile, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_file, .scheme_r5rs }), .sandbox = false },
    .{ .name = "call-with-port", .func = &callWithPort, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "with-input-from-file", .func = &withInputFromFile, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_file, .scheme_r5rs }), .sandbox = false },
    .{ .name = "with-output-to-file", .func = &withOutputToFile, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_file, .scheme_r5rs }), .sandbox = false },
    .{ .name = "open-binary-input-file", .func = &openBinaryInputFile, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_file), .sandbox = false },
    .{ .name = "open-binary-output-file", .func = &openBinaryOutputFile, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_file), .sandbox = false },
    // Exposed via (kaappi ffi) — the library FFI socket code (kaappi-net)
    // already imports — so a raw fd from an FFI call can be given reactor-
    // integrated non-blocking I/O (#1478). Not in sandbox: it is a raw
    // capability over an arbitrary descriptor.
    .{ .name = "fd->port", .func = &fdToPort, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false },
};

// ---------------------------------------------------------------------------
// Port helpers
// ---------------------------------------------------------------------------

const reporting = @import("reporting.zig");
pub const writeToFd = reporting.writeToFd;
pub const writeStdout = reporting.writeStdout;
pub const writeStderr = reporting.writeStderr;

/// Get the output port: use args[arg_idx] if provided, else current-output-port.
fn getOutputPort(args: []const Value, arg_idx: usize, proc: []const u8) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError(proc, "output port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_output) return primitives.typeError(proc, "output port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError(proc, "open output port", args[arg_idx]);
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = currentOutputPortValue(vm);
    if (!types.isPort(port_val)) return primitives.typeError(proc, "port", port_val);
    return types.toObject(port_val).as(types.Port);
}

/// Get the input port: use args[arg_idx] if provided, else current-input-port.
fn getInputPort(args: []const Value, arg_idx: usize, proc: []const u8) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError(proc, "input port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_input) return primitives.typeError(proc, "input port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError(proc, "open input port", args[arg_idx]);
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = currentInputPortValue(vm);
    if (!types.isPort(port_val)) return primitives.typeError(proc, "port", port_val);
    return types.toObject(port_val).as(types.Port);
}

fn currentInputPortValue(vm: *vm_mod.VM) Value {
    if (vm.current_input_port_param != types.VOID)
        return vm.getParameterValue(types.toParameter(vm.current_input_port_param));
    return vm.stdin_port;
}

fn currentOutputPortValue(vm: *vm_mod.VM) Value {
    if (vm.current_output_port_param != types.VOID)
        return vm.getParameterValue(types.toParameter(vm.current_output_port_param));
    return vm.stdout_port;
}

fn currentErrorPortValue(vm: *vm_mod.VM) Value {
    if (vm.current_error_port_param != types.VOID)
        return vm.getParameterValue(types.toParameter(vm.current_error_port_param));
    return vm.stderr_port;
}

// ---------------------------------------------------------------------------
// Non-blocking port I/O (KEP-0001 Phase 3)
//
// Reads and buffered-write drains that would block suspend the calling
// fiber on the reactor (fiber.waitForFd) instead of blocking the OS thread.
// A fiber dispatched directly by a scheduler loop parks — its primitive
// re-executes on readiness, so every read site with partial progress
// stashes it into port.read_buf first (propagateReadErr). The main fiber
// (or one under re-entrant native frames) drives the scheduler in place and
// resumes here. Sequential programs never create a scheduler, so their
// ports stay blocking and their syscall profile is unchanged.
// ---------------------------------------------------------------------------

/// Pending-output span above which a buffered port drains to the fd before
/// accepting more bytes (suspending the writer as needed). Bounds per-port
/// buffer memory at roughly this plus the largest single write.
const write_high_water: usize = 8192;

/// Bytes a single fd read(2) fills into the port's read_buf. Byte-at-a-time
/// consumers (read-char, read-u8, read-bytevector, read-string, read-line)
/// then serve subsequent bytes from memory, paying one syscall per burst
/// rather than one per byte (#1460). read(2) short-returns whatever is
/// already available, so filling never blocks past the first available byte.
const read_chunk_size: usize = 4096;

/// Ports whose writes accumulate in `write_buf`: real-fd ports other than
/// stdin/stdout/stderr. fd 0/1/2 keep the historical unbuffered
/// direct-write behavior (REPL echo and diagnostic ordering depend on it);
/// string ports have their own growable buffer.
fn isBufferedFdPort(port: *types.Port) bool {
    return !port.is_string_port and port.fd > 2;
}

/// Lazily flips the port's fd to O_NONBLOCK the first time it is used while
/// a fiber scheduler exists — the precondition for any reactor wait to
/// engage. Never touches fd 0/1/2: those share their open file description
/// with the shell/terminal (and linenoise reads fd 0 directly in REPL
/// mode), so flipping them would leak non-blocking mode outside this
/// process. Without a scheduler nothing is flipped and sequential programs
/// keep blocking fds. Pub only for tests_port_io's guard checks.
///
/// On WASI this doubles as the host-capability probe (KEP-0001 Phase 4):
/// fd readiness is best-effort per the KEP, and a host that rejects
/// fd_fdstat_set_flags(NONBLOCK) — the playground's browser shim does —
/// keeps the port on a blocking fd, so no read ever EAGAINs, nothing
/// registers with the reactor, and I/O degrades to single-fiber blocking
/// exactly where the host can't support better.
///
/// On Windows the probe is fdKind (#1608): a port whose CRT fd wraps a
/// SOCKET is marked `fd_state.is_socket` — unconditionally, on first
/// touch — routing its I/O through sockRecv/sockSend (portFdRead/
/// portFdWrite); once a scheduler exists it additionally flips
/// non-blocking via FIONBIO, so would-block surfaces as the EAGAIN the
/// shared paths expect and the WSAEventSelect reactor backend supplies
/// the wakeup (stage 1). A non-socket pipe fd is marked
/// `fd_state.is_pipe`; once a scheduler exists the port enters *emulated*
/// non-blocking mode — `nonblocking` set with no OS-level flip (pipe fds
/// have no would-block mode) — routing its I/O through pipeRead/pipeWrite,
/// whose peek/quota pre-checks synthesize the EAGAIN, and the reactor
/// re-runs those checks on a poll cadence for the wakeup (stage 2). File
/// fds stay fully blocking, which is the POSIX baseline too (O_NONBLOCK
/// is a no-op on regular files; epoll rejects them). The probe result is
/// remembered per port (fd_state.probe_done) so file ports don't pay the
/// probe syscalls per read.
pub fn maybeSetNonblocking(port: *types.Port) void {
    if (port.nonblocking or port.is_string_port or port.fd <= 2) return;
    if (comptime platform.is_windows) {
        // The fd-kind probe is NOT scheduler-gated, unlike the flips below:
        // sockets are OVERLAPPED handles by default on Windows, which CRT
        // _read/_write (plain ReadFile/WriteFile) cannot operate on at
        // all — so a socket port must route through recv/send (portFdRead/
        // portFdWrite) from its very first touch, scheduler or not. A
        // still-blocking socket keeps blocking recv/send semantics, so
        // sequential programs behave exactly like POSIX blocking reads.
        if (!port.fd_state.probe_done) {
            port.fd_state.probe_done = true;
            switch (platform.fdKind(port.fd)) {
                .socket => port.fd_state.is_socket = true,
                .pipe => port.fd_state.is_pipe = true,
                .other => {},
            }
        }
        const wvm = vm_mod.vm_instance orelse return;
        if (wvm.scheduler == null) return;
        if (port.fd_state.is_socket) {
            if (platform.setSockNonblockingFd(port.fd)) port.nonblocking = true;
        } else if (port.fd_state.is_pipe) {
            port.nonblocking = true;
        }
        return;
    }
    const vm = vm_mod.vm_instance orelse return;
    if (vm.scheduler == null) return;
    if (comptime is_wasm) {
        var stat: std.os.wasi.fdstat_t = undefined;
        if (std.os.wasi.fd_fdstat_get(port.fd, &stat) != .SUCCESS) return;
        var flags = stat.fs_flags;
        flags.NONBLOCK = true;
        if (std.os.wasi.fd_fdstat_set_flags(port.fd, flags) != .SUCCESS) return;
        port.nonblocking = true;
        return;
    }
    const flags = std.c.fcntl(port.fd, std.posix.F.GETFL, @as(c_int, 0));
    if (flags < 0) return;
    const nonblock: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
    if (std.c.fcntl(port.fd, std.posix.F.SETFL, flags | nonblock) < 0) return;
    port.nonblocking = true;
}

/// The port's fd byte source: read(2) everywhere except on Windows, where
/// a socket port must recv() on the underlying SOCKET — CRT _read cannot
/// operate on (overlapped) SOCKET handles at all (platform_win_sock.zig) —
/// and a pipe port in emulated non-blocking mode reads through the
/// PeekNamedPipe gate that synthesizes EAGAIN (platform_win_pipe.zig; a
/// sequential program's pipe port keeps plain blocking _read and its exact
/// syscall profile). Same return/errno contract as platform.read.
fn portFdRead(port: *types.Port, buf: [*]u8, len: usize) isize {
    if (comptime platform.is_windows) {
        if (port.fd_state.is_socket) return platform.sockRecv(port.fd, buf, len);
        if (port.fd_state.is_pipe and port.nonblocking) return platform.pipeRead(port.fd, buf, len);
    }
    return platform.read(port.fd, buf, len);
}

/// The port's fd byte sink; portFdRead's write-side twin (pipe ports gate
/// on the write-quota query instead of the peek).
fn portFdWrite(port: *types.Port, buf: [*]const u8, len: usize) isize {
    if (comptime platform.is_windows) {
        if (port.fd_state.is_socket) return platform.sockSend(port.fd, buf, len);
        if (port.fd_state.is_pipe and port.nonblocking) return platform.pipeWrite(port.fd, buf, len);
    }
    return platform.write(port.fd, buf, len);
}

/// Suspends the current fiber until the port's fd is ready for `interest`,
/// then confirms the port survived the wait. A parked fiber propagates
/// error.Yielded from inside waitForFd (the re-executed primitive re-checks
/// the port via getInputPort/getOutputPort); a scheduler-driving waiter
/// resumes here, so the is_open re-check — a sibling may have closed the
/// port while we waited — must raise the clean "port closed" error itself.
fn waitPortFd(port: *types.Port, interest: reactor_mod.Interest) PrimitiveError!void {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidArgument;
    try fiber_mod.waitForFd(vm, port.fd, interest);
    if (!port.is_open) return raisePortClosedDuringIo();
}

fn raisePortClosedDuringIo() PrimitiveError {
    const gc = memory.gc_instance orelse return PrimitiveError.InvalidArgument;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidArgument;
    var msg = gc.allocString("port closed while I/O was blocked on it") catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, types.NIL) catch return PrimitiveError.OutOfMemory;
    types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

/// Preserves a read primitive's partial progress across a park-and-retry.
/// The bytes go to the *front* of port.read_buf — the first software buffer
/// the retry drains — ahead of any bytes an inner reader (a mid-sequence
/// UTF-8 read) already stashed while unwinding, since each outer frame's
/// bytes are chronologically earlier. `parts` concatenate in order.
fn stashPartialRead(port: *types.Port, parts: []const []const u8) PrimitiveError!void {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var total: usize = 0;
    for (parts) |p| total += p.len;
    if (total == 0) return;
    // The peek buffers drain before the fd is ever touched, so no partial
    // read can be unwinding while they still hold bytes.
    std.debug.assert(port.peek_byte == null and port.peek_extra_len == 0);
    const old = port.read_buf;
    const old_len = port.read_buf_len;
    const saved = gc.allocator.alloc(u8, total + old_len) catch return PrimitiveError.OutOfMemory;
    var off: usize = 0;
    for (parts) |p| {
        @memcpy(saved[off..][0..p.len], p);
        off += p.len;
    }
    if (old) |rb| {
        // Live span is the *last* read_buf_len bytes (consumption advances
        // from the front by shrinking the count).
        @memcpy(saved[off..][0..old_len], rb[rb.len - old_len ..]);
        gc.allocator.free(rb);
    }
    port.read_buf = saved;
    port.read_buf_len = saved.len;
}

/// Propagates a read-path error; for a park (error.Yielded) first preserves
/// the caller's partial progress so the re-executed primitive resumes
/// losslessly. If preserving fails, the park is aborted — the fiber comes
/// back off the reactor so its waiter lists never hold a non-parked fiber —
/// and OutOfMemory propagates instead.
pub fn propagateReadErr(port: *types.Port, err: PrimitiveError, parts: []const []const u8) PrimitiveError {
    if (err != PrimitiveError.Yielded) return err;
    stashPartialRead(port, parts) catch {
        unparkCurrentFiber(port);
        return PrimitiveError.OutOfMemory;
    };
    return PrimitiveError.Yielded;
}

fn unparkCurrentFiber(port: *types.Port) void {
    const vm = vm_mod.vm_instance orelse return;
    const me = vm.current_fiber orelse return;
    if (vm.reactor) |r| r.removeWaiter(port.fd, me);
    me.status = .running;
    me.io_fd = null;
    vm.yield_retry = false;
}

/// Drains the port's pending write buffer to the fd until empty. On EAGAIN
/// the writer suspends on write readiness; `write_buf_start` records drain
/// progress, so the wait can be a parked primitive's full re-execution and
/// still resume with exactly the remaining slice.
fn drainWriteBuffer(port: *types.Port) PrimitiveError!void {
    while (port.write_buf_start < port.write_buf_len) {
        // Re-fetch each pass: a scheduler drive inside waitPortFd can run a
        // sibling fiber that appends to this same port and reallocs the
        // buffer (or a concurrent close-port drains it for us).
        const buf = port.write_buf orelse break;
        maybeSetNonblocking(port);
        const rc = portFdWrite(port, buf.ptr + port.write_buf_start, port.write_buf_len - port.write_buf_start);
        if (rc < 0) {
            const e = platform.errno(rc);
            if (e == .INTR) continue;
            if (e == .AGAIN) {
                try waitPortFd(port, .write);
                continue;
            }
            // Parity with the historical writeToFd loop: other write errors
            // (EPIPE, EIO) are swallowed. Drop the unwritable remainder so
            // the buffer cannot grow without bound against a dead fd.
            break;
        }
        if (rc == 0) break;
        port.write_buf_start += @as(usize, @intCast(rc));
    }
    port.write_buf_start = 0;
    port.write_buf_len = 0;
}

fn appendWriteBuf(port: *types.Port, bytes: []const u8) PrimitiveError!void {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf = port.write_buf orelse blk: {
        const b = gc.allocator.alloc(u8, @max(bytes.len, 1024)) catch return PrimitiveError.OutOfMemory;
        port.write_buf = b;
        break :blk b;
    };
    if (port.write_buf_len + bytes.len > buf.len) {
        // Compact the live span to the front, then grow if still needed.
        const pending = port.write_buf_len - port.write_buf_start;
        if (port.write_buf_start > 0) {
            std.mem.copyForwards(u8, buf[0..pending], buf[port.write_buf_start..port.write_buf_len]);
            port.write_buf_start = 0;
            port.write_buf_len = pending;
        }
        if (port.write_buf_len + bytes.len > buf.len) {
            const new_cap = @max(buf.len * 2, port.write_buf_len + bytes.len);
            const nb = gc.allocator.realloc(buf, new_cap) catch return PrimitiveError.OutOfMemory;
            port.write_buf = nb;
            buf = nb;
        }
    }
    @memcpy(buf[port.write_buf_len..][0..bytes.len], bytes);
    port.write_buf_len += bytes.len;
}

/// Best-effort blocking drain of every open buffered port's pending
/// output. Called by `exit` (R7RS runs cleanup; emergency-exit does not) —
/// std.process.exit skips GC teardown, which is where leaked ports
/// otherwise flush (gc_collect.freeObject). No parking: a would-block
/// remainder is dropped, exactly like freeObject's flush.
pub fn flushAllOpenPorts(gc: *memory.GC) void {
    const lists = [_]?*types.Object{ gc.objects, gc.old_objects };
    for (lists) |head| {
        var obj = head;
        while (obj) |o| : (obj = o.next) {
            if (o.tag != .port) continue;
            const port = o.as(types.Port);
            if (!port.is_open or port.is_string_port or port.fd <= 2) continue;
            const wb = port.write_buf orelse continue;
            // Ensure the Windows fd-kind probe ran: a below-high-water
            // append never drains, so this may be the port's first fd
            // touch, and CRT _write cannot operate on a SOCKET handle.
            maybeSetNonblocking(port);
            while (port.write_buf_start < port.write_buf_len) {
                const rc = portFdWrite(port, wb.ptr + port.write_buf_start, port.write_buf_len - port.write_buf_start);
                if (rc < 0 and platform.errno(rc) == .INTR) continue;
                if (rc <= 0) break;
                port.write_buf_start += @as(usize, @intCast(rc));
            }
        }
    }
}

/// Port-layer byte sink for every write primitive (display, write,
/// write-char, write-string, write-u8, write-bytevector). String ports
/// append to their growable buffer; fd 0/1/2 write straight through;
/// buffered fd ports accumulate in `write_buf`, draining when the pending
/// span crosses `write_high_water`, at flush-output-port, at close-port,
/// and before a read on the same port. The drain — never the append — is
/// the only point that can suspend the calling fiber, and it runs *before*
/// the new bytes are appended, so a parked primitive's re-execution cannot
/// duplicate output.
pub fn portWriteBytes(port: *types.Port, bytes: []const u8) PrimitiveError!void {
    if (port.is_string_port) {
        stringPortWrite(port, bytes);
        return;
    }
    if (!isBufferedFdPort(port)) {
        writeToFd(port.fd, bytes);
        return;
    }
    if ((port.write_buf_len - port.write_buf_start) + bytes.len > write_high_water) {
        try drainWriteBuffer(port);
    }
    try appendWriteBuf(port, bytes);
}

fn stringPortWrite(port: *types.Port, bytes: []const u8) void {
    const gc = memory.gc_instance orelse return;
    var buf = port.string_out_buf orelse return;
    const len = port.string_out_len;
    const cap = port.string_out_cap;
    if (len + bytes.len > cap) {
        const new_cap = @max(cap * 2, len + bytes.len);
        const new_buf = gc.allocator.realloc(buf, new_cap) catch return;
        port.string_out_buf = new_buf;
        buf = new_buf;
        port.string_out_cap = new_cap;
    }
    @memcpy(buf[len .. len + bytes.len], bytes);
    port.string_out_len = len + bytes.len;
}

// ---------------------------------------------------------------------------
// I/O -- Port-based (R7RS 6.13)
// ---------------------------------------------------------------------------

fn display(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1, "display");
    const s = printer.valueToString(gc.allocator, args[0], .display) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    try portWriteBytes(port, s);
    return types.VOID;
}

fn write(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1, "write");
    const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    try portWriteBytes(port, s);
    return types.VOID;
}

fn writeShared(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1, "write-shared");
    const s = printer.valueToString(gc.allocator, args[0], .shared) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    try portWriteBytes(port, s);
    return types.VOID;
}

fn newline(args: []const Value) PrimitiveError!Value {
    const port = try getOutputPort(args, 0, "newline");
    try portWriteBytes(port, "\n");
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Port procedures (R7RS 6.13)
// ---------------------------------------------------------------------------

pub fn initPortParams(vm: *vm_mod.VM) !void {
    const gc = vm.gc;
    vm.current_input_port_param = gc.allocParameter(vm.stdin_port, types.NIL) catch return error.OutOfMemory;
    gc.extra_roots.append(gc.allocator, vm.current_input_port_param) catch return error.OutOfMemory;
    try vm.defineGlobal("current-input-port", vm.current_input_port_param);
    vm.current_output_port_param = gc.allocParameter(vm.stdout_port, types.NIL) catch return error.OutOfMemory;
    gc.extra_roots.append(gc.allocator, vm.current_output_port_param) catch return error.OutOfMemory;
    try vm.defineGlobal("current-output-port", vm.current_output_port_param);
    vm.current_error_port_param = gc.allocParameter(vm.stderr_port, types.NIL) catch return error.OutOfMemory;
    gc.extra_roots.append(gc.allocator, vm.current_error_port_param) catch return error.OutOfMemory;
    try vm.defineGlobal("current-error-port", vm.current_error_port_param);
}

fn portP(args: []const Value) PrimitiveError!Value {
    return if (types.isPort(args[0])) types.TRUE else types.FALSE;
}

fn inputPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_input) types.TRUE else types.FALSE;
}

fn outputPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_output) types.TRUE else types.FALSE;
}

fn textualPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (!port.is_binary) types.TRUE else types.FALSE;
}

fn binaryPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_binary) types.TRUE else types.FALSE;
}

fn inputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("input-port-open?", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_input and port.is_open) types.TRUE else types.FALSE;
}

fn outputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("output-port-open?", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_output and port.is_open) types.TRUE else types.FALSE;
}

fn raiseFileError(gc: *@import("memory.zig").GC, msg_text: []const u8, irritant: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    var msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    var irritants_root = irritants;
    gc.pushRoot(&irritants_root);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, irritants_root) catch return PrimitiveError.OutOfMemory;
    types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

fn openInputFile(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return primitives.typeError("open-input-file", "non-WASM platform", args[0]);
    if (!types.isString(args[0])) return primitives.typeError("open-input-file", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = platform.openRead(path_z) catch {
        return raiseFileError(gc, "cannot open input file", args[0]);
    };
    errdefer _ = platform.close(fd);

    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, true, false, owned_name, true) catch {
        gc.allocator.free(owned_name);
        return PrimitiveError.OutOfMemory;
    };
}

fn openOutputFile(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return primitives.typeError("open-output-file", "non-WASM platform", args[0]);
    if (!types.isString(args[0])) return primitives.typeError("open-output-file", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = platform.openWriteTrunc(path_z, 0o644) catch {
        return raiseFileError(gc, "cannot open output file", args[0]);
    };
    errdefer _ = platform.close(fd);

    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, false, true, owned_name, true) catch {
        gc.allocator.free(owned_name);
        return PrimitiveError.OutOfMemory;
    };
}

fn openBinaryInputFile(args: []const Value) PrimitiveError!Value {
    const result = try openInputFile(args);
    types.toObject(result).as(types.Port).is_binary = true;
    return result;
}

fn openBinaryOutputFile(args: []const Value) PrimitiveError!Value {
    const result = try openOutputFile(args);
    types.toObject(result).as(types.Port).is_binary = true;
    return result;
}

/// (fd->port fd) — wrap a raw OS file descriptor as a bidirectional binary
/// port. Every read/write then goes through the same non-blocking,
/// reactor-integrated path as file ports (readOneByte/portWriteBytes): an
/// operation that would block suspends the calling fiber on the reactor
/// instead of the OS thread, and the fd flips to O_NONBLOCK lazily the first
/// time it's touched under a scheduler. This is the bridge that lets an FFI
/// socket (kaappi-net) get real event-driven wakeup for free instead of a
/// poll-then-sleep loop (#1478).
///
/// The port takes ownership of the fd: close-port closes it (fd > 2), wakes
/// any fiber parked on it, and unregisters it from the reactor. The caller
/// must not also close the fd through its own path, or the number could be
/// recycled onto an unrelated port.
fn fdToPort(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return primitives.typeError("fd->port", "non-WASM platform", args[0]);
    if (!types.isFixnum(args[0])) return primitives.typeError("fd->port", "file descriptor", args[0]);
    const fd_i = types.toFixnum(args[0]);
    // Reject the standard streams (whose blocking semantics other code
    // relies on) and anything outside fd_t's range.
    if (fd_i < 3 or fd_i > std.math.maxInt(i32)) return primitives.typeError("fd->port", "socket/pipe file descriptor (> 2)", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port_val = gc.allocPort(@intCast(fd_i), true, true, "fd", false) catch return PrimitiveError.OutOfMemory;
    types.toObject(port_val).as(types.Port).is_binary = true;
    return port_val;
}

fn closePort(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("close-port", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    // Flush buffered output while the fd is still writable. This can
    // suspend the calling fiber; a parked close-port re-executes from the
    // top with the drain progress preserved in the port.
    if (port.is_open and !port.is_string_port and port.write_buf_len > port.write_buf_start) {
        try drainWriteBuffer(port);
    }
    if (port.read_buf) |rb| {
        if (memory.gc_instance) |gc| {
            gc.allocator.free(rb);
        }
        port.read_buf = null;
        port.read_buf_len = 0;
    }
    if (port.write_buf) |wb| {
        if (memory.gc_instance) |gc| {
            gc.allocator.free(wb);
        }
        port.write_buf = null;
        port.write_buf_start = 0;
        port.write_buf_len = 0;
    }
    if (port.is_open and !port.is_string_port) {
        // Close discipline (KEP-0001 Phase 3, resolved question 4): wake
        // every fiber parked on this fd — the retry observes
        // is_open == false and raises a clean error — and drop the reactor
        // registration before the fd number can be closed and recycled.
        if (vm_mod.vm_instance) |vm| {
            if (vm.scheduler) |sched| fiber_mod.wakeIoWaitersOnFd(sched, port.fd);
            if (vm.reactor) |r| r.unregister(port.fd);
        }
        if (port.fd > 2) _ = platform.close(port.fd);
    }
    port.is_open = false;
    return types.VOID;
}

/// Single byte source for every textual and binary port read primitive
/// (read-char, peek-char, read-line, read-string, read-u8, peek-u8,
/// read-bytevector, ...). Drains the software buffers — peek_byte,
/// peek_extra, read_buf, string data — before touching the fd, so buffered
/// data costs zero syscalls. The fd path flushes this port's own pending
/// writes first (a socket port's request must reach the peer before we
/// wait on its response), then reads a chunk (up to `read_chunk_size`) and
/// buffers all but the first byte back into read_buf, so a run of
/// byte-at-a-time reads costs one syscall per burst instead of one per byte
/// (#1460); on EAGAIN the calling fiber suspends on read readiness. Errors
/// only with Yielded (parked; caller stashes partial progress via
/// propagateReadErr), OutOfMemory, or ExceptionRaised (port closed
/// mid-wait); `null` still means EOF.
pub fn readOneByte(port: *types.Port) PrimitiveError!?u8 {
    // Check peek buffer first
    if (port.peek_byte) |b| {
        port.peek_byte = null;
        return b;
    }
    // Check peek continuation bytes (from multi-byte peek-char)
    if (port.peek_extra_len > 0) {
        const b = port.peek_extra[0];
        port.peek_extra[0] = port.peek_extra[1];
        port.peek_extra[1] = port.peek_extra[2];
        port.peek_extra_len -= 1;
        return b;
    }
    // Check read buffer (from prior (read) that buffered excess, or a
    // parked read primitive's stashed partial progress)
    if (port.read_buf) |rb| {
        if (port.read_buf_len > 0) {
            const pos = rb.len - port.read_buf_len;
            const byte = rb[pos];
            port.read_buf_len -= 1;
            if (port.read_buf_len == 0) {
                if (memory.gc_instance) |gc| {
                    gc.allocator.free(rb);
                }
                port.read_buf = null;
            }
            return byte;
        }
    }
    // SRFI-271 random port: an inexhaustible byte source, never EOF. A null
    // means a randomized port could not obtain OS entropy — surface that as an
    // error rather than a silent EOF or predictable bytes.
    if (port.random_gen) |g| {
        if (!port.is_open) return null;
        return g.nextByte() orelse {
            if (vm_mod.vm_instance) |vm|
                vm.setErrorDetail("random port: OS entropy source unavailable", .{});
            return PrimitiveError.InvalidArgument;
        };
    }
    // String input port
    if (port.is_string_port) {
        const data = port.string_data orelse return null;
        if (port.string_pos >= data.len) return null;
        const byte = data[port.string_pos];
        port.string_pos += 1;
        return byte;
    }
    if (port.write_buf_len > port.write_buf_start) try drainWriteBuffer(port);
    maybeSetNonblocking(port);
    var chunk: [read_chunk_size]u8 = undefined;
    while (true) {
        const raw = portFdRead(port, &chunk, chunk.len);
        if (raw < 0) {
            const e = platform.errno(raw);
            if (e == .INTR) continue;
            if (e == .AGAIN) {
                try waitPortFd(port, .read);
                continue;
            }
            return null;
        }
        if (raw == 0) return null;
        const n: usize = @intCast(raw);
        // One read(2) per burst, not per byte (#1460): return the first byte
        // and park the rest in read_buf for the consumption drain above to
        // hand out on the next calls. read_buf is empty on this path — its
        // drain only falls through once exhausted (and freed to null then) —
        // so the fresh slice is entirely live (read_buf_len == len, so the
        // "last read_buf_len bytes" cursor starts at 0). A caller that later
        // parks does so on a subsequent call after this buffer drains, where
        // stashPartialRead prepends onto an empty read_buf.
        if (n > 1) {
            std.debug.assert(port.read_buf == null);
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            const rest = gc.allocator.alloc(u8, n - 1) catch return PrimitiveError.OutOfMemory;
            @memcpy(rest, chunk[1..n]);
            port.read_buf = rest;
            port.read_buf_len = n - 1;
        }
        return chunk[0];
    }
}

const Utf8ReadResult = struct {
    codepoint: u21,
    bytes: [4]u8,
    len: u3,
};

fn readUtf8CharWithBytes(port: *types.Port) PrimitiveError!?Utf8ReadResult {
    const lead = try readOneByte(port) orelse return null;
    const seq_len = std.unicode.utf8ByteSequenceLength(lead) catch return .{ .codepoint = @intCast(lead), .bytes = .{ lead, 0, 0, 0 }, .len = 1 };
    if (seq_len == 1) return .{ .codepoint = @intCast(lead), .bytes = .{ lead, 0, 0, 0 }, .len = 1 };
    var buf: [4]u8 = .{ 0, 0, 0, 0 };
    buf[0] = lead;
    for (1..seq_len) |i| {
        // A park mid-sequence stashes the bytes already consumed so the
        // re-executed primitive re-reads the identical prefix.
        buf[i] = (readOneByte(port) catch |err| return propagateReadErr(port, err, &.{buf[0..i]})) orelse
            return .{ .codepoint = @intCast(lead), .bytes = buf, .len = @intCast(i) };
    }
    const cp = std.unicode.utf8Decode(buf[0..seq_len]) catch return .{ .codepoint = @intCast(lead), .bytes = buf, .len = @intCast(seq_len) };
    return .{ .codepoint = cp, .bytes = buf, .len = @intCast(seq_len) };
}

fn readUtf8Char(port: *types.Port) PrimitiveError!?u21 {
    const result = try readUtf8CharWithBytes(port) orelse return null;
    return result.codepoint;
}

fn readCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "read-char");
    const cp = try readUtf8Char(port) orelse return types.EOF;
    return types.makeChar(cp);
}

fn peekCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "peek-char");
    if (port.peek_byte) |b| {
        const seq_len = std.unicode.utf8ByteSequenceLength(b) catch return types.makeChar(@intCast(b));
        if (seq_len == 1) return types.makeChar(@intCast(b));
        if (port.is_string_port) {
            const data = port.string_data orelse return types.EOF;
            const pos = port.string_pos;
            if (pos > 0) {
                const start = pos - 1;
                if (start + seq_len <= data.len) {
                    var buf: [4]u8 = undefined;
                    buf[0] = b;
                    for (1..seq_len) |i| buf[i] = data[start + i];
                    const cp = std.unicode.utf8Decode(buf[0..seq_len]) catch return types.makeChar(@intCast(b));
                    return types.makeChar(cp);
                }
            }
        } else if (port.peek_extra_len > 0) {
            var utf8_buf: [4]u8 = undefined;
            utf8_buf[0] = b;
            const avail: usize = @intCast(port.peek_extra_len);
            for (0..avail) |i| utf8_buf[i + 1] = port.peek_extra[i];
            if (avail >= seq_len - 1) {
                const cp = std.unicode.utf8Decode(utf8_buf[0..seq_len]) catch return types.makeChar(@intCast(b));
                return types.makeChar(cp);
            }
        } else {
            var utf8_buf: [4]u8 = undefined;
            utf8_buf[0] = b;
            port.peek_byte = null;
            var i: usize = 1;
            while (i < seq_len) : (i += 1) {
                // A park here stashes the cleared peek byte plus any
                // continuation bytes consumed; the re-executed peek-char
                // finds peek_byte empty and re-reads them from read_buf.
                utf8_buf[i] = (readOneByte(port) catch |err|
                    return propagateReadErr(port, err, &.{utf8_buf[0..i]})) orelse break;
            }
            port.peek_byte = b;
            if (i >= seq_len) {
                const extra_len = seq_len - 1;
                for (0..extra_len) |j| port.peek_extra[j] = utf8_buf[j + 1];
                port.peek_extra_len = @intCast(extra_len);
                const cp = std.unicode.utf8Decode(utf8_buf[0..seq_len]) catch return types.makeChar(@intCast(b));
                return types.makeChar(cp);
            }
        }
        return types.makeChar(@intCast(b));
    }
    const port2 = port;
    const result = try readUtf8CharWithBytes(port2) orelse return types.EOF;
    const len: usize = @intCast(result.len);
    if (port2.is_string_port and port2.string_pos >= len) {
        port2.string_pos -= len;
    } else {
        port2.peek_byte = result.bytes[0];
        if (len > 1) {
            for (1..len) |i| port2.peek_extra[i - 1] = result.bytes[i];
            port2.peek_extra_len = @intCast(len - 1);
        }
    }
    return types.makeChar(result.codepoint);
}

fn readLineFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0, "read-line");

    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(gc.allocator);

    while (true) {
        const byte = (readOneByte(port) catch |err|
            return propagateReadErr(port, err, &.{line_buf.items})) orelse
            {
                // EOF
                if (line_buf.items.len == 0) return types.EOF;
                break;
            };
        if (byte == '\n') break;
        if (byte == '\r') {
            // Check for \r\n. A park here must re-stash the '\r' too — it
            // was consumed but not appended, and the re-executed read-line
            // needs to see it again to reach this same decision point.
            const next = readOneByte(port) catch |err|
                return propagateReadErr(port, err, &.{ line_buf.items, "\r" });
            if (next) |nb| {
                if (nb != '\n') {
                    port.peek_byte = nb; // put it back
                }
            }
            break;
        }
        line_buf.append(gc.allocator, byte) catch return PrimitiveError.OutOfMemory;
    }

    return gc.allocString(line_buf.items) catch return PrimitiveError.OutOfMemory;
}

fn charReadyP(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "char-ready?");
    if (port.peek_byte != null or port.peek_extra_len > 0) return types.TRUE;
    // For simplicity, always return #t (non-blocking check not worth the complexity)
    return types.TRUE;
}

fn writeCharFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("write-char", "character", args[0]);
    const port = try getOutputPort(args, 1, "write-char");
    const cp = types.toChar(args[0]);
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch return primitives.typeError("write-char", "valid unicode character", args[0]);
    try portWriteBytes(port, buf[0..len]);
    return types.VOID;
}

fn writeStringFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("write-string", "string", args[0]);
    const port = try getOutputPort(args, 1, "write-string");
    const str = types.toObject(args[0]).as(types.SchemeString);
    const data = str.data[0..str.len];
    const string_mod = @import("primitives_string.zig");
    const cp_count = string_mod.utf8CodepointCount(data);
    var start_cp: usize = 0;
    var end_cp: usize = cp_count;
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("write-string", "integer", args[2]);
        const s = types.toFixnum(args[2]);
        if (s < 0) return primitives.typeError("write-string", "non-negative integer", args[2]);
        start_cp = @intCast(s);
    }
    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return primitives.typeError("write-string", "integer", args[3]);
        const e = types.toFixnum(args[3]);
        if (e < 0) return primitives.typeError("write-string", "non-negative integer", args[3]);
        end_cp = @intCast(e);
    }
    if (start_cp > end_cp or end_cp > cp_count) return primitives.typeError("write-string", "valid range", args[0]);
    const byte_start = string_mod.utf8IndexToByteOffset(data, start_cp) orelse return primitives.typeError("write-string", "valid start index", args[0]);
    const byte_end = string_mod.utf8IndexToByteOffset(data, end_cp) orelse return primitives.typeError("write-string", "valid end index", args[0]);
    try portWriteBytes(port, data[byte_start..byte_end]);
    return types.VOID;
}

/// Parses one datum with R7RS 6.13.2 `read` semantics: EOF before any datum
/// text begins yields null (the caller returns the EOF object); EOF that
/// interrupts an incomplete datum — including an unterminated comment —
/// propagates as an error so the caller can signal one satisfying read-error?.
fn parseDatumForRead(reader: *reader_mod.Reader) reader_mod.ReadError!?Value {
    if (!try reader.hasMore()) return null;
    return try reader.readDatum();
}

fn raiseReadError(gc: *@import("memory.zig").GC) PrimitiveError!Value {
    var msg = gc.allocString("read error") catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, types.NIL) catch return PrimitiveError.OutOfMemory;
    const errObj = types.toObject(err_obj).as(types.ErrorObject);
    errObj.error_type = .read;
    const raise_args = [1]Value{err_obj};
    return primitives_control.raiseFn(&raise_args);
}

fn readFromPeekByteOnly(gc: *@import("memory.zig").GC, port: *types.Port) PrimitiveError!Value {
    const b = port.peek_byte.?;
    port.peek_byte = null;
    const source: [1]u8 = .{b};
    var reader = reader_mod.Reader.init(gc, &source);
    reader.mark_immutable = false;
    defer reader.deinit();
    const maybe_datum = parseDatumForRead(&reader) catch |err| {
        if (err == reader_mod.ReadError.OutOfMemory) return PrimitiveError.OutOfMemory;
        return raiseReadError(gc);
    };
    return maybe_datum orelse types.EOF;
}

fn readDatumFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0, "read");

    // For string ports, read directly from the string data
    if (port.is_string_port) {
        const data = port.string_data orelse {
            if (port.peek_byte != null) return readFromPeekByteOnly(gc, port);
            return types.EOF;
        };
        if (port.string_pos >= data.len and port.peek_byte == null) return types.EOF;

        // Handle any peeked byte
        var source: []const u8 = data[port.string_pos..];
        var prefix: [1]u8 = undefined;
        var combined: std.ArrayList(u8) = .empty;
        defer combined.deinit(gc.allocator);
        if (port.peek_byte) |b| {
            prefix[0] = b;
            port.peek_byte = null;
            combined.append(gc.allocator, prefix[0]) catch return PrimitiveError.OutOfMemory;
            combined.appendSlice(gc.allocator, source) catch return PrimitiveError.OutOfMemory;
            source = combined.items;
        }

        var reader = reader_mod.Reader.init(gc, source);
        reader.mark_immutable = false;
        defer reader.deinit();
        const maybe_datum = parseDatumForRead(&reader) catch |err| {
            if (err == reader_mod.ReadError.OutOfMemory) return PrimitiveError.OutOfMemory;
            return raiseReadError(gc);
        };
        const datum = maybe_datum orelse return types.EOF;
        // Advance string_pos by amount consumed
        port.string_pos += reader.pos;
        if (combined.items.len > 0 and reader.pos > 0) {
            // Adjust for the prefix byte
            port.string_pos -= 1;
        }
        return datum;
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gc.allocator);

    // Drain in chronological order: peek_byte → peek_extra → read_buf → fd
    if (port.peek_byte) |b| {
        buf.append(gc.allocator, b) catch return PrimitiveError.OutOfMemory;
        port.peek_byte = null;
    }
    while (port.peek_extra_len > 0) {
        buf.append(gc.allocator, port.peek_extra[0]) catch return PrimitiveError.OutOfMemory;
        port.peek_extra[0] = port.peek_extra[1];
        port.peek_extra[1] = port.peek_extra[2];
        port.peek_extra_len -= 1;
    }
    if (port.read_buf) |rb| {
        const pos = rb.len - port.read_buf_len;
        buf.appendSlice(gc.allocator, rb[pos .. pos + port.read_buf_len]) catch return PrimitiveError.OutOfMemory;
        gc.allocator.free(rb);
        port.read_buf = null;
        port.read_buf_len = 0;
    }

    // Read from fd, parsing incrementally so that interactive terminals
    // return as soon as a complete datum is available (#847).
    if (port.write_buf_len > port.write_buf_start) {
        // A park in this drain must preserve the bytes already moved out
        // of peek_byte/peek_extra/read_buf into `buf` above — a bare try
        // would unwind without stashing and the retry would lose them.
        drainWriteBuffer(port) catch |err| return propagateReadErr(port, err, &.{buf.items});
    }
    maybeSetNonblocking(port);
    var tmp: [read_chunk_size]u8 = undefined;
    while (true) {
        // Try to parse a datum from what we already have.
        if (buf.items.len > 0) {
            var reader = reader_mod.Reader.init(gc, buf.items);
            reader.mark_immutable = false;
            defer reader.deinit();
            const result = parseDatumForRead(&reader);
            if (result) |maybe_datum| {
                if (maybe_datum) |datum| {
                    // Save unconsumed bytes back to port buffer.
                    const remaining = buf.items[reader.pos..];
                    if (remaining.len > 0) {
                        const saved = gc.allocator.alloc(u8, remaining.len) catch return PrimitiveError.OutOfMemory;
                        @memcpy(saved, remaining);
                        port.read_buf = saved;
                        port.read_buf_len = remaining.len;
                    }
                    return datum;
                }
                // Buffer was only whitespace/comments — discard and read more.
                buf.clearRetainingCapacity();
            } else |err| {
                if (err != reader_mod.ReadError.UnexpectedEof)
                    return if (err == reader_mod.ReadError.OutOfMemory) PrimitiveError.OutOfMemory else raiseReadError(gc);
                // Incomplete datum — fall through to read more.
            }
        }

        const raw_n = portFdRead(port, &tmp, tmp.len);
        if (raw_n < 0) {
            const e = platform.errno(raw_n);
            if (e == .INTR) continue;
            if (e == .AGAIN) {
                // Mid-datum would-block: a parked retry re-executes this
                // primitive from the top, so the partial accumulation goes
                // back into port.read_buf and is re-drained on entry. The
                // scheduler-driving path resumes right here with `buf`
                // intact and just reads again.
                waitPortFd(port, .read) catch |err|
                    return propagateReadErr(port, err, &.{buf.items});
                continue;
            }
            break;
        }
        if (raw_n == 0) break; // EOF
        const n: usize = @intCast(raw_n);
        buf.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    // Reached EOF — parse whatever remains.
    if (buf.items.len == 0) return types.EOF;

    var reader = reader_mod.Reader.init(gc, buf.items);
    reader.mark_immutable = false;
    defer reader.deinit();
    const maybe_datum = parseDatumForRead(&reader) catch |err| {
        if (err == reader_mod.ReadError.OutOfMemory) return PrimitiveError.OutOfMemory;
        return raiseReadError(gc);
    };
    const datum = maybe_datum orelse return types.EOF;

    const remaining = buf.items[reader.pos..];
    if (remaining.len > 0) {
        const saved = gc.allocator.alloc(u8, remaining.len) catch return PrimitiveError.OutOfMemory;
        @memcpy(saved, remaining);
        port.read_buf = saved;
        port.read_buf_len = remaining.len;
    }

    return datum;
}

fn fileExistsP(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return types.FALSE;
    if (!types.isString(args[0])) return primitives.typeError("file-exists?", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    return if (platform.pathExists(path_z)) types.TRUE else types.FALSE;
}

fn eofObjectP(args: []const Value) PrimitiveError!Value {
    return if (args[0] == types.EOF) types.TRUE else types.FALSE;
}

fn eofObjectFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.EOF;
}

// ---------------------------------------------------------------------------
// String ports (R7RS 6.13)
// ---------------------------------------------------------------------------

fn openInputString(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("open-input-string", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    return gc.allocStringInputPort(str.data[0..str.len]) catch return PrimitiveError.OutOfMemory;
}

fn openOutputString(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocStringOutputPort() catch return PrimitiveError.OutOfMemory;
}

fn getOutputString(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("get-output-string", "port", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = types.toObject(args[0]).as(types.Port);
    if (!port.is_string_port or !port.is_output) return primitives.typeError("get-output-string", "output string port", args[0]);
    const buf = port.string_out_buf orelse return gc.allocString("") catch return PrimitiveError.OutOfMemory;
    return gc.allocString(buf[0..port.string_out_len]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Additional I/O procedures
// ---------------------------------------------------------------------------

fn readStringFn(args: []const Value) PrimitiveError!Value {
    // (read-string k [port]) -- read k characters
    if (!types.isFixnum(args[0])) return primitives.typeError("read-string", "integer", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("read-string", "non-negative integer", args[0]);
    const count: usize = @intCast(@as(u64, @bitCast(k)));
    const port = try getInputPort(args, 1, "read-string");

    // (read-string 0 port) yields "" -- characters are "available" only when
    // k > 0, so k = 0 never signals EOF (mirrors read-bytevector, issue #281).
    if (count == 0) return gc.allocString("") catch return PrimitiveError.OutOfMemory;

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);

    var chars_read: usize = 0;
    while (chars_read < count) {
        // On a park, readUtf8Char has already stashed its own mid-sequence
        // bytes; prepending the accumulated characters keeps the retry's
        // byte stream chronological.
        const cp = (readUtf8Char(port) catch |err|
            return propagateReadErr(port, err, &.{result.items})) orelse break;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch break;
        result.appendSlice(gc.allocator, buf[0..len]) catch return PrimitiveError.OutOfMemory;
        chars_read += 1;
    }
    if (result.items.len == 0) return types.EOF;
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

fn flushOutputPort(args: []const Value) PrimitiveError!Value {
    const port = try getOutputPort(args, 0, "flush-output-port");
    // String ports and the unbuffered standard fds have nothing pending;
    // buffered fd ports drain fully (suspending the fiber as needed —
    // idempotent across a parked retry since progress lives in the port).
    if (isBufferedFdPort(port)) try drainWriteBuffer(port);
    return types.VOID;
}

fn deleteFile(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return primitives.typeError("delete-file", "non-WASM platform", args[0]);
    if (!types.isString(args[0])) return primitives.typeError("delete-file", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const result = platform.unlink(path_z);
    if (result < 0) {
        var msg = gc.allocString("cannot delete file") catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&msg);
        defer gc.popRoot();
        var irritant = gc.allocString(path) catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&irritant);
        defer gc.popRoot();
        var irr_list = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&irr_list);
        defer gc.popRoot();
        const err_obj = gc.allocErrorObject(msg, irr_list) catch return PrimitiveError.OutOfMemory;
        types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
        const raise_args = [1]Value{err_obj};
        return primitives_control.raiseFn(&raise_args);
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// File I/O wrappers (R7RS 6.13)
// ---------------------------------------------------------------------------

/// (call-with-input-file string proc)
fn callWithInputFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    // Open file
    const port_val = try openInputFile(&[_]Value{args[0]});
    // Call proc with port
    const result = vm.callWithArgs(args[1], &[_]Value{port_val}) catch |err| {
        // Close port on error
        _ = closePort(&[_]Value{port_val}) catch {};
        return err;
    };
    // Close port
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (call-with-output-file string proc)
fn callWithOutputFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = try openOutputFile(&[_]Value{args[0]});
    const result = vm.callWithArgs(args[1], &[_]Value{port_val}) catch |err| {
        _ = closePort(&[_]Value{port_val}) catch {};
        return err;
    };
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (call-with-port port proc)
fn callWithPort(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("call-with-port", "port", args[0]);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const result = vm.callWithArgs(args[1], &[_]Value{args[0]}) catch |err| {
        _ = closePort(&[_]Value{args[0]}) catch {};
        return err;
    };
    _ = try closePort(&[_]Value{args[0]});
    return result;
}

/// (with-input-from-file string thunk)
fn withInputFromFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = try openInputFile(&[_]Value{args[0]});
    const saved = currentInputPortValue(vm);
    setCurrentPort(vm, vm.current_input_port_param, port_val);
    const result = vm.callWithArgs(args[1], &[_]Value{}) catch |err| {
        setCurrentPort(vm, vm.current_input_port_param, saved);
        _ = closePort(&[_]Value{port_val}) catch {};
        return err;
    };
    setCurrentPort(vm, vm.current_input_port_param, saved);
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (with-output-to-file string thunk)
fn withOutputToFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = try openOutputFile(&[_]Value{args[0]});
    const saved = currentOutputPortValue(vm);
    setCurrentPort(vm, vm.current_output_port_param, port_val);
    const result = vm.callWithArgs(args[1], &[_]Value{}) catch |err| {
        setCurrentPort(vm, vm.current_output_port_param, saved);
        _ = closePort(&[_]Value{port_val}) catch {};
        return err;
    };
    setCurrentPort(vm, vm.current_output_port_param, saved);
    _ = try closePort(&[_]Value{port_val});
    return result;
}

fn setCurrentPort(vm: *vm_mod.VM, param_val: Value, port_val: Value) void {
    if (param_val != types.VOID) {
        vm.setParameterValue(types.toParameter(param_val), port_val) catch {};
    }
}
