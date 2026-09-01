//! Reactor OS backends (KEP-0001), split from `reactor.zig` along the
//! dispatch-versus-backend seam (file size policy): the four
//! readiness-multiplexer implementations — kqueue (macOS/BSDs), epoll
//! (Linux), poll_oneoff (WASI), WSAEventSelect + polled pipes (Windows) —
//! plus the shared per-poll buffer bound and NetBSD's versioned kevent
//! binding. `reactor.zig` selects one per target (`Backend`) and re-exports
//! `msFromNs`; the backend structs consume the reactor's normalized types
//! (`ReadyEvent`, `Interest`, `NotifierBackend`) through the circular
//! import, which Zig resolves lazily.
const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const reactor = @import("reactor.zig");

const linux = std.os.linux;

const ReadyEvent = reactor.ReadyEvent;
const Interest = reactor.Interest;
const NotifierBackend = reactor.NotifierBackend;

/// Events buffered per backend `wait()` call. A burst larger than this
/// drains over multiple `poll()` calls, which the scheduler loop already
/// performs naturally.
const max_events_per_poll: usize = 256;

/// NetBSD versions every libc symbol whose signature contains `time_t`:
/// the plain `kevent` symbol is the pre-6.0 compat wrapper reading a
/// 32-bit-tv_sec `struct timespec50` for the timeout, while modern code
/// (what the system headers' __RENAME(__kevent50) resolves to) must call
/// `__kevent50`. Zig's std.c declares only the plain name, so bind the
/// versioned symbol explicitly there; every other kqueue OS keeps the
/// plain name. (struct kevent itself never changed — only the timeout
/// parameter's type did.) `pub`: ThreadNotifier.notify (reactor.zig) rings
/// its EVFILT.USER trigger through this same binding.
pub const kevent_sys = if (builtin.os.tag == .netbsd) struct {
    extern "c" fn __kevent50(
        kq: c_int,
        changelist: [*]const std.c.Kevent,
        nchanges: c_int,
        eventlist: [*]std.c.Kevent,
        nevents: c_int,
        timeout: ?*const std.c.timespec,
    ) c_int;
}.__kevent50 else std.c.kevent;

// ---------------------------------------------------------------------------
// kqueue backend (macOS/Apple platforms, FreeBSD, OpenBSD, NetBSD)
// ---------------------------------------------------------------------------

