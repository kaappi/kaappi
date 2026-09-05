//! `(kaappi process)` primitives — the Scheme surface of KEP-0022.
//!
//! Spawn-based subprocess support with redirections expressed as named
//! options, pipe parent-ends wrapped as ordinary fd ports on the
//! reactor-integrated path (via `primitives_io.makeFdPort`, the constructor
//! `fd->port` shares), a `process-wait` that parks instead of blocking, and a
//! `process-kill` that never re-signals a reaped child. There is no pre-exec
//! hook; every knob between spawn and exec is a named option. (The POSIX
//! backend spawns through `posix_spawnp` except on its two fork-route
//! cases — see `process_posix.routeFor`; Windows never forks.)
//!
//! This file owns everything platform-independent: option parsing,
//! redirection validation, the `Process` object and its ports, the zombie
//! sweeps, and the whole Phase-2 fiber park. The syscalls live in the two
//! backends, selected at comptime:
//!
//! | Phase | Backend | Spawn | Group | Reap |
//! |-------|---------|-------|-------|------|
//! | 1/2 (kaappi#2414, #2415) | `process_posix.zig` | `posix_spawnp` + file actions | POSIX process group | `waitpid` / pidfd / EVFILT_PROC |
//! | 3 (kaappi#2416) | `process_win.zig` | `CreateProcessW` + explicit inherit list | Job Object | process HANDLE |
//!
//! The seam between the two is the three types in `types_process.zig`
//! (`Redir`, `SpawnConfig`, `Spawned`) plus the small function set each
//! backend exports; nothing OS-specific is analyzed on the other platform,
//! because only one of the two files is ever imported.
//!
//! Phase 2 (kaappi#2415): `process-wait` parks the calling fiber against the
//! reactor's child-exit readiness (kqueue EVFILT_PROC / Linux pidfd /
//! Windows process handle) instead of blocking the whole OS thread, with a
//! `timeout:` option riding the reactor timer heap (Python's contract — `#f`
//! on expiry, child lives). Reaping happens at the reactor, exactly once;
//! the Phase-1 blocking reap survives only as the no-scheduler fallback.
//! On WASM — which has no process creation at all — this module is not
//! registered, so `(library (kaappi process))` gates false.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const types_process = @import("types_process.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const primitives_io = @import("primitives_io.zig");
const primitives_r7rs = @import("primitives_r7rs.zig");
const fiber_mod = @import("fiber.zig");
const srfi18 = @import("primitives_srfi18.zig");

const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;
const GC = memory.GC;
const Redir = types_process.Redir;
const SpawnConfig = types_process.SpawnConfig;

/// The OS backend. Exactly one of the two files is imported, so neither
/// platform's raw syscall surface is ever analyzed on the other.
const backend = if (platform.is_windows)
    @import("process_win.zig")
else
    @import("process_posix.zig");

const SIGTERM: c_int = 15;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// A catchable `.file` error carrying errno, mirroring
/// primitives_filesystem.raiseFileErrorCode: spawn failures are the same
/// family as open failures ("program not found" vs "permission" is exactly
/// ENOENT vs EACCES), so `file-error?` and `posix-error?` see them. Pass 0
/// for rejections that never reached a syscall. Public because both backends
/// raise through it (a Win32 failure arrives with `GetLastError` already
/// folded onto an errno by `process_win.lastError`).
pub fn raiseProcessError(gc: *GC, msg_text: []const u8, irritant: Value, errno_val: c_int) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant
    var msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    var irritants_root = irritants;
    gc.pushRoot(&irritants_root);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, irritants_root) catch return PrimitiveError.OutOfMemory;
    const err = types.toObject(err_obj).as(types.ErrorObject);
    err.error_type = .file;
    err.posix_errno = errno_val;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

fn raiseProcessMessage(comptime msg: []const u8) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var msg_val = gc.allocString(msg) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg_val);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg_val, types.NIL) catch return PrimitiveError.OutOfMemory;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

// ---------------------------------------------------------------------------
// Argument checking (owner check = channel precedent, KEP-0022)
// ---------------------------------------------------------------------------

/// Type-check, owner-check, and unwrap a Process argument. A Process is
/// thread-affine — its pid, status bookkeeping and (Phase 2) reactor
/// registration belong to the scheduler of the thread that spawned it —
/// exactly like a channel (primitives_fiber.zig) and a thread handle
/// (primitives_srfi18.checkThreadOwner). `process?` stays exempt, exactly
/// like `channel?`/`thread?`. The irritant is #f rather than the foreign
/// process: storing a foreign-heap object in a condition the owner's GC may
/// free would re-open the hazard the check exists to close.
fn expectProcess(comptime proc: []const u8, val: Value) PrimitiveError!*types.Process {
    if (!types.isProcess(val)) return primitives.typeError(proc, "process", val);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const obj = types.toObject(val);
    if (obj.owner != gc.id) {
        // Always raises (.ExceptionRaised); `try` propagates it.
        _ = try raiseProcessMessage(proc ++ ": process belongs to another thread; a process may only be used by the thread that spawned it");
    }
    return obj.as(types.Process);
}

// ---------------------------------------------------------------------------
// Redirection specs
// ---------------------------------------------------------------------------

