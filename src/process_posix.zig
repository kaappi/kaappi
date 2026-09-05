//! The POSIX backend for `(kaappi process)` — KEP-0022 Phase 1/2.
//!
//! Spawn is `posix_spawnp` with redirections expressed as
//! `posix_spawn_file_actions_t` entries — the fast path every spawn takes
//! except where libc cannot express what is needed: OpenBSD's spawn cannot
//! report a child's exec failure (kaappi#2456), and a build on a host with
//! no `posix_spawn_file_actions_addchdir_np` — neither through the comptime
//! link gate nor the weak extern's runtime binding — cannot express
//! `directory:` (kaappi#2517). Those take a fork + exec route instead
//! (`spawnChildForkExec`), and no path has a pre-exec hook, so every knob
//! between spawn and exec is a named option.
//! Reaping is `waitpid`, signaling is `kill`, and a process group is a real
//! POSIX process group.
//!
//! Split out of `primitives_process.zig` when Phase 3 gave `(kaappi process)`
//! a second OS backend (`process_win.zig`): everything Scheme-facing —
//! option parsing, redirection validation, the Process object and its ports,
//! the fiber park — stayed there, and the syscalls moved here. The seam is
//! the three types in `types_process.zig` (`Redir`, `SpawnConfig`,
//! `Spawned`).
//!
//! POSIX-only libc surface lives here, naked: this file is referenced only
//! on POSIX targets, so none of it is analyzed on Windows or WASM.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const types_process = @import("types_process.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");

const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const GC = memory.GC;
const Redir = types_process.Redir;
const SpawnConfig = types_process.SpawnConfig;
const Spawned = types_process.Spawned;

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
    /// OpenBSD only (see routeFor): its userland, vfork-based posix_spawn
    /// has no channel to report the child's exec failure — POSIX permits
    /// the child to exit 127 instead of the parent seeing an error — so a
    /// missing program "succeeds" and dies 127, indistinguishable from a
    /// program that ran and failed. There, spawn goes through fork + execvp
    /// with a CLOEXEC error pipe (CPython subprocess's mechanism), which
    /// reports the exec errno synchronously like every other libc. file
    /// actions cannot express the pipe's child-side write, so the
    /// redirection setup the actions carry on other platforms runs in the
    /// forked child directly. The same route is the kaappi#2517 runtime
    /// fallback for `directory:` on a build whose host provides no
    /// addchdir_np at all — neither through the comptime gate nor the weak
    /// extern's runtime binding (a genuinely pre-2.29 glibc, NetBSD); there
    /// the diversion is per-spawn at run time (routeFor), not comptime.
    pub const spawn_via_fork_exec = builtin.os.tag == .openbsd;
    pub extern "c" fn fork() c_int;
    /// execve, not execvp: execvp reads the CHILD's environment for its PATH
    /// search, which under `env:` diverged from posix_spawnp's parent-side
    /// resolution (kaappi#2517 review); the child walks the parent-captured
    /// PATH itself (childPathExec) and execve never consults environ.
    pub extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
    pub extern "c" fn open(path: [*:0]const u8, oflag: c_int, mode: c_uint) c_int;
    pub extern "c" fn setpgid(pid: c_int, pgid: c_int) c_int;

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
    /// NetBSD's or OpenBSD's libc (verified at link time per target).
    ///
    /// The glibc floor matters concretely: the release workflow targets
    /// x86_64-linux-gnu.2.28, where the symbol is absent — referencing it
    /// unconditionally on Linux fails that link even when `directory:` is
    /// never used (kaappi#2414 review). Zig only links referenced externs,
    /// so the version gate on this STRONG extern must be comptime,
    /// mirrored by the `comptime` guard at the call site.
    ///
    /// The floor is the *build target's*, not the host's, and a binary
    /// floored at glibc 2.28 was rejecting `directory:` on every Linux host
    /// however new its glibc (kaappi#2517). The strong extern's gate is a
    /// link constraint, not a capability verdict, so availability is
    /// settled in two layers: where the gate is false, `addchdir_weak`
    /// below asks at RUN time — and only where the weak reference is also
    /// unbound (a genuinely pre-2.29 glibc host, NetBSD, OpenBSD) does
    /// `routeFor` send `directory:` down the fork + exec route, whose child
    /// chdirs before the exec — what glibc's addchdir_np itself performs on
    /// the vforked child inside posix_spawn.
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

    /// The weak twin of the extern above, for builds whose comptime gate is
    /// false (the gnu.2.28 floor, NetBSD, OpenBSD). A weak undefined
    /// reference links anywhere — a strong one would fail the gnu.2.28
    /// release link — and the dynamic linker binds it at load time where
    /// the symbol exists: on a gnu.2.28-floored binary running against
    /// glibc >= 2.29, the unversioned weak reference resolves to the
    /// default `@@GLIBC_2.29` definition and `addchdir_weak != null`
    /// (kaappi#2517 review; verified linking for x86_64-linux-gnu.2.28 and
    /// binding under ubuntu-24.04/glibc 2.39). Where the symbol is
    /// genuinely absent — a pre-2.29 host, NetBSD, OpenBSD — it stays null
    /// and `routeFor` diverts `directory:` spawns to the fork route.
    /// Referenced only under `!has_addchdir`, so comptime-true builds
    /// neither analyze nor emit it.
    pub const addchdir_weak: ?*const fn (*FileActionsPtr, [*:0]const u8) callconv(.c) c_int =
        @extern(?*const fn (*FileActionsPtr, [*:0]const u8) callconv(.c) c_int, .{
            .name = "posix_spawn_file_actions_addchdir_np",
            .linkage = .weak,
        });

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

