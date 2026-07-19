//! SRFI-260 — Generated Symbols.
//!
//! `generate-symbol` mints a fresh symbol whose name is unique "for all
//! practical purposes" and unpredictable. Unlike an uninterned symbol
//! (SRFI 258), a generated symbol keeps write/read invariance and the classic
//! rule that two symbols are identical iff their names are equal.
//!
//! Kaappi has no uninterned symbols — every symbol is interned by name in the
//! one symbol table (`GC.allocSymbol`) — so those two properties fall out for
//! free: any symbol we mint round-trips through `write`/`read` back to an `eq?`
//! symbol (the printer bar-quotes names that need it). The whole SRFI therefore
//! reduces to "intern a symbol under a fresh, unpredictable, collision-free
//! name."
//!
//! The generated name is `"<pretty>.<counter>.<128-bit-random-hex>"`:
//!   * a process-global atomic counter gives a hard in-process uniqueness
//!     guarantee, independent of entropy quality or of SRFI-18 threads (which
//!     run independent VMs but share this one static), and
//!   * 128 bits of OS entropy (`platform.osRandomBytes`) make the name
//!     unpredictable and collision-free across processes and reads.
//!
//! The optional `pretty-name` is a display hint only — per the SRFI it "does
//! not determine the generated symbol's actual name". We use it as the prefix;
//! two calls with the same pretty-name still yield distinct symbols.

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const SRFI260 = LS.initOne(.srfi_260);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "generate-symbol", .func = &generateSymbol, .arity = .{ .variadic = 0 }, .libs = SRFI260 },
};

/// Process-global monotonic counter shared across every OS thread, giving each
/// call a distinct value under which the random bits sit. It is `usize` rather
/// than `u64` because wasm32 — the one single-threaded target — has no 64-bit
/// atomic RMW: there `usize` is 32 bits and the count wraps only after 2^32
/// calls, which the 128 random bits still make collision-free. On native
/// targets `usize` is 64-bit, so the counter alone stays unique for all
/// practical use.
var gensym_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

fn generateSymbol(args: []const Value) PrimitiveError!Value {
    // (generate-symbol) or (generate-symbol pretty-name). `.variadic = 0` only
    // bounds args from below, so reject the over-application here.
    if (args.len > 1) {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.ArityMismatch;
        vm.setErrorDetail("'generate-symbol': expected 0 or 1 arguments, got {d}", .{args.len});
        return PrimitiveError.ArityMismatch;
    }

    // Display hint only: the pretty-name prefixes the name but never determines
    // identity. Absent, we use "g" (a letter-initial, collision-free default).
    const pretty: []const u8 = if (args.len == 1)
        try primitives.expectString("generate-symbol", args[0])
    else
        "g";

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // 128 bits of OS entropy make the name unpredictable. If the OS CSPRNG
    // genuinely fails, raise rather than fall back to predictable
    // clock-derived bytes — the same principle the SRFI-271 random ports
    // follow. `platform.osRandomBytes` documents the failure as effectively
    // unreachable on a healthy host and, deliberately, never substitutes weak
    // bytes itself; the counter below still guarantees uniqueness, but a symbol
    // advertised as unpredictable must not in fact be predictable.
    var rnd: [2]u64 = undefined;
    if (!platform.osRandomBytes(std.mem.asBytes(&rnd)))
        return raiseEntropyUnavailable(gc);

    const n = gensym_counter.fetchAdd(1, .monotonic);

    // Assemble the name off-heap; `allocSymbol` copies it into the symbol
    // table (and never triggers a collection), so freeing it after is safe.
    const name = std.fmt.allocPrint(
        gc.allocator,
        "{s}.{x}.{x:0>16}{x:0>16}",
        .{ pretty, n, rnd[0], rnd[1] },
    ) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(name);

    return gc.allocSymbol(name) catch return PrimitiveError.OutOfMemory;
}

/// The OS CSPRNG failed, so an unpredictable name cannot be produced. Raise a
/// catchable general error rather than hand back a predictable symbol.
fn raiseEntropyUnavailable(gc: *memory.GC) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    var msg = gc.allocString("generate-symbol: OS entropy source unavailable") catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, types.NIL) catch return PrimitiveError.OutOfMemory;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}
