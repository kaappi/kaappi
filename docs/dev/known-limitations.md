# Known limitations

The documented deviations and restrictions of the current implementation,
with the exact procedures each one affects. This is the source that the
short summary in the top-level `README.md` and the
[conformance page](https://kaappi-lang.org/conformance/) on kaappi-lang.org
both point at; [CONFORMANCE.md](../../CONFORMANCE.md) records the spec-level
coverage these restrictions sit alongside. Everything here is either a
deliberate choice or a known engine constraint — treat it as documented
behaviour, not a bug, when triaging (see `docs/audit-strategy.md`). When a
restriction is lifted or a new one lands, update this file, the README
summary, and the site's conformance page together.

## Continuations

`call/cc` captures continuations by copying the full VM state (registers, call
frames, exception handlers, dynamic-wind stack). Cost is O(stack depth) per
capture — negligible for most programs, but noticeable if continuations are
captured in tight inner loops. Continuations captured in one top-level REPL
expression cannot re-enter subsequent top-level expressions (standard behavior
shared by Guile, Chibi, Chicken, Chez, and Racket).

A continuation captured inside the callback of a **native driver** — a
higher-order procedure implemented in Zig that re-enters the VM once per
element — cannot be resumed once that driver's call has returned, because the
driver's state lives on the Zig stack, not in the copied VM state. This is the
restriction [CONFORMANCE.md](../../CONFORMANCE.md) refers to. It is why a
continuation-backed value (e.g. a SRFI 158 coroutine generator, which captures
a continuation on every `yield`) breaks when consumed inside such a driver.

Which procedures are exempt is not guessable from the outside, so here is the
list. **Exempt** — a continuation captured in the callback resumes freely:
`apply` and `call-with-values` (both positions, and both halves of the latter:
`#2451` for its consumer, `#2453` for its producer),
`map`, `for-each`, `vector-map`, `vector-for-each`, `string-for-each`, and — as
of #2060 — the SRFI-1 `fold`, `filter`, `any`, `every`, `unfold` and SRFI-69
`hash-table-walk`. A coroutine generator can be applied, folded, filtered,
mapped or walked freely.

**Still restricted**: the remaining native SRFI-1 drivers — `fold-right`,
`reduce`, `reduce-right`, `find`, `find-tail`, `count`, `partition`, `remove`,
`take-while`, `drop-while`, `delete`, `delete-duplicates`, `filter-map`,
`append-map`, `pair-for-each`, `pair-fold`, the `lset-*` family, and
`assoc`/`member` with a custom predicate, among others — plus one corner of
the exempt pair: an `apply` whose flattened argument list exceeds 255
arguments, which falls back to the native route because the call opcode's
argument count is a single byte.

SRFI 248's delimited continuations (`with-unwind-handler`, and the extended
`guard`) are built on this `call/cc` via a sticky exception handler, with three
observable caveats:

- **Single-shot** — each captured delimited continuation may be resumed at most
  once. Every SRFI 248 idiom (coroutine generators, `for-each->fold`, effect
  handlers) resumes each `k` once, so this does not affect them; resuming the
  same `k` twice fails because it re-enters a native frame that has already
  returned.
- **Handler timing** — the handler runs at the raise point rather than after
  unwinding to `with-unwind-handler`, so a handler side effect (and, since
  `guard` is built on it, a `guard` clause) runs *before* a `dynamic-wind`
  after-thunk of the guarded body, where R7RS-small runs it after. All the
  effects still happen; only their order differs. See
  [CONFORMANCE.md](../../CONFORMANCE.md) for details.
