const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;

// ---------------------------------------------------------------------------
// Hash table (SRFI-69)
// ---------------------------------------------------------------------------

pub const HashEntryState = enum(u8) {
    empty,
    occupied,
    tombstone,
};

pub const HashEntry = struct {
    key: Value,
    value: Value,
    /// The key's hash, cached at insertion. `rehash` re-buckets from this
    /// instead of re-deriving it, which is what keeps a custom Scheme hash
    /// procedure from running while a soon-to-be-freed entry array is live
    /// (#2024). Deliberately has no default so every insertion site must
    /// supply the hash `findSlot` already computed.
    ///
    /// `u32`, not `usize`: only `hash & (capacity - 1)` is ever read, and a
    /// table with 2^32 buckets would need ~96 GB of entries, so the high half
    /// can never select a bucket. It also keeps this struct at 24 bytes --
    /// widening it to 32 cost 17% on the `hashtable` benchmark, which probes
    /// far more entries than it stores.
    hash: u32,
    state: HashEntryState = .empty,
};

pub const CompareMode = enum(u8) {
    equal, // equal? + hash (default)
    eq, // eq? + hash-by-identity
    eqv, // eqv? + hash
    string_eq, // string=? + string-hash
    string_ci, // string-ci=? + string-ci-hash
    custom, // arbitrary Scheme procedures
};

pub const HashTable = struct {
    header: Object,
    entries: []HashEntry,
    count: usize, // number of live entries
    capacity: usize, // length of entries slice
    compare_mode: CompareMode,
    equiv_fn: Value, // Scheme equivalence procedure
    hash_fn: Value, // Scheme hash procedure
};