// ---------------------------------------------------------------------------
// Backend interface (mirrored by process_win.zig)
// ---------------------------------------------------------------------------

/// The errno the last failing call left behind, for the errno-carrying
/// `.file` condition. (Windows folds GetLastError into an errno here.)
pub fn lastError() c_int {
    return std.c._errno().*;
}

/// A `'signal: 0` probe is `kill(pid, 0)` — existence without delivery.
pub const signal_zero_is_probe = true;

// ---------------------------------------------------------------------------
// spawn
// ---------------------------------------------------------------------------

/// Which of the two spawn routes a child takes: the `posix_spawnp` fast
/// path with file actions, or the fork + exec route with its CLOEXEC error
/// pipe (`spawnChildForkExec`).
pub const SpawnRoute = enum { posix_spawn, fork_exec };

/// The route decision (kaappi#2517), keyed on one comptime fact and up to
/// two runtime ones:
///
/// - `spawn_via_fork_exec` is COMPTIME (OpenBSD: its userland posix_spawn
///   cannot report a child's exec failure, so every spawn forks). As a
///   `comptime` parameter of an `inline fn`, the decision folds on such a
///   build and the posix route is not analyzed at all — the same link
///   protection the old `if (comptime ...)` dispatch had.
/// - `addchdir_available` is a RUNTIME fact on builds whose comptime gate
///   for `posix_spawn_file_actions_addchdir_np` is false (the gnu.2.28
///   floor, NetBSD): there the call site passes the binding of the weak
///   extern `spawn_c.addchdir_weak`, so a release binary keeps the
///   `posix_spawnp` fast path for `directory:` on every host whose libc
///   has the symbol (glibc >= 2.29 — essentially all of them) and forks
///   only on genuinely old hosts. On a comptime-true build the call site
///   passes a comptime-known `true`, which folds the decision to
///   `posix_spawn` for every spawn — both routes are analyzed and emitted
///   only where the branch is genuinely runtime.
/// - With neither addchdir nor a `directory:` request, `posix_spawnp` —
///   the fast path every spawn takes unless the fork route is forced.
///
/// `inline` is load-bearing, not stylistic: a plain `fn` called with a
/// runtime argument makes the call itself runtime, Zig then analyzes both
/// dispatch branches on every target, and the comptime folding above — and
/// the OpenBSD link protection it restores — is gone (kaappi#2517 review).
///
/// A pure function of its flags (rather than reading `spawn_c` directly)
/// so the routing table is unit-testable on hosts where some combinations
/// never occur natively (`tests_process_fork.zig`).
pub inline fn routeFor(comptime spawn_via_fork_exec: bool, addchdir_available: bool, directory_requested: bool) SpawnRoute {
    if (spawn_via_fork_exec) return .fork_exec;
    if (addchdir_available) return .posix_spawn;
    if (!directory_requested) return .posix_spawn;
    return .fork_exec;
}

