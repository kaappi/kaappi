const builtin = @import("builtin");
const std = @import("std");
const build_options = @import("build_options");

/// A Scheme value packed into a 64-bit word (NaN-boxing).
///
/// Encoding:
///   v < NANBOX_THRESHOLD:          flonum (raw IEEE 754 f64 bits)
///   (v >> 48) == 0xFFFC:           pointer to heap Object (48-bit address)
///   (v >> 48) == 0xFFFD:           fixnum (i48, sign-extended)
///   (v >> 48) == 0xFFFE:           immediate (nil, bool, void, eof, char)
///
/// NaN values from f64 are canonicalized to 0x7FF8000000000000.
pub const Value = u64;

// NaN-boxing tag constants
const NANBOX_PTR: u64 = 0xFFFC000000000000;
const NANBOX_FIX: u64 = 0xFFFD000000000000;
const NANBOX_IMM: u64 = 0xFFFE000000000000;
const NANBOX_THRESHOLD: u64 = 0xFFFC000000000000;
const NANBOX_PAYLOAD: u64 = 0x0000FFFFFFFFFFFF;
const CANONICAL_NAN: u64 = 0x7FF8000000000000;

// ---------------------------------------------------------------------------
// Immediate constants
// ---------------------------------------------------------------------------

pub const NIL: Value = NANBOX_IMM | 0;
pub const FALSE: Value = NANBOX_IMM | 1;
pub const TRUE: Value = NANBOX_IMM | 2;
pub const VOID: Value = NANBOX_IMM | 3;
pub const EOF: Value = NANBOX_IMM | 4;
pub const UNDEFINED: Value = NANBOX_IMM | 5;

// ---------------------------------------------------------------------------
// Fixnum operations (i48: ±140 trillion)
// ---------------------------------------------------------------------------

pub fn makeFixnum(n: i64) Value {
    const unsigned: u64 = @bitCast(n);
    return NANBOX_FIX | (unsigned & NANBOX_PAYLOAD);
}

pub fn toFixnum(v: Value) i64 {
    const payload: u48 = @truncate(v);
    return @as(i64, @as(i48, @bitCast(payload)));
}

pub fn isFixnum(v: Value) bool {
    return (v >> 48) == 0xFFFD;
}

// ---------------------------------------------------------------------------
// Pointer operations (48-bit address)
// ---------------------------------------------------------------------------

pub fn isPointer(v: Value) bool {
    return (v >> 48) == 0xFFFC;
}

pub fn makePointer(ptr: *anyopaque) Value {
    return NANBOX_PTR | @as(u64, @intFromPtr(ptr));
}

pub fn toObject(v: Value) *Object {
    return @ptrFromInt(@as(usize, @truncate(v & NANBOX_PAYLOAD)));
}

// ---------------------------------------------------------------------------
// Immediate operations
// ---------------------------------------------------------------------------

pub fn isImmediate(v: Value) bool {
    return (v >> 48) == 0xFFFE;
}

pub fn isBool(v: Value) bool {
    return v == TRUE or v == FALSE;
}

pub fn isNil(v: Value) bool {
    return v == NIL;
}

pub fn makeChar(codepoint: u21) Value {
    return NANBOX_IMM | (@as(Value, codepoint) << 8) | 0x80;
}

pub fn toChar(v: Value) u21 {
    return @truncate((v >> 8) & 0x1FFFFF);
}

pub fn isChar(v: Value) bool {
    return (v >> 48) == 0xFFFE and (v & 0x80) != 0;
}

pub fn isTruthy(v: Value) bool {
    return v != FALSE;
}

