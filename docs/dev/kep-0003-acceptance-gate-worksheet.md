# KEP-0003 acceptance-gate classification worksheet (kaappi#1474)

**Status: COMPLETE — both reference machines collected** (macOS aarch64
2026-07-15, Linux x86_64 2026-07-15). This is the §6 reading instrument.
Both machines read **4 Between** independently, so per §5's cross-machine
rule the combined classification is Between **by agreement**, not merely
by the "one machine reading Between forces the combined result" fallback.
Filled from the #1472 §6 CSV (`benchmarks/gate/classify.py` applies §5
mechanically).

## What this is, and the one rule that governs it

This worksheet operationalizes
[keps `research/benchmarks/README.md` §5–§6](https://github.com/kaappi/keps/blob/main/research/benchmarks/README.md)
— the pre-registered, **frozen** KEP-0003 acceptance gate. The thresholds
(25 %, 10 %, ≥ 2 in-place workloads, `w = 8`, sizes ≥ 1 MiB) were
registered 2026-07-12, before any Phase 7 code existed. The gate is *"a
reading, not an argument"*: you drop in the measured `share` values and
their bootstrap CIs, evaluate the boolean tests exactly as written, and
report what they say.

**No post-hoc adjustment.** Once #1472's data collection starts the
protocol is frozen; a defect discovered mid-run *voids the run* and
starts over rather than bending a threshold. This worksheet must not
introduce a threshold, a CI-bound choice, or a tie-break that isn't
derivable from §5.

### Progress (what has landed)

The whole gate harness landed (kaappi#1546 + the #1489 wakeup fix #1548):
the six `parallel-map` workloads + controls (`benchmarks/gate/gate-harness.scm`),
the parent-side `share` instrumentation (`T_submit_copy` + `T_result_copy` +
`T_reassembly`) in the real `shared_channel.zig` path, lever **D** wired behind
`-Dchannel-instrument`, and the Kalibera–Jones driver
(`benchmarks/gate/run-gate.py`) emitting the §6 CSV. The frozen protocol was
amended pre-freeze (keps#22: FO-TREE vector nodes, lever-D bytevector scope,
IP-MATMUL capped at 64 KiB/1 MiB).

**macOS aarch64 collected** (commit `b6d349c0`, 2026-07-15): 920 launches, 0
failures, K-J floor 20 × 10, w = 8, both levers. Filled below.

**Linux x86_64 collected** (commit `807fd64a`, 2026-07-16): dedicated
8-physical-core x86_64 droplet (DigitalOcean `s-8vcpu-16gb-intel`, confirmed
via `lscpu` — 1 socket, 8 cores/socket, no SMT), K-J floor 20 × 10, w = 8,
both levers. One amendment: FO-DIGEST's 64 MiB cell (both levers) was
excluded — a direct timing probe measured ~74–82 s/iteration for that cell
on this hardware (vs. ~13 s on the macOS reference), which alone would have
added roughly 10 hours to the run. This mirrors the protocol's existing
IP-MATMUL precedent (largest size infeasible on some hardware) and does not
touch the classification: FO-DIGEST is compute-dominated and reads
`share` well under 2% at every size collected on both machines. Filled
below.

## How to fill it in

For every cell, read `share_mean`, `share_ci95_lo`, `share_ci95_hi` from
the §6 CSV row matching `(machine, workload, size_bytes, workers=8,
levers)`. Enter them as `mean [lo, hi]` in percent. Then evaluate the
three rule tests per machine, combine across machines, and read the
outcome. Fill the run-metadata block from the CSV header / results file.

The gate is decided on the **copy+reassembly overhead `share`** at
`w = 8` only. Speedup, RSS, and envelope-bytes columns of the CSV are
recorded for context but **do not enter any rule**.

---

## Run metadata (fill from the results file)

| Field | macOS aarch64 | Linux x86_64 |
|-------|---------------|--------------|
| `kaappi` commit | `b6d349c0` | `807fd64a` |
| protocol commit (keps) | `af421900` | `af421900` (unchanged) |
| OS / kernel version | macOS 26.5.2 (Darwin arm64) | Ubuntu 24.04 LTS, kernel 6.8 (x86_64) |
| CPU, physical cores (SMT) | Apple Silicon, 12 physical (no SMT) | DO-Premium-Intel, dedicated vCPU, 8 physical, 1 socket (no SMT) |
| power / performance profile | AC power, default | cloud dedicated-vCPU droplet, default |
| K–J counts (invocations × iterations) achieved | 20 × 10 (floor); serial 5 × 5; warmup 2 | 20 × 10 (floor); serial 5 × 5; warmup 2 (FO-DIGEST 64 MiB excluded — see Amendments) |
| CI method (bootstrap over invocation means) | bootstrap 10 000 over invocation means | bootstrap 10 000 over invocation means |
| date collected | 2026-07-15 | 2026-07-15 |

Both machines require ≥ 8 physical cores for `w = 8` (§4.6) — macOS has 12,
Linux has 8 (confirmed via `lscpu`: 1 socket, 8 cores/socket, 1 thread/core).
Data-collection start (freeze point): **2026-07-14** (macOS run launch).

---

## Data tables — `share` at `w = 8`, as `mean % [ci95_lo, ci95_hi]`

Two lever settings enter the rules: **`C+D`** (gate/Erlang tests) and
**`none`** (Absent test). Sizes are the envelope-side dominant-payload
bytes (§1). One pair of tables per machine.

### Machine 1 — macOS aarch64

**Levers `C+D`** (feeds Rule 1 Racket + Rule 2 Erlang)

| workload | 64 KiB | 1 MiB | 8 MiB | 64 MiB |
|----------|--------|-------|-------|--------|
| IP-BAND   | 6.2 [6.1, 6.2] | 3.9 [3.8, 3.9] | 4.5 [4.5, 4.6] | 4.5 [4.4, 4.5] |
| IP-MAP    | 25.2 [25.0, 25.5] | 21.5 [21.4, 21.6] | 23.2 [22.9, 23.4] | 26.0 [25.7, 26.3] |
| IP-MATMUL | 2.4 [2.4, 2.4] | 0.6 [0.6, 0.6] | N/A | N/A |
| FO-DIGEST | 0.6 [0.5, 0.7] | 0.4 [0.4, 0.4] | 0.4 [0.4, 0.4] | 0.3 [0.3, 0.4] |
| FO-TREE   | 66.3 [65.8, 66.8] | 69.9 [69.6, 70.2] | 69.6 [69.1, 70.1] | 72.4 [71.7, 73.0] |
| FO-SLICE  | 46.3 [45.8, 46.8] | 52.7 [52.5, 52.8] | 55.3 [55.0, 55.6] | 57.0 [56.9, 57.2] |

**Levers `none`** (feeds Rule 3 Absent)

| workload | 64 KiB | 1 MiB | 8 MiB | 64 MiB |
|----------|--------|-------|-------|--------|
| IP-BAND   | 6.4 [6.2, 6.6] | 4.2 [4.1, 4.2] | 4.8 [4.7, 4.8] | 4.7 [4.7, 4.7] |
| IP-MAP    | 25.2 [24.9, 25.4] | 21.4 [21.3, 21.6] | 23.3 [23.0, 23.4] | 26.0 [25.7, 26.3] |
| IP-MATMUL | 2.4 [2.4, 2.4] | 0.6 [0.6, 0.6] | N/A | N/A |
| FO-DIGEST | 0.4 [0.4, 0.4] | 0.3 [0.3, 0.4] | 0.3 [0.3, 0.3] | 0.3 [0.3, 0.3] |
| FO-TREE   | 66.4 [65.9, 66.9] | 69.6 [69.2, 70.0] | 70.0 [69.6, 70.4] | 72.9 [72.4, 73.4] |
| FO-SLICE  | 46.0 [45.2, 46.6] | 52.7 [52.4, 52.9] | 55.5 [54.9, 56.3] | 57.0 [56.9, 57.1] |

*(IP-MATMUL 8/64 MiB are N/A per the keps#22 amendment — interpreted O(M³)
compute makes them infeasible/contaminated.)*

### Machine 2 — Linux x86_64

**Levers `C+D`**

| workload | 64 KiB | 1 MiB | 8 MiB | 64 MiB |
|----------|--------|-------|-------|--------|
| IP-BAND   | 7.9 [6.9, 9.2] | 3.7 [3.5, 3.9] | 3.4 [3.2, 3.6] | 3.6 [3.4, 3.7] |
| IP-MAP    | 27.8 [26.0, 29.4] | 22.7 [21.6, 23.7] | 27.6 [26.6, 28.7] | 26.8 [26.2, 27.4] |
| IP-MATMUL | 3.5 [3.4, 3.7] | 0.8 [0.8, 0.8] | N/A | N/A |
| FO-DIGEST | 1.5 [1.4, 1.5] | 1.2 [1.2, 1.3] | 1.2 [1.2, 1.3] | N/A¹ |
| FO-TREE   | 71.8 [66.0, 75.4] | 75.4 [74.8, 76.1] | 76.9 [76.4, 77.5] | 78.6 [78.2, 79.0] |
| FO-SLICE  | 44.9 [43.4, 46.3] | 52.3 [49.1, 54.8] | 55.4 [53.7, 57.0] | 64.6 [64.0, 65.1] |

**Levers `none`**

| workload | 64 KiB | 1 MiB | 8 MiB | 64 MiB |
|----------|--------|-------|-------|--------|
| IP-BAND   | 8.0 [7.6, 8.3] | 4.7 [4.4, 5.0] | 4.8 [4.6, 5.1] | 5.1 [5.0, 5.3] |
| IP-MAP    | 27.7 [25.4, 30.0] | 21.8 [21.0, 22.5] | 26.9 [26.1, 27.7] | 26.5 [26.1, 26.9] |
| IP-MATMUL | 3.6 [3.4, 3.8] | 0.8 [0.7, 0.8] | N/A | N/A |
| FO-DIGEST | 0.8 [0.8, 0.9] | 0.8 [0.8, 0.9] | 0.9 [0.8, 0.9] | N/A¹ |
| FO-TREE   | 73.6 [72.8, 74.4] | 76.3 [75.4, 77.2] | 77.0 [76.4, 77.7] | 78.7 [78.2, 79.1] |
| FO-SLICE  | 44.5 [42.6, 46.2] | 53.9 [51.3, 55.9] | 56.0 [54.6, 57.3] | 65.3 [64.6, 66.0] |

*(IP-MATMUL 8/64 MiB are N/A per the keps#22 amendment, same as macOS.
¹FO-DIGEST 64 MiB is N/A on Linux only, per the pre-run amendment documented
above and in `gate-linux-x86_64-metadata.txt` — excluded for cost, not
protocol infeasibility; it does not affect any rule, since FO-DIGEST is
compute-dominated and reads well under 2% at every collected size on both
machines.)*

---

## Rule tests (evaluate per machine)

Each rule names the lever setting, the exact cells, the comparison, and
**which CI bound** it reads — the bound is what makes each `≥`/`<`
*statistically resolved* rather than a point-estimate graze (§5). A
threshold crossing whose CI straddles it satisfies **no** rule and lands
in Rule 4 (Between).

### Rule 1 — Racket-shaped (KEP-0003 proceeds)

> With levers **`C+D`**, at least **2 of the 3 `IP-*`** workloads have
> `share ≥ 25 %` at **any** size ≥ 1 MiB, with the **CI lower bound**
> clearing: `share_ci95_lo ≥ 25 %`.

Per IP workload, PASS if *any* size in {1 MiB, 8 MiB, 64 MiB} (64 KiB is
excluded — must be ≥ 1 MiB) has `ci95_lo ≥ 25 %` in the `C+D` table.

| machine | IP-BAND pass? | IP-MAP pass? | IP-MATMUL pass? | # pass | Rule 1 (≥ 2)? |
|---------|:---:|:---:|:---:|:---:|:---:|
| macOS aarch64 | ✗ (max ci_lo 4.5) | ✓ (64 MiB, ci_lo 25.7) | ✗ (0.6) | 1 | ✗ **no** (need ≥ 2) |
| Linux x86_64  | ✗ (max ci_lo 3.5) | ✓ (8 & 64 MiB, ci_lo 26.6/26.2) | ✗ (0.8) | 1 | ✗ **no** (need ≥ 2) |

### Rule 2 — Erlang-shaped (KEP-0003 rejected → Alternative 1)

> With levers **`C+D`**, **every** gate and supporting cell (all 6
> `IP-*`/`FO-*` workloads × all 4 sizes, `w = 8`) has `share < 10 %`,
> with the **CI upper bound** below: `share_ci95_hi < 10 %` for all 24
> cells.

(With IP-MATMUL capped at two sizes, 22 cells are present on macOS, not 24;
on Linux, FO-DIGEST's additional 64 MiB exclusion (see Amendments) leaves 21.
The test is over all present cells on each machine.)

| machine | all `C+D` cells `ci95_hi < 10 %`? | Rule 2? |
|---------|:---:|:---:|
| macOS aarch64 | ✗ (IP-MAP, FO-TREE, FO-SLICE all ≥ 10) | ✗ **no** |
| Linux x86_64  | ✗ (IP-MAP, FO-TREE, FO-SLICE all ≥ 10) | ✗ **no** |

### Rule 3 — Absent (reject both KEP-0003 and Alternative 1)

> Even with levers **`none`**, **no** `IP-*`/`FO-*` cell (all 6 × all 4
> sizes) reaches `share ≥ 10 %`. Read as the resolved mirror of Rule 2 at
> the `none` lever: `share_ci95_hi < 10 %` for all 24 `none` cells. (A
> cell that *straddles* 10 % is a CI-unresolved crossing → Rule 4, not
> Absent; requiring the **upper bound** below 10 % is the same
> resolved-crossing discipline Rule 2 uses.)

| machine | all `none` cells `ci95_hi < 10 %`? | Rule 3? |
|---------|:---:|:---:|
| macOS aarch64 | ✗ (IP-MAP, FO-TREE, FO-SLICE all ≥ 10) | ✗ **no** |
| Linux x86_64  | ✗ (IP-MAP, FO-TREE, FO-SLICE all ≥ 10) | ✗ **no** |

### Rule 4 — Between (stays gated)

Anything else, **including any CI-unresolved threshold crossing** (a cell
whose CI straddles 25 % or 10 % such that no far-bound test resolves).
This is the catch-all; it needs no test of its own.

---

## Per-machine outcome (mechanical combination)

The three rule conditions are mutually exclusive except that Rule 3
(Absent) nests inside Rule 2 (Erlang): `share` is monotone in the levers
(`C+D` ≤ `none` cell-by-cell, since the levers only remove copy work), so
if every `none` cell is resolved below 10 % then every `C+D` cell is too.
When both could read true, **Absent wins** — it is the stronger claim
(copying is negligible even with no elision) and its consequence rejects
Alternative 1 as well. Rule 1 (Racket) excludes both by the same
monotonicity. Hence the fixed precedence:

```
outcome(machine) =
    Rule1 (Racket)  if  ≥ 2 of 3 IP-* pass the C+D lower-bound test
  else Rule3 (Absent) if  all 24 none cells have ci95_hi < 10 %
  else Rule2 (Erlang) if  all 24 C+D  cells have ci95_hi < 10 %
  else Rule4 (Between)
```

| machine | Rule 1 | Rule 3 | Rule 2 | → outcome |
|---------|:---:|:---:|:---:|:---|
| macOS aarch64 | ✗ | ✗ | ✗ | **4 Between (stays gated)** |
| Linux x86_64  | ✗ | ✗ | ✗ | **4 Between (stays gated)** |

## Combined outcome (two-machine agreement — required)

> The classification stands only if **both machines agree**. Disagreement
> ⇒ outcome **4 (Between, stays gated)**, with both datasets published — a
> demand shape on one microarchitecture only is not enough to carve out
> the GC model (§5 cross-machine rule).

```
combined =
    outcome(macOS)  if  outcome(macOS) == outcome(Linux)
  else Between (4)          # disagreement ⇒ stays gated, publish both
```

**Combined classification: 4 Between (stays gated).** Both machines are now
in: macOS aarch64 reads **4 Between**, and Linux x86_64 independently reads
**4 Between** too — the same failure shape on a heterogeneous
Apple-Silicon part and a homogeneous 8-core x86_64 part. Rule 1 falls one
workload short on both machines (only IP-MAP clears the 25% CI-lower bound;
IP-BAND and IP-MATMUL are both compute/reassembly-bound on both machines),
and Rules 2/3 fail on both for the identical three offenders (IP-MAP,
FO-TREE, FO-SLICE, all far above the 10% upper bound). Before this run,
the combined outcome was already forced to Between by the cross-machine
rule regardless of what Linux showed (one machine reading Between makes
agreement-or-disagreement both resolve to Between) — but the two machines
turning out to *agree* is a stronger result than that logical fallback: it's
a genuine cross-machine confirmation of the same demand shape, not just an
unfalsifiable classification. KEP-0003 therefore **stays Draft (gated)**.
The protocol's default action for this outcome is to leave kaappi#1474 open
as a placeholder for the revisit trigger; the maintainer closed it anyway on
2026-07-16 as an explicit call (issuecomment-4987953896) once the dataset
and this worksheet were complete. The trigger itself is unaffected by that
housekeeping choice and remains the thing to watch for: real
`kaappi-examples` traces with an `IP-*`-shaped hot loop.

### Reading (both machines) — what the numbers say beyond the verdict

- **Copy is clearly a real cost, just not in the Racket shape, on either
  machine.** IP-MAP (22–28%), FO-SLICE (45–65%), and FO-TREE (66–79%) spend
  a large, CI-resolved fraction of wall time in copy+reassembly on both
  macOS and Linux. What fails Rule 1 is narrow on both: only **one** in-place
  workload (IP-MAP) clears the 25% lower bound, and only at the larger sizes;
  IP-BAND (≈3–8%) and IP-MATMUL (≈0.6–3.5%) are compute/reassembly-bound on
  both machines. Two-of-three is the bar, and one cleared it — on both an
  Apple-Silicon part and a homogeneous 8-core x86_64 part.
- **Lever D barely moves the needle (`cd` ≈ `none`) on either machine.** D
  elides only *bytevector* copies, but every high-share workload here is
  byte-opaque — flonum vectors (IP-MAP, FO-SLICE) and a record/vector tree
  (FO-TREE) — so D is a no-op on exactly the payloads where copy dominates.
  That is precisely the pre-KEP-0003 "walk tax": a refcounted byte side-heap
  cannot share a NaN-boxed flonum vector. The one bytevector in-place
  workload (IP-BAND) is render/reassembly-bound, so D's zero-copy receive
  shaves only a few points on both machines.
- **The shape is architecture-independent.** The same three workloads
  (IP-MAP, FO-TREE, FO-SLICE) are the offenders against Rules 2/3 on both
  machines, and the same single workload (IP-MAP) is the only Rule 1
  near-miss on both. This isn't one microarchitecture's quirk — the demand
  shape replicates on both a heterogeneous P/E-core Apple Silicon part and a
  homogeneous dedicated-vCPU x86_64 part, which is exactly the kind of
  agreement the cross-machine rule was designed to detect.
- **Implication for KEP-0003.** The data neither clears the Racket bar nor
  shows copy to be negligible, on either machine; it shows copy cost
  concentrated in flonum-vector/tree payloads that byte-level sharing
  (lever D) cannot touch — the case flat f64 storage (KEP-0003) is meant to
  address — but not in ≥ 2 of the 3 registered in-place workloads. Hence
  "stays gated, revisit with field traces," not "proceed."

---

## Outcome → action (from §5 / #1474 Acceptance)

Whichever row the combined outcome selects is the action to take; the
numbers and this filled worksheet attach to kaappi#1474 *before* the
status PR.

| Outcome | KEP-0003 status PR (keps repo) | kaappi issue actions |
|---------|-------------------------------|----------------------|
| **1 Racket** | KEP-0003 → **Accepted** (data linked) | split [#1475](https://github.com/kaappi/kaappi/issues/1475) into real phase sub-issues |
| **2 Erlang** | KEP-0003 → **Rejected** (data linked) | open the Alternative-1 issue (refcounted immutable payloads) under KEP-0002 UQ 1; close #1475 unworked |
| **3 Absent** | KEP-0003 → **Rejected** (data linked) | close both #1475 **and** the Alternative-1 line, with the data linked |
| **4 Between** | KEP-0003 stays **Draft** (gated) | #1474 stays open; document the revisit trigger: real `kaappi-examples` traces with an `IP-*`-shaped hot loop |

*(This run landed outcome 4. The "#1474 stays open" cell above is the
protocol's default action; in practice the maintainer closed #1474 on
2026-07-16 once this worksheet was complete, rather than leaving it open —
see the note at the end of the Combined outcome section. The revisit
trigger stands regardless of the issue's open/closed state.)*

---

## Provenance

- Protocol (frozen): keps `research/benchmarks/README.md` §5–§6,
  registered 2026-07-12; gate amendment kaappi/keps#14 (merged).
- Consumes: kaappi#1472 §6 CSV (`machine, workload, size_bytes, workers,
  levers, invocations, iterations, E_mean_ms, E_ci95_lo, E_ci95_hi,
  share_mean, share_ci95_lo, share_ci95_hi, S_ms, speedup, rss_peak_mib,
  envelope_peak_mib`).
- Feeds: the KEP-0003 status decision (kaappi#1474 → keps status PR).
