# NetBSD: `thread-join!` hangs — uncapped priority inheritance through `pthread_join`, amplified by pure spin locks

## Status

**Fixed** (2026-09-02, kaappi#2446), in two parts. (1) SRFI-18 OS threads
are detached at spawn and `thread-join!` waits on a per-spawn exit flag
instead of `pthread_join`, because on NetBSD the joining LWP absorbs a
reaped LWP's CPU-usage estimate with no cap and sinks, with every thread it
spawns afterwards, to the lowest user priority. (2) `platform.spinBackoff`
(spin, then yield, then sleep 32 µs doubling to 1 ms) replaces every pure
spin in a cross-thread wait: `memory.spinLock`, `VM.stopForCollection`,
`markLiveChildRoots`'s wait for children to stop, and `GlobalsRwLock`.
Regression tests in `tests_srfi18.zig`: "contenders on a held spin lock
sleep instead of burning CPU" and "thread-join! returns only after the
child's whole epilogue". Measurements on the NetBSD 10.1 aarch64 reference
VM under 4-CPU load are in "The fix" below.

## Symptom

`tests/scheme/srfi/srfi18-join-spawn-grandchild-2129.scm` — sub-second when
it passes — intermittently ran until killed on NetBSD 10.1 aarch64, and once
in the x86_64 `netbsd-test` CI job. Never on macOS, Linux, FreeBSD or
OpenBSD. The rate was load-sensitive: 0/10 on an idle box, 5–9 out of 10
with four CPU-burner shells running alongside.

## The wrong diagnosis, and why it was convincing

The first investigation attached gdb to hung processes and found a child
LWP whose PC never moved — parked at `pthread__create_tramp+0`, or frozen
mid-`threadEntryFn` with no syscall in progress — while the joiner sat in
`pthread_join`. Instrumentation showed every other thread's lifecycle
completing cleanly. The conclusion was that NetBSD (or the UTM/aarch64
virtualization layer) strands a freshly created LWP and never schedules it
again: an OS defect, `blocked-upstream`, with three kaappi-side mitigations
(a spawn-start handshake with retry, ringing waiters outside the registry
lock, a self-pipe notifier) that halved the rate but could not reach zero.

Every observation in that account was real. The inference was wrong because
gdb shows only the *userspace* view: a thread that is runnable but never
scheduled and a thread the OS has lost look identical from there — frozen
PC, no syscall. What gdb cannot show is *why* the kernel isn't running it.

## What the kernel-side view showed

`ps -s` lists every LWP with its scheduler state, wait channel, CPU and
priority. Two samples five seconds apart on a hung process:

```text
 PID   LID STAT WCHAN   CPUID PRI    TIME %CPU
3808 13115 R    -           0  26 2:04.32  290
3808 28593 S    nanoslp     1  64 2:04.32  290
3808 26365 I    lwpwait     0  64 2:04.32  290
3808 12010 O    -           2  25 2:04.32  290
3808 20262 R    -           0   0 2:04.32  290
3808 18430 R    -           0   0 2:04.32  290     <- kevent, holds the lock
3808  3455 R    -           0  26 2:04.32  290
   ... 13 more R/O LWPs at PRI 25-27 ...
3808  3808 I    lwpwait     2  85 2:04.32  290
--- +5s ---                                2:20.20  291
```

Not one stranded thread: **23 LWPs, 18 of them runnable, the process
burning three CPUs' worth of time every five seconds**. gdb then named the
spinners — 17 threads in

```text
memory.spinLock () at memory.zig:97
reactor.withdrawCrossThreadWaiter () at reactor.zig:278
fiber_wait.CrossThreadEnrolment.release () at fiber_wait.zig:236
primitives_srfi18.threadSleepFn () at primitives_srfi18.zig:1104
```

— grandchildren leaving their `(thread-sleep! 0.3)`, each withdrawing from
the cross-thread wait registry, all spinning on its lock. The holder was LID
18430: runnable (`R`, no wait channel), inside `_sys___kevent50` — that is
`wakeCrossThreadWaiters` ringing every parked thread under the lock — and at
**priority 0**, the lowest a user LWP can have, while every spinner sat at
25–27. The kernel had preempted it mid-ring and, with 17 spinners and 4
burners competing for 4 CPUs, never picked it again. The test's 12-iteration
loop spawns a middle that returns without joining its grandchild, so a dozen
sleeping grandchildren accumulate and all wake within the same few
milliseconds, which is why this test and not another.

## Why NetBSD and only NetBSD

NetBSD's default scheduler is 4BSD (`sys/kern/sched_4bsd.c`):

- A user LWP's priority is `63 − estcpu/2048`. `estcpu` grows by 1024 on
  every clock tick the LWP is *running* and decays 90% over `5 × loadavg`
  seconds — tens of seconds under load.
- A new LWP inherits its spawner's `estcpu` (`sched_lwp_fork`).
- Each CPU runs the highest-priority runnable LWP. `sched_yield` requeues
  behind LWPs of the *same* priority, never behind a lower one.

So a thread that has done real work — rung a dozen kevents, run a thunk,
joined children — is at priority 0. Threads that just woke from a sleep, or
were just spawned by an idle parent, are at 25+. Once the kernel preempts
the busy thread while it holds a lock, a crowd of fresh waiters at higher
priority spins, each spin tick keeps *their* estcpu high but the holder's
never gets a chance to matter: it is simply never the best runnable LWP on
any CPU. Yielding in the spin loop changes nothing, since the yielders only
requeue behind each other. Linux CFS and macOS give every runnable thread a
share of the CPU regardless of history, so there the same spin costs
latency and never liveness — which is why four platforms never saw it.

The earlier "child parked at `pthread__create_tramp+0`" captures are the
same mechanism one step earlier: a new LWP inheriting a priority-0 spawner's
`estcpu`, runnable from birth, never scheduled behind the spinning crowd.
And the earlier mitigations helped for the same reason: retrying a spawn
gave up on a starved LWP, and ringing outside the lock shortened the
critical section in which the holder could be preempted. Neither removed
the spinners.

## Second round: why the backoff alone was not enough

Sleeping instead of spinning took the hang from 5/8 to 0/10 in a first
sample, then 4 of the next 8 runs hung again. Those captures had a new
shape: the process used **no CPU at all** (`TIME` frozen), eight waiters
asleep in the new backoff, eleven runnable at priority 0 in `sched_yield`,
and the kevent holder runnable at priority 0. With every spinner asleep, the
holder was still never chosen — because priority 0 is *below the floor* of
the formula above. For a nice-0 process `pri = 63 − estcpu/2048 − 20`, and
the per-tick accumulation clamps `estcpu` at `18 × 2048`, so the lowest a
thread can reach by running is 25 — the same as the CPU burners. Something
had pushed these LWPs below what running can do.

The one unclamped path is `sched_lwp_collect` (`sched_4bsd.c`):

```c
/* Absorb estcpu value of collected LWP. */
l->l_estcpu += t->l_estcpu;      /* no ESTCPULIM, unlike sched_proc_exit */
```

It runs in `lwp_wait` — that is, in `pthread_join` — on the **joining** LWP.
The interpreter thread joins every middle thread; each arrives with a full
`18 × 2048` after its work, and after three joins the joiner's estimate is
past `43 × 2048`: priority 0, and decaying at ~7%/s under load it stays
there for a long time. `sched_lwp_fork` then copies the estimate into every
LWP the joiner creates, so each new middle thread — and, through it, each
grandchild — is *born* at priority 0. Under contention from any ordinary
nice-0 process (priority 25+) such an LWP gets CPU only when a burner is
forced off by the round-robin tick, and with a dozen priority-0 siblings
ahead of it in the queue, effectively never. That is the "child parked at
`pthread__create_tramp+0` forever" of the first investigation, exactly.

A 40-line C program pins it (`estcpu.c`, kept on the reference VM): join
three threads that each spin for 1.5 s, then spawn a trivial child under
four burners. The child's join took 0.8 s; with the same three threads
*detached* instead of joined, 0 ms, as in the no-join control.

Detached LWPs are freed in `lwp_exit` without `sched_lwp_collect`. Hence
part (1) of the fix: SRFI-18 OS threads are detached the instant they are
spawned, and `reapOsThread` waits on a per-spawn exit flag the child raises
after its outermost defer, which covers everything `pthread_join` covered
(the child's status is stored well before; the flag marks the end of its
epilogue, descendant drain included).

## The fix

Part (2), the backoff, is still necessary: a thread that has merely done a
lot of work sits at 25 like the burners, and a crowd spinning on its lock at
25–27 outranks it on ties; the sleep is what ends the convoy.

`platform.spinBackoff(spins)`: the first 32 iterations are a pure spin, the
next 64 a `sched_yield`, and everything after sleeps, 32 µs doubling to a
1 ms cap. The sleep is the part that matters: it takes the waiter *off the
run queue*, so the preempted holder becomes the best runnable LWP and gets
its CPU. The spin and yield phases keep the uncontended and briefly
contended cases as fast as before — a healthy critical section under these
locks is a few dozen instructions, and a stopped child reaches its safepoint
in microseconds, so no sleep ever happens on a healthy machine.

Used at every cross-thread wait that was a pure spin:

| Site | Waits for |
|------|-----------|
| `memory.spinLock` | the holder of any of the 15 `std.atomic.Mutex` locks (wait registry, child registry, symbol table, channel waiter lists, …) |
| `VM.stopForCollection` | the collecting parent to finish marking |
| `markLiveChildRoots` (`primitives_srfi18.zig`) | each armed child to leave `.running` |
| `GlobalsRwLock.lockShared` / `.lock` (`globals.zig`) | the writer, or readers draining |
| `reapOsThread` (`primitives_srfi18.zig`) | the detached child's exit flag (part 1) |

Measured on the NetBSD 10.1 aarch64 reference VM (4 vCPUs), 40 s bound per
run, `srfi18-join-spawn-grandchild-2129.scm`:

| build | 4 burners | 8 burners |
|-------|-----------|-----------|
| unmodified `main` | 5/8 hung | 4/10 hung |
| backoff only | 0/10, then 4/8 hung | — |
| backoff + detach | 0/20 hung (and 0/10 of `srfi18-terminate-native-wait-1982.scm`) | 0/30 hung |

Not changed: `wakeCrossThreadWaiters` still rings under the lock. With
backoff, a preempted ringer costs the waiters latency (bounded by the 1 ms
sleep cap per probe), never liveness; moving the ring outside the lock
would need per-entry retain/release on a path that must not allocate, and
is a separate trade-off.

## Lessons

- **A frozen PC in gdb is not evidence about the scheduler.** It is
  compatible with "the OS lost this thread", "this thread is runnable and
  starved", and "this thread is asleep in a page fault". Only the kernel's
  per-thread state distinguishes them. On NetBSD:
  `ps -s -o pid,lid,lstate,wchan,cpuid,pri,time,pcpu -p <pid>`, sampled
  twice — climbing `TIME` in a "hung" process means it is spinning, not
  stuck. Linux: `/proc/<pid>/task/*/stat` (state, priority, utime);
  macOS: `top -pid` thread counts plus `sample`.
- **A userspace pure spin is a scheduler-policy bet.** It assumes the thread
  being waited for is running, or will be run promptly. That holds on fair
  schedulers and fails on priority-decay ones; the first priority-based
  scheduler in the platform matrix turned a latency cost into a hang. Every
  wait on another OS thread must be able to sleep.
- **Blocked-upstream is a strong claim and needs the kernel's testimony.**
  "No userspace program can produce this" should be backed by the state the
  kernel reports for the thread, not by the absence of a syscall in a
  userspace backtrace.
- **Measure under load with the burners tracked by PID.** The hang needs more
  runnable LWPs than CPUs. Orphaned burner shells from an aborted session
  double the load and poison the next measurement.
