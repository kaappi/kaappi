# KEP-0001 Phase 7: Performance Evaluation

Tracking issue: [#1445](https://github.com/kaappi/kaappi/issues/1445). Epic:
[#1438](https://github.com/kaappi/kaappi/issues/1438). Phases 1–6 are merged;
this phase measures the reactor's real-world costs and confirms (or
overturns, with data) the design decisions recorded in [keps#2](https://github.com/kaappi/keps/pull/2).

All benchmark sources live in `src/bench_reactor.zig` (Q1/Q2/Q3, run with
`zig build bench-reactor`) and `src/bench_fibers.zig` (Q5, run with
`zig build bench-fibers`). Server benchmarks used a one-off load generator
(no `wrk`/`hey`/`ab` available in this workspace) — see the ecosystem
benchmark section below for how to reproduce.

## Summary

| Question | Decision | Confirmed? |
|---|---|---|
| Q1 — wake-all herd cost | Wake-all (not wake-head-only) | **Confirmed** — no measurable herd cost at the reactor level |
| Q2 — timer granularity | ms + ceil-round on Linux, no `timerfd` | **Confirmed** — no workload needs sub-ms precision |
| Q3 — ONESHOT vs LT | ONESHOT | **Confirmed** — re-arm cost is well under the cost of the adjacent I/O syscall it accompanies |
| Q5 — per-fiber memory | Live-window save/restore | **Partially confirmed** — memory is bounded and modest, but per-switch *time* degrades with total live-fiber count (see below) — the actual residual this phase was meant to surface |
| Edge-triggered migration | — | **No-go for now** (see below) |

Prerequisite fix landed before any of this could be measured safely: see
"Prerequisite: #1463" below.

## Q1 — Wake-all herd cost

`src/bench_reactor.zig`'s `benchWakeAllFanout`: N fake fibers registered as
waiters on one shared fd, one real write, measuring how long `poll()` takes
to wake all N (confirming wake-all, not wake-head-only).

macOS (kqueue):

| N | woken | poll (ns) | ns/woken-fiber |
|---|---|---|---|
| 2 | 2 | 2000 | 1000.0 |
| 10 | 10 | 2000 | 200.0 |
| 100 | 100 | 1000 | 10.0 |
| 1000 | 1000 | 4000 | 4.0 |

Linux (epoll, aarch64 container):

| N | woken | poll (ns) | ns/woken-fiber |
|---|---|---|---|
| 2 | 2 | 3584 | 1792.0 |
| 10 | 10 | 1542 | 154.2 |
| 100 | 100 | 2125 | 21.3 |
| 1000 | 1000 | 10500 | 10.5 |

`poll()`'s own wake-all fan-out cost does **not** grow with N — it's
dominated by a small fixed per-call cost (array copy), not a per-waiter one.
The KEP's wake-head-only-FIFO fallback is not warranted at the reactor
level. (The real per-waiter cost of wake-all — every registered fiber
retrying its syscall and only one winning — is an *application*-level
tradeoff, not a reactor one; see the fiber HTTP server latency numbers
below, where it plausibly contributes at high concurrency.)

## Q2 — Timer granularity

`src/bench_reactor.zig`'s `benchTimerGranularity`: schedules one timer at a
known deadline, measures how late `poll()` actually returns.

macOS (kqueue, ns-precision `timespec` API):

| requested | late by |
|---|---|
| 1ms | +133µs |
| 5ms | +631µs |
| 20ms | +1033µs |
| 100ms | +1018µs |

Linux (epoll, in a podman/QEMU-virtualized container — expect extra jitter
from virtualization on top of the numbers below):

| requested | late by |
|---|---|
| 1ms | +260µs |
| 5ms | +215µs |
| 20ms | +660µs |
| 100ms | +2412µs |

Two things worth noting: (1) even kqueue's nanosecond-precision timer API
shows a practical floor around ~1ms once the requested duration is more
than a few ms — this is OS thread-scheduling wake-up latency, not a kaappi
limitation, and it means kqueue's theoretical precision advantage over
epoll's ms-ceil-rounding (`msFromNs`, `src/reactor.zig:487-491`) mostly
doesn't show up in practice. (2) A grep across the test suites and
ecosystem repos (`kaappi-net`, `kaappi-pg`, `kaappi-http`) found no
`thread-sleep!` interval below 1ms in real (non-microbenchmark) code — the
Q2 decision holds: nothing in this codebase needs sub-ms deadlines, so the
`timerfd` escape hatch stays unbuilt.

## Q3 — ONESHOT re-arm cost

`src/bench_reactor.zig`'s `benchRearmVsIo`: 100,000 cycles of `register()`
(the `epoll_ctl`/`kevent` call) vs. an adjacent `read(2)`+`write(2)` pair on
the same pipe.

| Backend | register() (arm) | read+write (io) | ratio |
|---|---|---|---|
| macOS (kqueue) | 338.5 ns | 442.1 ns | 0.77x |
| Linux (epoll) | 173.8 ns | 372.9 ns | 0.47x |
| Linux, wake-all fan-out with an OS-thread instead of a fiber (not measured) | — | — | — |

On both platforms the re-arm call is *cheaper* than the I/O syscall pair
it accompanies every cycle. There is no meaningful overhead here for
edge-triggered mode to eliminate.

## Q5 — Per-fiber memory and switch time

`src/bench_fibers.zig`. Three things were measured: raw switch/spawn cost
at scale, RSS, and whether the native-frame `frameWindow()` fallback
(`types.zig:546-551`, 256 registers for any frame with no attached
closure) measurably inflates a fiber's saved register/frame arrays.

### Switch time degrades with total live-fiber count

Spawning N fibers, each yielding 50 times in a tight loop, then joining all:

| fibers | ns/switch | RSS |
|---|---|---|
| 100 | ~465 ns | +0 MB |
| 1,000 | ~3,300–4,600 ns | +0 MB |
| 10,000 | ~93,000–99,000 ns | +0.06 MB |

Consistent across three separate runs. Isolating spawn cost alone (0 yield
rounds, just N `spawn` + `fiber-join` pairs) shows the same shape: ~10–30
µs/spawn at 100–1,000 fibers, jumping to ~250–280 µs/spawn at 10,000.

**Root cause**: `FiberScheduler.schedule()` (`src/fiber.zig:302-325`) does a
full round-robin scan over *every* slot in `sched.fibers.items` (including
completed/errored ones still occupying a slot) to find the next runnable
fiber — O(fiber count) per dispatch, called on every single switch.
`FiberScheduler.addFiber()` (`src/fiber.zig:86-99`) does the same kind of
O(fiber count) linear scan for a free slot on every spawn. Per-fiber
memory itself stays flat and modest (the RSS deltas above are noise-level
until 10k, where it's still only +0.06MB) — it's *switch time*, not memory,
that's the real Q5 residual, and it degrades by roughly two orders of
magnitude between 100 and 10,000 concurrently-live fibers.

This is not just a synthetic-benchmark artifact — it shows up end-to-end in
the HTTP server benchmarks below (`http-listen-fiber`'s p99 latency at
1,000 concurrent connections is *worse* than the naive sequential server's).
**Follow-up filed**: replacing the O(n) scan with an actual ready queue
(the KEP's Q1 discussion already floated "wake-head-only FIFO" for a
related reason — this is the same class of fix).

### Native-frame register/frame inflation: not observed

Compared fibers yielding from a pure-bytecode tail loop against fibers
yielding from inside `for-each`'s native call frame, across recursion
depths 0, 10, 60, and 300 (with up to 7 extra bound locals per frame to
vary register pressure). In every configuration tested, both kinds
allocated identical register/frame array sizes (e.g. 256 registers / 32
frames at shallow depth, growing identically to 4096/512 at depth 300 with
extra locals). **No inflation was observed in practice** across this
range — the initial per-fiber capacities (`INITIAL_FIBER_REGISTER_CAPACITY
= 256`, `INITIAL_FIBER_FRAME_CAPACITY = 32`, `types.zig:527-528`) appear to
already absorb the native-frame fallback's window without forcing a
reallocation in these scenarios, or the outer non-tail call chain's own
register usage already dominates whatever the native frame's flat 256
contributes. This is a genuine null result, not a methodology gap that
was worked around — three different attempts at making the two cases
diverge (shallow, deep, and register-heavy-deep) all showed no difference.
A more surgical Zig-level instrumentation of `liveRegisterSpan` directly
would be needed to fully rule out inflation in *all* possible call shapes,
but nothing tested here found it.

## Edge-triggered migration: **no-go for now**

The KEP is explicit that migrating to `EPOLLET`/`EV_CLEAR` should not be
done without a soak test, since edge-triggering without strict drain
discipline hangs fibers. Given that constraint, this phase evaluates
whether there's even a reason to take on that risk, rather than building
and soak-testing a parallel backend under time pressure inside a
measurement phase.

The Q3 data above answers this directly: on both kqueue and epoll, the
ONESHOT re-arm cost is *already cheaper* than the I/O syscall it
accompanies (0.77x on macOS, 0.47x on Linux). There is no overhead left
for edge-triggered mode to remove. **Recommendation: no-go.** Revisit only
if future profiling under a real production workload shows re-arm cost
actually dominating — nothing measured here suggests that will happen.

## Ecosystem server benchmarks

Compared `kaappi-http`'s four server models (`http-listen`,
`http-listen-threaded`, `http-listen-prefork` with 4 workers,
`http-listen-fiber`) at 1, 100, and 1,000 concurrent connections, one
request per connection (`Connection: close`), against a trivial `"Hello,
World!"` handler. No load-gen tool was available in this workspace, so a
minimal Python client (threaded, one connection per request) was used
instead — not a substitute for `wrk`, but sufficient to compare the four
models against each other on the same client.

**`http-listen-threaded` could not be benchmarked** — see "New bug found"
below; it hangs on every request in this environment, confirmed
pre-existing (reproduces on an unmodified `main` build, unrelated to any
change in this phase).

| model | concurrency | req/s | p50 | p99 | max | RSS |
|---|---|---|---|---|---|---|
| sequential | 1 | 3329 | 0.20ms | 4.45ms | 4.45ms | — |
| sequential | 100 | 10103 | 7.32ms | 22.20ms | 24.34ms | — |
| sequential | 1000 | 9707 | 14.65ms | 351.60ms | 372.29ms | 6.9 MB |
| prefork (4w) | 1 | 3089 | 0.23ms | 3.86ms | 3.86ms | — |
| prefork (4w) | 100 | 11016 | 6.06ms | 27.59ms | 29.20ms | — |
| prefork (4w) | 1000 | 11142 | 15.24ms | 52.94ms | 92.91ms | 6.0 MB (parent only — 4 workers each hold their own heap, not counted) |
| fiber | 1 | 747 | 1.25ms | 5.66ms | 5.66ms | — |
| fiber | 100 | 9060 | 1.46ms | 48.48ms | 49.03ms | — |
| fiber | 1000 | 8116 | 1.73ms | 490.24ms | 500.29ms | 15.3 MB |

Two findings worth calling out:

1. **`http-listen-fiber` pays a ~1ms tax on every request, even
   uncontended** (conc=1 req/s is 747 vs. sequential's 3329 — 4.5x slower
   for a single client with zero contention). This matches what the code
   review at the start of this phase found: `fiber-recv`/`fiber-send`
   (`kaappi-http/lib/kaappi/http/server.sld:105-119`) poll the fd once and,
   if not immediately ready, `(thread-sleep! 0.001)` before retrying —
   which means the fiber server's I/O never actually registers with
   `Reactor.register`/`waitForFd` at all (`kaappi-net`'s raw TCP fds never
   reach `src/reactor.zig`); it's a fixed 1ms poll-then-sleep loop layered
   on top, not real event-driven wakeup. **Follow-up filed**: wire
   `kaappi-net`'s raw sockets into the reactor properly.

2. **`http-listen-fiber`'s p99 at 1,000 concurrent connections (490ms) is
   *worse* than the naive sequential server's (352ms)** — despite fibers
   being the model designed for exactly this workload. This is the
   FiberScheduler O(n) scan cost from the Q5 section above showing up
   end-to-end: every read/write retry across 1,000 live connections pays
   an ever-growing scheduling-scan tax. The reactor's own mechanics (Q1,
   Q3) are not the bottleneck; the scheduler's dispatch-loop scan is.

10,000-connection runs were not attempted locally — macOS's low default
`ulimit -n` and the two findings above (which already show real
degradation at 1,000) made a 10k run unlikely to produce more useful
signal than cost. A dedicated Linux run would be the right way to get
that data point once the two follow-ups above are addressed.

### Reproducing

```
cd kaappi-http
# terminal 1
DYLD_LIBRARY_PATH=..:../../kaappi-net zig-out/bin/kaappi \
  --lib-path ../kaappi-net/lib --lib-path lib bench_server_app.scm fiber
# terminal 2 (no wrk/hey in this workspace -- see scratch script in this PR's description)
python3 http_load_gen.py 19999 1000 5000
```

## New bug found: `http-listen-threaded` hangs (pre-existing)

While setting up the server benchmarks, `http-listen-threaded` hung on
every single request — confirmed to reproduce on an unmodified `main`
build (stashed this phase's changes and rebuilt to verify), so it
predates this phase and is unrelated to the `#1463` fix below.

**Minimal repro**: a `define-library`-defined procedure that calls
`thread-start!` with a thunk which itself calls into *another* library's
exported procedure (here, `(kaappi http parse)`'s `make-http-buffer` /
`http-read-request`) hangs the child OS thread — it never gets past that
call. The *identical* code, with the exact same imports, hangs only when
the calling procedure is defined inside a library body; moved verbatim to
top-level script code, it works correctly. Bisected imports
(`(kaappi fibers)`, `(kaappi ffi)`, `(kaappi http net)` vs. `(kaappi net)`
directly) ruled those out — the only remaining variable is
library-body-defined vs. top-level-defined for the thread-spawning
procedure itself.

This points at something in how a child OS thread's VM
(`VM.initForThread`, which shares the parent's globals/libraries) resolves
bindings for a closure whose *defining* environment is a library body,
when that closure calls into a second library's procedure from inside the
child thread. Root-causing and fixing this fully is a separate, deeper
investigation than this benchmarking phase — filing as a follow-up rather
than fixing here.

## Prerequisite: #1463 (fixed this phase)

`thread-sleep!` (`src/primitives_srfi18.zig`) lacked the
`dispatched_from_scheduler`-aware yield-retry branch `fiber.waitForFd` has
(`src/fiber.zig:552-576`) — a scheduler-dispatched fiber calling
`thread-sleep!` always drove the scheduler recursively instead of
unwinding flatly, so concurrent fibers each retrying via short
`thread-sleep!` calls grew the native call stack without bound. Confirmed
via a regression test that segfaults (stack overflow) without the fix and
passes with it (`src/tests_srfi18.zig`). This was a **necessary
prerequisite** for this phase: `http-listen-fiber`'s
`fiber-recv`/`fiber-send` use exactly this poll-then-`thread-sleep!`
pattern, and benchmarking it at any real concurrency (as confirmed by a
500- and 1,000-concurrent-connection stress test after the fix) would
very likely have hung or crashed instead of producing numbers.

## Follow-ups to file

1. `FiberScheduler.schedule()`/`addFiber()` O(fiber count) scans don't
   scale past ~1,000 concurrently-live fibers — replace with an O(1)/O(log
   n) ready-queue design. Directly explains the `http-listen-fiber` p99
   regression above.
2. Wire `kaappi-net`'s raw TCP sockets into `Reactor.register`/`waitForFd`
   properly, so `http-listen-fiber` gets genuine event-driven wakeup
   instead of a fixed 1ms poll-then-sleep loop.
3. `http-listen-threaded` hangs on every request — pre-existing,
   reproducible, isolated to library-defined-procedure + cross-thread +
   cross-library-call. Needs a deeper VM/threading investigation.
4. `kaappi-net`'s `net.sld` and `kaappi-pg`'s `pg.sld` have comments noting
   they avoid `thread-sleep!` in retry loops "until [the core] follow-up
   lands" (referring to the same bug as #1463) — now that the core fix has
   landed, those comments are stale and the workaround could be
   revisited (low priority, not urgent since the `yield`-based workaround
   already works).
