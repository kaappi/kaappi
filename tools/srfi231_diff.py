#!/usr/bin/env python3
"""Differential testing of Kaappi's SRFI 231 against the reference implementation.

SRFI 231's documented rule in this codebase is "when the spec's prose and its
reference implementation disagree, trust the code" -- which makes the reference
an oracle in the strict sense. Gambit bundles it as `(srfi 231)`, and chibi
ships an independent port. This tool generates random SRFI 231 programs in the
subset of R7RS all three run, executes each under Kaappi and an oracle, and
reports any program whose printed output differs.

Why this exists: the official conformance suite (10,936 evaluations) encodes
the reference's answers on the inputs its author wrote down. It cannot see a
property violation its cases never exercise -- kaappi#2539 passed the whole
suite while breaking the spec's own definition of call/cc-safe. Generated
inputs find bugs at the rate of inputs, not ideas.

It is **not** part of `run-all.sh`: it needs an oracle installed (`brew install
gambit-scheme` or `chibi-scheme`) and a useful run takes minutes. Cases it
finds get reduced and pinned as ordinary regression tests under
tests/scheme/srfi/, with the seed in the comment so they replay:

    tools/srfi231_diff.py reshape --count 500              # gambit oracle
    tools/srfi231_diff.py reshape --oracle chibi --count 200
    tools/srfi231_diff.py reshape --seed 7 --count 1        # exactly one case
    tools/srfi231_diff.py reshape --seed 7 --print          # show its program

Modes
  reshape  A chain of view operations over one specialized array -- extract,
           translate, permute, reverse, sample, curry-pick, tile-pick, copy,
           and specialized-array-reshape with and without copy-on-failure? --
           printing the domain, array-packed?, mutability and contents after
           every step, then writing through the final view and printing the
           base array to compare body sharing. Every step is guarded, so
           "errors here" versus "does not" is compared too. Aimed at the
           NumPy-derived affine-reshape detection in lib/srfi/231/views.sld
           and at array-packed? over composed views, the two places where the
           implementation reasons about index arithmetic rather than copying
           the reference's structure.

Known oracle divergence: chibi 0.12's port raises on a `copy-on-failure? #t`
reshape that needs the copy, where the spec (and Gambit, and Kaappi) return a
copy -- expect that mismatch shape with `--oracle chibi` (seeds 5227 and 5248
of the reshape mode show it) and confirm against Gambit before chasing it.

Each case is a pure function of (mode, seed); `--seed N --count K` runs seeds
N..N+K-1. Mismatches are saved as <save-dir>/<mode>-<seed>.scm with the two
outputs beside them, and the run exits 1.
"""

import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PRELUDE = """\
(import (scheme base) (scheme write) (srfi 231))
(define (show . xs) (for-each (lambda (x) (write x) (display " ")) xs) (newline))
(define (dom a)
  (let ((d (array-domain a)))
    (list (interval-lower-bounds->list d) (interval-upper-bounds->list d))))
(define (describe tag a)
  (show tag (dom a) (specialized-array? a) (mutable-array? a) (array-packed? a)
        (array->list* a)))
(define-syntax try
  (syntax-rules () ((_ e) (guard (c (#t 'ERROR)) e))))
;; write-through probe: set the r-th multi-index (lexicographic) of a to 'X
;; and print the BASE array, so body sharing across the whole chain is
;; compared; the index is chosen here, from a's actual domain, so it is
;; valid whatever the chain did
(define (probe a r)
  (if (array-empty? a)
      (show 'write-through 'empty)
      (let* ((idxs (reverse (interval-fold-left list (lambda (acc x) (cons x acc)) '()
                                               (array-domain a))))
             (idx (list-ref idxs (modulo r (length idxs)))))
        (show 'write-through idx
              (try (begin (apply array-set! a 'X idx) (array->list* a0)))))))
;; a step: bind the result if it succeeded, else keep the previous array so
;; the chain (and the oracle comparison of every later step) continues
(define-syntax step
  (syntax-rules ()
    ((_ name tag prev e)
     (define name (let ((r (try e)))
                    (if (eq? r 'ERROR) (begin (show tag 'ERROR) prev)
                        (begin (describe tag r) r)))))))
"""


# --- interval helpers (Python side) ----------------------------------------

