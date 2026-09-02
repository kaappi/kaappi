# Fibers and the I/O reactor (KEP-0001)

How a port read that would block suspends one fiber instead of the whole OS
thread, and what each platform's readiness backend can and cannot do.

For the *thread* model that sits above this (SRFI-18, one VM and GC per OS
thread), see `docs/dev/thread-value-sharing.md`.

## The reactor

Each OS thread's scheduler owns a `Reactor` (`src/reactor.zig` — the
dispatch core, registries, and timer heap; the four OS backends —
kqueue/epoll/WASI-`poll_oneoff`/Windows-`WSAEventSelect` — live in
`src/reactor_backends.zig`, split along the dispatch-versus-backend seam),
created lazily with the scheduler by `fiber.ensureScheduler`.

The blocking-wait machinery — `waitForFd`, reactor parking (`parkOnReactor`),
and the shared in-place scheduler drive (`runSchedulerStep`) — lives in
`src/fiber_wait.zig`, re-exported through `fiber.zig`, so the `fiber.X` names
below are unchanged.

## Parking versus driving in place

Port reads and writes that would block (`EAGAIN`) suspend the calling fiber
instead of the thread (`fiber.waitForFd`):

- a fiber dispatched directly by a scheduler loop **parks** (`.io_waiting` plus
  the yield-retry re-execution protocol — callers stash partial progress into
  `port.read_buf` first, via `primitives_io.propagateReadErr`);
- the main fiber, or one under re-entrant native frames, **drives the scheduler
  in place** instead.

An in-place drive that goes idle while an *enclosing* drive's wait already
resolved or timed out (`FiberScheduler.driving_waits`) unwinds with a catchable
"port I/O abandoned" error rather than blocking unboundedly — the pinned
ancestor can only proceed once this fiber's native frames unwind (kaappi#1625).

`runSchedulerStep` is also where the custom-port callback check lives
(kaappi#2000): every in-place drive passes through it, so a blocking primitive
called from inside a SRFI 181 callback is rejected with a catchable error
instead of recursively driving the scheduler. See the SRFI 181 section of
`docs/dev/srfi-implementation-notes.md`.

## Cross-thread wakeups (kaappi#2395)

Each `Reactor` owns a `ThreadNotifier` (KEP-0002 §5) — a kqueue `EVFILT.USER`
trigger, an eventfd, or a Windows auto-reset event — that any other OS thread
may ring to interrupt this one's `reactor.poll`. Promoted channels ring it
through per-channel waiter lists (`src/shared_channel.zig`).

The SRFI-18 waits have no per-object waiter list to hang a notifier off: a
mutex or condition variable is an ordinary GC object reached through the
globals route (`docs/dev/thread-value-sharing.md`), with no cross-thread
bookkeeping of its own. So `src/reactor.zig` keeps a process-global registry
keyed by **thread**, not by object:

| | |
|---|---|
| enrol | `enrollCrossThreadWaiter` / `withdrawCrossThreadWaiter`, wrapped per wait by `fiber_wait.CrossThreadEnrolment` |
| ring | `wakeCrossThreadWaiters` — every enrolled thread, on any state change one of these waits could observe |
| who enrols | `thread-join!` on a running OS thread, `mutex-lock!`, a condition-variable wait, and `thread-sleep!` — **unconditionally**, never gated on whether another OS thread exists yet |
| who rings | `mutex-unlock!`, a mutex abandoned by a dying fiber or thread (`abandonFiberMutexes`), `condition-variable-signal!`/`-broadcast!`, `thread-terminate!`, and an OS thread's exit (`threadEntryFn`) |

A ring wakes *every* enrolled thread; each re-checks its own condition and
re-parks, so a spurious wake costs one loop iteration. Before kaappi#2395 all
of these waits instead re-checked their own state every millisecond
(`sleepNs(CROSS_THREAD_POLL_NS)` and the `pollCapNs` caps), which is why a
`(thread-sleep! 60)` on a child thread used to wake 60,000 times.

Five things load-bearing enough to be worth knowing before touching this:

- **Enrolment is unconditional, and must stay that way.** Gating it on
  `crossThreadWaitPossible()` at entry looks like an obvious saving and is a
  hole: `runSchedulerStep` evaluates `pollCapNs` once, before dispatching
  anything, and a timed wait's own deadline timer keeps the reactor non-empty
  — so a sibling fiber that the wait's own drive dispatches can start the
  process's *first* OS thread, whose unlock or signal then rings a registry
  the wait never joined. The park runs to its deadline and reports a timeout
  for a hand-off that happened (measured: `(mutex-lock! m 2)` returning `#f`
  at 2.002s for an unlock at 0.1s). The cost of enrolling always is that a
  purely local wait also holds a slot, so an unlock on the same thread rings
  its own notifier — one syscall, only while a fiber is actually parked.

- **An enrolment is deliberately invisible to `hasRunnableFibers`**, unlike a
  `shared_waiters` entry. A *timed* wait needs nothing there — its own
  deadline timer already keeps the reactor non-empty, so it parks inside
  `runSchedulerStep` with no cap and the ring is what ends it. An *untimed*
  one needs `parkOnReactor`'s "nothing local can happen" verdict to keep
  coming back, because that verdict is what returns control to the
  mutex/condvar retry loop, where `crossThreadWaitPossible()` decides between
  waiting longer and raising the deadlock diagnostic. That loop then blocks on
  the ring itself, via `fiber_wait.awaitCrossThreadRing` — the same poll
  `parkOnReactor` does, minus the empty-reactor refusal, bounded by
  `CROSS_THREAD_RING_WAIT_NS` (100 ms) so the liveness check still gets its
  turn. Counting enrolments in `hasRunnableFibers` instead turns that
  diagnostic into a hang.
- **`parkOnReactor` returns `true` as soon as it consumes a pending notify**,
  rather than going on to poll. Consuming the flag does not consume the OS
  trigger, so the poll normally returns at once anyway — except when the same
  tick's `reactor.poll(0)` (`runReactorTick`, taken whenever an fd is
  registered) already drained the trigger. That interleaving would otherwise
  block on an event already delivered.
