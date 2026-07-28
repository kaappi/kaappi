const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;

// ---------------------------------------------------------------------------
// SRFI-254 (Ephemerons and Guardians)
// ---------------------------------------------------------------------------

/// An ephemeron holds `value` alive only while `key` is reachable through a
/// path that does not pass through this ephemeron's value field. When the key
/// becomes unreachable the garbage collector *breaks* the ephemeron: it sets
/// `broken`, and clears `key` and `value` to FALSE (clearing the value keeps
/// `ephemeron-value` memory-safe once the value it referenced is reclaimable —
/// see gc_collect.processWeakRefs). The value field is retained (marked)
/// during collection only when the key is reachable, which is what a plain
/// weak-key pair cannot do: an ephemeron correctly breaks even when its value
/// references its key.
pub const Ephemeron = struct {
    header: Object,
    key: Value,
    value: Value,
    broken: bool = false,
};

/// One registration in a guardian: `watched` is the object observed for
/// unreachability (held weakly), `payload` is the representative returned by a
/// zero-argument guardian call once the element is resurrected. For the
/// one-argument register form `payload == watched`.
pub const GuardEntry = struct {
    watched: Value,
    payload: Value,
};

/// A guardian (SRFI-254). Invoked as a procedure: `(g obj [rep])` registers an
/// element, `(g)` removes and returns a resurrected element's representative
/// (or `#f`). `registered` elements are held weakly; when the collector proves
/// a `watched` object unreachable it resurrects the element (marking both
/// fields) and moves it to `ready`, where `(g)` can retrieve it.
///
/// A transport cell guardian (`is_transport`) is the degenerate case on
/// Kaappi's non-moving collector: keys never move, so no cell is ever
/// transported. Its `registered` cells are held *strongly* (marked by the GC),
/// `ready` stays empty, and `(tg)` always returns `#f`.
pub const Guardian = struct {
    header: Object,
    is_transport: bool,
    registered: std.ArrayList(GuardEntry) = .empty,
    ready: std.ArrayList(GuardEntry) = .empty,
};

/// A transport cell (SRFI-254). On a non-moving collector its `key` and
/// `value` are ordinary strong fields and it never breaks (`broken` stays
/// false); it exists so code written against transport cell guardians ports
/// unchanged, using `current-hash` for stable eq?-hashing.
pub const TransportCell = struct {
    header: Object,
    key: Value,
    value: Value,
    broken: bool = false,
};