fn parseRedir(comptime proc: []const u8, val: Value) PrimitiveError!Redir {
    if (val == types.FALSE or val == types.VOID) return .inherit;
    if (types.isSymbol(val)) {
        const name = types.symbolName(val);
        if (std.mem.eql(u8, name, "inherit")) return .inherit;
        if (std.mem.eql(u8, name, "pipe")) return .pipe;
        if (std.mem.eql(u8, name, "null")) return .null_sink;
        if (std.mem.eql(u8, name, "stdout")) return .merge_stdout;
        return primitives.argError(proc, "unknown redirection spec: {s}", .{name});
    }
    if (types.isPort(val)) {
        // Read the fd before anything can allocate; reject port kinds whose
        // backing is not an OS descriptor (string/custom/transcoded/random).
        const port = types.toObject(val).as(types.Port);
        if (!port.is_open or port.is_string_port or port.custom_backend != null or
            port.transcode != null or port.random_gen != null)
        {
            return primitives.argError(proc, "redirection port must be an open fd-backed port", .{});
        }
        if (port.fd < 0) return primitives.argError(proc, "redirection port has no file descriptor", .{});
        // The child's slot copy would share this fd's open file description
        // — O_NONBLOCK included. A port the fiber scheduler already flipped
        // non-blocking would hand the child non-blocking stdio, and the
        // parent's next I/O would re-flip it even if cleared here; reject
        // rather than corrupt (kaappi#2414 review). Windows keeps the same
        // rejection even though its non-blocking mode is emulated in the
        // port rather than set on the handle: one rule, not a platform
        // lottery for which ports a program may redirect.
        if (port.nonblocking)
            return primitives.argError(proc, "redirection port is in non-blocking use by the fiber scheduler; pass a port not yet driven by fibers", .{});
        // Input read-ahead FIRST: software read-ahead makes the kernel
        // offset run ahead of the port's logical position, so a child
        // handed the raw fd would silently skip the buffered bytes.
        // Seekable fds are rewound; an unseekable fd with pending
        // read-ahead is rejected. Order matters on a bidirectional port:
        // draining output before the rewind would land the parent's
        // buffered writes at the stale read-ahead offset instead of the
        // logical position (kaappi#2442 review).
        if (port.is_input) {
            const unsynced = primitives_io.rewindPortReadAheadForSpawn(port);
            if (unsynced != 0)
                return primitives.argError(proc, "redirection port has {d} buffered byte(s) of read-ahead that its unseekable descriptor cannot give back to the child", .{unsynced});
        }
        // Then buffered parent output, so it lands in the file at the
        // logical position, before the child's own writes; the drain can
        // park a fiber, and a re-executed spawn re-parses the options
        // idempotently.
        if (port.is_output) try primitives_io.drainPortWriteBufferForSpawn(port);
        return .{ .fd = port.fd };
    }
    return primitives.typeError(proc, "redirection spec (inherit, pipe, null, stdout, or an fd-backed port)", val);
}

// ---------------------------------------------------------------------------
// Zombie sweep (KEP-0022 unresolved question 3, settled for Phase 1)
// ---------------------------------------------------------------------------

/// Reap every already-exited unreaped process of this heap, storing each
/// status into its Process. Bounded: the list holds only unreaped processes,
/// so the sweep is O(concurrently-unreaped), and it runs at the top of the
/// two blocking paths (spawn, wait) — covering the scheduler-less loop that
/// never runs a reactor tick. Together with freeObject's last-resort reap,
/// the only escaping window is a Process collected while its child still
/// runs (documented on `GC.unreaped_processes`).
///
/// Windows has no zombies — an exited child persists exactly as long as a
/// handle to it does — but the sweep still earns its keep there: it is what
/// turns "exited" into a stored status and a waiter wakeup on the paths that
/// never run a reactor tick.
fn sweepUnreaped(gc: *GC) void {
    var i: usize = 0;
    while (i < gc.unreaped_processes.items.len) {
        const proc = gc.unreaped_processes.items[i];
        if (types_process.reapNonBlocking(proc) == .reaped) {
            _ = gc.unreaped_processes.swapRemove(i);
            // A reap outside the reactor must still deliver the wakeup the
            // reactor's exit event would have (Phase 2): a fiber parked in
            // process-wait on this child learns of the exit from the stored
            // status, never from a wait of its own.
            wakeProcessWaiters(proc);
        } else {
            i += 1;
        }
    }
}

/// Wake every fiber parked in `process-wait` on `proc` and drop its reactor
/// registration — the out-of-band half of the reactor's own exit handling,
/// for the reap paths that run outside `Reactor.poll` (`process-status`'s
/// targeted reap, the WNOHANG sweeps). The current fiber is never in the
/// list from its own call path (it parks only after the status checks), and
/// a stale entry for a since-terminated fiber fails the `.waiting` guard.
fn wakeProcessWaiters(proc: *types.Process) void {
    const vm = vm_mod.vm_instance orelse return;
    const reactor = vm.reactor orelse return;
    const sched = vm.scheduler orelse return;
    var waiters = reactor.cancelProcessWatch(proc);
    defer waiters.deinit(reactor.allocator);
    for (waiters.items) |f| {
        if (f.status == .waiting) {
            f.status = .suspended;
            sched.markRunnable(f);
        }
    }
}

// ---------------------------------------------------------------------------
// %process-spawn / spawn-process
// ---------------------------------------------------------------------------

/// The spawn itself: validate what is platform-independent, hand the
/// syscalls to the backend, then build the Process and its ports from what
/// comes back. Everything GC-managed is read before the backend's
/// allocation-free syscall section; the Process object and its ports are
/// allocated only after the child exists.
fn spawnImpl(cfg: SpawnConfig) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Zombie sweep on the blocking spawn path (see sweepUnreaped).
    sweepUnreaped(gc);

    const redirs = [3]Redir{ cfg.stdin, cfg.stdout, cfg.stderr };
    // 'stdout means "this slot becomes a copy of the child's stdout", which
    // only stderr can ask for. Checked here rather than in each backend, so
    // both reject it identically and neither has to reach the spec.
    if (redirs[0] == .merge_stdout or redirs[1] == .merge_stdout)
        return primitives.argError("spawn-process", "'stdout is a stderr-only redirection spec", .{});
    if (cfg.directory) |dir_val| {
        if (!types.isString(dir_val)) return primitives.typeError("spawn-process", "string", dir_val);
    }

    var spawned = try backend.spawnChild(gc, cfg, redirs);
    // Every parent pipe end the backend handed over is ours to release until
    // a Port owns it; blanking a slot is what records the transfer, so no
    // exit path from here on can double-close or leak one.
    defer for (&spawned.parent_ends) |*fd| {
        if (fd.* >= 0) _ = platform.close(fd.*);
        fd.* = -1;
    };

    const proc = gc.allocProcess(spawned.pid, spawned.pgid) catch {
        // Nothing tracks this child (enrolment happens inside allocProcess),
        // so an unreaped survivor here is lost for good — but that needs
        // the kill itself to fail, which has no realistic path.
        _ = backend.killAndReapFresh(spawned);
        return PrimitiveError.OutOfMemory;
    };
    // The OS handles belong to the Process from here on: `gc_sweep.freeObject`
    // closes them, and the errdefer below leaves them alone.
    proc.win_handle = spawned.win_handle;
    proc.win_job = spawned.win_job;
    var proc_val = types.makePointer(&proc.header);
    gc.pushRoot(&proc_val);
    defer gc.popRoot();

    // Any failure between here and the return leaves a Process the caller
    // will never see: it would be collected, dropped from the unreaped
    // registry, and its still-running child would be permanently untracked
    // (kaappi#2442 review — the kill/reap must cover the port
    // constructions, not just allocProcess). Terminate and reap the fresh
    // child, and record the status so a later sweep does not re-probe a
    // reused pid (or, on Windows, a handle whose process is gone).
    errdefer {
        if (backend.killAndReapChild(proc)) {
            proc.status = backend.kill_fresh_status;
            removeFromUnreaped(gc, proc);
        }
        // else: keep the registry entry — the sweeps reap it when the child
        // does die, instead of the pid being forgotten.
    }

    if (spawned.parent_ends[0] >= 0) {
        const port_val = try primitives_io.makeFdPort(gc, spawned.parent_ends[0], false, true, "process-stdin");
        spawned.parent_ends[0] = -1;
        proc.stdin_port = port_val;
        gc.writeBarrier(&proc.header, port_val);
    }
    if (spawned.parent_ends[1] >= 0) {
        const port_val = try primitives_io.makeFdPort(gc, spawned.parent_ends[1], true, false, "process-stdout");
        spawned.parent_ends[1] = -1;
        proc.stdout_port = port_val;
        gc.writeBarrier(&proc.header, port_val);
    }
    if (spawned.parent_ends[2] >= 0) {
        const port_val = try primitives_io.makeFdPort(gc, spawned.parent_ends[2], true, false, "process-stderr");
        spawned.parent_ends[2] = -1;
        proc.stderr_port = port_val;
        gc.writeBarrier(&proc.header, port_val);
    }
    return proc_val;
}