- **`wakeCrossThreadWaiters` takes the registry lock even to find it empty.**
  An atomic length gate read outside the lock is a store-buffering pattern
  against the enroller — both sides can miss the other's store — and with no
  poll cap left as a backstop that is a hang, not a latency blip.
- **Every wait on another OS thread backs off to a sleep** —
  `platform.spinBackoff`: a short pure spin, then `sched_yield`, then
  `nanosleep` doubling from 32 µs to 1 ms — and that includes the registry
  lock itself (`memory.spinLock`), the stop-the-world handshake on both sides
  (`VM.stopForCollection`, `markLiveChildRoots`), the globals RW lock, and
  `thread-join!`'s wait for a detached OS thread's exit flag (`reapOsThread`,
  which replaced `pthread_join` — the joining LWP would otherwise inherit the
  dead thread's CPU-usage estimate on NetBSD). A
  pure spin only works while the thread being waited for is *running*; once
  the kernel preempts it, the spinners compete with it for CPU, and on a
  priority-decay scheduler they win outright. That was kaappi#2446: on
  NetBSD's 4BSD scheduler, 17 threads leaving `thread-sleep!` spun on the
  registry lock at priority 25–27 while the holder — preempted inside the
  `kevent` ring, at priority 0 after the work it had done — stayed runnable
  and never ran again. Yielding does not help (it requeues behind LWPs of the
  *same* priority); only a sleep takes the spinner off the run queue.
  Since kaappi#2470 the ring itself is issued *outside* the lock — the
  first 128 entries are snapshotted (retained) under it, then notified and
  released after it is dropped, so the critical section is bounded by the
  copy, not by one syscall per parked thread; entries past 128 are the
  overflow tail, still rung under the lock.

A "never" deadline is a real one and reaches the backends: SRFI-18 reads
`+inf.0` as "never times out", `saturatedNsFromSeconds` turns that into
`maxInt(u64)` nanoseconds, and a timespec ~585 years out is one `kevent`
rejects with `EINVAL` — surfacing as `KP9002: out of memory` rather than a
block. `Reactor.effectiveTimeout` therefore clamps any single blocking wait to
`MAX_POLL_WAIT_NS` (24 hours) and lets the caller re-loop. This was already
reachable before kaappi#2395 — `(thread-sleep! 1e18)` raised instead of
sleeping — and became unavoidable once `thread-join!`'s timed wait stopped
being a `nanosleep` loop.

The caps survive as a *degraded* path only: `enrollCrossThreadWaiter` returns
false if the registry cannot allocate, and each wait's `pollCapNs` then falls
back to the pre-kaappi#2395 1 ms cadence rather than parking on a ring that
will never come.

## Non-blocking mode is lazy, and is the platform probe

Port fds (never 0/1/2) flip to `O_NONBLOCK` lazily, only once a scheduler
exists — sequential programs keep blocking fds and their exact syscall profile.

**WASI.** The flip is the host-capability probe: `fd_fdstat_set_flags(NONBLOCK)`
failing (for example the playground's browser shim) leaves ports blocking, so
nothing ever registers an fd and the reactor degrades to CLOCK-only
`poll_oneoff` waits — timers and `thread-sleep!` always work. `thread-sleep!` is
the one SRFI-18 primitive registered on WASM, as a global; the `(srfi 18)`
library itself stays native-only.

**Windows.** The probe is `fdKind` (kaappi#1608):

| Port kind | Non-blocking | Readiness |
|-----------|--------------|-----------|
| socket-backed (CRT fd wrapping a SOCKET via `_open_osfhandle`) | real, via `FIONBIO`; read/write through `platform.sockRecv`/`sockSend` | `WSAEventSelect` in the reactor |
| pipe | *emulated* — no OS flip exists; `platform.pipeRead`/`pipeWrite`'s peek/write-quota pre-checks synthesize the `EAGAIN` | reactor re-polls the same checks on a 10 ms quantum, paid only while a pipe waiter exists |
| file | blocking | none — the POSIX baseline too; no OS has regular-file readiness |

`docs/dev/windows.md` explains why IOCP was rejected.

## Child-exit readiness (KEP-0022 Phases 2-3)

The reactor also watches spawned children (`(kaappi process)`) for exit:
kqueue registers an `EVFILT_PROC` + `NOTE_EXIT` knote by pid; epoll registers
a `pidfd_open(2)` descriptor for read-readiness (a pidfd becomes readable on
exit, and its lifetime *is* the registration's — opened in
`Reactor.registerProcess`, closed when the registration drops); Windows adds
the child's process HANDLE to `WaitForMultipleObjects`'s wait set (Phase 3,
kaappi#2416 — the handle is *borrowed*, since the `Process` owns it for its
whole lifetime, and the 64-object ceiling sends any surplus to the same 10 ms
quantum the pipe entries use). On the event, the reactor reaps —
`types_process.reapNonBlocking`, which is `waitpid(pid, WNOHANG)` on POSIX
and `GetExitCodeProcess` on a signaled handle on Windows; status into
`proc.status`; the child off `GC.unreaped_processes` — and wakes every parked
waiter at once. There is no SIGCHLD handler anywhere, so children spawned by
C FFI libraries are unobserved and unaffected.

The registration key shares a namespace with fd numbers on kqueue (a pid) and
on Windows (a process id), so both backends flag their exit events
explicitly (`ReadyEvent.proc`); only epoll, whose key is a real descriptor,
can be routed by registry lookup (`Reactor.proc_events_are_flagged`).

Four rules keep it honest:

- **"Armed ⇔ a waiter is parked"**, the fd ONESHOT discipline: the last
  waiter's withdrawal (`removeProcessWaiter`) drops the whole registration,
  so zombie discipline for never-waited children stays with the Phase-1
  sweeps rather than the registry pinning Processes alive.
  `Reactor.markRoots` traces registered Processes and their waiters.
- **Arm-then-probe closes the exit-before-arm race**: an exit that beats the
  arm posts no kernel event, ever (and the arm itself may refuse with ESRCH
  once the child is reapable) — so `process-wait` follows every registration
  with one WNOHANG probe. An exit before the arm is caught by the probe; one
  after it, by the event.
- **Status-first resolution everywhere**: a woken retry consults
  `proc.status`, never a `waitpid` of its own, and a stored status outranks a
  fired timeout timer (delivery-wins, the channel precedent). This is also
  what makes the wake-all discipline safe against spurious `timed_out` flags.
- **Reaps outside the reactor must wake too**: `process-status`'s targeted
  reap and the WNOHANG sweeps call `wakeProcessWaiters`
  (`Reactor.cancelProcessWatch`) so a parked waiter never depends on a kernel
  event whose registration was already dropped.

`process-wait` itself follows the standard park-versus-drive split above,
with `timeout:` riding the reactor timer heap (`#f` on expiry, child lives —
Python's contract). No scheduler and no timeout means the Phase-1 blocking
`waitpid` fallback; a wait from a non-owning SRFI-18 thread raises via the
`Object.owner` check like every other thread-affine handle.

When the kernel cannot watch a process at all — `pidfd_open` is ENOSYS
before Linux 5.3 and under Rosetta's x86_64 syscall translation (the podman
amd64 leg) — `process-wait` degrades to a *polled* park
(`primitives_process.polledWait`): a WNOHANG probe every 20 ms, parked on
the reactor timer heap between probes, driving in place for every caller.
Siblings keep running, which the blocking fallback cannot promise — a
program whose child exits only after a sibling acts would deadlock in a
blocking `waitpid`.

## Buffering and close

Ports on fd > 2 buffer writes in `port.write_buf` until `flush-output-port`,
`close-port`, a read on the same port, or the 8 KiB high-water mark.

`close-port` flushes, wakes fibers parked on the fd
(`fiber.wakeIoWaitersOnFd` — their retry sees `is_open == false` and raises
cleanly), and unregisters the fd from the reactor.

## The one rule when adding I/O

`readOneByte` and `portWriteBytes` in `src/primitives_io.zig` are the single
byte source and sink for every textual *and* binary port primitive. Hook new I/O
through them, not around them — the fiber parking, the custom-port and
transcoded-port branches, and `takeFirstBufferingRest`'s ordering guarantee all
live there.

## Benchmarks

`zig build bench-fibers` (per-fiber switch time, RSS, register/frame footprint)
and `zig build bench-reactor` (ONESHOT re-arm, wake-all, timer granularity) are
the KEP-0001 Phase 7 gates — see `docs/dev/kep-0001-phase7-benchmarks.md`.
