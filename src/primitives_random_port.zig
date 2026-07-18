//! SRFI-271 random port core primitives.
//!
//! These are the `%`-prefixed internals the `(srfi 271 ...)` libraries build
//! on; the user-facing API (make-random-port, the state predicates, the
//! initialization-error condition) lives in `lib/srfi/271*.sld`. A random
//! port is an ordinary binary input port whose bytes come from a
//! `types.RandomGen` (see readOneByte's hook in primitives_io.zig).
//!
//! A determinized port's state is snapshot as a self-describing bytevector,
//! which `write`/`read` round-trip verbatim as a `#u8(...)` literal — exactly
//! the external-representation invariance SRFI-271 requires of states. Layout
//! (46 bytes):
//!
//!   [0..4)   magic "S271"        recognises a state at the type level
//!   [4]      version (1)
//!   [5]      out_pos (0..8)      bytes of the current block already delivered
//!   [6..14)  out[0..8)           the current 8-byte output block
//!   [14..46) s[0..4] LE u64      the xoshiro256** state words

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const state_len = 46;
const magic = [4]u8{ 'S', '2', '7', '1' };
const version: u8 = 1;
const seed_len = 32; // bytes consumed to seed the four state words

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "%random-port-make-randomized", .func = &makeRandomizedFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%random-port-make-from-seed", .func = &makeFromSeedFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%random-port-make-from-state", .func = &makeFromStateFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%random-port-state", .func = &portStateFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%random-port?", .func = &randomPortPredFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
};

/// The determinized random port behind `v`, or a type error.
fn getDeterminizedPort(proc: []const u8, v: Value) PrimitiveError!*types.RandomGen {
    if (types.isPort(v)) {
        const port = types.toObject(v).as(types.Port);
        if (port.random_gen) |g| {
            if (g.kind == .determinized) return g;
        }
    }
    return primitives.typeError(proc, "determinized random port", v);
}

fn makeRandomizedFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocRandomPort(.{ .kind = .randomized }) catch return PrimitiveError.OutOfMemory;
}

fn makeFromSeedFn(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("%random-port-make-from-seed", "bytevector", args[0]);
    const bv = types.toBytevector(args[0]);
    if (bv.data.len < seed_len) return primitives.typeError("%random-port-make-from-seed", "bytevector of length >= 32", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var gen = types.RandomGen{ .kind = .determinized };
    for (&gen.s, 0..) |*word, i| {
        word.* = std.mem.readInt(u64, bv.data[i * 8 ..][0..8], .little);
    }
    return gc.allocRandomPort(gen) catch return PrimitiveError.OutOfMemory;
}

fn makeFromStateFn(args: []const Value) PrimitiveError!Value {
    if (!isStateBytevector(args[0])) return primitives.typeError("%random-port-make-from-state", "random-port state", args[0]);
    const bv = types.toBytevector(args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var gen = types.RandomGen{ .kind = .determinized };
    gen.out_pos = bv.data[5];
    @memcpy(&gen.out, bv.data[6..14]);
    for (&gen.s, 0..) |*word, i| {
        word.* = std.mem.readInt(u64, bv.data[14 + i * 8 ..][0..8], .little);
    }
    return gc.allocRandomPort(gen) catch return PrimitiveError.OutOfMemory;
}

fn portStateFn(args: []const Value) PrimitiveError!Value {
    const g = try getDeterminizedPort("%random-port-state", args[0]);
    var buf: [state_len]u8 = undefined;
    @memcpy(buf[0..4], &magic);
    buf[4] = version;
    buf[5] = g.out_pos;
    @memcpy(buf[6..14], &g.out);
    for (g.s, 0..) |word, i| {
        std.mem.writeInt(u64, buf[14 + i * 8 ..][0..8], word, .little);
    }
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocBytevector(&buf) catch return PrimitiveError.OutOfMemory;
}

fn randomPortPredFn(args: []const Value) PrimitiveError!Value {
    if (types.isPort(args[0])) {
        const port = types.toObject(args[0]).as(types.Port);
        if (port.random_gen) |g| {
            if (g.kind == .determinized) return types.TRUE;
        }
    }
    return types.FALSE;
}

/// Structural recognition of a determinized random-port state bytevector.
/// Mirrors random-port-state? in the .sld (kept here so from-state never
/// trusts an unvalidated blob), including the "state words not all zero"
/// rule — an all-zero xoshiro256** state is a fixed point that emits only
/// zero bytes, so it is not a valid state.
fn isStateBytevector(v: Value) bool {
    if (!types.isBytevector(v)) return false;
    const bv = types.toBytevector(v);
    if (bv.data.len != state_len) return false;
    if (!std.mem.eql(u8, bv.data[0..4], &magic)) return false;
    if (bv.data[4] != version) return false;
    if (bv.data[5] > 8) return false;
    for (bv.data[14..46]) |b| {
        if (b != 0) return true;
    }
    return false;
}