/// Collect an argv list of Values for SpawnConfig. The Values are rooted by
/// the caller's register file (they are args), so plain ArrayList storage is
/// GC-safe; the strings themselves are copied by the backend later.
/// Cycle-guarded: a cyclic argv must be an error, not an unbounded
/// native-side loop.
fn collectArgv(comptime proc: []const u8, list_val: Value, gc: *GC) PrimitiveError!std.ArrayList(Value) {
    if (!types.isPair(list_val))
        return primitives.typeError(proc, "argv list of strings", list_val);
    var list: std.ArrayList(Value) = .empty;
    errdefer list.deinit(gc.allocator);
    var cur = list_val;
    var slow = list_val;
    var step = false;
    while (cur != types.NIL) : (step = !step) {
        if (!types.isPair(cur))
            return primitives.typeError(proc, "argv list of strings", list_val);
        list.append(gc.allocator, types.car(cur)) catch return PrimitiveError.OutOfMemory;
        cur = types.cdr(cur);
        if (step) {
            slow = types.cdr(slow);
            if (cur == slow)
                return primitives.argError(proc, "argv list is cyclic", .{});
        }
    }
    return list;
}

/// (spawn-process argv ['stdin: spec] ['stdout: spec] ['stderr: spec]
///                  ['directory: path] ['env: alist] ['new-group: bool])
///
/// Options are quoted keyword symbols followed by their value, Guile-style:
/// `(spawn-process '("ls" "-l") 'stdout: 'pipe 'new-group: #t)`.
fn spawnProcessFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var argv_list = try collectArgv("spawn-process", args[0], gc);
    defer argv_list.deinit(gc.allocator);
    var cfg = SpawnConfig{ .argv = argv_list.items };

    var i: usize = 1;
    while (i < args.len) : (i += 2) {
        if (!types.isSymbol(args[i]))
            return primitives.argError("spawn-process", "expected an option symbol like 'stdin:, got a value", .{});
        if (i + 1 >= args.len)
            return primitives.argError("spawn-process", "option '{s}' has no value", .{types.symbolName(args[i])});
        const opt = types.symbolName(args[i]);
        const val = args[i + 1];
        if (std.mem.eql(u8, opt, "stdin:")) {
            cfg.stdin = try parseRedir("spawn-process", val);
        } else if (std.mem.eql(u8, opt, "stdout:")) {
            cfg.stdout = try parseRedir("spawn-process", val);
        } else if (std.mem.eql(u8, opt, "stderr:")) {
            cfg.stderr = try parseRedir("spawn-process", val);
        } else if (std.mem.eql(u8, opt, "directory:")) {
            cfg.directory = val;
        } else if (std.mem.eql(u8, opt, "env:")) {
            cfg.env = val;
        } else if (std.mem.eql(u8, opt, "new-group:")) {
            cfg.new_group = types.isTruthy(val);
        } else {
            return primitives.argError("spawn-process", "unknown option '{s}'", .{opt});
        }
    }
    return spawnImpl(cfg);
}

/// (%process-spawn argv stdin stdout stderr directory env new-group) — the
/// normalized positional form of spawn-process with no option parsing: the
/// stable internal entry point for future Scheme-level layers (run-process,
/// Phase 4) and compiler-synthesized call sites. Specs are the symbols
/// inherit/pipe/null/stdout or an fd-backed port (#f = inherit); directory
/// and env are a string / an alist or #f.
fn processSpawnRawFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var argv_list = try collectArgv("%process-spawn", args[0], gc);
    defer argv_list.deinit(gc.allocator);
    const cfg = SpawnConfig{
        .argv = argv_list.items,
        .stdin = try parseRedir("%process-spawn", args[1]),
        .stdout = try parseRedir("%process-spawn", args[2]),
        .stderr = try parseRedir("%process-spawn", args[3]),
        .directory = if (args[4] == types.FALSE) null else args[4],
        .env = if (args[5] == types.FALSE) null else args[5],
        .new_group = types.isTruthy(args[6]),
    };
    return spawnImpl(cfg);
}

// ---------------------------------------------------------------------------
// Accessors and control
// ---------------------------------------------------------------------------

fn processP(args: []const Value) PrimitiveError!Value {
    return if (types.isProcess(args[0])) types.TRUE else types.FALSE;
}

