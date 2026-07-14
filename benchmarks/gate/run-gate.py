#!/usr/bin/env python3
"""KEP-0002 Phase 7 gate-campaign driver (kaappi#1472).

Orchestrates the invocation level of the two-level statistics protocol
(keps research/benchmarks/README.md §4): for every benchmark cell it launches
N fresh `kaappi` processes (invocations), each running the in-process iteration
loop in gate-harness.scm, then aggregates with bootstrap confidence intervals
and emits the §6 CSV plus a rendered table.

Protocol points implemented here:

  * §4.1 two levels: invocations (fresh process) x iterations (in-process).
  * §4.2 report mean + 95% bootstrap CI over invocation means; never best-of-N,
    never discard outliers (a slow invocation is data). A *timed-out* invocation
    (a hang, not a slow run) is recorded as a failure and excluded, with a
    warning -- see the kaappi#1489 note in README.md.
  * §4.3 randomization: the whole (cell x invocation) launch schedule is
    shuffled under a seed, and a dummy env var of random length (0-4096 bytes)
    is exported per process (the Mytkowicz environment-size effect). ASLR is
    left on (nothing disables it).
  * §4.4 one binary: the lever is a runtime arg to the same instrumented binary.
  * §4.6 w = 8 needs >= 8 physical cores; the driver records the machine label
    and core count but does not enforce it (the operator asserts it).

Invocation model (an operational definition added pre-freeze, README.md): one
invocation = one fresh process running exactly ONE cell for `iterations`
iterations. This keeps per-cell RSS / peak-envelope clean and makes a single
cell's hang cost only that cell's invocation, not a whole multi-cell process.
The §4.3 cell-order shuffle is honored as the shuffle of the campaign-wide
launch schedule.

Usage:
  run-gate.py --bin <kaappi-instrumented> [--mode pilot|full] [--out results.csv]
              [--machine LABEL] [--cores N] [--sizes 65536,1048576,...]
              [--workers 1,2,4,8] [--workloads ip-band,...] [--levers none,c,cd]
              [--invocations N] [--iterations N] [--warmup N]
              [--timeout SECS] [--seed N] [--bootstrap N]

The binary MUST be built with `-Dchannel-instrument=true`, or every copy
counter reads 0 (the driver warns if it detects all-zero copy time).
"""

import argparse
import os
import random
import subprocess
import sys
import threading
import time

import numpy as np

WORKLOADS = ["ip-band", "ip-map", "ip-matmul", "fo-digest", "fo-tree", "fo-slice"]
GATE_IP = ["ip-band", "ip-map", "ip-matmul"]
GATE_FO = ["fo-digest", "fo-tree", "fo-slice"]

CSV_HEADER = (
    "machine,workload,size_bytes,workers,levers,invocations,iterations,"
    "E_mean_ms,E_ci95_lo,E_ci95_hi,share_mean,share_ci95_lo,share_ci95_hi,"
    "S_ms,speedup,rss_peak_mib,envelope_peak_mib"
)


def maxrss_to_mib(ru_maxrss):
    # darwin reports ru_maxrss in bytes; linux in KiB.
    if sys.platform == "darwin":
        return ru_maxrss / (1024.0 * 1024.0)
    return ru_maxrss / 1024.0


def run_once(bin_path, harness, workload, size, workers, lever, warmup, iters,
             timeout, pad_len):
    """Run one invocation (one fresh process). Returns a dict with parsed
    per-iteration rows, child peak RSS (MiB), and a status string."""
    env = os.environ.copy()
    # Mytkowicz environment-size perturbation (§4.3): a padding var of random
    # length. Random bytes as an ASCII-safe string.
    env["KAAPPI_GATE_PAD"] = "x" * pad_len
    cmd = [bin_path, harness, workload, str(size), str(workers), lever,
           str(warmup), str(iters)]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, text=True)
    timed_out = [False]

    def _kill():
        timed_out[0] = True
        try:
            proc.kill()
        except ProcessLookupError:
            pass

    timer = threading.Timer(timeout, _kill)
    timer.start()
    # Output is small (a handful of ITER lines); reading to EOF before reaping
    # cannot deadlock. read() returns when the process exits or is killed.
    out = proc.stdout.read()
    err = proc.stderr.read()
    try:
        pid, status, rusage = os.wait4(proc.pid, 0)
        proc.returncode = os.waitstatus_to_exitcode(status)  # keep Popen from re-reaping
        rss_mib = maxrss_to_mib(rusage.ru_maxrss)
    except ChildProcessError:
        rss_mib = 0.0
    timer.cancel()

    rows = []
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 11 and f[0] == "ITER":
            # ITER wl size workers lever iter e submit result reassembly peak
            rows.append({
                "e_ns": float(f[6]),
                "submit_ns": float(f[7]),
                "result_ns": float(f[8]),
                "reassembly_ns": float(f[9]),
                "peak_bytes": float(f[10]),
            })
    if timed_out[0]:
        status_s = "TIMEOUT"
    elif proc.returncode != 0:
        status_s = f"EXIT{proc.returncode}"
    elif not rows:
        status_s = "NOOUTPUT"
    else:
        status_s = "OK"
    return {"rows": rows, "rss_mib": rss_mib, "status": status_s, "stderr": err}