pub fn typeName(val: Value) []const u8 {
    if (isFixnum(val)) return "integer";
    if (val == NIL) return "nil";
    if (val == TRUE or val == FALSE) return "boolean";
    if (val == VOID) return "void";
    if (val == EOF) return "eof-object";
    if (isChar(val)) return "char";
    if (!isPointer(val)) return "unknown";
    const obj = toObject(val);
    return switch (obj.tag) {
        .pair => "pair",
        .symbol => "symbol",
        .string => "string",
        .closure, .native_fn, .native_closure => "procedure",
        .function => "function",
        .vector => "vector",
        .bytevector => "bytevector",
        .port => "port",
        .flonum => "number",
        .complex => "complex",
        .transformer => "syntax",
        .error_object => "error",
        .record_type => "record-type",
        .record_instance => "record",
        .continuation => "continuation",
        .multiple_values => "values",
        .promise => "promise",
        .parameter => "parameter",
        .rational => "rational",
        .bignum => "integer",
        .hash_table => "hash-table",
        .ffi_library => "ffi-library",
        .ffi_function => "ffi-function",
        .ffi_callback => "ffi-callback",
        .fiber => "fiber",
        .channel => "channel",
        .mutex => "mutex",
        .condition_variable => "condition-variable",
        .srfi18_time => "time",
        .file_info => "file-info",
        .user_info => "user-info",
        .group_info => "group-info",
        .directory_object => "directory",
        .random_source => "random-source",
        .scheme_environment => "environment",
    };
}

// ---------------------------------------------------------------------------
// Heap object types
// ---------------------------------------------------------------------------

pub const ObjectTag = enum(u6) {
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
    file_info = 24,
    user_info = 25,
    group_info = 26,
    directory_object = 27,
    random_source = 28,
    ffi_callback = 29,
    fiber = 30,
    channel = 31,
    mutex = 32,
    condition_variable = 33,
    srfi18_time = 34,
    native_closure = 35,
    scheme_environment = 36,
};

