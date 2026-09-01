//! The `(kaappi process)` heap type (KEP-0022 Phases 1-3).
//!
//! A `Process` is a spawned child: its pid, its reaped exit status, and the
//! Kaappi-side ends of any pipes requested at spawn. The child-side pipe ends
//! live only inside the posix_spawn file actions (POSIX) or the spawn's
//! explicit inherit list (Windows); nothing here refers to them.
//!
//! This file also owns the *status domain*: how a reaped child's fate is
//! encoded in `status`, how it decodes to the Scheme-facing value, and the
//! one non-blocking reap every layer shares (the reactor's exit event, the
//! primitives' WNOHANG sweeps, the GC's last-resort sweep). Keeping the reap
//! here rather than in `primitives_process.zig` is what lets `reactor.zig`
//! and `gc_sweep.zig` reap without importing the primitive layer.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const platform = @import("platform.zig");
const Value = types.Value;
const Object = types.Object;

const is_windows = platform.is_windows;

pub const Process = struct {
    header: Object,
    /// The child's pid. Valid for signaling only while `status == null`
    /// (process-kill refuses to re-signal a reaped pid -- the number may have
    /// been reused by an unrelated process). On Windows this is the bit
    /// pattern of the u32 process id (`process-pid` reinterprets it), so a
    /// hypothetical id above 2^31 still keys the reactor uniquely.
    pid: i32,
    /// Linux: the pidfd from pidfd_open(), opened when a `process-wait`
    /// registers this child with the reactor and closed when the
    /// registration is dropped — the pidfd's lifetime IS the registration's
    /// (Reactor.registerProcess, KEP-0022 Phase 2). kqueue platforms and
    /// Windows: always -1 (EVFILT_PROC registers by pid; Windows watches
    /// `win_handle`, which the Process owns for its whole lifetime rather
    /// than for a registration's).
    wait_handle: platform.fd_t = -1,
    /// Windows only (KEP-0022 Phase 3): the child's process HANDLE from
    /// CreateProcess. It is the wait object, the reap source
    /// (GetExitCodeProcess) and the kill target (TerminateProcess) all at
    /// once, so the Process owns it for its whole lifetime and only
    /// `gc_sweep.freeObject` closes it — a reap must not, or the reactor's
    /// still-registered wait would hold a dangling handle. Null everywhere
    /// else.
    win_handle: ?*anyopaque = null,
    /// Windows only: the Job Object this child was assigned to at spawn
    /// under `new-group:`, before its primary thread was resumed. Job
    /// Objects are the only Windows mechanism that reaches grandchildren, so
    /// this is what `process-kill 'group: #t` terminates. Closed alongside
    /// `win_handle`; deliberately created *without*
    /// JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, so an abandoned Process leaves
    /// its group running exactly as an abandoned POSIX process group does.
    win_job: ?*anyopaque = null,
    /// The reaped exit status; null while running. POSIX stores the raw
    /// waitpid(2) status word and Windows the raw GetExitCodeProcess code —
    /// two different encodings behind one field, which is why nothing
    /// outside this file may read it except through `decodeStatus`.
    status: ?u32 = null,
    /// Kaappi-side pipe ports, one per 'pipe redirection spec. FALSE for
    /// every other spec ('inherit, 'null, a caller-supplied port, and stderr
    /// under the 'stdout merge) -- exactly what the process-stdin/stdout/
    /// stderr accessors return. Stored once, at spawn, while the Process is
    /// young; the write barrier is applied at that store anyway per the
    /// gc-safety rule ("when in doubt").
    stdin_port: Value = types.FALSE,
    stdout_port: Value = types.FALSE,
    stderr_port: Value = types.FALSE,
    /// Process-group id when spawned with new-group:, else 0. POSIX group
    /// kills signal -pgid; a lone-child kill signals pid. On Windows the
    /// group is `win_job` and this field only records *that* there is one
    /// (it is set to the pid, so `process-group` reports the same value a
    /// POSIX group leader would).
    pgid: i32 = 0,
};