fn processPid(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-pid", args[0]);
    // Windows process ids are unsigned; `Process.pid` stores the bit pattern
    // so the reactor can key on it, and this is where it reads back as the
    // number the OS reports.
    if (comptime platform.is_windows)
        return types.makeFixnum(@as(i64, @as(u32, @bitCast(proc.pid))));
    return types.makeFixnum(proc.pid);
}

fn processGroup(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-group", args[0]);
    if (proc.pgid == 0) return types.FALSE;
    if (comptime platform.is_windows)
        return types.makeFixnum(@as(i64, @as(u32, @bitCast(proc.pgid))));
    return types.makeFixnum(proc.pgid);
}

fn processStdin(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-stdin", args[0]);
    return proc.stdin_port;
}

fn processStdout(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-stdout", args[0]);
    return proc.stdout_port;
}

fn processStderr(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-stderr", args[0]);
    return proc.stderr_port;
}

/// Non-blocking targeted reap: if `proc`'s child has exited, store its
/// status and drop it from the unreaped list. Shared by process-status (so
/// polling reflects an exit without an intervening wait — and doubles as the
/// KEP's zombie-discipline hook on the polling path) and by the wait path.
fn tryReapOne(gc: *GC, proc: *types.Process) void {
    if (proc.status != null) return;
    if (types_process.reapNonBlocking(proc) == .reaped) {
        removeFromUnreaped(gc, proc);
        // See sweepUnreaped: a reap outside the reactor must still wake any
        // parked process-wait waiters.
        wakeProcessWaiters(proc);
    }
}

fn removeFromUnreaped(gc: *GC, proc: *types.Process) void {
    for (gc.unreaped_processes.items, 0..) |p, idx| {
        if (p == proc) {
            _ = gc.unreaped_processes.swapRemove(idx);
            break;
        }
    }
}

fn processStatus(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-status", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    tryReapOne(gc, proc);
    // Scalar out before the allocating decode (gc-safety: no raw pointer
    // across allocation).
    const status = proc.status;
    if (status) |st| return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
    return types.FALSE;
}

/// Terminal-exit cleanup for a fiber that was (or may have been) parked in
/// `process-wait` on `proc`: withdraws its reactor waiter entry, detaches an
/// armed timeout timer, and clears the park fields. Every step is a guarded
/// no-op on a fiber that never parked, so the status-return fast path calls
/// this unconditionally — a flat-park retry woken by the exit event arrives
/// there with `waiting_on` still set and possibly a live timer (the wake
/// clears neither), and leaving either behind fires into whatever wait this
/// fiber enters next (#1602's stale-timer hazard; the #2433 discipline).
fn clearProcessParkState(proc: *types.Process, proc_val: Value) void {
    const vm = vm_mod.vm_instance orelse return;
    const sched = vm.scheduler orelse return;
    const me = sched.fibers.items[sched.current_idx] orelse return;
    if (vm.reactor) |r| {
        r.removeProcessWaiter(proc, me);
        if (me.waiting_on == proc_val and me.deadline_ns != null) {
            r.removeTimer(me);
            me.deadline_ns = null;
        }
    }
    if (me.waiting_on == proc_val) {
        me.waiting_on = types.VOID;
        // Spurious by construction here: the reactor's wake path
        // (wakeReadyFiber) flips timed_out for every `.waiting` fiber it
        // reports, exit events included — the status-first discipline is
        // what distinguishes an exit from a timeout, and this clear keeps
        // the flag from leaking into the fiber's next timed wait.
        me.timed_out = false;
    }
}

/// The Phase-1 blocking reap, kept as the no-scheduler fallback (and the
/// degradation path when the reactor cannot watch this child).
fn blockingWaitReap(gc: *GC, proc: *types.Process) PrimitiveError!Value {
    const wait_errno = backend.blockingReap(proc);
    if (wait_errno != 0)
        return raiseProcessError(gc, "cannot wait for process", types.FALSE, wait_errno);
    const raw = proc.status.?;
    removeFromUnreaped(gc, proc);
    wakeProcessWaiters(proc);
    return types.decodeWaitStatus(gc, raw) catch PrimitiveError.OutOfMemory;
}

/// Wait condition for the in-call scheduler drive: the child has been
/// reaped — by the reactor's exit event, a sweep, or a sibling's
/// process-status — and its status stored.
const ProcessWait = struct {
    proc: *types.Process,
    pub fn isDone(self: ProcessWait) bool {
        return self.proc.status != null;
    }
};

/// Registration-failure degradation: the kernel cannot watch this child
/// (pidfd_open is ENOSYS on pre-5.3 kernels and under Rosetta's x86_64
/// syscall translation), so poll a non-blocking reap at a fixed cadence
/// while parking on the reactor timer heap between probes. Sibling fibers
/// keep running — the guarantee the blocking fallback cannot give: a program
/// whose child exits only after a sibling acts (the starvation test's
/// close-the-stdin idiom) would deadlock outright in a blocking wait.
///
/// Drives in place for every caller, dispatched fibers included: with no
/// kernel event to wake a flat park, a yield-retry would need to tell its
/// polling timer from the user's `timeout:` deadline, while a drive needs
/// no such split — each cadence timer ends exactly one bounded park, so the
/// #1625 unbounded-block wedge cannot arise either.
const POLL_FALLBACK_CADENCE_NS: u64 = 20 * std.time.ns_per_ms;

