//! The `(kaappi process)` heap type (KEP-0022 Phase 1).
//!
//! A `Process` is a spawned child: its pid, its reaped exit status, and the
//! Kaappi-side ends of any pipes requested at spawn. The child-side pipe ends
//! live only inside the posix_spawn file actions; nothing here refers to them.

const types = @import("types.zig");
const platform = @import("platform.zig");
const Value = types.Value;
const Object = types.Object;

pub const Process = struct {
    header: Object,
    /// The child's pid. Valid for signaling only while `status == null`
    /// (process-kill refuses to re-signal a reaped pid -- the number may have
    /// been reused by an unrelated process).
    pid: i32,
    /// Linux: pidfd from pidfd_open(); Windows: the process HANDLE. kqueue
    /// platforms: always -1 (EVFILT_PROC is registered by pid, not fd).
    /// Phase 1 leaves it -1 everywhere; Phase 2 (reactor reaping) fills it.
    wait_handle: platform.fd_t = -1,
    /// The raw waitpid(2) status word once reaped; null while running. Use
    /// the decoders below to turn it into the Scheme-facing representation
    /// (see `decodeStatus`).
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
    /// Process-group id when spawned with new-group:, else 0. Group kills
    /// signal -pgid; a lone-child kill signals pid.
    pgid: i32 = 0,
    /// Fibers parked in process-wait (Phase 2, reactor reaping). Opaque
    /// placeholder until then, matching the Channel.shared / FfiLibrary.handle
    /// precedent for fields the types layer must not reach into.
    waiters: ?*anyopaque = null,
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
/// GC-safe as written: the fixnum is immediate, and the signaled pair's
/// symbol is interned (root-marked via the symbol table) while allocPair
/// roots its own arguments.
pub fn decodeStatus(gc: anytype, status: u32) !Value {
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
