//! Port readiness oracles behind `char-ready?` and `u8-ready?` — kaappi#2511
//! plus its PR review round (#2516).
//!
//! R7RS 6.13.1 hangs a hard guarantee on these predicates: "If char-ready?
//! returns #t then the next read-char operation on the given port is
//! guaranteed not to hang" (6.13.3 says the same of u8-ready?), and both must
//! return #t at end of file (#1179). The pre-fix code returned #t
//! unconditionally, so a poll-then-read drive loop on a subprocess pipe fell
//! straight into the blocking read it was polling to avoid. Extracted from
//! primitives_io.zig so the readiness layer has one cohesive home (the rest
//! of that file stays put — it is a flat primitives file, which the repo's
//! file-size policy explicitly exempts from the 1500-line cap).
//!
//! Two oracles live here because the two predicates promise different things:
//!
//! * `portReadyNow` — byte readiness (u8-ready? via primitives_bytevector).
//!   One available byte, or an EOF/error that answers at once, is enough.
//!
//! * `charReadyNow` — character readiness (char-ready? via primitives_io).
//!   A *complete* character must be available: a lone UTF-8 lead byte makes
//!   the fd readable, but read-char would consume it and then block waiting
//!   for the continuation — exactly the hang the #t guarantee forbids. The
//!   predicate therefore drains whatever the fd holds *right now* into the
//!   port's own software buffers (peek_byte/peek_extra/read_buf — the same
//!   buffers every read drains, so nothing Scheme-visible is consumed or
//!   reordered) and then checks buffered completeness. The drain never parks
//!   (this is a synchronous predicate, not a scheduler operation): it only
//!   reads when a zero-timeout poll just said data is there, and treats
//!   would-block as a conservative #f — which R7RS permits, since only #t
//!   carries the guarantee.
//!
//! Custom ports (SRFI 181) have no readiness contract: read! is arbitrary
//! Scheme code with no non-blocking probe, so the only truthful answer
//! without invoking it (a side effect a predicate must not have) is #f until
//! a complete character is already buffered — and #t when the port is
//! output-only, whose reads are EOF forever. Both oracles hold that line.
//! Likewise a transcoded port's readiness is its wrapped port's *character*
//! readiness under both predicates: the transcoded layer emits whole
//! re-encoded characters, so a single buffered wrapped byte — byte-ready as
//! it may be — cannot produce even one output byte without possibly
//! blocking.
//!
//! WASM keeps the historical best-effort #t everywhere readiness cannot be
//! queried (KEP-0001 Phase 4): wasmtime's poll_oneoff cannot serve a
//! zero-timeout snapshot here, and draining on a host that cannot report
//! readiness could block the only fiber.

const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const memory = @import("memory.zig");
const primitives_io = @import("primitives_io.zig");

/// Byte-granular readiness oracle behind `u8-ready?` (primitives_bytevector).
/// True iff the next read on `port` completes immediately, from a software
/// buffer, an inexhaustible or at-EOF source, or an underlying fd that has a
/// byte (or EOF/error) available right now.
///
/// Mirrors readOneByte's port-kind dispatch in the same order so the two can
/// never disagree about which source serves the next byte:
///
///   peek_byte / peek_extra / read_buf   buffered bytes -> true
///   random_gen                          inexhaustible -> true
///   string port                         data or EOF, never blocks -> true
///   custom port (SRFI 181)              no readiness contract for read!;
///                                       true only when output-only (reads
///                                       are EOF forever), else buffered
///                                       bytes only (checked above)
///   transcoded port (SRFI 181)          recursion on the wrapped port's
///                                       *character* readiness — the port's
///                                       own peek/read buffers checked above
///                                       already hold any re-encoded
///                                       leftovers
///   fd                                  fdReadReadyNow: a zero-timeout
///                                       poll of the fd itself, never a
///                                       park
pub fn portReadyNow(port: *types.Port) bool {
    if (port.peek_byte != null or port.peek_extra_len > 0) return true;
    if (port.read_buf_len > 0) return true;
    if (port.random_gen != null) return true;
    if (port.is_string_port) return true;
    if (port.custom_backend) |cb| return cb.read_proc == types.FALSE;
    if (port.transcode) |ts| {
        const wrapped = types.toObject(ts.wrapped_port).as(types.Port);
        return charReadyNow(wrapped);
    }
    return fdReadReadyNow(port.fd);
}

