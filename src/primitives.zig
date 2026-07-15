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

pub const PrimitiveError = @import("errors.zig").KaappiError;

// ---------------------------------------------------------------------------
// Spec table types — single source of truth for registration and export
// ---------------------------------------------------------------------------

pub const Lib = enum {
    scheme_base,
    scheme_write,
    scheme_inexact,
    scheme_read,
    scheme_char,
    scheme_lazy,
    scheme_time,
    scheme_process_context,
    scheme_eval,
    scheme_repl,
    scheme_load,
    scheme_r5rs,
    scheme_file,
    scheme_cxr,
    scheme_complex,
    kaappi_ffi,
    kaappi_fibers,
    kaappi_diagnostics,
    srfi_1,
    srfi_13,
    srfi_18,
    srfi_39,
    srfi_69,
    srfi_133,
    srfi_170,
    /// Internal-only tag for primitives that live in vm.globals but must
    /// not be exported by any standard library. No library is registered
    /// for this tag, so `addExportsForLib` never picks these specs up.
    internal,

    pub fn canonicalName(self: Lib) []const u8 {
        return switch (self) {
            .scheme_base => "scheme.base",
            .scheme_write => "scheme.write",
            .scheme_inexact => "scheme.inexact",
            .scheme_read => "scheme.read",
            .scheme_char => "scheme.char",
            .scheme_lazy => "scheme.lazy",
            .scheme_time => "scheme.time",
            .scheme_process_context => "scheme.process-context",
            .scheme_eval => "scheme.eval",
            .scheme_repl => "scheme.repl",
            .scheme_load => "scheme.load",
            .scheme_r5rs => "scheme.r5rs",
            .scheme_file => "scheme.file",
            .scheme_cxr => "scheme.cxr",
            .scheme_complex => "scheme.complex",
            .kaappi_ffi => "kaappi.ffi",
            .kaappi_fibers => "kaappi.fibers",
            .kaappi_diagnostics => "kaappi.diagnostics",
            .srfi_1 => "srfi.1",
            .srfi_13 => "srfi.13",
            .srfi_18 => "srfi.18",
            .srfi_39 => "srfi.39",
            .srfi_69 => "srfi.69",
            .srfi_133 => "srfi.133",
            .srfi_170 => "srfi.170",
            .internal => "kaappi.internal",
        };
    }

    pub fn sandboxAllowed(self: Lib) bool {
        return switch (self) {
            .scheme_file,
            .scheme_load,
            .scheme_eval,
            .scheme_repl,
            .scheme_process_context,
            .scheme_r5rs,
            .kaappi_ffi,
            .srfi_18,
            .srfi_170,
            .internal,
            => false,
            else => true,
        };
    }

    pub fn wasmAvailable(self: Lib) bool {
        return switch (self) {
            .kaappi_ffi, .srfi_18, .srfi_170 => false,
            else => true,
        };
    }

    /// Whether this lib tag corresponds to a real library that should
    /// be registered. Returns false for `.internal`.
    pub fn isRegisterable(self: Lib) bool {
        return self != .internal;
    }
};

pub const LibSet = std.EnumSet(Lib);

pub const PrimSpec = struct {
    name: []const u8,
    func: types.NativeFnType,
    arity: NativeFn.Arity,
    libs: LibSet,
    sandbox: bool = true,
    wasm: bool = true,
};

const LS = LibSet;
const BR = LS.initMany(&.{ .scheme_base, .scheme_r5rs });
const BRS1 = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_1 });
const BCRS1 = LS.initMany(&.{ .scheme_base, .scheme_cxr, .scheme_r5rs, .srfi_1 });