pub const KqueueBackend = struct {
    kq: i32,
    raw: [max_events_per_poll]std.c.Kevent = undefined,
    ready: [max_events_per_poll]ReadyEvent = undefined,

    /// EV_EOF is 0x8000 on every kqueue OS (sys/event.h), but this Zig's
    /// freebsd std.c.EV binding omits the constant — fall back to the
    /// literal there.
    const EV_EOF: u16 = if (@hasDecl(std.c.EV, "EOF")) std.c.EV.EOF else 0x8000;

    /// Owns no allocations — the allocator is part of the uniform
    /// three-backend init signature (WasiPollBackend needs it). Also
    /// registers the one persistent EVFILT.USER knote (KEP-0002 §5) that
    /// ThreadNotifier.notify() rings later -- EV.CLEAR means it self-clears
    /// on retrieval, so no separate drain step is needed in wait().
    pub fn init(_: std.mem.Allocator) !KqueueBackend {
        const kq = std.c.kqueue();
        if (kq < 0) return error.Unexpected;
        // CLOEXEC: kqueue(2) takes no flags, and a kqueue fd IS a normal fd —
        // inherited across fork and kept open across exec unless FD_CLOEXEC
        // says otherwise (the comment on EpollBackend.init below long claimed
        // the opposite). Without this, the reactor's kq leaks into every
        // child the core spawns (KEP-0022 CLOEXEC audit).
        _ = platform.setFdCloexec(kq);
        var self: KqueueBackend = .{ .kq = kq };
        var reg = std.c.Kevent{
            .ident = 0,
            .filter = std.c.EVFILT.USER,
            .flags = std.c.EV.ADD | std.c.EV.CLEAR,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        };
        self.apply((&reg)[0..1]) catch {
            _ = platform.close(kq);
            return error.Unexpected;
        };
        return self;
    }

    pub fn notifierBackend(self: *const KqueueBackend) NotifierBackend {
        return .{ .kq = self.kq };
    }

    /// No-op: `kq` is shared with the notifier's EVFILT.USER registration
    /// (KEP-0002 §5), so exactly one place may ever close it -- concentrated
    /// entirely in releaseNotifier's zero-transition (reactor.zig top-level)
    /// instead of here, to avoid a double-close race on whichever release
    /// happens last. raw/ready are inline arrays, owning nothing else.
    pub fn deinit(self: *KqueueBackend) void {
        _ = self;
    }

    fn filterFor(interest: Interest) i16 {
        return switch (interest) {
            .read => std.c.EVFILT.READ,
            .write => std.c.EVFILT.WRITE,
        };
    }

    fn mkChange(fd: i32, interest: Interest, add: bool) std.c.Kevent {
        return .{
            .ident = @intCast(fd),
            .filter = filterFor(interest),
            .flags = if (add) (std.c.EV.ADD | std.c.EV.ONESHOT) else std.c.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = @intCast(fd),
        };
    }

    /// Read and write are independent kqueue filters (separate knotes), so
    /// arming one direction never disturbs the other and `first_time` is
    /// irrelevant here (kept for a uniform two-backend call site).
    pub fn arm(self: *KqueueBackend, fd: i32, wants_read: bool, wants_write: bool, _: bool) !void {
        var changes: [2]std.c.Kevent = undefined;
        var n: usize = 0;
        if (wants_read) {
            changes[n] = mkChange(fd, .read, true);
            n += 1;
        }
        if (wants_write) {
            changes[n] = mkChange(fd, .write, true);
            n += 1;
        }
        if (n == 0) return;
        try self.apply(changes[0..n]);
    }

    /// Child-exit watch (KEP-0022 Phase 2): one EVFILT_PROC + NOTE_EXIT
    /// knote, registered by pid alongside the fd knotes on the same kq.
    /// ONESHOT for the "armed ⇔ a waiter is parked" discipline the fd path
    /// uses; the kernel auto-deletes a PROC knote when its process is
    /// reaped anyway. EV_ADD on an already-exited-and-reaped pid fails
    /// ESRCH — surfaced as an error the registration caller closes with a
    /// WNOHANG reap.
    pub fn armProc(self: *KqueueBackend, pid: i32) !void {
        var change = [1]std.c.Kevent{.{
            .ident = @intCast(pid),
            .filter = std.c.EVFILT.PROC,
            .flags = std.c.EV.ADD | std.c.EV.ONESHOT,
            .fflags = std.c.NOTE.EXIT,
            .data = 0,
            .udata = 0,
        }};
        try self.apply(change[0..1]);
    }

    pub fn disarmProc(self: *KqueueBackend, pid: i32) void {
        // ENOENT is expected whenever the ONESHOT already fired or the
        // kernel auto-deleted the knote at reap time.
        var change = [1]std.c.Kevent{.{
            .ident = @intCast(pid),
            .filter = std.c.EVFILT.PROC,
            .flags = std.c.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        }};
        self.apply(change[0..1]) catch {};
    }

    pub fn disarmAll(self: *KqueueBackend, fd: i32) void {
        // Two independent calls, not one batched changelist: with a
        // zero-length eventlist, kevent() has nowhere to report a
        // per-change error, so it aborts the whole changelist at the first
        // failure. ENOENT is expected whenever a direction was never armed
        // (e.g. a write-only port has no read filter to delete) — batching
        // would let that expected ENOENT on one filter silently leave the
        // other filter's knote behind.
        var read_change = mkChange(fd, .read, false);
        self.apply((&read_change)[0..1]) catch {};
        var write_change = mkChange(fd, .write, false);
        self.apply((&write_change)[0..1]) catch {};
    }

    fn apply(self: *KqueueBackend, changes: []const std.c.Kevent) !void {
        var zero_ts: std.c.timespec = .{ .sec = 0, .nsec = 0 };
        const rc = kevent_sys(self.kq, changes.ptr, @intCast(changes.len), self.raw[0..0].ptr, 0, &zero_ts);
        if (rc < 0) return error.Unexpected;
    }

    pub fn wait(self: *KqueueBackend, timeout_ns: ?u64) ![]const ReadyEvent {
        var ts: std.c.timespec = undefined;
        var ts_ptr: ?*const std.c.timespec = null;
        if (timeout_ns) |ns| {
            ts = .{ .sec = @intCast(ns / 1_000_000_000), .nsec = @intCast(ns % 1_000_000_000) };
            ts_ptr = &ts;
        }
        const rc = kevent_sys(self.kq, self.raw[0..0].ptr, 0, &self.raw, self.raw.len, ts_ptr);
        if (rc < 0) {
            if (platform.errno(rc) == .INTR) return self.ready[0..0];
            return error.Unexpected;
        }

        const n: usize = @intCast(rc);
        var count: usize = 0;
        outer: for (self.raw[0..n]) |kev| {
            // The notifier's own EVFILT.USER trigger (KEP-0002 §5) — never
            // let it merge into a ReadyEvent slot by ident, since ident=0
            // could otherwise collide with a real fd 0 (stdin) READ event
            // in the same batch. wake_pending was already set by notify()
            // before this event was posted; nothing further to do here.
            if (kev.filter == std.c.EVFILT.USER) continue;
            const fd: i32 = @intCast(kev.ident);
            // Child-exit event (KEP-0022 Phase 2): the ident is a *pid*.
            // Reported under its own flag so a pid can never merge with (or
            // be merged into) a same-numbered fd's ReadyEvent slot.
            if (kev.filter == std.c.EVFILT.PROC) {
                self.ready[count] = .{ .fd = fd, .readable = false, .writable = false, .proc = true };
                count += 1;
                continue;
            }
            const broken = (kev.flags & EV_EOF) != 0;
            const is_read = kev.filter == std.c.EVFILT.READ;
            for (self.ready[0..count]) |*re| {
                if (re.fd == fd and !re.proc) {
                    if (is_read or broken) re.readable = true;
                    if (!is_read or broken) re.writable = true;
                    continue :outer;
                }
            }
            self.ready[count] = .{ .fd = fd, .readable = is_read or broken, .writable = !is_read or broken };
            count += 1;
        }
        return self.ready[0..count];
    }
};