/// Create the child. Everything GC-managed is copied into an arena before the
/// first syscall; nothing GC-managed crosses the spawn section, and on
/// success every OS resource in the returned `Spawned` belongs to the caller.
pub fn spawnChild(gc: *GC, cfg: SpawnConfig, redirs_in: [3]Redir) PrimitiveError!Spawned {
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
        const dir = types.toObject(dir_val).as(types.SchemeString);
        directory_z = try dupeZChecked("spawn-process", arena_al, dir.data[0..dir.len], "directory: path");
    }

    // -- pipes. Cleanup discipline: every fd this function creates lives in
    // one of the slots below, and the single defer closes whatever is still
    // >= 0 on ANY exit path — success included. Ownership transfer is
    // recorded by writing -1 into the slot: the child ends after their
    // explicit post-spawn close, each parent end once it has been handed to
    // the caller in `Spawned`, the staged redirect duplicates never (the
    // parent must always release them). Nothing is disarmed wholesale, so an
    // OOM between the spawn and the handoff cannot leak a descriptor
    // (kaappi#2442 review).
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
        return raiseSpawnError(gc, "cannot create stdin pipe", types.FALSE, lastError());
    if (cfg.stdout == .pipe and pipeWithFdRetry(gc, &stdout_pipe) != 0)
        return raiseSpawnError(gc, "cannot create stdout pipe", types.FALSE, lastError());
    if (cfg.stderr == .pipe and pipeWithFdRetry(gc, &stderr_pipe) != 0)
        return raiseSpawnError(gc, "cannot create stderr pipe", types.FALSE, lastError());

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
    var redirs = redirs_in;
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
            return raiseSpawnError(gc, "cannot stage redirection descriptor", types.FALSE, lastError());
        staged_fds[slot] = staged;
        r.* = .{ .fd = staged };
    }

    // The child-side ends of any pipes: the posix path's file actions
    // dup2 them into the stdio slots, the OpenBSD fork path's child does
    // the same dup2s directly.
    const child_pipe_ends = [3]platform.fd_t{ stdin_pipe[0], stdout_pipe[1], stderr_pipe[1] };

    // -- spawn. Route it (see routeFor): the posix_spawnp fast path takes
    // every spawn wherever addchdir_np is available — on a comptime-true
    // build that is everywhere, and on a gnu.2.28-floored release binary it
    // is every host with glibc >= 2.29, read from the runtime weak-extern
    // binding — plus every directory-less spawn anywhere. The fork + exec
    // route takes OpenBSD (always) and a `directory:` spawn of a build on a
    // host where neither the comptime gate nor the weak binding provides
    // the symbol (a genuinely pre-2.29 glibc, NetBSD, OpenBSD); its child
    // chdirs between fork and exec because file actions cannot express the
    // change of directory there.
    const addchdir_available = if (comptime spawn_c.has_addchdir) true else (spawn_c.addchdir_weak != null);
    var pid: c_int = -1;
    if (routeFor(spawn_c.spawn_via_fork_exec, addchdir_available, directory_z != null) == .fork_exec) {
        pid = try spawnChildForkExec(gc, argv, env_block, redirs, child_pipe_ends, cfg, directory_z);
    } else {
        pid = try spawnChildPosixSpawn(gc, argv, env_block, directory_z, redirs, child_pipe_ends, cfg);
    }

    // The child owns the child ends now; the parent's copies must go
    // (recorded as -1 so the cleanup defer never double-closes them).
    if (stdin_pipe[0] >= 0) _ = platform.close(stdin_pipe[0]);
    stdin_pipe[0] = -1;
    if (stdout_pipe[1] >= 0) _ = platform.close(stdout_pipe[1]);
    stdout_pipe[1] = -1;
    if (stderr_pipe[1] >= 0) _ = platform.close(stderr_pipe[1]);
    stderr_pipe[1] = -1;

    // Hand the parent ends over; blanking each slot is what keeps the
    // cleanup defer from closing what the caller now owns.
    var out = Spawned{ .pid = pid, .pgid = if (cfg.new_group) pid else 0 };
    out.parent_ends = .{ stdin_pipe[1], stdout_pipe[0], stderr_pipe[0] };
    stdin_pipe[1] = -1;
    stdout_pipe[0] = -1;
    stderr_pipe[0] = -1;
    return out;
}

/// The posix_spawnp fast path: redirections as file actions, close-by-default
/// as actions or Darwin's CLOEXEC_DEFAULT, `directory:` as addchdir_np — the
/// plain extern where the comptime link gate allows, the runtime-bound weak
/// extern on a gnu.2.28-floored build. Every spawn wherever addchdir_np is
/// available, and every directory-less spawn anywhere, routes here
/// (routeFor). Extracted from `spawnChild` when kaappi#2517 gave it a sibling
/// route; the body is the pre-fallback code plus the weak-extern arm.
/// Returns the child's pid.
fn spawnChildPosixSpawn(
    gc: *GC,
    argv: [*:null]const ?[*:0]const u8,
    env_block: ?[*:null]const ?[*:0]const u8,
    directory_z: ?[*:0]const u8,
    redirs: [3]Redir,
    child_pipe_ends: [3]platform.fd_t,
    cfg: SpawnConfig,
) PrimitiveError!c_int {
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
        if (rc < 0) rc = lastError();
        if (rc != 0) return spawnSetupError(gc, rc);
    }
    defer _ = spawn_c.posix_spawn_file_actions_destroy(actions);

    const O_RDONLY: c_int = 0;
    const O_WRONLY: c_int = 1;
    const null_z: [*:0]const u8 = "/dev/null";
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
                // Rejected for slots 0 and 1 by the shared caller.
                const rc = spawn_c.posix_spawn_file_actions_adddup2(actions, 1, 2);
                if (rc != 0) return spawnSetupError(gc, rc);
            },
        }
    }
    // `directory:` as an addchdir action — two ways to reach the symbol.
    // Where the comptime link gate allows (macOS, FreeBSD, musl,
    // gnu-ABI >= 2.29), the plain extern. On a comptime-false build, the
    // weak extern instead: it links where a strong reference would fail
    // the gnu.2.28 release link, and the dynamic linker binds it at load
    // time on every host with glibc >= 2.29 — so a release binary honors
    // `directory:` through this fast path there rather than forking
    // (kaappi#2517 review). Where the binding is null — a genuinely
    // pre-2.29 host, NetBSD, OpenBSD — routeFor has already diverted the
    // `directory:` spawn to the fork route, so this branch sees
    // directory_z == null by construction and a null binding cannot
    // silently drop a requested directory.
    if (comptime spawn_c.has_addchdir) {
        if (directory_z) |dir| {
            const rc = spawn_c.posix_spawn_file_actions_addchdir_np(actions, dir);
            if (rc != 0) return spawnSetupError(gc, rc);
        }
    } else if (directory_z) |dir| {
        if (spawn_c.addchdir_weak) |addchdir| {
            const rc = addchdir(actions, dir);
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
        if (rc < 0) rc = lastError();
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

    // -- posix_spawnp
    const envp: [*:null]const ?[*:0]const u8 = env_block orelse @ptrCast(std.c.environ);
    var spawn_rc: c_int = 0;
    var pid: c_int = -1;
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
        // posix-error-name reports it precisely. The caller's cleanup defer
        // closes the pipes and staged fds; the destroy defers above release
        // actions/attr.
        return raiseSpawnErrorInt(gc, "cannot spawn process", cfg.argv[0], spawn_rc);
    }
    return pid;
}

