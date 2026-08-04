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
