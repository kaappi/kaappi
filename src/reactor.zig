//! Per-OS-thread I/O readiness multiplexer (KEP-0001 Phases 1-2).
//!
//! One `Reactor` belongs to one OS thread's scheduler. A fiber that would
//! block on a fd registers its interest and parks; `poll` blocks once,
//! bounded by the nearest timer deadline, and reports every fiber that
//! became runnable (fd readiness or timer expiry). Wired into the
//! scheduler in KEP-0001 Phase 2 (fiber.zig's runSchedulerStep). See
//! https://github.com/kaappi/keps/blob/main/keps/0001-event-loop-reactor.md
const std = @import("std");
const builtin = @import("builtin");
const fiber_mod = @import("fiber.zig");
const memory = @import("memory.zig");
const types = @import("types.zig");
const Fiber = fiber_mod.Fiber;

const linux = std.os.linux;

/// Events buffered per backend `wait()` call. A burst larger than this
/// drains over multiple `poll()` calls, which the scheduler loop already
/// performs naturally.
const max_events_per_poll: usize = 256;

pub const Interest = enum { read, write };

/// A backend-normalized readiness result: which directions fired for `fd`.
const ReadyEvent = struct { fd: i32, readable: bool, writable: bool };

const Backend = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos => KqueueBackend,
    .linux => EpollBackend,
    .wasi => WasiBackend,
    else => @compileError("reactor: unsupported OS (kqueue/epoll/wasi only)"),
};

const TimerEntry = struct {
    deadline_ns: u64,
    fiber: *Fiber,
};

fn timerLessThan(_: void, a: TimerEntry, b: TimerEntry) std.math.Order {
    return std.math.order(a.deadline_ns, b.deadline_ns);
}

const TimerHeap = std.PriorityQueue(TimerEntry, void, timerLessThan);

/// Per-fd bookkeeping. Waiter lists are usually length 1; multiple waiters
/// on one direction are woken all at once on readiness (resolved KEP-0001
/// question 1) — the same discipline `FiberScheduler.wakeChannelWaiters`
/// uses for channels. Losers of the resulting retry race simply re-park.
const Reg = struct {
    read_waiters: std.ArrayList(*Fiber) = .empty,
    write_waiters: std.ArrayList(*Fiber) = .empty,
    /// Whether this fd has ever been armed with the backend. epoll must
    /// distinguish first-arm (EPOLL_CTL_ADD) from re-arm (EPOLL_CTL_MOD) —
    /// re-adding an already-tracked fd fails EEXIST. kqueue ignores this
    /// (EV_ADD is idempotent whether creating fresh or recreating a knote
    /// that a prior EV_ONESHOT deleted).
    kernel_registered: bool = false,

    fn isEmpty(self: Reg) bool {
        return self.read_waiters.items.len == 0 and self.write_waiters.items.len == 0;
    }
};

