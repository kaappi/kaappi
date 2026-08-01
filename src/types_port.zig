const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;
const FALSE = types.FALSE;

pub const Port = struct {
    header: Object,
    fd: platform.fd_t,
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
    string_out_len: usize = 0, // total extent ever written (get-output-string reads [0..this))
    string_out_cap: usize = 0,
    /// SRFI 192 write cursor for output string ports, independent of
    /// string_out_len: a write happens at this position, overwriting
    /// existing bytes in place up to string_out_len and only growing it
    /// if the write extends past the current end (matching how a
    /// seekable fd-backed output port already behaves via the OS's own
    /// lseek+write). Stays equal to string_out_len except after
    /// set-port-position! seeks it elsewhere.
    string_out_pos: usize = 0,
    is_binary: bool = false,
    read_buf: ?[]u8 = null,
    read_buf_len: usize = 0,
    /// SRFI-271 random port: when non-null this input port yields bytes from
    /// a random generator rather than an fd or string buffer (owned; freed
    /// with the port). See RandomGen below.
    random_gen: ?*RandomGen = null,
    // Non-blocking port state (KEP-0001 Phase 3):
    /// O_NONBLOCK has been set on `fd` (lazily, the first time a read/write
    /// runs while a fiber scheduler exists). Never set for fd 0/1/2.
    nonblocking: bool = false,
    /// Pending output not yet written to `fd` (owned, growable). The live
    /// span is [write_buf_start..write_buf_len) — `start` records drain
    /// progress so a write that would block can suspend mid-buffer and a
    /// retry resumes with the remaining slice.
    write_buf: ?[]u8 = null,
    write_buf_start: usize = 0,
    write_buf_len: usize = 0,
    /// Windows-only fd-kind state (#1608); always defaults elsewhere.
    fd_state: packed struct(u8) {
        /// maybeSetNonblocking's fd-kind probe already ran for this port,
        /// whatever its outcome — the probe is a handful of syscalls and
        /// must not repeat on every read of an ordinary file port.
        probe_done: bool = false,
        /// `fd` wraps a SOCKET (fdKind probe, #1608 stage 1), so
        /// reads/writes must route through platform.sockRecv/sockSend —
        /// CRT _read/_write cannot operate on (overlapped) SOCKET handles
        /// at all, blocking or not.
        is_socket: bool = false,
        /// `fd` wraps a non-socket pipe end (#1608 stage 2). Under a
        /// scheduler the port enters *emulated* non-blocking mode
        /// (`nonblocking` set with no OS-level flip): reads/writes route
        /// through platform.pipeRead/pipeWrite, whose peek/write-quota
        /// pre-checks synthesize the EAGAIN that parks the fiber, and the
        /// reactor re-runs the same checks on a poll cadence for the
        /// wakeup.
        is_pipe: bool = false,
        _pad: u5 = 0,
    } = .{},
    /// SRFI 181: non-null when this port's I/O is backed by user-supplied
    /// Scheme procedures rather than an fd/string/random buffer. Owned;
    /// freed with the port (destroySatellites below, called from
    /// gc_sweep.freeObject) -- same shape as random_gen above, except its
    /// fields are Values, so it also needs tracing (forEachValue below).
    /// None of these fields are ever mutated after construction (SRFI 181
    /// defines no setters), so no gc.writeBarrier call is ever needed.
    custom_backend: ?*CustomBacking = null,
    /// SRFI 181: non-null when this port is a transcoded (textual) view
    /// over another (binary) port -- decodes/encodes bytes<->characters
    /// via `codec`, translating line endings per `eol_style` and handling
    /// invalid input per `error_mode`. The wrapped port is read/written
    /// via direct Zig calls (readOneByte/portWriteBytes in
    /// primitives_io.zig), never a Scheme callback, so none of
    /// custom_backend's reentrant-call restrictions apply here. Owned;
    /// freed with the port, same as custom_backend above -- and like it,
    /// never mutated after construction, so no write barrier is needed.
    transcode: ?*TranscodeState = null,
};