// ---------------------------------------------------------------------------
// epoll backend (Linux)
// ---------------------------------------------------------------------------

pub const EpollBackend = struct {
    epfd: i32,
    /// The notifier's eventfd (KEP-0002 §5) -- a fd independent of `epfd`,
    /// registered into it but never ONESHOT ("unlike fd registrations, the
    /// notifier must stay armed"). Closing it is releaseNotifier's job
    /// (reactor.zig top-level), not EpollBackend.deinit's -- unlike kqueue,
    /// epfd and notify_fd are different fds, so no double-close risk exists
    /// either way; the split just keeps ownership consistent across both
    /// backends.
    notify_fd: i32,
    raw: [max_events_per_poll]linux.epoll_event = undefined,
    ready: [max_events_per_poll]ReadyEvent = undefined,

    pub fn init(_: std.mem.Allocator) !EpollBackend {
        // CLOEXEC: without it the epoll fd leaks into every child the core
        // spawns (thottam_proc.zig, native_compiler.zig via
        // std.process.Child). The kqueue backend sets FD_CLOEXEC after
        // kqueue() in KqueueBackend.init -- same discipline, different
        // mechanism, since kqueue(2) takes no flags argument.
        const rc = linux.epoll_create1(linux.EPOLL.CLOEXEC);
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
        const epfd: i32 = @intCast(rc);

        const efd_rc = linux.eventfd(0, linux.EFD.NONBLOCK | linux.EFD.CLOEXEC);
        if (linux.errno(efd_rc) != .SUCCESS) {
            _ = linux.close(epfd);
            return error.Unexpected;
        }
        const notify_fd: i32 = @intCast(efd_rc);

        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN, .data = .{ .fd = notify_fd } };
        const ctl_rc = linux.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, notify_fd, &ev);
        if (linux.errno(ctl_rc) != .SUCCESS) {
            _ = linux.close(notify_fd);
            _ = linux.close(epfd);
            return error.Unexpected;
        }

        return .{ .epfd = epfd, .notify_fd = notify_fd };
    }

    pub fn notifierBackend(self: *const EpollBackend) NotifierBackend {
        return .{ .fd = self.notify_fd };
    }

    pub fn deinit(self: *EpollBackend) void {
        _ = linux.close(self.epfd);
    }

    /// epoll's ONESHOT disarms the *whole* fd registration on any fire, not
    /// just the direction that fired — unlike kqueue's independent
    /// read/write knotes. `first_time` selects EPOLL_CTL_ADD (fresh fd) vs
    /// EPOLL_CTL_MOD (re-arm) since ADD on an already-tracked fd fails
    /// EEXIST, even while dormant after a ONESHOT fire.
    ///
    /// `first_time` is advisory, not authoritative: a port freed by the GC
    /// closes its fd without unregistering, which silently removes the fd
    /// from the epoll set while the Reactor's Reg (kernel_registered=true)
    /// survives. When the fd number is recycled onto a new port, the
    /// resulting MOD hits ENOENT — retry as ADD (and symmetrically ADD →
    /// EEXIST retries as MOD). kqueue needs no equivalent: EV_ADD is
    /// create-or-recreate either way.
    pub fn arm(self: *EpollBackend, fd: i32, wants_read: bool, wants_write: bool, first_time: bool) !void {
        var events: u32 = linux.EPOLL.ONESHOT;
        if (wants_read) events |= linux.EPOLL.IN;
        if (wants_write) events |= linux.EPOLL.OUT;
        var ev: linux.epoll_event = .{ .events = events, .data = .{ .fd = fd } };
        const op: u32 = if (first_time) linux.EPOLL.CTL_ADD else linux.EPOLL.CTL_MOD;
        var rc = linux.epoll_ctl(self.epfd, op, fd, &ev);
        if (linux.errno(rc) == .NOENT and op == linux.EPOLL.CTL_MOD) {
            rc = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_ADD, fd, &ev);
        } else if (linux.errno(rc) == .EXIST and op == linux.EPOLL.CTL_ADD) {
            rc = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_MOD, fd, &ev);
        }
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
    }

    pub fn disarmAll(self: *EpollBackend, fd: i32) void {
        _ = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_DEL, fd, null);
    }

    /// Child-exit watch (KEP-0022 Phase 2): the pidfd becomes readable when
    /// the child exits, so it registers like any fd — ONESHOT, read
    /// interest. The EEXIST retry mirrors `arm`'s: a re-registration after
    /// a fired ONESHOT is a MOD, not an ADD.
    pub fn armProc(self: *EpollBackend, pidfd: i32) !void {
        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN | linux.EPOLL.ONESHOT, .data = .{ .fd = pidfd } };
        var rc = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_ADD, pidfd, &ev);
        if (linux.errno(rc) == .EXIST) {
            rc = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_MOD, pidfd, &ev);
        }
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
    }

    pub fn disarmProc(self: *EpollBackend, pidfd: i32) void {
        _ = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_DEL, pidfd, null);
    }

    pub fn wait(self: *EpollBackend, timeout_ns: ?u64) ![]const ReadyEvent {
        const timeout_ms = msFromNs(timeout_ns);
        const rc = linux.epoll_wait(self.epfd, &self.raw, @intCast(self.raw.len), timeout_ms);
        const e = linux.errno(rc);
        if (e != .SUCCESS) {
            if (e == .INTR) return self.ready[0..0];
            return error.Unexpected;
        }

        const n: usize = @intCast(rc);
        for (self.raw[0..n], 0..) |ev, i| {
            if (ev.data.fd == self.notify_fd) {
                // Level-triggered eventfd (KEP-0002 §5, deliberately not
                // ONESHOT so it stays armed): must drain here or the next
                // epoll_wait returns immediately forever. wake_pending was
                // already set by notify() before this write; the ready
                // slot itself is inert (Reactor.poll's regs lookup never
                // finds an entry for notify_fd).
                var drain_buf: [8]u8 = undefined;
                _ = platform.read(self.notify_fd, &drain_buf, drain_buf.len);
                self.ready[i] = .{ .fd = self.notify_fd, .readable = false, .writable = false };
                continue;
            }
            // epoll_wait always reports HUP/ERR even if not requested; a fd
            // in either state must wake both directions defensively (real
            // observed behavior varies by fd type on which bits accompany
            // HUP/ERR — retrying a not-actually-ready direction is always
            // safe under the park-and-retry protocol).
            const broken = (ev.events & (linux.EPOLL.ERR | linux.EPOLL.HUP)) != 0;
            self.ready[i] = .{
                .fd = ev.data.fd,
                .readable = broken or (ev.events & linux.EPOLL.IN) != 0,
                .writable = broken or (ev.events & linux.EPOLL.OUT) != 0,
            };
        }
        return self.ready[0..n];
    }
};

