const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;

// Extracted modules
const primitives_arithmetic = @import("primitives_arithmetic.zig");
const primitives_io = @import("primitives_io.zig");
const primitives_control = @import("primitives_control.zig");
const primitives_vector = @import("primitives_vector.zig");
const primitives_string = @import("primitives_string.zig");
const primitives_char = @import("primitives_char.zig");
const primitives_cxr = @import("primitives_cxr.zig");
const primitives_bytevector = @import("primitives_bytevector.zig");
const primitives_lazy = @import("primitives_lazy.zig");
const primitives_r7rs = @import("primitives_r7rs.zig");
const primitives_ffi = @import("primitives_ffi.zig");
const primitives_srfi1 = @import("primitives_srfi1.zig");
const primitives_hashtable = @import("primitives_hashtable.zig");
const primitives_random = @import("primitives_random.zig");
const primitives_filesystem = @import("primitives_filesystem.zig");

pub const PrimitiveError = error{
    TypeError,
    DivisionByZero,
    ArityMismatch,
    OutOfMemory,
    ExceptionRaised,
    ContinuationInvoked,
    IndexOutOfBounds,
    InvalidArgument,
    Yielded,
};

fn registerCore(vm: *vm_mod.VM) !void {
    // Pairs and lists
    try reg(vm, "cons", &cons, .{ .exact = 2 });
    try reg(vm, "car", &car, .{ .exact = 1 });
    try reg(vm, "cdr", &cdr, .{ .exact = 1 });
    try reg(vm, "set-car!", &setCar, .{ .exact = 2 });
    try reg(vm, "set-cdr!", &setCdr, .{ .exact = 2 });
    try reg(vm, "list", &list, .{ .variadic = 0 });
    try reg(vm, "length", &length, .{ .exact = 1 });
    try reg(vm, "append", &append, .{ .variadic = 0 });
    try reg(vm, "reverse", &reverse, .{ .exact = 1 });

    // Composed car/cdr (base library)
    try reg(vm, "caar", &caarFn, .{ .exact = 1 });
    try reg(vm, "cadr", &cadrFn, .{ .exact = 1 });
    try reg(vm, "cdar", &cdarFn, .{ .exact = 1 });
    try reg(vm, "cddr", &cddrFn, .{ .exact = 1 });

    // List utilities, map, for-each, member, assoc
    const primitives_list = @import("primitives_list.zig");
    try primitives_list.registerList(vm);

    // Type predicates
    try reg(vm, "pair?", &pairP, .{ .exact = 1 });
    try reg(vm, "null?", &nullP, .{ .exact = 1 });
    try reg(vm, "number?", &numberP, .{ .exact = 1 });
    try reg(vm, "integer?", &integerP, .{ .exact = 1 });
    try reg(vm, "real?", &realP, .{ .exact = 1 });
    try reg(vm, "complex?", &complexP, .{ .exact = 1 });
    try reg(vm, "rational?", &rationalP, .{ .exact = 1 });
    try reg(vm, "symbol?", &symbolP, .{ .exact = 1 });
    try reg(vm, "string?", &stringP, .{ .exact = 1 });
    try reg(vm, "boolean?", &booleanP, .{ .exact = 1 });
    try reg(vm, "char?", &charP, .{ .exact = 1 });
    try reg(vm, "procedure?", &procedureP, .{ .exact = 1 });
    try reg(vm, "list?", &listP, .{ .exact = 1 });

    // Equivalence
    try reg(vm, "eq?", &eqP, .{ .exact = 2 });
    try reg(vm, "eqv?", &eqvP, .{ .exact = 2 });
    try reg(vm, "equal?", &equalP, .{ .exact = 2 });

    // Boolean
    try reg(vm, "not", &notFn, .{ .exact = 1 });

    // String (moved to primitives_string.zig, but keep registration here for backward compat)
    try reg(vm, "string-length", &stringLength, .{ .exact = 1 });
    try reg(vm, "string-append", &stringAppend, .{ .variadic = 0 });
    try reg(vm, "symbol->string", &symbolToString, .{ .exact = 1 });

    // Record system (R7RS 5.5) -- internal primitives
    try reg(vm, "%make-record-type", &makeRecordTypeFn, .{ .exact = 2 });
    try reg(vm, "%make-record", &makeRecordFn, .{ .variadic = 1 });
    try reg(vm, "%record?", &recordCheckFn, .{ .exact = 2 });
    try reg(vm, "%record-ref", &recordRefFn, .{ .exact = 2 });
    try reg(vm, "%record-set!", &recordSetFn, .{ .exact = 3 });

    // Misc
    try reg(vm, "apply", &applyFn, .{ .variadic = 2 });
}

