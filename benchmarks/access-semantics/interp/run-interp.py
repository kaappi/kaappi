#!/usr/bin/env python3
"""Interpreter-tier control aggregator (memo §9.4).

Launches the dispatch-model microbench (dispatch_plain / dispatch_unordered)
under the same two-level invocation x iteration discipline as the main matrix,
and reports ns/call for -ref and -set! with bootstrap 95% CIs plus the
plain->unordered delta. Expected: Delta ~ 0 (dispatch dominates; the atomic
annotation is a sub-ns fraction of an indirect call).
"""
import argparse, os, random, subprocess, sys
import numpy as np


def run_once(binp, n, warmup, iters, pad):
    env = os.environ.copy()
    env["KAAPPI_ACCESS_PAD"] = "x" * pad
    p = subprocess.run([binp, str(n), str(warmup), str(iters)],
                       capture_output=True, text=True, env=env, timeout=120)
    ref, sset = [], []
    for line in p.stdout.splitlines():
        f = line.split()
        if len(f) >= 5 and f[0] == "ITER":
            ref.append(float(f[3])); sset.append(float(f[4]))
    return ref, sset


def boot(vals, nb, rng):
    a = np.asarray(vals, float)
    if len(a) < 2:
        return (float(a.mean()) if len(a) else float("nan"),) * 3
    idx = rng.integers(0, len(a), size=(nb, len(a)))
    b = a[idx].mean(axis=1)
    return float(a.mean()), float(np.percentile(b, 2.5)), float(np.percentile(b, 97.5))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bindir", default=os.path.dirname(__file__))
    ap.add_argument("--n", type=int, default=100000)
    ap.add_argument("--invocations", type=int, default=20)
    ap.add_argument("--iterations", type=int, default=10)
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--seed", type=int, default=1473)
    ap.add_argument("--bootstrap", type=int, default=10000)
    ap.add_argument("--out", default="../results/interp-dispatch.csv")
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)
    pyrng = random.Random(args.seed)

    arms = {"plain": os.path.join(args.bindir, "dispatch_plain"),
            "unordered": os.path.join(args.bindir, "dispatch_unordered")}
    sched = [(a, b) for a, b in arms.items() for _ in range(args.invocations)]
    pyrng.shuffle(sched)

    inv = {a: {"ref": [], "set": []} for a in arms}
    for enc, binp in sched:
        ref, sset = run_once(binp, args.n, args.warmup, args.iterations,
                             pyrng.randint(0, 4096))
        if ref:
            inv[enc]["ref"].append(float(np.mean(ref)))
            inv[enc]["set"].append(float(np.mean(sset)))

    rows = ["op,encoding,ns_per_call_mean,ci95_lo,ci95_hi,delta_vs_plain_pct"]
    print(f"\n{'op':<6}{'enc':<11}{'ns/call':>10}{'[lo,':>10}{'hi]':>10}{'delta%':>9}")
    base = {}
    for op in ("ref", "set"):
        base[op] = np.mean(inv["plain"][op]) if inv["plain"][op] else float("nan")
    for op in ("ref", "set"):
        for enc in ("plain", "unordered"):
            m, lo, hi = boot(inv[enc][op], args.bootstrap, rng)
            delta = (m - base[op]) / base[op] * 100.0 if enc == "unordered" else 0.0
            ds = "" if enc == "plain" else f"{delta:>8.2f}"
            print(f"{op:<6}{enc:<11}{m:>10.4f}{lo:>10.4f}{hi:>10.4f}{ds:>9}")
            rows.append(f"{op},{enc},{m:.6f},{lo:.6f},{hi:.6f},{delta:.3f}")
    outp = os.path.join(args.bindir, args.out)
    os.makedirs(os.path.dirname(outp), exist_ok=True)
    with open(outp, "w") as fh:
        fh.write("\n".join(rows) + "\n")
    print(f"\nCSV -> {outp}", file=sys.stderr)


if __name__ == "__main__":
    main()
