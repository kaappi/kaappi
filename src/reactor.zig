//! Per-OS-thread I/O readiness multiplexer (KEP-0001).
//!
//! One `Reactor` belongs to one OS thread's scheduler. A fiber that would
//! block on a fd registers its interest and parks; `poll` blocks once,
//! bounded by the nearest timer deadline, and reports every fiber that
//! became runnable (fd readiness or timer expiry). Wired into the
//! scheduler in KEP-0001 Phase 2 (fiber.zig's runSchedulerStep). Backends:
//! kqueue (macOS/BSD), epoll (Linux), poll_oneoff (WASI, Phase 4),
//! WSAEventSelect + polled pipes (Windows — #1608). See
//! https://github.com/kaappi/keps/blob/main/keps/0001-event-loop-reactor.md
const std = @import("std");
const platform = @import("platform.zig");
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

/// Upper bound on a single blocking poll (see `Reactor.effectiveTimeout`).
const MAX_POLL_WAIT_NS: u64 = 24 * 60 * 60 * std.time.ns_per_s;

pub const Interest = enum { read, write };

/// A backend-normalized readiness result: which directions fired for `fd`.
/// `proc` marks a child-exit event (KEP-0022 Phase 2): on kqueue, `fd` is
/// then a *pid* (EVFILT_PROC shares no namespace with fds, so the flag is
/// what keeps a pid from ever being read as a same-numbered descriptor); on
/// epoll a child exit arrives as ordinary readability of the pidfd and the
/// Reactor routes it by registry lookup instead, so the flag stays false.
const ReadyEvent = struct { fd: i32, readable: bool, writable: bool, proc: bool = false };

/// Whether this target's backend can watch a child process for exit
/// readiness (KEP-0022 Phase 2): kqueue's EVFILT_PROC, or Linux's
/// pidfd_open(2) registered with epoll. Windows joins in Phase 3 (process
/// HANDLE in the polled set); WASI has no spawn at all.
pub const supports_process_watch = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd, .linux => true,
    else => false,
};

const is_kqueue_os = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd => true,
    else => false,
};

const Backend = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd => KqueueBackend,
    .linux => EpollBackend,
    .wasi => WasiPollBackend,
    .windows => WindowsEventBackend,
    else => @compileError("reactor: unsupported OS (kqueue/epoll/wasi/windows only)"),
};

/// NetBSD versions every libc symbol whose signature contains `time_t`:
/// the plain `kevent` symbol is the pre-6.0 compat wrapper reading a
/// 32-bit-tv_sec `struct timespec50` for the timeout, while modern code
/// (what the system headers' __RENAME(__kevent50) resolves to) must call
/// `__kevent50`. Zig's std.c declares only the plain name, so bind the
/// versioned symbol explicitly there; every other kqueue OS keeps the
/// plain name. (struct kevent itself never changed — only the timeout
/// parameter's type did.)
const kevent_sys = if (builtin.os.tag == .netbsd) struct {
    extern "c" fn __kevent50(
        kq: c_int,
        changelist: [*]const std.c.Kevent,
        nchanges: c_int,
        eventlist: [*]std.c.Kevent,
        nevents: c_int,
        timeout: ?*const std.c.timespec,
    ) c_int;
}.__kevent50 else std.c.kevent;

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

/// KEP-0002 §5: cross-thread wakeup handle, one per Reactor (one per OS
/// thread). Registrations come only from SharedChannel waiter lists (§7);
/// the creating Reactor holds the base +1 (mirrors shared_object.init's
/// "the creating stub is the first counted reference"), released at
/// Reactor.deinit. Allocated from std.heap.c_allocator (not the Reactor's
/// own allocator) because it must be able to outlive this thread's Reactor
/// whenever another thread still holds a registration on it -- same
/// rationale as SharedChannel/Envelope (KEP-0002 §1).
pub const ThreadNotifier = struct {
    refcount: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    wake_pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Cleared at Reactor.deinit -- notify() on a dead handle is a no-op.
    /// Does NOT gate memory safety (the refcount does); it only skips a
    /// syscall that would otherwise touch a backend resource whose closing
    /// may already be in flight (see releaseNotifier).
    alive: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
    backend: NotifierBackend,

    /// Thread-safe: sets wake_pending (release store) then rings the OS
    /// primitive -- always both, so a notify racing the consume protocol's
    /// swap loop (fiber.zig) is never lost (KEP-0002 §5).
    pub fn notify(self: *ThreadNotifier) void {
        self.wake_pending.store(true, .release);
        if (!self.alive.load(.acquire)) return;
        switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd => {
                var triggers = [1]std.c.Kevent{.{
                    .ident = 0,
                    .filter = std.c.EVFILT.USER,
                    .flags = 0,
                    .fflags = std.c.NOTE.TRIGGER,
                    .data = 0,
                    .udata = 0,
                }};
                var zero_ts: std.c.timespec = .{ .sec = 0, .nsec = 0 };
                // Retry on EINTR: an unretried signal-interrupted kevent()
                // here would leave wake_pending set but no OS event ever
                // posted, and the reactor blocked in poll() has no other
                // way to learn a notify happened.
                while (true) {
                    const rc = kevent_sys(self.backend.kq, &triggers, 1, triggers[0..0].ptr, 0, &zero_ts);
                    if (rc >= 0 or platform.errno(rc) != .INTR) break;
                }
            },
            .linux => {
                const one: u64 = 1;
                while (true) {
                    const rc = platform.write(self.backend.fd, @ptrCast(&one), @sizeOf(u64));
                    if (rc >= 0 or platform.errno(rc) != .INTR) break;
                }
            },
            // Auto-reset event: signaling is idempotent while pending and
            // the next WaitForSingleObject consumes it atomically — the
            // same self-clearing wake the EVFILT.USER/eventfd paths give.
            .windows => _ = platform.win.SetEvent(self.backend.event),
            .wasi => {},
            else => unreachable,
        }
    }
};

