# Fibers and the I/O reactor (KEP-0001)

How a port read that would block suspends one fiber instead of the whole OS
thread, and what each platform's readiness backend can and cannot do.

For the *thread* model that sits above this (SRFI-18, one VM and GC per OS
thread), see `docs/dev/thread-value-sharing.md`.

## The reactor

Each OS thread's scheduler owns a `Reactor` (`src/reactor.zig`:
kqueue/epoll/WASI-`poll_oneoff`/Windows-`WSAEventSelect` backends plus a
userspace timer heap), created lazily with the scheduler by
`fiber.ensureScheduler`.

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

## Cross-thread wakes ride the notifier (kaappi#2395)

Each reactor's `ThreadNotifier` (KEP-0002 §5) is the only way another OS
thread can end this thread's blocking `poll()`. Originally only shared
channels used it; since kaappi#2395 (KEP-0002 unresolved question 3) every
cross-thread SRFI-18 wait does, and the old 1 ms polls are gone. The wake
edges, all in `src/reactor.zig` unless noted:

| Event | Who gets rung | Mechanism |
|-------|---------------|-----------|
| Channel send/receive/close | Threads registered in the `SharedChannel` waiter lists | `shared_channel.zig`'s snapshot-and-ring (unchanged) |
| `mutex-unlock!`, mutex abandonment, terminated-owner release | Threads registered on the mutex | `NotifierList` on `Mutex.cross_waiters` (an opaque slot, the `Channel.shared` precedent) |
| `condition-variable-signal!`/`-broadcast!` | Threads registered on the condvar | `NotifierList` on `ConditionVariable.cross_waiters`, rung right after the generation bump |
| `thread-terminate!` | The victim thread | `Fiber.os_notifier`, published by the child when its reactor is created (`fiber.ensureScheduler`), released at `reapOsThread` or the handle's sweep |
| An OS thread exiting | **Every** live reactor | `ringAllNotifiers()` over the process-wide registry every `Reactor.init` joins, called by `threadEntryFn`'s outermost defer after the `live_child_threads` decrement |

Waiter-side, `runSchedulerStep`'s wait contexts replace the old
`pollCapNs` cap with `externalWakePossible()` (re-evaluated at every park):
when true, `parkOnReactor` blocks on the notifier even with an empty reactor
instead of reporting deadlock. The SRFI-18 mutex/condvar waits register on
the object's `NotifierList` **before** their first state check and
deregister via `defer`; wakers change state **before** ringing. One of two
synchronization edges then always exists — the ring sees the registration
(and the OS-level wake persists until polled, so a ring that outruns the
park still ends it), or the registration's slot-CAS/list-lock reads-from the
ring's, making the state change visible to the waiter's re-check — the same
two-channel argument as KEP-0002 §5. `NotifierList`'s doc comment carries
the full protocol, including why the empty-slot probe is a no-op CAS rather
than a plain load.

The exit ring-all is also what keeps the deadlock verdicts sound: a wait
parked unbounded because `crossThreadWaitPossible()` was true re-runs that
verdict when the thread it was counting on exits, and either resolves,
re-parks, or raises the deadlock error — where the old code polled its way
to the same verdict. It wakes shared-channel waiters too (the sweep is
unconditional), which narrows KEP-0002 §5's accepted only-peer-exited
liveness gap to the cases where the channel's stub count still reports
another holder.

`thread-join!` on an OS thread now waits the same way: the timed path (and
the never-started-handle path) drive the scheduler via `OsJoinWait`, parked
until the child's exit ring or the deadline timer — dispatching runnable
sibling fibers, which the old `sleepNs(1 ms)` status loop starved (that
starvation was the never-started half of kaappi#2194: a sibling fiber's
`thread-start!` on the joined handle could never run). An untimed join of a
started thread still blocks directly in `thread.join()`, which was always
event-driven.

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