/// Character-granular readiness oracle behind `char-ready?`
/// (primitives_io). True iff the next read-char answers immediately: a
/// complete character (or an invalid lead byte, which read-char returns
/// as-is) is already buffered, or the source can never block (string data,
/// random bytes), or the fd can complete the character right now / is at
/// EOF / is about to raise. False is always a *may* hang, never a promise.
pub fn charReadyNow(port: *types.Port) bool {
    if (bufferedCharComplete(port)) return true;
    if (port.random_gen != null) return true;
    // A string source never blocks; even a truncated UTF-8 tail answers at
    // once (readUtf8Char returns the lead byte alone at EOF).
    if (port.is_string_port) return true;
    // Custom backend: documented contract above — ready only when buffered
    // (checked first) or when read! is absent and reads are EOF forever.
    if (port.custom_backend) |cb| return cb.read_proc == types.FALSE;
    if (port.transcode) |ts| {
        const wrapped = types.toObject(ts.wrapped_port).as(types.Port);
        return charReadyNow(wrapped);
    }
    return switch (fdCharReadyNow(port)) {
        .ready => true,
        .would_block => false,
    };
}

// ---------------------------------------------------------------------------
// Software-buffer completeness
// ---------------------------------------------------------------------------

/// The next undelivered stream byte across the software buffers, in the
/// order readOneByte drains them: peek_byte, then peek_extra, then the live
/// span of read_buf.
fn headByte(port: *types.Port) ?u8 {
    if (port.peek_byte) |b| return b;
    if (port.peek_extra_len > 0) return port.peek_extra[0];
    if (port.read_buf) |rb| {
        if (port.read_buf_len > 0) return rb[rb.len - port.read_buf_len];
    }
    return null;
}

fn bufferedByteCount(port: *types.Port) usize {
    var n: usize = if (port.peek_byte != null) 1 else 0;
    n += port.peek_extra_len;
    n += port.read_buf_len;
    return n;
}

/// Whether the software buffers hold a complete character: at least as many
/// bytes as the head byte's UTF-8 sequence length. An invalid lead byte is
/// "complete" — readUtf8Char returns it as a single Latin-1 character rather
/// than waiting for continuations — and decodability need not be checked,
/// since a decode failure also answers immediately (the Latin-1 fallback).
fn bufferedCharComplete(port: *types.Port) bool {
    const lead = headByte(port) orelse return false;
    const seq_len = std.unicode.utf8ByteSequenceLength(lead) catch return true;
    return bufferedByteCount(port) >= seq_len;
}

// ---------------------------------------------------------------------------
// fd readiness
// ---------------------------------------------------------------------------

/// What one zero-timeout poll of an fd says about reading it right now.
const FdReadSnapshot = struct {
    /// The query itself failed; callers report ready (fdReadReadyNow's
    /// standing rule: a wrong #f stalls a polling loop on data that arrived
    /// between checks, while a spurious #t costs exactly one blocking read).
    failed: bool,
    /// A read returns at least one byte right now (POLLIN / oracle).
    data: bool,
    /// A read answers at once with EOF or an error instead: POLLHUP,
    /// POLLERR, POLLNVAL on POSIX. Unknown (false) on Windows, whose
    /// pipe/console oracles cannot distinguish it — there the conservative
    /// loop below simply reports would-block instead.
    closed_or_err: bool,
};

