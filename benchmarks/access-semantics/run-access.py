#!/usr/bin/env python3
"""P1 access-semantics codegen-timing driver (kaappi#1473).

Owns the invocation level of the two-level Kalibera-Jones protocol
(keps research/benchmarks/README.md §4, the same discipline Phase 7 registers,
per the P1 memo §9.5). For every cell (kernel x encoding x size) it launches N
fresh processes (invocations), each running `iterations` in-process timed
samples of ns/element, then aggregates with bootstrap 95% CIs over invocation
means.

Protocol points (mirrors benchmarks/gate/run-gate.py):
  * §4.1 two levels: invocations (fresh process) x iterations (in-process).
  * §4.2 mean + 95% bootstrap CI over invocation means; never best-of-N, never
    discard outliers.
  * §4.3 randomization: the whole (cell x invocation) launch schedule is
    shuffled under a seed; a dummy env var of random length (0-4096 bytes) is
    exported per process (the Mytkowicz environment-size effect); ASLR left on.
  * §4.4 one binary per cell -- the driver source is identical across all 18
    binaries; only the kernel object (the experimental variable) differs, and
    there is no LTO, so the timed loop is exactly the `zig cc -O2` codegen.
  * §4.5 build/env recorded in the metadata sidecar by run-all.sh.

The decision quantity is the per-kernel-per-size *cost of unordered (and
monotonic) relative to plain*: cost% = (nspe_enc - nspe_plain)/nspe_plain*100,
with a bootstrap CI formed by resampling the two arms' invocation means
independently. The pre-registered criterion (memo §9, open-problems P1) asks
whether that cost is < 10% on the vectorizable kernels.
"""

import argparse
import os
import random
import subprocess
import sys
import time

import numpy as np

KERNELS = ["f64_fill", "f64_map", "f64_sum", "i64_checksum", "u8_fill", "u8_copy"]
ENCODINGS = ["plain", "unordered", "monotonic"]
ELEM_SIZE = {
    "f64_fill": 8, "f64_map": 8, "f64_sum": 8,
    "i64_checksum": 8, "u8_fill": 1, "u8_copy": 1,
}

CSV_HEADER = (
    "machine,kernel,encoding,size_bytes,elem_size,invocations,iterations,"
    "nspe_mean,nspe_ci95_lo,nspe_ci95_hi,"
    "cost_vs_plain_pct,cost_ci95_lo,cost_ci95_hi"
)


def run_once(bin_path, size_bytes, elem_size, warmup, iters, timeout, pad_len):
    env = os.environ.copy()
    env["KAAPPI_ACCESS_PAD"] = "x" * pad_len  # Mytkowicz env-size perturbation
    cmd = [bin_path, str(size_bytes), str(elem_size), str(warmup), str(iters)]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"nspe": [], "status": "TIMEOUT"}
    if proc.returncode != 0:
        return {"nspe": [], "status": f"EXIT{proc.returncode}", "stderr": proc.stderr}
    nspe = []
    for line in proc.stdout.splitlines():
        f = line.split()
        if len(f) >= 5 and f[0] == "ITER":
            nspe.append(float(f[3]))
    return {"nspe": nspe, "status": "OK" if nspe else "NOOUTPUT"}


def bootstrap_ci(values, n_boot, rng):
    a = np.asarray(values, dtype=float)
    if len(a) == 0:
        return (float("nan"), float("nan"), float("nan"))
    if len(a) == 1:
        return (float(a[0]), float(a[0]), float(a[0]))
    idx = rng.integers(0, len(a), size=(n_boot, len(a)))
    boot = a[idx].mean(axis=1)
    return (float(a.mean()), float(np.percentile(boot, 2.5)),
            float(np.percentile(boot, 97.5)))


def bootstrap_cost_ci(plain_means, enc_means, n_boot, rng):
    """Cost% = (enc - plain)/plain * 100, CI by independently resampling the two
    arms' invocation means (they come from different processes -- unpaired)."""
    p = np.asarray(plain_means, dtype=float)
    e = np.asarray(enc_means, dtype=float)
    if len(p) == 0 or len(e) == 0:
        return (float("nan"), float("nan"), float("nan"))
    point = (e.mean() - p.mean()) / p.mean() * 100.0
    if len(p) == 1 and len(e) == 1:
        return (point, point, point)
    pi = rng.integers(0, len(p), size=(n_boot, len(p)))
    ei = rng.integers(0, len(e), size=(n_boot, len(e)))
    pm = p[pi].mean(axis=1)
    em = e[ei].mean(axis=1)
    cost = (em - pm) / pm * 100.0
    return (point, float(np.percentile(cost, 2.5)), float(np.percentile(cost, 97.5)))


