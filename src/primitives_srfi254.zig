//! SRFI-254 — Ephemerons and Guardians.
//!
//! The constructors, predicates and accessors live here as ordinary native
//! procedures; the interesting parts are elsewhere:
//!   * the weak-reference garbage-collection semantics are in
//!     gc_collect.processWeakRefs (marking, resurrection, breaking), and
//!   * guardian *invocation* — a guardian is itself callable — is in
//!     vm_calls.invokeGuardian, wired into every call-dispatch site.
//!
//! On Kaappi's non-moving collector `current-hash` is a stable identity hash
//! and transport cell guardians are degenerate: keys never move, so a cell is
//! never transported and a zero-argument transport-cell-guardian call always
//! returns #f. See the SRFI-254 section of README/CLAUDE for the rationale.

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

// Library membership sets. Every identifier is also exported by the composite
// (srfi 254) and (srfi 254 ephemerons-and-guardians) libraries.
const EPH = LS.initMany(&.{ .srfi_254_ephemerons, .srfi_254_ephemerons_and_guardians, .srfi_254 });
const GUA = LS.initMany(&.{ .srfi_254_guardians, .srfi_254_ephemerons_and_guardians, .srfi_254 });
const TCG = LS.initMany(&.{ .srfi_254_transport_cell_guardians, .srfi_254_ephemerons_and_guardians, .srfi_254 });
// reference-barrier is exported by both the ephemerons and guardians libraries.
const REFBAR = LS.initMany(&.{ .srfi_254_ephemerons, .srfi_254_guardians, .srfi_254_ephemerons_and_guardians, .srfi_254 });

pub const specs = [_]primitives.PrimSpec{
    // Ephemerons
    .{ .name = "make-ephemeron", .func = &makeEphemeron, .arity = .{ .exact = 2 }, .libs = EPH },
    .{ .name = "ephemeron?", .func = &ephemeronP, .arity = .{ .exact = 1 }, .libs = EPH },
    .{ .name = "ephemeron-key", .func = &ephemeronKey, .arity = .{ .exact = 1 }, .libs = EPH },
    .{ .name = "ephemeron-value", .func = &ephemeronValue, .arity = .{ .exact = 1 }, .libs = EPH },
    .{ .name = "ephemeron-broken?", .func = &ephemeronBrokenP, .arity = .{ .exact = 1 }, .libs = EPH },
    .{ .name = "ephemeron-ref", .func = &ephemeronRef, .arity = .{ .variadic = 2 }, .libs = EPH },

    // Guardians
    .{ .name = "make-guardian", .func = &makeGuardian, .arity = .{ .exact = 0 }, .libs = GUA },
    .{ .name = "guardian?", .func = &guardianP, .arity = .{ .exact = 1 }, .libs = GUA },

    // Transport cell guardians
    .{ .name = "make-transport-cell-guardian", .func = &makeTransportCellGuardian, .arity = .{ .exact = 0 }, .libs = TCG },
    .{ .name = "transport-cell-guardian?", .func = &transportCellGuardianP, .arity = .{ .exact = 1 }, .libs = TCG },
    .{ .name = "transport-cell?", .func = &transportCellP, .arity = .{ .exact = 1 }, .libs = TCG },
    .{ .name = "transport-cell-key", .func = &transportCellKey, .arity = .{ .exact = 1 }, .libs = TCG },
    .{ .name = "transport-cell-value", .func = &transportCellValue, .arity = .{ .exact = 1 }, .libs = TCG },
    .{ .name = "transport-cell-broken?", .func = &transportCellBrokenP, .arity = .{ .exact = 1 }, .libs = TCG },
    .{ .name = "current-hash", .func = &currentHash, .arity = .{ .exact = 1 }, .libs = TCG },

    // Shared
    .{ .name = "reference-barrier", .func = &referenceBarrier, .arity = .{ .exact = 1 }, .libs = REFBAR },
};

// --- Ephemerons ------------------------------------------------------------

fn makeEphemeron(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocEphemeron(args[0], args[1]) catch return PrimitiveError.OutOfMemory;
}

fn ephemeronP(args: []const Value) PrimitiveError!Value {
    return if (types.isEphemeron(args[0])) types.TRUE else types.FALSE;
}