def volume(lo, hi):
    v = 1
    for l, h in zip(lo, hi):
        v *= h - l
    return v


def fmt_vec(xs):
    return "'#(" + " ".join(str(x) for x in xs) + ")"


def fmt_interval(lo, hi):
    return f"(make-interval {fmt_vec(lo)} {fmt_vec(hi)})"


def random_factorization(rng, v, max_axes=4):
    """Split v >= 1 into 0..max_axes factors >= 1, width-1 axes included."""
    if v == 1 and rng.random() < 0.2:
        return []
    n = rng.randint(1, max_axes)
    dims = [1] * n
    rest = v
    # distribute prime factors randomly across the axes
    p = 2
    while rest > 1:
        while rest % p == 0:
            dims[rng.randrange(n)] *= p
            rest //= p
        p += 1
    return dims


def merge_or_split(rng, widths):
    """Merge two adjacent axes into one, or split one axis into two factors.
    Merging axes with non-chaining strides is the exact affine boundary."""
    w = list(widths)
    if len(w) >= 2 and (rng.random() < 0.6 or not any(x > 1 for x in w)):
        i = rng.randrange(len(w) - 1)
        return w[:i] + [w[i] * w[i + 1]] + w[i + 2:]
    cands = [i for i, x in enumerate(w) if x > 1]
    if not cands:
        return w + [1]
    i = rng.choice(cands)
    divs = [f for f in range(1, w[i] + 1) if w[i] % f == 0]
    f = rng.choice(divs)
    return w[:i] + [f, w[i] // f] + w[i + 1:]


def random_same_volume_domain(rng, lo, hi):
    v = volume(lo, hi)
    if v > 0 and rng.random() < 0.5:
        widths = merge_or_split(rng, [h - l for l, h in zip(lo, hi)])
        nlo = [rng.randint(-2, 2) for _ in widths]
        return nlo, [l + w for l, w in zip(nlo, widths)]
    if v == 0:
        n = rng.randint(1, 4)
        widths = [rng.randint(0, 3) for _ in range(n)]
        widths[rng.randrange(n)] = 0
    else:
        widths = random_factorization(rng, v)
    nlo = [rng.randint(-2, 2) for _ in widths]
    return nlo, [l + w for l, w in zip(nlo, widths)]


# --- the reshape-mode generator ---------------------------------------------

class Chain:
    """Tracks the current array's domain on the Python side so every generated
    argument is valid by construction; the guards catch what is not."""

    def __init__(self, rng):
        self.rng = rng
        self.lines = [PRELUDE]
        # mostly 2-3 axes of width 2-4 -- the shapes where affine-reshape
        # detection has real work to do -- with a tail of empty, width-1
        # and zero-dimensional cases
        d = rng.choice([0, 1, 2, 2, 2, 3, 3, 3, 4])
        self.lo = [rng.randint(-2, 2) for _ in range(d)]
        self.hi = [l + rng.choice([0, 1, 2, 2, 3, 3, 4, 4]) for l in self.lo]
        self.n = 0
        # elements are their own multi-index, so contents identify positions
        # unambiguously whatever order an implementation visits them in
        self.lines.append(
            f"(define a0 (array-copy (make-array {fmt_interval(self.lo, self.hi)} list)))")
        self.lines.append("(describe 'base a0)")

    @property
    def cur(self):
        return f"a{self.n}"

    @property
    def d(self):
        return len(self.lo)

    def emit(self, tag, expr, lo, hi):
        prev = self.cur
        self.n += 1
        self.lines.append(f"(step {self.cur} '{tag} {prev} {expr})")
        # the step keeps prev on error; the Python-side domain only advances
        # for arguments generated valid by construction, which is all of them
        self.lo, self.hi = lo, hi

    # each op returns True if it emitted a step
    def op_extract(self):
        lo, hi = [], []
        for l, h in zip(self.lo, self.hi):
            nl = self.rng.randint(l, h)
            nh = self.rng.randint(nl, h)
            lo.append(nl)
            hi.append(nh)
        self.emit("extract", f"(array-extract {self.cur} {fmt_interval(lo, hi)})", lo, hi)
        return True

    def op_translate(self):
        t = [self.rng.randint(-3, 3) for _ in range(self.d)]
        lo = [l + x for l, x in zip(self.lo, t)]
        hi = [h + x for h, x in zip(self.hi, t)]
        self.emit("translate", f"(array-translate {self.cur} {fmt_vec(t)})", lo, hi)
        return True

    def op_permute(self):
        p = list(range(self.d))
        self.rng.shuffle(p)
        lo = [self.lo[i] for i in p]
        hi = [self.hi[i] for i in p]
        self.emit("permute", f"(array-permute {self.cur} {fmt_vec(p)})", lo, hi)
        return True

    def op_reverse(self):
        if self.rng.random() < 0.3:
            self.emit("reverse", f"(array-reverse {self.cur})", self.lo, self.hi)
        else:
            flips = ["#t" if self.rng.random() < 0.5 else "#f" for _ in range(self.d)]
            self.emit("reverse", f"(array-reverse {self.cur} {fmt_vec(flips)})", self.lo, self.hi)
        return True

    def op_sample(self):
        if any(l != 0 for l in self.lo):
            # array-sample needs zero lower bounds; translate there first
            t = [-l for l in self.lo]
            self.emit("translate", f"(array-translate {self.cur} {fmt_vec(t)})",
                      [0] * self.d, [h - l for l, h in zip(self.lo, self.hi)])
        s = [self.rng.randint(1, 3) for _ in range(self.d)]
        hi = [-(-h // k) for h, k in zip(self.hi, s)]  # ceiling
        self.emit("sample", f"(array-sample {self.cur} {fmt_vec(s)})", self.lo, hi)
        return True

    def op_curry_pick(self):
        if self.d == 0:
            return False
        k = self.rng.randint(0, self.d)
        outer = self.d - k
        if volume(self.lo[:outer], self.hi[:outer]) == 0:
            return False
        idx = [self.rng.randrange(l, h) for l, h in zip(self.lo[:outer], self.hi[:outer])]
        expr = f"(array-ref (array-curry {self.cur} {k}) {' '.join(map(str, idx))})"
        self.emit("curry-pick", expr, self.lo[outer:], self.hi[outer:])
        return True

    def op_tile_pick(self):
        if self.d == 0:
            return False
        sides, jidx, tile_lo, tile_hi = [], [], [], []
        for l, h in zip(self.lo, self.hi):
            w = h - l
            if w == 0:
                # spec: a zero-width axis takes a nonempty vector of zeros
                sides.append("#(0)")
                jidx.append(0)
                tile_lo.append(l)
                tile_hi.append(l)
            elif self.rng.random() < 0.5:
                s = self.rng.randint(1, w)
                j = self.rng.randrange(-(-w // s))
                sides.append(str(s))
                jidx.append(j)
                tile_lo.append(l + j * s)
                tile_hi.append(min(l + (j + 1) * s, h))
            else:
                # a cut vector of nonnegative widths summing to w
                ncuts = self.rng.randint(1, min(w, 3))
                cuts = [0] * ncuts
                for _ in range(w):
                    cuts[self.rng.randrange(ncuts)] += 1
                j = self.rng.randrange(ncuts)
                sides.append("#(" + " ".join(map(str, cuts)) + ")")
                jidx.append(j)
                tile_lo.append(l + sum(cuts[:j]))
                tile_hi.append(l + sum(cuts[:j + 1]))
        expr = (f"(array-ref (array-tile {self.cur} '#({' '.join(sides)})) "
                f"{' '.join(map(str, jidx))})")
        self.emit("tile-pick", expr, tile_lo, tile_hi)
        return True

    def op_copy(self):
        self.emit("copy", f"(array-copy {self.cur})", self.lo, self.hi)
        return True

    def op_reshape(self):
        lo, hi = random_same_volume_domain(self.rng, self.lo, self.hi)
        if self.rng.random() < 0.5:
            expr = f"(specialized-array-reshape {self.cur} {fmt_interval(lo, hi)} #t)"
            self.emit("reshape-copy", expr, lo, hi)
            return True
        # Without copy-on-failure? the reshape may legitimately error, and
        # the step then keeps the previous array while the Python-side
        # domain would advance -- so this is always the chain's last step.
        expr = f"(specialized-array-reshape {self.cur} {fmt_interval(lo, hi)})"
        self.emit("reshape", expr, lo, hi)
        self.terminal = True
        return True

    def finish(self):
        self.lines.append(f"(probe {self.cur} {self.rng.randrange(1000)})")
        self.lines.append("(show 'end)")
        return "\n".join(self.lines) + "\n"


def gen_reshape(seed):
    rng = random.Random(seed)
    c = Chain(rng)
    ops = [c.op_extract, c.op_translate, c.op_permute, c.op_permute, c.op_reverse,
           c.op_sample, c.op_sample, c.op_curry_pick, c.op_tile_pick, c.op_copy,
           c.op_reshape, c.op_reshape]
    nsteps = rng.randint(1, 6)
    done = 0
    while done < nsteps and not getattr(c, "terminal", False):
        if rng.choice(ops)():
            done += 1
    return c.finish()


MODES = {"reshape": gen_reshape}


# --- running -----------------------------------------------------------------

def run_one(cmd, path, env, timeout):
    try:
        p = subprocess.run(cmd + [path], capture_output=True, text=True,
                           timeout=timeout, env=env)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"


def normalize(out):
    return "\n".join(line.rstrip() for line in out.strip().splitlines())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("mode", choices=sorted(MODES))
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--oracle", choices=["gambit", "chibi"], default="gambit")
    ap.add_argument("--kaappi", default=os.path.join(ROOT, "zig-out", "bin", "kaappi"))
    ap.add_argument("--gsi", default=shutil.which("gsi") or "/opt/homebrew/bin/gsi")
    ap.add_argument("--chibi", default=shutil.which("chibi-scheme") or "chibi-scheme")
    ap.add_argument("--save", default=None, help="directory for mismatching cases")
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--print", action="store_true", help="print the first case's program and exit")
    args = ap.parse_args()

    gen = MODES[args.mode]
    if args.print:
        sys.stdout.write(gen(args.seed))
        return 0

    oracle_cmd = [args.gsi] if args.oracle == "gambit" else [args.chibi]
    save = args.save or tempfile.mkdtemp(prefix="srfi231-diff-")
    os.makedirs(save, exist_ok=True)
    work = tempfile.mkdtemp(prefix="srfi231-diff-work-")
    # one isolated KAAPPI_HOME for the whole run: the checkout's lib/ wins over
    # any ~/.kaappi/lib (kaappi#2352) and the .sld cache warms once
    env = dict(os.environ, KAAPPI_HOME=os.path.join(work, "home"))
    os.makedirs(env["KAAPPI_HOME"])

    mismatches = 0
    for seed in range(args.seed, args.seed + args.count):
        prog = gen(seed)
        path = os.path.join(work, f"{args.mode}-{seed}.scm")
        with open(path, "w") as f:
            f.write(prog)
        kc, ko, ke = run_one([args.kaappi], path, env, args.timeout)
        oc, oo, oe = run_one(oracle_cmd, path, env, args.timeout)
        same = normalize(ko) == normalize(oo) and (kc == 0) == (oc == 0)
        if same:
            continue
        mismatches += 1
        dst = os.path.join(save, f"{args.mode}-{seed}.scm")
        shutil.copy(path, dst)
        with open(dst + ".kaappi.txt", "w") as f:
            f.write(f"exit {kc}\n--- stdout\n{ko}\n--- stderr\n{ke}")
        with open(dst + f".{args.oracle}.txt", "w") as f:
            f.write(f"exit {oc}\n--- stdout\n{oo}\n--- stderr\n{oe}")
        print(f"MISMATCH seed {seed}: {dst}")
        kl, ol = normalize(ko).splitlines(), normalize(oo).splitlines()
        for i in range(max(len(kl), len(ol))):
            a = kl[i] if i < len(kl) else "<none>"
            b = ol[i] if i < len(ol) else "<none>"
            if a != b:
                print(f"  first difference at output line {i + 1}:")
                print(f"    kaappi:  {a[:200]}")
                print(f"    {args.oracle:7s}: {b[:200]}")
                break
        else:
            print(f"  exit codes differ: kaappi {kc}, {args.oracle} {oc}; stderr: {ke.strip()[:200]} | {oe.strip()[:200]}")

    print(f"{args.mode}: {args.count} cases from seed {args.seed}, oracle {args.oracle}, "
          f"{mismatches} mismatches" + (f" saved under {save}" if mismatches else ""))
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
