# Subprocesses — `(kaappi process)`

KEP-0022. A spawn-only subprocess API: no `fork`, no pre-exec hook, argv
never a shell string, child-exit reaped by the reactor rather than by a
`SIGCHLD` handler. Four phases shipped it — POSIX spawn and pipe ports
(kaappi#2414), reactor child-exit readiness (kaappi#2415), the Windows
backend (kaappi#2416), and the one-shot `run-process` layer with its
`process-timeout` condition (kaappi#2417).

This document is the map. `docs/dev/fibers-and-reactor.md` owns the reactor
itself, `docs/dev/windows.md` the Win32 particulars, and
`docs/dev/gc-safety-and-error-handling.md` the rooting rules every allocation
here obeys.

## Where the code lives

| File | Owns |
|------|------|
| `src/types_process.zig` | The `Process` heap type, the status domain (`decodeStatus`), and the one non-blocking reap every layer shares |
| `src/primitives_process.zig` | Everything platform-independent: option parsing, redirection validation, the zombie sweeps, the fiber park, the `run-process` Scheme source |
| `src/process_posix.zig` | `posix_spawnp`, file actions, process groups, `waitpid`/pidfd |
| `src/process_win.zig` | `CreateProcessW`, the explicit inherit list, Job Objects, `GetExitCodeProcess` |
| `src/reactor.zig` | `registerProcess`/`cancelProcessWatch`: kqueue `EVFILT_PROC`, Linux `pidfd_open` + epoll, a Windows process HANDLE in the polled set |
| `src/vm_bootstrap.zig` | Installs `run-process`'s Scheme body over its stub |

The seam between the two backends is three types in `types_process.zig`
(`Redir`, `SpawnConfig`, `Spawned`) plus a small function set each backend
exports. Exactly one of the two files is ever imported, so neither
platform's raw syscall surface is analyzed on the other.

## The Scheme surface

| Procedure | Notes |
|---|---|
| `(spawn-process argv opt…)` | `stdin:`/`stdout:`/`stderr:`, `directory:`, `env:`, `new-group:` |
| `(process? x)` `(process-pid p)` `(process-group p)` | `process-group` is `#f` unless `new-group: #t` |
| `(process-stdin p)` `(process-stdout p)` `(process-stderr p)` | the pipe port for a `'pipe` spec; `#f` for every other spec |
| `(process-status p)` | `#f` while running; exit code; `(signaled . n)` |
| `(process-wait p ['timeout: s])` | parks the fiber; `#f` on expiry with the child still alive |
| `(process-kill p ['signal: n] ['group: bool])` | SIGTERM default; a quiet no-op after the reap |
| `(process-environment)` | the current environment as the `(name . value)` alist `env:` takes |
| `(run-process argv opt…)` | one-shot: `(values status out err)` |
| `(process-timeout? c)` `(process-timeout-stdout c)` `(process-timeout-stderr c)` | the condition `run-process`'s `timeout:` raises |

Redirection specs are `'inherit` (the default), `'pipe`, `'null`, an
fd-backed port, and — for `stderr:` only — `'stdout`, which merges the two
streams onto one pipe.

There is no `kaappi-process` `cond-expand` feature identifier. Portable code
gates on the library instead, which `cond-expand` already supports:

```scheme
(cond-expand ((library (kaappi process)) (import (kaappi process))) (else …))
```

The gate answers false in exactly two places, and for two different reasons:
on WASM, because `primitives.all_specs` omits the whole module (WASI has no
process creation); and under `--sandbox`, because every spec is
`.sandbox = false`.

## Spawn

`posix_spawnp` on POSIX, `CreateProcessW` on Windows. No `fork` anywhere:
Kaappi has SRFI-18 OS threads, a reactor holding live kernel objects, and a
Windows tier, and each of the three rules `fork` out on its own. There is no
pre-exec hook either — Python kept `preexec_fn` for compatibility and has
spent a decade regretting it — so every knob between spawn and exec is a
named option.

Descriptors are closed by default, with no allowlist: a child inherits
exactly slots 0, 1 and 2. That is what keeps the reactor's kqueue/epoll fd,
a listening socket, or another library's database connection out of the
child. `tests_process.zig` asserts it by spawning `sh -c 'ls /dev/fd'`.

Two rejections in `parseRedir` are worth knowing before you pass a port as a
redirection:

- **A port the fiber scheduler has already flipped non-blocking is
  refused.** The child's slot would share the open file description,
  O_NONBLOCK included, and the parent's next I/O would re-flip it even if it
  were cleared at spawn.
- **Buffered read-ahead is rewound first, buffered output drained second.**
  The order matters on a bidirectional port: draining output before the
  rewind would land the parent's buffered writes at the stale read-ahead
  offset instead of the logical one. An unseekable fd with pending read-ahead
  is rejected rather than silently skipped past.

`SIGPIPE` is set to `SIG_IGN` process-wide at `VM.init` and reset to its
default in the child — an ignored disposition survives `exec`, so a child
would otherwise inherit the runtime's policy rather than the shell's.

## Waiting and reaping

`process-wait` parks the calling fiber on the reactor's child-exit
readiness; siblings keep running. Reaping happens exactly once, at the
reactor, so there is no `SIGCHLD` handler, no race with children spawned by
a C FFI library, and no interference between threads. asyncio shipped
signal-based child watchers, hit every failure mode, and deprecated the
whole subsystem in 3.12 — this is the design that survived.

The park has three tiers, in order of preference:

1. **Registered.** kqueue `EVFILT_PROC`, Linux `pidfd_open` + epoll, or a
   Windows process HANDLE in the polled set.
2. **Polled.** The kernel cannot watch this child — `pidfd_open` is `ENOSYS`
   before Linux 5.3 and under Rosetta's syscall translation — so a
   `WNOHANG` reap runs at a 20 ms cadence with the fiber parked on the timer
   heap between probes. Siblings still run, which is the guarantee the
   blocking fallback cannot give.
3. **Blocking.** No scheduler and no timeout: the plain `waitpid` /
   `WaitForSingleObject`, the same degradation port reads already implement.

Everything is **status-first**: a stored status outranks a fired timer, and
a woken retry consults `proc.status` rather than making a syscall of its
own. `timed_out` alone is never a verdict — the reactor's wake path flips it
for every `.waiting` fiber it reports, exit events included — so only a
deadline that has actually passed reports `#f`.

An exit that beats the registration posts no kernel event, ever. The single
`tryReapOne` probe immediately after arming is what closes that window.

**Zombies.** The reactor reaps on exit regardless of waiters, and a parent
that exits leaves its zombies to `init`. The real window is a long-running
parent whose owning thread never runs a scheduler tick yet keeps spawning:
`sweepUnreaped` runs at the top of the blocking spawn and wait paths for
exactly that case, and `gc_sweep.freeObject` is the last resort for a
Process collected while its child still runs.

## Thread affinity

A `Process` is owned by the scheduler of the thread that spawned it, and
every entry point except the `process?` predicate checks `Object.owner` —
the same total treatment channels and thread handles get. The irritant on
that condition is `#f`, never the foreign process: storing a foreign-heap
object in a condition the owner's GC may free would reopen the hazard the
check exists to close.

## `run-process`

The one-shot layer, and the only part of the subsystem written in Scheme:
the source is `primitives_process.run_process_src`, and
`vm_bootstrap.install` evaluates it over a `bootstrapStub`. It is Scheme
because it is fiber choreography end to end — a feeder fiber writes
`input:` while two drain fibers read stdout and stderr, all three running
*while* `process-wait` parks. A native frame cannot spawn and join fibers;
this is the same reason `map` and `for-each` live there.

That choreography is the whole point. Feeding a child's stdin and then
reading its stdout serially deadlocks the moment either side passes the
64 KiB pipe buffer — the bug Python's `communicate()` exists to work around
with threads and `select`. Fibers answer it directly.

```scheme
(call-with-values
    (lambda () (run-process '("git" "log" "--oneline" "-5") 'directory: repo))
  (lambda (status out err) …))
```

Options: `input:` (string or bytevector), `timeout:` (seconds), `output:`
(`'string`, the default, or `'bytevector`), `directory:`, `env:`,
`new-group:`.

Four behaviours that are decisions rather than accidents:

- **stdin is `'null` unless `input:` is given.** A one-shot capture that
  blocks on the terminal is the failure `'inherit` would produce; Go's
  `exec.Cmd` defaults the same way. stdout and stderr are always `'pipe`.
- **`timeout:` implies `new-group: #t`.** `process-kill` refuses `'group:`
  on a child sharing the parent's own group, and the group kill is also what
  lets the drain fibers reach EOF when a grandchild inherited the pipe. A
  caller who passes `new-group: #f` explicitly gets a child-only kill, and
  with it the risk that a surviving grandchild holds the drain open.
- **The timeout kill is SIGKILL.** A timeout is a bound; a child that
  ignores SIGTERM would turn it into a suggestion. Python's `run()` kills
  for the same reason.
- **A broken pipe on the feed is swallowed.** A child that exits without
  reading gives the write `EPIPE`; its verdict is the exit status, not a
  failure of the feed. Read errors on the *drains* are not swallowed — they
  are this call's failure and reach the caller.

`run-process` uses `call/cc` + `with-exception-handler` rather than `guard`
for those swallows. `guard`'s desugaring reaches `%unwind-to-escape`, which
`vm_bootstrap.install` purges from globals immediately after evaluating the
definition; the explicit escape has no macro underneath it.

## Errors

| Failure | Condition |
|---|---|
| Program not found, permission denied, any spawn syscall failure | the file-error family, with `posix_errno` set — `file-error?` and `posix-error?` both see it, and ENOENT vs. EACCES is what tells "not found" from "not allowed" apart |
| A bad option value or an unknown option | `primitives.argError` / `typeError`, as everywhere |
| `run-process` exceeded `timeout:` | `process-timeout?`, carrying partial output |

One platform gap, tracked as kaappi#2456: POSIX leaves it unspecified
whether a failed *PATH search* fails at `posix_spawnp` or lets the child
exec fail and exit 127, and OpenBSD takes the second option. So a bare
program name that resolves to nothing arrives there as a status, not a
condition. An argv head with a path is a spawn failure everywhere.

The timeout condition is an `ErrorObject` with `error_type = .process_timeout`
— the `channel_timeout` precedent. Its irritants are `(argv seconds)`; the
partial output rides `uncaught_reason` as a `(stdout . stderr)` pair, read
back by `process-timeout-stdout`/`-stderr`. Keeping the output off the
irritants list is deliberate: an uncaught timeout prints its irritants, and
a child that produced megabytes before stalling should not print them.

## Tests

| Layer | Where |
|---|---|
| POSIX unit tests | `src/tests_process.zig` — spawn/wait/status, the redirection matrix, fd hygiene, group kill, the Phase-2 park |
| `run-process` unit tests | `src/tests_process_run.zig` |
| Windows unit tests | `src/tests_process_win.zig` |
| Scheme, POSIX | `tests/scheme/process/process-test.scm`, `process-wait-test.scm` |
| Scheme, both platforms | `tests/scheme/process/process-portable.scm`, `process-run.scm` — kaappi itself as the child, the one program guaranteed present on a bare box of either kind |
| Native tier | `tests/scheme/compile/process-spawn-2414.sh` |

The native-tier script is not optional. Three regressions once passed as
`.scm` tests for years while the native tier failed them; `run-process` adds
a second reason, since a compiled binary runs `vm_bootstrap.install` from
`runtime_exports.zig` rather than from `main.zig`.

## Deliberately absent

Pseudo-terminals (`'pipe` covers the driving workload), `run-pipeline` /
scsh-style process notation, a `system`-style shell-string entry point
(injection; Chez is the cautionary precedent), and `pass-fds:`. A shell
helper or a pipeline combinator belongs in an ecosystem library under a name
that says shell.
