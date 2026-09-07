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
    tools/srfi231_diff.py storage --count 400               # all 16 storage classes
    tools/srfi231_diff.py storage --classes u1,f16 --count 200
    tools/srfi231_diff.py storage --count 50 --keep         # keep the work dir
    tools/srfi231_diff.py callcc --count 300                # continuation re-entry
    tools/srfi231_diff.py prose                             # every spec example
    tools/srfi231_diff.py prose --seed 44 --print           # one example's program

Modes
  prose    The spec's own code examples as a corpus: every code block of
           srfi-231.html (fetched, or --spec FILE), one case per block. A
           small reader wraps each top-level expression -- and each body
           expression of a top-level let, where the spec puts its `;; =>`
           annotations -- in a printer, so every annotated value is
           compared, not just the block's last. Values print through a
           canonical renderer (arrays as domain + contents, intervals as
           bounds, floats as exact rationals, unspecified as a symbol), and
           pretty-print/pp are replaced by it so Gambit's line breaking
           never counts. Each program carries the definitions of every
           earlier block, since the examples build on their own helpers
           (array-unveil, array-squeeze, ...). Blocks that read files,
           time, or draw random numbers are skipped and listed. The seed
           is the 1-based example number; --count defaults to all of them.
  callcc   Call/cc safety of every accumulating or callback-taking non-!
           procedure -- the spec's promise that such procedures "do not
           modify the state of any data captured by a continuation". One
           procedure per case (array-copy, array->list/vector and their *
           forms, the array and interval folds, array-reduce, array-every,
           array-any, array-for-each, array-map under array-copy, and
           array-stack/append/block/decurry) is driven by the kaappi#2539
           schedule generalized: two continuations captured on the first
           run at random positions, then re-invoked with random values in
           a random order, the whole result history printed at the end.
           The capture sits either in the source array's getter or in the
           callback itself (fold kernel, predicate, operator), and an
           escape-out variant invokes an outer continuation from inside
           the walk and then runs the procedure again. One re-entry cannot
           tell a shared accumulator from a functional one; the second
           can, which is how #2539 passed the official suite's own cases.
  storage  One storage class per case, through everything that consults its
           checker, getter and setter: the checker's verdict on boundary and
           wrong-typed values, make-specialized-array with an initial value,
           array-set! through the array and through a reversed extract of it,
           array-copy and list->array from a generic source, array-assign!
           into a view, and storage-class-length of the body. Values are
           canonicalized before printing -- finite reals as exact rationals,
           complex as a pair of those, chars as code points -- so f16/f32
           rounding is compared bit-exactly and Gambit's `.5` never differs
           from Kaappi's `0.5` textually. Aimed at the software u1 bit
           packing and f16 half-floats, the interleaved c64/c128 bodies, and
           the checker of every class (whether f64 rejects an exact integer,
           whether c64 accepts a real flonum), through views with offsets.
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