/// The fork + exec spawn path: fork + execve with a CLOEXEC error pipe, the
/// mechanism CPython's subprocess uses (kaappi#2456). OpenBSD's only route,
/// and since kaappi#2517 the runtime fallback for `directory:` on a build
/// whose host provides no `posix_spawn_file_actions_addchdir_np` at all —
/// neither through the comptime gate (macOS, FreeBSD, musl,
/// gnu-ABI >= 2.29) nor through the weak extern's runtime binding (a
/// gnu.2.28-floored release binary on a glibc >= 2.29 host): what remains
/// is a genuinely pre-2.29 glibc host, NetBSD, and OpenBSD.
///
/// The child installs the redirections, optionally chdirs to `directory`,
/// drops every inherited descriptor beyond the stdio slots, and execs. A
/// failure anywhere in that stretch writes its errno into the pipe and only
/// then _exits 127; a successful exec closes the write end via FD_CLOEXEC,
/// so the parent's read returns EOF exactly at the exec. That read point
/// also restores the vfork parity every other platform already has — the
/// parent does not resume until the exec is done, which is the same
/// signalability-from-return property the NetBSD exec barrier exists to
/// provide (and why the fallback needs no barrier of its own).
///
/// The child-side chdir is what glibc's addchdir_np performs on the
/// vforked child inside posix_spawn; doing it between fork and exec keeps
/// every child-side operation on POSIX's async-signal-safe list. A bad
/// `directory:` reports through the same one-byte error pipe as a failed
/// exec, synchronously — the condition macOS's and FreeBSD's posix_spawn
/// also raise for a failed chdir action. glibc's posix_spawn instead lets
/// a failed file action kill the child with exit 127 (measured on 2.39),
/// so on a glibc host the routes differ in failure REPORTING only — that
/// is glibc's own behavior for any addchdir build, not something the
/// fallback introduces — and the fork route's synchronous raise is the
/// more diagnosable of the two. PATH resolution matches the fast path
/// everywhere: the parent's PATH is captured before the fork and walked in
/// the child (see below), because execvp would search the child's — under
/// `env:` the two routes disagreed for the same request.
///
/// Only the fork, the read, and a failure reap run here; everything before
/// (argv, env block, pipes, redirect staging, the NUL-checked directory
/// copy) is shared with the posix_spawnp path, and everything the file
/// actions do there happens in the forked child directly (childExecSide).
/// `pub` so the unit tests can drive the fallback mechanism directly on
/// hosts whose own gate is true (tests_process_fork.zig); nothing else
/// imports the backend.
pub fn spawnChildForkExec(
    gc: *GC,
    argv: [*:null]const ?[*:0]const u8,
    env_block: ?[*:null]const ?[*:0]const u8,
    redirs: [3]Redir,
    child_pipe_ends: [3]platform.fd_t,
    cfg: SpawnConfig,
    directory: ?[*:0]const u8,
) PrimitiveError!c_int {
    var err_pipe: [2]platform.fd_t = .{ -1, -1 };
    if (pipeWithFdRetry(gc, &err_pipe) != 0)
        return raiseSpawnErrorInt(gc, "cannot create exec error pipe", types.FALSE, lastError());
    defer closePipePair(&err_pipe);
    // The error pipe must not live in a stdio slot: with inherited standard
    // descriptors closed, pipe(2) hands back 0, 1 or 2, and a non-inherit
    // redirection for that slot then REPLACES the child's copy of the write
    // end before a chdir/exec failure could report through it — the parent
    // would read EOF, treat the exec as successful, and hand back a child
    // that dies 127 (kaappi#2517 review). The same lift the user-facing
    // pipes already get, applied to the pipe whose whole job is reporting.
    try normalizePipeAboveStdio(gc, &err_pipe);

    // PATH parity with posix_spawnp (kaappi#2517 review): glibc resolves a
    // bare program name against the PARENT's PATH, but execvp in the child
    // reads the CHILD's environment — with `env:` replacing it, the same
    // request succeeded on one route and raised ENOENT on the other
    // (measured on the gnu.2.28 build). Capture the parent's PATH here,
    // where getenv is unrestricted, and walk it in the child with execve —
    // CPython's subprocess mechanism. Unset PATH falls back to the
    // historical "/bin:/usr/bin" (glibc's _PATH_STDPATH) in the child.
    const parent_path: ?[*:0]const u8 = std.c.getenv("PATH");

    var forked_pid: c_int = -1;
    var fork_errno: c_int = 0;
    var exec_errno: c_int = 0;
    {
        // The fork, the read up to the child's exec, and a failure reap
        // can all block past the dispatch-loop safepoint — the same
        // markable-in-native protocol as the posix_spawnp stretch (the
        // #1933 shape), restored before the raises below can allocate.
        const spawn_vm: ?*vm_mod.VM = if (vm_mod.vm_instance) |vm|
            (if (!vm.owns_globals) vm else null)
        else
            null;
        if (spawn_vm) |vm| vm.setCollectionInNative();
        defer if (spawn_vm) |vm| vm.setCollectionRunning();

        forked_pid = spawn_c.fork();
        if (forked_pid < 0) {
            fork_errno = lastError();
        } else if (forked_pid == 0) {
            childExecSide(argv, env_block, redirs, child_pipe_ends, cfg.new_group, directory, parent_path, err_pipe[1]);
        } else {
            // The child owns its copy of the write end; dropping ours is
            // what makes the read return at the child's exec rather than
            // at its death.
            _ = platform.close(err_pipe[1]);
            err_pipe[1] = -1;
            while (true) {
                var byte: [1]u8 = undefined;
                const n = platform.read(err_pipe[0], &byte, 1);
                if (n < 0 and lastError() == @intFromEnum(std.c.E.INTR)) continue;
                // One byte: the child's exec errno. Zero (EOF): the exec
                // closed the write end, i.e. it succeeded. A read error
                // other than EINTR cannot be diagnosed from here; treat
                // it as success and let the child's own lifetime (or its
                // first stdio failure) surface the truth.
                if (n == 1) exec_errno = byte[0];
                break;
            }
            if (exec_errno != 0) {
                // The child wrote its errno and is in _exit: reap it so
                // the failure leaves no zombie, then raise the file error
                // the errno names — synchronously, like every libc that
                // can report it.
                var st: c_int = 0;
                while (true) {
                    const r = platform.waitPid(forked_pid, &st, 0);
                    if (r == forked_pid) break;
                    if (r < 0 and lastError() == @intFromEnum(std.c.E.INTR)) continue;
                    break; // ECHILD: a concurrent sweep already reaped it
                }
            }
        }
    }
    if (fork_errno != 0)
        return raiseSpawnErrorInt(gc, "cannot spawn process", cfg.argv[0], fork_errno);
    if (exec_errno != 0)
        return raiseSpawnErrorInt(gc, "cannot spawn process", cfg.argv[0], exec_errno);
    return forked_pid;
}

