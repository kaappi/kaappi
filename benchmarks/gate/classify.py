#!/usr/bin/env python3
"""KEP-0002 Phase 7 gate classifier (kaappi#1472 → kaappi#1474).

Reads one or more §6 gate CSVs (one per machine) and applies the frozen §5 rule
set mechanically — the "reading, not an argument" the worksheet
(docs/dev/kep-0003-acceptance-gate-worksheet.md) calls for. Emits, per machine:
the `share` data tables at w=8 (levers C+D and none) as `mean% [lo, hi]`, the
Rule 1/2/3 evaluations with the exact CI bound each uses, and the per-machine
outcome; then the combined two-machine outcome.

The gate is decided on copy+reassembly overhead `share` at w=8 ONLY (§5);
speedup/RSS/envelope columns are context, not inputs.

Rules (verbatim thresholds, from the frozen protocol §5):
  R1 Racket : with C+D, >=2 of 3 IP-* have share_ci95_lo >= 25 at some size >=1 MiB.
  R2 Erlang : with C+D, every gate+supporting cell has share_ci95_hi < 10.
  R3 Absent : with none, every cell has share_ci95_hi < 10 (resolved mirror of R2).
  Precedence: R1 else R3 else R2 else R4 (Between). Combined: both machines must
  agree, else Between.

Usage: classify.py machine1.csv [machine2.csv ...]
"""

import csv
import sys

IP = ["ip-band", "ip-map", "ip-matmul"]
FO = ["fo-digest", "fo-tree", "fo-slice"]
GATE_WORKLOADS = IP + FO
SIZES = [65536, 1048576, 8388608, 67108864]
SIZE_LABEL = {65536: "64 KiB", 1048576: "1 MiB", 8388608: "8 MiB", 67108864: "64 MiB"}
WL_LABEL = {w: w.upper() for w in GATE_WORKLOADS}
RACKET_THRESHOLD = 25.0
ERLANG_THRESHOLD = 10.0
MIN_RACKET_SIZE = 1048576  # >= 1 MiB


def load(path):
    """Return {(workload,size,lever): row} for w=8 rows only."""
    cells = {}
    machine = None
    with open(path) as fh:
        for row in csv.DictReader(fh):
            if int(row["workers"]) != 8:
                continue
            machine = row["machine"]
            cells[(row["workload"], int(row["size_bytes"]), row["levers"])] = {
                "mean": float(row["share_mean"]),
                "lo": float(row["share_ci95_lo"]),
                "hi": float(row["share_ci95_hi"]),
            }
    return machine, cells


def fmt(cell):
    if cell is None:
        return "N/A"
    return f"{cell['mean']:.1f} [{cell['lo']:.1f}, {cell['hi']:.1f}]"


def data_table(cells, lever):
    lines = [f"**Levers `{lever}`** — share % [ci95_lo, ci95_hi] at w=8", ""]
    lines.append("| workload | " + " | ".join(SIZE_LABEL[s] for s in SIZES) + " |")
    lines.append("|" + "---|" * (len(SIZES) + 1))
    for wl in GATE_WORKLOADS:
        row = [WL_LABEL[wl]]
        for s in SIZES:
            row.append(fmt(cells.get((wl, s, lever))))
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def rule1_racket(cells):
    """>=2 of 3 IP-* with C+D have ci95_lo >= 25 at some size >= 1 MiB."""
    passed = []
    for wl in IP:
        ok = any(
            (c := cells.get((wl, s, "cd"))) is not None and c["lo"] >= RACKET_THRESHOLD
            for s in SIZES if s >= MIN_RACKET_SIZE
        )
        passed.append((wl, ok))
    n = sum(1 for _, ok in passed if ok)
    return n >= 2, passed, n


def all_cells_hi_below(cells, lever, thresh):
    """True iff every present gate+supporting cell at `lever` has ci95_hi < thresh."""
    present = [(wl, s) for wl in GATE_WORKLOADS for s in SIZES
              if (wl, s, lever) in cells]
    offenders = [(wl, s) for (wl, s) in present if cells[(wl, s, lever)]["hi"] >= thresh]
    return len(offenders) == 0, offenders, len(present)


def classify(cells):
    r1, r1_detail, r1_n = rule1_racket(cells)
    r2, r2_off, r2_n = all_cells_hi_below(cells, "cd", ERLANG_THRESHOLD)
    r3, r3_off, r3_n = all_cells_hi_below(cells, "none", ERLANG_THRESHOLD)
    # Precedence (§5): Racket, else Absent, else Erlang, else Between.
    if r1:
        outcome = "1 Racket (KEP-0003 proceeds)"
    elif r3:
        outcome = "3 Absent (reject KEP-0003 and Alternative 1)"
    elif r2:
        outcome = "2 Erlang (KEP-0003 rejected → Alternative 1)"
    else:
        outcome = "4 Between (stays gated)"
    return {
        "r1": r1, "r1_detail": r1_detail, "r1_n": r1_n,
        "r2": r2, "r2_off": r2_off, "r2_n": r2_n,
        "r3": r3, "r3_off": r3_off, "r3_n": r3_n,
        "outcome": outcome,
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    results = {}
    for path in sys.argv[1:]:
        machine, cells = load(path)
        print(f"\n{'='*70}\nMACHINE: {machine}   ({path})\n{'='*70}\n")
        print(data_table(cells, "cd") + "\n")
        print(data_table(cells, "none") + "\n")
        c = classify(cells)
        print("Rule 1 (Racket, C+D, ci95_lo ≥ 25 at ≥1 MiB, need ≥2 of 3 IP-*):")
        for wl, ok in c["r1_detail"]:
            print(f"    {wl:<11} {'PASS' if ok else 'fail'}")
        print(f"    → {c['r1_n']}/3 pass  ⇒  Rule 1 {'MET' if c['r1'] else 'not met'}")
        print(f"Rule 2 (Erlang, C+D, all {c['r2_n']} cells ci95_hi < 10): "
              f"{'MET' if c['r2'] else 'not met'}"
              + ("" if c["r2"] else f"  (offenders: {c['r2_off']})"))
        print(f"Rule 3 (Absent, none, all {c['r3_n']} cells ci95_hi < 10): "
              f"{'MET' if c['r3'] else 'not met'}"
              + ("" if c["r3"] else f"  (offenders: {c['r3_off']})"))
        print(f"\n  OUTCOME ({machine}): {c['outcome']}")
        results[machine] = c["outcome"]

    if len(results) >= 2:
        outs = set(results.values())
        combined = list(outs)[0] if len(outs) == 1 else "4 Between (cross-machine disagreement ⇒ stays gated)"
        print(f"\n{'='*70}\nCOMBINED (both machines must agree): {combined}\n{'='*70}")
    else:
        print(f"\n(Only one machine supplied — combined classification needs both; "
              f"per §5 it stays gated until the second machine agrees.)")


if __name__ == "__main__":
    main()