/// Backend-specific data `notify()` needs to ring the live OS primitive.
/// Populated once, from the already-initialized backend, when the owning
/// Reactor is constructed (see Reactor.init / each backend's
/// `notifierBackend`).
const NotifierBackend = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd => struct { kq: i32 },
    .linux => struct { fd: i32 },
    .wasi => struct {},
    .windows => struct { event: platform.win.HANDLE },
    else => @compileError("reactor: unsupported OS (kqueue/epoll/wasi/windows only)"),
};

/// KEP-0002 §7 leak-check hook, mirrors shared_object.liveCount() --
/// ThreadNotifier is deliberately NOT a shared_object.Header instance (its
/// references come only from SharedChannel waiter lists, never GC stubs),
/// so it needs its own counterpart.
var notifier_live_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

pub fn notifierLiveCount() usize {
    return notifier_live_count.load(.monotonic);
}

pub fn retainNotifier(n: *ThreadNotifier) void {
    _ = n.refcount.fetchAdd(1, .monotonic);
}

/// Drops one reference. At the zero transition, closes the backend OS
/// resource and frees the struct -- ownership of that close is deliberately
/// concentrated entirely here rather than split with Reactor.deinit/backend
/// deinit, which would risk a double-close on kqueue (the notifier's
/// EVFILT.USER knote shares `kq` with ordinary fd polling -- see
/// KqueueBackend.deinit). Safe even though another thread might be
/// concurrently calling notify(): a thread only ever touches `n` while it
/// still holds one of its references (ring() calls notify() strictly before
/// releasing its own registration's ref), so no release can observe the
/// zero transition while another holder is still using the object -- the
/// same acq_rel argument shared_object.release already relies on.
pub fn releaseNotifier(n: *ThreadNotifier) void {
    if (n.refcount.fetchSub(1, .acq_rel) == 1) {
        switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd => _ = platform.close(n.backend.kq),
            .linux => _ = platform.close(n.backend.fd),
            .wasi => {},
            // Shared with the backend's wait — closed only here, exactly
            // like kqueue's shared kq (see KqueueBackend.deinit).
            .windows => _ = platform.win.CloseHandle(n.backend.event),
            else => unreachable,
        }
        std.heap.c_allocator.destroy(n);
        _ = notifier_live_count.fetchSub(1, .monotonic);
    }
}

// ---------------------------------------------------------------------------
// Cross-thread wait registry (KEP-0002 unresolved question 3, kaappi#2395)
// ---------------------------------------------------------------------------

/// The notifiers of every OS thread currently parked in a SRFI-18 wait whose
/// resolution can only come from *another* OS thread: `thread-join!` on a
/// running child, `mutex-lock!` on a mutex another thread holds, a
/// condition-variable wait, and a `thread-sleep!` that must still observe a
/// cross-thread `thread-terminate!`.
///
/// Those waits have no per-object waiter list to hang a notifier off — a
/// mutex or condition variable is an ordinary GC object reached through the
/// globals route (`docs/dev/thread-value-sharing.md`), owned by whichever
/// heap allocated it, with no cross-thread bookkeeping of its own — so the
/// unit of registration is the *thread*, not the object, and a state change
/// rings every parked thread rather than a selected few. The waiters then
/// re-check their own condition and re-park; a spurious wake costs one loop
/// iteration. This is what replaces the 1 ms `sleepNs` poll those waits used
/// before (KEP-0002 UQ3): the list is empty in every program where nothing is
/// cross-thread blocked, so `wakeCrossThreadWaiters` costs one uncontended
/// lock acquisition on every unlock/signal/exit that has nobody to wake.
///
/// One entry per *thread*, not per wait: a fiber blocked in `mutex-lock!` can
/// drive a sibling that itself blocks in a condition-variable wait, and both
/// resolve through the same reactor. `depth` counts those nested enrolments so
/// the inner one's withdrawal doesn't unregister the outer.
const WaitEntry = struct {
    notifier: *ThreadNotifier,
    depth: u32,
};