pub const Object = struct {
    tag: ObjectTag,
    flags: Flags = .{},
    /// Id of the GC that tracks (and will free) this object. Marking skips
    /// objects owned by another GC: an SRFI-18 child thread's heap can
    /// reference parent-heap objects (shared globals, interned symbols,
    /// closures being executed), and writing mark bits on those would corrupt
    /// the parent GC's mark state — under-marking sweeps live objects (#958).
    /// Fits in existing struct padding, so it adds no size.
    owner: u32 = 0,
    next: ?*Object = null,
    // Force 8-byte alignment so all heap objects satisfy the pointer tag
    // check (v & 7 == 0). Without this, wasm32 allocators may return
    // 4-byte-aligned pointers for types that lack u64 fields (Symbol, etc.).
    _align: Align = .{},

    const Flags = packed struct(u8) {
        marked: bool = false,
        generation: u1 = 0,
        survive_count: u2 = 0,
        immutable: bool = false,
        _pad: u3 = 0,
    };
    const Align = if (@alignOf(?*Object) < 8) struct { _: u64 align(8) = 0 } else struct {};

    fn expectedTag(comptime T: type) ?ObjectTag {
        return switch (T) {
            Pair => .pair,
            Symbol => .symbol,
            SchemeString => .string,
            Closure => .closure,
            NativeFn => .native_fn,
            NativeClosure => .native_closure,
            Vector => .vector,
            Bytevector => .bytevector,
            Port => .port,
            RecordType => .record_type,
            Function => .function,
            Flonum => .flonum,
            Transformer => .transformer,
            ErrorObject => .error_object,
            RecordInstance => .record_instance,
            Continuation => .continuation,
            MultipleValues => .multiple_values,
            Complex => .complex,
            Promise => .promise,
            ParameterObject => .parameter,
            FfiLibrary => .ffi_library,
            FfiFunction => .ffi_function,
            FfiCallback => .ffi_callback,
            HashTable => .hash_table,
            Bignum => .bignum,
            Rational => .rational,
            FileInfo => .file_info,
            UserInfo => .user_info,
            GroupInfo => .group_info,
            DirectoryObject => .directory_object,
            RandomSource => .random_source,
            Channel => .channel,
            Mutex => .mutex,
            ConditionVariable => .condition_variable,
            Srfi18Time => .srfi18_time,
            SchemeEnvironment => .scheme_environment,
            else => null,
        };
    }

    pub fn as(self: *Object, comptime T: type) *T {
        if (builtin.mode == .Debug) {
            if (comptime expectedTag(T)) |expected| {
                std.debug.assert(self.tag == expected);
            }
        }
        // Not a plain @ptrCast: "auto"-layout structs (every T here — none
        // are extern) give Zig no guarantee that `header: Object` sits at
        // byte offset 0, only that it's declared first. @fieldParentPtr
        // computes the real offset regardless (see makePointer(&x.header)
        // call sites, which is what self actually points at).
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
};

pub const NativeFnType = *const fn (args: []const Value) anyerror!Value;

pub const NativeFn = struct {
    header: Object,
    func: NativeFnType,
    name: []const u8,
    arity: Arity,

    profile_calls: u64 = 0,
    profile_time_ns: u64 = 0,
    profile_alloc_bytes: u64 = 0,

    pub const Arity = union(enum) {
        exact: u8,
        variadic: u8, // minimum args
    };
};

pub const NativeClosureFnType = *const fn (?*@import("vm.zig").VM, [*]const Value, u64, [*]const Value) callconv(.c) u64;

pub const NativeClosure = struct {
    header: Object,
    fn_ptr: NativeClosureFnType,
    upvalues: []Value,
    arity: u8,
    name: []const u8,
};

pub const DebugLocal = struct {
    name: []const u8,
    slot: u16,
};

pub const LineEntry = struct {
    offset: u16,
    line: u32,
};

pub const Function = struct {
    header: Object,
    code: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    arity: u8,
    locals_count: u16 = 0,
    upvalue_count: u16 = 0,
    is_variadic: bool = false,
    name: ?[]const u8 = null,
    owns_name: bool = false,
    source_line: u32 = 0,
    source_name: ?[]const u8 = null,
    debug_locals: []DebugLocal = &.{},
    line_table: std.ArrayList(LineEntry) = .empty,
    global_cache: ?[]Value = null,
    cache_version: u32 = 0,
    env: ?*std.StringHashMap(Value) = null,
    env_val: Value = NIL,
    restricted_globals: bool = false,
    profile_instrs: u64 = 0,
    profile_calls: u64 = 0,
    profile_time_ns: u64 = 0,
    profile_inclusive_ns: u64 = 0,
    profile_alloc_bytes: u64 = 0,

    pub fn lineForOffset(self: *const Function, offset: usize) u32 {
        var best: u32 = self.source_line;
        for (self.line_table.items) |entry| {
            if (entry.offset <= offset) best = entry.line else break;
        }
        return best;
    }
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

pub const CapturedLocal = struct {
    name: []const u8,
    slot: u16,
};

pub const Transformer = struct {
    header: Object,
    literals: []Value,
    patterns: []Value,
    templates: []Value,
    num_rules: u16,
    captured_locals: []CapturedLocal = &.{},
    def_env: ?*std.StringHashMap(Value) = null,
    def_env_val: Value = NIL,
    custom_ellipsis: ?[]const u8 = null,
    literal_bound: []u32 = &.{},
    let_syntax_peer_names: [][]const u8 = &.{},
    let_syntax_peer_vals: []Value = &.{},
    bound_free_refs: [][]const u8 = &.{},
};

pub const ErrorObject = struct {
    pub const ErrorType = enum(u8) {
        general,
        file,
        read,
        join_timeout,
        abandoned_mutex,
        terminated_thread,
        uncaught_exception,
    };

    header: Object,
    message: Value, // string
    irritants: Value, // list
    error_type: ErrorType = .general,
    uncaught_reason: Value = VOID,
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
    forcing: bool = false,
    value: Value,
};

pub const Port = struct {
    header: Object,
    fd: std.posix.fd_t,
    is_input: bool,
    is_output: bool,
    is_open: bool,
    name: []const u8,
    owns_name: bool, // if true, name is heap-allocated and must be freed
    peek_byte: ?u8, // lead byte lookahead for peek-char
    peek_extra: [3]u8 = .{ 0, 0, 0 }, // UTF-8 continuation bytes from peek-char
    peek_extra_len: u2 = 0,
    // String port fields:
    is_string_port: bool = false,
    string_data: ?[]const u8 = null, // for input string ports (owned copy)
    string_pos: usize = 0, // read position for input string ports
    string_out_buf: ?[]u8 = null, // for output string ports (owned, growable)
    string_out_len: usize = 0,
    string_out_cap: usize = 0,
    is_binary: bool = false,
    read_buf: ?[]u8 = null,
    read_buf_len: usize = 0,
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
    base: u32,
    dst: u16,
    saved_wind_count: u16,
    // Mirrors CallFrame.returns_to_native (see vm.zig): the frame's result
    // belongs to a re-entrant native Zig caller, so returning it into a
    // caller frame register after that native has died is an error.
    returns_to_native: bool,
    // Frame birth id (see CallFrame.seq in vm.zig). The u64 also forces
    // 8-byte alignment on wasm32, keeping the struct size a multiple of
    // @sizeOf(Value) without manual padding.
    seq: u64,
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

// --- Live execution frame types (used by VM, fiber, and GC) ---

pub const INITIAL_FRAME_CAPACITY: usize = build_options.max_frames;
pub const INITIAL_REGISTER_CAPACITY: usize = build_options.max_registers;
pub const MAX_FRAME_LIMIT: usize = 32768;
pub const MAX_REGISTER_LIMIT: usize = 65536;
pub const MAX_HANDLERS = 64;
pub const MAX_WINDS = 64;

/// Per-fiber initial storage (KEP-0001 Phase 2, resolved question 5) —
/// deliberately much smaller than the VM's own INITIAL_REGISTER_CAPACITY/
/// INITIAL_FRAME_CAPACITY. Fibers grow their own arrays geometrically as
/// needed (see FiberScheduler.saveCurrentFiber); most fibers never touch
/// more than a handful of frames, so starting small keeps per-fiber
/// preallocation cheap even with thousands of concurrently-live fibers.
pub const INITIAL_FIBER_REGISTER_CAPACITY: usize = 256;
pub const INITIAL_FIBER_FRAME_CAPACITY: usize = 32;

pub const ExceptionHandler = struct {
    handler: Value,
    frame_count: usize,
};

pub const CallFrame = struct {
    closure: ?*Closure,
    native: ?*NativeFn = null,
    code: []const u8,
    ip: usize,
    base: u32,
    dst: u16,
    saved_wind_count: u16 = 0,
    returns_to_native: bool = false,
    seq: u64 = 0,

    pub fn frameWindow(self: CallFrame) usize {
        return if (self.closure) |cls| blk: {
            const lc = cls.func.locals_count;
            break :blk if (lc == 0) 256 else @as(usize, lc);
        } else 256;
    }
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
    dst_reg: u16, // register offset within frame where result goes
    dst_base: u32, // base register of the return frame
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
    exact_real: bool = false,
    exact_imag: bool = false,
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

pub const Channel = struct {
    header: Object,
    head: Value,
    tail: Value,
};

// ---------------------------------------------------------------------------
// SRFI-18 types (mutex, condition variable, time)
// ---------------------------------------------------------------------------

pub const Mutex = struct {
    header: Object,
    name: Value,
    owner: Value,
    locked: bool,
    abandoned: bool,
    specific: Value,
};

pub const ConditionVariable = struct {
    header: Object,
    name: Value,
    specific: Value,
    // Bumped (atomically) by condition-variable-signal!/-broadcast!. Each OS
    // thread runs its own independent FiberScheduler, so a waiter parked by a
    // *different* thread never observes that thread's local wakeOneCondVarWaiter/
    // wakeAllCondVarWaiters bookkeeping; polling this counter is how a
    // cross-thread waiter detects a signal happened.
    signal_generation: u64 = 0,
};

pub const TimeType = enum(u8) {
    utc,
    tai,
    monotonic,
    duration,
};

pub const Srfi18Time = struct {
    header: Object,
    seconds: i64,
    nanoseconds: i64,
    time_type: TimeType,
};

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

pub const FileInfo = struct {
    header: Object,
    size: i64,
    mtime: i64,
    atime: i64,
    ctime: i64,
    dev: i64,
    ino: i64,
    nlinks: i64,
    rdev: i64,
    blksize: i64,
    blocks: i64,
    mode: u32,
    uid: u32,
    gid: u32,
    file_type: FileType,

    pub const FileType = enum(u8) { regular, directory, symlink, fifo, socket, char_device, block_device, other };
};

pub const UserInfo = struct {
    header: Object,
    name: []const u8,
    uid: u32,
    gid: u32,
    home_dir: []const u8,
    shell: []const u8,
    full_name: []const u8,
};

pub const GroupInfo = struct {
    header: Object,
    name: []const u8,
    gid: u32,
};

pub const DirectoryObject = struct {
    header: Object,
    dir: ?*anyopaque,
    include_dotfiles: bool,
};

pub const RandomSource = struct {
    header: Object,
    prng: std.Random.DefaultPrng,
};

pub const SchemeEnvironment = struct {
    header: Object,
    env: *std.StringHashMap(Value),
    owned: bool = true, // false for interaction-environment (don't free the map)
    immutable: bool = false, // true for (environment ...) per R7RS 6.12
};

// ---------------------------------------------------------------------------
// Type predicates on Value
// ---------------------------------------------------------------------------

pub fn isPair(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .pair;
}

pub fn toPair(v: Value) *Pair {
    return toObject(v).as(Pair);
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

pub fn toClosure(v: Value) *Closure {
    return toObject(v).as(Closure);
}

pub fn isNativeFn(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .native_fn;
}

pub fn toNativeFn(v: Value) *NativeFn {
    return toObject(v).as(NativeFn);
}

pub fn isNativeClosure(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .native_closure;
}

pub fn isFunction(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .function;
}

pub fn isProcedure(v: Value) bool {
    return isClosure(v) or isNativeFn(v) or isNativeClosure(v) or isContinuation(v) or isParameter(v) or isFfiFunction(v);
}

pub fn isContinuation(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .continuation;
}

pub fn toContinuation(v: Value) *Continuation {
    return toObject(v).as(Continuation);
}

pub fn isMultipleValues(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .multiple_values;
}

pub fn isFlonum(v: Value) bool {
    return v < NANBOX_THRESHOLD;
}

pub fn makeFlonum(f: f64) Value {
    if (std.math.isNan(f)) return CANONICAL_NAN;
    return @bitCast(f);
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

pub fn isFfiCallback(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .ffi_callback;
}

pub fn isFiber(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .fiber;
}

pub fn isChannel(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .channel;
}

pub fn isMutex(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .mutex;
}

pub fn toMutex(v: Value) *Mutex {
    return toObject(v).as(Mutex);
}

pub fn isConditionVariable(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .condition_variable;
}

pub fn toConditionVariable(v: Value) *ConditionVariable {
    return toObject(v).as(ConditionVariable);
}

pub fn isSrfi18Time(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .srfi18_time;
}

pub fn toSrfi18Time(v: Value) *Srfi18Time {
    return toObject(v).as(Srfi18Time);
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

pub fn isFileInfo(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .file_info;
}

pub fn toFileInfo(v: Value) *FileInfo {
    return toObject(v).as(FileInfo);
}

pub fn isUserInfo(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .user_info;
}

pub fn toUserInfo(v: Value) *UserInfo {
    return toObject(v).as(UserInfo);
}

pub fn isGroupInfo(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .group_info;
}

pub fn toGroupInfo(v: Value) *GroupInfo {
    return toObject(v).as(GroupInfo);
}

pub fn isDirectoryObject(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .directory_object;
}

pub fn toDirectoryObject(v: Value) *DirectoryObject {
    return toObject(v).as(DirectoryObject);
}

pub fn isRandomSource(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .random_source;
}

pub fn isEnvironment(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .scheme_environment;
}

pub fn toEnvironment(v: Value) *SchemeEnvironment {
    return toObject(v).as(SchemeEnvironment);
}

pub fn isNumber(v: Value) bool {
    return isFixnum(v) or isFlonum(v) or isComplex(v) or isBignum(v) or isRationalObj(v);
}

pub fn toFlonum(v: Value) f64 {
    return @bitCast(v);
}

pub fn toF64(v: Value) f64 {
    if (isFixnum(v)) return @floatFromInt(toFixnum(v));
    if (isFlonum(v)) return toFlonum(v);
    if (isBignum(v)) return bignumToF64(toBignum(v));
    if (isRationalObj(v)) {
        const r = toRational(v);
        const n = toF64(r.numerator);
        const d = toF64(r.denominator);
        return n / d;
    }
    return 0.0;
}

fn bignumToF64(bn: *const Bignum) f64 {
    if (bn.len == 0) return 0.0;
    if (bn.len == 1) {
        const r: f64 = @floatFromInt(bn.limbs[0]);
        return if (bn.positive) r else -r;
    }
    const hi = bn.limbs[bn.len - 1];
    const lo = bn.limbs[bn.len - 2];
    var sticky: u64 = 0;
    for (bn.limbs[0 .. bn.len - 2]) |limb| sticky |= limb;
    const lo_adj: u64 = if (sticky != 0 and lo & 1 == 0) lo | 1 else lo;
    const combined: u128 = (@as(u128, hi) << 64) | @as(u128, lo_adj);
    var result: f64 = @floatFromInt(combined);
    const remaining: u32 = @intCast((bn.len - 2) * 64);
    const scale: f64 = std.math.scalbn(@as(f64, 1.0), @as(i32, @intCast(remaining)));
    result *= scale;
    if (!bn.positive) result = -result;
    return result;
}

// ---------------------------------------------------------------------------
// Pair accessors
// ---------------------------------------------------------------------------

pub fn car(v: Value) Value {
    return toPair(v).car;
}

pub fn cdr(v: Value) Value {
    return toPair(v).cdr;
}

pub fn setCar(v: Value, val: Value) void {
    toPair(v).car = val;
}

pub fn setCdr(v: Value, val: Value) void {
    toPair(v).cdr = val;
}

pub fn symbolName(v: Value) []const u8 {
    return toObject(v).as(Symbol).name;
}

pub fn stripHygienicPrefix(name: []const u8) []const u8 {
    var n = name;
    while (std.mem.startsWith(u8, n, "__hyg_")) {
        if (std.mem.indexOfScalar(u8, n[6..], '_')) |sep| {
            n = n[6 + sep + 1 ..];
        } else break;
    }
    return n;
}

pub fn isContinuationBarrier(name: []const u8) bool {
    return std.mem.eql(u8, name, "call-with-current-continuation") or
        std.mem.eql(u8, name, "call/cc") or
        std.mem.eql(u8, name, "call/ec") or
        std.mem.eql(u8, name, "call-with-escape-continuation") or
        std.mem.eql(u8, name, "call-with-values") or
        std.mem.eql(u8, name, "dynamic-wind") or
        std.mem.eql(u8, name, "with-exception-handler");
}

// ---------------------------------------------------------------------------
// Box helpers (upvalue box = pair whose cdr is VOID)
// ---------------------------------------------------------------------------

pub fn isBox(v: Value) bool {
    return isPair(v) and cdr(v) == VOID;
}

pub fn boxGet(v: Value) Value {
    return toPair(v).car;
}

pub fn boxSet(v: Value, val: Value) void {
    toPair(v).car = val;
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
    define_global, // sym_idx:u16, src:u8
    tail_apply, // base:u8, nargs:u8
    get_upvalue, // dst:u8, idx:u8
    set_upvalue, // idx:u8, src:u8
    call, // base:u8, nargs:u8
    tail_call, // base:u8, nargs:u8
    @"return", // src:u8
    jump, // offset:i16
    jump_false, // test:u8, offset:i16
    jump_true, // test:u8, offset:i16
    closure, // dst:u8, idx:u16
    cons, // dst:u8, car:u8, cdr:u8
    push_handler, // handler_reg:u8
    pop_handler, // (no operands)
    halt,
    call_global, // base:u8, sym_idx:u16, nargs:u8
    tail_call_global, // base:u8, sym_idx:u16, nargs:u8
    box_local, // reg:u8 — wrap register value in a pair (box) for shared mutation
    get_box_local, // dst:u8, reg:u8 — read car of boxed register
    set_box_local, // reg:u8, src:u8 — set car of boxed register
    self_tail_call, // base:u8, nargs:u8
    tail_call_cc, // base:u16, dst:u16 (receiver at base+0; captures continuation at dst, tail-calls receiver)
    tail_eval, // base:u8, nargs:u8 (expr at base+0, optional env at base+1; compiles and tail-calls)
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
    const values = [_]i64{ 0, 1, -1, 42, -42, 1000000, -1000000, std.math.maxInt(i48), std.math.minInt(i48) };
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

pub const platform_features = [_][]const u8{ "r7rs", "kaappi", "ieee-float", "posix", "exact-closed", "exact-complex" };

test "nil is not a pointer" {
    try std.testing.expect(!isPointer(NIL));
    try std.testing.expect(isNil(NIL));
}
