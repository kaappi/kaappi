//! `(kaappi process)` primitives — KEP-0022 Phase 1 (POSIX).
//!
//! Spawn-based subprocess support: `posix_spawnp` with redirections expressed
//! as `posix_spawn_file_actions_t` entries, pipe parent-ends wrapped as
//! ordinary fd ports on the reactor-integrated path (via
//! `primitives_io.makeFdPort`, the constructor `fd->port` shares), a blocking
//! `process-wait`, and `process-kill` that never re-signals a reaped pid.
//! There is no fork anywhere and no pre-exec hook; every knob between spawn
//! and exec is a named option.
//!
//! Phase boundaries: reactor child-exit readiness, fiber-parking
//! `process-wait` with timeouts, and group-kill tests are Phase 2; Windows
//! (CreateProcess + Job Objects) is Phase 3. On those targets this module is
//! not registered at all, so `(library (kaappi process))` gates false.
//!
//! POSIX-only libc surface lives here, naked: this file is referenced by
//! `primitives.all_specs` only on POSIX targets, so none of it is analyzed
//! on Windows or WASM.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const primitives_io = @import("primitives_io.zig");
const primitives_r7rs = @import("primitives_r7rs.zig");

const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;
const GC = memory.GC;

// ---------------------------------------------------------------------------
// libc: posix_spawn surface
// ---------------------------------------------------------------------------

const spawn_c = struct {
    pub const FileActionsPtr = *opaque {};
    pub const AttrPtr = *opaque {};

    pub extern "c" fn posix_spawn_file_actions_init(actions: *FileActionsPtr) c_int;
    pub extern "c" fn posix_spawn_file_actions_destroy(actions: *FileActionsPtr) c_int;
    pub extern "c" fn posix_spawn_file_actions_adddup2(actions: *FileActionsPtr, filedes: c_int, newfiledes: c_int) c_int;
    pub extern "c" fn posix_spawn_file_actions_addopen(actions: *FileActionsPtr, filedes: c_int, path: [*:0]const u8, oflag: c_int, mode: c_uint) c_int;
    pub extern "c" fn posix_spawn_file_actions_addclose(actions: *FileActionsPtr, filedes: c_int) c_int;
    pub extern "c" fn posix_spawnp(
        pid: *c_int,
        file: [*:0]const u8,
        actions: ?*const FileActionsPtr,
        attrp: ?*const AttrPtr,
        argv: [*:null]const ?[*:0]const u8,
        envp: [*:null]const ?[*:0]const u8,
    ) c_int;
    /// OpenBSD only (see the pre-flight in spawnImpl): its userland,
    /// vfork-based posix_spawn has no channel to report the child's exec
    /// failure, so spawning a missing program "succeeds" and the child
    /// exits 127 — POSIX permits that, but every other target reports
    /// ENOENT synchronously and the catchable-file-error contract should
    /// not be platform lottery for the common case.
    pub const spawn_cannot_report_exec_failure = builtin.os.tag == .openbsd;
    pub extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;

    pub extern "c" fn posix_spawnattr_init(attr: *AttrPtr) c_int;
    pub extern "c" fn posix_spawnattr_destroy(attr: *AttrPtr) c_int;
    pub extern "c" fn posix_spawnattr_setflags(attr: *AttrPtr, flags: c_short) c_int;
    pub extern "c" fn posix_spawnattr_setpgroup(attr: *AttrPtr, pgroup: c_int) c_int;
    pub extern "c" fn posix_spawnattr_setsigdefault(attr: *AttrPtr, sigset: *const std.c.sigset_t) c_int;

    /// The spawn attr/file-actions types are `*opaque` in every libc binding
    /// (macOS and FreeBSD make them pointer types whose `_init` allocates;
    /// glibc/musl/NetBSD/OpenBSD make them value structs initialized in
    /// place). Handing both a zeroed, generously-sized aligned buffer
    /// satisfies each discipline: the pointer flavor stores its allocation
    /// in the first word, the value flavor (glibc's posix_spawnattr_t with
    /// two 128-byte sigsets is the largest at ~336 bytes) fits whole.
    const storage_bytes = 512;
    pub const Storage = extern struct {
        _buf: [storage_bytes]u8 align(16),
    };

    pub fn zeroStorage() Storage {
        return .{ ._buf = @splat(0) };
    }

    // POSIX_SPAWN_* flag bits (posix_spawnattr_setflags). POSIX names them
    // but does NOT fix their values, and they are not uniform: SETPGROUP is
    // 0x02 everywhere (0x01 is RESETIDS), but SETSIGDEF is 0x04 only on
    // macOS/glibc/musl — the BSDs (FreeBSD, and NetBSD/OpenBSD which took
    // FreeBSD's <spawn.h> layout) put SETSCHEDPARAM at 0x04 and SETSIGDEF
    // at 0x10. Using 0x04 on a BSD silently requests a scheduler-parameter
    // reset from a zeroed attr instead of the signal-default reset.
    pub const SPAWN_SETPGROUP: u16 = 0x0002;
    pub const SPAWN_SETSIGDEF: u16 = switch (builtin.os.tag) {
        .freebsd, .netbsd, .openbsd, .dragonfly => 0x0010,
        else => 0x0004, // macOS/iOS, glibc, musl
    };
    /// Apple-only: close every fd > 2 in the child regardless of CLOEXEC
    /// state, keeping only the stdio slots the file actions install. A belt
    /// over the CLOEXEC audit on macOS (glibc's addclosefrom_np needs 2.34+
    /// and musl lacks it, so on Linux the audit is the whole story). 0x4000
    /// per the SDK's sys/spawn.h; std.c.POSIX_SPAWN's packed struct agrees.
    pub const SPAWN_CLOEXEC_DEFAULT: u16 = 0x4000;
    pub const apple_cloexec_default = builtin.os.tag.isDarwin();

    /// posix_spawn_file_actions_addchdir_np exists on macOS, Linux
    /// (glibc >= 2.29, musl >= 1.1.24) and FreeBSD >= 13, but not in
    /// NetBSD's or OpenBSD's libc (verified at link time per target), so
    /// `directory:` on those two is rejected at run time with a clear
    /// message rather than an unresolved symbol at build time.
    ///
    /// The glibc floor matters concretely: the release workflow targets
    /// x86_64-linux-gnu.2.28, where the symbol is absent — referencing it
    /// unconditionally on Linux fails that link even when `directory:` is
    /// never used (kaappi#2414 review). Zig only links referenced externs,
    /// so the version gate must be comptime, mirrored by the `comptime`
    /// guard at the call site.
    pub const has_addchdir = switch (builtin.os.tag) {
        .macos, .ios, .freebsd => true,
        .linux => blk: {
            if (!builtin.target.abi.isGnu()) break :blk true; // musl >= 1.1.24 (Zig bundles newer)
            const v = builtin.target.os.versionRange().gnuLibCVersion() orelse break :blk false;
            break :blk v.order(.{ .major = 2, .minor = 29, .patch = 0 }) != .lt;
        },
        else => false,
    };
    pub extern "c" fn posix_spawn_file_actions_addchdir_np(actions: *FileActionsPtr, path: [*:0]const u8) c_int;

    /// Darwin only: under POSIX_SPAWN_CLOEXEC_DEFAULT even the stdio slots
    /// are closed unless a file action names them; addinherit_np is the
    /// action the man page prescribes for a descriptor that must survive
    /// as-is (kaappi#2442 review).
    pub extern "c" fn posix_spawn_file_actions_addinherit_np(actions: *FileActionsPtr, filedes: c_int) c_int;

    /// FreeBSD >= 13.1: close every child fd >= `from` in one action —
    /// the kernel-side equivalent of the per-fd scan, with no upper bound,
    /// so a 100k+ RLIMIT_NOFILE costs nothing (kaappi#2442 review: the
    /// scan's old 65536 cap silently exempted valid high descriptors).
    /// glibc >= 2.34 has it too, but Linux keeps the /proc-driven scan,
    /// which works on every libc and glibc floor.
    pub const has_addclosefrom = builtin.os.tag == .freebsd;
    pub extern "c" fn posix_spawn_file_actions_addclosefrom_np(actions: *FileActionsPtr, from: c_int) c_int;

    /// NetBSD only: its posix_spawn is an in-kernel syscall whose *child*
    /// completes the exec after the parent's call has already returned — and
    /// a signal posted to the child before that exec has fully finished is
    /// dropped outright (measured on NetBSD 10.1: 5 of 40 immediate SIGTERMs
    /// to a spawned `sleep` were lost and the children ran to completion —
    /// kaappi#2414, the process-kill breakage both prior attempts hit).
    /// Every other target has no window by construction: FreeBSD/OpenBSD/
    /// glibc/musl spawn with vfork semantics (the parent resumes only after
    /// the exec), and macOS's spawn is atomic in-kernel.
    ///
    /// The barrier is kqueue's NOTE_EXEC — the kernel's own "exec completed"
    /// notification, raised at the end of execve_runproc. A CLOEXEC-pipe
    /// EOF barrier was tried first and measured *insufficient* (8/40 kills
    /// still lost): the kernel closes close-on-exec descriptors partway
    /// through the exec, before the child's signal state is finalized, so
    /// EOF arrives inside the loss window. A kill delayed past the window
    /// (50 ms) was 0/15 lost, pinning the mechanism to exec-completion
    /// timing.
    pub const needs_exec_barrier = builtin.os.tag == .netbsd;

    /// NetBSD versions every libc symbol whose signature contains `time_t`;
    /// the modern kevent is `__kevent50` (see the same binding in
    /// reactor.zig). Declared here unconditionally but referenced only under
    /// `needs_exec_barrier`, so no other target links it.
    pub extern "c" fn __kevent50(
        kq: c_int,
        changelist: [*]const std.c.Kevent,
        nchanges: c_int,
        eventlist: [*]std.c.Kevent,
        nevents: c_int,
        timeout: ?*const std.c.timespec,
    ) c_int;
};