/// epoll_wait's timeout is i32 milliseconds. Rounds up (ceil) so a timer
/// may fire slightly late but never early (resolved KEP-0001 question 2).
///
/// `pub` (and outside `EpollBackend`) so it compiles and can be asserted on
/// every target, not only Linux: it is the sole backend-specific timeout
/// rule that is a pure function, which is what lets a kqueue host verify
/// epoll's arithmetic — see `tests_reactor_parity.zig`.
pub fn msFromNs(timeout_ns: ?u64) i32 {
    const ns = timeout_ns orelse return -1;
    if (ns == 0) return 0;
    const ms = (ns +| 999_999) / 1_000_000;
    return if (ms > std.math.maxInt(i32)) std.math.maxInt(i32) else @intCast(ms);
}

// ---------------------------------------------------------------------------
// WASI poll_oneoff backend (KEP-0001 Phase 4)
//
// poll_oneoff is stateless: there is no kernel object that remembers
// interest between calls (the kqueue/epoll fd of the other backends).
// `interests` is that state, kept in userspace — arm() records the armed
// directions per fd, and every wait() rebuilds the full subscription list
// from it: one FD_READ/FD_WRITE subscription per armed direction plus one
// CLOCK subscription bounding the wait (the mio wasi model). An event
// disarms the direction it reports, giving ONESHOT parity with the other
// backends: "armed ⇔ a fiber is parked" holds by construction, and a
// stale interest (waiter removed via removeWaiter) fires at most once
// before self-clearing.
//
// Fd readiness is best-effort by design (KEP-0001 cross-platform
// section) — the capability probe lives in primitives_io's
// maybeSetNonblocking: a host that rejects fd_fdstat_set_flags(NONBLOCK)
// keeps its ports on blocking fds, so no EAGAIN, no registrations, and
// this backend degrades to single-fiber blocking I/O with CLOCK-only
// waits. That is exactly the playground's browser shim, which supports
// only a single CLOCK subscription per call — satisfied here since no fd
// can ever register there. wasmtime implements the full API.
// ---------------------------------------------------------------------------