pub const Reactor = struct {
    allocator: std.mem.Allocator,
    backend: Backend,
    regs: std.AutoHashMap(i32, Reg),
    timers: TimerHeap,

    pub fn init(allocator: std.mem.Allocator) !Reactor {
        return .{
            .allocator = allocator,
            .backend = try Backend.init(),
            .regs = std.AutoHashMap(i32, Reg).init(allocator),
            .timers = .empty,
        };
    }

    pub fn deinit(self: *Reactor) void {
        var it = self.regs.valueIterator();
        while (it.next()) |reg| {
            reg.read_waiters.deinit(self.allocator);
            reg.write_waiters.deinit(self.allocator);
        }
        self.regs.deinit();
        self.timers.deinit(self.allocator);
        self.backend.deinit();
    }

    /// Registers `fiber` as waiting for `interest` on `fd`. On success the
    /// fd is armed with the OS (ONESHOT — resolved question 3: the
    /// registration exists only while a fiber is parked, by construction).
    pub fn register(self: *Reactor, fd: i32, interest: Interest, fiber: *Fiber) !void {
        const gop = try self.regs.getOrPut(fd);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        const reg = gop.value_ptr;

        switch (interest) {
            .read => try reg.read_waiters.append(self.allocator, fiber),
            .write => try reg.write_waiters.append(self.allocator, fiber),
        }
        errdefer switch (interest) {
            .read => _ = reg.read_waiters.pop(),
            .write => _ = reg.write_waiters.pop(),
        };

        const wants_read = reg.read_waiters.items.len > 0;
        const wants_write = reg.write_waiters.items.len > 0;
        try self.backend.arm(fd, wants_read, wants_write, !reg.kernel_registered);
        reg.kernel_registered = true;
    }

    /// Drops all bookkeeping and OS-level registration for `fd`. Does not
    /// wake parked waiters — the caller (close-port, KEP-0001 Phase 3) is
    /// responsible for that, since it already knows which fibers to wake
    /// (resolved question 4: fd-keyed registration is sufficient because no
    /// user code runs between `poll()` returning and the scheduler's status
    /// flips, so the tokio-style fd-recycle race cannot occur here).
    pub fn unregister(self: *Reactor, fd: i32) void {
        if (self.regs.fetchRemove(fd)) |kv| {
            var reg = kv.value;
            self.backend.disarmAll(fd);
            reg.read_waiters.deinit(self.allocator);
            reg.write_waiters.deinit(self.allocator);
        }
    }

    pub fn addTimer(self: *Reactor, deadline_ns: u64, fiber: *Fiber) !void {
        try self.timers.push(self.allocator, .{ .deadline_ns = deadline_ns, .fiber = fiber });
    }

    /// Cancels `fiber`'s pending timer, if any. Needed whenever a timed
    /// wait resolves through its non-timeout path (e.g. a mutex unlock
    /// wakes a fiber that was also timed-waiting on the lock) — otherwise a
    /// stale heap entry could later fire against a reused fiber slot.
    /// No-op if `fiber` has no pending timer. Not part of the original KEP
    /// sketch; added because Phase 2's timed waits require it.
    pub fn removeTimer(self: *Reactor, fiber: *Fiber) void {
        for (self.timers.items, 0..) |entry, i| {
            if (entry.fiber == fiber) {
                _ = self.timers.popIndex(i);
                return;
            }
        }
    }

    /// True iff nothing could ever produce a wakeup: no timers, and no fd
    /// currently has a waiter (a `Reg` may still exist with empty waiter
    /// lists between a fired ONESHOT event and its next re-arm or
    /// unregister — that is not "pending" and must not count here, or a
    /// leaked/never-reused registration would make genuine deadlocks
    /// un-detectable).
    pub fn isEmpty(self: *Reactor) bool {
        if (self.timers.count() != 0) return false;
        var it = self.regs.valueIterator();
        while (it.next()) |reg| {
            if (!reg.isEmpty()) return false;
        }
        return true;
    }

    /// GC root, not just belt-and-braces: addFiber's slot-reuse overwrites
    /// .completed/.errored slots in FiberScheduler.fibers[], and
    /// thread-terminate! moves a victim straight to .errored. If terminate
    /// ever raced ahead of removeTimer for a fiber's pending wait, that
    /// fiber's only remaining reference would be here, in the timer heap —
    /// this mark is what keeps it alive long enough for the pop to run.
    pub fn markRoots(self: *Reactor, gc: *memory.GC) void {
        var it = self.regs.valueIterator();
        while (it.next()) |reg| {
            for (reg.read_waiters.items) |f| gc.markValue(types.makePointer(@ptrCast(&f.header)));
            for (reg.write_waiters.items) |f| gc.markValue(types.makePointer(@ptrCast(&f.header)));
        }
        for (self.timers.items) |entry| gc.markValue(types.makePointer(@ptrCast(&entry.fiber.header)));
    }

    /// Blocks up to `timeout_ns` (or the nearest timer deadline, whichever
    /// is sooner; forever if both are null) and appends every fiber made
    /// runnable — by fd readiness or timer expiry — to `ready`. `ready`
    /// must use the same allocator this Reactor was `init`ed with.
    ///
    /// `ready` may contain the same fiber twice in one call: a fiber parked
    /// with both an fd registration and a timer (a timed wait) is appended
    /// once if the fd wins and again if the timer also expires in this same
    /// call, since nothing removes the timer entry when the fd path wins.
    /// Callers must tolerate a duplicate wake (e.g. an idempotent status
    /// flip on the second occurrence).
    pub fn poll(self: *Reactor, timeout_ns: ?u64, ready: *std.ArrayList(*Fiber)) !void {
        const wait_ns = self.effectiveTimeout(timeout_ns);
        const events = try self.backend.wait(wait_ns);

        for (events) |ev| {
            const reg = self.regs.getPtr(ev.fd) orelse continue; // stale event; already unregistered

            var fired = false;
            // Reserved up front so the drain below can't fail mid-way: a
            // failure after the kernel's ONESHOT event was consumed but
            // before all waiters were moved to `ready` would strand the
            // remaining waiters forever (nothing re-arms the fd for them),
            // and `isEmpty()` would still report a waiter, so no deadlock
            // detector would catch it either.
            try ready.ensureUnusedCapacity(self.allocator, reg.read_waiters.items.len + reg.write_waiters.items.len);
            if (ev.readable and reg.read_waiters.items.len > 0) {
                for (reg.read_waiters.items) |f| ready.appendAssumeCapacity(f);
                reg.read_waiters.clearRetainingCapacity();
                fired = true;
            }
            if (ev.writable and reg.write_waiters.items.len > 0) {
                for (reg.write_waiters.items) |f| ready.appendAssumeCapacity(f);
                reg.write_waiters.clearRetainingCapacity();
                fired = true;
            }
            if (!fired) continue;

            // epoll's ONESHOT disarms the *whole* fd registration on any
            // fire, even a direction that didn't fire (unlike kqueue, where
            // read/write are independent knotes and an untouched filter
            // stays armed). Re-arm for whatever's left. Harmless no-op
            // redundant EV_ADD on kqueue.
            const remaining_read = reg.read_waiters.items.len > 0;
            const remaining_write = reg.write_waiters.items.len > 0;
            if (remaining_read or remaining_write) {
                try self.backend.arm(ev.fd, remaining_read, remaining_write, false);
            }
        }

        try self.popExpiredTimers(ready);
    }

    /// Moves every timer whose deadline has already passed into `ready`,
    /// removing it from the heap. Called from `poll` (after an fd wait)
    /// and separately from `FiberScheduler.schedule` on every dispatch
    /// tick — not just when the scheduler goes idle — so a timed wait
    /// resolves promptly even while other runnable fibers (a busy/yielding
    /// sibling) mean `poll` is never reached at all.
    pub fn popExpiredTimers(self: *Reactor, ready: *std.ArrayList(*Fiber)) !void {
        const now = fiber_mod.clockNs();
        while (self.timers.peek()) |top| {
            if (top.deadline_ns > now) break;
            try ready.append(self.allocator, self.timers.pop().?.fiber);
        }
    }

    fn effectiveTimeout(self: *Reactor, cap_ns: ?u64) ?u64 {
        var result = cap_ns;
        if (self.timers.peek()) |top| {
            const now = fiber_mod.clockNs();
            const until: u64 = if (top.deadline_ns <= now) 0 else top.deadline_ns - now;
            result = if (result) |r| @min(r, until) else until;
        }
        return result;
    }
};