- **Shared prompt cell** — the delimited-control prompt is a single cell per
  thread, shared by every fiber in it, so a `with-unwind-handler`/`guard` body
  must not span a fiber suspension point (a blocking channel operation, parked
  I/O) while another fiber runs delimited control: the prompts cross silently —
  one fiber's `with-unwind-handler` can return another fiber's handler value
  while the parked body never completes, with no error raised. Mixing in user
  `call/cc` is unsupported the same way: a `call/cc` capture that crosses a
  `with-unwind-handler` boundary makes the guarded body re-run exponentially —
  a loop that escapes through user `call/cc` from inside `with-unwind-handler`,
  run under SRFI 248's `guard`, executes its body 2^n-1 times instead of n (255
  where 8 is correct, at n = 8) and still exits 0.

All three are limited to SRFI 248; plain `call/cc`, `dynamic-wind`, and the
built-in `guard` are unaffected unless you import `(srfi 248)`.

## Exceptions

A handler runs after the stack has unwound to the `with-exception-handler` (or
`guard`) that installed it, rather than at the raise point, so a `parameterize`
or `dynamic-wind` extent entered between the two is already gone by the time
the handler is called. R7RS-small calls the handler in the dynamic environment
of the `raise`. `raise-continuable` is unaffected — its handler does run in
place, as specified.

`guard` clauses are evaluated in the guard's own dynamic environment, as R7RS
4.2.7 requires. One consequence of the above shows in the implicit re-raise:
when no clause matches, `raise-continuable` is invoked in the *guard's* dynamic
environment rather than the original raise's, so an outer
`with-exception-handler` observes the guard's parameterization. Restoring the
raise point's dynamic environment needs a continuation captured under the
native raise frame, which cannot be resumed once that frame has returned.

This applies to the built-in `guard`. `(srfi 248)` replaces `guard` with its
own, whose separate timing caveat is above.

## Fibers

Scheduling is cooperative: spawned fibers run when the main program blocks
(`channel-receive` on an empty channel, `fiber-join`) or calls `(yield)`.
A fiber that blocks on an empty channel is parked and woken by the next
`channel-send` on that channel. When the main program ends, fibers that are
still parked (e.g. workers that never received a stop sentinel) are simply
discarded and the process exits — like goroutines in Go. If the main program
blocks on a channel that no runnable or parked-and-wakeable fiber can ever
send to, `channel-receive` raises a deadlock error (an `error` object,
catchable with `guard`); the same applies to `fiber-join` on a fiber that can
never complete.

Callbacks driven by `map`, `for-each`, `vector-map`, `vector-for-each`,
`string-map`, `string-for-each`, `dynamic-wind`, `force`, and — since #2060 —
SRFI-1 `fold`, `filter`, `any`, `every`, `unfold` and SRFI-69 `hash-table-walk`
run in the bytecode dispatch loop, so a fiber can park inside them (e.g. block
on an empty channel) and resume later. Other higher-order procedures are still
native drivers — SRFI-1 (`fold-right`, `reduce`, `find`, `count`, `partition`,
`remove`, ...), `hash-table-update!`, `assoc`/`member` with a custom
predicate, `string-index`, `eval`, ... — and a fiber that blocks on
an empty channel inside one of those callbacks cannot be parked: the native
call's state lives on the Zig stack and cannot be suspended. If other fibers
are runnable the scheduler still makes progress, but if the blocked receive
is the only thing left it raises a deadlock error instead of suspending.
Move blocking `channel-receive` calls into plain Scheme loops (named `let`,
`do`) or the bytecode-driven procedures above when a fiber must wait inside
iteration.

Port I/O that would block (a socket or pipe read/write with no data or a
full kernel buffer) parks the fiber on the per-thread reactor instead of
blocking the OS thread, so fibers reading different connections interleave.
The main fiber — or a fiber inside a native-driver callback — cannot be
parked; it instead dispatches sibling fibers in place while it waits, so
progress continues either way. Ports on fds other than 0/1/2 buffer output
until `flush-output-port`, `close-port`, a read on the same port, the
buffer filling (8 KiB), or program exit; stdin/stdout/stderr remain
unbuffered.