pub const WasiPollBackend = struct {
    const wasi = std.os.wasi;

    const Dirs = struct { read: bool, write: bool };

    allocator: std.mem.Allocator,
    /// fd → armed directions; the userspace stand-in for kernel knotes.
    interests: std.AutoArrayHashMapUnmanaged(i32, Dirs) = .empty,
    /// Scratch buffers rebuilt each wait(); persistent so they grow to the
    /// working set once and stay there.
    subs: std.ArrayList(wasi.subscription_t) = .empty,
    events: std.ArrayList(wasi.event_t) = .empty,
    ready: std.ArrayList(ReadyEvent) = .empty,

    pub fn init(allocator: std.mem.Allocator) !WasiPollBackend {
        return .{ .allocator = allocator };
    }

    /// No real OS threads exist on WASI (thread-start! is already
    /// is_wasm-gated before reaching any KEP-0002 code) -- nothing for
    /// notify() to ring.
    pub fn notifierBackend(_: *const WasiPollBackend) NotifierBackend {
        return .{};
    }

    pub fn deinit(self: *WasiPollBackend) void {
        self.interests.deinit(self.allocator);
        self.subs.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.ready.deinit(self.allocator);
    }

    /// Both reactor call sites pass the fd's complete desired state
    /// (register: the current waiter lists; poll's re-arm: what remains
    /// after a fire), so this replaces rather than accumulates — epoll's
    /// CTL_MOD, minus the kernel. `first_time` is irrelevant: there is no
    /// kernel registry to ADD-versus-MOD against.
    pub fn arm(self: *WasiPollBackend, fd: i32, wants_read: bool, wants_write: bool, _: bool) !void {
        if (!wants_read and !wants_write) {
            _ = self.interests.swapRemove(fd);
            return;
        }
        try self.interests.put(self.allocator, fd, .{ .read = wants_read, .write = wants_write });
    }

    pub fn disarmAll(self: *WasiPollBackend, fd: i32) void {
        _ = self.interests.swapRemove(fd);
    }

    fn subFd(fd: i32, comptime tag: wasi.eventtype_t) wasi.subscription_t {
        return .{
            // The fd, not a fiber pointer — same discipline as kqueue's
            // udata/epoll's data.fd (a collected fiber must never be
            // reachable from a stale host event).
            .userdata = @intCast(fd),
            .u = .{ .tag = tag, .u = switch (tag) {
                .FD_READ => .{ .fd_read = .{ .fd = fd } },
                .FD_WRITE => .{ .fd_write = .{ .fd = fd } },
                else => @compileError("subFd is for fd subscriptions"),
            } },
        };
    }

    pub fn wait(self: *WasiPollBackend, timeout_ns: ?u64) ![]const ReadyEvent {
        self.subs.clearRetainingCapacity();
        var it = self.interests.iterator();
        while (it.next()) |entry| {
            const fd = entry.key_ptr.*;
            if (entry.value_ptr.read) try self.subs.append(self.allocator, subFd(fd, .FD_READ));
            if (entry.value_ptr.write) try self.subs.append(self.allocator, subFd(fd, .FD_WRITE));
        }
        if (timeout_ns) |ns| {
            // Relative (flags = 0), not ABSTIME: the reactor core already
            // reduced the timer heap's nearest deadline to a relative
            // bound in effectiveTimeout(), same as the kqueue timespec and
            // epoll ms paths. Re-deriving an absolute deadline here would
            // just add a clock read and couple this code to clockNs()'s
            // clock domain. Nanosecond-native, so no ceil-rounding is
            // needed (the epoll-only concern of resolved question 2);
            // "may fire late, never early" holds either way.
            try self.subs.append(self.allocator, .{
                .userdata = 0,
                .u = .{ .tag = .CLOCK, .u = .{ .clock = .{
                    .id = .MONOTONIC,
                    .timeout = ns,
                    .precision = 0,
                    .flags = 0,
                } } },
            });
        }
        // No subscriptions means no bound and nothing armed: poll_oneoff
        // rejects nsubscriptions == 0 (INVAL). Unreachable through the
        // scheduler — parkOnReactor checks isEmpty() first — so this is
        // only a direct-caller guard; an empty return beats a hard error.
        if (self.subs.items.len == 0) return &[_]ReadyEvent{};

        try self.events.ensureTotalCapacity(self.allocator, self.subs.items.len);
        self.events.items.len = self.subs.items.len;
        var nevents: usize = 0;
        const rc = wasi.poll_oneoff(&self.subs.items[0], &self.events.items[0], self.subs.items.len, &nevents);
        switch (rc) {
            .SUCCESS => {},
            .INTR => return &[_]ReadyEvent{},
            else => return error.Unexpected,
        }

        self.ready.clearRetainingCapacity();
        // Reserved before the loop runs any clearInterest: a fallible
        // append after an interest was disarmed would consume the event
        // without delivering it — the waiter would never be woken and
        // never re-armed (the same consumed-but-undelivered invariant
        // Reactor.poll guards with its own up-front ensureUnusedCapacity).
        // Dedup can only shrink the count, so nevents bounds the appends.
        try self.ready.ensureTotalCapacity(self.allocator, nevents);
        outer: for (self.events.items[0..nevents]) |ev| {
            // Timer expiry is decided by the reactor against clockNs()
            // (popExpiredTimers); the CLOCK event only ends the wait.
            if (ev.type == .CLOCK) continue;
            const fd: i32 = @intCast(ev.userdata);
            // A per-subscription error (BADF on a raced-away fd, rights)
            // or hangup wakes both directions defensively — the retried
            // syscall surfaces the real outcome, and retrying a
            // not-actually-ready direction is always safe under the
            // park-and-retry protocol (same policy as epoll's HUP/ERR).
            const broken = ev.@"error" != .SUCCESS or
                (ev.fd_readwrite.flags & wasi.EVENT_FD_READWRITE_HANGUP) != 0;
            const readable = ev.type == .FD_READ or broken;
            const writable = ev.type == .FD_WRITE or broken;
            self.clearInterest(fd, readable, writable);
            for (self.ready.items) |*re| {
                if (re.fd == fd) {
                    if (readable) re.readable = true;
                    if (writable) re.writable = true;
                    continue :outer;
                }
            }
            self.ready.appendAssumeCapacity(.{ .fd = fd, .readable = readable, .writable = writable });
        }
        return self.ready.items;
    }

    /// The ONESHOT half of the emulation: a delivered direction disarms
    /// itself, so the next wait() cannot re-report it unless the reactor
    /// re-arms (kqueue's per-filter knote deletion, not epoll's whole-fd
    /// disarm — an untouched direction stays armed for its own waiters).
    fn clearInterest(self: *WasiPollBackend, fd: i32, readable: bool, writable: bool) void {
        const dirs = self.interests.getPtr(fd) orelse return;
        if (readable) dirs.read = false;
        if (writable) dirs.write = false;
        if (!dirs.read and !dirs.write) _ = self.interests.swapRemove(fd);
    }
};