/// The child side of the fork (spawnChildForkExec): install the stdio
/// slots, chdir to the optional `directory` (the kaappi#2517 fallback —
/// the one knob the posix_spawn file actions cannot express without
/// addchdir_np), drop every inherited descriptor beyond the stdio slots,
/// become the optional group leader, restore SIGPIPE's default, and exec
/// through the PARENT-captured PATH (`path_env`, see spawnChildForkExec).
/// Between fork and exec in a forked child of a threaded process only
/// async-signal-safe calls are allowed — every branch below is raw
/// syscalls and stack-buffer memory moves on arena-copied arguments
/// (chdir(2) included: it is on POSIX's async-signal-safe list). Never
/// returns: a successful exec replaces the process, and every failure
/// writes its errno to `err_fd` and _exits 127.
fn childExecSide(
    argv: [*:null]const ?[*:0]const u8,
    env_block: ?[*:null]const ?[*:0]const u8,
    redirs: [3]Redir,
    child_pipe_ends: [3]platform.fd_t,
    new_group: bool,
    directory: ?[*:0]const u8,
    path_env: ?[*:0]const u8,
    err_fd: platform.fd_t,
) noreturn {
    const O_RDONLY: c_int = 0;
    const O_WRONLY: c_int = 1;
    const null_z: [*:0]const u8 = "/dev/null";
    const slot_oflag = [3]c_int{ O_RDONLY, O_WRONLY, O_WRONLY };

    // The direct twin of the file-actions loop: stdin/stdout/stderr in
    // order, stderr last so 'stdout merge duplicates the child's final
    // slot-1 descriptor.
    for (redirs, 0..) |redir, slot_usize| {
        const slot: platform.fd_t = @intCast(slot_usize);
        var ok = true;
        switch (redir) {
            // 'inherit keeps whatever the parent has in the slot —
            // including a slot the parent itself closed, which stays
            // closed in the child (the addinherit arm's getFdFlags guard
            // exists only because that action FAILS on a bad fd).
            .inherit => {},
            .pipe => {
                const child_end = child_pipe_ends[slot_usize];
                ok = std.c.dup2(child_end, slot) >= 0;
                // A close of a just-dup2'd descriptor cannot meaningfully
                // fail; exec would drop it anyway.
                _ = platform.close(child_end);
            },
            .null_sink => {
                // addopen's close-then-open-into-the-slot semantics; the
                // portable form opens to any descriptor (open() picks the
                // lowest free one, not a named slot) and dup2s it in. The
                // just-closed slot is usually that lowest free one, in
                // which case open() returns the slot ITSELF — then dup2
                // would be a no-op and closing `opened` would undo the
                // installation (measured as `cat: stdout: Bad file
                // descriptor` under 'stdout: 'null), so that case is its
                // own branch.
                _ = platform.close(slot);
                const opened = spawn_c.open(null_z, slot_oflag[slot_usize], 0);
                if (opened >= 0) {
                    if (opened != slot) {
                        ok = std.c.dup2(opened, slot) >= 0;
                        _ = platform.close(opened);
                    }
                } else ok = false;
            },
            .fd => |fd| ok = std.c.dup2(fd, slot) >= 0,
            .merge_stdout => ok = std.c.dup2(1, 2) >= 0,
        }
        if (!ok) childExecFail(err_fd, lastError());
    }

    // `directory:`, performed parent-side by addchdir_np wherever the
    // symbol is available. chdir(2) between fork and exec is
    // async-signal-safe, and a failure reports through the error pipe
    // exactly like a failed exec — synchronously, the way macOS's and
    // FreeBSD's posix_spawn report a failed chdir action (glibc's instead
    // exits the child 127; see spawnChildForkExec's doc).
    if (directory) |dir| {
        if (std.c.chdir(dir) != 0) childExecFail(err_fd, lastError());
    }

    // The fork twin of addInheritedFdCloses: after the exec, the child must
    // hold nothing beyond the stdio slots. On Linux (kernel >= 5.11), one
    // raw close_range(2) with CLOSE_RANGE_CLOEXEC marks the whole range
    // close-on-exec at once — the raw syscall, not a libc wrapper (glibc
    // grew close_range only in 2.34; the syscall bypasses libc, so the
    // gnu.2.28 floor is irrelevant, and a raw syscall is async-signal-safe).
    // Marking CLOEXEC rather than closing is the correct shape here, not a
    // compromise: at this point every fd >= 3 the child still holds is
    // either already close-on-exec BY DESIGN (the staged redirect sources;
    // this path's own error pipe, whose EOF-at-exec is the parent's very
    // success signal) or an inherited descriptor close-by-default must
    // remove — the exec closes them all, which is exactly the end state the
    // probe loop below produces, without ~RLIMIT_NOFILE fcntl probes
    // (measured ~80 ms per spawn at soft nofile 524288; kaappi#2517 review).
    // A plain close_range would instead CLOSE the range outright, killing
    // the error pipe before a chdir/exec failure could report through it.
    // ENOSYS (kernel < 5.9) and EINVAL (5.9-5.10, flag unsupported) — and,
    // defensively, any other failure — fall back to the probe.
    const range_marked = blk: {
        if (comptime builtin.os.tag != .linux) break :blk false;
        // `last` = every fd: fd_t is signed, so -1 is the all-bits-set the
        // kernel reads as ~0U.
        const rc = std.os.linux.close_range(3, -1, .{ .CLOEXEC = true });
        break :blk rc == 0;
    };
    if (!range_marked) {
        // OpenBSD/NetBSD (and a pre-5.11 Linux): the inline fcntl probe —
        // every open fd >= 3 that is not already close-on-exec is closed.
        // No /proc on OpenBSD, no allocation, and the same
        // no-arbitrary-cap rationale as the file-actions fallback: a valid
        // high descriptor silently exempted would break close-by-default.
        const fallback: u64 = 65536;
        const raw_limit: u64 = blk: {
            const rl = std.posix.getrlimit(.NOFILE) catch break :blk fallback;
            break :blk std.math.cast(u64, rl.cur) orelse fallback;
        };
        const limit: platform.fd_t = @intCast(@min(raw_limit, std.math.maxInt(platform.fd_t)));
        const FD_CLOEXEC: c_int = 1;
        var fd: platform.fd_t = 3;
        while (fd < limit) : (fd += 1) {
            const flags = platform.getFdFlags(fd);
            if (flags < 0) continue; // not open
            if ((flags & FD_CLOEXEC) == 0) _ = platform.close(fd);
        }
    }

    if (new_group) _ = spawn_c.setpgid(0, 0);

    // The parent runs SIGPIPE ignored and an ignored disposition survives
    // fork and exec; restore the default, the same reset SETSIGDEF
    // performs on the posix_spawnp path.
    var act = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &act, null);

    // Exec through the PARENT's PATH (captured before the fork; see
    // spawnChildForkExec). A caller-supplied env: block is passed to
    // execve directly — the child never touches the global environ.
    const envp: [*:null]const ?[*:0]const u8 = env_block orelse @ptrCast(std.c.environ);
    childPathExec(argv, envp, path_env, err_fd);
}

