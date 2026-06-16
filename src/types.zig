const std = @import("std");

/// A Scheme value packed into a 64-bit word.
///
/// Encoding (low bits):
///   bit 0 = 1:       fixnum, value = arithmetic shift right by 1
///   bits 0-2 = 000:  pointer to heap Object (8-byte aligned)
///   bits 0-1 = 10:   immediate (nil, bool, void, eof, char)
pub const Value = u64;

// ---------------------------------------------------------------------------
// Immediate constants
// ---------------------------------------------------------------------------

// Immediate layout: [payload:56][subtype:5][10]
// Subtypes: 0=nil, 1=bool, 2=void, 3=eof, 4=undefined, 5=char
pub const NIL: Value = 0b0_00000_10; // subtype 0, payload 0
pub const FALSE: Value = 0b0_00001_10; // subtype 1, payload 0
pub const TRUE: Value = 0b1_00001_10; // subtype 1, payload 1
pub const VOID: Value = 0b0_00010_10; // subtype 2
pub const EOF: Value = 0b0_00011_10; // subtype 3
pub const UNDEFINED: Value = 0b0_00100_10; // subtype 4

// ---------------------------------------------------------------------------
// Fixnum operations
// ---------------------------------------------------------------------------

pub fn makeFixnum(n: i64) Value {
    const unsigned: u64 = @bitCast(n);
    return (unsigned << 1) | 1;
}

pub fn toFixnum(v: Value) i64 {
    const signed: i64 = @bitCast(v);
    return signed >> 1;
}

pub fn isFixnum(v: Value) bool {
    return (v & 1) != 0;
}

// ---------------------------------------------------------------------------
// Pointer operations
// ---------------------------------------------------------------------------

pub fn isPointer(v: Value) bool {
    return (v & 0b111) == 0 and v != 0;
}

pub fn makePointer(ptr: *anyopaque) Value {
    return @intFromPtr(ptr);
}

pub fn toObject(v: Value) *Object {
    return @ptrFromInt(v);
}

// ---------------------------------------------------------------------------
// Immediate operations
// ---------------------------------------------------------------------------

pub fn isImmediate(v: Value) bool {
    return (v & 0b11) == 0b10;
}

pub fn isBool(v: Value) bool {
    return v == TRUE or v == FALSE;
}

pub fn isNil(v: Value) bool {
    return v == NIL;
}

pub fn makeChar(codepoint: u21) Value {
    return (@as(Value, codepoint) << 7) | 0b00101_10;
}

pub fn toChar(v: Value) u21 {
    return @truncate(v >> 7);
}

pub fn isChar(v: Value) bool {
    return (v & 0b1111111) == 0b00101_10;
}

pub fn isTruthy(v: Value) bool {
    return v != FALSE;
}

// ---------------------------------------------------------------------------
// Heap object types
// ---------------------------------------------------------------------------

pub const ObjectTag = enum(u5) {
    pair = 0,
    symbol = 1,
    string = 2,
    closure = 3,
    native_fn = 4,
    vector = 5,
    bytevector = 6,
    port = 7,
    record_type = 8,
    function = 9,
    flonum = 10,
    transformer = 11,
    error_object = 12,
    record_instance = 13,
    continuation = 14,
    multiple_values = 15,
    complex = 16,
    promise = 17,
    parameter = 18,
    ffi_library = 19,
    ffi_function = 20,
    hash_table = 21,
    bignum = 22,
    rational = 23,
};

pub const Object = struct {
    tag: ObjectTag,
    marked: bool = false,
    next: ?*Object = null,

    pub fn as(self: *Object, comptime T: type) *T {
        return @fieldParentPtr("header", self);
    }
};

pub const Pair = struct {
    header: Object,
    car: Value = NIL,
    cdr: Value = NIL,
};

pub const Symbol = struct {
    header: Object,
    name: []const u8,
};

pub const SchemeString = struct {
    header: Object,
    data: []u8,
    len: usize,
    immutable: bool = false,
};

pub const NativeFnType = *const fn (args: []const Value) anyerror!Value;

