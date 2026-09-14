# SRFI 231: a single re-entry is not evidence of call/cc safety

Postmortem of kaappi#2539: `array-copy` and every accumulating non-`!`
procedure in the SRFI 231 port passed the official suite's continuation
cases and were still not call/cc-safe, because the suite's cases re-enter a
captured continuation once and the defect needs two.

## Status

**Fixed** (2026-09-07, PR #2540, closing kaappi#2539). Every accumulating
procedure without a trailing `!` — `interval-fold-left`/`-right`,
`array-fold-left`/`-right`, `array-reduce`, `array-every`, `array->list`,
and the collection half of `array-copy` — threads its accumulator
functionally through one shared walk, `%interval-fold` in
`lib/srfi/231/intervals.sld`, never through a `set!` cell or a pre-sized
scratch vector. `array-copy` of a non-specialized source collects a
reversed list and fills a fresh body by linear position, the sample
implementation's exact shape. Regression tests drive two continuations,
each invoked twice, through the shared fixture
`tests/scheme/srfi/fixtures/srfi231-reentry.scm`.

## The report

Brad Lucier, the SRFI's author, posted on r/KaappiScheme that a getter
which captures a continuation and re-enters it later observes a partially
overwritten result. The spec's definition is literal: a procedure is
call/cc safe if it "does not modify the state of any data captured by a
continuation", and every procedure without a trailing `!` is intended to
be. Two shipped shapes violated it.

## Why the official suite did not catch it

The `array-copy` collector had been rewritten (kaappi#2454) to fill a
scratch vector directly for speed. A single re-entry of a getter's
continuation cannot tell a shared buffer from a functional accumulator:
the first re-entry simply writes into the buffer again and the result
looks right. Only the *second* re-entry, or a second continuation captured
during the first run, resumes over the earlier re-entry's overwrites. The
official suite's continuation entries (737–741) re-enter once, so the
scratch design passed them.

The fold-left shape had a second, accidental protection. Its accumulator
was a `set!` cell, and Kaappi evaluates arguments left to right, so
`(set! acc (operator acc (apply f ix)))` read `acc` into a register
*before* the getter ran; the old value was already in hand when a
re-entry came back. Under chibi's right-to-left order the same code
returns garbage. A `set!` cell can pass a re-entry test by
evaluation-order luck.

## The fix

The sample implementation's shape, adopted exactly: one shared fold that
threads the accumulator through loop variables and return values, and a
list collector for `array-copy`. Two measured trade-offs were recorded so
the next performance pass does not undo them:

- For a non-specialized source the list collector is *faster* than the
  scratch vector it replaced (73.5 s vs 114.9 s on a 20×1M copy): the old
  copy-out's per-element indexer call cost more than the pairs.
- For a specialized source the direct fill stays, as in the sample
  implementation's own `%!array-copy`: the list path is 1.8× faster there
  but at 14× the peak memory (176 MB vs 12.5 MB on a u8 copy). A
  `make-storage-class` getter or a `specialized-array-share` mapping is
  user code that runs inside that fill and could capture a continuation;
  neither the sample implementation nor Kaappi defends that case, and
  the exemption is documented in `views.sld`.

## Lessons

- **A continuation-safety test must drive at least two continuations,
  each invoked at least twice.** One re-entry proves nothing about
  shared state; it is the second that reads the first's overwrites.
- **A `set!` accumulator that passes is not evidence either.** Argument
  evaluation order can hide the read-before-write; write the accumulator
  as a loop variable and the question does not arise.
- **A property fixed cases cannot see needs a generator.** This is what
  `tools/srfi231_diff.py` exists for: random view and reshape programs
  diffed against the sample implementation under Gambit, in the modes
  `docs/dev/testing.md` lists.
- **Proving a `.sld` regression test fails before the fix needs a clean
  home.** An installed `~/.kaappi/lib` shadows the checkout; run with
  `KAAPPI_HOME` pointing at a temporary tree holding the old file.