pub fn registerAll(vm: *vm_mod.VM) !void {
    try primitives_arithmetic.registerArithmetic(vm);
    try primitives_io.registerIO(vm);
    try primitives_control.registerControl(vm);
    try primitives_vector.registerVector(vm);
    try primitives_string.registerString(vm);
    try primitives_char.registerChar(vm);
    try primitives_cxr.registerCxr(vm);
    try primitives_bytevector.registerBytevector(vm);
    try primitives_lazy.registerLazy(vm);
    try primitives_r7rs.registerR7RS(vm);
    if (!is_wasm) try primitives_ffi.registerFfi(vm);
    try primitives_srfi1.registerSrfi1(vm);
    try primitives_hashtable.registerHashTable(vm);
    try primitives_random.registerRandom(vm);
    if (!is_wasm) try primitives_filesystem.registerFilesystem(vm);
    try @import("primitives_fiber.zig").registerFiber(vm);
    if (!is_wasm) try @import("primitives_srfi18.zig").registerSrfi18(vm);
    try registerCore(vm);
}

pub fn registerSandboxed(vm: *vm_mod.VM) !void {
    try primitives_arithmetic.registerArithmetic(vm);
    try primitives_io.registerIOSandboxed(vm);
    try primitives_control.registerControl(vm);
    try primitives_vector.registerVector(vm);
    try primitives_string.registerString(vm);
    try primitives_char.registerChar(vm);
    try primitives_cxr.registerCxr(vm);
    try primitives_bytevector.registerBytevector(vm);
    try primitives_lazy.registerLazy(vm);
    try primitives_r7rs.registerR7RSSandboxed(vm);
    try primitives_srfi1.registerSrfi1(vm);
    try primitives_hashtable.registerHashTable(vm);
    try primitives_random.registerRandom(vm);
    try @import("primitives_fiber.zig").registerFiber(vm);
    try registerCore(vm);
}

pub fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    const val = try vm.gc.allocNativeFn(name, func, arity);
    try vm.defineGlobal(name, val);
}

// ---------------------------------------------------------------------------
// Numeric helpers (pub for use by extracted modules)
// ---------------------------------------------------------------------------

pub fn anyFlonum(args: []const Value) bool {
    for (args) |a| {
        if (types.isFlonum(a)) return true;
    }
    return false;
}

pub fn toF64(v: Value) PrimitiveError!f64 {
    if (types.isFixnum(v)) return @floatFromInt(types.toFixnum(v));
    if (types.isFlonum(v)) return types.toFlonum(v);
    if (types.isBignum(v)) {
        const bignum_mod = @import("bignum.zig");
        return bignum_mod.toF64(v);
    }
    if (types.isRationalObj(v)) {
        const r = types.toRational(v);
        const n = try toF64(r.numerator);
        const d = try toF64(r.denominator);
        return n / d;
    }
    return PrimitiveError.TypeError; // bare-ok: numeric coercion fallback
}

pub fn makeFlonumVal(f: f64) PrimitiveError!Value {
    return types.makeFlonum(f);
}

pub fn isNum(v: Value) bool {
    return types.isFixnum(v) or types.isFlonum(v);
}

// ---------------------------------------------------------------------------
// GC / VM instances (pub for use by extracted modules)
// ---------------------------------------------------------------------------

pub threadlocal var gc_instance: ?*@import("memory.zig").GC = null;

pub fn setGCInstance(gc: *@import("memory.zig").GC) void {
    gc_instance = gc;
}

pub fn typeError(proc: []const u8, expected: []const u8, got: Value) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    var buf: [128]u8 = undefined;
    const s = safeValueDescription(&buf, got);
    vm.setErrorDetail("type error in '{s}': expected {s}, got {s}", .{ proc, expected, s });
    return PrimitiveError.TypeError;
}

