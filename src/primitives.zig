const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const printer = @import("printer.zig");
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
    // SRFI-254 (Ephemerons and Guardians): a composite library plus the three
    // component libraries and the (srfi 254 ephemerons-and-guardians) alias.
    srfi_254,
    srfi_254_ephemerons,
    srfi_254_guardians,
    srfi_254_transport_cell_guardians,
    srfi_254_ephemerons_and_guardians,
    srfi_192,
    srfi_258,
    srfi_260,
    /// Native primitives backing the portable SRFI 59/112/193 `.sld` layers
    /// (`%script-path`, `%implementation-version`, `%os-name`,
    /// `%cpu-architecture`) -- not itself a SRFI or a `(srfi N)` name, so no
    /// registry-shadows-a-.sld concern (contrast srfi_181_primitives /
    /// srfi_248_primitives, which exist specifically to dodge that).
    kaappi_sysinfo,
    // SRFI 181 (Custom and Transcoded Ports): the registry shadows a same
    // named .sld (see srfi_248_primitives below for the identical reason),
    // so the public `(srfi 181)` must stay file-only -- lib/srfi/181.sld
    // imports this sub-library and re-exports its full combined surface.
    srfi_181_primitives,
    // SRFI 248 (minimal delimited continuations): the two VM primitives the
    // portable `(srfi 248)` .sld builds on. Kept in their own importable
    // sub-library so the .sld can pull them in (the registry shadows a same
    // named .sld, so the public `(srfi 248)` must stay file-only).
    srfi_248_primitives,
    // SRFI 237 (R6RS Records, refined): the low-level RTD-creation and
    // inheritance-aware ref/set/predicate primitives the portable
    // `(srfi 237)` .sld's procedural layer builds on -- same
    // registry-shadows-a-.sld reason as srfi_181_primitives/
    // srfi_248_primitives above.
    srfi_237_primitives,
    // SRFI 160 (homogeneous numeric vector libraries): the generic
    // NumericVector create/ref/set!/kind/length primitives every
    // `(srfi 160 <tag>)` per-type .sld builds its named surface on -- same
    // registry-shadows-a-.sld reason as srfi_237_primitives above.
    srfi_160_primitives,
    // SRFI 211 (Scheme Macro Libraries): the er-macro-transformer /
    // lisp-transformer constructors the portable `(srfi 211
    // explicit-renaming)` / `(srfi 211 define-macro)` .slds re-export --
    // same registry-shadows-a-.sld reason as srfi_237_primitives above
    // (SRFI 211 is sub-library-only, so the sub-library names must stay
    // file-resolvable).
    srfi_211_primitives,
    /// `(kaappi primitives)`: the internal helpers a *portable* `.sld` names
    /// in its own Scheme source -- SRFI 27's random-source accessors, SRFI
    /// 74's endianness probe, SRFI 271's random ports, the record substrate
    /// SRFI 57/131/136/150/237 build on. They used to ride along in
    /// `(scheme base)`, which reserved their names against every user library
    /// (kaappi#1856); they are named here instead so each `.sld` declares the
    /// dependency it actually has. Every spec tagged with this is *also*
    /// tagged `.internal` (see `INTERNAL_PUBLIC`), so compiler-synthesized
    /// references still resolve against the pristine snapshot.
    ///
    /// Not a stability promise: `(kaappi primitives)` is this implementation's
    /// own substrate, and portable code should use the SRFIs layered over it.
    kaappi_primitives,
    /// Internal-only tag for primitives that live in vm.globals but must
    /// not be exported by any standard library. No library is registered
    /// for this tag, so `addExportsForLib` never picks these specs up.
    ///
    /// Reachable anyway, by two routes that both bypass the import graph:
    /// compiler-generated code (case-lambda's arity dispatch,
    /// `define-record-type`'s desugaring, `delay`'s promise construction)
    /// references them through `Compiler.trueBuiltinRefOrSymbol`, which
    /// resolves against `LibraryRegistry.internal_bindings`; a portable
    /// `.sld` that names one in Scheme source imports
    /// `(kaappi primitives)` (see `kaappi_primitives` above).
    ///
    /// Exporting them from `(scheme base)` instead took the whole
    /// `%`-prefixed namespace away from user libraries, since R7RS 5.2 makes
    /// importing one name from two libraries with different bindings an
    /// error — a user library defining its own `%length` could no longer be
    /// imported at all (kaappi#1856). The comptime guard below keeps them
    /// out of the `scheme.*` export sets.
    ///
    /// A subset of these are additionally *removed* from vm.globals once
    /// `vm_bootstrap.install()` has captured them (its `internal_helpers`
    /// list): `%push-wind` and the `%promise-*` mutators corrupt VM state
    /// if called out of sequence, so they must be unreachable, not merely
    /// unexported. Being `.internal` does not imply being purged.
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
            .srfi_254 => "srfi.254",
            .srfi_254_ephemerons => "srfi.254.ephemerons",
            .srfi_254_guardians => "srfi.254.guardians",
            .srfi_254_transport_cell_guardians => "srfi.254.transport-cell-guardians",
            .srfi_254_ephemerons_and_guardians => "srfi.254.ephemerons-and-guardians",
            .srfi_192 => "srfi.192",
            .srfi_258 => "srfi.258",
            .srfi_260 => "srfi.260",
            .kaappi_sysinfo => "kaappi.sysinfo",
            .srfi_181_primitives => "srfi.181.primitives",
            .srfi_248_primitives => "srfi.248.primitives",
            .srfi_237_primitives => "srfi.237.primitives",
            .srfi_160_primitives => "srfi.160.primitives",
            .srfi_211_primitives => "srfi.211.primitives",
            .kaappi_primitives => "kaappi.primitives",
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
            .srfi_192,
            .internal,
            => false,
            // Mixed: %implementation-version/%os-name/%cpu-architecture are
            // harmless (static build info) and stay sandbox = true on their
            // own specs; the filesystem-path-revealing ones (%script-path,
            // %current-lib-dir, %kaappi-lib-dir, %implementation-dir) opt
            // out per-spec instead (primitives_sysinfo.zig). Blocking the
            // whole library here would make those per-spec flags moot for
            // the harmless three. This only governs direct `(import (kaappi
            // sysinfo))`; every portable SRFI layered on it (59, 112, 193)
            // is still unreachable under --sandbox regardless, since it's a
            // `.sld` file and file-backed loads are blocked wholesale
            // (vm_library.libraryIsAvailable) unless embedded.
            .kaappi_sysinfo => true,
            else => true,
        };
    }

    pub fn wasmAvailable(self: Lib) bool {
        return switch (self) {
            .kaappi_ffi, .srfi_18, .srfi_170, .srfi_192 => false,
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
/// Registered in vm.globals, exported by nothing — see `Lib.internal`.
pub const INTERNAL = LS.initOne(.internal);
/// Same, plus exported by `(kaappi primitives)` for the portable `.sld`s that
/// name it in Scheme source — see `Lib.kaappi_primitives`. The `.internal`
/// half is not redundant: it is what puts the spec in the pristine snapshot
/// `Compiler.trueBuiltinRefOrSymbol` resolves against.
pub const INTERNAL_PUBLIC = LS.initMany(&.{ .internal, .kaappi_primitives });
const BR = LS.initMany(&.{ .scheme_base, .scheme_r5rs });
const BRS1 = LS.initMany(&.{ .scheme_base, .scheme_r5rs, .srfi_1 });
const BCRS1 = LS.initMany(&.{ .scheme_base, .scheme_cxr, .scheme_r5rs, .srfi_1 });

/// Shared by the spec entry and every error this primitive reports, so the name
/// a caller sees can never drift from the name it called -- the same convention
/// `primitives_srfi237.zig`'s `MAKE_RTD` follows. It matters more here than for
/// most: drop the `%` and the message names `record?`, a real and *different*
/// procedure `lib/srfi/237.sld` exports, which takes one argument rather than
/// two (kaappi#1916).
const RECORD_CHECK = "%record?";

const core_specs = [_]PrimSpec{
    .{ .name = "cons", .func = &cons, .arity = .{ .exact = 2 }, .libs = BRS1 },
    .{ .name = "car", .func = &car, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "cdr", .func = &cdr, .arity = .{ .exact = 1 }, .libs = BRS1 },
    .{ .name = "set-car!", .func = &setCar, .arity = .{ .exact = 2 }, .libs = BRS1 },
    .{ .name = "set-cdr!", .func = &setCdr, .arity = .{ .exact = 2 }, .libs = BRS1 },
    .{ .name = "list", .func = &list, .arity = .{ .variadic = 0 }, .libs = BRS1 },
    .{ .name = "length", .func = &length, .arity = .{ .exact = 1 }, .libs = BRS1 },
    // There is deliberately no `%length` alias here. case-lambda's arity
    // dispatch needs the real list-length primitive regardless of what
    // `length` means at its use site (kaappi#1714), but it gets that from
    // `Compiler.trueBuiltinRefOrSymbol("length")` -- the pristine
    // `(scheme base)` binding (kaappi#1715) -- rather than a second global.
    // The alias, exported from `(scheme base)`, made a user library that
    // defined its own `%length` un-importable (kaappi#1856); the prefixed
    // reference is also strictly stronger, since a top-level redefinition
    // could overwrite the alias but cannot touch the export table.
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
    // The record substrate `define-record-type`'s desugarer emits and the
    // portable record SRFIs (57/131/136/150/237) call directly. Internal,
    // not `(scheme base)` exports (kaappi#1856). %make-record-type's third
    // argument (per-field metadata, #2088) is optional so count-only
    // callers keep working.
    .{ .name = "%make-record-type", .func = &makeRecordTypeFn, .arity = .{ .range = .{ .min = 2, .max = 3 } }, .libs = INTERNAL_PUBLIC },
    .{ .name = "%make-record", .func = &makeRecordFn, .arity = .{ .variadic = 1 }, .libs = INTERNAL_PUBLIC },
    .{ .name = RECORD_CHECK, .func = &recordCheckFn, .arity = .{ .exact = 2 }, .libs = INTERNAL_PUBLIC },
    .{ .name = "%record-ref", .func = &recordRefFn, .arity = .{ .exact = 3 }, .libs = INTERNAL_PUBLIC },
    .{ .name = "%record-set!", .func = &recordSetFn, .arity = .{ .exact = 4 }, .libs = INTERNAL_PUBLIC },
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
    @import("primitives_srfi254.zig").specs ++
    @import("primitives_srfi258.zig").specs ++
    @import("primitives_srfi260.zig").specs ++
    @import("primitives_srfi211.zig").specs ++
    @import("primitives_srfi181.zig").specs ++
    @import("primitives_srfi237.zig").specs ++
    @import("primitives_srfi160.zig").specs ++
    @import("primitives_sysinfo.zig").specs ++
    primitives_hashtable.specs ++
    primitives_random.specs ++
    @import("primitives_random_port.zig").specs ++
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
    // A `%`-prefixed name must never be exported by an R7RS standard
    // library (kaappi#1856). `%` is this codebase's own "private helper"
    // marker -- and the portable SRFI libraries' -- so user code has good
    // reason to treat that namespace as its own; exporting `%length` from
    // `(scheme base)` made a user library that defines its own `%length`
    // un-importable outright, because R7RS 5.2 makes importing one
    // identifier from two libraries with different bindings an error
    // (enforced since kaappi#1726). Internal helpers belong in `.internal`,
    // which keeps them in vm.globals and out of every export set; a
    // deliberately public `%` name belongs in a `*_primitives`
    // sub-library, which a `.sld` opts into by name.
    for (all_specs) |spec| {
        if (spec.name[0] != '%') continue;
        for (std.enums.values(Lib)) |lib| {
            if (!spec.libs.contains(lib)) continue;
            if (std.mem.startsWith(u8, lib.canonicalName(), "scheme."))
                @compileError("%-prefixed spec \"" ++ spec.name ++ "\" is exported by " ++
                    lib.canonicalName() ++ "; use `.internal` (see Lib.internal) or a *_primitives sub-library");
        }
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
///
/// The tag is `InvalidBytecode` (-> KP9001 "internal error") because that is
/// what an uninstalled bootstrap is: an implementation-invariant violation no
/// program can cause or fix. It read `TypeError` (-> KP3002) until #1876,
/// which told every tool reading the code -- `--diagnostics=json`, the LSP,
/// `error-object-code` -- that the caller had passed a bad argument type.
pub fn bootstrapStub(comptime name: []const u8) types.NativeFnType {
    const S = struct {
        fn call(args: []const Value) PrimitiveError!Value {
            _ = args;
            const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode;
            vm.setErrorDetail("'{s}' is implemented in Scheme (src/vm_bootstrap.zig) but vm_bootstrap.install() has not run for this VM", .{name});
            return PrimitiveError.InvalidBytecode;
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
        return types.rationalToF64(r.numerator, r.denominator);
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
    return PrimitiveError.TypeError; // bare-ok: this is typeError itself
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
    const vm = vm_mod.vm_instance orelse return PrimitiveError.IndexOutOfBounds; // bare-ok: no VM
    vm.setErrorDetail("{s}: index {d} out of range for length {d}", .{ proc, index, len });
    return PrimitiveError.IndexOutOfBounds; // bare-ok: this is indexError itself
}

/// The `typeError`/`indexError` sibling for a constraint that is about neither
/// type nor range: the argument's type is acceptable and the procedure still
/// rejects it (R6RS's "parent is sealed", a uid whose field specs disagree).
/// `explanation` says what the procedure requires, in the caller's own words.
pub fn argError(proc: []const u8, comptime explanation: []const u8, fmt_args: anytype) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidArgument; // bare-ok: no VM
    vm.setErrorDetail("{s}: " ++ explanation, .{proc} ++ fmt_args);
    return PrimitiveError.InvalidArgument; // bare-ok: this is argError itself
}

/// The catchable error a rejected cross-heap store raises (kaappi#1924).
/// The mutation primitives and bytecode stores check
/// `memory.crossHeapStoreViolation` FIRST and call this before the store,
/// so the shared object is never corrupted — the error is a rejection, not
/// an undo. The message mirrors the channel/thread/fiber owner-check style:
/// it names the hazard and points at the supported way to move values
/// across a thread boundary (docs/dev/thread-value-sharing.md).
pub fn raiseCrossHeapStore(proc: []const u8) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [320]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "{s}: cannot store an object created on this thread into a heap object shared with another thread (it would dangle once this thread's heap is freed); pass values through the thread thunk, a channel message, or a join result instead",
        .{proc},
    ) catch "cross-heap store rejected";
    const message = gc.allocString(msg) catch return PrimitiveError.OutOfMemory;
    var msg_root = message;
    gc.pushRoot(&msg_root);
    const err_val = gc.allocErrorObject(msg_root, types.NIL) catch {
        gc.popRoot();
        return PrimitiveError.OutOfMemory;
    };
    gc.popRoot();
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    vm.current_exception = err_val;
    return PrimitiveError.ExceptionRaised;
}

/// Whether non-negative fixnum `idx` is strictly inside `len` on every
/// target, by comparing in u64 BEFORE any narrowing to usize.  On wasm32
/// (usize = u32) a fixnum-range index (up to 2^47) would otherwise truncate
/// inside a `@as(usize, @intCast(...))` bounds comparison and silently alias
/// an in-range element -- a wrong read, and for the set! family a wrong
/// write (kaappi#1912).  `fixnumIndexInBoundsInclusive` is the range-end
/// variant (start/end pairs), where an index equal to the length is legal.
pub inline fn fixnumIndexInBounds(idx: i64, len: usize) bool {
    return idx >= 0 and @as(u64, @intCast(idx)) < @as(u64, len);
}

/// `fixnumIndexInBounds`, but inclusive: `idx <= len`.
pub inline fn fixnumIndexInBoundsInclusive(idx: i64, len: usize) bool {
    return idx >= 0 and @as(u64, @intCast(idx)) <= @as(u64, len);
}

/// Whether fixnum `k` (already known non-negative) fits the target's usize
/// at all — the u64-domain check the `make-*` length conversions need
/// before narrowing (kaappi#2153, the same #1912 class): on wasm32 a length
/// like 10^14 would otherwise truncate inside `@intCast` and silently
/// allocate a far smaller object than requested instead of raising. Callers
/// report it as `OutOfMemory`, which is exactly what the 64-bit GC payload
/// cap (gc_alloc.max_payload_bytes) raises for the same request, so
/// `(guard ...)` sees one cross-platform condition.
pub inline fn fixnumFitsUsize(k: i64) bool {
    return @as(u64, @intCast(k)) <= @as(u64, std.math.maxInt(usize));
}

pub const Range = struct { start: usize, end: usize };

pub fn parseOptionalRange(args: []const Value, arg_offset: usize, max_len: usize, proc_name: []const u8) PrimitiveError!Range {
    var start: usize = 0;
    var end: usize = max_len;
    if (args.len > arg_offset) {
        if (!types.isFixnum(args[arg_offset])) return typeError(proc_name, "exact integer", args[arg_offset]);
        const s = types.toFixnum(args[arg_offset]);
        if (!fixnumIndexInBoundsInclusive(s, max_len)) return indexError(proc_name, s, max_len);
        start = @intCast(s);
    }
    if (args.len > arg_offset + 1) {
        if (!types.isFixnum(args[arg_offset + 1])) return typeError(proc_name, "exact integer", args[arg_offset + 1]);
        const e = types.toFixnum(args[arg_offset + 1]);
        if (!fixnumIndexInBoundsInclusive(e, max_len)) return indexError(proc_name, e, max_len);
        end = @intCast(e);
    }
    if (start > end) return argError(proc_name, "start {d} is greater than end {d}", .{ start, end });
    return .{ .start = start, .end = end };
}

/// Render `value` for a type-error message: enough of its identity that a user
/// can tell *which* value was wrong (kaappi#1899), not just its type.
///
/// This is on the error path of ~700 type-error sites, potentially holding a
/// half-constructed or foreign-owned value, so it stays deliberately
/// conservative — the same properties the flonum note below relied on:
///   (a) **No allocation and no VM callback.** Everything is read directly out
///       of the value or its object header; nothing calls the GC or the
///       interpreter. Bignum/rational rendering therefore only covers what
///       fits in a stack `u128` (`writeExactInteger`); a larger magnitude,
///       which would need heap scratch to stringify, falls back to `#<bignum>`
///       / `#<rational>`.
///   (b) **Bounded output.** Writing through a fixed 128-byte `Io.Writer`,
///       every write is capped by the buffer; strings and symbols are
///       additionally truncated with `...` before they get there, so a
///       megabyte string or million-element vector can never be dumped into a
///       diagnostic.
///   (c) **No recursion into heap structure.** Compound types render a
///       one-level summary (a vector/bytevector reports its length; a rational
///       renders its two exact-integer components), never a recursive print —
///       so a cyclic structure cannot make this loop.
/// `pub` since #2002: primitives_fiber.makeChannelFn's range rejection needs
/// the offending value in its argError message ("…between 0 and 4294967295,
/// got <value>") without duplicating this deliberately-defensive renderer.
pub fn safeValueDescription(buf: *[128]u8, value: Value) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    describeValue(&w, value);
    const out = w.buffered();
    return if (out.len == 0) "?" else out;
}

/// Best-effort renderer for `safeValueDescription`. All writes are `catch {}`:
/// a full buffer just truncates the description rather than propagating an
/// error out of the error path.
fn describeValue(w: *std.Io.Writer, value: Value) void {
    if (types.isFixnum(value)) {
        w.print("{d}", .{types.toFixnum(value)}) catch {};
        return;
    }
    if (value == types.NIL) return w.writeAll("()") catch {};
    if (value == types.TRUE) return w.writeAll("#t") catch {};
    if (value == types.FALSE) return w.writeAll("#f") catch {};
    if (value == types.VOID) return w.writeAll("#<void>") catch {};
    if (value == types.EOF) return w.writeAll("#<eof>") catch {};
    if (types.isChar(value)) return describeChar(w, types.toChar(value));
    if (types.isFlonum(value)) {
        // Via the printer, not a bare `{d}`, so an integral flonum keeps its
        // `.0`. Without it `(… 1.0)` reported "expected exact integer, got 1",
        // and 1 *is* an exact integer -- the message argued against itself
        // (kaappi#1916). Safe in this deliberately-defensive helper: a flonum
        // is inline under NaN-boxing, so `formatFlonum` reads no heap and
        // handles NaN/Inf itself.
        var fbuf: [64]u8 = undefined;
        w.writeAll(printer.formatFlonum(&fbuf, types.toFlonum(value))) catch {};
        return;
    }
    if (types.isPointer(value)) {
        const addr = @as(usize, @truncate(value));
        if (addr == 0 or addr < 4096) return w.writeAll("#<invalid-pointer>") catch {};
        const obj = types.toObject(value);
        const tag = @intFromEnum(obj.tag);
        if (tag >= @typeInfo(types.ObjectTag).@"enum".fields.len)
            return w.print("#<corrupt tag={d}>", .{tag}) catch {};
        switch (obj.tag) {
            // Symbol name is inline in the object (interned, no allocation);
            // print it so `(string-length 'foo)` says `got foo`, not `#<symbol>`.
            .symbol => describeBounded(w, obj.as(types.Symbol).name, 96),
            .string => {
                const s = obj.as(types.SchemeString);
                describeString(w, s.data[0..s.len]);
            },
            // Length, not contents: cheap, cycle-safe, and far more useful than
            // a bare tag (kaappi#1899). A one-level element preview would have
            // to guard against cyclic vectors; length needs no such guard.
            .vector => w.print("#<vector length {d}>", .{obj.as(types.Vector).data.len}) catch {},
            .bytevector => w.print("#<bytevector length {d}>", .{obj.as(types.Bytevector).data.len}) catch {},
            .bignum => if (!writeExactInteger(w, value)) {
                w.writeAll("#<bignum>") catch {};
            },
            .rational => {
                const r = obj.as(types.Rational);
                // Numerator and denominator are each a fixnum or bignum -- never
                // a pointer to a compound, so this cannot recurse or cycle.
                if (writeExactInteger(w, r.numerator)) {
                    w.writeByte('/') catch {};
                    if (!writeExactInteger(w, r.denominator)) w.writeAll("...") catch {};
                } else {
                    w.writeAll("#<rational>") catch {};
                }
            },
            .pair => w.writeAll("#<pair>") catch {},
            .closure, .native_fn, .function, .native_closure => w.writeAll("#<procedure>") catch {},
            .hash_table => w.writeAll("#<hash-table>") catch {},
            else => w.print("#<{s}>", .{@tagName(obj.tag)}) catch {},
        }
        return;
    }
    w.print("0x{x}", .{value}) catch {};
}

/// Write an exact integer (fixnum or a bignum small enough to fit a `u128`)
/// in decimal. Returns false, having written nothing, for a bignum too large
/// to stringify without heap scratch -- the caller renders `#<bignum>` then.
fn writeExactInteger(w: *std.Io.Writer, value: Value) bool {
    if (types.isFixnum(value)) {
        w.print("{d}", .{types.toFixnum(value)}) catch return false;
        return true;
    }
    if (types.isPointer(value) and types.toObject(value).tag == .bignum) {
        const bn = types.toObject(value).as(types.Bignum);
        if (bn.len == 0) {
            w.writeAll("0") catch return false;
            return true;
        }
        if (bn.len > 2) return false; // magnitude exceeds u128 -- needs allocation
        var mag: u128 = 0;
        var i: usize = bn.len;
        while (i > 0) {
            i -= 1;
            mag = (mag << 64) | bn.limbs[i];
        }
        if (!bn.positive) w.writeByte('-') catch return false;
        w.print("{d}", .{mag}) catch return false;
        return true;
    }
    return false;
}

/// Render a character in its `#\` external representation (kaappi#1899: chars
/// are immediates and were rendering as the opaque `#<char>`). Mirrors the
/// named/hex forms of `printer.printValueOnce`, but self-contained so it reads
/// no heap.
fn describeChar(w: *std.Io.Writer, cp: u21) void {
    w.writeAll("#\\") catch {};
    switch (cp) {
        0x00 => return w.writeAll("null") catch {},
        0x07 => return w.writeAll("alarm") catch {},
        0x08 => return w.writeAll("backspace") catch {},
        0x09 => return w.writeAll("tab") catch {},
        0x0A => return w.writeAll("newline") catch {},
        0x0D => return w.writeAll("return") catch {},
        0x1B => return w.writeAll("escape") catch {},
        0x20 => return w.writeAll("space") catch {},
        0x7F => return w.writeAll("delete") catch {},
        else => {},
    }
    if (cp < 0x20 or (cp >= 0x7F and cp <= 0x9F)) {
        w.print("x{x}", .{cp}) catch {};
    } else {
        var cbuf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &cbuf) catch 0;
        w.writeAll(cbuf[0..len]) catch {};
    }
}

/// Write `s` truncated to at most `cap` bytes, with a trailing `...` when cut.
/// Truncation backs off to a UTF-8 boundary so a diagnostic never emits a
/// split multibyte sequence.
fn describeBounded(w: *std.Io.Writer, s: []const u8, cap: usize) void {
    if (s.len <= cap) {
        w.writeAll(s) catch {};
        return;
    }
    var end = cap;
    while (end > 0 and (s[end] & 0xC0) == 0x80) end -= 1; // don't split a codepoint
    w.writeAll(s[0..end]) catch {};
    w.writeAll("...") catch {};
}

/// Write a bounded, quoted, escaped prefix of a string value.
fn describeString(w: *std.Io.Writer, s: []const u8) void {
    const cap: usize = 32;
    w.writeByte('"') catch {};
    var n = @min(s.len, cap);
    while (n > 0 and n < s.len and (s[n] & 0xC0) == 0x80) n -= 1; // don't split a codepoint
    for (s[0..n]) |c| {
        switch (c) {
            '"' => w.writeAll("\\\"") catch {},
            '\\' => w.writeAll("\\\\") catch {},
            '\n' => w.writeAll("\\n") catch {},
            '\t' => w.writeAll("\\t") catch {},
            '\r' => w.writeAll("\\r") catch {},
            else => w.writeByte(c) catch {},
        }
    }
    w.writeByte('"') catch {};
    if (n < s.len) w.writeAll("...") catch {};
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
    if (types.toObject(args[0]).flags.immutable) return argError("set-car!", "cannot mutate an immutable pair", .{});
    // #1924: reject before the store — a shared parent-heap pair must not
    // come to hold a child-heap object.
    if (memory.crossHeapStoreViolation(types.toObject(args[0]), args[1])) return raiseCrossHeapStore("set-car!");
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    types.setCar(args[0], args[1]);
    return types.VOID;
}

fn setCdr(args: []const Value) PrimitiveError!Value {
    if (!types.isPair(args[0])) return typeError("set-cdr!", "pair", args[0]);
    if (types.toObject(args[0]).flags.immutable) return argError("set-cdr!", "cannot mutate an immutable pair", .{});
    if (memory.crossHeapStoreViolation(types.toObject(args[0]), args[1])) return raiseCrossHeapStore("set-cdr!");
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
        // A stored complex with an exact zero imaginary part is demoted to
        // its real component at construction, so the only complexes that
        // reach this arm have a nonzero or inexact-zero imag (3.0+0.0i, the
        // -0.0i srfi160 decode) — none of which is an integer (kaappi#2166).
        return types.FALSE;
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
        // Only an exact zero imaginary part would make a complex real, and
        // such values are demoted to their real component at construction
        // (kaappi#2166); the -0.0i srfi160 decode keeps its sign and stays
        // non-real (kaappi#1951).
        const numeric = @import("primitives_numeric.zig");
        return if (types.isExactNumber(c.imag) and numeric.isZeroValue(c.imag)) types.TRUE else types.FALSE;
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
    // as flonums, so NaN/-0.0 behave consistently) AND their exactness flags
    // agree — R7RS 6.1 requires #f when one is exact and the other inexact.
    if (types.isComplex(args[0]) and types.isComplex(args[1])) {
        return if (types.complexEqv(args[0], args[1])) types.TRUE else types.FALSE;
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
        return types.complexEqv(a, b);
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
    if (types.isNumericVector(a) and types.isNumericVector(b)) {
        const na = types.toNumericVector(a);
        const nb = types.toNumericVector(b);
        return na.kind == nb.kind and std.mem.eql(u8, na.data, nb.data);
    }
    if (types.isRecordInstance(a) and types.isRecordInstance(b)) {
        const ra = types.toObject(a).as(types.RecordInstance);
        const rb = types.toObject(b).as(types.RecordInstance);
        // Same record type required (identity, not pointer -- a type
        // survives an SRFI-18 thread hop at a new address, kaappi#1932), then
        // fields compared pairwise. R7RS 6.1 leaves records in the "all other
        // cases" clause, so this structural choice is a permitted extension
        // that matches Gambit/Guile/Chibi (kaappi#2293).
        if (!types.sameRecordType(ra.record_type, rb.record_type)) return false;
        // Defensive: sameRecordType already implies equal field counts (both
        // instances are sized from record_type.num_fields), so this is a cheap
        // belt-and-suspenders guard, not a load-bearing check.
        if (ra.fields.len != rb.fields.len) return false;
        const key = VisitedKey{ .a = a, .b = b };
        if (visited.get(key) != null) return true;
        visited.put(key, {}) catch {};
        for (ra.fields, rb.fields) |fa, fb| {
            if (!deepEqualWithVisited(fa, fb, visited)) return false;
        }
        return true;
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

/// The `vm_instance` guard is `InvalidBytecode` (-> KP9001 "internal error")
/// even though `apply` raises real `typeError`s a few lines down, for a
/// non-procedure and for an improper final list (#1878). Those report what the
/// caller passed; the guard reports that `apply` cannot run at all, because it
/// fetches the VM in order to *call* the procedure rather than to attach a
/// message to an error it was already raising. The `gc_instance` line below is
/// the other case and keeps `OutOfMemory`: the allocations it protects return
/// exactly that. See "Tagging the vm_instance / gc_instance guards" in
/// `docs/dev/gc-safety-and-error-handling.md`.
fn applyFn(args: []const Value) PrimitiveError!Value {
    const vm = @import("vm.zig").vm_instance orelse return PrimitiveError.InvalidBytecode;
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
    // args[0] = name (string), args[1] = num_fields (fixnum), and optionally
    // args[2] = per-field metadata: a list of (name-string . mutable?) pairs,
    // the same shape %make-record-type-descriptor's field-specs argument
    // uses. Present exactly when the emitting define-record-type desugarer
    // knows the field names (#2088 -- the R7RS paths joined the R6RS and
    // procedural ones); absent for count-only callers.
    const name_data = try expectString("%make-record-type", args[0]);
    const nf = try expectFixnum("%make-record-type", args[1]);
    if (nf < 0 or nf > 255) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const num_fields: u8 = @intCast(nf);

    if (args.len == 2) {
        return gc.allocRecordType(name_data, num_fields) catch return PrimitiveError.OutOfMemory;
    }

    var field_names_buf: [256][]const u8 = undefined;
    var field_mutable_buf: [256]bool = undefined;
    var field_count: usize = 0;
    var specs_cur = args[2];
    while (specs_cur != types.NIL) {
        if (!types.isPair(specs_cur)) return typeError("%make-record-type", "list", args[2]);
        const entry = types.car(specs_cur);
        if (!types.isPair(entry)) return typeError("%make-record-type", "(name . mutable?) pair", entry);
        if (field_count >= 255) return PrimitiveError.TypeError; // bare-ok: internal record primitive
        field_names_buf[field_count] = try expectString("%make-record-type", types.car(entry));
        field_mutable_buf[field_count] = types.cdr(entry) != types.FALSE;
        field_count += 1;
        specs_cur = types.cdr(specs_cur);
    }
    // The count and the specs describe one type; disagreeing is an invalid
    // argument combination, not a type error.
    if (field_count != nf) {
        return argError(
            "%make-record-type",
            "field-specs list has {d} entries but the declared field count is {d}",
            .{ field_count, nf },
        );
    }

    // A parentless, generative, transparent type: %make-record-type has no
    // way to ask for anything else, so TooManyFields is unreachable here
    // (both the count and the specs list are capped at 255 above).
    return gc.allocRecordTypeExtended(
        name_data,
        null,
        field_names_buf[0..field_count],
        field_mutable_buf[0..field_count],
        null,
        false,
        false,
    ) catch return PrimitiveError.OutOfMemory;
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
    if (!types.isRecordType(args[1])) return typeError(RECORD_CHECK, "record-type", args[1]);
    const rt = types.toObject(args[1]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return types.FALSE;
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    return if (types.sameRecordType(ri.record_type, rt)) types.TRUE else types.FALSE;
}

fn recordRefFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum), args[2] = expected record type
    if (!types.isRecordType(args[2])) return typeError("%record-ref", "record-type", args[2]);
    const rt = types.toObject(args[2]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return typeError("%record-ref", rt.name, args[0]);
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    if (!types.sameRecordType(ri.record_type, rt)) return typeError("%record-ref", rt.name, args[0]);
    if (!types.isFixnum(args[1])) return typeError("%record-ref", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    // u64 comparison before narrowing (kaappi#1912): see fixnumIndexInBounds.
    if (!fixnumIndexInBounds(raw_idx, ri.fields.len)) return indexError("%record-ref", raw_idx, ri.fields.len);
    const idx: usize = @intCast(raw_idx);
    return ri.fields[idx];
}

fn recordSetFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = field index (fixnum), args[2] = new value, args[3] = expected record type
    if (!types.isRecordType(args[3])) return typeError("%record-set!", "record-type", args[3]);
    const rt = types.toObject(args[3]).as(types.RecordType);
    if (!types.isRecordInstance(args[0])) return typeError("%record-set!", rt.name, args[0]);
    const ri = types.toObject(args[0]).as(types.RecordInstance);
    if (!types.sameRecordType(ri.record_type, rt)) return typeError("%record-set!", rt.name, args[0]);
    if (!types.isFixnum(args[1])) return typeError("%record-set!", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    // u64 comparison before narrowing (kaappi#1912): see fixnumIndexInBounds.
    if (!fixnumIndexInBounds(raw_idx, ri.fields.len)) return indexError("%record-set!", raw_idx, ri.fields.len);
    const idx: usize = @intCast(raw_idx);
    if (memory.crossHeapStoreViolation(types.toObject(args[0]), args[2])) return raiseCrossHeapStore("%record-set!");
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