pub const NativeFn = struct {
    header: Object,
    func: NativeFnType,
    name: []const u8,
    arity: Arity,

    pub const Arity = union(enum) {
        exact: u8,
        variadic: u8, // minimum args
    };
};

pub const DebugLocal = struct {
    name: []const u8,
    slot: u8,
};

pub const Function = struct {
    header: Object,
    code: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    arity: u8,
    locals_count: u8 = 0,
    upvalue_count: u8 = 0,
    is_variadic: bool = false,
    name: ?[]const u8 = null,
    owns_name: bool = false,
    source_line: u32 = 0,
    source_name: ?[]const u8 = null,
    debug_locals: []DebugLocal = &.{},
    global_cache: ?[]Value = null,
};

pub const Closure = struct {
    header: Object,
    func: *Function,
    upvalues: []Value,
};

pub const Flonum = struct {
    header: Object,
    value: f64,
};

pub const Transformer = struct {
    header: Object,
    literals: []Value,
    patterns: []Value,
    templates: []Value,
    num_rules: u16,
};

pub const ErrorObject = struct {
    pub const ErrorType = enum(u8) { general, file, read };

    header: Object,
    message: Value, // string
    irritants: Value, // list
    error_type: ErrorType = .general,
};

pub const RecordType = struct {
    header: Object,
    name: []const u8,
    num_fields: u8,
};

pub const RecordInstance = struct {
    header: Object,
    record_type: *RecordType,
    fields: []Value,
};

pub const Vector = struct {
    header: Object,
    data: []Value,
};

pub const Bytevector = struct {
    header: Object,
    data: []u8,
};

pub const Promise = struct {
    header: Object,
    forced: bool,
    value: Value, // result after forcing, or the thunk before
};

pub const Port = struct {
    header: Object,
    fd: std.posix.fd_t,
    is_input: bool,
    is_output: bool,
    is_open: bool,
    name: []const u8,
    owns_name: bool, // if true, name is heap-allocated and must be freed
    peek_byte: ?u8, // 1-byte lookahead buffer for peek-char
    // String port fields:
    is_string_port: bool = false,
    string_data: ?[]const u8 = null, // for input string ports (owned copy)
    string_pos: usize = 0, // read position for input string ports
    string_out_buf: ?[]u8 = null, // for output string ports (owned, growable)
    string_out_len: usize = 0,
    string_out_cap: usize = 0,
};

// ---------------------------------------------------------------------------
// Continuation types (R7RS 6.10)
// ---------------------------------------------------------------------------

/// Saved call frame for continuation capture.
pub const SavedFrame = struct {
    closure: ?*Closure,
    native: ?*NativeFn,
    code: []const u8,
    ip: usize,
    base: u16,
    dst: u8,
};

/// Saved exception handler for continuation capture.
pub const SavedHandler = struct {
    handler: Value,
    frame_count: usize,
};

/// Saved dynamic-wind record.
pub const WindRecord = struct {
    before: Value,
    after: Value,
};

/// A captured continuation (R7RS call/cc).
/// Contains a snapshot of the VM state at the point of capture.
pub const Continuation = struct {
    header: Object,
    registers: []Value,
    frames: []SavedFrame,
    frame_count: usize,
    handlers: []SavedHandler,
    handler_count: usize,
    wind_records: []WindRecord,
    wind_count: usize,
    dst_reg: u8, // register offset within frame where result goes
    dst_base: u16, // base register of the return frame
    // Single backing allocation holding registers, frames, handlers and winds
    // contiguously. The four slices above are views into this buffer; it is
    // freed as one block on sweep. Empty for escape continuations.
    backing: []Value,
    // --- Escape continuations (call/ec) ---
    // An escape continuation captures no snapshot: it only records the stack
    // depths to unwind *back* to (the call/ec point is still live on the stack).
    // When is_escape is true the four slices above are empty and frame_count/
    // handler_count/wind_count are 0 (so GC mark loops are no-ops); the unwind
    // targets live in the target_* fields below. `valid` is cleared once the
    // call/ec call returns, after which invoking the continuation is an error.
    is_escape: bool = false,
    valid: bool = true,
    target_frame_count: usize = 0,
    target_wind_count: usize = 0,
    target_handler_count: usize = 0,
};

