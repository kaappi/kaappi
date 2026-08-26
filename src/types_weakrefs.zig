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
/// a `watched` object unreachable it resurrects the element — moving it to
/// `ready`, where `(g)` can retrieve it — keeping both fields *alive without
/// making them reachable* (a weak resurrection, per the spec's hypothetical
/// covering "the fields of guarded elements or by resurrected elements of all
/// guardians"), so every guardian watching the same object fires, not just
/// the first one (#2011).
///
/// A transport cell guardian (`is_transport`) is the degenerate case on
/// Kaappi's non-moving collector: keys never move, so no cell is ever
/// transported, `ready` stays empty, and `(tg)` always returns `#f`. Its
/// `registered` cells are held strongly — a registration is permanent — but
/// each cell's *key* is weakly holding and breaks when the key is reclaimed
/// (#2006).
pub const Guardian = struct {
    header: Object,
    is_transport: bool,
    registered: std.ArrayList(GuardEntry) = .empty,
    ready: std.ArrayList(GuardEntry) = .empty,
};

/// A transport cell (SRFI-254). The `value` field is an ordinary strong
/// field; the `key` field is weakly holding, so when the key location is
/// reclaimed the cell breaks (`broken` set, key cleared to `#f`, which
/// `transport-cell-key` reports; the value survives). Cells themselves never
/// transport on this non-moving collector — only their keys can die.
pub const TransportCell = struct {
    header: Object,
    key: Value,
    value: Value,
    broken: bool = false,
};
