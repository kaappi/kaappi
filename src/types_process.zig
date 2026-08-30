//! The `Process` heap type (KEP-0022, kaappi#2414) — a handle on a child
//! process spawned via `posix_spawn`. Kept in its own domain file and
//! re-exported from `types.zig`, following the heap-type checklist in
//! `CLAUDE.md`.
//!
//! A `Process` is *thread-affine*: it is spawned and reaped by one
//! scheduler thread, and its pipe ports live in that thread's heap. Every
//! `(kaappi process)` primitive that dereferences one checks the header
//! `Object.owner` against the current GC id (the channel precedent — ports
//! deliberately are not owner-checked, but Process takes the channel side),
//! and `gc_deep_copy.zig` refuses to copy it across a channel.

const types = @import("types.zig");
const platform = @import("platform.zig");
const Value = types.Value;
const Object = types.Object;

pub const Process = struct {
    header: Object,
    /// Child pid. Set once at spawn and never re-signaled after reap (the
    /// number may be reused by the OS — Python's `Popen.kill` contract).
    pid: i32,
    /// Reactor wait-registration handle: a `pidfd` on Linux, the process
    /// HANDLE on Windows, `-1` on kqueue platforms (where `EVFILT_PROC`
    /// registers by pid). Phase 1 (blocking `process-wait`) never registers
    /// with the reactor, so this stays `-1`; the field is reserved so the
    /// heap type does not change shape when Phase 2 wires in fiber-parking
    /// waits.
    wait_handle: platform.fd_t = -1,
    /// The raw `waitpid(2)` status once the child has been reaped, or `null`
    /// while it is still running. Decoded on demand by `process-status`
    /// (exit code as a fixnum, or `(signaled . signo)`).
    status: ?u32 = null,
    /// Kaappi-side pipe ports — the parent's end of each `'pipe` redirection,
    /// `#f` for every other spec (`'inherit`, `'null`, a caller-supplied
    /// port, and stderr under the `'stdout` merge). These are `Value` fields
    /// and must be traversed by the GC mark switches.
    stdin_port: Value = types.FALSE,
    stdout_port: Value = types.FALSE,
    stderr_port: Value = types.FALSE,
    /// Process-group id when spawned with `new-group: #t`, else `0`.
    pgid: i32 = 0,
};