const core_specs = [_]PrimSpec{
    .{ .name = "cons", .func = &cons, .arity = .{ .exact = 2 }, .libs = BRS1 },
    .{ .name = "car", .func = &car, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "cdr", .func = &cdr, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "set-car!", .func = &setCar, .arity = .{ .exact = 2 }, .libs = BRS1 },
    .{ .name = "set-cdr!", .func = &setCdr, .arity = .{ .exact = 2 }, .libs = BRS1 },
    .{ .name = "list", .func = &list, .arity = .{ .variadic = 0 }, .libs = BRS1 },
    .{ .name = "length", .func = &length, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "append", .func = &append, .arity = .{ .variadic = 0 }, .libs = BRS1 },
    .{ .name = "reverse", .func = &reverse, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "caar", .func = &caarFn, .arity = .{ .exact = 1 }, .libs = BCRS1 },
    .{ .name = "cadr", .func = &cadrFn, .arity = .{ .exact = 1 }, .libs = BCRS1 },
    .{ .name = "cdar", .func = &cdarFn, .arity = .{ .exact = 1 }, .libs = BCRS1 },
    .{ .name = "cddr", .func = &cddrFn, .arity = .{ .exact = 1 }, .libs = BCRS1 },
    .{ .name = "pair?", .func = &pairP, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "null?", .func = &nullP, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "number?", .func = &numberP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "integer?", .func = &integerP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "real?", .func = &realP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "complex?", .func = &complexP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "rational?", .func = &rationalP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "symbol?", .func = &symbolP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "string?", .func = &stringP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "boolean?", .func = &booleanP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "char?", .func = &charP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "procedure?", .func = &procedureP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "list?", .func = &listP, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "eq?", .func = &eqP, .arity = .{ .exact = 2 }, .libs = BR },
    .{ .name = "eqv?", .func = &eqvP, .arity = .{ .exact = 2 }, .libs = BR },
    .{ .name = "equal?", .func = &equalP, .arity = .{ .exact = 2 }, .libs = BR },
    .{ .name = "not", .func = &notFn, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "string-length", .func = &stringLength, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "string-append", .func = &stringAppend, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_13 }) },
    .{ .name = "symbol->string", .func = &symbolToString, .arity = .{ .exact = 1 }, .libs = BR },
    .{ .name = "%make-record-type", .func = &makeRecordTypeFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%make-record", .func = &makeRecordFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%record?", .func = &recordCheckFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%record-ref", .func = &recordRefFn, .arity = .{ .exact = 3 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%record-set!", .func = &recordSetFn, .arity = .{ .exact = 4 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "apply", .func = &applyFn, .arity = .{ .variadic = 2 }, .libs = BR },
};

const no_specs = [0]PrimSpec{};

pub const all_specs = core_specs ++
    @import("primitives_list.zig").specs ++
    primitives_arithmetic.specs ++
    @import("primitives_numeric.zig").specs ++
    primitives_io.specs ++
    primitives_control.specs ++
    primitives_vector.specs ++
    primitives_string.specs ++
    @import("primitives_string_ext.zig").specs ++
    primitives_char.specs ++
    primitives_cxr.specs ++
    primitives_bytevector.specs ++
    primitives_lazy.specs ++
    primitives_r7rs.specs ++
    (if (is_wasm) no_specs else primitives_ffi.specs) ++
    primitives_srfi1.specs ++
    primitives_hashtable.specs ++
    primitives_random.specs ++
    (if (is_wasm) no_specs else primitives_filesystem.specs) ++
    @import("primitives_fiber.zig").specs ++
    @import("primitives_parallel.zig").specs ++
    // SRFI-18's OS-thread machinery cannot exist on WASM, but its
    // fiber-safe subset (thread-sleep!, the KEP-0001 Phase 4 timer path)
    // can: wasm_specs is the comptime-filtered `.wasm = true` slice, so
    // the WASM build never references std.Thread.spawn and friends.
    (if (is_wasm) @import("primitives_srfi18.zig").wasm_specs else @import("primitives_srfi18.zig").specs);

comptime {
    @setEvalBranchQuota(all_specs.len * all_specs.len * 30);
    for (all_specs, 0..) |a, i| {
        for (all_specs[i + 1 ..]) |b| {
            if (std.mem.eql(u8, a.name, b.name))
                @compileError("duplicate spec: " ++ a.name);
        }
    }
    for (all_specs) |spec| {
        if (spec.libs.count() == 0)
            @compileError("orphan spec (no libraries): " ++ spec.name);
    }
}