// ---------------------------------------------------------------------------
// The port/GC contract (audit v2, Phase 7A)
// ---------------------------------------------------------------------------
//
// `Port` is the only heap type that owns *satellite* structs by pointer, so
// it is the only one where the GC must follow an indirection to find the
// Values it holds. Five sites do that by hand:
//
//   gc_collect.zig  referencesYoung      (generational remembered-set check)
//   gc_collect.zig  markObjectContents   (recursive marking, via markValue)
//   gc_collect.zig  markValueInner       (worklist marking)
//   gc_sweep.zig    objectSize           (GC stats)
//   gc_sweep.zig    freeObject           (release owned memory)
//
// Zig's exhaustiveness check guarantees each has a `.port` *arm*; nothing
// guaranteed what was *inside* it. Measured before this was written: a
// third Value-bearing field compiled clean under `zig build` and was missed
// by 3 of the 5 (a bare `Value`, or one on an existing satellite) or by all
// 5 (a brand-new satellite) -- observed as a real use-after-free, plus a
// leak for the satellite case.
//
// The three walkers below are now the single enumeration. They live here,
// not in gc_collect.zig, because types.zig cannot import memory.zig (where
// `GC.markValue` lives) without an import cycle -- so the *enumeration* is
// expressed here and each caller supplies its own *action*. That is also
// what lets markValueInner keep appending to its worklist instead of
// recursing, which is why it duplicated markPortValues in the first place.

/// Every type a `Port` owns through a pointer, and whether the GC must trace
/// Values inside it. The comptime gate below rejects any owned-pointer field
/// on `Port` whose pointee is absent from this list, so a new satellite is a
/// build error until someone has answered that question.
const satellites = .{
    .{ CustomBacking, true },
    .{ TranscodeState, true },
    .{ RandomGen, false },
};

/// `Port` fields typed `u64` that are **not** Scheme Values -- counters,
/// offsets, handles. Empty today; `Port` has no bare `u64` field at all.
///
/// `Value` is `u64`, so no comptime type test can tell a real Value from a
/// plain counter. `forEachValue` therefore treats every `Value`-typed field
/// as a Value (the safe over-approximation: `markValue` ignores anything
/// that is not pointer-tagged) and this list is the opt-out for a field
/// where that would be wrong. The dangerous direction -- a Value the
/// walkers never reach -- is a hard build error instead, see below.
const plain_u64_fields = [_][]const u8{};

fn isPlainU64(comptime name: []const u8) bool {
    for (plain_u64_fields) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

/// The struct a `?*T` / `*T` field points at, or null for anything else
/// (slices, optionals of slices, scalars, inline structs).
fn pointeeStruct(comptime T: type) ?type {
    const ptr = switch (@typeInfo(T)) {
        .optional => |o| switch (@typeInfo(o.child)) {
            .pointer => |p| p,
            else => return null,
        },
        .pointer => |p| p,
        else => return null,
    };
    if (ptr.size != .one) return null;
    return switch (@typeInfo(ptr.child)) {
        .@"struct" => ptr.child,
        else => null,
    };
}

fn satelliteHoldsValues(comptime T: type) ?bool {
    comptime var found: ?bool = null;
    inline for (satellites) |entry| {
        if (entry[0] == T) found = entry[1];
    }
    return found;
}

comptime {
    // Gate 1: every owned-pointer field on Port names a classified satellite.
    // This is what makes the worst mutation class -- a new satellite, missed
    // by all five sites -- impossible to add silently.
    for (@typeInfo(Port).@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, "header")) continue;
        if (pointeeStruct(f.type)) |S| {
            if (satelliteHoldsValues(S) == null) @compileError(
                "Port." ++ f.name ++ " points at " ++ @typeName(S) ++
                    ", which is not in types_port.satellites.\n" ++
                    "Add it there with whether it holds Scheme Values. Everything else " ++
                    "(marking at 3 sites, sizing, freeing) is derived from that entry.",
            );
        }
    }
    // Gate 2: a satellite declared value-free must really be value-free,
    // since forEachValue skips it entirely.
    for (satellites) |entry| {
        if (!entry[1]) {
            for (@typeInfo(entry[0]).@"struct".fields) |f| {
                if (f.type == Value) @compileError(
                    @typeName(entry[0]) ++ "." ++ f.name ++ " is a Value, but " ++
                        @typeName(entry[0]) ++ " is listed value-free in " ++
                        "types_port.satellites. Flip its flag to true.",
                );
            }
        }
    }
}

