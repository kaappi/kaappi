const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;

/// SRFI 160's homogeneous numeric vector element types, minus `u8` (which
/// stays a plain R7RS bytevector -- SRFI 160 explicitly recommends
/// u8vector/bytevector identity, and this codebase's pre-existing SRFI 4
/// port already relies on it).
pub const NumericElementKind = enum(u8) {
    s8,
    u16,
    s16,
    u32,
    s32,
    u64,
    s64,
    f32,
    f64,
    c64,
    c128,

    /// Byte width of one element. c64/c128 are 2 consecutive f32s/f64s
    /// (real, imag) packed contiguously -- never boxed inside the buffer.
    pub fn elementWidth(self: NumericElementKind) usize {
        return switch (self) {
            .s8 => 1,
            .u16, .s16 => 2,
            .u32, .s32, .f32 => 4,
            .u64, .s64, .f64, .c64 => 8,
            .c128 => 16,
        };
    }
};

/// A single new heap type covers all 11 kinds (rather than 11 parallel
/// ObjectTags) -- see NumericElementKind. Every field is raw numeric
/// bytes with zero nested `Value` pointers, so this is a GC-trivial leaf
/// type exactly like Bytevector: all three mark-graph switches in
/// gc_collect.zig get a no-op arm, only objectSize/freeObject/deep-copy
/// need real logic. No `shared`-buffer lever (Bytevector's KEP-0002 Lever
/// D) -- that's a channel-crossing optimization this type doesn't need.
pub const NumericVector = struct {
    header: Object,
    kind: NumericElementKind,
    data: []u8,
};

// ---------------------------------------------------------------------------
// Bignum (arbitrary-precision integer)
// ---------------------------------------------------------------------------

pub const Bignum = struct {
    header: Object,
    limbs: []u64, // little-endian limbs (magnitude)
    len: usize, // active limbs count
    positive: bool, // sign (true = positive/zero)
};

// ---------------------------------------------------------------------------
// Rational (exact fraction p/q, always in lowest terms, q > 1)
// ---------------------------------------------------------------------------

pub const Rational = struct {
    header: Object,
    numerator: Value, // fixnum or bignum
    denominator: Value, // fixnum or bignum (always positive, > 1)
};
