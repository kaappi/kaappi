const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;
const VOID = types.VOID;
const diagnostics = @import("diagnostics.zig");

pub const ErrorObject = struct {
    pub const ErrorType = enum(u8) {
        general,
        file,
        read,
        join_timeout,
        abandoned_mutex,
        terminated_thread,
        uncaught_exception,
        channel_timeout,
        /// SRFI 181: raised by a transcoded port's decode loop under
        /// `raise` error-handling mode. Continuable -- see
        /// primitives_control.raiseContinuable.
        io_decoding,
        /// SRFI 181: raised by a transcoded port's encode loop under
        /// `raise` error-handling mode. Unreachable in practice for v1's
        /// UTF-8-only codec (every valid Kaappi character encodes
        /// successfully), kept for spec-completeness of the predicate/
        /// accessor pair. uncaught_reason carries the offending character
        /// for i/o-encoding-error-char.
        io_encoding,
        /// KEP-0022 Phase 4: `run-process` exceeded its `timeout:`. The
        /// child (and its group) has already been killed and reaped by the
        /// time this is raised, so the condition is the *only* route to
        /// what the child managed to produce: `uncaught_reason` carries
        /// the partial output as a `(stdout . stderr)` pair, which
        /// `process-timeout-stdout`/`-stderr` read back. Irritants hold
        /// the argv and the elapsed-timeout seconds, which are small; the
        /// output rides the reason slot instead precisely so an uncaught
        /// timeout does not print however many megabytes the child wrote.
        process_timeout,
    };

    header: Object,
    message: Value, // string
    irritants: Value, // list
    error_type: ErrorType = .general,
    uncaught_reason: Value = VOID,
    /// Stable diagnostic code (KEP-0005, #1504). Defaults to `.uncategorized`
    /// for user errors — `(error ...)` — and any raise site not yet migrated;
    /// implementation raise sites stamp a specific code. Carried on the object
    /// so it survives catch/re-raise and is the seed the Phase-4
    /// `error-object-code` accessor reads.
    code: diagnostics.Code = .uncategorized,
    /// The `errno` captured at the failing syscall, or 0 when the error did
    /// not come from a syscall (SRFI-170's posix-error protocol, #1978).
    /// Snapshot the thread-local *before* any further libc call — the GC
    /// and strerror(3) itself can clobber it. Stamped by the SRFI-170
    /// raise sites in primitives_filesystem.zig; `posix-error?`/
    /// `posix-error-name`/`posix-error-message` read it.
    posix_errno: c_int = 0,
};
