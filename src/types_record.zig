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
    /// type). RecordType is fully immutable after construction -- this is
    /// set once at allocation, never mutated -- so no write barrier is
    /// ever needed for any field on this struct.
    uid: ?[]const u8 = null,
    sealed: bool = false,
    is_opaque: bool = false,
};

pub const RecordInstance = struct {
    header: Object,
    record_type: *RecordType,
    fields: []Value,
};