const SIGTERM: c_int = 15;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// A catchable `.file` error carrying errno, mirroring
/// primitives_filesystem.raiseFileErrorCode: spawn failures are the same
/// family as open failures ("program not found" vs "permission" is exactly
/// ENOENT vs EACCES), so `file-error?` and `posix-error?` see them. Pass 0
/// for rejections that never reached a syscall.
fn raiseProcessError(gc: *GC, msg_text: []const u8, irritant: Value, errno_val: c_int) PrimitiveError!Value {
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

const Redir = union(enum) {
    inherit,
    pipe,
    null_sink,
    /// stderr only: dup2(1, 2) in the child.
    merge_stdout,
    /// Child gets this descriptor (from an fd-backed port); no pipe is
    /// created and the accessor returns #f.
    fd: platform.fd_t,
};

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
        // rather than corrupt (kaappi#2414 review).
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
fn sweepUnreaped(gc: *GC) void {
    var i: usize = 0;
    while (i < gc.unreaped_processes.items.len) {
        const proc = gc.unreaped_processes.items[i];
        var st: c_int = 0;
        const r = platform.waitPid(proc.pid, &st, platform.WNOHANG);
        if (r == proc.pid) {
            proc.status = @bitCast(@as(u32, @bitCast(st)));
            _ = gc.unreaped_processes.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

// ---------------------------------------------------------------------------
// %process-spawn / spawn-process
// ---------------------------------------------------------------------------

const SpawnConfig = struct {
    argv: []const Value,
    stdin: Redir = .inherit,
    stdout: Redir = .inherit,
    stderr: Redir = .inherit,
    /// null = inherit the current environment wholesale (posix_spawnp env
    /// argument = std.c.environ). An alist (including the empty list)
    /// replaces the environment wholesale — Guile/Python semantics; the
    /// copy-and-extend idiom starts from (process-environment).
    env: ?Value = null,
    directory: ?Value = null,
    new_group: bool = false,
};

/// The spawn itself. Everything GC-managed is copied or read before the
/// first allocation-free syscall section; the Process object and its ports
/// are allocated only after the child exists.
fn spawnImpl(cfg: SpawnConfig) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // Zombie sweep on the blocking spawn path (see sweepUnreaped).
    sweepUnreaped(gc);

    // -- argv, env, cwd into Zig-owned memory (an arena freed on every exit
    // path below): nothing GC-managed may cross the spawn section.
    var arena = std.heap.ArenaAllocator.init(gc.allocator);
    defer arena.deinit();
    const arena_al = arena.allocator();

    const argv = try copyArgv(arena_al, cfg.argv);

    var env_block: ?[*:null]const ?[*:0]const u8 = null;
    if (cfg.env) |env_val| {
        env_block = try buildEnvp(arena_al, env_val);
    }

    var directory_z: ?[*:0]const u8 = null;
    if (cfg.directory) |dir_val| {
        if (!types.isString(dir_val)) return primitives.typeError("spawn-process", "string", dir_val);
        const dir = types.toObject(dir_val).as(types.SchemeString);
        if (!spawn_c.has_addchdir)
            return primitives.argError("spawn-process", "directory: is not supported on this platform", .{});
        directory_z = try dupeZChecked("spawn-process", arena_al, dir.data[0..dir.len], "directory: path");
    }

    // -- pipes. Cleanup discipline: every fd this function creates lives in
    // one of the slots below, and the single defer closes whatever is still
    // >= 0 on ANY exit path — success included. Ownership transfer is
    // recorded by writing -1 into the slot: the child ends after their
    // explicit post-spawn close, each parent end once a Port owns it, the
    // staged redirect duplicates never (the parent must always release
    // them). Nothing is disarmed wholesale, so an OOM between the spawn and
    // the last port allocation cannot leak a descriptor (kaappi#2442
    // review).
    var stdin_pipe: [2]platform.fd_t = .{ -1, -1 }; // [0] child read end, [1] parent write end
    var stdout_pipe: [2]platform.fd_t = .{ -1, -1 };
    var stderr_pipe: [2]platform.fd_t = .{ -1, -1 };
    var staged_fds: [3]platform.fd_t = .{ -1, -1, -1 }; // parent-side dups of low redirect sources
    defer {
        closePipePair(&stdin_pipe);
        closePipePair(&stdout_pipe);
        closePipePair(&stderr_pipe);
        for (&staged_fds) |*sfd| {
            if (sfd.* >= 0) _ = platform.close(sfd.*);
            sfd.* = -1;
        }
    }
    if (cfg.stdin == .pipe and pipeWithFdRetry(gc, &stdin_pipe) != 0)
        return raiseProcessError(gc, "cannot create stdin pipe", types.FALSE, std.c._errno().*);
    if (cfg.stdout == .pipe and pipeWithFdRetry(gc, &stdout_pipe) != 0)
        return raiseProcessError(gc, "cannot create stdout pipe", types.FALSE, std.c._errno().*);
    if (cfg.stderr == .pipe and pipeWithFdRetry(gc, &stderr_pipe) != 0)
        return raiseProcessError(gc, "cannot create stderr pipe", types.FALSE, std.c._errno().*);

    // A launcher that closed a standard descriptor makes pipe(2) hand back
    // 0, 1, or 2 — and a pipe end living IN a stdio slot corrupts the file
    // actions (dup2(0,0) then close(0) destroys the stream it just
    // installed; a parent end in 0..2 collides with the port close
    // discipline). Lift every pipe end above the stdio range before any
    // action names it (kaappi#2442 review).
    try normalizePipeAboveStdio(gc, &stdin_pipe);
    try normalizePipeAboveStdio(gc, &stdout_pipe);
    try normalizePipeAboveStdio(gc, &stderr_pipe);

    // Caller-port redirect sources in 0..2 must be staged into fds >= 3:
    // the file actions run sequentially in the child, so a later action
    // naming a low source reads whatever an earlier dup2 just installed
    // there — `stdout: (current-error-port) stderr: (current-output-port)`
    // queued dup2(2,1); dup2(1,2) and sent BOTH streams to the original
    // stderr instead of swapping (kaappi#2442 review). The staged copies
    // are parent-side CLOEXEC dups: actions reference them, exec drops
    // them in the child, and the defer above releases the parent's copies.
    var redirs = [3]Redir{ cfg.stdin, cfg.stdout, cfg.stderr };
    for (&redirs, 0..) |*r, slot| {
        if (r.* != .fd) continue;
        if (r.*.fd > 2) continue;
        // A source already sitting in its own destination slot needs no
        // stage: dup2(slot, slot) cannot collide with any earlier action,
        // and it still names the descriptor for Darwin's CLOEXEC_DEFAULT —
        // so `stdout: (current-output-port)` (explicit inheritance) must
        // not fail just because the fd table is full (kaappi#2442 review).
        if (r.*.fd == @as(platform.fd_t, @intCast(slot))) continue;
        const staged = platform.dupCloexecAtLeast(r.*.fd, 3);
        if (staged < 0)
            return raiseProcessError(gc, "cannot stage redirection descriptor", types.FALSE, std.c._errno().*);
        staged_fds[slot] = staged;
        r.* = .{ .fd = staged };
    }

    // -- file actions + attrs. Both initializers can fail (ENOMEM on the
    // pointer-backed libcs), and their destroy must run only on a
    // successfully initialized object (kaappi#2442 review).
    var actions_storage = spawn_c.zeroStorage();
    const actions: *spawn_c.FileActionsPtr = @ptrCast(&actions_storage);
    {
        // FreeBSD's initializers return -1 with the error in errno (unlike
        // the errno-returning convention everywhere else in this API), so a
        // negative result is normalized before it can masquerade as a bogus
        // error number (kaappi#2442 review).
        var rc = spawn_c.posix_spawn_file_actions_init(actions);
        if (rc < 0) rc = std.c._errno().*;
        if (rc != 0) return spawnSetupError(gc, rc);
    }
    defer _ = spawn_c.posix_spawn_file_actions_destroy(actions);

    const O_RDONLY: c_int = 0;
    const O_WRONLY: c_int = 1;
    const null_z: [*:0]const u8 = "/dev/null";
    const child_pipe_ends = [3]platform.fd_t{ stdin_pipe[0], stdout_pipe[1], stderr_pipe[1] };
    const slot_oflag = [3]c_int{ O_RDONLY, O_WRONLY, O_WRONLY };

    // Slot actions, stdin/stdout/stderr in order — stderr last, so the
    // 'stdout merge duplicates the child's final slot-1 descriptor,
    // whatever installed it. `redirs` (not cfg) carries the staged sources.
    for (redirs, 0..) |redir, slot_usize| {
        const slot: c_int = @intCast(slot_usize);
        switch (redir) {
            .inherit => {
                // Darwin's CLOEXEC_DEFAULT closes even the stdio slots
                // unless a file action names them — a plain 'inherit spawn
                // lost all three streams (kaappi#2442 review; the man page
                // prescribes addinherit_np for exactly this). A slot the
                // parent itself has closed is skipped: the child correctly
                // sees it closed, and an addinherit on a bad fd would fail
                // the whole spawn.
                if (comptime spawn_c.apple_cloexec_default) {
                    if (platform.getFdFlags(slot) >= 0) {
                        const rc = spawn_c.posix_spawn_file_actions_addinherit_np(actions, slot);
                        if (rc != 0) return spawnSetupError(gc, rc);
                    }
                }
            },
            .pipe => {
                const child_end = child_pipe_ends[slot_usize];
                var rc = spawn_c.posix_spawn_file_actions_adddup2(actions, child_end, slot);
                if (rc == 0) rc = spawn_c.posix_spawn_file_actions_addclose(actions, child_end);
                if (rc != 0) return spawnSetupError(gc, rc);
            },
            .null_sink => {
                const rc = spawn_c.posix_spawn_file_actions_addopen(actions, slot, null_z, slot_oflag[slot_usize], 0o666);
                if (rc != 0) return spawnSetupError(gc, rc);
            },
            .fd => |fd| {
                const rc = spawn_c.posix_spawn_file_actions_adddup2(actions, fd, slot);
                if (rc != 0) return spawnSetupError(gc, rc);
            },
            .merge_stdout => {
                if (slot != 2)
                    return primitives.argError("spawn-process", "'stdout is a stderr-only redirection spec", .{});
                const rc = spawn_c.posix_spawn_file_actions_adddup2(actions, 1, 2);
                if (rc != 0) return spawnSetupError(gc, rc);
            },
        }
    }
    // Comptime gate, not just the run-time one above: the extern is absent
    // from NetBSD/OpenBSD libc, so the call itself must not be analyzed
    // there (Zig only links referenced externs).
    if (comptime spawn_c.has_addchdir) {
        if (directory_z) |dir| {
            const rc = spawn_c.posix_spawn_file_actions_addchdir_np(actions, dir);
            if (rc != 0) return spawnSetupError(gc, rc);
        }
    }

    // Close-by-default (KEP-0022): the child must inherit only the three
    // stdio slots. CLOEXEC on every Kaappi-opened fd covers Kaappi's own
    // descriptors, but a descriptor Kaappi itself INHERITED from its
    // launcher (`kaappi 9</dev/null prog.scm`) or acquired through FFI has
    // no such guarantee and would otherwise pass into every child —
    // leaking sockets and lock files, and holding unrelated pipes open
    // past EOF (kaappi#2414 review). On macOS POSIX_SPAWN_CLOEXEC_DEFAULT
    // (below) closes everything wholesale; everywhere else, enumerate the
    // open non-CLOEXEC fds and add an explicit close action for each.
    // These actions run AFTER the dup2/open actions above, so a caller
    // redirect port's own fd is closed only after its slot copy exists.
    if (comptime !spawn_c.apple_cloexec_default) {
        try addInheritedFdCloses(gc, actions);
    }

    var attr_storage = spawn_c.zeroStorage();
    const attr: *spawn_c.AttrPtr = @ptrCast(&attr_storage);
    {
        // Same FreeBSD -1/errno normalization as the file-actions init.
        var rc = spawn_c.posix_spawnattr_init(attr);
        if (rc < 0) rc = std.c._errno().*;
        if (rc != 0) return spawnSetupError(gc, rc);
    }
    defer _ = spawn_c.posix_spawnattr_destroy(attr);

    var flags: u16 = 0;
    if (cfg.new_group) {
        // pgroup 0 = the child becomes its own group leader
        // (setpgid(child, 0) semantics), so pgid == pid after spawn.
        const rc = spawn_c.posix_spawnattr_setpgroup(attr, 0);
        if (rc != 0) return spawnSetupError(gc, rc);
        flags |= spawn_c.SPAWN_SETPGROUP;
    }
    {
        // Reset SIGPIPE to its default in the child: the parent runs with
        // SIG_IGN (VM.init, KEP-0022) and ignored dispositions survive exec,
        // which would silently change the behavior of children that rely on
        // dying on EPIPE (e.g. `yes | head` inside a shell pipeline). The
        // same restore Python's subprocess performs by default. The set is
        // built with Zig's own sigset helpers, not libc's sigemptyset/
        // sigaddset externs — NetBSD's sigset accessors are macros over a
        // renamed ABI, so the plain symbols are not portably linkable.
        var sigset = std.posix.sigemptyset();
        std.posix.sigaddset(&sigset, std.posix.SIG.PIPE);
        const rc = spawn_c.posix_spawnattr_setsigdefault(attr, &sigset);
        if (rc != 0) return spawnSetupError(gc, rc);
        flags |= spawn_c.SPAWN_SETSIGDEF;
    }
    if (spawn_c.apple_cloexec_default) flags |= spawn_c.SPAWN_CLOEXEC_DEFAULT;
    if (flags != 0) {
        const rc = spawn_c.posix_spawnattr_setflags(attr, @bitCast(flags));
        if (rc != 0) return spawnSetupError(gc, rc);
    }

    // OpenBSD pre-flight (see spawn_cannot_report_exec_failure): for a
    // slash-containing program path — the case with exactly one candidate
    // file — probe it with access(X_OK) so "no such program" raises the
    // same errno-carrying file-error as on every other platform. A bare
    // name goes through posix_spawnp's PATH search and keeps the
    // POSIX-sanctioned exit-127 fallback; the probe is advisory (TOCTOU
    // races simply fall back to that same behavior).
    if (comptime spawn_c.spawn_cannot_report_exec_failure) {
        const prog = argv[0].?;
        if (std.mem.indexOfScalar(u8, std.mem.span(prog), '/') != null) {
            const X_OK: c_int = 1;
            if (spawn_c.access(prog, X_OK) != 0)
                return raiseProcessError(gc, "cannot spawn process", cfg.argv[0], std.c._errno().*);
        }
    }

    // -- spawn
    var pid: c_int = -1;
    const envp: [*:null]const ?[*:0]const u8 = env_block orelse @ptrCast(std.c.environ);
    var spawn_rc: c_int = 0;
    {
        // A child-thread VM blocking in the vfork-style spawn (which waits
        // through the exec and its filesystem lookups) — or in the NetBSD
        // exec barrier — never reaches the dispatch-loop safepoint, so a
        // concurrent parent collection would spin in markLiveChildRoots
        // (the same #1933 shape process-wait already handles; kaappi#2442
        // review). Publish the VM as markable-in-native for the syscall
        // stretch, restoring .running before anything below allocates.
        const spawn_vm: ?*vm_mod.VM = if (vm_mod.vm_instance) |vm|
            (if (!vm.owns_globals) vm else null)
        else
            null;
        if (spawn_vm) |vm| vm.setCollectionInNative();
        defer if (spawn_vm) |vm| vm.setCollectionRunning();
        spawn_rc = spawn_c.posix_spawnp(&pid, argv[0].?, actions, attr, argv, envp);
        // Exec barrier (NetBSD; see needs_exec_barrier): block until the
        // kernel reports the child's exec completed (or the child died), so
        // the child is signalable from the moment spawn-process returns.
        // Without this, a process-kill issued promptly after spawn is
        // silently dropped.
        if (comptime spawn_c.needs_exec_barrier) {
            if (spawn_rc == 0) execBarrierWait(pid);
        }
    }
    if (spawn_rc != 0) {
        // posix_spawn returns the errno itself, not -1. ENOENT is the common
        // case (program not on PATH); the errno rides the condition so
        // posix-error-name reports it precisely. The function-wide defer
        // closes the pipes and staged fds; the destroy defers release
        // actions/attr.
        return raiseProcessError(gc, "cannot spawn process", cfg.argv[0], spawn_rc);
    }

    // The child owns the child ends now; the parent's copies must go
    // (recorded as -1 so the cleanup defer never double-closes them).
    if (stdin_pipe[0] >= 0) _ = platform.close(stdin_pipe[0]);
    stdin_pipe[0] = -1;
    if (stdout_pipe[1] >= 0) _ = platform.close(stdout_pipe[1]);
    stdout_pipe[1] = -1;
    if (stderr_pipe[1] >= 0) _ = platform.close(stderr_pipe[1]);
    stderr_pipe[1] = -1;

    // -- Process object + parent-end ports. `proc_val` stays rooted across
    // the three port allocations; each port is stored into the Process as
    // soon as it exists so the next allocation sees it reachable. Each
    // parent end's slot is blanked as its Port takes ownership; an OOM
    // between any two steps leaves the remaining ends to the cleanup defer.
    const pgid: i32 = if (cfg.new_group) pid else 0;
    const proc = gc.allocProcess(pid, pgid) catch {
        // Nothing tracks this child (enrolment happens inside allocProcess),
        // so an unreaped survivor here is lost for good — but that needs
        // the kill itself to fail, which has no realistic path.
        _ = killAndReapFresh(pid);
        return PrimitiveError.OutOfMemory;
    };
    var proc_val = types.makePointer(&proc.header);
    gc.pushRoot(&proc_val);
    defer gc.popRoot();

    // Any failure between here and the return leaves a Process the caller
    // will never see: it would be collected, dropped from the unreaped
    // registry, and its still-running child would be permanently untracked
    // (kaappi#2442 review — the kill/reap must cover the port
    // constructions, not just allocProcess). Terminate and reap the fresh
    // child, and record the status so freeObject does not reap a reused
    // pid later.
    errdefer {
        if (killAndReapFresh(pid)) {
            proc.status = 9; // (signaled . 9): the raw wait status of SIGKILL
            removeFromUnreaped(gc, proc);
        }
        // else: keep the registry entry — the WNOHANG sweeps reap it when
        // the child does die, instead of the pid being forgotten.
    }

    if (stdin_pipe[1] >= 0) {
        const port_val = try primitives_io.makeFdPort(gc, stdin_pipe[1], false, true, "process-stdin");
        stdin_pipe[1] = -1;
        proc.stdin_port = port_val;
        gc.writeBarrier(&proc.header, port_val);
    }
    if (stdout_pipe[0] >= 0) {
        const port_val = try primitives_io.makeFdPort(gc, stdout_pipe[0], true, false, "process-stdout");
        stdout_pipe[0] = -1;
        proc.stdout_port = port_val;
        gc.writeBarrier(&proc.header, port_val);
    }
    if (stderr_pipe[0] >= 0) {
        const port_val = try primitives_io.makeFdPort(gc, stderr_pipe[0], true, false, "process-stderr");
        stderr_pipe[0] = -1;
        proc.stderr_port = port_val;
        gc.writeBarrier(&proc.header, port_val);
    }
    return proc_val;
}

/// Terminate and reap a child spawned moments ago that no caller will ever
/// be able to wait on (a post-spawn allocation failed). Returns true when
/// the child was actually reaped — the caller keeps its registry entry
/// otherwise, so the ordinary WNOHANG sweeps can finish the job later
/// rather than a pid being forgotten (kaappi#2442 review). The blocking
/// reap runs only after the SIGKILL demonstrably went out (an unchecked
/// kill followed by an unconditional wait could block on a child that was
/// never signaled), under the same markable-in-native protocol as
/// process-wait, since a child-thread VM blocking here would otherwise
/// starve a concurrent parent collection (#1933 shape). SIGKILL cannot be
/// caught, so the wait is bounded by the child's own teardown (an
/// uninterruptible-sleep child can stretch that, but never indefinitely).
fn killAndReapFresh(pid: c_int) bool {
    if (platform.procKill(pid, 9) != 0) {
        // Could not signal (already reaped elsewhere would be a bug; a
        // bizarre EPERM leaves the child running): one non-blocking probe,
        // then let the registry sweeps take over.
        var st0: c_int = 0;
        return platform.waitPid(pid, &st0, platform.WNOHANG) == pid;
    }
    const wait_vm: ?*vm_mod.VM = if (vm_mod.vm_instance) |vm|
        (if (!vm.owns_globals) vm else null)
    else
        null;
    if (wait_vm) |vm| vm.setCollectionInNative();
    defer if (wait_vm) |vm| vm.setCollectionRunning();
    var st: c_int = 0;
    while (true) {
        const r = platform.waitPid(pid, &st, 0);
        if (r == pid) return true;
        if (r < 0 and std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
        return false;
    }
}

/// Raise the errno-carrying redirection-setup error. All posix_spawn
/// file-action and attr functions RETURN the error number rather than
/// setting errno (kaappi#2442 review) — callers pass that return code here.
fn spawnSetupError(gc: *GC, rc: c_int) PrimitiveError!Value {
    return raiseProcessError(gc, "cannot set up process redirection", types.FALSE, rc);
}

/// Lift both ends of a created pipe above the stdio range (fd >= 3) via
/// F_DUPFD_CLOEXEC, closing the low originals. See the call site for why a
/// pipe end in 0..2 is unusable in the file actions.
fn normalizePipeAboveStdio(gc: *GC, fds: *[2]platform.fd_t) PrimitiveError!void {
    for (fds) |*fd| {
        if (fd.* < 0 or fd.* > 2) continue;
        const high = platform.dupCloexecAtLeast(fd.*, 3);
        if (high < 0)
            _ = try raiseProcessError(gc, "cannot relocate pipe descriptor above the stdio range", types.FALSE, std.c._errno().*);
        _ = platform.close(fd.*);
        fd.* = high;
    }
}

/// Add a close file-action for every open fd > 2 that is not close-on-exec
/// (the non-macOS half of close-by-default; see the call site). Enumeration
/// is /proc/self/fd on Linux — accurate and O(open fds) even under a huge
/// RLIMIT_NOFILE — and an fcntl(F_GETFD) probe of 3..RLIMIT_NOFILE (capped)
/// on the BSDs, whose /dev/fd entries are static device nodes that exist
/// whether or not the fd is open. Both paths re-probe F_GETFD right before
/// adding the action, so the Linux directory fd (closed by then) and any
/// CLOEXEC descriptor are skipped: exec itself closes the latter, and glibc
/// fails the whole spawn on a close action naming a closed fd.
///
/// Known window, documented and accepted for Phase 1: an fd another thread
/// opens non-CLOEXEC between this scan and the posix_spawnp call can still
/// slip through — the same race every enumerate-then-spawn implementation
/// (CPython's subprocess on platforms without close_range) accepts.
fn addInheritedFdCloses(gc: *GC, actions: *spawn_c.FileActionsPtr) PrimitiveError!void {
    if (comptime spawn_c.has_addclosefrom) {
        // One kernel-side action replaces the whole scan, with no upper
        // bound to silently exempt high descriptors. It runs after the slot
        // dup2s, so redirect sources have already been copied into 0..2;
        // closing them (and everything else >= 3) is exactly
        // close-by-default.
        const rc = spawn_c.posix_spawn_file_actions_addclosefrom_np(actions, 3);
        if (rc != 0) _ = try spawnSetupError(gc, rc);
        return;
    }
    if (comptime builtin.os.tag == .linux) {
        if (platform.DirIter.open("/proc/self/fd")) |it_state| {
            // The genuinely sparse enumeration must be collected before
            // probing: the directory's own fd is part of the listing, and
            // only closing the iterator first lets the F_GETFD re-probe in
            // closeFdIfInheritable see it as already gone.
            var fds: std.ArrayList(platform.fd_t) = .empty;
            defer fds.deinit(gc.allocator);
            var it = it_state;
            while (it.next()) |name| {
                const n = std.fmt.parseInt(platform.fd_t, name, 10) catch continue;
                fds.append(gc.allocator, n) catch {
                    it.close();
                    return PrimitiveError.OutOfMemory;
                };
            }
            it.close();
            for (fds.items) |fd| try closeFdIfInheritable(gc, actions, fd);
            return;
        }
    }
    // NetBSD/OpenBSD fallback (and Linux without /proc): probe the
    // descriptor range inline — no ArrayList (materializing the dense range
    // costs allocation for nothing) and no arbitrary cap: a valid high
    // descriptor silently exempted is a broken close-by-default guarantee
    // (kaappi#2442 review), so the scan runs to the full soft limit. The
    // targets that commonly raise RLIMIT_NOFILE into six figures (FreeBSD,
    // Linux) never reach this loop — they use addclosefrom_np and /proc
    // respectively.
    const fallback: u64 = 65536;
    const raw_limit: u64 = blk: {
        const rl = std.posix.getrlimit(.NOFILE) catch break :blk fallback;
        // rlim_t is signed on some libcs (FreeBSD's i64); a negative
        // cur (RLIM_INFINITY representations aside) means "no info".
        break :blk std.math.cast(u64, rl.cur) orelse fallback;
    };
    // Clamp to what an fd can actually number — an RLIM_INFINITY-shaped
    // soft limit must not overflow the counter (kaappi#2442 review). This
    // is not a coverage cap: no descriptor can exceed maxInt(fd_t).
    const limit: platform.fd_t = @intCast(@min(raw_limit, std.math.maxInt(platform.fd_t)));
    var fd: platform.fd_t = 3;
    while (fd < limit) : (fd += 1) {
        try closeFdIfInheritable(gc, actions, fd);
    }
}

fn closeFdIfInheritable(gc: *GC, actions: *spawn_c.FileActionsPtr, fd: platform.fd_t) PrimitiveError!void {
    const FD_CLOEXEC: c_int = 1;
    if (fd < 3) return;
    const flags = platform.getFdFlags(fd);
    if (flags < 0) return; // closed (or the enumeration dir's own fd)
    if ((flags & FD_CLOEXEC) != 0) return; // exec closes it anyway
    const rc = spawn_c.posix_spawn_file_actions_addclose(actions, fd);
    if (rc != 0) _ = try spawnSetupError(gc, rc);
}

/// NetBSD's exec barrier (see spawn_c.needs_exec_barrier): register a
/// oneshot EVFILT_PROC knote for NOTE_EXEC|NOTE_EXIT on the fresh child and
/// wait for it. NOTE_EXEC is raised at the very end of the kernel's exec
/// path, strictly after the child's signal state is final — the property the
/// CLOEXEC-pipe EOF measurably lacked. The 20 ms timeout covers the one
/// blind spot: a child that completed its exec in the microseconds before
/// the knote was registered raises no event (rare — the child needs a
/// scheduling slot first — and the fallback only ever *delays*, never
/// breaks). Registration failure (ESRCH: child already exited and reaped by
/// a concurrent sweep) just returns. Best-effort by design: no error path.
fn execBarrierWait(pid: c_int) void {
    const kq = std.c.kqueue();
    if (kq < 0) return;
    defer _ = platform.close(kq);
    var change = [1]std.c.Kevent{.{
        .ident = @intCast(pid),
        .filter = std.c.EVFILT.PROC,
        .flags = std.c.EV.ADD | std.c.EV.ONESHOT,
        .fflags = std.c.NOTE.EXEC | std.c.NOTE.EXIT,
        .data = 0,
        .udata = 0,
    }};
    var out: [1]std.c.Kevent = undefined;
    const ts: std.c.timespec = .{ .sec = 0, .nsec = 20 * std.time.ns_per_ms };
    _ = spawn_c.__kevent50(kq, &change, 1, &out, 1, &ts);
}

/// pipe(2) with the kaappi#1993 descriptor-exhaustion recovery `open` has
/// had since #2324: on EMFILE/ENFILE, force a full collection — closing the
/// descriptors held by unreachable process pipe ports — and retry once. A
/// legal program that abandons process handles faster than the GC's
/// allocation-count threshold trips must not spuriously fail at a normal
/// `ulimit -n`; the OpenBSD CI leg's low limit caught exactly that in the
/// spawn-loop rooting test. GC-safe at both call sites: everything held at
/// pipe-creation time is either arena memory or a register-rooted argument
/// Value, so a collection here frees only garbage.
fn pipeWithFdRetry(gc: *GC, fds: *[2]platform.fd_t) c_int {
    const rc = platform.pipe(fds);
    if (rc == 0 or !platform.errnoIsFdExhausted()) return rc;
    gc.collectFull();
    return platform.pipe(fds);
}

fn closePipePair(fds: *[2]platform.fd_t) void {
    if (fds[0] >= 0) _ = platform.close(fds[0]);
    if (fds[1] >= 0) _ = platform.close(fds[1]);
    fds.* = .{ -1, -1 };
}

/// Duplicate `bytes` as a NUL-terminated C string in the arena, rejecting an
/// embedded NUL. `dupeZ` alone would silently truncate at the interior NUL
/// on the OS side — the child would exec or receive something different from
/// the value the Scheme program supplied (kaappi#2414 review; CWE-626).
fn dupeZChecked(comptime proc: []const u8, arena: std.mem.Allocator, bytes: []const u8, comptime what: []const u8) PrimitiveError![*:0]const u8 {
    if (std.mem.indexOfScalar(u8, bytes, 0) != null)
        return primitives.argError(proc, what ++ " contains an embedded NUL byte", .{});
    const duped = arena.dupeZ(u8, bytes) catch return PrimitiveError.OutOfMemory;
    return duped.ptr;
}

/// Copy the argv list of strings into a null-terminated C array inside the
/// arena. argv[0] (the program, resolved via PATH by posix_spawnp) must be a
/// string and the list non-empty.
fn copyArgv(arena: std.mem.Allocator, argv_list: []const Value) PrimitiveError![*:null]const ?[*:0]const u8 {
    if (argv_list.len == 0)
        return primitives.argError("spawn-process", "argv must contain at least the program name", .{});
    const argv_z = arena.alloc(?[*:0]const u8, argv_list.len + 1) catch return PrimitiveError.OutOfMemory;
    for (argv_list, 0..) |arg, i| {
        if (!types.isString(arg)) return primitives.typeError("spawn-process", "string (argv element)", arg);
        const str = types.toObject(arg).as(types.SchemeString);
        argv_z[i] = try dupeZChecked("spawn-process", arena, str.data[0..str.len], "argv element");
    }
    argv_z[argv_list.len] = null;
    return @ptrCast(argv_z.ptr);
}

/// `env:` — an alist of (name . value) string pairs replacing the child's
/// environment wholesale (an empty list means an empty environment).
///
/// Both walks are cycle-guarded: a legal cyclic Scheme list would otherwise
/// spin forever inside this native primitive, beyond even --timeout's reach
/// (kaappi#2414 review). Entries are validated so no environment block can
/// be reinterpreted: names must be non-empty, NUL-free and '='-free, values
/// NUL-free.
fn buildEnvp(arena: std.mem.Allocator, env_val: Value) PrimitiveError![*:null]const ?[*:0]const u8 {
    var count: usize = 0;
    var cur = env_val;
    var slow = env_val;
    var step = false;
    while (cur != types.NIL) : (step = !step) {
        if (!types.isPair(cur))
            return primitives.typeError("spawn-process", "environment alist", env_val);
        const entry = types.car(cur);
        if (!types.isPair(entry))
            return primitives.typeError("spawn-process", "environment alist entry (name . value) pair", entry);
        const name = types.car(entry);
        const value = types.cdr(entry);
        if (!types.isString(name) or !types.isString(value))
            return primitives.typeError("spawn-process", "environment entry of two strings", entry);
        const name_str = types.toObject(name).as(types.SchemeString);
        if (name_str.len == 0)
            return primitives.argError("spawn-process", "environment variable name is empty", .{});
        if (std.mem.indexOfScalar(u8, name_str.data[0..name_str.len], '=') != null)
            return primitives.argError("spawn-process", "environment variable name contains '='", .{});
        count += 1;
        cur = types.cdr(cur);
        if (step) {
            slow = types.cdr(slow);
            if (cur == slow)
                return primitives.argError("spawn-process", "environment alist is cyclic", .{});
        }
    }
    const envp = arena.alloc(?[*:0]const u8, count + 1) catch return PrimitiveError.OutOfMemory;
    var i: usize = 0;
    cur = env_val;
    // Bounded by the first pass's count, so even a list mutated from another
    // OS thread mid-walk cannot run this loop away.
    while (cur != types.NIL and i < count) : (cur = types.cdr(cur)) {
        const entry = types.car(cur);
        const name = types.toObject(types.car(entry)).as(types.SchemeString);
        const value = types.toObject(types.cdr(entry)).as(types.SchemeString);
        const name_bytes = name.data[0..name.len];
        const value_bytes = value.data[0..value.len];
        if (std.mem.indexOfScalar(u8, name_bytes, 0) != null or
            std.mem.indexOfScalar(u8, value_bytes, 0) != null)
            return primitives.argError("spawn-process", "environment entry contains an embedded NUL byte", .{});
        const joined = std.fmt.allocPrintSentinel(arena, "{s}={s}", .{ name_bytes, value_bytes }, 0) catch return PrimitiveError.OutOfMemory;
        envp[i] = joined.ptr;
        i += 1;
    }
    envp[i] = null;
    return @ptrCast(envp.ptr);
}

/// Collect an argv list of Values for SpawnConfig. The Values are rooted by
/// the caller's register file (they are args), so plain ArrayList storage is
/// GC-safe; the strings themselves are copied into the spawn arena later.
/// Cycle-guarded like buildEnvp: a cyclic argv must be an error, not an
/// unbounded native-side loop.
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
    return types.makeFixnum(proc.pid);
}

fn processGroup(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-group", args[0]);
    return if (proc.pgid != 0) types.makeFixnum(proc.pgid) else types.FALSE;
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
    var st: c_int = 0;
    if (platform.waitPid(proc.pid, &st, platform.WNOHANG) == proc.pid) {
        proc.status = @bitCast(st);
        removeFromUnreaped(gc, proc);
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

fn processWait(args: []const Value) PrimitiveError!Value {
    const proc = try expectProcess("process-wait", args[0]);
    if (args.len > 1) {
        // 'timeout: parks a fiber against the reactor — Phase 2 (KEP-0022
        // implementation plan). Reject it loudly here so nobody ships a
        // busy-wait by accident.
        if (types.isSymbol(args[1]) and std.mem.eql(u8, types.symbolName(args[1]), "timeout:")) {
            return primitives.argError("process-wait", "timeout: arrives with the reactor-based wait (KEP-0022 Phase 2)", .{});
        }
        return primitives.argError("process-wait", "unknown option", .{});
    }

    // Already reaped (possibly by an earlier wait, a sweep, or both): the
    // stored status is the answer.
    if (proc.status) |st| {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
    }

    // Sweep first: a prior spawn/wait sweep may already hold our exit, and
    // this is the KEP's zombie-discipline hook on the blocking wait path.
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    sweepUnreaped(gc);
    if (proc.status) |st| {
        return types.decodeWaitStatus(gc, st) catch PrimitiveError.OutOfMemory;
    }

    // Blocking reap. Phase 1 semantics: no scheduler-awareness — a fiber
    // that waits parks the whole OS thread (Phase 2 makes this park only the
    // fiber via reactor child-exit readiness). EINTR retries; any other
    // failure is a real waitpid error (an ECHILD here would mean something
    // outside Kaappi reaped our specific child).
    var st: c_int = 0;
    var wait_errno: c_int = 0;
    var reaped = false;
    {
        // A child-thread VM blocking in waitpid never reaches the dispatch-
        // loop safepoint, so a concurrent parent collection would spin in
        // markLiveChildRoots for the child's whole wait (#1933 shape;
        // kaappi#2414 review). The frames/registers are stable for the
        // duration of the syscall, so publish the VM as markable-in-native —
        // and restore .running before anything below can allocate (the
        // collector must never mark concurrently with a mutating VM).
        const wait_vm: ?*vm_mod.VM = if (vm_mod.vm_instance) |vm|
            (if (!vm.owns_globals) vm else null)
        else
            null;
        if (wait_vm) |vm| vm.setCollectionInNative();
        defer if (wait_vm) |vm| vm.setCollectionRunning();
        while (true) {
            const r = platform.waitPid(proc.pid, &st, 0);
            if (r == proc.pid) {
                reaped = true;
                break;
            }
            if (r < 0) {
                wait_errno = std.c._errno().*;
                const eintr: c_int = @intFromEnum(std.c.E.INTR);
                if (wait_errno == eintr) continue;
                break;
            }
        }
    }
    if (!reaped)
        return raiseProcessError(gc, "cannot wait for process", types.FALSE, wait_errno);
    const raw: u32 = @bitCast(st);
    proc.status = raw;
    removeFromUnreaped(gc, proc);
    return types.decodeWaitStatus(gc, raw) catch PrimitiveError.OutOfMemory;
}

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
        // ESRCH right after spawn is almost always the SETPGROUP race, not
        // "already dead": POSIX_SPAWN_SETPGROUP's setpgid runs in the child
        // just before its exec, and the parent's posix_spawn return does
        // not synchronize with it — a group kill issued microseconds after
        // spawn can precede the group's creation. Retry briefly; the group
        // appears once the child execs. (A pid kill has no such race: the
        // pid exists from spawn on.) Bounded at ~100 ms — 200 × 500 µs — so
        // a genuinely dead group surfaces as an error, just a moment later.
        const esrch: c_int = @intFromEnum(std.c.E.SRCH);
        var attempts: u32 = 0;
        while (true) {
            const rc = platform.procKill(-proc.pgid, sig);
            if (rc == 0) break;
            const errno_val = std.c._errno().*;
            if (errno_val == esrch and attempts < 200) {
                attempts += 1;
                platform.sleepNs(500 * std.time.ns_per_us);
                continue;
            }
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            return raiseProcessError(gc, "cannot signal process group", types.FALSE, errno_val);
        }
        return types.VOID;
    }
    const target: i32 = proc.pid;
    if (platform.procKill(target, sig) != 0) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        return raiseProcessError(gc, "cannot signal process", args[0], std.c._errno().*);
    }
    return types.VOID;
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
};