/// The child's PATH walk (childExecSide's tail): resolve `argv[0]` against
/// `path_env` — the PARENT's PATH, not the child's environment — and
/// execve each candidate, exactly execvp's rules:
///
/// - a program name containing '/' is execve'd as-is, never searched;
/// - an empty PATH entry means the current directory (which `directory:`
///   may have just changed — the same order glibc's addchdir + spawnp
///   performs, so the two routes agree here too);
/// - an EACCES candidate is remembered while the search continues, and a
///   fully failed search reports EACCES if any candidate hit it, ENOENT
///   otherwise;
/// - an unset PATH uses the historical "/bin:/usr/bin" (glibc's
///   _PATH_STDPATH), not the inherited environment.
///
/// Stack buffers only — no allocation, so the async-signal-safe contract
/// between fork and exec holds (execvpe would hand the walk to libc, but
/// OpenBSD has none; execvp reads the child's environ, which under `env:`
/// diverged from posix_spawnp's parent-side resolution — kaappi#2517
/// review). Never returns: a successful execve replaces the process, and
/// every failure reports through `err_fd` and _exits 127.
fn childPathExec(
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
    path_env: ?[*:0]const u8,
    err_fd: platform.fd_t,
) noreturn {
    const prog: [*:0]const u8 = argv[0].?;

    // A name with a slash is never searched — execvp's rule.
    var has_slash = false;
    {
        var i: usize = 0;
        while (prog[i] != 0) : (i += 1) {
            if (prog[i] == '/') {
                has_slash = true;
                break;
            }
        }
    }
    if (has_slash) {
        _ = spawn_c.execve(prog, argv, envp);
        childExecFail(err_fd, lastError());
    }

    const path: [*:0]const u8 = path_env orelse "/bin:/usr/bin";
    var saw_acces = false;
    var start: usize = 0;
    var i: usize = 0;
    while (true) {
        const c = path[i];
        if (c != 0 and c != ':') {
            i += 1;
            continue;
        }
        // Entry [start, i); empty means "." — execvp's rule.
        const entry: []const u8 = if (i == start) "." else path[start..i];
        const prog_len = std.mem.len(prog);
        var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        if (entry.len + 1 + prog_len + 1 > buf.len) {
            // An unbuildable candidate (entry near PATH_MAX) cannot be
            // exec'd; skip it rather than truncate into a different path.
            if (c == 0) break;
            i += 1;
            start = i;
            continue;
        }
        @memcpy(buf[0..entry.len], entry);
        buf[entry.len] = '/';
        @memcpy(buf[entry.len + 1 .. entry.len + 1 + prog_len], prog[0..prog_len]);
        buf[entry.len + 1 + prog_len] = 0;
        const candidate: [*:0]const u8 = buf[0 .. entry.len + 1 + prog_len :0].ptr;
        _ = spawn_c.execve(candidate, argv, envp);
        // execve returned: this candidate failed. EACCES is remembered and
        // the search continues (execvp's behavior); every other error —
        // ENOENT, ENOTDIR, ENAMETOOLONG, ... — also continues, because a
        // later entry may still hold the program.
        if (lastError() == @intFromEnum(std.c.E.ACCES)) saw_acces = true;
        if (c == 0) break;
        i += 1;
        start = i;
    }
    childExecFail(err_fd, if (saw_acces)
        @intFromEnum(std.c.E.ACCES)
    else
        @intFromEnum(std.c.E.NOENT));
}

