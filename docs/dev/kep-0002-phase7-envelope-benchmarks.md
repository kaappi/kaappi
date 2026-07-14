# KEP-0002 Phase 7 — envelope-cost A/B/C/D micro-benchmark (P3)

This documents the **envelope-cost half** of KEP-0002 Phase 7
([kaappi#1472](https://github.com/kaappi/kaappi/issues/1472)): the P3
elision-lever matrix from
[keps `research/open-problems.md` P3](https://github.com/kaappi/keps/blob/main/research/open-problems.md)
and the pre-registered A/B/C/D decision it drives. It is the "run
before/after, compare by eye" benchmark tier (like `bench-fibers` /
`bench-reactor`), **not** the statistically-disciplined gate campaign.

The other Phase 7 half — the `parallel-map` scaling curve that feeds the
KEP-0003 acceptance gate ([kaappi#1474](https://github.com/kaappi/kaappi/issues/1474)),
under the full Kalibera–Jones statistics of
[keps `research/benchmarks/README.md`](https://github.com/kaappi/keps/blob/main/research/benchmarks/README.md)
— is separate and still to do (see [Status](#status--what-remains)).

## Running it

```
zig build bench-channel                        # ReleaseSafe: the shipped default
zig build bench-channel -Doptimize=ReleaseFast # faster build, for contrast
```

The harness prints its build mode in the header. **The P3 decision reads
the ReleaseSafe numbers**, because the shipped binary is ReleaseSafe
(keps `research/benchmarks/README.md` §4.5) and the (B) verdict is
build-mode sensitive (below).

## What it measures

Three sections (`src/bench_channel.zig`):

1. **Local (unpromoted) send+receive** — the invariant-3 fast-path gate: a
   channel that never crossed a thread is today's pair-queue plus two
   null-checks. Runs through a real VM/eval.
2. **The P3 A/B/C/D matrix** — for each lever × payload shape, a
   send-side *build envelope* + receive-side *copy out* round trip,
   reporting ns/message, allocations/message (via a counting allocator),
   and the message's heap-object count.
3. **Reference: real promoted send+receive** through `shared_channel`
   (lever A, full spin-lock + queue), so the matrix's lever-A column ties
   back to the shipped path.

### The four levers

| Lever | Envelope strategy |
|-------|-------------------|
| **A** | Per-message GC struct — a fresh private mini-heap + `deepCopy` in, torn down after copy-out. Exactly what `src/shared_channel.zig` ships. |
| **B** | Reusable per-channel arena — one persistent GC reused message after message; only the copied-in graph is freed between uses, keeping the ~8 KiB root buffer + GC struct across the channel's life. |
| **C** | A **plus** the immediate fast path — non-pointer NaN-boxed values (fixnums, booleans, chars; also nil/flonums) skip the envelope heap entirely (`deepCopy` would return them unchanged). |
| **D** | C **plus** a refcounted immutable side-heap — large bytevectors/strings (≥ 8 KiB here) cross by a `shared_object` reference: one snapshot copy at creation, zero-copy on receive. |

The workloads are P3's five shapes: fixnum, small pair, 1 KiB string,
64 KiB bytevector, and a 50-deep nested-pair chain standing in for the
"deep record" shape (same stand-in the Phase 1 harness used, until a
record-type harness lands).

## Results — macOS aarch64

Reference machine: Apple **M3 Pro**, 12 physical cores (6P+6E,
heterogeneous — noted per protocol §4.6), macOS 26.5.2, Zig 0.16.0,
kaappi `5e86f231`. Machine idle, on power. These are single-run point
estimates from this benchmark tier; the mechanical decision below reads
only the outcomes that clear their thresholds by a wide margin (see
[Caveats](#caveats)).

### ns/message

**ReleaseSafe (operative — shipped default):**

| payload shape | A | B | C | D |
|---|--:|--:|--:|--:|
| fixnum | 256.8 | 5.4 | 2.4 | 2.3 |
| small pair | 405.9 | 141.0 | 485.5 | 470.1 |
| 1 KiB string | 555.9 | 238.0 | 479.9 | 540.0 |
| 64 KiB bytevector | 5673.4 | 4714.6 | 5514.4 | 1996.6 |
| 50-deep chain | 4819.7 | 4557.7 | 4885.3 | 4842.4 |

**ReleaseFast (contrast):**

| payload shape | A | B | C | D |
|---|--:|--:|--:|--:|
| fixnum | 60.1 | 3.8 | 2.2 | 2.2 |
| small pair | 179.9 | 123.1 | 181.5 | 180.8 |
| 1 KiB string | 254.7 | 188.7 | 255.6 | 255.4 |
| 64 KiB bytevector | 2268.4 | 2120.0 | 2276.8 | 881.6 |
| 50-deep chain | 4636.2 | 4656.0 | 4739.7 | 4546.9 |

### allocations/message (deterministic, identical across both builds)

| payload shape | A | B | C | D | msg heap objs |
|---|--:|--:|--:|--:|--:|
| fixnum | 2 | 0 | 0 | 0 | 0 |
| small pair | 6 | 4 | 6 | 6 | 1 |
| 1 KiB string | 8 | 6 | 8 | 8 | 1 |
| 64 KiB bytevector | 8 | 6 | 8 | 2 | 1 |
| 50-deep chain | 110 | 108 | 110 | 110 | 50 |

The allocation column is the mechanism, exactly:

- **A pays two fixed allocations per message** — the GC struct and its
  ~8 KiB root buffer — *even for a fixnum whose message graph has zero
  heap objects*. That fixed tax is what the other levers attack.
- **B removes exactly those two** across every shape (6→4, 8→6, 110→108):
  the arena is allocated once, not per message.
- **C removes the whole envelope for immediates** (2→0 on the fixnum) and
  is a no-op for pointer payloads (it falls through to A).
- **D turns the 64 KiB copy into a refcount**: 8→2 allocations (the
  side-buffer struct + its bytes, allocated once) and no copy-out.

## The pre-registered P3 decision

Thresholds verbatim from open-problems.md P3; the harness prints this
block mechanically.

### (C) immediate fast path — **SHIP**

> (C) ships if immediates are ≥ 2× (A) for fixnum messages.

Fixnum A/C = **107.9×** (ReleaseSafe), **27.8×** (ReleaseFast). Both
build modes clear 2× by more than an order of magnitude, and C erases
the two fixed allocations. This is the near-certain outcome P3
predicted. **Recommend shipping C** — a `!isPointer(payload)` fast path
in `shared_channel.send`/`receive` that carries the raw value instead of
building an envelope.

### (B) reusable arena — **ship candidate under ReleaseSafe, pending the second clause**

> (B) replaces (A) only if it wins ≥ 30% on the small-message workloads
> **and** survives the gc-stress/leak suite with no new lifetime rules
> visible outside `shared_channel.zig`.

B's improvement `(A−B)/A` on the small-message set:

| shape | ReleaseSafe | ReleaseFast |
|---|--:|--:|
| fixnum | 97.9% | 93.7% |
| small pair | 65.3% | 31.6% |
| 1 KiB string | 57.2% | **25.9%** |

**The verdict flips on build mode.** Under **ReleaseSafe (the shipped
default)** all three small-message shapes clear ≥ 30% (57–98%) → the
performance clause is **met**. Under ReleaseFast the 1 KiB string only
reaches ~26% → not met. The swing cell is the 1 KiB string: safety
checks make A's per-message GC-struct + root-buffer alloc/free costlier
in absolute terms, so B's amortization recovers a larger share.

Because the shipped binary is ReleaseSafe, **the operative reading is
that B meets the performance bar.** But the *second clause is
unproven*: the ≥30% result only licenses B if a real arena in
`shared_channel.zig` survives gc-stress + the leak suite **without
leaking any new lifetime rule outside that file**. That is an
implementation-and-verification task, not something this micro-benchmark
settles. The benchmark's arena is deliberately exercised only on
symbol-free graphs (a symbol-bearing arena needs the symbol table
preserved across resets — see `freeArena`'s comment); a shipped arena
must handle symbol-bearing messages too. **Recommendation: treat B as a
ship candidate; gate it on a `shared_channel.zig` arena prototype that
passes gc-stress/leak with the lifetime rule contained.**

### (D) refcounted side-heap — **measured only**

> (D) is implemented behind a flag for measurement; its *shipping*
> decision belongs to the KEP-0003 gate, not this benchmark.

64 KiB bytevector A/D = **2.8×** (ReleaseSafe), **2.6×** (ReleaseFast),
even in a 1:1 round trip (one snapshot copy vs. copy-in + copy-out). The
larger lever — one copy shared across an N-worker fan-out instead of N
copies — is what [kaappi#1474](https://github.com/kaappi/kaappi/issues/1474)
measures. Recorded here; **not decided here.**

## Caveats

- **This is the eyeball tier, not the gate tier.** Single-run point
  estimates, no bootstrap CIs, no invocation/iteration discipline. The
  decision reads only outcomes that clear their thresholds by a wide
  margin.
- **The noise floor is visible in the fall-through cells.** C and D on
  the small pair / 1 KiB string / chain execute the *identical* path as
  A, so those cells should equal A. Under ReleaseSafe they spread ±15–20%
  (e.g. C small-pair 485 vs A 406; C 1 KiB 480 vs A 556) — a direct read
  on this tier's run-to-run variance, and the reason a borderline verdict
  (ReleaseFast's 1 KiB string at 26%) is *not* trustworthy while the
  wide-margin verdicts (C at 28–120×, B's ReleaseSafe small-message wins
  at 57–98%) are.
- **One machine.** macOS aarch64 only. No cross-machine agreement is
  claimed for the P3 verdict yet (see below).

## Status / what remains

Done in this pass:

- `src/bench_channel.zig` grown from the Phase 1 single-lever harness
  into the full A/B/C/D matrix, with a counting allocator and the
  mechanical P3 decision printer. Unit suite green; the file is a
  standalone bench executable, outside the `test` graph.

Still open for Phase 7 / #1472:

1. **Second reference machine** — re-run on Linux x86_64 (≥ 8 physical
   cores) and confirm the C and B verdicts agree. Only then is the P3
   decision two-machine-solid.
2. **Lever-B ship gate** — prototype the reusable arena inside
   `shared_channel.zig` and run it under `-Dgc-stress=true` + the leak
   suite, checking the lifetime rule stays contained. This is the P3 (B)
   second clause; without it the ≥30% result is necessary but not
   sufficient.
3. **Lever-C ship** — the immediate fast path now exists in the real
   `send`/`receive` (behind `-Dchannel-instrument`, as the gate lever
   `c`; see the gate campaign below). Promoting it to the shipped default
   (lever-invariant, no flag) with a regression test is the remaining
   step.
4. **KEP-0002 UQ 1 amendment** — record the A/B/C/D outcome (ship C; B
   pending clause 2; D deferred) into KEP-0002, per #1472's acceptance.
   Best done after (1).
5. **The gate campaign** — the `parallel-map` IP-*/FO-* workloads, the
   parent-side copy-overhead-share instrumentation, the Kalibera–Jones
   statistics driver, the CSV + classification worksheet, and lever D
   wired behind a flag in the real path. The larger, separate half of
   #1472 that feeds #1474. **Harness landed** in `benchmarks/gate/` (see
   `benchmarks/gate/README.md`): the six workloads + controls, the real-
   path `share` counters (`src/channel_instrument.zig` →
   `src/shared_channel.zig`), levers `none`/`c`, and the K–J driver
   emitting the §6 CSV, all locally piloted on macOS aarch64. Still open
   there: **lever D in the real path** (the gate cells are `C+D`, so the
   gate is blocked until it lands), the frozen two-machine §4 collection,
   and the worksheet fill-in.
