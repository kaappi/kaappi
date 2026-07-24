//! SRFI 237 — R6RS Records, refined for R7RS.
//!
//! The syntactic layer (`define-record-type` accepting R6RS clause syntax)
//! is a Zig-level desugarer in vm_records.zig, exactly like R7RS's own
//! `define-record-type` -- it needs no primitives of its own beyond the
//! ones already backing R7RS records (`%make-record`, `%record-ref`,
//! `%record-set!`) plus the inheritance-aware variants below.
//!
//! This file supplies the pieces the *procedural* layer (`lib/srfi/237/
//! base.sld`: `make-record-type-descriptor`, `record-constructor`,
//! `record-predicate`, `record-accessor`, `record-mutator`, and every
//! inspection procedure) cannot do in portable Scheme:
//!   - %make-record-type-descriptor: allocates a RecordType with
//!     inheritance/uid/sealed/opaque metadata (memory.GC.allocRecordTypeExtended).
//!     `name`/`uid` are plain strings and field-specs is a list of
//!     `(name-string . mutable?)` pairs -- the portable layer converts to
//!     and from symbols at its own boundary, keeping this primitive's
//!     contract minimal (the same "internal primitive, light validation"
//!     convention as %make-record-type/%record-ref/%record-set! already
//!     use, since only this file's own lib/srfi/237/base.sld calls it).
//!   - %record?/inherit, %record-ref/inherit, %record-set!/inherit: like
//!     the R7RS %record?/%record-ref/%record-set!, but walk `parent` so a
//!     subtype instance satisfies an ancestor's predicate/accessor/mutator
//!     (R7RS's own primitives stay exact-type-only, unchanged, since
//!     R7RS's define-record-type has no inheritance to support).
//!   - Inspection one-liners over RecordType's new fields.
//!
//! `%record-field-mutable?`/the field-names list operate on THIS type's
//! OWN fields only (RecordType.own_field_names/own_field_mutable), not the
//! full inherited set -- matching SRFI 237's `record-type-field-names`,
//! which is documented as returning only a type's own fields. The
//! portable layer walks `record-type-parent` to build an absolute
//! field-index mapping when it needs one (e.g. inside `record-accessor`).
//!
//! Registered under `.srfi_237_primitives` ("srfi.237.primitives"), not a
//! bare `.srfi_237`: the public `(srfi 237)` is `lib/srfi/237.sld`, which
//! imports this sub-library and re-exports its full surface --
//! `vm.libraries`'s startup registration otherwise shadows a same-named
//! `.sld` outright (see `.srfi_248_primitives`/`.srfi_181_primitives` for
//! the identical, already-solved problem).
//!
//! Nothing here touches platform.zig, threads, or FFI -- every operation
//! is plain heap/Value manipulation, so this library needs no
//! sandboxAllowed/wasmAvailable exclusion (falls into Lib's `else => true`
//! default for both, same reasoning as SRFI 181's custom ports).

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const PrimitiveError = primitives.PrimitiveError;
const typeError = primitives.typeError;
const indexError = primitives.indexError;
const expectString = primitives.expectString;
const expectFixnum = primitives.expectFixnum;
const LS = primitives.LibSet;