pub fn registerAll(vm: *vm_mod.VM) !void {
    try primitives_io.initPortParams(vm);
    primitives_random.initDefaultRS(vm);
    for (&all_specs) |spec| {
        if (!is_wasm or spec.wasm)
            try reg(vm, spec.name, spec.func, spec.arity);
    }
    if (comptime !is_wasm) {
        try vm.defineGlobal("owner/unchanged", types.makeFixnum(-1));
        try vm.defineGlobal("group/unchanged", types.makeFixnum(-1));
    }
}

pub fn registerSandboxed(vm: *vm_mod.VM) !void {
    try primitives_io.initPortParams(vm);
    primitives_random.initDefaultRS(vm);
    for (&all_specs) |spec| {
        if (spec.sandbox and (!is_wasm or spec.wasm))
            try reg(vm, spec.name, spec.func, spec.arity);
    }
}

/// Registration placeholder for procedures whose real implementation is
/// Scheme source in vm_bootstrap.zig, installed at VM init right after
/// registration. The spec entry must stay (it drives arity metadata and
/// library exports), but the native body was retired when the Scheme
/// version became the single implementation (#1375): a stub that errors
/// makes a missing vm_bootstrap.install() fail loudly instead of silently
/// falling back to a native implementation that has since diverged.
pub fn bootstrapStub(comptime name: []const u8) types.NativeFnType {
    const S = struct {
        fn call(args: []const Value) PrimitiveError!Value {
            _ = args;
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
            vm.setErrorDetail("'{s}' is implemented in Scheme (src/vm_bootstrap.zig) but vm_bootstrap.install() has not run for this VM", .{name});
            return PrimitiveError.TypeError;
        }
    };
    return &S.call;
}

pub fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    if (std.debug.runtime_safety) {
        if (vm.globals.get(name) != null) {
            std.debug.panic("duplicate primitive registration: {s}", .{name});
        }
    }
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

const memory = @import("memory.zig");

pub fn typeError(proc: []const u8, expected: []const u8, got: Value) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    var buf: [128]u8 = undefined;
    const s = safeValueDescription(&buf, got);
    vm.setErrorDetail("type error in '{s}': expected {s}, got {s}", .{ proc, expected, s });
    return PrimitiveError.TypeError;
}

pub fn expectPair(proc: []const u8, v: Value) PrimitiveError!*types.Pair {
    if (!types.isPair(v)) return typeError(proc, "pair", v);
    return types.toPair(v);
}

pub fn expectVector(proc: []const u8, v: Value) PrimitiveError!*types.Vector {
    if (!types.isVector(v)) return typeError(proc, "vector", v);
    return types.toVector(v);
}

pub fn expectFixnum(proc: []const u8, v: Value) PrimitiveError!i64 {
    if (!types.isFixnum(v)) return typeError(proc, "exact integer", v);
    return types.toFixnum(v);
}

pub fn expectChar(proc: []const u8, v: Value) PrimitiveError!u21 {
    if (!types.isChar(v)) return typeError(proc, "char", v);
    return types.toChar(v);
}

pub fn expectString(proc: []const u8, v: Value) PrimitiveError![]const u8 {
    if (!types.isString(v)) return typeError(proc, "string", v);
    const str = types.toObject(v).as(types.SchemeString);
    return str.data[0..str.len];
}

pub fn expectPort(proc: []const u8, v: Value) PrimitiveError!*types.Port {
    if (!types.isPort(v)) return typeError(proc, "port", v);
    return types.toObject(v).as(types.Port);
}

pub fn indexError(proc: []const u8, index: i64, len: usize) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.IndexOutOfBounds;
    vm.setErrorDetail("{s}: index {d} out of range for length {d}", .{ proc, index, len });
    return PrimitiveError.IndexOutOfBounds;
}

pub const Range = struct { start: usize, end: usize };

