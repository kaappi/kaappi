const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;

// ---------------------------------------------------------------------------
// FFI types (C Foreign Function Interface)
// ---------------------------------------------------------------------------

pub const FfiType = enum(u8) {
    int, // c_int (i32)
    long, // c_long (i64)
    double, // f64
    float, // f32
    string, // [*:0]const u8
    pointer, // *anyopaque
    void_type, // void
    bool_type, // c_int (0/1)
    uint8, // u8
    int8, // i8
    int16, // i16
    int32, // i32
    int64, // i64
    uint16, // u16
    uint32, // u32
    uint64, // u64
    size_type, // usize
    char_type, // u8
};

pub const FfiLibrary = struct {
    header: Object,
    handle: ?*anyopaque,
    name: []const u8,
};

pub const FfiFunction = struct {
    header: Object,
    symbol: *anyopaque,
    library: Value,
    name: []const u8,
    param_types: []FfiType,
    return_type: FfiType,
    param_count: u8,
};

pub const FfiCallback = struct {
    header: Object,
    closure: Value,
    slot_index: u8,
    fn_ptr: *anyopaque,
    active: bool,
};