const SRFI237 = LS.initOne(.srfi_237_primitives);
// %record?/inherit, %record-ref/inherit, %record-set!/inherit, and
// %record-split-args are referenced directly by vm_records.zig's R6RS
// desugarer's GENERATED code, exactly like the original R7RS %make-record/
// %record?/%record-ref/%record-set! already are -- so they need the same
// unconditional `.scheme_base` visibility those have (core_specs in
// primitives.zig), not the `.srfi_237_primitives` sub-library tag, which
// only gates what `lib/srfi/237/base.sld`'s own procedural-layer Scheme
// code can `(import (srfi 237 primitives))`.
const BASE = LS.initOne(.scheme_base);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "%make-record-type-descriptor", .func = &makeRecordTypeDescriptorFn, .arity = .{ .exact = 6 }, .libs = SRFI237 },
    .{ .name = "%record?/inherit", .func = &recordCheckInheritFn, .arity = .{ .exact = 2 }, .libs = BASE },
    .{ .name = "%record-ref/inherit", .func = &recordRefInheritFn, .arity = .{ .exact = 3 }, .libs = BASE },
    .{ .name = "%record-set!/inherit", .func = &recordSetInheritFn, .arity = .{ .exact = 4 }, .libs = BASE },
    .{ .name = "%record-split-args", .func = &recordSplitArgsFn, .arity = .{ .exact = 2 }, .libs = BASE },
    .{ .name = "%record?/any", .func = &recordCheckAnyFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-rtd", .func = &recordRtdFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-name", .func = &recordTypeNameFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-parent", .func = &recordTypeParentFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-uid", .func = &recordTypeUidFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-generative?", .func = &recordTypeGenerativeFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-sealed?", .func = &recordTypeSealedFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-opaque?", .func = &recordTypeOpaqueFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-field-names", .func = &recordTypeFieldNamesFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-field-mutable?", .func = &recordFieldMutableFn, .arity = .{ .exact = 2 }, .libs = SRFI237 },
    .{ .name = "%record-type?", .func = &recordTypeCheckFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-type-total-field-count", .func = &recordTypeTotalFieldCountFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
    .{ .name = "%record-uid->rtd", .func = &recordUidToRtdFn, .arity = .{ .exact = 1 }, .libs = SRFI237 },
};

fn asRecordType(v: Value) *RecordType {
    return types.toObject(v).as(RecordType);
}

/// Walks from `start` up through `.parent` looking for `target` -- the
/// inheritance-aware analogue of R7RS's `ri.record_type == rt` exact check.
fn isOrDescendsFrom(start: *RecordType, target: *RecordType) bool {
    var rt: ?*RecordType = start;
    while (rt) |r| {
        if (r == target) return true;
        rt = r.parent;
    }
    return false;
}

fn makeRecordTypeDescriptorFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    // args: name(string), parent(record-type-or-#f), uid(string-or-#f),
    // sealed?(bool), opaque?(bool), field-specs(list of (name-string . mutable?))
    const name = try expectString("%make-record-type-descriptor", args[0]);

    const parent: ?*RecordType = if (args[1] == types.FALSE)
        null
    else blk: {
        if (!types.isRecordType(args[1])) return typeError("%make-record-type-descriptor", "record-type", args[1]);
        break :blk asRecordType(args[1]);
    };

    const uid: ?[]const u8 = if (args[2] == types.FALSE)
        null
    else
        try expectString("%make-record-type-descriptor", args[2]);

    const sealed = args[3] != types.FALSE;
    const is_opaque = args[4] != types.FALSE;

    // nongenerative: reuse an existing RTD registered under this uid rather
    // than allocating a new, non-interoperable one.
    if (uid) |u| {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
        if (vm.record_uid_registry.get(u)) |existing| return existing;
    }

    var field_names_buf: [256][]const u8 = undefined;
    var field_mutable_buf: [256]bool = undefined;
    var field_count: usize = 0;
    var specs_cur = args[5];
    while (specs_cur != types.NIL) {
        if (!types.isPair(specs_cur)) return typeError("%make-record-type-descriptor", "list", args[5]);
        const entry = types.car(specs_cur);
        if (!types.isPair(entry)) return typeError("%make-record-type-descriptor", "(name . mutable?) pair", entry);
        if (field_count >= 256) return PrimitiveError.TypeError; // bare-ok: internal record primitive
        field_names_buf[field_count] = try expectString("%make-record-type-descriptor", types.car(entry));
        field_mutable_buf[field_count] = types.cdr(entry) != types.FALSE;
        field_count += 1;
        specs_cur = types.cdr(specs_cur);
    }

    var new_val = gc.allocRecordTypeExtended(
        name,
        parent,
        field_names_buf[0..field_count],
        field_mutable_buf[0..field_count],
        uid,
        sealed,
        is_opaque,
    ) catch return PrimitiveError.OutOfMemory;

    if (uid) |u| {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
        // Root across put(): a Value reachable only from this local isn't
        // yet visible to markVMRoots' registry scan until the insert lands.
        gc.pushRoot(&new_val);
        defer gc.popRoot();
        vm.record_uid_registry.put(u, new_val) catch return PrimitiveError.OutOfMemory;
    }

    return new_val;
}