pub fn parseOptionalRange(args: []const Value, arg_offset: usize, max_len: usize, proc_name: []const u8) PrimitiveError!Range {
    var start: usize = 0;
    var end: usize = max_len;
    if (args.len > arg_offset) {
        if (!types.isFixnum(args[arg_offset])) return typeError(proc_name, "exact integer", args[arg_offset]);
        const s = types.toFixnum(args[arg_offset]);
        if (s < 0 or @as(usize, @intCast(s)) > max_len) return typeError(proc_name, "valid index", args[arg_offset]);
        start = @intCast(s);
    }
    if (args.len > arg_offset + 1) {
        if (!types.isFixnum(args[arg_offset + 1])) return typeError(proc_name, "exact integer", args[arg_offset + 1]);
        const e = types.toFixnum(args[arg_offset + 1]);
        if (e < 0 or @as(usize, @intCast(e)) > max_len) return typeError(proc_name, "valid index", args[arg_offset + 1]);
        end = @intCast(e);
    }
    if (start > end) return typeError(proc_name, "start <= end", args[arg_offset]);
    return .{ .start = start, .end = end };
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    if (types.toObject(args[0]).flags.immutable) return typeError("set-car!", "mutable pair", args[0]);
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    types.setCar(args[0], args[1]);
    return types.VOID;
}

fn setCdr(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("set-cdr!", "pair", args[0]);
    if (types.toObject(args[0]).flags.immutable) return typeError("set-cdr!", "mutable pair", args[0]);
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    types.setCdr(args[0], args[1]);
    return types.VOID;
}

fn list(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.makeList(args) catch return PrimitiveError.OutOfMemory;
}

fn length(args: []const Value) PrimitiveError!Value {
    var count: i64 = 0;
    var slow = args[0];
    var fast = args[0];
    while (fast != types.NIL) {
        if (!types.isPair(fast)) return typeError("length", "proper list", fast);
        fast = types.cdr(fast);
        count += 1;
        if (fast == types.NIL) break;
        if (!types.isPair(fast)) return typeError("length", "proper list", fast);
        fast = types.cdr(fast);
        count += 1;
        slow = types.cdr(slow);
        if (slow == fast) return typeError("length", "proper list", fast);
    }
    return types.makeFixnum(count);
}