var wait_registry: std.ArrayList(WaitEntry) = .empty;
var wait_registry_lock: std.atomic.Mutex = .unlocked;

/// `wait_registry.items.len`, published under the lock so `crossThreadWaiterCount`
/// can be read without taking it. Deliberately NOT a lock-free fast-path gate
/// for `wakeCrossThreadWaiters` — see that function for why the ring must go
/// through the lock even when there is nobody to wake.
var wait_registry_len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

/// Registers this thread's notifier for cross-thread wakeups. Returns false
/// if the registry could not grow, which is a *degradation, not a failure*:
/// the caller falls back to its old bounded poll (`CROSS_THREAD_POLL_NS`),
/// which is exactly the pre-#2395 behaviour. Balanced by
/// `withdrawCrossThreadWaiter` — call it only when this returned true.
pub fn enrollCrossThreadWaiter(n: *ThreadNotifier) bool {
    memory.spinLock(&wait_registry_lock);
    defer memory.spinUnlock(&wait_registry_lock);
    for (wait_registry.items) |*e| {
        if (e.notifier == n) {
            e.depth += 1;
            return true;
        }
    }
    wait_registry.append(std.heap.c_allocator, .{ .notifier = n, .depth = 1 }) catch return false;
    retainNotifier(n);
    wait_registry_len.store(wait_registry.items.len, .release);
    return true;
}

pub fn withdrawCrossThreadWaiter(n: *ThreadNotifier) void {
    memory.spinLock(&wait_registry_lock);
    var released = false;
    for (wait_registry.items, 0..) |*e, i| {
        if (e.notifier != n) continue;
        e.depth -= 1;
        if (e.depth == 0) {
            _ = wait_registry.swapRemove(i);
            wait_registry_len.store(wait_registry.items.len, .release);
            released = true;
        }
        break;
    }
    memory.spinUnlock(&wait_registry_lock);
    // Outside the lock, mirroring shared_channel's `ring`: the zero
    // transition frees the notifier and closes its backend fd, neither of
    // which should happen with the registry lock held.
    if (released) releaseNotifier(n);
}

/// Rings every thread parked in a cross-thread SRFI-18 wait. Called from the
/// state changes those waits observe — a mutex unlock or abandonment, a
/// condition-variable signal/broadcast, a `thread-terminate!`, and an OS
/// thread's exit.
///
/// **Takes the lock unconditionally, even to discover the registry is empty.**
/// An atomic length gate read outside the lock would be a store-buffering
/// (Dekker) pattern — waiter enrols then re-checks the shared state; ringer
/// writes the state then reads the length — in which *both* sides may miss
/// the other's store, since the state accesses are the plain acquire/release
/// ones the mutex and condvar already use. That is a lost wakeup, and with no
/// poll cap left to paper it over (see CROSS_THREAD_POLL_NS in
/// primitives_srfi18.zig), a hang. Going through the lock replaces that
/// argument with mutual exclusion: a ringer that finds the registry empty
/// released the lock before the enroller acquired it, so the enroller's own
/// state re-check — which follows its enrolment — necessarily observes the
/// state the ringer had already published. The cost is one uncontended atomic
/// RMW on paths (`mutex-unlock!`, `condition-variable-signal!`) that already
/// perform several atomic stores and a hash lookup.
///
/// Rings *under* the lock too, unlike `shared_channel.ring`'s
/// snapshot-then-ring: the list is one entry per blocked OS thread (single
/// digits in any real program), `notify()` takes no lock of its own so there
/// is no lock-order hazard, and holding the lock is what keeps each entry
/// alive without a retain/release round trip per ring. The alternative —
/// snapshotting — would need an allocation on a path that must not fail.
pub fn wakeCrossThreadWaiters() void {
    memory.spinLock(&wait_registry_lock);
    defer memory.spinUnlock(&wait_registry_lock);
    for (wait_registry.items) |e| e.notifier.notify();
}