fn polledWait(gc: *GC, proc: *types.Process, proc_val: Value, deadline_ns: ?u64) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode;
    const ctx = try fiber_mod.ensureScheduler(vm);
    const me = ctx.sched.fibers.items[ctx.sched.current_idx].?;
    while (true) {
        if (proc.status == null) {
            // This loop is the terminal resolver on kernels that cannot
            // watch the process, so a persistent reap failure (ECHILD —
            // something outside Kaappi reaped our child) must surface as the
            // same error the blocking path raises, not spin at the cadence
            // forever.
            switch (types_process.reapNonBlocking(proc)) {
                .reaped => {
                    removeFromUnreaped(gc, proc);
                    wakeProcessWaiters(proc);
                },
                .running => {},
                .failed => return raiseProcessError(gc, "cannot wait for process", types.FALSE, backend.lastError()),
            }
        }
        if (proc.status) |st| {
            me.timed_out = false;
            return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
        }
        const now = fiber_mod.clockNs();
        if (deadline_ns) |d| {
            if (now >= d) return types.FALSE;
        }
        const until = if (deadline_ns) |d| @min(d, now +| POLL_FALLBACK_CADENCE_NS) else now +| POLL_FALLBACK_CADENCE_NS;
        me.timed_out = false;
        me.status = .waiting;
        me.waiting_on = proc_val;
        vm.gc.writeBarrier(&me.header, proc_val);
        me.deadline_ns = until;
        ctx.reactor.addTimer(until, me) catch |err| {
            me.status = .running;
            me.waiting_on = types.VOID;
            me.deadline_ns = null;
            return err;
        };
        _ = fiber_mod.runSchedulerStep(ProcessWait, .{ .proc = proc }, ctx.vm, ctx.sched, me) catch |err| {
            // The #2433 unpark discipline, same as the registered path.
            me.status = .running;
            me.timed_out = false;
            ctx.reactor.removeTimer(me);
            me.waiting_on = types.VOID;
            me.deadline_ns = null;
            return err;
        };
        ctx.reactor.removeTimer(me);
        me.deadline_ns = null;
        me.waiting_on = types.VOID;
        me.timed_out = false;
    }
}

/// (process-wait p ['timeout: seconds])
///
/// Parks the calling fiber on the reactor's child-exit readiness (KEP-0022
/// Phase 2): siblings keep running while this fiber waits. `timeout:` bounds
/// the wait via the reactor timer heap and returns `#f` on expiry with the
/// child still running (Python's contract); `#f` as the timeout value means
/// no timeout. With no scheduler and no timeout the Phase-1 blocking
/// fallback is unchanged. Status resolution is status-first everywhere: a
/// stored status outranks a fired timer (delivery-wins, the channel
/// precedent), which is also what makes the reactor's wake-all discipline
/// safe — a woken retry consults `proc.status`, never a syscall of its own.
fn processWait(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-wait", args[0]);
    const proc_val = args[0];

    var deadline_ns: ?u64 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 2) {
        if (!types.isSymbol(args[i]))
            return primitives.argError("process-wait", "expected an option symbol like 'timeout:", .{});
        if (i + 1 >= args.len)
            return primitives.argError("process-wait", "option '{s}' has no value", .{types.symbolName(args[i])});
        const opt = types.symbolName(args[i]);
        if (std.mem.eql(u8, opt, "timeout:")) {
            deadline_ns = try srfi18.timeoutToDeadlineNs("process-wait", args[i + 1]);
        } else {
            return primitives.argError("process-wait", "unknown option '{s}'", .{opt});
        }
    }

    // Already reaped (an earlier wait, a sweep, the reactor, or a sibling's
    // process-status): the stored status is the answer. Runs the park-state
    // cleanup first — this is exactly where a flat-parked waiter woken by
    // the exit event re-enters.
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (proc.status) |st| {
        clearProcessParkState(proc, proc_val);
        return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
    }

    // Sweep next: a prior spawn/wait sweep may already hold our exit, and
    // this is the KEP's zombie-discipline hook on the wait path. Delivery
    // wins over a fired timer by the same order.
    sweepUnreaped(gc);
    if (proc.status) |st| {
        clearProcessParkState(proc, proc_val);
        return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant

    // No scheduler and no timeout: the Phase-1 blocking fallback, verbatim.
    // (With a timeout, ensureScheduler below lazily creates the scheduler +
    // reactor and the wait resolves via the timer even with no other fiber.)
    if (vm.scheduler == null and deadline_ns == null) {
        return blockingWaitReap(gc, proc);
    }

    const ctx = try fiber_mod.ensureScheduler(vm);
    const my_idx = ctx.sched.current_idx;
    const me = ctx.sched.fibers.items[my_idx].?;

    // Post-timeout redispatch of a flat-parked wait: the status checks above
    // already gave delivery priority. `timed_out` alone is not proof of a
    // timeout — the reactor's wake path flips it for every `.waiting` fiber
    // it reports, including a wake with *no* status stored (a failed reap:
    // something outside Kaappi took our child) — so only a deadline that has
    // actually passed reports `#f`. A spurious pre-deadline wake clears the
    // flag and falls through to re-park; the dead-registration re-arm then
    // fails and resolves through the polled path below, which surfaces the
    // real wait error.
    if (me.waiting_on == proc_val and me.deadline_ns != null and me.timed_out) {
        if (fiber_mod.clockNs() >= me.deadline_ns.?) {
            me.timed_out = false;
            me.deadline_ns = null;
            ctx.reactor.removeProcessWaiter(proc, me);
            me.waiting_on = types.VOID;
            return types.FALSE;
        }
        me.timed_out = false;
    }

    // Park fields first (the reactor holds `me` from registration on), then
    // arm the kernel watch.
    me.status = .waiting;
    me.waiting_on = proc_val;
    vm.gc.writeBarrier(&me.header, proc_val);
    ctx.reactor.registerProcess(proc, me) catch |err| {
        me.status = .running;
        me.waiting_on = types.VOID;
        if (err == error.OutOfMemory) return PrimitiveError.OutOfMemory;
        // The kernel refused the watch — either the child already exited
        // (EVFILT_PROC EV_ADD and pidfd_open both fail ESRCH once the pid is
        // reapable-or-reaped; the reap below settles it) or this kernel
        // cannot watch processes at all (pidfd_open is ENOSYS before Linux
        // 5.3 and under Rosetta's syscall translation) — degrade to the
        // polled park, which keeps siblings running where a blocking wait
        // would deadlock a program whose child exits only after a sibling
        // acts. A flat retry may arrive with the previous park's preserved
        // absolute deadline (and its still-armed timer): hand the polled
        // wait that deadline, never the recomputed-and-extended one, and
        // detach the stale timer so it cannot fire into the polled parks.
        const eff_deadline = me.deadline_ns orelse deadline_ns;
        if (me.deadline_ns != null) {
            ctx.reactor.removeTimer(me);
            me.deadline_ns = null;
        }
        me.timed_out = false;
        tryReapOne(gc, proc);
        if (proc.status) |st|
            return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
        return polledWait(gc, proc, proc_val, eff_deadline);
    };
    // Exit-before-arm race close: an exit that beat the arm posts no kernel
    // event, ever — the one probe after arming is what closes the window (an
    // exit before the arm is caught here; one after it, by the event). The
    // reap wakes every registered waiter, this fiber included; restore it.
    tryReapOne(gc, proc);
    if (proc.status) |st| {
        me.status = .running;
        me.waiting_on = types.VOID;
        me.timed_out = false;
        return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
    }

    // Dispatched fiber: the flat yield_retry park — the whole primitive
    // re-executes on wake (see the retry paths above). Timer discipline
    // mirrors the channel flat parks: armed once from the preserved absolute
    // deadline, re-attached on every re-park, never extended (#1602).
    if (my_idx != 0 and vm.dispatched_from_scheduler) {
        if (me.deadline_ns orelse deadline_ns) |d| {
            ctx.reactor.removeTimer(me);
            me.deadline_ns = d;
            ctx.reactor.addTimer(d, me) catch |err| {
                // #2433: undo everything the park armed before returning a
                // catchable error.
                ctx.reactor.removeProcessWaiter(proc, me);
                me.status = .running;
                me.waiting_on = types.VOID;
                me.deadline_ns = null;
                return err;
            };
        }
        vm.yield_retry = true;
        return PrimitiveError.Yielded;
    }

    // Main fiber (or re-entrant native frames): drive the scheduler in
    // place. Siblings run; the reactor's exit event (or the timer) resolves
    // the wait. `.waiting` is safe here exactly as in every SRFI-18 timed
    // wait — schedule() never picks a `.waiting` fiber, and the epilogue
    // restores `.running`.
    me.timed_out = false;
    if (deadline_ns) |d| {
        me.deadline_ns = d;
        ctx.reactor.addTimer(d, me) catch |err| {
            ctx.reactor.removeProcessWaiter(proc, me);
            me.status = .running;
            me.waiting_on = types.VOID;
            me.deadline_ns = null;
            return err;
        };
    }
    _ = fiber_mod.runSchedulerStep(ProcessWait, .{ .proc = proc }, ctx.vm, ctx.sched, me) catch |err| {
        // Restore every park field explicitly rather than leaning on
        // runSchedulerStep's #2429 epilogue (#2433): its first
        // `try saveCurrentFiber` runs before that errdefer is armed, and the
        // epilogue never resets a mid-drive `timed_out`. OutOfMemory is
        // catchable — a `guard` must not resume on stale park state.
        ctx.reactor.removeProcessWaiter(proc, me);
        me.status = .running;
        me.timed_out = false;
        if (deadline_ns != null) {
            ctx.reactor.removeTimer(me);
            me.deadline_ns = null;
        }
        me.waiting_on = types.VOID;
        return err;
    };
    ctx.reactor.removeProcessWaiter(proc, me); // no-op if the exit event already drained it
    if (deadline_ns != null) {
        ctx.reactor.removeTimer(me);
        me.deadline_ns = null;
    }
    me.waiting_on = types.VOID;
    // Delivery wins: a stored status outranks a fired timer.
    if (proc.status) |st| {
        me.timed_out = false;
        return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
    }
    // `timed_out` alone is not a verdict (the wake path also flips it for a
    // no-status wake — a failed reap at the reactor): only an actually
    // expired deadline is a timeout.
    if (me.timed_out) {
        me.timed_out = false;
        if (deadline_ns) |d| {
            if (fiber_mod.clockNs() >= d) return types.FALSE;
        }
    }
    // No status, no expired timeout: the registration was dropped by a wake
    // that could not reap (ECHILD — something outside Kaappi took our
    // child). Finish through the polled path, which reaps a late arrival,
    // honors the remaining deadline, or surfaces the wait error.
    return polledWait(gc, proc, proc_val, deadline_ns);
}

