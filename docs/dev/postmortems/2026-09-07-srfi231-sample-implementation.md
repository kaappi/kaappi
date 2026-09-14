# SRFI 231: the sample implementation is not the specification

Postmortem of a three-PR loop (kaappi#2543, #2558, #2559) in which a
differential tester's disagreement with Gambit was filed as a bug, fixed by
matching Gambit, then reverted once the SRFI's author explained that the
bundled code is a *sample* implementation and the document is the spec —
and that the disagreement was about R6RS versus R7RS, not about SRFI 231.

## Status

**Resolved** (2026-09-09, PR #2559 closing the loop; #2558 corrected the
terminology). The c64/c128 storage-class checkers run the sample
implementation's line verbatim and accept a bare real flonum. Kaappi and
Gambit disagree on c64/c128 permanently, and that is not a bug:
`tools/srfi231_diff.py` draws those classes only when `--classes` names
them, and the divergence is recorded in the tool so it is not re-filed.
The implementation notes no longer describe a "trust the code" rule as
the SRFI's.

## The chain

1. The differential tester's first batch found that Kaappi's c64/c128
   checkers accept `1.0` where Gambit rejects it (kaappi#2542).
2. #2543 added `(not (real? x))` to the checkers to reproduce Gambit's
   verdict, on the reasoning that the bundled code was the reference and
   its verdict governed.
3. Brad Lucier, the SRFI's author, corrected two things on r/KaappiScheme.
   The document uses "sample implementation" fifteen times and "reference
   implementation" never, and "generally speaking the document is the
   specification." And the verdicts differ for a reason outside the SRFI:
   the checker is textually `(and (complex? obj) (inexact? (real-part obj))
   (inexact? (imag-part obj)))` on both sides, but Gambit's
   `(imag-part 1.0)` is an exact `0` and Kaappi's is `0.0`. Exact-0 is
   **R6RS**'s rule, adopted there on his own suggestion; "that's not what
   R7RS small does."
4. #2558 renamed every "reference implementation" across the `.sld`
   files, `testing.md` and the tool, and demoted the tester's oracle to a
   second opinion. #2559 reverted the checker clause.

## What the spec actually says

Checked against `docs/errata-corrected-r7rs.pdf` §6.2.6 rather than taken
on report. Its only exactness permission is that `real-part` and
`imag-part` "may return exact real numbers when applied to an inexact
complex number if the corresponding argument passed to `make-rectangular`
was exact", which a bare `1.0` never went through. What governs is
"`(real? z)` is true if and only if `(zero? (imag-part z))` is true", and
`(zero? 0.0)` is `#t`, so an inexact `0.0` satisfies it exactly as an
exact `0` would. Nothing requires one over the other. (The iff rule does
not survive the inexact-zero-imaginary case either: the same section
prints `(real? -2.5+0.0i) ⇒ #f`, which the rule would make `#t`; every
implementation, Kaappi and Gambit included, follows the example.)

SRFI 231's own normative constraint on a checker is only that
`(checker (getter v i))` be `#t`, which holds either way. Two other items
put to the author in the same thread: `array-inner-product`'s prose omits
an `array-curry` argument the sample code supplies, which he confirmed is
a document error he will fix; and `check-nested-list`'s dimension-0 case
differs between prose and code, which is moot because the library does
not export it. Neither supported the heuristic they had been cited for.

## Consequences kept

- **Where prose and sample code disagree, the prose governs** unless
  there is positive reason to think it is an error. A divergence that
  turns on the *host's* representation choices is not such a reason.
- **The c64/c128 divergence cascades.** Once the checker accepts, the
  setter runs and array contents diverge too. A post-filter on the
  tester's output was tried and abandoned: tight enough to be safe it
  caught one of three instances (infinities canonicalize as `(inf 1)`);
  loose enough to catch them all it would model the whole downstream
  consequence, which is the shape that would later hide a real c64 setter
  bug. Narrowing the *draw* filters nothing.
- **A residual the checker cannot reach:** a mixed-exactness complex
  (`1+2.0i`) keeps an exact real part under Gambit and is rejected there,
  while Kaappi's representation makes exactness contagious and accepts
  it. If the tester's value pool ever grows such a literal, that verdict
  is this known residual, not a finding.

## Lessons

- **Read the spec's own words before asserting what it says.** We wrote
  "this SRFI's documented rule" about a heuristic we invented; the
  document says no such thing.
- **A differential oracle is a lead, not a verdict**, especially across
  standards: two R7RS-legal implementations can disagree where R7RS is
  silent, and the oracle's host may be following a different standard.
- **When a divergence is permanent, record it in the tool** so the next
  run does not re-file it.
