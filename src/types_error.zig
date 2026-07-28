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
};