/// (process-kill p ['signal: n] ['group: bool])
///
/// POSIX delivers signal `n` (default SIGTERM) with `kill(2)`; `group: #t`
/// signals the whole process group. Windows has no signals: the backend
/// folds `n` into the exit code it stamps with `TerminateProcess`, and
/// `group: #t` is `TerminateJobObject` on the Job Object `new-group:`
/// created — the only Windows mechanism that reaches grandchildren. See
/// `process_win.zig`'s header for the mapping.
fn processKill(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-kill", args[0]);
    var sig: c_int = SIGTERM;
    var group = false;
    var i: usize = 1;
    while (i < args.len) : (i += 2) {
        if (!types.isSymbol(args[i]))
            return primitives.argError("process-kill", "expected an option symbol like 'signal:", .{});
        if (i + 1 >= args.len)
            return primitives.argError("process-kill", "option '{s}' has no value", .{types.symbolName(args[i])});
        const opt = types.symbolName(args[i]);
        const val = args[i + 1];
        if (std.mem.eql(u8, opt, "signal:")) {
            if (!types.isFixnum(val))
                return primitives.typeError("process-kill", "integer (signal number)", val);
            const n = types.toFixnum(val);
            if (n < 0 or n > 64)
                return primitives.argError("process-kill", "signal number {d} outside the valid range", .{n});
            sig = @intCast(n);
        } else if (std.mem.eql(u8, opt, "group:")) {
            group = types.isTruthy(val);
        } else {
            return primitives.argError("process-kill", "unknown option '{s}'", .{opt});
        }
    }

    // Never re-signal a reaped pid (Python's Popen.kill contract): the
    // number may have been reused by an unrelated process. A kill after
    // reap is a quiet no-op, not an error.
    if (proc.status != null) return types.VOID;

    if (group and proc.pgid == 0) {
        return primitives.argError("process-kill", "process was not spawned with 'new-group: #t; group: would signal the parent's own process group", .{});
    }
    if (group) {
        const rc = backend.signalGroup(proc, sig);
        if (rc != 0) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            return raiseProcessError(gc, "cannot signal process group", types.FALSE, rc);
        }
        return types.VOID;
    }
    const rc = backend.signalOne(proc, sig);
    if (rc != 0) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return raiseProcessError(gc, "cannot signal process", args[0], rc);
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// process-timeout condition (KEP-0022 Phase 4, kaappi#2417)
// ---------------------------------------------------------------------------