/// Test/leak-check hook, mirroring `notifierLiveCount`: every enrolment must
/// be withdrawn, so this is 0 between waits.
pub fn crossThreadWaiterCount() usize {
    return wait_registry_len.load(.acquire);
}

/// Per-watched-process bookkeeping (KEP-0022 Phase 2). Mirrors `Reg`:
/// `waiters` holds every fiber parked in `process-wait` on this child, all
/// woken at once on exit readiness (the same wake-all discipline as fd
/// waiters — a stale entry for a since-terminated fiber is a no-op at wake).
/// A registration exists only while at least one fiber is parked on the
/// process ("armed ⇔ a waiter is parked", the fd ONESHOT discipline) —
/// `removeProcessWaiter` drops the whole registration when the last waiter
/// withdraws, so zombie discipline for never-waited processes stays with the
/// Phase-1 WNOHANG sweeps rather than this table pinning the Process alive.
const ProcReg = struct {
    proc: *types.Process,
    waiters: std.ArrayList(*Fiber) = .empty,
};

pub const Reactor = struct {
    allocator: std.mem.Allocator,
    backend: Backend,
    regs: std.AutoHashMap(i32, Reg),
    /// Child processes watched for exit readiness (KEP-0022 Phase 2), keyed
    /// by the backend's own handle: the pid on kqueue (EVFILT_PROC registers
    /// by pid), the pidfd on epoll (a real fd, so it can never collide with
    /// a `regs` key for a *different* descriptor). Empty on every target
    /// without process-watch support.
    procs: std.AutoHashMap(i32, ProcReg),
    timers: TimerHeap,
    notifier: *ThreadNotifier,

    pub fn init(allocator: std.mem.Allocator) !Reactor {
        // Notifier allocated *before* the backend, not after: on kqueue,
        // closing the backend's raw `kq` is now releaseNotifier's job alone
        // (KqueueBackend.deinit is a no-op -- see its doc comment), so an
        // `errdefer backend.deinit()` guarding a later notifier-allocation
        // failure would leak `kq` (and, on epoll, `notify_fd`) with nobody
        // left to close it. Ordering it first means a Backend.init failure
        // has nothing of ours to clean up (each backend's own init already
        // unwinds its own partial resources internally), and the notifier
        // errdefer below covers both failure points uniformly.
        const notifier = try std.heap.c_allocator.create(ThreadNotifier);
        errdefer std.heap.c_allocator.destroy(notifier);
        var backend = try Backend.init(allocator);
        notifier.* = .{ .backend = backend.notifierBackend() };
        _ = notifier_live_count.fetchAdd(1, .monotonic);
        return .{
            .allocator = allocator,
            .backend = backend,
            .regs = std.AutoHashMap(i32, Reg).init(allocator),
            .procs = std.AutoHashMap(i32, ProcReg).init(allocator),
            .timers = .empty,
            .notifier = notifier,
        };
    }

    pub fn deinit(self: *Reactor) void {
        var it = self.regs.valueIterator();
        while (it.next()) |reg| {
            reg.read_waiters.deinit(self.allocator);
            reg.write_waiters.deinit(self.allocator);
        }
        self.regs.deinit();
        // A registration surviving to reactor teardown (its fibers died with
        // the thread) still owns backend resources — on Linux, the pidfd.
        if (comptime supports_process_watch) {
            var pit = self.procs.iterator();
            while (pit.next()) |entry| {
                self.backend.disarmProc(entry.key_ptr.*);
                if (comptime builtin.os.tag == .linux) closePidfd(entry.value_ptr.proc);
                entry.value_ptr.waiters.deinit(self.allocator);
            }
        }
        self.procs.deinit();
        self.timers.deinit(self.allocator);
        // Order matters: flip `alive` before releasing, so a notify() that
        // wins a race against this release still observes `alive == false`
        // and skips the syscall instead of touching a resource this thread
        // is about to hand off (or close) via releaseNotifier below.
        self.notifier.alive.store(false, .release);
        releaseNotifier(self.notifier);
        self.backend.deinit();
    }

    /// KEP-0002 §5's `Reactor.notifyHandle()`. Exposes this thread's own
    /// cross-thread wakeup handle -- callers register it in a SharedChannel's
    /// waiter lists, never construct one themselves.
    pub fn notifyHandle(self: *Reactor) *ThreadNotifier {
        return self.notifier;
    }

    /// Registers `fiber` as waiting for `interest` on `fd`. On success the
    /// fd is armed with the OS (ONESHOT — resolved question 3: the
    /// registration exists only while a fiber is parked, by construction).
    /// The caller must have already flipped `fiber` to `.io_waiting`.
    pub fn register(self: *Reactor, fd: i32, interest: Interest, fiber: *Fiber) !void {
        const gop = try self.regs.getOrPut(fd);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        const reg = gop.value_ptr;

        // Every waiter already listed for this fd must still be parked: a
        // completed/errored/suspended fiber here means a close-port ran
        // without waking waiters and unregistering, and this fd number has
        // been recycled onto an unrelated port (resolved KEP-0001
        // question 4 — the assertion that keeps that invariant honest).
        if (comptime builtin.mode == .Debug) {
            for (reg.read_waiters.items) |f| std.debug.assert(f.status == .io_waiting);
            for (reg.write_waiters.items) |f| std.debug.assert(f.status == .io_waiting);
        }

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

    /// Removes `fiber` from `fd`'s waiter lists without waking it or
    /// disturbing other waiters. Cleanup for a wait that resolves outside
    /// the poll/close paths (an error unwinding waitForFd's scheduler
    /// drive) — those paths clear the lists themselves. A kernel ONESHOT
    /// left armed with no listed waiter fires once into the stale-event
    /// path of poll() and is dropped there; on epoll that stale fire still
    /// disarms the whole fd (not just the removed direction), so poll()
    /// re-arms for whatever the other direction still needs regardless of
    /// whether this event matched a live waiter (#1462). No-op if absent.
    pub fn removeWaiter(self: *Reactor, fd: i32, fiber: *Fiber) void {
        const reg = self.regs.getPtr(fd) orelse return;
        var lists = [_]*std.ArrayList(*Fiber){ &reg.read_waiters, &reg.write_waiters };
        for (&lists) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i] == fiber) {
                    _ = list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    /// The backend handle a process is registered under: the pid on kqueue,
    /// the pidfd on epoll (opened here on first use, stored in
    /// `proc.wait_handle`, closed when the registration is dropped — the
    /// pidfd's lifetime IS the registration's).
    fn procHandleFor(self: *Reactor, proc: *types.Process) !i32 {
        _ = self;
        if (comptime builtin.os.tag == .linux) {
            if (proc.wait_handle < 0) {
                // pidfd_open fds are O_CLOEXEC by construction (man page) —
                // no separate audit action needed. ESRCH means the child was
                // already reaped (by a WNOHANG sweep); ENOSYS means a
                // pre-5.3 kernel. Both surface as a registration failure the
                // caller degrades from (blocking fallback / immediate reap).
                const rc = linux.pidfd_open(proc.pid, 0);
                if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
                proc.wait_handle = @intCast(rc);
            }
            return proc.wait_handle;
        }
        return proc.pid;
    }

    fn closePidfd(proc: *types.Process) void {
        if (proc.wait_handle >= 0) {
            _ = platform.close(proc.wait_handle);
            proc.wait_handle = -1;
        }
    }

    /// Registers `fiber` as parked in `process-wait` on `proc` (KEP-0022
    /// Phase 2), arming the backend's exit watch (kqueue EVFILT_PROC +
    /// NOTE_EXIT; epoll on a pidfd) on the first waiter. Idempotent per
    /// (proc, fiber): a yield-retry re-park finds its own entry and returns.
    ///
    /// Failure leaves no registration behind (the caller's unpark cleanup
    /// need not know how far this got). An arm failure usually means the
    /// child already exited: an EVFILT_PROC EV_ADD on a reaped pid is ESRCH,
    /// and pidfd_open on one likewise — the caller closes that race with a
    /// WNOHANG reap either way, since an exit *before* the arm posts no
    /// event and would otherwise strand the waiter forever.
    pub fn registerProcess(self: *Reactor, proc: *types.Process, fiber: *Fiber) !void {
        if (comptime !supports_process_watch) return error.Unexpected;
        const handle = try self.procHandleFor(proc);
        const gop = try self.procs.getOrPut(handle);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .proc = proc };
            self.backend.armProc(handle) catch |err| {
                _ = self.procs.remove(handle);
                if (comptime builtin.os.tag == .linux) closePidfd(proc);
                return err;
            };
        }
        const reg = gop.value_ptr;
        for (reg.waiters.items) |f| {
            if (f == fiber) return; // re-park of the same waiter
        }
        reg.waiters.append(self.allocator, fiber) catch |err| {
            if (reg.waiters.items.len == 0) self.dropProcReg(handle);
            return err;
        };
    }

    /// Withdraws `fiber` from `proc`'s waiter list — the cleanup half for a
    /// wait that resolves outside the exit event (a timeout, an error
    /// unwinding the park). Dropping the last waiter drops the whole
    /// registration, keeping "armed ⇔ a waiter is parked" true by
    /// construction. No-op if not registered.
    pub fn removeProcessWaiter(self: *Reactor, proc: *types.Process, fiber: *Fiber) void {
        if (comptime !supports_process_watch) return;
        const handle = self.findProcHandle(proc) orelse return;
        const reg = self.procs.getPtr(handle) orelse return;
        var i: usize = 0;
        while (i < reg.waiters.items.len) {
            if (reg.waiters.items[i] == fiber) {
                _ = reg.waiters.swapRemove(i);
            } else {
                i += 1;
            }
        }
        if (reg.waiters.items.len == 0) self.dropProcReg(handle);
    }

    /// Drops `proc`'s registration entirely and hands back its parked
    /// waiters for the caller to wake (ownership of the list transfers; the
    /// caller deinits it with this reactor's allocator). For reap paths
    /// outside the reactor — `process-status`'s targeted reap and the
    /// WNOHANG sweeps — which store the status themselves and must then
    /// wake any parked waiters exactly as the exit event would have.
    /// Returns an empty list when `proc` was not registered.
    pub fn cancelProcessWatch(self: *Reactor, proc: *types.Process) std.ArrayList(*Fiber) {
        if (comptime !supports_process_watch) return .empty;
        const handle = self.findProcHandle(proc) orelse return .empty;
        const kv = self.procs.fetchRemove(handle) orelse return .empty;
        self.backend.disarmProc(handle);
        if (comptime builtin.os.tag == .linux) closePidfd(proc);
        return kv.value.waiters;
    }

    fn findProcHandle(self: *Reactor, proc: *types.Process) ?i32 {
        const handle: i32 = if (comptime builtin.os.tag == .linux) proc.wait_handle else proc.pid;
        if (handle < 0) return null;
        const reg = self.procs.getPtr(handle) orelse return null;
        // Defensive on kqueue, where the key is a pid the OS can recycle:
        // never treat another Process's registration as ours.
        if (reg.proc != proc) return null;
        return handle;
    }

    fn dropProcReg(self: *Reactor, handle: i32) void {
        const kv = self.procs.fetchRemove(handle) orelse return;
        self.backend.disarmProc(handle);
        if (comptime builtin.os.tag == .linux) closePidfd(kv.value.proc);
        var waiters = kv.value.waiters;
        waiters.deinit(self.allocator);
    }

    /// One child-exit readiness event (KEP-0022 Phase 2): reap at the
    /// reactor, exactly once — `waitpid(pid, WNOHANG)`, store the raw status
    /// word, drop the child from the heap's unreaped registry — then wake
    /// every parked waiter and drop the registration. No SIGCHLD handler
    /// exists anywhere, so children spawned by C FFI libraries are
    /// unobserved and unaffected; the kernel object watched here is only
    /// ever one of our own children.
    fn handleProcessEvent(self: *Reactor, handle: i32, ready: *std.ArrayList(*Fiber)) !void {
        const reg = self.procs.getPtr(handle) orelse return; // stale event
        const proc = reg.proc;
        // Reserved before the reap: an OOM after the status is stored (or
        // after the kernel's ONESHOT event is consumed) but before the
        // waiters reach `ready` would strand them forever — the same
        // consumed-but-undelivered invariant the fd path guards above.
        try ready.ensureUnusedCapacity(self.allocator, reg.waiters.items.len);
        if (proc.status == null) {
            var st: c_int = 0;
            const r = platform.waitPid(proc.pid, &st, platform.WNOHANG);
            if (r == proc.pid) {
                proc.status = @bitCast(st);
                if (memory.gc_instance) |gc| {
                    for (gc.unreaped_processes.items, 0..) |p, i| {
                        if (p == proc) {
                            _ = gc.unreaped_processes.swapRemove(i);
                            break;
                        }
                    }
                }
            } else if (r == 0) {
                // Not reapable yet (an early/spurious notification — not
                // observed on any backend, but NOTE_EXIT's delivery point is
                // the kernel's business): re-arm and keep everyone parked.
                // If even the re-arm fails, fall through and wake — the
                // waiters' retry re-registers or reaps for itself, which
                // beats stranding them on a dead watch.
                rearm: {
                    self.backend.armProc(handle) catch break :rearm;
                    return;
                }
            }
            // r < 0 (ECHILD: something outside Kaappi reaped our child):
            // wake the waiters; their retry surfaces the waitpid error.
        }
        for (reg.waiters.items) |f| ready.appendAssumeCapacity(f);
        self.dropProcReg(handle);
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
        // A watched process always has at least one parked waiter (the
        // registration is dropped with its last waiter), and its exit is a
        // wakeup the kernel will deliver — never a deadlock.
        if (self.procs.count() != 0) return false;
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
            for (reg.read_waiters.items) |f| gc.markValue(types.makePointer(&f.header));
            for (reg.write_waiters.items) |f| gc.markValue(types.makePointer(&f.header));
        }
        for (self.timers.items) |entry| gc.markValue(types.makePointer(&entry.fiber.header));
        // KEP-0022 Phase 2: a watched Process and its parked waiters must
        // survive collection for as long as the registration exists — the
        // exit event dereferences both.
        var pit = self.procs.valueIterator();
        while (pit.next()) |preg| {
            gc.markValue(types.makePointer(&preg.proc.header));
            for (preg.waiters.items) |f| gc.markValue(types.makePointer(&f.header));
        }
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
            // Child-exit readiness (KEP-0022 Phase 2). On kqueue the backend
            // flags EVFILT_PROC events explicitly (their ident is a pid, not
            // an fd); on epoll an exit is ordinary readability of the pidfd,
            // routed here by registry lookup — a pidfd is a real descriptor,
            // so a `procs` hit can never be some other port's fd.
            if (comptime supports_process_watch) {
                const is_proc_event = if (comptime is_kqueue_os)
                    ev.proc
                else
                    self.procs.count() != 0 and self.procs.contains(ev.fd);
                if (is_proc_event) {
                    try self.handleProcessEvent(ev.fd, ready);
                    continue;
                }
            }
            const reg = self.regs.getPtr(ev.fd) orelse continue; // stale event; already unregistered

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
            }
            if (ev.writable and reg.write_waiters.items.len > 0) {
                for (reg.write_waiters.items) |f| ready.appendAssumeCapacity(f);
                reg.write_waiters.clearRetainingCapacity();
            }

            // epoll's ONESHOT disarms the *whole* fd registration on any
            // fire — including a "stale" fire whose direction has no live
            // waiter (e.g. removeWaiter already dropped it) — unlike
            // kqueue, where read/write are independent knotes and an
            // untouched filter stays armed. Re-arm unconditionally for
            // whatever waiters remain, even when this event matched none:
            // gating the re-arm on `fired` left a stale fire's untouched
            // direction disarmed in the kernel with its waiter still
            // parked and still listed, so no deadlock detector would catch
            // it either (#1462). Harmless no-op redundant EV_ADD on kqueue.
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
            // Append before popping: if the append allocation fails, the
            // timer must stay in the heap so the fiber isn't stranded —
            // popping first would drop it from both places on OOM.
            try ready.append(self.allocator, top.fiber);
            _ = self.timers.pop();
        }
    }

    fn effectiveTimeout(self: *Reactor, cap_ns: ?u64) ?u64 {
        var result = cap_ns;
        if (self.timers.peek()) |top| {
            const now = fiber_mod.clockNs();
            const until: u64 = if (top.deadline_ns <= now) 0 else top.deadline_ns - now;
            result = if (result) |r| @min(r, until) else until;
        }
        // Clamp, because a "never" deadline is a real, reachable one: SRFI-18
        // reads `+inf.0` as "never times out" and `saturatedNsFromSeconds`
        // turns it into `maxInt(u64)` nanoseconds, ~585 years out. Handed to
        // kevent as a timespec that far in the future, macOS rejects the call
        // outright (EINVAL) -- `wait` returns error.Unexpected and the park
        // surfaces as KP9002 "out of memory" instead of blocking, which is
        // what `(thread-sleep! 1e18)` did before kaappi#2395 and what
        // `(thread-join! t +inf.0)` started doing once its wait became a real
        // reactor park rather than a nanosleep loop. A day is far longer than
        // any wait that matters and is safely inside every backend's range
        // (epoll's own msFromNs cap is 24.8 days, Windows' DWORD ms is 49
        // days); the cost of a genuinely unbounded wait is one spurious
        // wakeup per day, which every caller already re-loops through.
        if (result) |r| return @min(r, MAX_POLL_WAIT_NS);
        return result;
    }
};

