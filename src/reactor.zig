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
const types_process = @import("types_process.zig");
const Fiber = fiber_mod.Fiber;

const linux = std.os.linux;

/// Upper bound on a single blocking poll (see `Reactor.effectiveTimeout`).
const MAX_POLL_WAIT_NS: u64 = 24 * 60 * 60 * std.time.ns_per_s;

pub const Interest = enum { read, write };

/// A backend-normalized readiness result: which directions fired for `fd`.
/// `proc` marks a child-exit event (KEP-0022 Phase 2): on kqueue, `fd` is
/// then a *pid* (EVFILT_PROC shares no namespace with fds, so the flag is
/// what keeps a pid from ever being read as a same-numbered descriptor); on
/// epoll a child exit arrives as ordinary readability of the pidfd and the
/// Reactor routes it by registry lookup instead, so the flag stays false.
pub const ReadyEvent = struct { fd: i32, readable: bool, writable: bool, proc: bool = false };

/// Whether this target's backend can watch a child process for exit
/// readiness: kqueue's EVFILT_PROC, Linux's pidfd_open(2) registered with
/// epoll (KEP-0022 Phase 2), or the child's process HANDLE in the Windows
/// backend's wait set (Phase 3). WASI has no spawn at all.
pub const supports_process_watch = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd, .linux, .windows => true,
    else => false,
};

const is_kqueue_os = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd => true,
    else => false,
};

/// Whether a child-exit event arrives with `ReadyEvent.proc` set, rather
/// than as ordinary readability the Reactor has to route by registry lookup.
/// True wherever the registration key shares a namespace with fd numbers —
/// kqueue keys by pid, the Windows backend keys by process id — because a
/// registry lookup alone could then mistake a same-numbered port fd for a
/// child exit. epoll's key is a pidfd, a real descriptor, so it is safe to
/// route by lookup there.
const proc_events_are_flagged = is_kqueue_os or builtin.os.tag == .windows;

// The OS backends live in reactor_backends.zig (split along the
// dispatch-versus-backend seam; file size policy). `msFromNs` is re-exported
// below so external references (tests_reactor_parity) are unchanged.
const backends = @import("reactor_backends.zig");
const kevent_sys = backends.kevent_sys;
pub const msFromNs = backends.msFromNs;

const Backend = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd => backends.KqueueBackend,
    .linux => backends.EpollBackend,
    .wasi => backends.WasiPollBackend,
    .windows => backends.WindowsEventBackend,
    else => @compileError("reactor: unsupported OS (kqueue/epoll/wasi/windows only)"),
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
pub const NotifierBackend = switch (builtin.os.tag) {
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

    /// The backend handle a process is registered under: the pid on kqueue
    /// and Windows, the pidfd on epoll (opened here on first use, stored in
    /// `proc.wait_handle`, closed when the registration is dropped — the
    /// pidfd's lifetime IS the registration's). The Windows process HANDLE
    /// is deliberately *not* the key: it belongs to the Process for its whole
    /// lifetime, not to a registration, so the backend is handed it
    /// separately (`armProcWatch`) and never owns it.
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

    /// Arm the backend's exit watch for `handle`. Windows needs the process
    /// HANDLE as well as the key — it has no kernel registry keyed by pid —
    /// and borrows it: the Process still owns and closes it.
    fn armProcWatch(self: *Reactor, handle: i32, proc: *types.Process) !void {
        if (comptime builtin.os.tag == .windows) {
            return self.backend.armProcHandle(handle, proc.win_handle orelse return error.Unexpected);
        }
        return self.backend.armProc(handle);
    }

    /// Registers `fiber` as parked in `process-wait` on `proc` (KEP-0022
    /// Phase 2/3), arming the backend's exit watch (kqueue EVFILT_PROC +
    /// NOTE_EXIT; epoll on a pidfd; the process HANDLE in the Windows wait
    /// set) on the first waiter. Idempotent per (proc, fiber): a yield-retry
    /// re-park finds its own entry and returns.
    ///
    /// Failure leaves no registration behind (the caller's unpark cleanup
    /// need not know how far this got). An arm failure usually means the
    /// child already exited: an EVFILT_PROC EV_ADD on a reaped pid is ESRCH,
    /// and pidfd_open on one likewise — the caller closes that race with a
    /// non-blocking reap either way, since an exit *before* the arm posts no
    /// event and would otherwise strand the waiter forever. (Windows cannot
    /// fail this way: its wait object is a handle the Process already holds,
    /// signaled from the moment the child exits, so an exit before the arm
    /// is reported by the very first sweep.)
    pub fn registerProcess(self: *Reactor, proc: *types.Process, fiber: *Fiber) !void {
        if (comptime !supports_process_watch) return error.Unexpected;
        const handle = try self.procHandleFor(proc);
        const gop = try self.procs.getOrPut(handle);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .proc = proc };
            self.armProcWatch(handle, proc) catch |err| {
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
    /// reactor, exactly once — the shared `types_process.reapNonBlocking`
    /// (WNOHANG waitpid, or GetExitCodeProcess on a signaled handle), store
    /// the status, drop the child from the heap's unreaped registry — then wake
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
            const outcome = types_process.reapNonBlocking(proc);
            if (outcome == .reaped) {
                if (memory.gc_instance) |gc| {
                    for (gc.unreaped_processes.items, 0..) |p, i| {
                        if (p == proc) {
                            _ = gc.unreaped_processes.swapRemove(i);
                            break;
                        }
                    }
                }
            } else if (outcome == .running) {
                // Not reapable yet (an early/spurious notification — not
                // observed on any backend, but NOTE_EXIT's delivery point is
                // the kernel's business): re-arm and keep everyone parked.
                // If even the re-arm fails, fall through and wake — the
                // waiters' retry re-registers or reaps for itself, which
                // beats stranding them on a dead watch.
                rearm: {
                    self.armProcWatch(handle, proc) catch break :rearm;
                    return;
                }
            }
            // `.failed` (ECHILD: something outside Kaappi reaped our child,
            // or a dead handle): wake the waiters; their retry surfaces the
            // error.
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
            // Child-exit readiness (KEP-0022 Phase 2/3). kqueue and Windows
            // flag these events explicitly (their key is a pid, not an fd —
            // see proc_events_are_flagged); on epoll an exit is ordinary
            // readability of the pidfd, routed here by registry lookup, and a
            // pidfd is a real descriptor so a `procs` hit can never be some
            // other port's fd.
            if (comptime supports_process_watch) {
                const is_proc_event = if (comptime proc_events_are_flagged)
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