// ---------------------------------------------------------------------------
// waitpid(2) status decoding
// ---------------------------------------------------------------------------
//
// The POSIX macros as functions over the raw status word. Platform-independent
// by construction (every POSIX kernel encodes wait status this way), so the
// BSDs' nonstandard bits (core dump, stop) are simply ignored.

pub fn ifExited(status: u32) bool {
    return (status & 0x7f) == 0;
}

pub fn exitStatus(status: u32) u32 {
    return (status >> 8) & 0xff;
}

pub fn ifSignaled(status: u32) bool {
    const sig = status & 0x7f;
    return sig != 0 and sig != 0x7f;
}

pub fn termSig(status: u32) u32 {
    return status & 0x7f;
}

/// The user-facing encoding of a reaped status (KEP-0022 unresolved question
/// 4, settled Phase 1): the integer exit code for a normal exit, and the pair
/// `(signaled . n)` for abnormal death. This matches the KEP's guide-level
/// examples and the Guile/Python convention (Popen.returncode's negative
/// signaling), needs no decoder procedures, and leaves room for decoders to
/// layer on top later if a SRFI-170-style surface is ever wanted.
///
/// Windows has no signal delivery and no wait-status word: a child's fate is
/// exactly the u32 GetExitCodeProcess reports, so every Windows status
/// decodes to that integer and `(signaled . n)` never appears. What
/// `process-kill` does instead is fold the requested signal into the exit
/// code it hands TerminateProcess — `128 + signal`, the shell convention —
/// so a `'signal: 9` kill surfaces as 137 rather than as a lost distinction
/// (see `process_win.terminateExitCode`). The ambiguity that leaves (a child
/// that *chose* to exit 137) is inherent to the platform.
///
/// GC-safe as written: the fixnum is immediate, and the signaled pair's
/// symbol is interned (root-marked via the symbol table) while allocPair
/// roots its own arguments.
pub fn decodeStatus(gc: anytype, status: u32) !Value {
    if (comptime is_windows) return types.makeFixnum(@intCast(status));
    if (ifExited(status)) return types.makeFixnum(@intCast(exitStatus(status)));
    if (ifSignaled(status)) {
        const sym = try gc.allocSymbol("signaled");
        return gc.allocPair(sym, types.makeFixnum(@intCast(termSig(status))));
    }
    // WIFSTOPPED/WIFCONTINUED (0x7f with stopsig): only reachable via
    // WUNTRACED waits, which Kaappi never issues. Report it as a signal
    // death of 0 rather than inventing a third encoding.
    return types.makeFixnum(0);
}

// ---------------------------------------------------------------------------
// The shared non-blocking reap
// ---------------------------------------------------------------------------

/// What one non-blocking reap attempt found. `.failed` means the child is
/// gone but its status is unobtainable — ECHILD on POSIX (something outside
/// Kaappi reaped it), a dead handle on Windows — which every caller must
/// distinguish from `.running`, or a wait would spin forever on it.
pub const ReapOutcome = enum { reaped, running, failed };