// ---------------------------------------------------------------------------
// Windows event backend (#1608: socket + pipe readiness)
//
// Win32 has no unified readiness API for arbitrary handles, so this
// backend is two mechanisms behind one wait:
//
// * Sockets (stage 1) get event-driven readiness. maybeSetNonblocking's
//   fdKind probe flips them via FIONBIO, their reads/writes EAGAIN
//   through sockRecv/sockSend, and every armed socket posts its
//   network-event records via WSAEventSelect to one shared manual-reset
//   event (`sock_event`). wait() blocks on exactly two handles — the
//   auto-reset notify event (KEP-0002 cross-thread ring, unchanged) and
//   `sock_event` — bounded by the nearest timer deadline; after any
//   wakeup a sweep WSAEnumNetworkEvents-es every armed socket and maps
//   the records onto ReadyEvents (FD_READ/FD_ACCEPT → readable,
//   FD_WRITE/FD_CONNECT → writable, FD_CLOSE → both, the epoll HUP
//   policy). Sharing one event avoids the 64-handle
//   WaitForMultipleObjects ceiling outright; the O(armed) sweep mirrors
//   WasiPollBackend's per-wait rebuild.
//
//   FD_WRITE and FD_CLOSE are edge-recorded, and (re)issuing
//   WSAEventSelect clears the socket's pending records — so a condition
//   that became true before arm() would be missed entirely (the classic
//   WSAEventSelect races: send hit WSAEWOULDBLOCK, the peer drained the
//   buffer, *then* the fiber parked). arm() therefore takes a 0-timeout
//   select() snapshot right after arming and stashes it as pre-ready
//   state that the next wait() reports without blocking.
//
// * Pipes (stage 2) get *polled* readiness. Pipe handles are not
//   waitable readiness objects and carry no would-block mode; completion
//   I/O is off the table too (CRT/inherited anonymous pipes lack
//   FILE_FLAG_OVERLAPPED — see platform_win_pipe.zig). What they do
//   offer is non-destructive state queries, so a pipe port EAGAINs
//   through pipeRead/pipeWrite's peek/quota pre-checks, and while any
//   pipe interest is armed wait() bounds its block at
//   `pipe_poll_quantum_ns` and re-runs the same checks (pipePollReady)
//   in its sweep — level-triggered by construction, so none of the
//   edge-record races above apply and no pre-ready snapshot is needed.
//   The quantum is the same order as the ~15 ms OS timer granularity
//   that already bounds this backend's timers, and it is paid only
//   while a fiber is actually parked on a pipe.
//
// Files stay fully blocking — which is the POSIX baseline as well
// (O_NONBLOCK is a no-op on regular files; epoll rejects them), so
// there is no cross-platform behavior gap to lift for them.
// ---------------------------------------------------------------------------

