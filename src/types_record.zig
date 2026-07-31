const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;

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
};

pub const RecordInstance = struct {
    header: Object,
    record_type: *RecordType,
    fields: []Value,
};
