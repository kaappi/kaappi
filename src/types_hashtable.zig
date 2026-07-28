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