/// Report a child-side exec failure and die: one errno byte for the parent
/// (every OpenBSD errno value fits in a byte, and a 1-byte write to a pipe
/// is atomic), then the conventional exec-failure exit status. Writing
/// before _exit is what keeps the parent from mistaking this child for a
/// program that ran and legitimately failed.
fn childExecFail(err_fd: platform.fd_t, errno_val: c_int) noreturn {
    const byte: u8 = @truncate(@as(u32, @bitCast(errno_val)));
    _ = platform.write(err_fd, @ptrCast(&byte), 1);
    std.c._exit(127);
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
pub fn killAndReapFresh(spawned: Spawned) bool {
    return killAndReapPid(spawned.pid);
}

/// The same, for a child whose Process object already exists. POSIX owns no
/// per-Process OS handle, so the two are identical here; on Windows they
/// differ in who closes the process HANDLE.
pub fn killAndReapChild(proc: *types.Process) bool {
    return killAndReapPid(proc.pid);
}

fn killAndReapPid(pid: i32) bool {
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
        if (r < 0 and lastError() == @intFromEnum(std.c.E.INTR)) continue;
        return false;
    }
}

/// The raw wait status a `killAndReapFresh` SIGKILL leaves behind, stored so
/// a later sweep never reaps a reused pid.
pub const kill_fresh_status: u32 = 9; // (signaled . 9)