// ---------------------------------------------------------------------------
// kqueue backend (macOS/Apple platforms)
// ---------------------------------------------------------------------------

const KqueueBackend = struct {
    kq: i32,
    raw: [max_events_per_poll]std.c.Kevent = undefined,
    ready: [max_events_per_poll]ReadyEvent = undefined,

    fn init() !KqueueBackend {
        const kq = std.c.kqueue();
        if (kq < 0) return error.Unexpected;
        return .{ .kq = kq };
    }

    fn deinit(self: *KqueueBackend) void {
        _ = std.posix.system.close(self.kq);
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
    fn arm(self: *KqueueBackend, fd: i32, wants_read: bool, wants_write: bool, _: bool) !void {
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

    fn disarmAll(self: *KqueueBackend, fd: i32) void {
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
        const rc = std.c.kevent(self.kq, changes.ptr, @intCast(changes.len), self.raw[0..0].ptr, 0, &zero_ts);
        if (rc < 0) return error.Unexpected;
    }

    fn wait(self: *KqueueBackend, timeout_ns: ?u64) ![]const ReadyEvent {
        var ts: std.c.timespec = undefined;
        var ts_ptr: ?*const std.c.timespec = null;
        if (timeout_ns) |ns| {
            ts = .{ .sec = @intCast(ns / 1_000_000_000), .nsec = @intCast(ns % 1_000_000_000) };
            ts_ptr = &ts;
        }
        const rc = std.c.kevent(self.kq, self.raw[0..0].ptr, 0, &self.raw, self.raw.len, ts_ptr);
        if (rc < 0) {
            if (std.posix.errno(rc) == .INTR) return self.ready[0..0];
            return error.Unexpected;
        }

        const n: usize = @intCast(rc);
        var count: usize = 0;
        outer: for (self.raw[0..n]) |kev| {
            const fd: i32 = @intCast(kev.ident);
            const broken = (kev.flags & std.c.EV.EOF) != 0;
            const is_read = kev.filter == std.c.EVFILT.READ;
            for (self.ready[0..count]) |*re| {
                if (re.fd == fd) {
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

const EpollBackend = struct {
    epfd: i32,
    raw: [max_events_per_poll]linux.epoll_event = undefined,
    ready: [max_events_per_poll]ReadyEvent = undefined,

    fn init() !EpollBackend {
        // CLOEXEC: without it the epoll fd leaks into every child the core
        // spawns (thottam_proc.zig, native_compiler.zig via
        // std.process.Child). kqueue needs no equivalent — kqueue(2) fds
        // are never inherited across fork by design.
        const rc = linux.epoll_create1(linux.EPOLL.CLOEXEC);
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
        return .{ .epfd = @intCast(rc) };
    }

    fn deinit(self: *EpollBackend) void {
        _ = linux.close(self.epfd);
    }

    /// epoll's ONESHOT disarms the *whole* fd registration on any fire, not
    /// just the direction that fired — unlike kqueue's independent
    /// read/write knotes. `first_time` selects EPOLL_CTL_ADD (fresh fd) vs
    /// EPOLL_CTL_MOD (re-arm) since ADD on an already-tracked fd fails
    /// EEXIST, even while dormant after a ONESHOT fire.
    fn arm(self: *EpollBackend, fd: i32, wants_read: bool, wants_write: bool, first_time: bool) !void {
        var events: u32 = linux.EPOLL.ONESHOT;
        if (wants_read) events |= linux.EPOLL.IN;
        if (wants_write) events |= linux.EPOLL.OUT;
        var ev: linux.epoll_event = .{ .events = events, .data = .{ .fd = fd } };
        const op: u32 = if (first_time) linux.EPOLL.CTL_ADD else linux.EPOLL.CTL_MOD;
        const rc = linux.epoll_ctl(self.epfd, op, fd, &ev);
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
    }

    fn disarmAll(self: *EpollBackend, fd: i32) void {
        _ = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_DEL, fd, null);
    }

    fn wait(self: *EpollBackend, timeout_ns: ?u64) ![]const ReadyEvent {
        const timeout_ms = msFromNs(timeout_ns);
        const rc = linux.epoll_wait(self.epfd, &self.raw, @intCast(self.raw.len), timeout_ms);
        const e = linux.errno(rc);
        if (e != .SUCCESS) {
            if (e == .INTR) return self.ready[0..0];
            return error.Unexpected;
        }

        const n: usize = @intCast(rc);
        for (self.raw[0..n], 0..) |ev, i| {
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
fn msFromNs(timeout_ns: ?u64) i32 {
    const ns = timeout_ns orelse return -1;
    if (ns == 0) return 0;
    const ms = (ns +| 999_999) / 1_000_000;
    return if (ms > std.math.maxInt(i32)) std.math.maxInt(i32) else @intCast(ms);
}

// ---------------------------------------------------------------------------
// WASI backend — timer-only stopgap.
//
// The full design (build a subscription_t[] — one fd_read/fd_write per
// registration plus one CLOCK subscription at the nearest deadline, call
// std.os.wasi.poll_oneoff) is KEP-0001 Phase 4. Nothing registers a port's
// fd with the reactor before Phase 3, so on wasm32-wasi today the only
// path that must actually work is a plain wait bounded by the timer
// heap's nearest deadline — exactly what thread-sleep! and timed
// mutex/join/condvar waits need. arm() is unreachable until Phase 3 lands
// I/O primitive changes (gated by the existing is_wasm flag, per the
// KEP's cross-platform section: WASI falls back to single-fiber blocking
// I/O where poll_oneoff socket support is unavailable).
// ---------------------------------------------------------------------------

const WasiBackend = struct {
    fn init() !WasiBackend {
        return .{};
    }

    fn deinit(self: *WasiBackend) void {
        _ = self;
    }

    fn arm(self: *WasiBackend, fd: i32, wants_read: bool, wants_write: bool, first_time: bool) !void {
        _ = self;
        _ = fd;
        _ = wants_read;
        _ = wants_write;
        _ = first_time;
        return error.Unexpected;
    }

    fn disarmAll(self: *WasiBackend, fd: i32) void {
        _ = self;
        _ = fd;
    }

    fn wait(self: *WasiBackend, timeout_ns: ?u64) ![]const ReadyEvent {
        _ = self;
        if (timeout_ns) |ns| {
            var ts: std.c.timespec = .{
                .sec = @intCast(ns / 1_000_000_000),
                .nsec = @intCast(ns % 1_000_000_000),
            };
            while (true) {
                const ret = std.c.nanosleep(&ts, &ts);
                if (ret == 0) break;
                if (std.posix.errno(ret) != .INTR) return error.Unexpected;
            }
        }
        return &[_]ReadyEvent{};
    }
};