Known oracle divergences. Gambit's bundled reference flips the initial
value of `specialized-array-default-safe?` to #t (spec and the SRFI
repository's copy: #f); the storage mode pins it to #f in its prelude.
kaappi#2542 (the c64/c128 checkers accepted real flonums, which the
reference rejects) used to surface as `check` mismatches on those two
classes; before kaappi#2543 fixed it, the workaround was excluding them
with `--classes`, and both are back in the default draw. Since a
program's first difference hides everything after it, `--classes` is
still the way to focus a run on the classes you care about.
And chibi 0.12's port raises on a `copy-on-failure? #t`
reshape that needs the copy, where the spec (and Gambit, and Kaappi) return a
copy -- expect that mismatch shape with `--oracle chibi` (seeds 5227 and 5248
of the reshape mode show it) and confirm against Gambit before chasing it.
Its storage classes have checker bugs of their own (u16 accepts 65536, u64
accepts negatives, c64 accepts a real flonum, make-specialized-array does
not validate its initial value), all contradicted by Gambit; its u1 checker
returns a list rather than a boolean, which the storage mode hides by
printing only the boolean verdict. In the callcc mode chibi's array-copy --
into a typed storage class, or of an array-map result -- keeps a value
written by an earlier re-entry across a second continuation: the
kaappi#2539 shape, a shared scratch behind a call/cc-safe procedure, which
Gambit and Kaappi (since #2540) rebuild from the captured prefix instead;
its array-fold-right and interval-fold-right accumulate through a set! cell,
so a re-entry conses onto the whole first run's list. Gambit sides with
Kaappi on every one of these.

Each case is a pure function of (mode, seed); `--seed N --count K` runs seeds
N..N+K-1. Mismatches are saved as <save-dir>/<mode>-<seed>.scm with the two
outputs beside them, and the run exits 1.
"""

import argparse
import html as html_mod
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

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
;; specialized-array-default-safe? is deliberately left unpinned here,
;; unlike the storage prelude: every array in this mode is generic (the
;; checker accepts anything), every index is valid by construction, and
;; nothing printed observes the flag -- so Gambit's flipped default cannot
;; show. The storage mode prints array-safe?, hence pins it.
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
        # set by a no-copy reshape, which is always the chain's last step
        self.terminal = False
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


def gen_reshape(seed, classes=None, spec=None):
    rng = random.Random(seed)
    c = Chain(rng)
    ops = [c.op_extract, c.op_translate, c.op_permute, c.op_permute, c.op_reverse,
           c.op_sample, c.op_sample, c.op_curry_pick, c.op_tile_pick, c.op_copy,
           c.op_reshape, c.op_reshape]
    nsteps = rng.randint(1, 6)
    done = 0
    while done < nsteps and not c.terminal:
        if rng.choice(ops)():
            done += 1
    return c.finish()


# --- the storage-class-mode generator -----------------------------------------

STORAGE_PRELUDE = PRELUDE.replace(
    "(import (scheme base) (scheme write) (srfi 231))",
    "(import (scheme base) (scheme write) (scheme inexact) (scheme complex) (srfi 231))") + """\
;; the spec says (specialized-array-default-safe?) is initially #f, and so
;; does the SRFI repository's reference source, but Gambit's bundled copy
;; of that same file flips the initial value to #t -- pin it, so an omitted
;; safe? argument means the same thing under both
(specialized-array-default-safe? #f)
;; implementations print flonums differently (Gambit: .5 and 1.; Kaappi:
;; 0.5 and 1.0), so print every value in a representation both write
;; identically: finite reals as exact rationals (bit-exact, so f16/f32
;; rounding is compared precisely), complex as a tagged pair of those,
;; chars as code points, nested lists recursively; infinities and nan as
;; tagged lists rather than symbols, which chibi would write as |+inf|
(define (canon v)
  (cond ((and (real? v) (exact? v)) v)
        ((real? v) (cond ((nan? v) '(nan))
                         ((infinite? v) (if (> v 0) '(inf 1) '(inf -1)))
                         (else (exact v))))
        ;; exact complex too: chibi writes 0+1i as 0+i, Kaappi as +i
        ((number? v) (list 'c (canon (real-part v)) (canon (imag-part v))))
        ((char? v) (list 'ch (char->integer v)))
        ((pair? v) (cons (canon (car v)) (canon (cdr v))))
        ((array? v) 'array)
        (else v)))
"""

CLASSES = ["generic", "char", "u1", "u8", "s8", "u16", "s16", "u32", "s32",
           "u64", "s64", "f16", "f32", "f64", "c64", "c128"]

# every candidate value, as source text both readers accept
INTS = [-(2**64), -(2**63) - 1, -(2**63), -(2**32), -(2**31) - 1, -(2**31), -32769,
        -32768, -129, -128, -2, -1, 0, 1, 2, 127, 128, 255, 256, 32767, 32768,
        65535, 65536, 2**31 - 1, 2**31, 2**32 - 1, 2**32, 2**63 - 1, 2**63,
        2**64 - 1, 2**64]
FLOATS = ["0.0", "-0.0", "0.5", "-0.5", "0.1", "1.0", "-1.5", "2.5", "3.0",
          "255.0", "65504.0", "65520.0", "1e-8", "6.1e-5", "5.96e-8", "1e-10",
          "3.4e38", "3.5e38", "1e300", "+inf.0", "-inf.0", "+nan.0",
          "1/2", "1/3"]  # the two rationals are exact reals, not flonums
COMPLEX = ["1.0+2.0i", "0.5-0.25i", "-1.5+0.0i", "0.0+1.0i", "1+2i", "0+1i",
           "1.0+1e300i", "65504.0+65520.0i"]
CHARS = ["#\\a", "#\\x0", "#\\x3bb", "#\\space"]
OTHERS = ["'sym", "\"s\"", "'(1 2)", "#t", "#f", "'()"]


def int_range(name):
    bits = int(name[1:]) if name[1:].isdigit() else None
    if name == "u1":
        return 0, 1
    if name.startswith("u"):
        return 0, 2**bits - 1
    return -(2**(bits - 1)), 2**(bits - 1) - 1


def likely_valid(rng, cls):
    """A value the class's checker should (or plausibly might) accept."""
    if cls == "generic":
        return rng.choice([str(v) for v in INTS] + FLOATS + COMPLEX + CHARS + OTHERS)
    if cls == "char":
        return rng.choice(CHARS)
    if cls[0] in "us":
        lo, hi = int_range(cls)
        return str(rng.choice([lo, hi, lo + 1, hi - 1, 0, 1] + [rng.randint(lo, hi) for _ in range(3)]))
    if cls[0] == "f":
        return rng.choice(FLOATS)
    return rng.choice(COMPLEX + FLOATS)


def any_value(rng):
    return rng.choice([str(v) for v in INTS] + FLOATS + COMPLEX + CHARS + OTHERS)


def value(rng, cls):
    return likely_valid(rng, cls) if rng.random() < 0.7 else any_value(rng)


def gen_storage(seed, classes=None, spec=None):
    rng = random.Random(seed)
    cls = rng.choice(classes or CLASSES)
    sc = f"{cls}-storage-class"
    L = [STORAGE_PRELUDE]
    L.append(f"(define sc {sc})")
    L.append(f"(show 'class '{cls} (canon (storage-class-default sc)) (storage-class? sc))")
    # no f8 probe: the spec lets an implementation with an 8-bit float type
    # define f8-storage-class (chibi does); Gambit and Kaappi leave it #f
    # the checker's verdict on a handful of values -- the most direct probe
    for _ in range(8):
        v = value(rng, cls)
        # `(and ... #t)`: chibi's u1 checker is memv-shaped and returns the
        # tail, so only the boolean verdict is compared, never its spelling
        L.append(f"(show 'check (canon {v}) (and ((storage-class-checker sc) {v}) #t))")
    # a small 1-2 axis domain; sometimes empty
    d = rng.choice([1, 1, 2, 2, 2])
    lo = [rng.randint(-2, 2) for _ in range(d)]
    hi = [l + rng.choice([0, 1, 2, 3, 3, 4]) for l in lo]
    vol = volume(lo, hi)
    iv = fmt_interval(lo, hi)
    L.append(f"(define iv {iv})")
    init = value(rng, cls)
    L.append(f"(define a0 (try (make-specialized-array iv sc {init} #t)))")
    L.append(f"(show 'make (canon {init}) (if (eq? a0 'ERROR) 'ERROR (canon (array->list a0))))")
    # keep going with a default-initialized array if the initial value was rejected
    L.append("(define a (if (eq? a0 'ERROR) (make-specialized-array iv sc) a0))")
    L.append("(show 'length ((storage-class-length sc) (array-body a)) (mutable-array? a) (array-safe? a))")
    if vol > 0:
        for _ in range(rng.randint(2, 5)):
            v = value(rng, cls)
            idx = " ".join(str(rng.randrange(l, h)) for l, h in zip(lo, hi))
            L.append(f"(show 'set (canon {v}) (try (begin (array-set! a {v} {idx}) 'ok)))")
        L.append("(show 'contents (canon (array->list a)))")
        # a view with an offset into the body: extract a sub-interval, reverse it
        slo = [rng.randint(l, h - 1) for l, h in zip(lo, hi)]
        shi = [rng.randint(sl + 1, h) for sl, h in zip(slo, hi)]
        flips = fmt_vec(["#t" if rng.random() < 0.6 else "#f" for _ in range(d)])
        L.append(f"(define b (array-reverse (array-extract a {fmt_interval(slo, shi)}) {flips}))")
        L.append("(show 'view (dom b) (array-packed? b) (canon (array->list b)))")
        for _ in range(rng.randint(1, 3)):
            v = value(rng, cls)
            idx = " ".join(str(rng.randrange(l, h)) for l, h in zip(slo, shi))
            L.append(f"(show 'view-set (canon {v}) (try (begin (array-set! b {v} {idx}) 'ok)))")
        L.append("(show 'contents (canon (array->list a)))")
        # array-assign! from a generic array of one (usually valid) value
        v = value(rng, cls)
        L.append(f"(show 'assign (canon {v}) (try (begin (array-assign! b (array-copy (make-array (array-domain b) (lambda idx {v})) generic-storage-class)) (canon (array->list a)))))")
    # bulk constructors from generic sources, with the checker in the loop
    vals = [value(rng, cls) for _ in range(vol)]
    L.append(f"(define g (list->array iv (list {' '.join(vals)}) generic-storage-class))")
    L.append("(show 'copy (try (canon (array->list (array-copy g sc)))))")
    L.append(f"(show 'list->array (try (canon (array->list (list->array iv (list {' '.join(vals)}) sc)))))")
    L.append(f"(show 'vector->array (try (canon (array->list (vector->array iv (vector {' '.join(vals)}) sc)))))")
    # and a copy of the typed array back to generic and to itself
    L.append("(show 'copy-generic (try (canon (array->list (array-copy a generic-storage-class)))))")
    L.append("(show 'copy-same (try (canon (array->list (array-copy a)))) (try (eq? sc (array-storage-class (array-copy a)))))")
    L.append("(show 'end)")
    return "\n".join(L) + "\n"


# --- the call/cc-mode generator ----------------------------------------------

CALLCC_PRELUDE = """\
(import (scheme base) (scheme write) (srfi 231))
(define (show . xs) (for-each (lambda (x) (write x) (display " ")) xs) (newline))
;; The kaappi#2539 driver, generalized. `collect` is a procedure of one
;; argument: a hook (lambda (x) ...) that returns x, which the case
;; threads into the source array's getter or into the callback under
;; test. On the FIRST run the hook captures its continuation at two
;; positions; afterwards the schedule re-invokes those continuations with
;; fresh values in the generated order, and every result the procedure
;; returned -- first run and each re-entry -- is recorded. All of it is
;; one procedure body, so a re-entered continuation resumes inside this
;; frame and never re-executes a top-level form. The schedule index and
;; the result list are shared mutable state on purpose: that is the
;; caller's own state, which each re-entry is meant to see.
(define (drive collect p1 p2 schedule)
  (let* ((cont1 #f) (cont2 #f) (first-run? #t) (i 0) (results '())
         (hook (lambda (x)
                 (call-with-current-continuation
                  (lambda (c)
                    (if first-run?
                        (cond ((= x p1) (set! cont1 c))
                              ((= x p2) (set! cont2 c))))
                    x)))))
    (let ((r (collect hook)))
      (set! first-run? #f)
      (set! results (cons r results)))
    ;; a step whose continuation was never captured (the walk stopped
    ;; before its position: array-any past its short-circuit, a reduce
    ;; seeded from element 0) is skipped, never allowed to end the
    ;; schedule and starve the steps after it
    (let loop ()
      (if (< i (length schedule))
          (let ((step (list-ref schedule i)))
            (set! i (+ i 1))
            (let ((k (if (= (car step) 1) cont1 cont2)))
              (if k (k (cdr step)) (loop))))))
    ;; which positions were reached is itself a differential signal: a
    ;; differing short-circuit point or fold seeding shows up here
    (show 'captured (and cont1 #t) (and cont2 #t))
    (reverse results)))
;; escape variant: the hook throws to a continuation OUTSIDE the
;; procedure under test at position p1, then the same procedure is run
;; again with an identity hook -- the escape must not have left it or
;; its inputs in a state the second run can observe
(define (escape collect p1)
  (list (call-with-current-continuation
         (lambda (k)
           (collect (lambda (x) (if (= x p1) (k (list 'escaped x)) x)))))
        (collect (lambda (x) x))))
"""

# Each family is (name, template). In the template, {A} is the source
# array expression and {H} the hook; a template that uses {H} directly
# puts the capture in the callback, one that only uses {A} relies on the
# getter capture. {IV} is the domain, {L} a lambda mapping a multi-index
# to its linear position (so a capture position means the same thing in
# every dimension).
CALLCC_FAMILIES = [
    # capture in the source array's getter
    ("copy", "(array->list* (array-copy {A}))"),
    ("copy-typed", "(array->list* (array-copy {A} s32-storage-class))"),
    ("->list", "(array->list {A})"),
    ("->vector", "(array->vector {A})"),
    ("->list*", "(array->list* {A})"),
    ("->vector*", "(array->vector* {A})"),
    ("fold-left", "(reverse (array-fold-left (lambda (acc x) (cons x acc)) '() {A}))"),
    ("fold-right", "(array-fold-right cons '() {A})"),
    ("reduce", "(array-reduce + {A})"),
    ("every", "(array-every list {A})"),
    ("any", "(array-any (lambda (x) (and (>= x 2) (list x))) {A})"),
    # the for-each families accumulate through a set! cell on the CALLER's
    # side, which is legitimate -- but (set! acc (cons (h x) acc)) would read
    # acc before or after the capture depending on the implementation's
    # argument evaluation order (unspecified by R7RS; chibi is right-to-left),
    # so the hook's value is always bound first
    ("for-each", "(let ((acc '())) (array-for-each (lambda (x) (set! acc (cons x acc))) {A}) (reverse acc))"),
    ("map-copy", "(array->list* (array-copy (array-map (lambda (x) (* 2 x)) {A})))"),
    # the same source twice: the hook fires twice per position and the later
    # capture at p1 overwrites the earlier, which is benign only because both
    # calls carry the same position and + commutes. An implementation that
    # read a duplicated source once per position would show a re-entry as
    # (+ v v) rather than (+ v p1) -- that is what a mismatch here means.
    ("map2-copy", "(array->list* (array-copy (array-map + {A} {A})))"),
    ("stack", "(array->list* (array-stack 0 (list {A} (make-array {IV} (lambda idx 99)))))"),
    ("append", "(array->list* (array-append 0 (list {A} (make-array {IV} (lambda idx 99)))))"),
    # the outer array of blocks must have the pieces' rank: two blocks
    # stacked along axis 0, so its domain is 2 x 1 x ... x 1
    ("block", "(array->list* (array-block (list->array {OUTER} (list (array-copy {A}) (array-copy {A})))))"),
    ("decurry", "(array->list* (array-decurry (list->array (make-interval '#(2)) (list {A} (make-array {IV} (lambda idx 99))))))"),
    ("interval-fold-left", "(reverse (interval-fold-left (lambda idx ({H} ({L} idx))) (lambda (acc x) (cons x acc)) '() {IV}))"),
    ("interval-fold-right", "(interval-fold-right (lambda idx ({H} ({L} idx))) cons '() {IV})"),
    ("interval-for-each", "(let ((acc '())) (interval-for-each (lambda idx (let ((y ({H} ({L} idx)))) (set! acc (cons y acc)))) {IV}) (reverse acc))"),
    # capture in the callback, over a plain (non-capturing) array
    ("kernel-fold-left", "(reverse (array-fold-left (lambda (acc x) (cons ({H} x) acc)) '() {P}))"),
    ("kernel-fold-right", "(array-fold-right (lambda (x acc) (cons ({H} x) acc)) '() {P})"),
    ("kernel-reduce", "(array-reduce (lambda (a b) (+ a ({H} b))) {P})"),
    ("kernel-every", "(array-every (lambda (x) (list ({H} x))) {P})"),
    ("kernel-any", "(array-any (lambda (x) (let ((y ({H} x))) (and (>= y 2) (list y)))) {P})"),
    ("kernel-for-each", "(let ((acc '())) (array-for-each (lambda (x) (let ((y ({H} x))) (set! acc (cons y acc)))) {P}) (reverse acc))"),
    ("kernel-map-copy", "(array->list* (array-copy (array-map (lambda (x) ({H} x)) {P})))"),
    ("kernel-interval-fold-left", "(reverse (interval-fold-left (lambda idx ({L} idx)) (lambda (acc x) (cons ({H} x) acc)) '() {IV}))"),
]


def gen_callcc(seed, classes=None, spec=None):
    rng = random.Random(seed)
    # a small domain: 1-D of 4..6, or 2-D 2x2 / 2x3 / 3x2, lower bounds 0
    shape = rng.choice([[4], [5], [6], [2, 2], [2, 3], [3, 2]])
    n = 1
    for w in shape:
        n *= w
    iv = f"(make-interval {fmt_vec(shape)})"
    if len(shape) == 1:
        lin = "(lambda (idx) (car idx))"
    else:
        lin = f"(lambda (idx) (+ (* (car idx) {shape[1]}) (cadr idx)))"
    p1 = rng.randrange(0, n - 1)
    p2 = rng.randrange(p1 + 1, n)
    name, tmpl = rng.choice(CALLCC_FAMILIES)
    # the getter-capturing source: element = linear position through the hook
    A = f"(make-array {iv} (lambda idx (h ({lin} idx))))"
    # the plain source for callback-capturing families
    P = f"(make-array {iv} (lambda idx ({lin} idx)))"
    outer = f"(make-interval {fmt_vec([2] + [1] * (len(shape) - 1))})"
    body = tmpl.format(A=A, P=P, H="h", IV=iv, L=lin, OUTER=outer)
    L = [CALLCC_PRELUDE, f"(define collect (lambda (h) {body}))"]
    L.append(f"(show 'family '{name} 'shape '({' '.join(map(str, shape))}) 'p1 {p1} 'p2 {p2})")
    if rng.random() < 0.2:
        L.append(f"(show 'escape (escape collect {p1}))")
    else:
        # 3-5 re-invocations, each of a random continuation with a fresh value
        steps = [(rng.choice([1, 2]), rng.randint(10, 40)) for _ in range(rng.randint(3, 5))]
        sched = " ".join(f"(cons {c} {v})" for c, v in steps)
        L.append(f"(show 'schedule '({' '.join(f'({c} {v})' for c, v in steps)}))")
        L.append(f"(show 'results (drive collect {p1} {p2} (list {sched})))")
    L.append("(show 'end)")
    return "\n".join(L) + "\n"


# --- the prose-examples mode: the spec's code blocks as a corpus -------------

SPEC_URL = "https://srfi.schemers.org/srfi-231/srfi-231.html"

PROSE_PRELUDE = """\
(import (scheme base) (scheme write) (scheme inexact) (scheme complex)
        (scheme char) (scheme cxr) (srfi 1) (srfi 4) (srfi 231))
(define-syntax try
  (syntax-rules () ((_ e) (guard (c (#t 'ERROR)) e))))
(define (dom a)
  (let ((d (array-domain a)))
    (list (interval-lower-bounds->list d) (interval-upper-bounds->list d))))
;; one printable form for everything an example can evaluate to, written
;; identically by every implementation: arrays as domain + contents (so a
;; lazy array is forced through its own getter, which is what the example
;; is about), intervals as bounds, opaque things as a tag, floats as exact
;; rationals, the unspecified value as a symbol
(define (render v)
  (cond ((eq? v (if #f #f)) 'unspecified)
        ((array? v) (list 'array (dom v) (render (try (array->list* v)))))
        ((interval? v) (list 'interval (interval-lower-bounds->list v)
                             (interval-upper-bounds->list v)))
        ((storage-class? v) 'storage-class)
        ((procedure? v) 'procedure)
        ((pair? v) (cons (render (car v)) (render (cdr v))))
        ((vector? v) (list 'vec (render (vector->list v))))
        ((and (real? v) (exact? v)) v)
        ((real? v) (cond ((nan? v) '(nan))
                         ((infinite? v) (if (> v 0) '(inf 1) '(inf -1)))
                         (else (exact v))))
        ((number? v) (list 'c (render (real-part v)) (render (imag-part v))))
        ((char? v) (list 'ch (char->integer v)))
        ;; every SRFI 4 body type, so a body an example displays never
        ;; reaches write (whose float spelling differs)
        ((u8vector? v) (list 'u8 (u8vector->list v)))
        ((s8vector? v) (list 's8 (s8vector->list v)))
        ((u16vector? v) (list 'u16 (u16vector->list v)))
        ((s16vector? v) (list 's16 (s16vector->list v)))
        ((u32vector? v) (list 'u32 (u32vector->list v)))
        ((s32vector? v) (list 's32 (s32vector->list v)))
        ((u64vector? v) (list 'u64 (u64vector->list v)))
        ((s64vector? v) (list 's64 (s64vector->list v)))
        ((f32vector? v) (render (list 'f32 (f32vector->list v))))
        ((f64vector? v) (render (list 'f64 (f64vector->list v))))
        (else v)))
;; the examples display array bodies (homogeneous vectors, whose written
;; form is implementation-specific) and call Gambit's pretty printer,
;; whose line breaking would never match -- so both implementations get
;; these: strings and chars verbatim, everything else rendered
(define (display x . port)
  (cond ((string? x) (write-string x))
        ((char? x) (write-char x))
        (else (write (render x)))))
(define (show . xs) (for-each (lambda (x) (write x) (write-string " ")) xs) (newline))
(define (pretty-print x . port) (write (render x)) (newline))
(define (pp x . port) (write (render x)) (newline))
;; Gambit built-ins the examples use without importing anything
(define (identity x) x)
(define (fl+ a b) (+ a b))
(define (fl- a b) (- a b))
(define (fl* a b) (* a b))
(define (fl/ a b) (/ a b))
(define (flsqrt a) (sqrt a))
(define (flsquare a) (* a a))
(define (fx+ a b) (+ a b))
(define (fx- a b) (- a b))
(define (fx* a b) (* a b))
(define (fx< a b) (< a b))
(define (fx<= a b) (<= a b))
(define (fx= a b) (= a b))
(define (fx> a b) (> a b))
(define (fx>= a b) (>= a b))
(define (fxquotient a b) (quotient a b))
(define (fxremainder a b) (remainder a b))
"""

# a block containing any of these needs files, a clock, or randomness
PROSE_SKIP_MARKERS = ["read-char", "read-line", "open-input", "open-output",
                      "call-with-input", "call-with-output", "with-input-from",
                      "with-output-to", "read-pgm", "write-pgm", "(time ",
                      "random", "(include ",
                      # signature lines with optional arguments are prose
                      "[",
                      # a lazy array of 10^9 elements summed in blocks: the
                      # reference needs minutes for it
                      "'#(1000000001)"]


def tokenize_scheme(src):
    """Yield (kind, start, end) over src: kind in open/close/prefix/atom."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c.isspace():
            i += 1
        elif c == ";":
            while i < n and src[i] != "\n":
                i += 1
        elif src.startswith("#|", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith("#|", i):
                    depth, i = depth + 1, i + 2
                elif src.startswith("|#", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
        elif src.startswith("#;", i):
            yield ("datum-comment", i, i + 2)
            i += 2
        elif c in "([":
            yield ("open", i, i + 1)
            i += 1
        elif c in ")]":
            yield ("close", i, i + 1)
            i += 1
        elif c == "#" and i + 1 < n and (src[i + 1] == "(" or re.match(r"[usfc]\d+\(", src[i + 1:])):
            j = src.index("(", i)
            yield ("open", i, j + 1)
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            yield ("atom", i, j + 1)
            i = j + 1
        elif src.startswith("#\\", i):
            j = i + 3
            while j < n and not src[j].isspace() and src[j] not in "()[]":
                j += 1
            yield ("atom", i, max(j, i + 3))
            i = max(j, i + 3)
        elif c in "'`":
            yield ("prefix", i, i + 1)
            i += 1
        elif c == ",":
            j = i + 2 if src.startswith(",@", i) else i + 1
            yield ("prefix", i, j)
            i = j
        else:
            j = i
            while j < n and not src[j].isspace() and src[j] not in "()[];\"":
                j += 1
            yield ("atom", i, j)
            i = j


def parse_scheme(src):
    """Return top-level nodes: ('list', children, start, end) or ('atom', start, end).
    A prefixed datum ('x, `x, ,x) is one node spanning the prefix too."""
    toks = list(tokenize_scheme(src))
    pos = 0

    def datum():
        nonlocal pos
        kind, a, b = toks[pos]
        if kind == "datum-comment":
            pos += 1
            if pos < len(toks):
                datum()
            return None
        if kind == "prefix":
            pos += 1
            inner = datum()
            return ("atom", a, inner[-1]) if inner else ("atom", a, b)
        if kind == "open":
            pos += 1
            children = []
            while pos < len(toks) and toks[pos][0] != "close":
                d = datum()
                if d:
                    children.append(d)
            end = toks[pos][2] if pos < len(toks) else b
            pos += 1
            return ("list", children, a, end)
        pos += 1
        return ("atom", a, b)

    out = []
    while pos < len(toks):
        d = datum()
        if d:
            out.append(d)
    return out


def node_text(src, node):
    return src[node[-2]:node[-1]] if node[0] == "list" else src[node[1]:node[2]]


def head_of(src, node):
    if node[0] == "list" and node[1] and node[1][0][0] == "atom":
        return node_text(src, node[1][0])
    return None


LET_FORMS = {"let", "let*", "letrec", "letrec*"}
KEEP_FORMS = {"define", "define-record-type", "define-syntax", "define-values",
              "import", "define-macro"}


def wrap_expr(text):
    return f"(show 'v (try (render {text})))"


def defined_name(src, node):
    kids = node[1]
    if len(kids) < 2:
        return None
    target = kids[1]
    if target[0] == "list" and target[1]:
        return node_text(src, target[1][0])
    return node_text(src, target)


def transform_define(src, node):
    """(define name expr) -> guarded, so a failing definition still binds."""
    kids = node[1]
    if len(kids) == 3 and kids[1][0] == "atom":
        return f"(define {node_text(src, kids[1])} (try {node_text(src, kids[2])}))"
    return node_text(src, node)


def transform_toplevel(src, node):
    head = head_of(src, node)
    if head == "define":
        return transform_define(src, node)
    if head in KEEP_FORMS:
        return node_text(src, node)
    if head == "begin":
        return "\n".join(transform_toplevel(src, k) for k in node[1][1:])
    if head in LET_FORMS:
        kids = node[1]
        body_from = 3 if (head == "let" and len(kids) > 1 and kids[1][0] == "atom") else 2
        if len(kids) > body_from:
            # wrap each body expression in place, last first so offsets hold
            text = node_text(src, node)
            base = node[-2]
            for k in reversed(kids[body_from:]):
                if head_of(src, k) in KEEP_FORMS or k[-1] <= k[-2]:
                    continue
                a, b = k[-2] - base, k[-1] - base
                text = text[:a] + wrap_expr(text[a:b]) + text[b:]
            # the bindings themselves run outside the body's guards, and
            # several examples bind free pseudocode variables there
            return f"(let ((r (try {text}))) (if (eq? r 'ERROR) (show 'form 'ERROR)))"
    if node[-1] <= node[-2]:
        return ""
    return wrap_expr(node_text(src, node))


_PROSE = None


def load_prose(spec):
    """(revision line, [(pre-index, code, following-output-or-None)])."""
    global _PROSE
    if _PROSE is not None:
        return _PROSE
    if re.match(r"https?://", spec):
        with urllib.request.urlopen(spec, timeout=60) as r:
            page = r.read().decode("utf-8", errors="replace")
    else:
        page = open(spec, encoding="utf-8", errors="replace").read()
    pres = [html_mod.unescape(re.sub(r"<[^>]+>", "", x))
            for x in re.findall(r"<pre[^>]*>(.*?)</pre>", page, re.S)]
    rev = re.findall(r"(\d{4}-\d{2}-\d{2}) \(([^)]*)\)", page)
    revision = (f"spec revision {rev[-1][0]} ({re.sub(r'<[^>]+>', '', rev[-1][1])})"
                if rev else "spec revision unknown")
    # the SRFI's own export surface, from its "Procedure: (name ..." headings
    text = html_mod.unescape(re.sub(r"<[^>]+>", "", page))
    exports = set(re.findall(r"^\s*(?:Procedure|Variable|Parameter|Syntax):\s*\(?([^\s()]+)", text, re.M))
    examples = []
    for i, text in enumerate(pres):
        if not text.lstrip().startswith("("):
            continue
        nxt = pres[i + 1] if i + 1 < len(pres) and not pres[i + 1].lstrip().startswith("(") else None
        examples.append((i, text.strip("\n"), nxt))
    _PROSE = (revision, examples, exports)
    return _PROSE


def prose_skip_reason(code):
    for m in PROSE_SKIP_MARKERS:
        if m in code:
            return m
    return None


def quote_digit_identifiers(code):
    """1D-transform and 2x2-matrix-multiply-into! are identifiers to Gambit
    but not to an R7RS reader (Kaappi's says so); |...| is read by both."""
    def fix(m):
        tok = m.group(1)
        if re.fullmatch(r"[0-9]+(?:e[-+]?[0-9]+|i|/[0-9]+)?", tok):
            return tok
        return f"|{tok}|"
    return re.sub(r"(?<![\w#\\|.'-])([0-9]+[A-Za-z][-\w!?*<>=/+]*)", fix, code)


def prose_code_kind(code):
    """'code', or why this block is not: unbalanced, or a data literal."""
    depth = 0
    for kind, a, b in tokenize_scheme(code):
        if kind == "open":
            depth += 1
        elif kind == "close":
            depth -= 1
            if depth < 0:
                return "unbalanced"
    if depth != 0:
        return "unbalanced"
    # a result listing starts with nested lists whose innermost head is a
    # number or an empty list; code starts with an operator symbol (or an
    # application like ((storage-class-maker sc) n v), whose innermost
    # head is still a symbol)
    # judged by the first top-level form only: later bare numbers are the
    # spec's "=> 78498" annotations, which the transform turns into comments
    nodes = parse_scheme(code)
    n = nodes[0] if nodes else None
    while n and n[0] == "list":
        if not n[1]:
            return "data, not code"
        n = n[1][0]
    if n and re.match(r"[-+]?[0-9.]", node_text(code, n)):
        return "data, not code"
    return "code"


def gen_prose(seed, classes=None, spec=SPEC_URL):
    revision, examples, exports = load_prose(spec)
    idx = seed - 1
    if not 0 <= idx < len(examples):
        raise IndexError(f"prose example {seed} is out of range 1..{len(examples)}")
    pre_i, code, following = examples[idx]
    code = quote_digit_identifiers(code)
    L = [PROSE_PRELUDE, f";; {revision}; example {seed} of {len(examples)} (spec <pre> block {pre_i})"]
    reason = prose_skip_reason(code)
    if not reason and prose_code_kind(code) != "code":
        reason = prose_code_kind(code)
    if reason:
        L.append(f"(show 'skipped \"{reason}\")")
        L.append("(show 'end)")
        return "\n".join(L) + "\n"
    # context: every definition the earlier blocks made, in order
    ctx = []
    for j in range(idx):
        pj, cj, _ = examples[j]
        cj = quote_digit_identifiers(cj)
        if prose_skip_reason(cj) or prose_code_kind(cj) != "code":
            continue
        try:
            for node in parse_scheme(cj):
                if head_of(cj, node) not in KEEP_FORMS:
                    continue
                # the prose also shows illustrative definitions of the
                # library's own procedures (index-first, array-curry ...);
                # carrying those forward would make later examples run the
                # pseudocode instead of the implementation under test
                if head_of(cj, node) == "define" and defined_name(cj, node) in exports:
                    continue
                ctx.append(transform_toplevel(cj, node))
        except Exception:
            continue
    if ctx:
        L.append(";; --- definitions from earlier examples ---")
        L.extend(ctx)
    L.append(f";; --- example {seed} ---")
    nodes = parse_scheme(code)
    k = 0
    while k < len(nodes):
        node = nodes[k]
        # the spec writes "(expr) => value" on one line in some blocks: the
        # arrow and its datum are the expectation, not code -- keep them as
        # a comment beside the expression they annotate
        if node[0] == "atom" and node_text(code, node) == "=>":
            expected = node_text(code, nodes[k + 1]) if k + 1 < len(nodes) else ""
            L.append(";; spec: => " + " ".join(expected.split()))
            k += 2
            continue
        L.append(transform_toplevel(code, node))
        k += 1
    if following:
        L.append(";; the spec says this shows:")
        L.extend(";;   " + ln for ln in following.strip("\n").splitlines())
    L.append("(show 'end)")
    return "\n".join(L) + "\n"


MODES = {"reshape": gen_reshape, "storage": gen_storage, "callcc": gen_callcc,
         "prose": gen_prose}


# --- running -----------------------------------------------------------------

TIMED_OUT = object()  # never compares equal to an exit status


def run_one(cmd, path, env, timeout):
    try:
        p = subprocess.run(cmd + [path], capture_output=True, text=True,
                           timeout=timeout, env=env)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        return TIMED_OUT, (e.stdout or b"").decode(errors="replace"), "timed out"


def normalize(out):
    return "\n".join(line.rstrip() for line in out.strip().splitlines())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("mode", choices=sorted(MODES))
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=None,
                    help="cases to run (default 100; prose: every remaining example)")
    ap.add_argument("--oracle", choices=["gambit", "chibi"], default="gambit")
    ap.add_argument("--kaappi", default=os.path.join(ROOT, "zig-out", "bin", "kaappi"))
    ap.add_argument("--gsi", default=shutil.which("gsi") or "/opt/homebrew/bin/gsi")
    ap.add_argument("--chibi", default=shutil.which("chibi-scheme") or "chibi-scheme")
    ap.add_argument("--save", default=None,
                    help="directory for mismatching cases (default: a temp dir, created on the first mismatch)")
    ap.add_argument("--keep", action="store_true",
                    help="do not delete the work dir (generated cases, warm KAAPPI_HOME) on exit")
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--print", action="store_true", help="print the first case's program and exit")
    ap.add_argument("--classes", default=None,
                    help="storage mode: comma-separated storage classes to draw from "
                         "(default all 16), e.g. --classes u1,f16,c64")
    ap.add_argument("--spec", default=SPEC_URL,
                    help="prose mode: the srfi-231.html to take examples from (path or URL)")
    args = ap.parse_args()

    classes = None
    if args.classes:
        classes = args.classes.split(",")
        bad = [c for c in classes if c not in CLASSES]
        if bad:
            sys.exit(f"unknown storage class(es): {', '.join(bad)}; known: {', '.join(CLASSES)}")

    if args.mode == "prose":
        revision, examples, _ = load_prose(args.spec)
        remaining = len(examples) - args.seed + 1
        args.count = remaining if args.count is None else max(0, min(args.count, remaining))
        print(f"prose: {len(examples)} code examples, {revision}")
    elif args.count is None:
        args.count = 100

    def gen(seed):
        return MODES[args.mode](seed, classes, args.spec)

    if args.print:
        sys.stdout.write(gen(args.seed))
        return 0

    oracle = args.gsi if args.oracle == "gambit" else args.chibi
    for name, exe, hint in (("kaappi", args.kaappi, "run zig build, or pass --kaappi"),
                            (args.oracle, oracle, "brew install gambit-scheme / chibi-scheme, or pass --gsi/--chibi")):
        if not (os.access(exe, os.X_OK) or shutil.which(exe)):
            sys.exit(f"no {name} binary at {exe} ({hint})")

    work = tempfile.mkdtemp(prefix="srfi231-diff-work-")
    try:
        return run(args, gen, [oracle], work)
    finally:
        if args.keep:
            print(f"work dir kept: {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


def run(args, gen, oracle_cmd, work):
    # one isolated KAAPPI_HOME for the whole run: the checkout's lib/ wins over
    # any ~/.kaappi/lib (kaappi#2352) and the .sld cache warms once
    env = dict(os.environ, KAAPPI_HOME=os.path.join(work, "home"))
    os.makedirs(env["KAAPPI_HOME"])
    save = args.save  # created on the first mismatch, so a clean run leaves nothing behind

    mismatches = 0
    skipped = 0
    silent = 0   # programs that printed no value at all (definitions only)
    vacuous = 0  # programs whose every printed value was ERROR
    for seed in range(args.seed, args.seed + args.count):
        prog = gen(seed)
        path = os.path.join(work, f"{args.mode}-{seed}.scm")
        with open(path, "w") as f:
            f.write(prog)
        kc, ko, ke = run_one([args.kaappi], path, env, args.timeout)
        oc, oo, oe = run_one(oracle_cmd, path, env, args.timeout)
        # a timeout on either side is always a finding -- a hang with the
        # same partial output as the other side's error is the case that
        # matters most, not the one to hide
        timed_out = kc is TIMED_OUT or oc is TIMED_OUT
        same = (not timed_out and normalize(ko) == normalize(oo)
                and (kc == 0) == (oc == 0))
        # equal output is not the same as a comparison: a program whose
        # values are all ERROR on both sides (a prose fragment with free
        # variables, or a broken prelude) agrees trivially, and a summary
        # of "0 mismatches" must not hide that
        lines = [ln for ln in normalize(ko).splitlines() if ln and ln != "end"]
        if any(ln.startswith("skipped ") for ln in lines):
            skipped += 1
        elif not lines:
            silent += 1
        elif all(ln.endswith("ERROR") for ln in lines):
            vacuous += 1
        if same:
            continue
        mismatches += 1
        if save is None:
            save = tempfile.mkdtemp(prefix="srfi231-diff-")
        os.makedirs(save, exist_ok=True)
        dst = os.path.join(save, f"{args.mode}-{seed}.scm")
        shutil.copy(path, dst)
        for label, code, out, err in (("kaappi", kc, ko, ke), (args.oracle, oc, oo, oe)):
            with open(f"{dst}.{label}.txt", "w") as f:
                status = "timed out" if code is TIMED_OUT else f"exit {code}"
                f.write(f"{status}\n--- stdout\n{out}\n--- stderr\n{err}")
        print(f"MISMATCH seed {seed}: {dst}")
        if timed_out:
            who = [n for n, c in (("kaappi", kc), (args.oracle, oc)) if c is TIMED_OUT]
            print(f"  timed out after {args.timeout}s: {', '.join(who)}")
            continue
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

    note = ""
    if skipped or silent or vacuous:
        note = (f"; {skipped} skipped, {silent} printed no value (definitions only), "
                f"{vacuous} compared nothing (every value ERROR on both sides)")
    print(f"{args.mode}: {args.count} cases from seed {args.seed}, oracle {args.oracle}, "
          f"{mismatches} mismatches" + (f" saved under {save}" if mismatches else "") + note)
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