fn recordCheckInheritFn(args: []const Value) PrimitiveError!Value {
    // args[0] = value to check, args[1] = record-type
    if (!types.isRecordType(args[1])) return typeError("%record?/inherit", "record-type", args[1]);
    const target = asRecordType(args[1]);
    if (!types.isRecordInstance(args[0])) return types.FALSE;
    const ri = types.toObject(args[0]).as(RecordInstance);
    return if (isOrDescendsFrom(ri.record_type, target)) types.TRUE else types.FALSE;
}

fn recordCheckAnyFn(args: []const Value) PrimitiveError!Value {
    return if (types.isRecordInstance(args[0])) types.TRUE else types.FALSE;
}

fn recordRefInheritFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = absolute field index, args[2] = record-type
    if (!types.isRecordType(args[2])) return typeError("%record-ref/inherit", "record-type", args[2]);
    const rt = asRecordType(args[2]);
    if (!types.isRecordInstance(args[0])) return typeError("%record-ref/inherit", rt.name, args[0]);
    const ri = types.toObject(args[0]).as(RecordInstance);
    if (!isOrDescendsFrom(ri.record_type, rt)) return typeError("%record-ref/inherit", rt.name, args[0]);
    if (!types.isFixnum(args[1])) return typeError("%record-ref/inherit", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const idx: usize = @intCast(raw_idx);
    if (idx >= ri.fields.len) return indexError("%record-ref/inherit", raw_idx, ri.fields.len);
    return ri.fields[idx];
}

/// Splits `args[0]` (a list) into a (prefix . suffix) pair, where suffix is
/// the last `args[1]` elements. Backs the R6RS-clause `define-record-type`
/// desugarer's no-explicit-protocol subtype constructor: it needs to
/// forward "everything but this type's own field args" to the parent's
/// constructor without knowing that prefix's length at compile time (the
/// parent's own constructor might itself have an arbitrary-arity protocol),
/// so the split happens at runtime instead, from the tail (own field count
/// is always known) rather than the head. Not part of SRFI 237's public
/// surface -- an implementation detail of the desugarer, same category as
/// %make-record/%record-ref themselves.
fn recordSplitArgsFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const suffix_len_raw = try expectFixnum("%record-split-args", args[1]);
    if (suffix_len_raw < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const suffix_len: usize = @intCast(suffix_len_raw);

    var buf: [256]Value = undefined;
    var n: usize = 0;
    var cur = args[0];
    while (cur != types.NIL) {
        if (!types.isPair(cur)) return typeError("%record-split-args", "list", args[0]);
        if (n >= 256) return PrimitiveError.TypeError; // bare-ok: internal record primitive
        buf[n] = types.car(cur);
        n += 1;
        cur = types.cdr(cur);
    }
    if (suffix_len > n) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const split = n - suffix_len;

    var prefix = gc.makeList(buf[0..split]) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&prefix);
    defer gc.popRoot();
    const suffix = gc.makeList(buf[split..n]) catch return PrimitiveError.OutOfMemory;
    return gc.allocPair(prefix, suffix) catch return PrimitiveError.OutOfMemory;
}

fn recordSetInheritFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record instance, args[1] = absolute field index, args[2] = new value, args[3] = record-type
    if (!types.isRecordType(args[3])) return typeError("%record-set!/inherit", "record-type", args[3]);
    const rt = asRecordType(args[3]);
    if (!types.isRecordInstance(args[0])) return typeError("%record-set!/inherit", rt.name, args[0]);
    const ri = types.toObject(args[0]).as(RecordInstance);
    if (!isOrDescendsFrom(ri.record_type, rt)) return typeError("%record-set!/inherit", rt.name, args[0]);
    if (!types.isFixnum(args[1])) return typeError("%record-set!/inherit", "exact integer", args[1]);
    const raw_idx = types.toFixnum(args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const idx: usize = @intCast(raw_idx);
    if (idx >= ri.fields.len) return indexError("%record-set!/inherit", raw_idx, ri.fields.len);
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[2]);
    ri.fields[idx] = args[2];
    return types.VOID;
}