fn pollReadSnapshot(fd: platform.fd_t) FdReadSnapshot {
    if (comptime platform.is_windows) {
        // The reactor's own oracles (reactor_backends.arm() uses the same
        // pair): PeekNamedPipe for pipe ends, a 0-timeout select() for
        // sockets. Regular files and consoles have no cheap oracle, and a
        // read on either way never blocks on data arrival — data.
        switch (platform.fdKind(fd)) {
            .socket => {
                platform.ensureWinsock();
                const sock = platform.sockFromFd(fd) orelse
                    return .{ .failed = true, .data = false, .closed_or_err = false };
                return .{ .failed = false, .data = platform.sockPollReady(sock, true, false).readable, .closed_or_err = false };
            },
            .pipe => return .{ .failed = false, .data = platform.pipePollReady(fd, true, false).readable, .closed_or_err = false },
            .other => return .{ .failed = false, .data = true, .closed_or_err = false },
        }
    }
    if (comptime is_wasm) {
        // WASI has no poll(2) — std.posix.poll does not compile there
        // (std.Io.Threaded's own have_poll excludes it), and KEP-0001
        // Phase 4 keeps fd readiness best-effort on wasm hosts: the
        // playground shim cannot report it at all. Preserve the
        // historical #t rather than an always-#f no host could disprove.
        return .{ .failed = false, .data = true, .closed_or_err = false };
    }
    var fds = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const n = std.posix.poll(&fds, 0) catch
        return .{ .failed = true, .data = false, .closed_or_err = false };
    if (n == 0) return .{ .failed = false, .data = false, .closed_or_err = false };
    return .{
        .failed = false,
        .data = fds[0].revents & std.posix.POLL.IN != 0,
        .closed_or_err = fds[0].revents & (std.posix.POLL.HUP |
            std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0,
    };
}

/// Zero-timeout readability snapshot of a port's fd: true iff a read right
/// now would return data, EOF, or an error rather than blocking. POLLHUP,
/// POLLERR, and POLLNVAL count as ready — a pipe whose writer closed reads
/// EOF immediately (R7RS's "at end of file, ready" case, kaappi#1179), an
/// errored fd surfaces the error, not a hang, and poll only reports
/// POLLNVAL for an fd a read would reject at once. Any query failure also
/// reports ready: the wrong #f here stalls a polling drive loop on data
/// that arrived between the buffer check and the fd, while a spurious #t
/// costs exactly one blocking read — the pre-fix behavior everywhere.
pub fn fdReadReadyNow(fd: platform.fd_t) bool {
    const s = pollReadSnapshot(fd);
    return s.failed or s.data or s.closed_or_err;
}

// ---------------------------------------------------------------------------
// The character-completing drain (char-ready?'s fd arm)
// ---------------------------------------------------------------------------

const CharFdVerdict = enum { ready, would_block };

/// Decides, without consuming Scheme-visible input, whether read-char on an
/// fd-backed `port` answers immediately, given that the software buffers
/// currently hold an incomplete character (or nothing at all).
///
/// The loop poll-gates every read: a read(2) only runs when the zero-timeout
/// poll snapshot taken in the same iteration reported data, so a blocking fd
/// is never read blind — the same discipline readOneByte's reactor path
/// follows, minus the park (a predicate must not suspend the fiber; EAGAIN
/// becomes a conservative would-block instead). Bytes read here are stashed
/// into the port's software buffers and stay fully Scheme-visible: read_buf
/// and the peek slots are the stream, not a copy of it, and every later read
/// primitive drains them in order.
///
/// EOF and pending errors are "ready" even mid-sequence: readUtf8Char
/// returns a truncated tail's lead byte alone rather than blocking, and an
/// errored fd raises at once. Writes are deliberately NOT flushed first
/// (readOneByte does, for request/response liveness): the flush can itself
/// park, and any bytes drained here merely wait one read longer in read_buf
/// — the next real read still flushes before touching the fd.
fn fdCharReadyNow(port: *types.Port) CharFdVerdict {
    // WASM: no poll oracle exists (see pollReadSnapshot); draining on a host
    // that cannot report readiness could block the only fiber, so keep the
    // best-effort #t instead (KEP-0001 Phase 4 degradation).
    if (comptime is_wasm) return .ready;

    // A character needs at most 4 bytes and every successful read returns at
    // least one, so a handful of iterations suffices; the guard bounds a
    // pathological writer that dribbles one byte per poll round.
    var guard: usize = 0;
    while (guard < 8) : (guard += 1) {
        const snap = pollReadSnapshot(port.fd);
        if (snap.failed) return .ready;
        if (!snap.data) {
            // Nothing readable right now. EOF/error pending still answers a
            // read at once — ready even though the buffered character is
            // incomplete. A quiet fd with the writer alive is the truthful #f.
            return if (snap.closed_or_err) .ready else .would_block;
        }
        // How many more bytes would complete the head character? With no
        // head byte yet, fetch one; with one, fetch exactly the remainder.
        var needed: usize = 1;
        if (headByte(port)) |h| {
            const seq_len = std.unicode.utf8ByteSequenceLength(h) catch return .ready;
            needed = seq_len - bufferedByteCount(port);
        }
        // Reserve any read_buf growth before reading: bytes pulled off the
        // fd that cannot be kept are data loss, not a readiness answer, so
        // on reservation failure answer would-block without reading at all.
        if (!reserveReadBufTail(port, needed)) return .would_block;
        var chunk: [4]u8 = undefined;
        primitives_io.maybeSetNonblocking(port);
        const rc = primitives_io.portFdRead(port, &chunk, needed);
        if (rc > 0) {
            const n: usize = @intCast(rc);
            stashDrainedBytes(port, chunk[0..n]);
            if (bufferedCharComplete(port)) return .ready;
            continue; // short read mid-sequence: poll again for the rest
        }
        if (rc == 0) return .ready; // EOF behind (possibly partial) data
        const e = platform.errno(rc);
        if (e == .INTR) continue;
        if (e == .AGAIN) return .would_block; // raced/spurious wakeup
        return .ready; // a real error answers the next read immediately
    }
    return .would_block;
}

/// Ensures `extra` bytes can be appended behind read_buf's live span without
/// a later allocation: true when the stash will land in the peek scratch
/// instead (read_buf empty), when the slice's dead head space already has
/// room (a compaction copy only), or after growing the slice now. False only
/// when the growth allocation fails — the caller then reads nothing, so no
/// byte is ever pulled off the fd and lost.
fn reserveReadBufTail(port: *types.Port, extra: usize) bool {
    if (extra == 0 or port.read_buf_len == 0) return true; // peek-scratch path
    const gc = memory.gc_instance orelse return false;
    const rb = port.read_buf orelse return false; // non-null while read_buf_len > 0
    if (port.read_buf_len + extra <= rb.len) return true;
    const live_len = port.read_buf_len;
    const grown = gc.allocator.alloc(u8, live_len + extra) catch return false;
    // Keep the live span the slice tail — the cursor rule every other
    // read_buf user follows (consumption advances from the front by
    // shrinking the count) — by copying it to grown's tail; the hole at
    // grown's head is the reserved append room.
    @memcpy(grown[extra..], rb[rb.len - live_len ..]);
    gc.allocator.free(rb);
    port.read_buf = grown;
    return true;
}

/// Stashes a drain read's bytes at the end of the port's software buffers,
/// preserving stream order (peek_byte, peek_extra, read_buf live span). The
/// capacity invariant: the caller reads at most the bytes the head character
/// still needs, an incomplete head occupies at most peek_byte plus 2 peek
/// extras (3 extras would complete any sequence), so the 4-byte scratch
/// always fits; the read_buf path was pre-reserved by reserveReadBufTail,
/// and nothing between reserve and stash can run Scheme or switch fibers
/// (no VM call, and the raw allocator does not collect), so the reservation
/// cannot be invalidated in between.
fn stashDrainedBytes(port: *types.Port, bytes: []const u8) void {
    if (bytes.len == 0) return;
    if (port.read_buf_len == 0) {
        for (bytes) |b| {
            if (port.peek_byte == null and port.peek_extra_len == 0) {
                port.peek_byte = b;
            } else {
                port.peek_extra[port.peek_extra_len] = b;
                port.peek_extra_len += 1;
            }
        }
        return;
    }
    const rb = port.read_buf.?;
    const live_len = port.read_buf_len;
    std.debug.assert(live_len + bytes.len <= rb.len);
    // Compact the live span to the front (it is currently the tail) and lay
    // the new bytes down behind it, restoring the live-span-is-the-tail
    // cursor rule with the concatenated span.
    std.mem.copyForwards(u8, rb[0..live_len], rb[rb.len - live_len ..]);
    @memcpy(rb[live_len..][0..bytes.len], bytes);
    port.read_buf_len = live_len + bytes.len;
}