/// Multiple return values (R7RS values/call-with-values).
pub const MultipleValues = struct {
    header: Object,
    values: []Value,
};

/// Complex number (R7RS 6.2.6).
pub const Complex = struct {
    header: Object,
    real: f64,
    imag: f64,
};

/// Parameter object (R7RS make-parameter / parameterize).
pub const ParameterObject = struct {
    header: Object,
    value: Value,
    converter: Value, // NIL or a conversion procedure
};

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
};

pub const FfiLibrary = struct {
    header: Object,
    handle: ?*anyopaque,
    name: []const u8,
};

pub const FfiFunction = struct {
    header: Object,
    symbol: *anyopaque,
    name: []const u8,
    param_types: []FfiType,
    return_type: FfiType,
    param_count: u8,
};

// ---------------------------------------------------------------------------
// Hash table (SRFI-69)
// ---------------------------------------------------------------------------

pub const HashEntry = struct {
    key: Value,
    value: Value,
};

pub const HashTable = struct {
    header: Object,
    entries: []HashEntry,
    count: usize, // number of live entries
    capacity: usize, // length of entries slice
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

// ---------------------------------------------------------------------------
// Type predicates on Value
// ---------------------------------------------------------------------------

pub fn isPair(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .pair;
}

pub fn isSymbol(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .symbol;
}

pub fn isString(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .string;
}

pub fn isClosure(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .closure;
}

pub fn isNativeFn(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .native_fn;
}

pub fn isFunction(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .function;
}

pub fn isProcedure(v: Value) bool {
    return isClosure(v) or isNativeFn(v) or isContinuation(v) or isParameter(v) or isFfiFunction(v);
}

pub fn isContinuation(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .continuation;
}

pub fn isMultipleValues(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .multiple_values;
}

pub fn isFlonum(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .flonum;
}

pub fn isTransformer(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .transformer;
}

pub fn isErrorObject(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .error_object;
}

pub fn isRecordType(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .record_type;
}

pub fn isRecordInstance(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .record_instance;
}

pub fn isVector(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .vector;
}

pub fn toVector(v: Value) *Vector {
    return toObject(v).as(Vector);
}

pub fn isBytevector(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .bytevector;
}

pub fn toBytevector(v: Value) *Bytevector {
    return toObject(v).as(Bytevector);
}

pub fn isPromise(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .promise;
}

pub fn toPromise(v: Value) *Promise {
    return toObject(v).as(Promise);
}

pub fn isPort(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .port;
}

pub fn isComplex(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .complex;
}

pub fn toComplex(v: Value) *Complex {
    return toObject(v).as(Complex);
}

pub fn isParameter(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .parameter;
}

pub fn toParameter(v: Value) *ParameterObject {
    return toObject(v).as(ParameterObject);
}

pub fn isFfiLibrary(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .ffi_library;
}

pub fn isFfiFunction(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .ffi_function;
}

pub fn isHashTable(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .hash_table;
}

pub fn toHashTable(v: Value) *HashTable {
    return toObject(v).as(HashTable);
}

pub fn isBignum(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .bignum;
}

pub fn toBignum(v: Value) *Bignum {
    return toObject(v).as(Bignum);
}

pub fn isRational(v: Value) bool {
    if (isFixnum(v) or isBignum(v)) return true; // integers are rational
    return isPointer(v) and toObject(v).tag == .rational;
}

pub fn isRationalObj(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .rational;
}

pub fn toRational(v: Value) *Rational {
    return toObject(v).as(Rational);
}

pub fn isNumber(v: Value) bool {
    return isFixnum(v) or isFlonum(v) or isComplex(v) or isBignum(v) or isRationalObj(v);
}

pub fn toFlonum(v: Value) f64 {
    return toObject(v).as(Flonum).value;
}

pub fn toF64(v: Value) f64 {
    if (isFixnum(v)) return @floatFromInt(toFixnum(v));
    if (isFlonum(v)) return toFlonum(v);
    if (isRationalObj(v)) {
        const r = toRational(v);
        const n = toF64(r.numerator);
        const d = toF64(r.denominator);
        return n / d;
    }
    return 0.0;
}

// ---------------------------------------------------------------------------
// Pair accessors
// ---------------------------------------------------------------------------

pub fn car(v: Value) Value {
    return toObject(v).as(Pair).car;
}

pub fn cdr(v: Value) Value {
    return toObject(v).as(Pair).cdr;
}

pub fn setCar(v: Value, val: Value) void {
    toObject(v).as(Pair).car = val;
}

pub fn setCdr(v: Value, val: Value) void {
    toObject(v).as(Pair).cdr = val;
}

pub fn symbolName(v: Value) []const u8 {
    return toObject(v).as(Symbol).name;
}

// ---------------------------------------------------------------------------
// Bytecode opcodes
// ---------------------------------------------------------------------------

pub const OpCode = enum(u8) {
    load_const, // dst:u8, idx:u16
    load_nil, // dst:u8
    load_true, // dst:u8
    load_false, // dst:u8
    load_void, // dst:u8
    move, // dst:u8, src:u8
    get_global, // dst:u8, sym_idx:u16
    set_global, // sym_idx:u16, src:u8
    get_local, // dst:u8, slot:u8
    set_local, // slot:u8, src:u8
    get_upvalue, // dst:u8, idx:u8
    set_upvalue, // idx:u8, src:u8
    call, // base:u8, nargs:u8
    tail_call, // base:u8, nargs:u8
    @"return", // src:u8
    jump, // offset:i16
    jump_false, // test:u8, offset:i16
    jump_true, // test:u8, offset:i16
    closure, // dst:u8, idx:u16
    close_upvalue, // slot:u8
    cons, // dst:u8, car:u8, cdr:u8
    push_handler, // handler_reg:u8
    pop_handler, // (no operands)
    halt,
};

// ---------------------------------------------------------------------------
// List helpers
// ---------------------------------------------------------------------------

/// Count the length of a proper list. Returns null for improper lists.
pub fn listLength(v: Value) ?usize {
    var count: usize = 0;
    var current = v;
    while (current != NIL) {
        if (!isPair(current)) return null;
        count += 1;
        current = cdr(current);
    }
    return count;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "fixnum round-trip" {
    const values = [_]i64{ 0, 1, -1, 42, -42, 1000000, -1000000, std.math.maxInt(i63), std.math.minInt(i63) };
    for (values) |n| {
        const v = makeFixnum(n);
        try std.testing.expect(isFixnum(v));
        try std.testing.expect(!isPointer(v));
        try std.testing.expect(!isImmediate(v));
        try std.testing.expectEqual(n, toFixnum(v));
    }
}

test "immediate constants are distinct" {
    const imms = [_]Value{ NIL, FALSE, TRUE, VOID, EOF, UNDEFINED };
    for (imms, 0..) |a, i| {
        try std.testing.expect(isImmediate(a));
        try std.testing.expect(!isFixnum(a));
        for (imms, 0..) |b, j| {
            if (i != j) try std.testing.expect(a != b);
        }
    }
}

test "character round-trip" {
    const chars = [_]u21{ 'a', 'Z', 0x03BB, 0x1F600 }; // a, Z, lambda, emoji
    for (chars) |c| {
        const v = makeChar(c);
        try std.testing.expect(isChar(v));
        try std.testing.expect(isImmediate(v));
        try std.testing.expect(!isFixnum(v));
        try std.testing.expectEqual(c, toChar(v));
    }
}

test "truthiness" {
    try std.testing.expect(isTruthy(TRUE));
    try std.testing.expect(isTruthy(NIL)); // only #f is false in Scheme
    try std.testing.expect(isTruthy(makeFixnum(0)));
    try std.testing.expect(!isTruthy(FALSE));
}

test "nil is not a pointer" {
    try std.testing.expect(!isPointer(NIL));
    try std.testing.expect(isNil(NIL));
}