/// Visit every GC-traced `Value` this port holds, wherever it lives -- on
/// the port itself or inside an owned satellite.
///
/// **This is the only enumeration of a port's Values.** `referencesYoung`,
/// `markObjectContents` and `markValueInner` all route through it, so a new
/// Value field is traced by all three the moment it exists: one on `Port`
/// or on a `true` satellite needs no edit at all, and a brand-new satellite
/// needs exactly one line in `satellites` above (which the comptime gate
/// demands anyway).
///
/// `visit` returns `true` to stop the walk early -- `referencesYoung` wants
/// that short-circuit; the two marking callers always return `false`.
/// Returns `true` iff some `visit` stopped the walk.
pub fn forEachValue(
    port: *const Port,
    ctx: anytype,
    comptime visit: fn (@TypeOf(ctx), Value) bool,
) bool {
    inline for (@typeInfo(Port).@"struct".fields) |f| {
        if (comptime std.mem.eql(u8, f.name, "header")) {
            // The GC list link and tag, not port state.
        } else if (comptime f.type == Value and !isPlainU64(f.name)) {
            if (visit(ctx, @field(port, f.name))) return true;
        } else if (comptime pointeeStruct(f.type)) |S| {
            // `orelse false` never fires: gate 1 above rejects an
            // unclassified satellite outright. It keeps that the *only*
            // error such a build reports.
            if (comptime satelliteHoldsValues(S) orelse false) {
                if (@field(port, f.name)) |sat| {
                    inline for (@typeInfo(S).@"struct".fields) |sf| {
                        if (comptime sf.type == Value) {
                            if (visit(ctx, @field(sat, sf.name))) return true;
                        }
                    }
                }
            }
        }
    }
    return false;
}

/// Bytes of owned satellite structs hanging off this port, for
/// `gc_sweep.objectSize`. Derived from the same `satellites` list, so a new
/// satellite is accounted for without touching that arm.
pub fn satelliteBytes(port: *const Port) usize {
    var total: usize = 0;
    inline for (@typeInfo(Port).@"struct".fields) |f| {
        if (comptime pointeeStruct(f.type)) |S| {
            if (comptime satelliteHoldsValues(S) != null) {
                if (@field(port, f.name) != null) total += @sizeOf(S);
            }
        }
    }
    return total;
}

/// Free every owned satellite struct, for `gc_sweep.freeObject`. Frees only
/// the structs themselves:
///
///   * A custom port's `close_proc` is never called during a sweep. There is
///     no valid VM call stack to reenter during collection, and R7RS gives
///     no finalization guarantee for a port that becomes unreachable without
///     an explicit `close-port` -- the same as every other port kind, which
///     just drops its fd and buffers.
///   * A transcoded port's `wrapped_port` is never touched. It is a
///     separately GC-tracked Value: unreachable, it is swept on its own;
///     still reachable, it must not be freed just because this view over it
///     became garbage. `closePortObj` (primitives_io.zig) is what cascades a
///     close to the wrapped port, while the VM is live to do so.
pub fn destroySatellites(port: *Port, allocator: std.mem.Allocator) void {
    inline for (@typeInfo(Port).@"struct".fields) |f| {
        if (comptime pointeeStruct(f.type)) |S| {
            if (comptime satelliteHoldsValues(S) != null) {
                if (@field(port, f.name)) |sat| allocator.destroy(sat);
            }
        }
    }
}

/// SRFI 181: v1 supports UTF-8 only -- functionally the only variant this
/// enum can hold today, but kept as an enum (not hardcoded) so a future
/// latin-1/utf-16 codec is a matter of adding a variant, not restructuring
/// this struct.
pub const Codec = enum { utf8 };