// ---------------------------------------------------------------------------
// kqueue backend (macOS/Apple platforms, FreeBSD, OpenBSD, NetBSD)
// ---------------------------------------------------------------------------

const KqueueBackend = struct {
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
    fn init(_: std.mem.Allocator) !KqueueBackend {
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

    fn notifierBackend(self: *const KqueueBackend) NotifierBackend {
        return .{ .kq = self.kq };
    }

    /// No-op: `kq` is shared with the notifier's EVFILT.USER registration
    /// (KEP-0002 §5), so exactly one place may ever close it -- concentrated
    /// entirely in releaseNotifier's zero-transition (reactor.zig top-level)
    /// instead of here, to avoid a double-close race on whichever release
    /// happens last. raw/ready are inline arrays, owning nothing else.
    fn deinit(self: *KqueueBackend) void {
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

    /// Child-exit watch (KEP-0022 Phase 2): one EVFILT_PROC + NOTE_EXIT
    /// knote, registered by pid alongside the fd knotes on the same kq.
    /// ONESHOT for the "armed ⇔ a waiter is parked" discipline the fd path
    /// uses; the kernel auto-deletes a PROC knote when its process is
    /// reaped anyway. EV_ADD on an already-exited-and-reaped pid fails
    /// ESRCH — surfaced as an error the registration caller closes with a
    /// WNOHANG reap.
    fn armProc(self: *KqueueBackend, pid: i32) !void {
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

    fn disarmProc(self: *KqueueBackend, pid: i32) void {
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
        const rc = kevent_sys(self.kq, changes.ptr, @intCast(changes.len), self.raw[0..0].ptr, 0, &zero_ts);
        if (rc < 0) return error.Unexpected;
    }

    fn wait(self: *KqueueBackend, timeout_ns: ?u64) ![]const ReadyEvent {
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

const EpollBackend = struct {
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

    fn init(_: std.mem.Allocator) !EpollBackend {
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

    fn notifierBackend(self: *const EpollBackend) NotifierBackend {
        return .{ .fd = self.notify_fd };
    }

    fn deinit(self: *EpollBackend) void {
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
    fn arm(self: *EpollBackend, fd: i32, wants_read: bool, wants_write: bool, first_time: bool) !void {
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

    fn disarmAll(self: *EpollBackend, fd: i32) void {
        _ = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_DEL, fd, null);
    }

    /// Child-exit watch (KEP-0022 Phase 2): the pidfd becomes readable when
    /// the child exits, so it registers like any fd — ONESHOT, read
    /// interest. The EEXIST retry mirrors `arm`'s: a re-registration after
    /// a fired ONESHOT is a MOD, not an ADD.
    fn armProc(self: *EpollBackend, pidfd: i32) !void {
        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN | linux.EPOLL.ONESHOT, .data = .{ .fd = pidfd } };
        var rc = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_ADD, pidfd, &ev);
        if (linux.errno(rc) == .EXIST) {
            rc = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_MOD, pidfd, &ev);
        }
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
    }

    fn disarmProc(self: *EpollBackend, pidfd: i32) void {
        _ = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_DEL, pidfd, null);
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

const WasiPollBackend = struct {
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

    fn init(allocator: std.mem.Allocator) !WasiPollBackend {
        return .{ .allocator = allocator };
    }

    /// No real OS threads exist on WASI (thread-start! is already
    /// is_wasm-gated before reaching any KEP-0002 code) -- nothing for
    /// notify() to ring.
    fn notifierBackend(_: *const WasiPollBackend) NotifierBackend {
        return .{};
    }

    fn deinit(self: *WasiPollBackend) void {
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
    fn arm(self: *WasiPollBackend, fd: i32, wants_read: bool, wants_write: bool, _: bool) !void {
        if (!wants_read and !wants_write) {
            _ = self.interests.swapRemove(fd);
            return;
        }
        try self.interests.put(self.allocator, fd, .{ .read = wants_read, .write = wants_write });
    }

    fn disarmAll(self: *WasiPollBackend, fd: i32) void {
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

    fn wait(self: *WasiPollBackend, timeout_ns: ?u64) ![]const ReadyEvent {
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

const WindowsEventBackend = struct {
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

    fn init(allocator: std.mem.Allocator) !WindowsEventBackend {
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

    fn notifierBackend(self: *const WindowsEventBackend) NotifierBackend {
        return .{ .event = self.event };
    }

    fn deinit(self: *WindowsEventBackend) void {
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
    fn arm(self: *WindowsEventBackend, fd: i32, wants_read: bool, wants_write: bool, _: bool) !void {
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

    fn disarmAll(self: *WindowsEventBackend, fd: i32) void {
        if (self.sockets.fetchRemove(fd)) |kv| {
            // Best-effort cancel; errors (the socket may already be gone)
            // are irrelevant since the registry entry is dropped either way.
            _ = platform.win.WSAEventSelect(kv.value.sock, null, 0);
        }
        // Pipes have no kernel arming to cancel — dropping the entry is
        // the whole disarm.
        _ = self.pipes.remove(fd);
    }

    fn wait(self: *WindowsEventBackend, timeout_ns: ?u64) ![]const ReadyEvent {
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