fn recordRtdFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordInstance(args[0])) return typeError("%record-rtd", "record", args[0]);
    const ri = types.toObject(args[0]).as(RecordInstance);
    return types.makePointer(&ri.record_type.header);
}

fn recordTypeNameFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-name", "record-type", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rt = asRecordType(args[0]);
    return gc.allocSymbol(rt.name) catch return PrimitiveError.OutOfMemory;
}

fn recordTypeParentFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-parent", "record-type", args[0]);
    const rt = asRecordType(args[0]);
    if (rt.parent) |p| return types.makePointer(&p.header);
    return types.FALSE;
}

fn recordTypeUidFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-uid", "record-type", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rt = asRecordType(args[0]);
    if (rt.uid) |u| return gc.allocSymbol(u) catch return PrimitiveError.OutOfMemory;
    return types.FALSE;
}

fn recordTypeGenerativeFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-generative?", "record-type", args[0]);
    const rt = asRecordType(args[0]);
    return if (rt.uid == null) types.TRUE else types.FALSE;
}

fn recordTypeSealedFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-sealed?", "record-type", args[0]);
    const rt = asRecordType(args[0]);
    return if (rt.sealed) types.TRUE else types.FALSE;
}

fn recordTypeOpaqueFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-opaque?", "record-type", args[0]);
    const rt = asRecordType(args[0]);
    return if (rt.is_opaque) types.TRUE else types.FALSE;
}

fn recordTypeFieldNamesFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-field-names", "record-type", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rt = asRecordType(args[0]);
    var syms: [256]Value = undefined;
    for (rt.own_field_names, 0..) |fname, i| {
        syms[i] = gc.allocSymbol(fname) catch return PrimitiveError.OutOfMemory;
    }
    return gc.makeList(syms[0..rt.own_field_names.len]) catch return PrimitiveError.OutOfMemory;
}

fn recordFieldMutableFn(args: []const Value) PrimitiveError!Value {
    // args[0] = record-type, args[1] = OWN field index (fixnum)
    if (!types.isRecordType(args[0])) return typeError("%record-field-mutable?", "record-type", args[0]);
    const rt = asRecordType(args[0]);
    const raw_idx = try expectFixnum("%record-field-mutable?", args[1]);
    if (raw_idx < 0) return PrimitiveError.TypeError; // bare-ok: internal record primitive
    const idx: usize = @intCast(raw_idx);
    if (idx >= rt.own_field_mutable.len) return indexError("%record-field-mutable?", raw_idx, rt.own_field_mutable.len);
    return if (rt.own_field_mutable[idx]) types.TRUE else types.FALSE;
}

fn recordTypeCheckFn(args: []const Value) PrimitiveError!Value {
    return if (types.isRecordType(args[0])) types.TRUE else types.FALSE;
}

/// Total field count INCLUDING inherited fields -- what record-constructor
/// needs to compute "how many of an rtd's fields are this level's own"
/// (own = total(this) - total(parent)) without a dedicated own-count
/// primitive, and what a from-scratch %record-ref/%record-ref/inherit loop
/// over a freshly-materialized instance needs as its upper bound.
fn recordTypeTotalFieldCountFn(args: []const Value) PrimitiveError!Value {
    if (!types.isRecordType(args[0])) return typeError("%record-type-total-field-count", "record-type", args[0]);
    const rt = asRecordType(args[0]);
    return types.makeFixnum(rt.num_fields);
}

fn recordUidToRtdFn(args: []const Value) PrimitiveError!Value {
    const uid = try expectString("%record-uid->rtd", args[0]);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    if (vm.record_uid_registry.get(uid)) |rt_val| return rt_val;
    return types.FALSE;
}