class Cell:
    def __init__(self, kernel, encoding, size):
        self.kernel = kernel
        self.encoding = encoding
        self.size = size
        self.inv_means = []   # per-invocation mean ns/element
        self.failures = []

    def key(self):
        return (self.kernel, self.encoding, self.size)

    def add(self, result):
        if result["status"] != "OK":
            self.failures.append(result["status"])
            return
        self.inv_means.append(float(np.mean(result["nspe"])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bindir", default=os.path.join(os.path.dirname(__file__), "bin"))
    ap.add_argument("--out", default="results/access-results.csv")
    ap.add_argument("--mode", choices=["pilot", "full"], default="pilot")
    ap.add_argument("--machine", default="unknown")
    ap.add_argument("--sizes", default="16384,524288,8388608,67108864",
                    help="bytes; default spans L1/L2/LLC/DRAM")
    ap.add_argument("--kernels", default=",".join(KERNELS))
    ap.add_argument("--encodings", default=",".join(ENCODINGS))
    ap.add_argument("--invocations", type=int, default=0)
    ap.add_argument("--iterations", type=int, default=0)
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--seed", type=int, default=1473)
    ap.add_argument("--bootstrap", type=int, default=10000)
    args = ap.parse_args()

    # §4.1 counts. Pilot 5x20; full uses the floors 20x10 (a real campaign sets
    # these from the pilot variance; the driver prints the CI half-width so the
    # operator can confirm the +-2% target).
    if args.mode == "pilot":
        invocations = args.invocations or 5
        iterations = args.iterations or 20
    else:
        invocations = args.invocations or 20
        iterations = args.iterations or 10

    sizes = [int(s) for s in args.sizes.split(",") if s]
    kernels = [k for k in args.kernels.split(",") if k]
    encodings = [e for e in args.encodings.split(",") if e]

    rng = np.random.default_rng(args.seed)
    pyrng = random.Random(args.seed)

    cells = {}
    for k in kernels:
        for e in encodings:
            for s in sizes:
                c = Cell(k, e, s)
                cells[c.key()] = c

    schedule = []
    for c in cells.values():
        for _ in range(invocations):
            schedule.append(c)
    pyrng.shuffle(schedule)

    print(f"# access campaign: mode={args.mode} machine={args.machine} "
          f"cells={len(cells)} inv={invocations} iter={iterations} "
          f"launches={len(schedule)}", file=sys.stderr)

    t0 = time.time()
    for i, c in enumerate(schedule):
        pad = pyrng.randint(0, 4096)
        binp = os.path.join(args.bindir, f"{c.kernel}_{c.encoding}")
        res = run_once(binp, c.size, ELEM_SIZE[c.kernel], args.warmup,
                       iterations, args.timeout, pad)
        c.add(res)
        if res["status"] != "OK":
            print(f"  ! {c.kernel}/{c.encoding} size={c.size} -> {res['status']}",
                  file=sys.stderr)
        if (i + 1) % 25 == 0 or i + 1 == len(schedule):
            print(f"  [{i+1}/{len(schedule)}] {time.time()-t0:.0f}s", file=sys.stderr)

    # Aggregate. plain is the baseline for each (kernel, size).
    plain_means = {}
    for c in cells.values():
        if c.encoding == "plain" and c.inv_means:
            plain_means[(c.kernel, c.size)] = c.inv_means

    rows = [CSV_HEADER]
    table = []
    for c in cells.values():
        if not c.inv_means:
            table.append((c, None)); continue
        nspe_mean, nspe_lo, nspe_hi = bootstrap_ci(c.inv_means, args.bootstrap, rng)
        base = plain_means.get((c.kernel, c.size))
        if c.encoding == "plain" or not base:
            cost, clo, chi = (0.0, 0.0, 0.0) if c.encoding == "plain" else (float("nan"),) * 3
        else:
            cost, clo, chi = bootstrap_cost_ci(base, c.inv_means, args.bootstrap, rng)
        rows.append(",".join(str(x) for x in [
            args.machine, c.kernel, c.encoding, c.size, ELEM_SIZE[c.kernel],
            len(c.inv_means), iterations,
            f"{nspe_mean:.6f}", f"{nspe_lo:.6f}", f"{nspe_hi:.6f}",
            f"{cost:.2f}", f"{clo:.2f}", f"{chi:.2f}",
        ]))
        table.append((c, (nspe_mean, nspe_lo, nspe_hi, cost, clo, chi)))

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w") as fh:
        fh.write("\n".join(rows) + "\n")

    # Rendered table grouped by kernel then size.
    print()
    print(f"{'kernel':<13}{'enc':<10}{'size':>10}"
          f"{'ns/elem':>11}{'[lo,':>10}{'hi]':>9}{'cost%':>9}{'costCI':>16}{'inv':>4}")
    order = {k: i for i, k in enumerate(KERNELS)}
    for c, agg in sorted(table, key=lambda t: (order.get(t[0].kernel, 99),
                                               t[0].size,
                                               ENCODINGS.index(t[0].encoding)
                                               if t[0].encoding in ENCODINGS else 9)):
        if agg is None:
            print(f"{c.kernel:<13}{c.encoding:<10}{c.size:>10}"
                  f"{'FAILED('+','.join(c.failures[:2])+')':>40}")
            continue
        nspe, lo, hi, cost, clo, chi = agg
        cost_s = "" if c.encoding == "plain" else f"{cost:>8.1f}"
        ci_s = "" if c.encoding == "plain" else f"[{clo:.1f},{chi:.1f}]"
        print(f"{c.kernel:<13}{c.encoding:<10}{c.size:>10}"
              f"{nspe:>11.4f}{lo:>10.4f}{hi:>9.4f}{cost_s:>9}{ci_s:>16}{len(c.inv_means):>4}")

    print(f"\nCSV written to {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