def bootstrap_ci(invocation_means, n_boot, rng):
    """95% CI as bootstrap percentiles over invocation-level means (§4.2)."""
    a = np.asarray(invocation_means, dtype=float)
    if len(a) == 0:
        return (float("nan"), float("nan"), float("nan"))
    if len(a) == 1:
        return (float(a[0]), float(a[0]), float(a[0]))
    idx = rng.integers(0, len(a), size=(n_boot, len(a)))
    boot_means = a[idx].mean(axis=1)
    return (float(a.mean()),
            float(np.percentile(boot_means, 2.5)),
            float(np.percentile(boot_means, 97.5)))


class Cell:
    """One (workload, size, workers, lever) measurement point."""

    def __init__(self, workload, size, workers, lever):
        self.workload = workload
        self.size = size
        self.workers = workers
        self.lever = lever
        self.invocations = []   # list of {"e": inv_mean_e_ns, "share": inv_mean_share, "peak": max_peak}
        self.rss_peak_mib = 0.0
        self.failures = []

    def key(self):
        return (self.workload, self.size, self.workers, self.lever)

    def add_invocation(self, result):
        if result["status"] != "OK":
            self.failures.append(result["status"])
            return
        es = np.array([r["e_ns"] for r in result["rows"]])
        # per-iteration share, then invocation mean (§3 quantity per section)
        shares = np.array([
            (r["submit_ns"] + r["result_ns"] + r["reassembly_ns"]) / r["e_ns"]
            if r["e_ns"] > 0 else 0.0
            for r in result["rows"]
        ])
        peak = max((r["peak_bytes"] for r in result["rows"]), default=0.0)
        self.invocations.append({
            "e": float(es.mean()),
            "share": float(shares.mean()),
            "peak": peak,
        })
        self.rss_peak_mib = max(self.rss_peak_mib, result["rss_mib"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True, help="path to kaappi built with -Dchannel-instrument=true")
    ap.add_argument("--harness", default=os.path.join(os.path.dirname(__file__), "gate-harness.scm"))
    ap.add_argument("--out", default="gate-results.csv")
    ap.add_argument("--mode", choices=["pilot", "full"], default="pilot")
    ap.add_argument("--machine", default="unknown")
    ap.add_argument("--cores", type=int, default=0)
    ap.add_argument("--sizes", default="65536,1048576")
    ap.add_argument("--workers", default="8")
    ap.add_argument("--workloads", default=",".join(WORKLOADS))
    ap.add_argument("--levers", default="none,c")
    ap.add_argument("--invocations", type=int, default=0)
    ap.add_argument("--iterations", type=int, default=0)
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--seed", type=int, default=1472)
    ap.add_argument("--bootstrap", type=int, default=10000)
    args = ap.parse_args()

    # Protocol §4.1 counts. Pilot: 5 x 20. Full: floors 20 x 10 (a real campaign
    # sets these from the pilot's variance; the driver reports the CI half-width
    # so the operator can confirm the +-2% target was met).
    if args.mode == "pilot":
        invocations = args.invocations or 5
        iterations = args.iterations or 20
    else:
        invocations = args.invocations or 20
        iterations = args.iterations or 10

    sizes = [int(s) for s in args.sizes.split(",") if s]
    workers = [int(w) for w in args.workers.split(",") if w]
    workloads = [w for w in args.workloads.split(",") if w]
    levers = [l for l in args.levers.split(",") if l]

    rng = np.random.default_rng(args.seed)
    pyrng = random.Random(args.seed)

    # Build cells: the parallel matrix, plus serial baselines (S) for each
    # (workload, size), plus c-empty at each worker count (control-plane floor).
    cells = {}

    def get_cell(wl, size, w, lever):
        c = Cell(wl, size, w, lever)
        if c.key() not in cells:
            cells[c.key()] = c
        return cells[c.key()]

    for wl in workloads:
        for size in sizes:
            for w in workers:
                for lever in levers:
                    get_cell(wl, size, w, lever)
    # serial baselines: workers=1, lever none (channels unused)
    serial_cells = {}
    for wl in workloads:
        for size in sizes:
            sc = Cell("s:" + wl, size, 1, "none")
            serial_cells[sc.key()] = sc
    # c-empty control at each worker count (size 0)
    for w in workers:
        get_cell("c-empty", 0, w, "none")

    all_cells = list(cells.values()) + list(serial_cells.values())

    # Launch schedule: (cell, invocation_index), shuffled campaign-wide (§4.3).
    schedule = []
    for c in all_cells:
        for inv in range(invocations):
            schedule.append(c)
    pyrng.shuffle(schedule)

    print(f"# gate campaign: mode={args.mode} machine={args.machine} "
          f"cells={len(all_cells)} invocations={invocations} iterations={iterations} "
          f"launches={len(schedule)}", file=sys.stderr)

    t_start = time.time()
    any_nonzero_copy = False
    for i, c in enumerate(schedule):
        pad_len = pyrng.randint(0, 4096)
        res = run_once(args.bin, args.harness, c.workload, c.size, c.workers,
                       c.lever, args.warmup, iterations, args.timeout, pad_len)
        c.add_invocation(res)
        if res["status"] == "OK":
            if any(r["submit_ns"] + r["result_ns"] > 0 for r in res["rows"]):
                any_nonzero_copy = True
        else:
            print(f"  ! {c.workload} size={c.size} w={c.workers} lever={c.lever}"
                  f" -> {res['status']}", file=sys.stderr)
            if res["stderr"].strip():
                print("    stderr:", res["stderr"].strip().splitlines()[-1], file=sys.stderr)
        if (i + 1) % 10 == 0 or i + 1 == len(schedule):
            el = time.time() - t_start
            print(f"  [{i+1}/{len(schedule)}] {el:.0f}s elapsed", file=sys.stderr)

    if not any_nonzero_copy:
        print("WARNING: all copy counters read 0 -- is --bin built with "
              "-Dchannel-instrument=true?", file=sys.stderr)

    # Serial S lookup by (workload, size).
    serial_ms = {}
    for sc in serial_cells.values():
        if sc.invocations:
            wl = sc.workload[2:]  # strip "s:"
            serial_ms[(wl, sc.size)] = np.mean([iv["e"] for iv in sc.invocations]) / 1e6

    # Emit CSV.
    rows_out = [CSV_HEADER]
    table = []
    for c in cells.values():
        if not c.invocations:
            table.append((c, None))
            continue
        e_means = [iv["e"] for iv in c.invocations]
        share_means = [iv["share"] * 100.0 for iv in c.invocations]  # percent
        e_mean, e_lo, e_hi = bootstrap_ci(e_means, args.bootstrap, rng)
        s_mean, s_lo, s_hi = bootstrap_ci(share_means, args.bootstrap, rng)
        e_mean_ms, e_lo_ms, e_hi_ms = e_mean / 1e6, e_lo / 1e6, e_hi / 1e6
        env_peak_mib = max((iv["peak"] for iv in c.invocations), default=0.0) / (1024.0 * 1024.0)
        base_wl = c.workload
        s_ms = serial_ms.get((base_wl, c.size), float("nan"))
        speedup = (s_ms / e_mean_ms) if (s_ms == s_ms and e_mean_ms > 0) else float("nan")
        rows_out.append(",".join(str(x) for x in [
            args.machine, c.workload, c.size, c.workers, c.lever,
            len(c.invocations), iterations,
            f"{e_mean_ms:.4f}", f"{e_lo_ms:.4f}", f"{e_hi_ms:.4f}",
            f"{s_mean:.3f}", f"{s_lo:.3f}", f"{s_hi:.3f}",
            f"{s_ms:.4f}", f"{speedup:.3f}",
            f"{c.rss_peak_mib:.2f}", f"{env_peak_mib:.4f}",
        ]))
        table.append((c, (e_mean_ms, s_mean, s_lo, s_hi, speedup)))

    with open(args.out, "w") as fh:
        fh.write("\n".join(rows_out) + "\n")

    # Rendered table (share is the gate quantity; show its CI half-width).
    print()
    print(f"{'workload':<11}{'size':>10}{'w':>3}{'lever':>6}"
          f"{'E_ms':>11}{'share%':>9}{'[lo,':>9}{'hi]':>8}{'ci+-%':>8}{'inv':>5}")
    for c, agg in table:
        if agg is None:
            print(f"{c.workload:<11}{c.size:>10}{c.workers:>3}{c.lever:>6}"
                  f"{'FAILED('+','.join(c.failures[:3])+')':>36}")
            continue
        e_ms, s_mean, s_lo, s_hi, speedup = agg
        half = (s_hi - s_lo) / 2.0
        pct = (half / s_mean * 100.0) if s_mean > 0 else float("nan")
        print(f"{c.workload:<11}{c.size:>10}{c.workers:>3}{c.lever:>6}"
              f"{e_ms:>11.3f}{s_mean:>9.2f}{s_lo:>9.2f}{s_hi:>8.2f}"
              f"{pct:>8.1f}{len(c.invocations):>5}")

    print(f"\nCSV written to {args.out}", file=sys.stderr)
    if args.mode == "pilot":
        print("# pilot: the ci+-% column is the bootstrap CI half-width as % of "
              "the share mean; the frozen run raises invocation counts until it "
              "meets the protocol's +-2% target (floors 20 inv x 10 iter).",
              file=sys.stderr)


if __name__ == "__main__":
    main()