On WASI, whether a port can park a fiber depends on the host. Ports flip to
non-blocking only if `fd_fdstat_set_flags(NONBLOCK)` succeeds; where it does
not — the playground's browser shim, for one — no fd is ever registered and the
reactor falls back to timer-only waits, leaving I/O blocking and single-fiber.
Timers and `thread-sleep!` work either way.

## OS threads (SRFI-18)

Each OS thread gets its own VM and GC with an independent heap, and can
allocate and collect without affecting the parent. A value reaches another
thread by one of **two routes**, which behave differently:

- **By copy** — the thunk closure at `thread-start!`, the result at
  `thread-join!`, and every channel message are deep-copied. Fourteen types are
  refused outright on this route (ports, continuations, fibers, mutexes,
  condition variables, and more).
- **By reference** — top-level bindings are shared *by pointer*, so a thunk
  that merely *names* a global gets the parent's own object, uncopied. The
  refusal list above does not apply, and only four types (channels, thread
  handles, fibers, guardians) check that the caller owns them.

So threads **can** share mutable state, through a top-level binding — and for
mutexes and condition variables that is the *only* supported way to share one.
Doing it with ordinary data is a hazard rather than an idiom: nothing
synchronizes the writes, the child collects independently, and the child heap
is freed after `thread-join!`. Prefer channels and return values. The full
per-type matrix, and which route checks what, is in
[thread-value-sharing.md](thread-value-sharing.md).

A `(kaappi fibers)` channel captured by a thread's thunk (or nested inside a
value sent over one) crosses safely: it is promoted to a mutex-protected,
refcounted shared channel outside every GC heap, and every message crosses by
copy (KEP-0002). `(kaappi parallel)` builds worker pools and `parallel-map`/
`parallel-for-each` on top of this — see the [Concurrency
guide](https://kaappi-lang.org/guide/concurrency/) for the higher-level API.
A channel must reach the other thread through **lexical capture** in the
thunk (or in a message sent over an already-promoted channel) — a channel
reached instead through a shared top-level `define` is never promoted, and
raises a descriptive error rather than corrupting memory
([#1742](https://github.com/kaappi/kaappi/issues/1742) is exactly this
trap). See [Standards
Conformance](https://kaappi-lang.org/conformance/#extensions-beyond-r7rs-smalls-scope)
for current status.

`parallel-map`/`parallel-for-each` submit one task per list element. For
very large inputs, chunking manually with `make-pool`/`pool-submit`/
`task-wait` (one task per processor, each covering a slice of the input with
an ordinary sequential loop) reduces per-task submission overhead — see
`kaappi-examples/parallel-primes` for a worked example.

## Script output

Running a script (`kaappi program.scm`) echoes the value of every non-void
top-level expression to stdout, as a REPL does; `define` and other
void-valued forms print nothing. A top-level call used for effect therefore
adds a datum to the program's own output — a cleanup helper ending in
`(guard (e (#t #f)) ...)` prints its `#f`, and `(map f rows)` prints the
resulting list. Chibi and Guile print nothing when running the same file. No
flag disables the echo; keep effectful top-level sequences void-valued (end a
`begin` with `(if #f #f)`) when the program's output must stay parseable.

## Macros

Only `syntax-rules` is supported. `syntax-case` was intentionally excluded from
R7RS-small and is not implemented.

## SRFI coverage

181 SRFIs are supported. Some built-in SRFIs have minor coverage gaps (e.g.,
linear-update variants in SRFI-1, `string-xcopy!` in SRFI-13). See
[CONFORMANCE.md](../../CONFORMANCE.md) for per-SRFI details.

SRFI 261 (Portable SRFI Library Reference) is supported as an import-resolver
convention: `(import (srfi srfi-1))` and `(import (srfi lists-1))` resolve to
`(srfi 1)` — the trailing number is authoritative — and sub-library tails pass
through (`(srfi srfi-146 hash)`). Literal names win when they exist, so a
library actually named `(srfi srfi-x)` is never shadowed. `cond-expand`'s
`(library …)` test honors the same forms.
