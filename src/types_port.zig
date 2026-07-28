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
    /// freed with the port (see freeObject's .port arm in gc_collect.zig) --
    /// same shape as random_gen above, except its fields are Values, so it
    /// also needs tracing (see markPortValues in gc_collect.zig). None of
    /// these fields are ever mutated after construction (SRFI 181 defines
    /// no setters), so no gc.writeBarrier call is ever needed for them.
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
