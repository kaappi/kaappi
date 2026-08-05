const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;

/// Source of `RecordType.identity`. Process-global and atomic because
/// SRFI-18 threads allocate record types concurrently on independent heaps
/// (each with its own GC), and the whole point of the counter is that no
/// two *distinct* types ever collide, whichever heap minted them. Starts at
/// 1 so a zero-initialised RecordType never accidentally matches a real one.
var next_identity: std.atomic.Value(u64) = .init(1);

/// Mints the identity for a freshly *defined* record type. A record type
/// COPIED across a thread boundary must not call this -- gc_deep_copy
/// carries the source's identity over instead (see `identity` below).
pub fn nextRecordTypeIdentity() u64 {
    return next_identity.fetchAdd(1, .monotonic);
}

/// The type-identity predicate behind `pt?`, `%record-ref`'s type check,
/// and SRFI 237's inheritance walk. Not pointer equality: a record type
/// that crosses a thread boundary is deep-copied into the receiving heap,
/// so the same type is represented by two distinct RecordType objects
/// (kaappi#1932). `identity` is what survives that copy.
pub fn sameRecordType(a: *const RecordType, b: *const RecordType) bool {
    if (a == b) return true;
    // 0 means "never went through the allocators", so it identifies nothing
    // -- two such types must not become interchangeable by both being 0.
    return a.identity != 0 and a.identity == b.identity;
}

pub const RecordType = struct {
    header: Object,
    name: []const u8,
    /// Total field count including inherited fields -- sizes
    /// RecordInstance.fields. Equals own_field_count for an R7RS record
    /// type (no parent).
    num_fields: u8,
    /// Length of own_field_names / own_field_mutable below. 0 for a plain
    /// R7RS record type, which doesn't track individual field metadata.
    own_field_count: u8 = 0,
    /// SRFI 237 inheritance. The only Value-bearing/heap-pointer field on
    /// this struct -- traced in gc_collect.zig's referencesYoung,
    /// markObjectContents, and markValueInner's worklist switch. Every
    /// other new field below is raw owned memory, same category as `name`
    /// already is, needing only objectSize/freeObject/deep-copy updates.
    parent: ?*RecordType = null,
    /// This type's OWN (non-inherited) field names, parallel to
    /// own_field_mutable. Owned strings, duped like `name`.
    own_field_names: [][]const u8 = &.{},
    own_field_mutable: []bool = &.{},
    /// SRFI 237 nongenerative identity. Owned string; null means
    /// generative (every evaluation of the defining form is a distinct
    /// type). No field on this struct ever needs a write barrier: `parent`
    /// is the only heap pointer and it is set once at allocation, and the
    /// one field written afterwards (`has_protocol`) is a plain bool.
    uid: ?[]const u8 = null,
    sealed: bool = false,
    is_opaque: bool = false,
    /// True when this type was defined by a syntactic `define-record-type`
    /// carrying a `(protocol ...)` clause. The protocol itself is not stored
    /// -- it is already baked into the exposed constructor the desugarer
    /// generates -- so this only records THAT there is one.
    ///
    /// SRFI 237 keeps a protocol on the record DESCRIPTOR, not on the rtd,
    /// which is why a procedurally created rtd always leaves this false. It
    /// exists so `(srfi 237)`'s `%fresh-rcd` can tell when deriving a
    /// protocol-less record descriptor from a bare rtd would silently skip
    /// that protocol, and refuse instead of constructing a wrong record
    /// (kaappi#1974). Set by vm_records.zig right after the rtd is created
    /// or reused, and only ever set to true -- a nongenerative uid shared by
    /// definitions that disagree about having a protocol stays conservative,
    /// because refusing is recoverable and a wrong field value is not.
    has_protocol: bool = false,
    /// Process-globally unique, assigned once by `nextRecordTypeIdentity` at
    /// definition and PRESERVED verbatim by gc_deep_copy. This is what makes
    /// a record type still be the same type after crossing an SRFI-18 thread
    /// boundary: the copy lands in another heap and therefore has another
    /// address, so the RecordType *pointer* cannot be the identity
    /// (kaappi#1932). Compare with `sameRecordType`, never with `==`.
    ///
    /// Only 0 for a RecordType built outside the GC allocators (none in
    /// shipped code); `sameRecordType` treats 0 as identifying nothing, so
    /// such a type matches only itself, by address.
    identity: u64 = 0,
};

pub const RecordInstance = struct {
    header: Object,
    record_type: *RecordType,
    fields: []Value,
};