/// (%raise-process-timeout argv seconds out err) — the raise half of
/// `run-process`'s `timeout:` path, kept in Zig because a typed condition
/// object cannot be built from Scheme.
///
/// The child is already killed and reaped by the time this runs, so the
/// condition is the only surviving route to what it produced: the partial
/// output rides `uncaught_reason` as a `(stdout . stderr)` pair. Irritants
/// carry `(argv seconds)` — the two small things a printed, uncaught
/// timeout should say — and never the output itself.
fn raiseProcessTimeoutFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant

    var reason = gc.allocPair(args[2], args[3]) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&reason);
    var irritants = gc.makeList(&.{ args[0], args[1] }) catch {
        gc.popRoot();
        return PrimitiveError.OutOfMemory;
    };
    gc.pushRoot(&irritants);
    const msg = gc.allocString("run-process: timed out") catch {
        gc.popRoot();
        gc.popRoot();
        return PrimitiveError.OutOfMemory;
    };
    // allocErrorObject roots its own Value arguments, so `msg` needs no
    // root of its own; `reason` and `irritants` do, and are popped strictly
    // LIFO right after the last allocation that could collect.
    const err_val = gc.allocErrorObject(msg, irritants) catch {
        gc.popRoot();
        gc.popRoot();
        return PrimitiveError.OutOfMemory;
    };
    gc.popRoot();
    gc.popRoot();
    const err = types.toObject(err_val).as(types.ErrorObject);
    err.error_type = .process_timeout;
    err.uncaught_reason = reason;
    vm.current_exception = err_val;
    return PrimitiveError.ExceptionRaised;
}

fn processTimeoutP(args: []const Value) PrimitiveError!Value {
    return if (srfi18.isErrorOfType(args[0], .process_timeout)) types.TRUE else types.FALSE;
}

fn processTimeoutStdout(args: []const Value) PrimitiveError!Value {
    if (!srfi18.isErrorOfType(args[0], .process_timeout))
        return primitives.typeError("process-timeout-stdout", "process-timeout condition", args[0]);
    return types.car(types.toObject(args[0]).as(types.ErrorObject).uncaught_reason);
}

fn processTimeoutStderr(args: []const Value) PrimitiveError!Value {
    if (!srfi18.isErrorOfType(args[0], .process_timeout))
        return primitives.typeError("process-timeout-stderr", "process-timeout condition", args[0]);
    return types.cdr(types.toObject(args[0]).as(types.ErrorObject).uncaught_reason);
}

fn processEnvironment(_: []const Value) PrimitiveError!Value {
    // Same alist shape as (get-environment-variables) — (name . value)
    // string pairs — so `env:` replace-wholesale composes with copy-and-
    // extend: (append (process-environment) (list (cons "FOO" "bar"))).
    return primitives_r7rs.getEnvironmentAlist();
}

