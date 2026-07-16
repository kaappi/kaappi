# KEP-0002 Phase 7 gate campaign (kaappi#1472)

This directory holds the `parallel-map` gate-campaign harness: the half of
Phase 7 that produces the **copy + reassembly overhead `share`** dataset the
KEP-0003 acceptance gate (kaappi#1474) consumes. The other Phase 7 half — the
P3 A/B/C/D envelope micro-benchmark — lives in `src/bench_channel.zig` and is
decided independently (see `docs/dev/kep-0002-phase7-envelope-benchmarks.md`).

**The pre-registered, frozen protocol is normative:**
[keps `research/benchmarks/README.md`](https://github.com/kaappi/keps/blob/main/research/benchmarks/README.md).
Everything here implements it; where this harness adds an operational
definition the protocol left open, it is called out below and marked
**PRE-FREEZE** — legal to change only until data collection for the frozen run
starts. This harness has **not** started that frozen run; it is built and
locally piloted so the protocol implementation can be reviewed first.

## Files

| File | What it is |
|------|-----------|
| `gate-harness.scm` | Runs ONE cell — `(workload, size, workers, lever)` — for warmup + measured iterations, printing one machine-readable `ITER` line per measured iteration. |
| `run-gate.py` | Kalibera–Jones driver: launches the invocation level (fresh processes), randomizes order + env size, aggregates with bootstrap CIs, emits the §6 CSV + a table. |

The counters and elision levers live in the interpreter:
`src/channel_instrument.zig` (counters + lever flag), hooked into
`src/shared_channel.zig` (the real `send`/`receive` path), exposed to Scheme as
`%chan-instr-*` / `%elision-lever-set!` (`src/primitives_parallel.zig`, tagged
`.internal`).

## Build (required)

The binary **must** be built with the instrumentation compiled in, or every
copy counter reads 0 and the lever flag is inert (protocol §3 keeps them out of
the shipped default):

```
zig build -Dchannel-instrument=true
```

`run-gate.py` warns if it detects all-zero copy counters (wrong binary).

## Workloads (protocol §1)

Three in-place-shaped (the gate counts these), three read-only fan-out, two
controls. "Size" is always the envelope-side bytes of the dominant payload.

| Id | Payload | Shape realized here |
|----|---------|---------------------|
| `ip-band` | RGBA image, `bytevector` of `size` bytes (W=256, H=size/1024) | each worker renders a disjoint row band (per-pixel arithmetic) → fresh bytevector; parent `bytevector-copy!`s into the image. Result copy dominates. |
| `ip-map` | vector of `size/8` NaN-boxed flonums | task carries a pre-sliced chunk (copied in); worker computes `2.5·x+1`; parent `vector-copy!`s the transformed chunk into place. |
| `ip-matmul` | two M×M f64 matrices, `M=isqrt(size/16)` | tasks carry **A and B whole** (fan-in copy) + a row-block spec; worker computes a disjoint C row block; parent assembles. |
| `fo-digest` | `bytevector` of `size` bytes | task captures the **whole** payload (fan-out copy to every worker); worker checksums all of it; result is a fixnum pair. |
| `fo-tree` | balanced binary tree of `size/40` nodes, symbol tags | task captures the **whole** tree; worker counts nodes tagged `gamma`; result a fixnum. Symbol-heavy (doubles as the §1 symbol-table probe). |
| `fo-slice` | vector of `size/8` flonums | task captures the **whole** vector (the over-copying idiom) but sums only its own index range; result a flonum. |
| `c-empty` | — | pool round trip, empty task → reply. Control-plane floor. |
| `s:<id>` | — | single-thread, no-pool serial baseline `S` of each kernel. |

NaN-boxed flonums: Kaappi has no flat f64 storage pre-KEP-0003, so a flonum
vector of `size` bytes is `size/8` inline Values, and copying it walks all of
them — that walk tax is deliberately part of what is measured (§1).

### Self-containment rule

Every worker **task thunk** captures only fixnums/flonums/payload objects and
calls only built-in primitives — never a top-level procedure defined in the
harness. A closure that crosses a worker boundary and then calls a
separately-defined procedure can hang (kaappi#1520). Serial baselines never
cross a thread, so they are free to call shared kernels.

## Metrics (protocol §3)

```
share = (T_submit_copy + T_result_copy + T_reassembly) / E
```

- `T_submit_copy` — the parent's envelope build (`Envelope.create` → deepCopy)
  on the send path, from the threadlocal counter. Worker-side builds land in a
  worker threadlocal that is never read (§3's parent-side attribution).
- `T_result_copy` — the parent's deepCopy of a result out of a reply envelope.
- `T_reassembly` — bracketed explicitly around each parent-side
  `bytevector-copy!` / `vector-copy!` into the output object.
- `E` — wall time from the first `pool-submit` to the last reassembly copy;
  pool creation/teardown and payload construction are excluded (per-cell setup,
  amortized by reusing one pool + payload across a cell's iterations).
- `S` — the `s:<id>` serial-kernel time; `speedup = S / E` (reported, not
  gating).

Secondary (non-gating): child peak RSS (from `wait4`), peak live envelope bytes.

## Running

Pilot (validates the harness; 5 invocations × 20 iterations by default):

```
zig build -Dchannel-instrument=true
python3 benchmarks/gate/run-gate.py \
    --bin zig-out/bin/kaappi --mode pilot \
    --machine macos-aarch64 --cores 12 \
    --sizes 65536,1048576 --workers 8 --levers none,c \
    --out gate-pilot.csv
```

Full frozen run (per machine; floors 20 invocations × 10 iterations — set the
counts from the pilot's CI half-widths to hit the protocol's ±2% target):

```
python3 benchmarks/gate/run-gate.py \
    --bin zig-out/bin/kaappi --mode full \
    --machine macos-aarch64 --cores 12 \
    --sizes 65536,1048576,8388608,67108864 \
    --workers 1,2,4,8,24 --levers none,cd \
    --out gate-macos.csv
```

The driver shuffles the whole (cell × invocation) launch schedule under `--seed`
and exports a random-length `KAAPPI_GATE_PAD` env var per process (§4.3), leaves
ASLR on, and selects the lever at runtime on one binary (§4.4).

## Output (protocol §6)

`--out` is the §6 CSV:

```
machine, workload, size_bytes, workers, levers, invocations, iterations,
E_mean_ms, E_ci95_lo, E_ci95_hi, share_mean, share_ci95_lo, share_ci95_hi,
S_ms, speedup, rss_peak_mib, envelope_peak_mib
```

`share_*` are in **percent** (what the §5 rules and the kaappi#1474 worksheet
compare against 25 % / 10 %). CIs are 95 % bootstrap percentiles over invocation
means. Drop the `C+D` and `none` rows into
`docs/dev/kep-0003-acceptance-gate-worksheet.md` and the classification reads
out mechanically.

## Local pilot (VALIDATION ONLY — not gate data)

A bring-up pilot on macOS aarch64 (M-series, 12 cores), `w = 8`, levers
`none`/`c` (not the gate's `C+D` — lever D is unimplemented), sizes 64 KiB and
1 MiB (not up to 64 MiB), 3 invocations × 5 iterations (not the frozen
20 × 10). **These numbers judge the harness, not the design; they must not be
cited as the gate dataset.** They demonstrate the harness produces sensible,
well-differentiated, statistically-summarized `share` values:

| workload | share% @64 KiB | share% @1 MiB | shape |
|----------|---------------:|--------------:|-------|
| ip-band   | ~7  | ~4  | in-place, result copy modest at these sizes |
| ip-map    | ~26 | ~22 | copy-bound (chunk in + out + reassemble) |
| ip-matmul | ~2.6| ~0.7| compute-dominated (interpreted O(M³)) |
| fo-digest | ~0.4| ~0.3| compute-dominated (whole-payload checksum) |
| fo-tree   | ~67 | ~70 | symbol-heavy fan-out over-copy dominates |
| fo-slice  | ~48 | ~55 | whole-vector fan-out over-copy dominates |

Speedups came out sane (IP-* ≤ 8× with 8 workers; FO-* < 1× — the fan-out
idiom does redundant whole-payload work per worker, by design). The pilot also
exercised the driver's timeout handling: ~8 % of invocations hit the
kaappi#1489 hang and were recorded as `TIMEOUT` failures (see limitation 2).

## Levers (protocol §2)

- `none` — per-message envelopes exactly as `shared_channel.zig` ships.
- `c` — `none` + immediates (fixnum/boolean/char/flonum/nil) skip the envelope
  heap. Implemented.
- `cd` — `c` + a refcounted immutable side-heap for large **bytevectors**
  (kaappi#1472 lever D), implemented in the real path. A bytevector ≥ 4 KiB
  crossing a channel is snapshotted once into a `SharedBuffer`
  (`src/shared_buffer.zig`) and shared by refcount: zero-copy on receive,
  copy-on-write on mutation. This is the lever the gate's `C+D` cells require
  (§2). Two scope points to confirm before the frozen run:
  - **Bytevectors only.** Strings are a follow-up; flonum *vectors*
    (IP-MAP/IP-MATMUL/FO-SLICE) and the record/vector tree (FO-TREE) are
    byte-opaque, so D does not apply to them — that "walk tax" is exactly the
    pre-KEP-0003 reality §1 measures, and is what flat f64 storage (KEP-0003)
    would address. So at `C+D`, D helps the bytevector workloads (IP-BAND,
    FO-DIGEST) and correctly leaves the vector workloads at their `none` share.
  - **No source promotion.** D elides the zero-copy *receive* of a distinct
    payload and re-aliases an already-backed payload, but does not promote a
    plain *source* bytevector to shared on first send — so a fan-out of the same
    plain bytevector still snapshots per task envelope. This affects only
    bytevector fan-out (FO-DIGEST), which is compute-dominated (share < 1 %), so
    it does not change the gate classification. Add source promotion only if a
    bytevector fan-out workload ever proves copy-bound.

## Known limitations & PRE-FREEZE findings

These surfaced during harness bring-up and must be resolved or explicitly
adopted **before** the frozen run starts (once it starts, the protocol freezes):

1. **Lever D scope (bytevectors; no source promotion; strings deferred).**
   Lever D is implemented in the real path (see the Levers section), but two
   scoping decisions — bytevectors only, and no plain-source promotion for
   fan-out — should be explicitly adopted (or closed) before the frozen run.
   Neither changes the gate classification (the only affected workload,
   FO-DIGEST fan-out, is compute-dominated), but both are protocol-visible.

2. **Intermittent pool hang (kaappi#1489).** The cross-thread wakeup path can
   lose a wakeup and hang, at any submission count (probability grows with
   count). The chunked idiom here uses only `w` tasks per iteration, so it is
   rare, but it *does* occur. The driver bounds every invocation with
   `--timeout` and records a `TIMEOUT` as a failed invocation (excluded, warned)
   — a hang is not a "slow invocation is data" case. A clean frozen run wants
   kaappi#1489 fixed first, or a documented retry policy.

3. **FO-TREE uses vector nodes, not records.** §1 specifies
   `define-record-type` nodes. Records cannot cross a Kaappi channel and remain
   usable: `deepCopy` mints a fresh `RecordType` per envelope, so a copied
   instance no longer matches the top-level record type an accessor closes over
   (record-type identity is not interned the way symbols are). Nodes are 4-slot
   vectors `#(left right tag count)` here — same shape, same symbol-heaviness.
   Either adopt this deviation in a protocol PR, or preserve record-type
   identity across `deepCopy`, before the frozen run.

4. **IP-MATMUL compute cost.** The kernel is interpreted O(M³); at 64 MiB
   (M=2048) that is ~8.6 G multiply-adds and dominates wall time, biasing
   `ip-matmul`'s `share` down (honestly, but extremely). Confirm the top matmul
   size is acceptable — or cap it — before freezing.

5. **Exception-crossing fragility.** A worker task that *raises* sends the
   condition back through the reply channel (`guard` in `parallel.sld`);
   re-raising a cross-thread-copied error object was observed to panic
   ("incorrect alignment") in one bring-up case. Well-formed workloads never
   raise, so it does not affect measurement, but it is a latent robustness bug
   worth a separate issue.

## Status — campaign complete

The frozen §4 collection has run on **both** reference machines: macOS
aarch64 (commit `b6d349c0`, 920 launches, 0 failures) and Linux x86_64
(commit `807fd64a`, ~1000 launches, 0 failures; FO-DIGEST's 64 MiB cell
excluded on Linux only, see `results/gate-linux-x86_64-metadata.txt`).
Both machines independently classify **4 Between** — agreement, not just
the cross-machine rule's fallback. The gate worksheet
(`../../docs/dev/kep-0003-acceptance-gate-worksheet.md`) is fully filled;
kaappi#1489 (limitation 2) was fixed before either frozen run started, and
neither run hit a hang. kaappi#1474 (the gate decision issue) is closed;
KEP-0003 stays Draft, gated, with its revisit trigger documented in the
worksheet.