/// SRFI 181 eol-style: `none` performs no line-ending translation in
/// either direction. On decode, `lf`/`crlf` both collapse any recognized
/// line ending (bare CR, bare LF, or CRLF) to a single #\newline -- the
/// distinction only matters on encode, where `lf` emits a bare #\newline
/// and `crlf` emits the two-byte CRLF sequence.
pub const EolStyle = enum { none, lf, crlf };

/// SRFI 181 error-handling mode for decoding/encoding failures. `replace`
/// substitutes U+FFFD (or '?' if unrepresentable) and continues; `raise`
/// signals a continuable i/o-decoding-error?/i/o-encoding-error? condition
/// (see primitives_control.raiseContinuable) and continues afterward.
/// Encoding cannot actually fail under the only codec v1 ships (every
/// valid Kaappi character has a UTF-8 encoding by construction), so
/// error_mode is only ever consulted on the decode path in practice.
pub const ErrorMode = enum { replace, raise };

pub const TranscodeState = struct {
    wrapped_port: Value, // the only Value field -- needs GC tracing
    codec: Codec,
    eol_style: EolStyle,
    error_mode: ErrorMode,
};

/// Callback procedures backing a SRFI 181 custom port. Each is either a
/// procedure or `types.FALSE` ("absent" -- e.g. an input-only port has no
/// write_proc). port.is_binary (already on Port) distinguishes a custom
/// binary port (bytevector read!/write! buffers) from a custom textual
/// port (string buffers); nothing here duplicates that flag.
pub const CustomBacking = struct {
    read_proc: Value = FALSE,
    write_proc: Value = FALSE,
    get_position_proc: Value = FALSE,
    set_position_proc: Value = FALSE,
    close_proc: Value = FALSE,
    flush_proc: Value = FALSE,
};

/// Which kind of source backs a SRFI-271 random binary input port.
pub const RandomKind = enum(u8) { randomized, determinized };

/// Generator state behind a SRFI-271 random port (owned by Port.random_gen).
/// Holds no Scheme Values, so the GC never traces it — only frees it.
///
/// Determinized ports run a xoshiro256** PRNG. Its full observable state is
/// the four state words `s` plus the current 8-byte output block `out` and
/// `out_pos`, the number of bytes of that block already delivered; this is
/// exactly what (random-port-state ...) captures, so two ports with equal
/// state produce identical byte streams. `out` is a pure function of `s`
/// (the advance step is a bijection), so equal `(s, out_pos)` always implies
/// equal `out` — state equality via a byte-for-byte snapshot is canonical.
///
/// Randomized ports refill each block from OS entropy and expose no state.
pub const RandomGen = struct {
    kind: RandomKind,
    s: [4]u64 = .{ 0, 0, 0, 0 },
    out: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    /// 8 means "no pending block"; the next byte forces a refill. A fresh
    /// determinized generator starts here so the seed words drive the first
    /// output block.
    out_pos: u8 = 8,

    fn xoshiroNext(self: *RandomGen) u64 {
        const s = &self.s;
        const result = std.math.rotl(u64, s[1] *% 5, 7) *% 9;
        const t = s[1] << 17;
        s[2] ^= s[0];
        s[3] ^= s[1];
        s[1] ^= s[2];
        s[0] ^= s[3];
        s[2] ^= t;
        s[3] = std.math.rotl(u64, s[3], 45);
        return result;
    }

    /// Next pseudorandom byte, or null when a randomized port's OS entropy
    /// source is unavailable (rather than emitting predictable bytes under a
    /// cryptographic-quality contract). Determinized ports never fail and
    /// never return null; a random port never reaches EOF. On a null the
    /// output block is left un-advanced so a retry re-attempts the refill.
    pub fn nextByte(self: *RandomGen) ?u8 {
        if (self.out_pos >= 8) {
            switch (self.kind) {
                .randomized => if (!platform.osRandomBytes(&self.out)) return null,
                .determinized => std.mem.writeInt(u64, &self.out, self.xoshiroNext(), .little),
            }
            self.out_pos = 0;
        }
        const b = self.out[self.out_pos];
        self.out_pos += 1;
        return b;
    }
};
