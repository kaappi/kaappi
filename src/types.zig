const builtin = @import("builtin");
const std = @import("std");

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

/// Build a heap Value from the address of a heap struct's `header` field:
/// `makePointer(&x.header)`. The payload is always the header address —
/// `toObject` reads it back as `*Object` and `Object.as()` recovers the
/// enclosing struct via @fieldParentPtr — so heap structs stay free to
/// gain or reorder fields (Zig's auto layout does not keep `header` at
/// byte offset 0; it once silently moved Port's to offset 48, #1618).
/// Taking `*Object` rather than `*anyopaque` makes passing the struct
/// pointer itself a compile error instead of latent Value corruption.
pub fn makePointer(ptr: *Object) Value {
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
        .ephemeron => "ephemeron",
        .guardian => "guardian",
        .transport_cell => "transport-cell",
        .numeric_vector => "numeric-vector",
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
    // SRFI-254 weak references. `ephemeron` and `guardian` are the two types
    // the garbage collector treats specially (see gc_collect.processWeakRefs);
    // `transport_cell` is an ordinary strong pair on Kaappi's non-moving GC.
    ephemeron = 37,
    guardian = 38,
    transport_cell = 39,
    // SRFI 160: homogeneous numeric vectors other than u8 (which stays a
    // plain bytevector alias, per SRFI 160's own recommended identity).
    numeric_vector = 40,
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
    /// In Debug/gc-stress builds, freeing the object stamps this field with
    /// `memory.FREED_OWNER` so a later mark of the dead header panics
    /// deterministically instead of being skipped as foreign (#1687).
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
            Ephemeron => .ephemeron,
            Guardian => .guardian,
            TransportCell => .transport_cell,
            NumericVector => .numeric_vector,
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
        // computes the real offset regardless — the inverse of
        // makePointer(&x.header), which is what self actually points at.
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
    /// Interned symbols (the common case) live in the GC's symbol table and are
    /// unique per name, so pointer identity == name identity. Uninterned symbols
    /// (SRFI 258) bypass that table: each is a fresh object never `eqv?` to any
    /// other symbol, even one with the same name. The flag is the only thing that
    /// distinguishes the two — equality already works by pointer identity alone.
    interned: bool = true,
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

/// A source span in 1-based `(line, col)` coordinates, half-open at the end
/// (`end_line:end_col` points just past the last character). A zero `line`
/// means "unknown" — the same sentinel `Function.source_line` has always used.
/// `end_line == 0` means only the start is known (the reader/compiler fills the
/// end in for datum forms; runtime debug info records the start only). Threaded
/// from the reader through IR into diagnostics (kaappi#1506).
pub const Span = struct {
    line: u32 = 0,
    col: u32 = 0,
    end_line: u32 = 0,
    end_col: u32 = 0,

    /// The start position is known (a datum was located in source).
    pub fn known(self: Span) bool {
        return self.line > 0;
    }

    /// The end position is known, so a full range (not just a point) exists.
    pub fn hasEnd(self: Span) bool {
        return self.end_line > 0;
    }
};

/// One entry in a function's line table: at bytecode `offset`, source position
/// is `line:col` (both 1-based). Runtime error reports read the start position
/// via `Function.locForOffset`; end positions are not carried in bytecode debug
/// info (only reader/compile diagnostics need them — kaappi#1506).
pub const LineEntry = struct {
    offset: u16,
    line: u32,
    col: u32 = 0,
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
    // `env` is authoritative: a name missing from it must not fall back to
    // vm.globals. Set for an R7RS restricted environment ((environment ...),
    // null-environment, (eval expr env)) and *not* for a library body, whose
    // env is only what it imported — see compiler.EnvKind. A property of the
    // environment, so every function compiled inside one inherits it
    // (Compiler.initChild); deriving it per-function made the same reference
    // resolve or not by syntactic position (kaappi#1860).
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

    /// The `(line, col)` of the instruction at `offset`, from the line table.
    /// Both 1-based; `col == 0` when no column was recorded (e.g. a function
    /// with only a `source_line`). Used by the runtime error path to report
    /// `file:line:col` (kaappi#1506).
    pub fn locForOffset(self: *const Function, offset: usize) struct { line: u32, col: u32 } {
        var line: u32 = self.source_line;
        var col: u32 = 0;
        for (self.line_table.items) |entry| {
            if (entry.offset <= offset) {
                line = entry.line;
                col = entry.col;
            } else break;
        }
        return .{ .line = line, .col = col };
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

const types_macro = @import("types_macro.zig");
pub const CapturedLocal = types_macro.CapturedLocal;
pub const TransformerKind = types_macro.TransformerKind;
pub const Transformer = types_macro.Transformer;

const types_error = @import("types_error.zig");
pub const ErrorObject = types_error.ErrorObject;

const types_record = @import("types_record.zig");
pub const RecordType = types_record.RecordType;
pub const RecordInstance = types_record.RecordInstance;

pub const Vector = struct {
    header: Object,
    data: []Value,
};

pub const Bytevector = struct {
    header: Object,
    data: []u8,
    /// Lever D (KEP-0002 Phase 7, kaappi#1472): when non-null, `data` is
    /// borrowed from a refcounted immutable `shared_buffer.SharedBuffer` (this
    /// bytevector holds one reference) rather than owned -- so a large payload
    /// crossing a channel is shared, not re-copied. Kept opaque so types.zig,
    /// the dependency-free base layer, doesn't import a feature module (the same
    /// precedent as Channel.shared / FfiLibrary.handle). freeObject releases the
    /// reference; a mutator first calls GC.unshareBytevector (copy-on-write).
    /// Always null in the shipped default (lever `none`).
    shared: ?*anyopaque = null,
};

const types_numeric = @import("types_numeric.zig");
pub const NumericElementKind = types_numeric.NumericElementKind;
pub const NumericVector = types_numeric.NumericVector;

pub const Promise = struct {
    header: Object,
    forced: bool,
    forcing: bool = false,
    value: Value,
};

const types_port = @import("types_port.zig");
pub const Port = types_port.Port;
pub const Codec = types_port.Codec;
pub const EolStyle = types_port.EolStyle;
pub const ErrorMode = types_port.ErrorMode;
pub const TranscodeState = types_port.TranscodeState;
pub const CustomBacking = types_port.CustomBacking;
pub const RandomKind = types_port.RandomKind;
pub const RandomGen = types_port.RandomGen;

const types_continuation = @import("types_continuation.zig");
pub const SavedFrame = types_continuation.SavedFrame;
pub const SavedHandler = types_continuation.SavedHandler;
pub const WindRecord = types_continuation.WindRecord;
pub const INITIAL_FRAME_CAPACITY = types_continuation.INITIAL_FRAME_CAPACITY;
pub const INITIAL_REGISTER_CAPACITY = types_continuation.INITIAL_REGISTER_CAPACITY;
pub const MAX_FRAME_LIMIT = types_continuation.MAX_FRAME_LIMIT;
pub const MAX_REGISTER_LIMIT = types_continuation.MAX_REGISTER_LIMIT;
pub const MAX_HANDLERS = types_continuation.MAX_HANDLERS;
pub const MAX_WINDS = types_continuation.MAX_WINDS;
pub const INITIAL_FIBER_REGISTER_CAPACITY = types_continuation.INITIAL_FIBER_REGISTER_CAPACITY;
pub const INITIAL_FIBER_FRAME_CAPACITY = types_continuation.INITIAL_FIBER_FRAME_CAPACITY;
pub const ExceptionHandler = types_continuation.ExceptionHandler;
pub const CallFrame = types_continuation.CallFrame;
pub const Continuation = types_continuation.Continuation;
pub const MultipleValues = types_continuation.MultipleValues;

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

const types_ffi = @import("types_ffi.zig");
pub const FfiType = types_ffi.FfiType;
pub const FfiLibrary = types_ffi.FfiLibrary;
pub const FfiFunction = types_ffi.FfiFunction;
pub const FfiCallback = types_ffi.FfiCallback;

const types_threading = @import("types_threading.zig");
pub const Channel = types_threading.Channel;
pub const Mutex = types_threading.Mutex;
pub const ConditionVariable = types_threading.ConditionVariable;
pub const TimeType = types_threading.TimeType;
pub const Srfi18Time = types_threading.Srfi18Time;

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

pub const Bignum = types_numeric.Bignum;
pub const Rational = types_numeric.Rational;

const types_filesystem = @import("types_filesystem.zig");
pub const FileInfo = types_filesystem.FileInfo;
pub const UserInfo = types_filesystem.UserInfo;
pub const GroupInfo = types_filesystem.GroupInfo;
pub const DirectoryObject = types_filesystem.DirectoryObject;

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

const types_weakrefs = @import("types_weakrefs.zig");
pub const Ephemeron = types_weakrefs.Ephemeron;
pub const GuardEntry = types_weakrefs.GuardEntry;
pub const Guardian = types_weakrefs.Guardian;
pub const TransportCell = types_weakrefs.TransportCell;

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

/// Whether `v` is an interned symbol. Caller must have already checked
/// `isSymbol(v)`. Uninterned symbols (SRFI 258) return false.
pub fn symbolInterned(v: Value) bool {
    return toObject(v).as(Symbol).interned;
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
    return isClosure(v) or isNativeFn(v) or isNativeClosure(v) or isContinuation(v) or isParameter(v) or isFfiFunction(v) or isGuardian(v);
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

pub fn isNumericVector(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .numeric_vector;
}

pub fn toNumericVector(v: Value) *NumericVector {
    return toObject(v).as(NumericVector);
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

pub fn isEphemeron(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .ephemeron;
}

pub fn toEphemeron(v: Value) *Ephemeron {
    return toObject(v).as(Ephemeron);
}

pub fn isGuardian(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .guardian;
}

pub fn toGuardian(v: Value) *Guardian {
    return toObject(v).as(Guardian);
}

pub fn isTransportCell(v: Value) bool {
    return isPointer(v) and toObject(v).tag == .transport_cell;
}

pub fn toTransportCell(v: Value) *TransportCell {
    return toObject(v).as(TransportCell);
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

/// Recover a hygiene-renamed identifier's underlying name, for callers that
/// need to recognize a name STRUCTURALLY (a special form, a builtin's exact
/// spelling, an SRFI 213 property key, a KP4xxx lint's "is this direct user
/// text") despite whatever rename scheme wrapped it. Handles both `__hyg_N_`
/// (compiler-minted gensyms) and `def_env_binding_prefix`-marked names
/// (#1812: `libname` + `def_env_binding_sep` + the original name) — a
/// def_env-marked reference is exactly as much "a renamed version of
/// origname" as a `__hyg_` one is, so every existing caller of this function
/// needs it recognized the same way (confirmed necessary by a real
/// regression: `(srfi 211 define-macro)`'s own `lisp-transformer`/
/// `er-macro-transformer` are SRFI 211 primitives, not `(scheme base)`
/// bindings, so they got this library's def-env prefix; compiler_macro.zig's
/// resolveTransformerSpecRec recognizes a transformer-spec head by exact
/// name via this same function, and silently rejected the renamed spelling
/// as invalid syntax). The two schemes never nest (renameForHygiene treats
/// a def_env-prefixed name as already-renamed too, so it's never wrapped in
/// a further __hyg_ gensym, and vice versa), but the loop tries both each
/// pass for robustness rather than assuming that invariant here as well.
pub fn stripHygienicPrefix(name: []const u8) []const u8 {
    var n = name;
    while (true) {
        if (std.mem.startsWith(u8, n, "__hyg_")) {
            if (std.mem.indexOfScalar(u8, n[6..], '_')) |sep| {
                n = n[6 + sep + 1 ..];
                continue;
            }
            break;
        }
        if (std.mem.startsWith(u8, n, def_env_binding_prefix)) {
            const rest = n[def_env_binding_prefix.len..];
            if (std.mem.indexOf(u8, rest, def_env_binding_sep)) |sep| {
                n = rest[sep + def_env_binding_sep.len ..];
                continue;
            }
            break;
        }
        break;
    }
    return n;
}

/// Prefix marking a compiler-synthesized reference to a name's pristine
/// `(scheme base)` binding (#1715; see globals.zig's lookupBaseBinding for
/// the resolution side). Defined here, rather than in globals.zig, purely
/// so isContinuationBarrier below can recognize a prefixed name as
/// equivalent to its bare counterpart without types.zig depending on
/// globals.zig (which itself depends on types.zig).
pub const base_binding_prefix = "__kaappi_base__";

/// Prefix marking a compiler-synthesized reference to a name bound in a
/// SPECIFIC macro's own definition-environment library (#1812; see
/// globals.zig's lookupDefEnvBinding for the resolution side). Encoding is
/// `def_env_binding_prefix ++ libname ++ def_env_binding_sep ++ origname`
/// -- unlike base_binding_prefix (which always means the one well-known
/// `(scheme base)` library), this one is parameterized per-transformer, so
/// the library name has to travel with it. Defined here for the same
/// one-way-dependency reason as base_binding_prefix above.
pub const def_env_binding_prefix = "__kaappi_defenv__";

/// Separator between the embedded library name and the original binding
/// name in a def_env_binding_prefix-marked symbol. An ASCII unit separator:
/// library names are dot-joined symbol/digit text (library.zig's
/// libraryNameToString) and R7RS identifiers can't contain control
/// characters, so this byte can never collide with either half.
pub const def_env_binding_sep = "\x1f";

pub fn isContinuationBarrier(name: []const u8) bool {
    // A prefixed reference (e.g. "__kaappi_base__call-with-values",
    // synthesized by let-values/let*-values's desugaring, #1715) must be
    // recognized the same as its bare form: compileCallGlobal's "superinstr-
    // uction" fast path skips the standard frame setup call-with-values
    // needs for correct continuation capture (see the commit that
    // introduced this exclusion, fa6ecf47), and that requirement doesn't
    // change just because the reference is spelled differently. Same
    // reasoning applies to a def_env_binding_prefix-marked name (#1812): the
    // original name is whatever follows the def_env_binding_sep.
    const n = if (std.mem.startsWith(u8, name, base_binding_prefix))
        name[base_binding_prefix.len..]
    else if (std.mem.startsWith(u8, name, def_env_binding_prefix))
        (if (std.mem.indexOf(u8, name, def_env_binding_sep)) |sep|
            name[sep + def_env_binding_sep.len ..]
        else
            name)
    else
        name;
    return std.mem.eql(u8, n, "call-with-current-continuation") or
        std.mem.eql(u8, n, "call/cc") or
        std.mem.eql(u8, n, "call/ec") or
        std.mem.eql(u8, n, "call-with-escape-continuation") or
        std.mem.eql(u8, n, "call-with-values") or
        std.mem.eql(u8, n, "dynamic-wind") or
        std.mem.eql(u8, n, "with-exception-handler");
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

const is_wasm_target = builtin.os.tag == .wasi;

/// Bare cond-expand (SRFI 0) feature identifiers. `kaappi-fibers` and
/// `kaappi-reactor` are compiled in on every target, including wasm32-wasi
/// (KEP-0001 Phase 4's poll_oneoff backend). `kaappi-diagnostics` (the KP
/// diagnostic registry and the `(kaappi diagnostics)` `error-object-code`
/// accessor, KEP-0005 §4) is likewise always compiled in — no platform
/// carve-out. `kaappi-threads` is omitted on wasm, matching
/// Lib.wasmAvailable()'s `srfi_18 => false` gate (primitives.zig) — no OS
/// threads there. (KEP-0004)
const is_windows_target = builtin.os.tag == .windows;
const base_platform_features = [_][]const u8{ "r7rs", "kaappi", "ieee-float", "exact-closed", "exact-complex", "kaappi-fibers", "kaappi-reactor", "kaappi-diagnostics" };
// R7RS appendix B feature identifiers: exactly one OS-class identifier —
// `windows` on Windows, `posix` everywhere else (WASI hosts are POSIX-ish
// enough for the subset the runtime exposes there).
const os_feature = [_][]const u8{if (is_windows_target) "windows" else "posix"};
pub const platform_features = if (is_wasm_target)
    base_platform_features ++ os_feature
else
    base_platform_features ++ os_feature ++ [_][]const u8{"kaappi-threads"};

test "nil is not a pointer" {
    try std.testing.expect(!isPointer(NIL));
    try std.testing.expect(isNil(NIL));
}

test "heap Value round-trip is layout-independent" {
    // Every heap Value's payload is the address of the struct's `header`
    // field (makePointer(&x.header)), never the struct address, so heap
    // structs may gain or reorder fields freely: Zig's auto layout keeps
    // no field at a fixed offset, and it once moved Port's header to byte
    // offset 48 just from adding two bools, silently corrupting every port
    // Value under the old struct-pointer convention (#1618). This test
    // pins the round-trip on a struct shaped to invite reordering; it must
    // hold whether or not the header lands at offset 0.
    const Skewed = struct {
        flag: bool = false,
        header: Object,
        wide: u64 = 0,
    };
    var x = Skewed{ .header = .{ .tag = .pair } };
    const v = makePointer(&x.header);
    try std.testing.expect(isPointer(v));
    const obj = toObject(v);
    try std.testing.expect(obj == &x.header);
    try std.testing.expect(obj.tag == .pair);
    try std.testing.expect(obj.as(Skewed) == &x);
}
