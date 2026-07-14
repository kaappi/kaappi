# KEP-0003 acceptance-gate classification worksheet (kaappi#1474)

**Status: SCAFFOLD — awaiting the #1472 gate dataset.** This is the §6
reading instrument, built from the frozen protocol *before* the data
exists so the eventual classification is a mechanical reading. Every
number slot below is an empty placeholder (`·`); every derived cell is
`☐ pending`. **Do not fill this in from anything but the #1472 §6 CSV.**

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

### Blocker (why this is still a scaffold)

The gate consumes the #1472 gate dataset, which **does not exist yet**.
What has landed for Phase 7 is only the P3 envelope-cost *eyeball*
benchmark (`src/bench_channel.zig`, kaappi#1535 — see
[`kep-0002-phase7-envelope-benchmarks.md`](kep-0002-phase7-envelope-benchmarks.md)):
the A/B/C/D matrix over fixnum / pair / string / bytevector / chain
shapes, single-run, macOS only. That decides *ship C / B-pending /
D-deferred*; it is **not** the gate campaign. Missing before this
worksheet can be filled:

- the `IP-BAND` / `IP-MAP` / `IP-MATMUL` and `FO-DIGEST` / `FO-TREE` /
  `FO-SLICE` `parallel-map` workloads;
- the parent-side `share` instrumentation
  (`T_submit_copy` + `T_result_copy` + `T_reassembly`) in the real path;
- lever **D** wired behind a flag in `src/shared_channel.zig` (not the
  `bench_channel.zig` stand-in) — *the gate cannot be evaluated until
  lever D exists behind its flag* (§2);
- the Kalibera–Jones statistics driver (≥ 20 invocations × ≥ 10
  iterations, bootstrap CIs, order/env randomization) emitting the §6
  CSV;
- runs on **both** reference machines (macOS aarch64 + Linux x86_64,
  ≥ 8 physical cores each).

All five are #1472's remaining "gate campaign" half (its Status item 5).
Until they produce the CSV, the cells below stay `·`.

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
| `kaappi` commit | `·` | `·` |
| protocol commit (keps) | `·` | `·` |
| OS / kernel version | `·` | `·` |
| CPU, physical cores (SMT) | `·` | `·` |
| power / performance profile | `·` | `·` |
| K–J counts (invocations × iterations) achieved | `·` | `·` |
| CI method (bootstrap over invocation means) | `·` | `·` |
| date collected | `·` | `·` |

Both machines require ≥ 8 physical cores for `w = 8` (§4.6). Record the
data-collection start (freeze point) here: `·`.

---

## Data tables — `share` at `w = 8`, as `mean % [ci95_lo, ci95_hi]`

Two lever settings enter the rules: **`C+D`** (gate/Erlang tests) and
**`none`** (Absent test). Sizes are the envelope-side dominant-payload
bytes (§1). One pair of tables per machine.

### Machine 1 — macOS aarch64

**Levers `C+D`** (feeds Rule 1 Racket + Rule 2 Erlang)

| workload | 64 KiB | 1 MiB | 8 MiB | 64 MiB |
|----------|--------|-------|-------|--------|
| IP-BAND   | `·` | `·` | `·` | `·` |
| IP-MAP    | `·` | `·` | `·` | `·` |
| IP-MATMUL | `·` | `·` | `·` | `·` |
| FO-DIGEST | `·` | `·` | `·` | `·` |
| FO-TREE   | `·` | `·` | `·` | `·` |
| FO-SLICE  | `·` | `·` | `·` | `·` |

**Levers `none`** (feeds Rule 3 Absent)

| workload | 64 KiB | 1 MiB | 8 MiB | 64 MiB |
|----------|--------|-------|-------|--------|
| IP-BAND   | `·` | `·` | `·` | `·` |
| IP-MAP    | `·` | `·` | `·` | `·` |
| IP-MATMUL | `·` | `·` | `·` | `·` |
| FO-DIGEST | `·` | `·` | `·` | `·` |
| FO-TREE   | `·` | `·` | `·` | `·` |
| FO-SLICE  | `·` | `·` | `·` | `·` |

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
| macOS aarch64 | ☐ | ☐ | ☐ | `·` | ☐ pending |
| Linux x86_64  | ☐ | ☐ | ☐ | `·` | ☐ pending |

### Rule 2 — Erlang-shaped (KEP-0003 rejected → Alternative 1)

> With levers **`C+D`**, **every** gate and supporting cell (all 6
> `IP-*`/`FO-*` workloads × all 4 sizes, `w = 8`) has `share < 10 %`,
> with the **CI upper bound** below: `share_ci95_hi < 10 %` for all 24
> cells.

| machine | all 24 `C+D` cells `ci95_hi < 10 %`? | Rule 2? |
|---------|:---:|:---:|
| macOS aarch64 | ☐ | ☐ pending |
| Linux x86_64  | ☐ | ☐ pending |

### Rule 3 — Absent (reject both KEP-0003 and Alternative 1)

> Even with levers **`none`**, **no** `IP-*`/`FO-*` cell (all 6 × all 4
> sizes) reaches `share ≥ 10 %`. Read as the resolved mirror of Rule 2 at
> the `none` lever: `share_ci95_hi < 10 %` for all 24 `none` cells. (A
> cell that *straddles* 10 % is a CI-unresolved crossing → Rule 4, not
> Absent; requiring the **upper bound** below 10 % is the same
> resolved-crossing discipline Rule 2 uses.)

| machine | all 24 `none` cells `ci95_hi < 10 %`? | Rule 3? |
|---------|:---:|:---:|
| macOS aarch64 | ☐ | ☐ pending |
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
| macOS aarch64 | ☐ | ☐ | ☐ | ☐ pending |
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

**Combined classification: ☐ pending** (`·`)

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
