# KEP-0003 acceptance-gate classification worksheet (kaappi#1474)

**Status: PARTIAL — macOS aarch64 filled (2026-07-15); Linux x86_64
pending.** This is the §6 reading instrument. The macOS reference machine
has been collected and read below; the second machine (Linux x86_64) is a
follow-up, and per §5's cross-machine rule the **combined** classification
stays gated until both machines are in and agree. The macOS machine's own
per-machine outcome is **4 Between** (see the rule tests). Filled only from
the #1472 §6 CSV (`benchmarks/gate/classify.py` applies §5 mechanically).

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

**Linux x86_64 pending**: the second reference machine is a follow-up (the
DigitalOcean droplet path was not driveable from the collecting session — MCP
lifecycle-only, no shell). Run the same `run-gate.py` command on any x86_64
≥ 8-physical-core box at commit `b6d349c0` and drop its CSV into
`benchmarks/gate/classify.py` alongside the macOS CSV to complete the combined
classification. Until then the combined outcome stays gated (§5 cross-machine
rule).

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
| `kaappi` commit | `b6d349c0` | `·` (pending) |
| protocol commit (keps) | `af421900` | `·` |
| OS / kernel version | macOS 26.5.2 (Darwin arm64) | `·` |
| CPU, physical cores (SMT) | Apple Silicon, 12 physical (no SMT) | `·` |
| power / performance profile | AC power, default | `·` |
| K–J counts (invocations × iterations) achieved | 20 × 10 (floor); serial 5 × 5; warmup 2 | `·` |
| CI method (bootstrap over invocation means) | bootstrap 10 000 over invocation means | `·` |
| date collected | 2026-07-15 | `·` |

Both machines require ≥ 8 physical cores for `w = 8` (§4.6) — macOS has 12.
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
| IP-BAND   | `·` | `·` | `·` | `·` |
| IP-MAP    | `·` | `·` | `·` | `·` |
| IP-MATMUL | `·` | `·` | `·` | `·` |
| FO-DIGEST | `·` | `·` | `·` | `·` |
| FO-TREE   | `·` | `·` | `·` | `·` |
| FO-SLICE  | `·` | `·` | `·` | `·` |

**Levers `none`**

| workload | 64 KiB | 1 MiB | 8 MiB | 64 MiB |
|----------|--------|-------|-------|--------|
| IP-BAND   | `·` | `·` | `·` | `·` |
| IP-MAP    | `·` | `·` | `·` | `·` |
| IP-MATMUL | `·` | `·` | `·` | `·` |
| FO-DIGEST | `·` | `·` | `·` | `·` |
| FO-TREE   | `·` | `·` | `·` | `·` |
| FO-SLICE  | `·` | `·` | `·` | `·` |

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
| Linux x86_64  | ☐ | ☐ | ☐ | `·` | ☐ pending |

### Rule 2 — Erlang-shaped (KEP-0003 rejected → Alternative 1)

> With levers **`C+D`**, **every** gate and supporting cell (all 6
> `IP-*`/`FO-*` workloads × all 4 sizes, `w = 8`) has `share < 10 %`,
> with the **CI upper bound** below: `share_ci95_hi < 10 %` for all 24
> cells.

(With IP-MATMUL capped at two sizes, 22 cells are present, not 24; the test
is over all present cells.)

| machine | all `C+D` cells `ci95_hi < 10 %`? | Rule 2? |
|---------|:---:|:---:|
| macOS aarch64 | ✗ (IP-MAP, FO-TREE, FO-SLICE all ≥ 10) | ✗ **no** |
| Linux x86_64  | ☐ | ☐ pending |

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
| Linux x86_64  | ☐ | ☐ pending |

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
| Linux x86_64  | ☐ | ☐ | ☐ | ☐ pending |

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

**Combined classification: 4 Between (stays gated).** macOS aarch64 reads
**4 Between**. The combined rule is `outcome(macOS) if the two machines
agree, else Between`. Because macOS is Between, the combined result is
Between in *every* case: if Linux also reads Between the machines agree on
Between; if Linux reads anything else they disagree, which the cross-machine
rule *also* resolves to Between. So the Linux run **cannot move the gate off
Between** — the outcome is already determined. Linux is still worth
collecting for a complete, published two-machine dataset (and to confirm the
shape holds on homogeneous cores), but it is confirmation, not a swing vote.
KEP-0003 therefore **stays Draft (gated)**; #1474 stays open with the
revisit trigger documented (real `kaappi-examples` traces with an
`IP-*`-shaped hot loop).

### Reading (macOS) — what the numbers say beyond the verdict

- **Copy is clearly a real cost, just not in the Racket shape.** IP-MAP
  (21–26 %), FO-SLICE (46–57 %), and FO-TREE (66–72 %) spend a large,
  CI-resolved fraction of wall time in copy+reassembly. What fails Rule 1 is
  narrow: only **one** in-place workload (IP-MAP) clears the 25 % lower bound,
  and only at 64 MiB; IP-BAND (≈4–6 %) and IP-MATMUL (≈0.6–2 %) are
  compute-bound. Two-of-three is the bar, and one cleared it.
- **Lever D barely moves the needle (`cd` ≈ `none`).** D elides only
  *bytevector* copies, but every high-share workload here is byte-opaque —
  flonum vectors (IP-MAP, FO-SLICE) and a record/vector tree (FO-TREE) — so D
  is a no-op on exactly the payloads where copy dominates. That is precisely
  the pre-KEP-0003 "walk tax": a refcounted byte side-heap cannot share a
  NaN-boxed flonum vector. The one bytevector in-place workload (IP-BAND) is
  render/reassembly-bound, so D's zero-copy receive shaves only ~0.3 pts.
- **Implication for KEP-0003.** The data neither clears the Racket bar nor
  shows copy to be negligible; it shows copy cost concentrated in
  flonum-vector/tree payloads that byte-level sharing (lever D) cannot touch —
  the case flat f64 storage (KEP-0003) is meant to address — but not in ≥ 2 of
  the 3 registered in-place workloads. Hence "stays gated, revisit with field
  traces," not "proceed."

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

---

## Provenance

- Protocol (frozen): keps `research/benchmarks/README.md` §5–§6,
  registered 2026-07-12; gate amendment kaappi/keps#14 (merged).
- Consumes: kaappi#1472 §6 CSV (`machine, workload, size_bytes, workers,
  levers, invocations, iterations, E_mean_ms, E_ci95_lo, E_ci95_hi,
  share_mean, share_ci95_lo, share_ci95_hi, S_ms, speedup, rss_peak_mib,
  envelope_peak_mib`).
- Feeds: the KEP-0003 status decision (kaappi#1474 → keps status PR).