// ---------------------------------------------------------------------------
// Specs
// ---------------------------------------------------------------------------

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "spawn-process", .func = &spawnProcessFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "%process-spawn", .func = &processSpawnRawFn, .arity = .{ .exact = 7 }, .libs = primitives.INTERNAL, .sandbox = false, .wasm = false },
    .{ .name = "process?", .func = &processP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-pid", .func = &processPid, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-group", .func = &processGroup, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-stdin", .func = &processStdin, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-stdout", .func = &processStdout, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-stderr", .func = &processStderr, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-status", .func = &processStatus, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-wait", .func = &processWait, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-kill", .func = &processKill, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-environment", .func = &processEnvironment, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    // Phase 4 (kaappi#2417). `run-process` is Scheme source (`run_process_src`
    // below) installed over this stub by vm_bootstrap.install: its whole job
    // is to drive three sibling fibers through the dispatch loop, which a
    // native frame cannot do.
    .{ .name = "run-process", .func = primitives.bootstrapStub("run-process"), .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "%raise-process-timeout", .func = &raiseProcessTimeoutFn, .arity = .{ .exact = 4 }, .libs = primitives.INTERNAL, .sandbox = false, .wasm = false },
    .{ .name = "process-timeout?", .func = &processTimeoutP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-timeout-stdout", .func = &processTimeoutStdout, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-timeout-stderr", .func = &processTimeoutStderr, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
};

// ---------------------------------------------------------------------------
// run-process (KEP-0022 Phase 4, kaappi#2417)
// ---------------------------------------------------------------------------

/// The Scheme body behind the `run-process` bootstrap stub above, installed
/// by `vm_bootstrap.install` (which skips it on WASM, where none of the
/// names it captures is registered).
///
/// Scheme, not Zig, because the whole procedure is fiber choreography:
/// stdin is fed and both pipes are drained by sibling fibers *while*
/// `process-wait` parks, which is the fiber-native answer to the classic
/// "write to stdin, read stdout, deadlock" bug that Python's
/// `communicate()` exists to work around. Spawning and joining fibers is
/// dispatch-loop work; a native frame cannot do it.
///
/// The `let`-captured dependencies follow the vm_bootstrap discipline: a
/// later top-level redefinition of `car` or `process-wait` must not change
/// what `run-process` does.
pub const run_process_src =
    \\(define run-process
    \\  (let ((%process-spawn %process-spawn)
    \\        (%raise-process-timeout %raise-process-timeout)
    \\        (process-stdin process-stdin)
    \\        (process-stdout process-stdout)
    \\        (process-stderr process-stderr)
    \\        (process-group process-group)
    \\        (process-wait process-wait)
    \\        (process-kill process-kill)
    \\        (spawn spawn)
    \\        (fiber-join fiber-join)
    \\        (read-bytevector read-bytevector)
    \\        (write-bytevector write-bytevector)
    \\        (open-output-bytevector open-output-bytevector)
    \\        (get-output-bytevector get-output-bytevector)
    \\        (utf8->string utf8->string)
    \\        (string->utf8 string->utf8)
    \\        (flush-output-port flush-output-port)
    \\        (close-port close-port)
    \\        (eof-object? eof-object?)
    \\        (bytevector? bytevector?)
    \\        (string? string?)
    \\        (call/cc call-with-current-continuation)
    \\        (with-exception-handler with-exception-handler)
    \\        (values values) (error error) (eq? eq?) (not not)
    \\        (null? null?) (pair? pair?) (car car) (cdr cdr))
    \\    (lambda (argv . opts)
    \\      ;; `guard` is unavailable here: its desugaring reaches %unwind-to-escape,
    \\      ;; which vm_bootstrap.install purges from globals right after evaluating
    \\      ;; this definition. call/cc + with-exception-handler is the same escape
    \\      ;; with no macro underneath.
    \\      (define (quietly thunk)
    \\        (call/cc (lambda (k) (with-exception-handler (lambda (e) (k #f)) thunk))))
    \\      ;; One drain fiber per pipe, each appending into its own bytevector
    \\      ;; sink. The sink -- not the fiber's return value -- is what holds the
    \\      ;; output, so a timeout can report the partial bytes without the fiber
    \\      ;; having finished.
    \\      (define (drain-into port sink)
    \\        (let loop ()
    \\          (let ((chunk (read-bytevector 65536 port)))
    \\            (if (eof-object? chunk)
    \\                #t
    \\                (begin (write-bytevector chunk sink) (loop))))))
    \\      (define (harvest sink port want-bytes)
    \\        (quietly (lambda () (close-port port)))
    \\        (let ((bytes (get-output-bytevector sink)))
    \\          (if want-bytes bytes (utf8->string bytes))))
    \\      (define (go input timeout output directory env new-group)
    \\        (let* ((want-bytes
    \\                (cond ((eq? output 'bytevector) #t)
    \\                      ((eq? output 'string) #f)
    \\                      (else (error "run-process: output: expects 'string or 'bytevector" output))))
    \\               (fed (cond ((not input) #f)
    \\                          ((string? input) (string->utf8 input))
    \\                          ((bytevector? input) input)
    \\                          (else (error "run-process: input: expects a string or a bytevector" input))))
    \\               ;; A timeout has to be able to kill the whole tree: the
    \\               ;; group kill is what reaches a grandchild, and a grandchild
    \\               ;; holding the pipe is what would otherwise keep the drains
    \\               ;; from ever reaching EOF. So `timeout:` implies
    \\               ;; `new-group: #t`, and an explicit #f alongside it is
    \\               ;; refused rather than silently unbounded -- process-kill
    \\               ;; also refuses 'group: on a child sharing our own group, so
    \\               ;; the combination cannot deliver the bound it promises.
    \\               (grouped (cond ((eq? new-group 'unset) (if timeout #t #f))
    \\                              ((and timeout (not new-group))
    \\                               (error "run-process: timeout: needs new-group: #t -- a child-only kill cannot reach a grandchild holding the pipes, so the timeout could not be bounded" argv))
    \\                              (else new-group)))
    \\               (p (%process-spawn argv (if fed 'pipe 'null) 'pipe 'pipe
    \\                                  directory env grouped))
    \\               (out-port (process-stdout p))
    \\               (err-port (process-stderr p))
    \\               (in-port (process-stdin p))
    \\               (out-sink (open-output-bytevector))
    \\               (err-sink (open-output-bytevector))
    \\               ;; Spawned before the wait, so all three run while it parks:
    \\               ;; this is the deadlock Python's communicate() exists to avoid,
    \\               ;; answered with fibers instead of threads.
    \\               (feeder (if in-port
    \\                           (spawn (lambda ()
    \\                                    ;; A child that exits without reading gives
    \\                                    ;; the write EPIPE. That is a verdict the
    \\                                    ;; exit status already carries, not an
    \\                                    ;; error of ours -- Python swallows the
    \\                                    ;; same BrokenPipeError in communicate().
    \\                                    (quietly (lambda ()
    \\                                               (write-bytevector fed in-port)
    \\                                               (flush-output-port in-port)))
    \\                                    (quietly (lambda () (close-port in-port)))))
    \\                           #f))
    \\               (out-fiber (spawn (lambda () (drain-into out-port out-sink))))
    \\               (err-fiber (spawn (lambda () (drain-into err-port err-sink))))
    \\               (status (if timeout (process-wait p 'timeout: timeout) (process-wait p))))
    \\          (if (and timeout (not status))
    \\              (begin
    \\                ;; SIGKILL, not SIGTERM: `timeout:` is a bound, and a child
    \\                ;; that ignores SIGTERM would make it a suggestion (Python's
    \\                ;; run() kills for the same reason). Always the group form --
    \\                ;; `grouped` is #t on every path that reaches here -- since
    \\                ;; that is what reaches a grandchild holding the same pipe,
    \\                ;; and so what lets the drains below reach EOF at all.
    \\                (process-kill p 'signal: 9 'group: #t)
    \\                (process-wait p)
    \\                (quietly (lambda () (fiber-join out-fiber)))
    \\                (quietly (lambda () (fiber-join err-fiber)))
    \\                (if feeder (quietly (lambda () (fiber-join feeder))))
    \\                (%raise-process-timeout
    \\                 argv timeout
    \\                 (harvest out-sink out-port want-bytes)
    \\                 (harvest err-sink err-port want-bytes)))
    \\              (begin
    \\                ;; No `quietly` here: a read error on a pipe is this call's
    \\                ;; failure and must reach the caller.
    \\                (fiber-join out-fiber)
    \\                (fiber-join err-fiber)
    \\                (if feeder (quietly (lambda () (fiber-join feeder))))
    \\                (values status
    \\                        (harvest out-sink out-port want-bytes)
    \\                        (harvest err-sink err-port want-bytes))))))
    \\      (let loop ((o opts) (input #f) (timeout #f) (output 'string)
    \\                 (directory #f) (env #f) (new-group 'unset))
    \\        (cond
    \\         ((null? o) (go input timeout output directory env new-group))
    \\         ((not (pair? o)) (error "run-process: improper option list" opts))
    \\         ((not (pair? (cdr o))) (error "run-process: option has no value" (car o)))
    \\         (else
    \\          (let ((k (car o)) (v (car (cdr o))) (rest (cdr (cdr o))))
    \\            (cond
    \\             ((eq? k 'input:) (loop rest v timeout output directory env new-group))
    \\             ((eq? k 'timeout:) (loop rest input v output directory env new-group))
    \\             ((eq? k 'output:) (loop rest input timeout v directory env new-group))
    \\             ((eq? k 'directory:) (loop rest input timeout output v env new-group))
    \\             ((eq? k 'env:) (loop rest input timeout output directory v new-group))
    \\             ((eq? k 'new-group:) (loop rest input timeout output directory env (if v #t #f)))
    \\             (else (error "run-process: unknown option" k))))))))))
;