fn safeValueDescription(buf: *[128]u8, value: Value) []const u8 {
    if (types.isFixnum(value)) {
        return std.fmt.bufPrint(buf, "{d}", .{types.toFixnum(value)}) catch "?";
    }
    if (value == types.NIL) return "()";
    if (value == types.TRUE) return "#t";
    if (value == types.FALSE) return "#f";
    if (value == types.VOID) return "#<void>";
    if (value == types.EOF) return "#<eof>";
    if (types.isChar(value)) return "#<char>";
    if (types.isFlonum(value)) {
        return std.fmt.bufPrint(buf, "{d}", .{types.toFlonum(value)}) catch "?";
    }
    if (types.isPointer(value)) {
        const addr = @as(usize, @truncate(value));
        if (addr == 0 or addr < 4096) return "#<invalid-pointer>";
        const obj = types.toObject(value);
        const tag = @intFromEnum(obj.tag);
        if (tag >= @typeInfo(types.ObjectTag).@"enum".fields.len)
            return std.fmt.bufPrint(buf, "#<corrupt tag={d}>", .{tag}) catch "#<corrupt>";
        return switch (obj.tag) {
            .pair => "#<pair>",
            .symbol => "#<symbol>",
            .string => "#<string>",
            .closure, .native_fn, .function, .native_closure => "#<procedure>",
            .vector => "#<vector>",
            .hash_table => "#<hash-table>",
            else => std.fmt.bufPrint(buf, "#<{s}>", .{@tagName(obj.tag)}) catch "#<object>",
        };
    }
    return std.fmt.bufPrint(buf, "0x{x}", .{value}) catch "?";
}

// ---------------------------------------------------------------------------
// Pairs and lists
// ---------------------------------------------------------------------------

fn cons(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPair(args[0], args[1]) catch return PrimitiveError.OutOfMemory;
}

fn car(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("car", "pair", args[0]);
    return types.car(args[0]);
}

fn cdr(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("cdr", "pair", args[0]);
    return types.cdr(args[0]);
}