fn ephemeronKey(args: []const Value) PrimitiveError!Value {
    if (!types.isEphemeron(args[0])) return primitives.typeError("ephemeron-key", "ephemeron", args[0]);
    // The key field is cleared to #f when the ephemeron breaks, so this already
    // returns #f for a broken ephemeron.
    return types.toEphemeron(args[0]).key;
}

fn ephemeronValue(args: []const Value) PrimitiveError!Value {
    if (!types.isEphemeron(args[0])) return primitives.typeError("ephemeron-value", "ephemeron", args[0]);
    return types.toEphemeron(args[0]).value;
}

fn ephemeronBrokenP(args: []const Value) PrimitiveError!Value {
    if (!types.isEphemeron(args[0])) return primitives.typeError("ephemeron-broken?", "ephemeron", args[0]);
    return if (types.toEphemeron(args[0]).broken) types.TRUE else types.FALSE;
}

fn ephemeronRef(args: []const Value) PrimitiveError!Value {
    if (!types.isEphemeron(args[0])) return primitives.typeError("ephemeron-ref", "ephemeron", args[0]);
    if (args.len > 3) {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.ArityMismatch;
        vm.setErrorDetail("'ephemeron-ref': expected 2 or 3 arguments, got {d}", .{args.len});
        return PrimitiveError.ArityMismatch;
    }
    const eph = types.toEphemeron(args[0]);
    const default: Value = if (args.len == 3) args[2] else types.FALSE;
    if (eph.broken) return default;
    // eq? comparison of Values is identity on the boxed word.
    return if (eph.key == args[1]) eph.value else default;
}

// --- Guardians -------------------------------------------------------------

fn makeGuardian(_: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocGuardian(false) catch return PrimitiveError.OutOfMemory;
}

fn guardianP(args: []const Value) PrimitiveError!Value {
    return if (types.isGuardian(args[0]) and !types.toGuardian(args[0]).is_transport) types.TRUE else types.FALSE;
}

// --- Transport cell guardians ----------------------------------------------

fn makeTransportCellGuardian(_: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocGuardian(true) catch return PrimitiveError.OutOfMemory;
}

fn transportCellGuardianP(args: []const Value) PrimitiveError!Value {
    return if (types.isGuardian(args[0]) and types.toGuardian(args[0]).is_transport) types.TRUE else types.FALSE;
}

fn transportCellP(args: []const Value) PrimitiveError!Value {
    return if (types.isTransportCell(args[0])) types.TRUE else types.FALSE;
}

fn transportCellKey(args: []const Value) PrimitiveError!Value {
    if (!types.isTransportCell(args[0])) return primitives.typeError("transport-cell-key", "transport-cell", args[0]);
    const tc = types.toTransportCell(args[0]);
    return if (tc.broken) types.FALSE else tc.key;
}

fn transportCellValue(args: []const Value) PrimitiveError!Value {
    if (!types.isTransportCell(args[0])) return primitives.typeError("transport-cell-value", "transport-cell", args[0]);
    return types.toTransportCell(args[0]).value;
}

fn transportCellBrokenP(args: []const Value) PrimitiveError!Value {
    if (!types.isTransportCell(args[0])) return primitives.typeError("transport-cell-broken?", "transport-cell", args[0]);
    return if (types.toTransportCell(args[0]).broken) types.TRUE else types.FALSE;
}

/// A stable identity hash. Kaappi never relocates objects, so the boxed value
/// word (a heap address for pointers, the immediate/number bits otherwise) is
/// constant for the lifetime of an eq? object. Folded to 46 bits so the result
/// is always a non-negative fixnum.
fn currentHash(args: []const Value) PrimitiveError!Value {
    const h: u64 = args[0] & 0x00003FFFFFFFFFFF;
    return types.makeFixnum(@intCast(h));
}

// --- Shared ----------------------------------------------------------------

/// Keep the argument's location alive across the call. In the interpreter the
/// argument is held in a live register for the duration, so this reduces to a
/// value-returning no-op; it exists so portable code has a guaranteed way to
/// pin a location, and returns an unspecified value.
fn referenceBarrier(_: []const Value) PrimitiveError!Value {
    return types.VOID;
}