fn append(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (args.len == 0) return types.NIL;
    if (args.len == 1) return args[0];

    var result = args[args.len - 1];
    gc.pushRoot(&result);
    defer gc.popRoot();
    var i = args.len - 1;
    while (i > 0) {
        i -= 1;
        var lst = args[i];
        var elems: std.ArrayList(Value) = .empty;
        defer elems.deinit(gc.allocator);
        var slow = lst;
        var step: bool = false;
        while (lst != types.NIL) {
            if (!types.isPair(lst)) return typeError("append", "proper list", lst);
            elems.append(gc.allocator, types.car(lst)) catch return PrimitiveError.OutOfMemory;
            lst = types.cdr(lst);
            if (step) {
                slow = types.cdr(slow);
                if (slow == lst) return typeError("append", "proper list", lst);
            }
            step = !step;
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
    var current = args[0];
    var slow = current;
    var step: bool = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return typeError("reverse", "proper list", current);
        result = gc.allocPair(types.car(current), result) catch return PrimitiveError.OutOfMemory;
        current = types.cdr(current);
        if (step) {
            slow = types.cdr(slow);
            if (slow == current) return typeError("reverse", "proper list", current);
        }
        step = !step;
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
    const data = try expectString("string-length", args[0]);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var total_len: usize = 0;
    for (args) |a| {
        if (!types.isString(a)) return typeError("string-append", "string", a);
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
    if (!types.isSymbol(args[0])) return typeError("symbol->string", "symbol", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const val = gc.allocString(types.symbolName(args[0])) catch return PrimitiveError.OutOfMemory;
    // R7RS: strings returned by symbol->string are immutable
    types.toObject(val).flags.immutable = true;
    return val;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

fn applyFn(args: []const Value) PrimitiveError!Value {
    const vm = @import("vm.zig").vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isProcedure(proc) and !types.isNativeFn(proc)) return typeError("apply", "procedure", proc);

    // Collect all arguments: args[1..n-1] are individual, args[n-1] is a list
    var call_args: std.ArrayList(Value) = .empty;
    defer call_args.deinit(gc.allocator);

    // Individual args (everything between proc and the final list)
    for (args[1 .. args.len - 1]) |a| {
        call_args.append(gc.allocator, a) catch return PrimitiveError.OutOfMemory;
    }

    // Flatten the last arg (must be a proper list)
    var rest = args[args.len - 1];
    var slow = rest;
    var step: bool = false;
    while (rest != types.NIL) {
        if (!types.isPair(rest)) return typeError("apply", "proper list", rest);
        call_args.append(gc.allocator, types.car(rest)) catch return PrimitiveError.OutOfMemory;
        rest = types.cdr(rest);
        if (step) {
            slow = types.cdr(slow);
            if (slow == rest) return typeError("apply", "proper list", rest);
        }
        step = !step;
    }

    return vm.callWithArgs(proc, call_args.items) catch |err| {
        return err;
    };
}

// ---------------------------------------------------------------------------
// Record system (R7RS 5.5) -- internal primitives
// ---------------------------------------------------------------------------

fn makeRecordTypeFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    // args[0] = name (string), args[1] = num_fields (fixnum)
    const name_data = try expectString("%make-record-type", args[0]);
    const nf = try expectFixnum("%make-record-type", args[1]);
    if (nf < 0 or nf > 255) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const num_fields: u8 = @intCast(nf);
    return gc.allocRecordType(name_data, num_fields) catch return PrimitiveError.OutOfMemory;
}

fn makeRecordFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    // args[0] = record_type, args[1..] = field values
    if (!types.isRecordType(args[0])) return typeError("%make-record", "record-type", args[0]);
    const rt = types.toObject(args[0]).as(types.RecordType);
    return gc.allocRecordInstance(rt, args[1..]) catch return PrimitiveError.OutOfMemory;
}

fn recordCheckFn(args: []const Value) PrimitiveError!Value {
    // args[0] = value to check, args[1] = record_type
    if (!types.isRecordType(args[1])) return typeError("record?", "record-type", args[1]);
    const rt = types.toObject(args[1]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return types.FALSE;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    return if (ri.record_type == rt) types.TRUE else types.FALSE;
}

fn recordRefFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum), args[2] = expected record type
    if (!types.isRecordType(args[2])) return typeError("%record-ref", "record-type", args[2]);
    const rt = types.toObject(args[2]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return typeError("%record-ref", rt.name, args[0]);
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    if (ri.record_type != rt) return typeError("%record-ref", rt.name, args[0]);
    if (!types.isFixnum(args[1])) return typeError("%record-ref", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const idx: usize = @intCast(raw_idx);
    if (idx >= ri.fields.len) return indexError("%record-ref", raw_idx, ri.fields.len);
    return ri.fields[idx];
}

fn recordSetFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum), args[2] = new value, args[3] = expected record type
    if (!types.isRecordType(args[3])) return typeError("%record-set!", "record-type", args[3]);
    const rt = types.toObject(args[3]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return typeError("%record-set!", rt.name, args[0]);
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    if (ri.record_type != rt) return typeError("%record-set!", rt.name, args[0]);
    if (!types.isFixnum(args[1])) return typeError("%record-set!", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const idx: usize = @intCast(raw_idx);
    if (idx >= ri.fields.len) return indexError("%record-set!", raw_idx, ri.fields.len);
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[2]);
    ri.fields[idx] = args[2];
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Composed car/cdr (base library: caar, cadr, cdar, cddr)
// ---------------------------------------------------------------------------

fn caarFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("caar", "pair", args[0]);
    const a = types.car(args[0]);
    if (!types.isPair(a)) return typeError("caar", "pair", a);
    return types.car(a);
}

fn cadrFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("cadr", "pair", args[0]);
    const d = types.cdr(args[0]);
    if (!types.isPair(d)) return typeError("cadr", "pair", d);
    return types.car(d);
}

fn cdarFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("cdar", "pair", args[0]);
    const a = types.car(args[0]);
    if (!types.isPair(a)) return typeError("cdar", "pair", a);
    return types.cdr(a);
}

fn cddrFn(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("cddr", "pair", args[0]);
    const d = types.cdr(args[0]);
    if (!types.isPair(d)) return typeError("cddr", "pair", d);
    return types.cdr(d);
}

// ---------------------------------------------------------------------------
