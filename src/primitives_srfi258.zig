//! SRFI 258 — Uninterned Symbols.
//!
//! An uninterned symbol is a symbol that is not `eqv?` to any other symbol,
//! even one with the same name. They are useful for macro programming and for
//! generating guaranteed-unique identifiers. Most of the machinery lives
//! elsewhere:
//!   * `GC.allocUninternedSymbol` (memory.zig) allocates a symbol that bypasses
//!     the interning table, and the `Symbol.interned` flag (types.zig) is the
//!     only thing distinguishing the two kinds;
//!   * equality needs no special code — `eqv?`/`eq?`/`equal?` already compare
//!     symbols by pointer identity, so two distinct objects are two distinct
//!     symbols regardless of name;
//!   * the printer writes an uninterned symbol in an unreadable `#<…>` form so
//!     `read` rejects it (printer.zig), deliberately breaking write/read
//!     invariance as the SRFI requires.

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const primitives_string = @import("primitives_string.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const S258 = LS.initOne(.srfi_258);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "string->uninterned-symbol", .func = &stringToUninternedSymbol, .arity = .{ .exact = 1 }, .libs = S258 },
    .{ .name = "symbol-interned?", .func = &symbolInternedP, .arity = .{ .exact = 1 }, .libs = S258 },
    .{ .name = "generate-uninterned-symbol", .func = &generateUninternedSymbol, .arity = .{ .variadic = 0 }, .libs = S258 },
};

/// Monotonic source of "likely to be unique" names for
/// generate-uninterned-symbol. A 32-bit atomic keeps concurrent SRFI-18 threads
/// from minting the same number without needing 64-bit atomics (absent on
/// wasm32). Wrap-around is harmless: an uninterned symbol's identity is
/// guaranteed by allocation, so even a duplicate name still yields a distinct
/// symbol.
var gensym_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

/// (string->uninterned-symbol string) → a fresh uninterned symbol whose textual
/// name is `string`. Never `eqv?` to any other symbol.
fn stringToUninternedSymbol(args: []const Value) PrimitiveError!Value {
    const name = try primitives_string.getStringSlice("string->uninterned-symbol", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocUninternedSymbol(name) catch return PrimitiveError.OutOfMemory;
}

/// (symbol-interned? symbol) → #t for an ordinary interned symbol, #f for an
/// uninterned one. Signals an error on a non-symbol (its domain is symbols).
fn symbolInternedP(args: []const Value) PrimitiveError!Value {
    if (!types.isSymbol(args[0])) return primitives.typeError("symbol-interned?", "symbol", args[0]);
    return if (types.symbolInterned(args[0])) types.TRUE else types.FALSE;
}

/// (generate-uninterned-symbol [prefix]) → a fresh uninterned symbol with a
/// likely-unique name. The optional `prefix` is a string (used verbatim) or a
/// symbol (its name); when omitted the prefix is "g". The name is
/// `<prefix><counter>`.
fn generateUninternedSymbol(args: []const Value) PrimitiveError!Value {
    // The dispatcher only enforces the .variadic minimum (0); reject the excess
    // here so a second argument is an arity error, not silently dropped.
    if (args.len > 1) {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.ArityMismatch;
        vm.setErrorDetail("'generate-uninterned-symbol': expected 0 or 1 arguments, got {d}", .{args.len});
        return PrimitiveError.ArityMismatch;
    }
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    var prefix: []const u8 = "g";
    if (args.len > 0) {
        if (types.isString(args[0])) {
            prefix = try primitives_string.getStringSlice("generate-uninterned-symbol", args[0]);
        } else if (types.isSymbol(args[0])) {
            prefix = types.symbolName(args[0]);
        } else {
            return primitives.typeError("generate-uninterned-symbol", "string or symbol", args[0]);
        }
    }

    const n = gensym_counter.fetchAdd(1, .monotonic);

    // Build "<prefix><n>" in a private buffer, then hand it to
    // allocUninternedSymbol (which copies it before any collection). Freed
    // afterwards — the symbol owns its own duplicated name.
    const name = std.fmt.allocPrint(gc.allocator, "{s}{d}", .{ prefix, n }) catch
        return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(name);
    return gc.allocUninternedSymbol(name) catch return PrimitiveError.OutOfMemory;
}