/// One non-blocking reap of `proc`, storing `status` on success. The single
/// implementation behind every WNOHANG sweep, the reactor's exit event, and
/// the GC's last-resort sweep — the three places that must agree on what
/// "already exited" means.
///
/// Windows deliberately tests the handle's signaled state rather than
/// GetExitCodeProcess's STILL_ACTIVE (259): a child that legitimately exits
/// with 259 is indistinguishable from a running one by that code alone, and
/// only the wait object is authoritative.
///
/// Does *not* close `win_handle`: on Windows the handle is also the reactor's
/// wait object and the kill target, owned for the Process's whole lifetime
/// (see the field comment).
pub fn reapNonBlocking(proc: *Process) ReapOutcome {
    if (proc.status != null) return .reaped;
    if (comptime is_windows) {
        const h = proc.win_handle orelse return .failed;
        const w = platform.win.WaitForSingleObject(h, 0);
        if (w == platform.win.WAIT_TIMEOUT) return .running;
        if (w != platform.win.WAIT_OBJECT_0) return .failed;
        var code: u32 = 0;
        if (platform.win.GetExitCodeProcess(h, &code) == 0) return .failed;
        proc.status = code;
        return .reaped;
    }
    if (comptime platform.is_wasm) return .failed;
    var st: c_int = 0;
    const r = platform.waitPid(proc.pid, &st, platform.WNOHANG);
    if (r == proc.pid) {
        proc.status = @bitCast(st);
        return .reaped;
    }
    if (r == 0) return .running;
    // EINTR is "ask again", not "gone": WNOHANG waits do not block, so this
    // is vanishingly rare, but reporting it as `.failed` would turn a
    // spurious interrupt into a raised "cannot wait for process".
    if (platform.errno(-1) == .INTR) return .running;
    return .failed;
}

/// Release the OS objects a Process owns. Called once, from
/// `gc_sweep.freeObject`: the Linux pidfd (belt — a live reactor
/// registration roots the Process, so a collected one is already
/// unregistered) and, on Windows, the process and Job Object handles.
pub fn releaseHandles(proc: *Process) void {
    if (proc.wait_handle >= 0) {
        if (comptime !platform.is_wasm and !is_windows) platform.close(proc.wait_handle);
        proc.wait_handle = -1;
    }
    if (comptime is_windows) {
        if (proc.win_handle) |h| _ = platform.win.CloseHandle(h);
        proc.win_handle = null;
        if (proc.win_job) |j| _ = platform.win.CloseHandle(j);
        proc.win_job = null;
    }
}

// ---------------------------------------------------------------------------
// The spawn contract between the Scheme surface and the two OS backends
// ---------------------------------------------------------------------------
//
// `primitives_process.zig` owns everything Scheme-facing (option parsing,
// redirection validation, the Process object and its ports, the fiber park);
// `process_posix.zig` and `process_win.zig` own the syscalls. These three
// types are the whole seam, and they live here — the type-domain file both
// sides already import — so neither backend has to import the primitive layer
// back.

/// A validated redirection for one stdio slot.
pub const Redir = union(enum) {
    inherit,
    pipe,
    null_sink,
    /// stderr only: the child's slot 2 becomes a copy of its slot 1.
    merge_stdout,
    /// Child gets this descriptor (from an fd-backed port); no pipe is
    /// created and the accessor returns #f.
    fd: platform.fd_t,
};

pub const SpawnConfig = struct {
    argv: []const Value,
    stdin: Redir = .inherit,
    stdout: Redir = .inherit,
    stderr: Redir = .inherit,
    /// null = inherit the current environment wholesale. An alist (including
    /// the empty list) replaces the environment wholesale — Guile/Python
    /// semantics; the copy-and-extend idiom starts from
    /// (process-environment).
    env: ?Value = null,
    directory: ?Value = null,
    new_group: bool = false,
};

/// What a backend hands back once the child exists. Every OS resource in
/// here is *transferred* to the caller, which stores it into the Process (or
/// releases it if a later allocation fails) — a backend must own nothing
/// once it has returned successfully.
pub const Spawned = struct {
    pid: i32,
    /// Nonzero only under `new-group:` (the pid, since the child leads its
    /// own group on both platforms).
    pgid: i32 = 0,
    /// Windows: the child's process HANDLE and, under `new-group:`, its Job
    /// Object. Null on POSIX.
    win_handle: ?*anyopaque = null,
    win_job: ?*anyopaque = null,
    /// Parent ends of the pipes requested by 'pipe specs, indexed by stdio
    /// slot; -1 for every slot that asked for something else. The caller
    /// blanks each slot as a Port takes ownership and closes whatever is
    /// left over on any failure path.
    parent_ends: [3]platform.fd_t = .{ -1, -1, -1 },
};