fn setCar(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("set-car!", "pair", args[0]);
    if (gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    types.setCar(args[0], args[1]);
    return types.VOID;
}

fn setCdr(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("set-cdr!", "pair", args[0]);
    if (gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    types.setCdr(args[0], args[1]);
    return types.VOID;
}

fn list(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.makeList(args) catch return PrimitiveError.OutOfMemory;
}

fn length(args: []const Value) PrimitiveError!Value {
    var count: i64 = 0;
    var slow = args[0];
    var fast = args[0];
    while (fast != types.NIL) {
        if (!types.isPair(fast)) return PrimitiveError.TypeError;
        fast = types.cdr(fast);
        count += 1;
        if (fast == types.NIL) break;
        if (!types.isPair(fast)) return PrimitiveError.TypeError;
        fast = types.cdr(fast);
        count += 1;
        slow = types.cdr(slow);
        if (slow == fast) return PrimitiveError.TypeError;
    }
    return types.makeFixnum(count);
}

fn append(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 0) return types.NIL;
    if (args.len == 1) return args[0];

    var result = args[args.len - 1];
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i = args.len - 1;
    while (i > 0) {
        i -= 1;
        var lst = args[i];
        var elems: std.ArrayList(Value) = .empty;
        defer elems.deinit(gc.allocator);
        while (lst != types.NIL) {
            if (!types.isPair(lst)) return PrimitiveError.TypeError;
            elems.append(gc.allocator, types.car(lst)) catch return PrimitiveError.OutOfMemory;
            lst = types.cdr(lst);
        }
        var j = elems.items.len;
        while (j > 0) {
            j -= 1;
            result = gc.allocPair(elems.items[j], result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

fn reverse(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var current = args[0];
    while (current != types.NIL) {
        if (!types.isPair(current)) return PrimitiveError.TypeError;
        result = gc.allocPair(types.car(current), result) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Type predicates
// ---------------------------------------------------------------------------

fn pairP(args: []const Value) PrimitiveError!Value {
    return if (types.isPair(args[0])) types.TRUE else types.FALSE;
}

fn nullP(args: []const Value) PrimitiveError!Value {
    return if (types.isNil(args[0])) types.TRUE else types.FALSE;
}

fn numberP(args: []const Value) PrimitiveError!Value {
    return if (types.isNumber(args[0])) types.TRUE else types.FALSE;
}

fn integerP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isBignum(args[0])) return types.TRUE;
    if (types.isRationalObj(args[0])) return types.FALSE;
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        if (std.math.isNan(f) or std.math.isInf(f)) return types.FALSE;
        return if (f == @trunc(f)) types.TRUE else types.FALSE;
    }
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        if (c.imag != 0 or !c.exact_imag) return types.FALSE;
        if (std.math.isNan(c.real) or std.math.isInf(c.real)) return types.FALSE;
        return if (c.real == @trunc(c.real)) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn complexP(args: []const Value) PrimitiveError!Value {
    return if (types.isNumber(args[0])) types.TRUE else types.FALSE;
}

fn realP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isFlonum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.TRUE;
    if (types.isComplex(args[0])) {
        const c = types.toComplex(args[0]);
        return if (c.imag == 0 and c.exact_imag) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn rationalP(args: []const Value) PrimitiveError!Value {
    if (types.isFixnum(args[0]) or types.isBignum(args[0]) or types.isRationalObj(args[0])) return types.TRUE;
    if (types.isFlonum(args[0])) {
        const f = types.toFlonum(args[0]);
        return if (std.math.isFinite(f)) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn symbolP(args: []const Value) PrimitiveError!Value {
    return if (types.isSymbol(args[0])) types.TRUE else types.FALSE;
}

fn stringP(args: []const Value) PrimitiveError!Value {
    return if (types.isString(args[0])) types.TRUE else types.FALSE;
}

fn booleanP(args: []const Value) PrimitiveError!Value {
    return if (types.isBool(args[0])) types.TRUE else types.FALSE;
}

fn charP(args: []const Value) PrimitiveError!Value {
    return if (types.isChar(args[0])) types.TRUE else types.FALSE;
}

fn procedureP(args: []const Value) PrimitiveError!Value {
    return if (types.isProcedure(args[0])) types.TRUE else types.FALSE;
}

fn listP(args: []const Value) PrimitiveError!Value {
    var slow = args[0];
    var fast = args[0];
    while (true) {
        if (fast == types.NIL) return types.TRUE;
        if (!types.isPair(fast)) return types.FALSE;
        fast = types.cdr(fast);
        if (fast == types.NIL) return types.TRUE;
        if (!types.isPair(fast)) return types.FALSE;
        fast = types.cdr(fast);
        slow = types.cdr(slow);
        if (slow == fast) return types.FALSE;
    }
}

// ---------------------------------------------------------------------------
// Equivalence
// ---------------------------------------------------------------------------

fn eqP(args: []const Value) PrimitiveError!Value {
    return if (args[0] == args[1]) types.TRUE else types.FALSE;
}

fn eqvP(args: []const Value) PrimitiveError!Value {
    if (args[0] == args[1]) return types.TRUE;
    // Two flonums are eqv? if they have the same bits (handles NaN correctly)
    if (types.isFlonum(args[0]) and types.isFlonum(args[1])) {
        const a: u64 = @bitCast(types.toFlonum(args[0]));
        const b: u64 = @bitCast(types.toFlonum(args[1]));
        return if (a == b) types.TRUE else types.FALSE;
    }
    // Two bignums with equal value are eqv?
    if (types.isBignum(args[0]) and types.isBignum(args[1])) {
        const bignum_mod = @import("bignum.zig");
        return if (bignum_mod.compare(args[0], args[1]) == 0) types.TRUE else types.FALSE;
    }
    // Bignum and fixnum with same value are eqv?
    if ((types.isBignum(args[0]) and types.isFixnum(args[1])) or
        (types.isFixnum(args[0]) and types.isBignum(args[1])))
    {
        const bignum_mod = @import("bignum.zig");
        return if (bignum_mod.compare(args[0], args[1]) == 0) types.TRUE else types.FALSE;
    }
    // Two complex numbers are eqv? if both components match bitwise (same rule
    // as flonums, so NaN/-0.0 behave consistently).
    if (types.isComplex(args[0]) and types.isComplex(args[1])) {
        const ca = types.toComplex(args[0]);
        const cb = types.toComplex(args[1]);
        const ra: u64 = @bitCast(ca.real);
        const rb: u64 = @bitCast(cb.real);
        const ia: u64 = @bitCast(ca.imag);
        const ib: u64 = @bitCast(cb.imag);
        return if (ra == rb and ia == ib) types.TRUE else types.FALSE;
    }
    // Two rationals are eqv? if they have the same numerator and denominator
    // (they are always in lowest terms so this is sufficient)
    if (types.isRationalObj(args[0]) and types.isRationalObj(args[1])) {
        const ra = types.toRational(args[0]);
        const rb = types.toRational(args[1]);
        if (ra.numerator == rb.numerator and ra.denominator == rb.denominator) return types.TRUE;
        // Handle bignum numerator/denominator
        const bignum_mod = @import("bignum.zig");
        const n_eq = if (ra.numerator == rb.numerator) true else if ((types.isBignum(ra.numerator) or types.isFixnum(ra.numerator)) and (types.isBignum(rb.numerator) or types.isFixnum(rb.numerator))) bignum_mod.compare(ra.numerator, rb.numerator) == 0 else false;
        const d_eq = if (ra.denominator == rb.denominator) true else if ((types.isBignum(ra.denominator) or types.isFixnum(ra.denominator)) and (types.isBignum(rb.denominator) or types.isFixnum(rb.denominator))) bignum_mod.compare(ra.denominator, rb.denominator) == 0 else false;
        return if (n_eq and d_eq) types.TRUE else types.FALSE;
    }
    return types.FALSE;
}

fn equalP(args: []const Value) PrimitiveError!Value {
    return if (deepEqual(args[0], args[1])) types.TRUE else types.FALSE;
}

const VisitedKey = struct { a: Value, b: Value };
const VisitedMap = std.AutoHashMap(VisitedKey, void);

fn deepEqualWithVisited(a: Value, b: Value, visited: *VisitedMap) bool {
    if (a == b) return true;
    if (types.isFlonum(a) and types.isFlonum(b)) {
        const fa: u64 = @bitCast(types.toFlonum(a));
        const fb: u64 = @bitCast(types.toFlonum(b));
        return fa == fb;
    }
    if ((types.isBignum(a) or types.isFixnum(a)) and (types.isBignum(b) or types.isFixnum(b))) {
        if (types.isBignum(a) or types.isBignum(b)) {
            const bignum_mod = @import("bignum.zig");
            return bignum_mod.compare(a, b) == 0;
        }
    }
    if (types.isComplex(a) and types.isComplex(b)) {
        const ca = types.toComplex(a);
        const cb = types.toComplex(b);
        const ra: u64 = @bitCast(ca.real);
        const rb: u64 = @bitCast(cb.real);
        const ia: u64 = @bitCast(ca.imag);
        const ib: u64 = @bitCast(cb.imag);
        return ra == rb and ia == ib;
    }
    if (types.isRationalObj(a) and types.isRationalObj(b)) {
        const ra = types.toRational(a);
        const rb = types.toRational(b);
        return deepEqualWithVisited(ra.numerator, rb.numerator, visited) and
            deepEqualWithVisited(ra.denominator, rb.denominator, visited);
    }
    if (types.isPair(a) and types.isPair(b)) {
        const key = VisitedKey{ .a = a, .b = b };
        if (visited.get(key) != null) return true;
        visited.put(key, {}) catch {};
        return deepEqualWithVisited(types.car(a), types.car(b), visited) and
            deepEqualWithVisited(types.cdr(a), types.cdr(b), visited);
    }
    if (types.isString(a) and types.isString(b)) {
        const sa = types.toObject(a).as(types.SchemeString);
        const sb = types.toObject(b).as(types.SchemeString);
        return std.mem.eql(u8, sa.data, sb.data);
    }
    if (types.isVector(a) and types.isVector(b)) {
        const va = types.toVector(a);
        const vb = types.toVector(b);
        if (va.data.len != vb.data.len) return false;
        const key = VisitedKey{ .a = a, .b = b };
        if (visited.get(key) != null) return true;
        visited.put(key, {}) catch {};
        for (va.data, vb.data) |ea, eb| {
            if (!deepEqualWithVisited(ea, eb, visited)) return false;
        }
        return true;
    }
    if (types.isBytevector(a) and types.isBytevector(b)) {
        const ba = types.toBytevector(a);
        const bb = types.toBytevector(b);
        return std.mem.eql(u8, ba.data, bb.data);
    }
    return false;
}

pub fn deepEqual(a: Value, b: Value) bool {
    var visited = VisitedMap.init(std.heap.page_allocator);
    defer visited.deinit();
    return deepEqualWithVisited(a, b, &visited);
}

// ---------------------------------------------------------------------------
// Boolean
// ---------------------------------------------------------------------------

fn notFn(args: []const Value) PrimitiveError!Value {
    return if (!types.isTruthy(args[0])) types.TRUE else types.FALSE;
}

// ---------------------------------------------------------------------------
// String
// ---------------------------------------------------------------------------

fn stringLength(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const data = str.data[0..str.len];
    // Count UTF-8 codepoints, not bytes
    var count: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        const len = std.unicode.utf8ByteSequenceLength(data[i]) catch 1;
        i += len;
        count += 1;
    }
    return types.makeFixnum(@intCast(count));
}

fn stringAppend(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    var total_len: usize = 0;
    for (args) |a| {
        if (!types.isString(a)) return PrimitiveError.TypeError;
        total_len += types.toObject(a).as(types.SchemeString).len;
    }
    var result = gc.allocator.alloc(u8, total_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(result);
    var pos: usize = 0;
    for (args) |a| {
        const str = types.toObject(a).as(types.SchemeString);
        @memcpy(result[pos .. pos + str.len], str.data);
        pos += str.len;
    }
    return gc.allocString(result) catch return PrimitiveError.OutOfMemory;
}

fn symbolToString(args: []const Value) PrimitiveError!Value {
    if (!types.isSymbol(args[0])) return PrimitiveError.TypeError;
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    const val = gc.allocString(types.symbolName(args[0])) catch return PrimitiveError.OutOfMemory;
    // R7RS: strings returned by symbol->string are immutable
    types.toObject(val).as(types.SchemeString).immutable = true;
    return val;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

fn applyFn(args: []const Value) PrimitiveError!Value {
    const vm = @import("vm.zig").vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return PrimitiveError.TypeError;

    // Collect all arguments: args[1..n-1] are individual, args[n-1] is a list
    var call_args: [256]Value = undefined;
    var count: usize = 0;

    // Individual args (everything between proc and the final list)
    for (args[1 .. args.len - 1]) |a| {
        if (count >= 256) return PrimitiveError.OutOfMemory;
        call_args[count] = a;
        count += 1;
    }

    // Flatten the last arg (must be a proper list)
    var rest = args[args.len - 1];
    while (rest != types.NIL) {
        if (!types.isPair(rest)) return PrimitiveError.TypeError;
        if (count >= 256) return PrimitiveError.OutOfMemory;
        call_args[count] = types.car(rest);
        count += 1;
        rest = types.cdr(rest);
    }

    return vm.callWithArgs(proc, call_args[0..count]) catch |err| {
        return switch (err) {
            @import("vm.zig").VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            @import("vm.zig").VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            @import("vm.zig").VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };
}

// ---------------------------------------------------------------------------
// Record system (R7RS 5.5) -- internal primitives
// ---------------------------------------------------------------------------

fn makeRecordTypeFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    // args[0] = name (string), args[1] = num_fields (fixnum)
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const nf = types.toFixnum(args[1]);
    if (nf < 0 or nf > 255) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const num_fields: u8 = @intCast(nf);
    return gc.allocRecordType(str.data[0..str.len], num_fields) catch return PrimitiveError.OutOfMemory;
}

fn makeRecordFn(args: []const Value) PrimitiveError!Value {
    const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
    // args[0] = record_type, args[1..] = field values
    if (!types.isRecordType(args[0])) return PrimitiveError.TypeError;
    const rt = types.toObject(args[0]).as(types.RecordType);
    return gc.allocRecordInstance(rt, args[1..]) catch return PrimitiveError.OutOfMemory;
}

fn recordCheckFn(args: []const Value) PrimitiveError!Value {
    // args[0] = value to check, args[1] = record_type
    if (!types.isRecordType(args[1])) return PrimitiveError.TypeError;
    const rt = types.toObject(args[1]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return types.FALSE;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    return if (ri.record_type == rt) types.TRUE else types.FALSE;
}

fn recordRefFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum)
    if (!types.isRecordInstance(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const idx: usize = @intCast(raw_idx);
    if (idx >= ri.fields.len) return PrimitiveError.TypeError;
    return ri.fields[idx];
}

fn recordSetFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum), args[2] = new value
    if (!types.isRecordInstance(args[0])) return PrimitiveError.TypeError;
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const idx: usize = @intCast(raw_idx);
    if (idx >= ri.fields.len) return PrimitiveError.TypeError;
    if (gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[2]);
    ri.fields[idx] = args[2];
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Composed car/cdr (base library: caar, cadr, cdar, cddr)
// ---------------------------------------------------------------------------

fn caarFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    const a = types.car(args[0]);
    if (!types.isPair(a)) return PrimitiveError.TypeError;
    return types.car(a);
}

fn cadrFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    const d = types.cdr(args[0]);
    if (!types.isPair(d)) return PrimitiveError.TypeError;
    return types.car(d);
}

fn cdarFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    const a = types.car(args[0]);
    if (!types.isPair(a)) return PrimitiveError.TypeError;
    return types.cdr(a);
}

fn cddrFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return PrimitiveError.TypeError;
    const d = types.cdr(args[0]);
    if (!types.isPair(d)) return PrimitiveError.TypeError;
    return types.cdr(d);
}

// ---------------------------------------------------------------------------