pub const WindowsEventBackend = struct {
    /// Notify event (auto-reset). Shared with the ThreadNotifier (same
    /// handle), so — like kqueue's `kq` — exactly one place may close it:
    /// releaseNotifier's zero transition, never deinit here.
    event: platform.win.HANDLE,
    /// The single event every armed socket's WSAEventSelect signals
    /// (manual-reset; wait() resets it before each sweep). Owned by this
    /// backend, closed in deinit.
    sock_event: platform.win.HANDLE,
    allocator: std.mem.Allocator,
    /// fd → armed socket state; the userspace registry the sweep walks
    /// (kernel knotes' stand-in, like WasiPollBackend.interests).
    sockets: std.AutoHashMap(i32, SockReg),
    /// fd → armed pipe interest (#1608 stage 2). No kernel object backs
    /// these; while non-empty, wait() bounds its block at the poll
    /// quantum and re-checks each entry (pipePollReady) in its sweep. A
    /// reported direction disarms itself (the WasiPollBackend ONESHOT
    /// emulation), so entries exist only while a fiber is parked and the
    /// quantum is never paid otherwise.
    pipes: std.AutoHashMap(i32, PipeReg),
    ready: std.ArrayList(ReadyEvent) = .empty,
    /// Sweep scratch: fds whose socket died under the registration, and
    /// pipe fds whose armed interest was fully consumed this sweep.
    dead: std.ArrayList(i32) = .empty,
    /// Whether any armed socket carries an unreported pre-ready snapshot;
    /// makes the next wait() a 0-timeout collect instead of a block.
    any_pre_ready: bool = false,

    const SockReg = struct {
        sock: platform.win.SOCKET,
        /// arm()'s select() snapshot: ready-at-arm-time conditions whose
        /// event records were clobbered by WSAEventSelect itself (see the
        /// header comment). Consumed by the next wait() sweep.
        pre_read: bool = false,
        pre_write: bool = false,
    };

    const PipeReg = struct { want_read: bool, want_write: bool };

    /// Wait-timeout cap while any pipe interest is armed. Pipe readiness
    /// on Windows is polled (header comment); this is the cadence — the
    /// same order as the OS scheduler's ~15 ms timer granularity that
    /// already bounds this backend, so pipe waits join the platform's
    /// existing latency envelope rather than adding a new one.
    const pipe_poll_quantum_ms: u32 = 10;

    pub fn init(allocator: std.mem.Allocator) !WindowsEventBackend {
        const ev = platform.win.CreateEventW(null, 0, 0, null) orelse return error.Unexpected;
        const sock_ev = platform.win.CreateEventW(null, 1, 0, null) orelse {
            _ = platform.win.CloseHandle(ev);
            return error.Unexpected;
        };
        return .{
            .event = ev,
            .sock_event = sock_ev,
            .allocator = allocator,
            .sockets = std.AutoHashMap(i32, SockReg).init(allocator),
            .pipes = std.AutoHashMap(i32, PipeReg).init(allocator),
        };
    }

    pub fn notifierBackend(self: *const WindowsEventBackend) NotifierBackend {
        return .{ .event = self.event };
    }

    pub fn deinit(self: *WindowsEventBackend) void {
        // Disarm every still-registered socket before its event handle
        // goes away: an armed WSAEventSelect association may outlive the
        // Reactor (a port closed only after scheduler teardown), and
        // while AFD holds its own reference on the event object, leaving
        // a live mask pointed at a handle this thread no longer owns has
        // no upside. Best-effort — the socket may already be closed.
        var it = self.sockets.iterator();
        while (it.next()) |entry| {
            _ = platform.win.WSAEventSelect(entry.value_ptr.sock, null, 0);
        }
        _ = platform.win.CloseHandle(self.sock_event);
        self.sockets.deinit();
        self.pipes.deinit();
        self.ready.deinit(self.allocator);
        self.dead.deinit(self.allocator);
    }

    /// Arms readiness interest for the socket or pipe behind `fd`. Both
    /// reactor call sites pass the fd's complete desired state, and both
    /// mechanisms replace the previous interest wholesale — epoll's
    /// CTL_MOD shape, so `first_time` is irrelevant. The fd's kind and
    /// its SOCKET are re-derived on every arm, which also self-heals
    /// fd-number recycling over a stale registration (the epoll
    /// ENOENT-retry concern), including a recycle that changes the fd's
    /// kind — each path drops the other registry's entry. Fails cleanly
    /// on a non-socket, non-pipe fd (WSAEventSelect: WSAENOTSOCK) —
    /// waitForFd turns that into a diagnosable registration error;
    /// port-layer callers never get here for files because file ports
    /// never EAGAIN.
    pub fn arm(self: *WindowsEventBackend, fd: i32, wants_read: bool, wants_write: bool, _: bool) !void {
        platform.ensureWinsock();
        if (platform.fdKind(fd) == .pipe) {
            _ = self.sockets.remove(fd);
            try self.pipes.put(fd, .{ .want_read = wants_read, .want_write = wants_write });
            return;
        }
        _ = self.pipes.remove(fd);
        const sock = platform.sockFromFd(fd) orelse return error.Unexpected;

        // Reserve the map slot before touching the kernel so an OOM can't
        // leave an armed mask with no registry entry behind it.
        const gop = try self.sockets.getOrPut(fd);
        errdefer if (!gop.found_existing) {
            _ = self.sockets.remove(fd);
        };

        var mask: c_long = 0;
        if (wants_read) mask |= platform.win.FD_READ | platform.win.FD_ACCEPT | platform.win.FD_CLOSE;
        if (wants_write) mask |= platform.win.FD_WRITE | platform.win.FD_CONNECT | platform.win.FD_CLOSE;
        if (platform.win.WSAEventSelect(sock, self.sock_event, mask) != 0) return error.Unexpected;

        // The post-arm race probe (see the header comment). Runs after
        // WSAEventSelect so nothing can become ready between probe and
        // arm unobserved: a condition arising after the arm is recorded
        // by the mask, one already true before it is caught here.
        const pre = platform.sockPollReady(sock, wants_read, wants_write);
        gop.value_ptr.* = .{ .sock = sock, .pre_read = pre.readable, .pre_write = pre.writable };
        if (pre.readable or pre.writable) self.any_pre_ready = true;
    }

    pub fn disarmAll(self: *WindowsEventBackend, fd: i32) void {
        if (self.sockets.fetchRemove(fd)) |kv| {
            // Best-effort cancel; errors (the socket may already be gone)
            // are irrelevant since the registry entry is dropped either way.
            _ = platform.win.WSAEventSelect(kv.value.sock, null, 0);
        }
        // Pipes have no kernel arming to cancel — dropping the entry is
        // the whole disarm.
        _ = self.pipes.remove(fd);
    }

    pub fn wait(self: *WindowsEventBackend, timeout_ns: ?u64) ![]const ReadyEvent {
        // One ceil-to-ms rule for every backend: call msFromNs (resolved
        // KEP-0001 question 2 — a timer may fire slightly late but never
        // early) and translate its i32/-1 convention into the Windows
        // u32/INFINITE one. -1 ("no bound") becomes INFINITE; a positive
        // result is clamped to INFINITE-1.
        const ms_i32 = msFromNs(timeout_ns);
        var ms: u32 = if (ms_i32 < 0)
            platform.win.INFINITE
        else
            @min(@as(u32, @intCast(ms_i32)), platform.win.INFINITE - 1);
        // Armed pipe interest has no kernel wakeup — bound the block at
        // the poll quantum so the sweep below re-checks it (#1608 stage 2).
        if (self.pipes.count() > 0) ms = @min(ms, pipe_poll_quantum_ms);
        // Unreported pre-ready state turns the block into a collect pass.
        if (self.any_pre_ready) ms = 0;

        var handles = [2]platform.win.HANDLE{ self.event, self.sock_event };
        _ = platform.win.WaitForMultipleObjects(handles.len, &handles, 0, ms);

        // Reset before sweeping, unconditionally: readiness detection
        // below comes from per-socket records and pre-ready flags, never
        // from the event's own state, so records posted after this reset
        // simply re-signal for the next wait — nothing is lost, and a
        // signaled event with no matching registration can't busy-loop
        // the scheduler.
        _ = platform.win.ResetEvent(self.sock_event);

        // Reserved up front so the sweep below can't fail after
        // WSAEnumNetworkEvents has already consumed a socket's records —
        // the same consumed-but-undelivered invariant Reactor.poll and
        // WasiPollBackend guard with their own ensure-capacity calls.
        self.ready.clearRetainingCapacity();
        self.dead.clearRetainingCapacity();
        const max_events = self.sockets.count() + self.pipes.count();
        try self.ready.ensureTotalCapacity(self.allocator, max_events);
        try self.dead.ensureTotalCapacity(self.allocator, max_events);
        self.any_pre_ready = false;

        var it = self.sockets.iterator();
        while (it.next()) |entry| {
            const fd = entry.key_ptr.*;
            const reg = entry.value_ptr;
            var readable = reg.pre_read;
            var writable = reg.pre_write;
            reg.pre_read = false;
            reg.pre_write = false;

            var ne: platform.win.WSANetworkEvents = undefined;
            if (platform.win.WSAEnumNetworkEvents(reg.sock, null, &ne) != 0) {
                // The socket died under the registration (a GC-freed port
                // closes its fd without unregister). Report both
                // directions broken once — a parked waiter's retry then
                // surfaces the real error — and drop the entry so a dead
                // socket can't re-fire on every subsequent wait.
                readable = true;
                writable = true;
                self.dead.appendAssumeCapacity(fd);
            } else {
                const ev = ne.network_events;
                const broken = (ev & platform.win.FD_CLOSE) != 0;
                if (broken or (ev & (platform.win.FD_READ | platform.win.FD_ACCEPT)) != 0) readable = true;
                if (broken or (ev & (platform.win.FD_WRITE | platform.win.FD_CONNECT)) != 0) writable = true;
            }
            if (readable or writable) {
                self.ready.appendAssumeCapacity(.{ .fd = fd, .readable = readable, .writable = writable });
            }
        }
        for (self.dead.items) |fd| _ = self.sockets.remove(fd);

        // Pipe sweep (#1608 stage 2): polled, level-triggered readiness —
        // each pass re-derives the fd's current state, so there are no
        // event records to lose and no pre-ready snapshots to keep. A
        // reported direction disarms itself (the WasiPollBackend ONESHOT
        // emulation: armed ⇔ a fiber is parked holds by construction);
        // Reactor.poll re-arms for whatever waiters remain after a fire.
        self.dead.clearRetainingCapacity();
        var pit = self.pipes.iterator();
        while (pit.next()) |entry| {
            const fd = entry.key_ptr.*;
            const reg = entry.value_ptr;
            const r = platform.pipePollReady(fd, reg.want_read, reg.want_write);
            if (!r.readable and !r.writable) continue;
            self.ready.appendAssumeCapacity(.{ .fd = fd, .readable = r.readable, .writable = r.writable });
            if (r.readable) reg.want_read = false;
            if (r.writable) reg.want_write = false;
            if (!reg.want_read and !reg.want_write) self.dead.appendAssumeCapacity(fd);
        }
        for (self.dead.items) |fd| _ = self.pipes.remove(fd);
        // Timer expiry is decided by the reactor against clockNs()
        // (popExpiredTimers); a notify set wake_pending before SetEvent.
        return self.ready.items;
    }
};