// ---------------------------------------------------------------------------
// reap / signal
// ---------------------------------------------------------------------------

/// Block until the child is reaped. `status` is stored on success; the
/// returned errno is 0 on success and the failing `waitpid` errno otherwise.
/// The Phase-1 blocking reap, kept verbatim as the no-scheduler fallback
/// (and the degradation path when the reactor cannot watch this child).
pub fn blockingReap(proc: *types.Process) c_int {
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
                wait_errno = lastError();
                const eintr: c_int = @intFromEnum(std.c.E.INTR);
                if (wait_errno == eintr) continue;
                break;
            }
        }
    }
    if (!reaped) return if (wait_errno != 0) wait_errno else @intFromEnum(std.c.E.CHILD);
    proc.status = @bitCast(st);
    return 0;
}

/// `kill(pid, sig)`. Returns 0, or the errno of the failure.
pub fn signalOne(proc: *types.Process, sig: c_int) c_int {
    if (platform.procKill(proc.pid, sig) == 0) return 0;
    return lastError();
}

/// `kill(-pgid, sig)` — the whole process group, grandchildren included.
///
/// ESRCH right after spawn is almost always the SETPGROUP race, not
/// "already dead": POSIX_SPAWN_SETPGROUP's setpgid runs in the child just
/// before its exec, and the parent's posix_spawn return does not synchronize
/// with it — a group kill issued microseconds after spawn can precede the
/// group's creation. Retry briefly; the group appears once the child execs.
/// (A pid kill has no such race: the pid exists from spawn on.) Bounded at
/// ~100 ms — 200 x 500 us — so a genuinely dead group surfaces as an error,
/// just a moment later.
pub fn signalGroup(proc: *types.Process, sig: c_int) c_int {
    const esrch: c_int = @intFromEnum(std.c.E.SRCH);
    var attempts: u32 = 0;
    while (true) {
        if (platform.procKill(-proc.pgid, sig) == 0) return 0;
        const errno_val = lastError();
        if (errno_val == esrch and attempts < 200) {
            attempts += 1;
            platform.sleepNs(500 * std.time.ns_per_us);
            continue;
        }
        return errno_val;
    }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// A catchable `.file` error carrying errno. Thin forwarder to the shared
/// raiser so this file needs no import of the primitive layer.
fn raiseSpawnError(gc: *GC, msg_text: []const u8, irritant: Value, errno_val: c_int) PrimitiveError!Spawned {
    _ = try @import("primitives_process.zig").raiseProcessError(gc, msg_text, irritant, errno_val);
    unreachable;
}

/// The same raise with the fork+exec path's payload type (spawnChildForkExec
/// returns a bare pid; spawnChild wraps it into `Spawned` afterwards).
fn raiseSpawnErrorInt(gc: *GC, msg_text: []const u8, irritant: Value, errno_val: c_int) PrimitiveError!c_int {
    _ = try @import("primitives_process.zig").raiseProcessError(gc, msg_text, irritant, errno_val);
    unreachable;
}

/// Raise the errno-carrying redirection-setup error. All posix_spawn
/// file-action and attr functions RETURN the error number rather than
/// setting errno (kaappi#2442 review) — callers pass that return code here.
/// Payload type matches the posix route (spawnChildPosixSpawn) and
/// addInheritedFdCloses, both of which return a bare pid or void.
fn spawnSetupError(gc: *GC, rc: c_int) PrimitiveError!c_int {
    return raiseSpawnErrorInt(gc, "cannot set up process redirection", types.FALSE, rc);
}

/// Lift both ends of a created pipe above the stdio range (fd >= 3) via
/// F_DUPFD_CLOEXEC, closing the low originals. See the call site for why a
/// pipe end in 0..2 is unusable in the file actions.
fn normalizePipeAboveStdio(gc: *GC, fds: *[2]platform.fd_t) PrimitiveError!void {
    for (fds) |*fd| {
        if (fd.* < 0 or fd.* > 2) continue;
        const high = platform.dupCloexecAtLeast(fd.*, 3);
        if (high < 0)
            _ = try raiseSpawnError(gc, "cannot relocate pipe descriptor above the stdio range", types.FALSE, lastError());
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
    // Linux) never reach a per-fd probe loop at all: FreeBSD uses
    // addclosefrom_np above, Linux uses /proc here, and the fork route's
    // child-side twin (childExecSide) uses close_range there — so no spawn
    // path on either pays the probe cost.
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
