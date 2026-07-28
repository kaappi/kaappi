;;; SRFI 149 — Basic Syntax-rules Template Extensions.
;;;
;;; Specifies two extensions to R7RS-small syntax-rules templates: (1)
;;; consecutive ellipses directly after one template element (`a ... ...`),
;;; which R7RS's own stricter grammar requires extra parens for instead
;;; (`((a ...) ...)`, a nested single-ellipsis template); (2) letting a
;;; pattern variable be followed by MORE ellipses in the template than its
;;; own pattern-matched depth, with the "excess" ellipses repeating the
;;; variable's already-resolved value at the innermost position (R6RS
;;; specifies the opposite, outermost convention -- this SRFI explicitly
;;; picks innermost, with neither being objectively more correct).
;;;
;;; Confirmed via a dedicated research pass (fetching both the spec text
;;; and, since the spec's own prose gives no worked example for the
;;; genuinely-new nonzero-depth-excess case, the reference implementation's
;;; algorithm) that Kaappi's expander already implements both extensions
;;; correctly with zero code changes: its ellipsis instantiation is driven
;;; by live per-binding depth reduction rather than a static free-variable
;;; scan, so a shallower sibling variable that has already been reduced to
;;; a scalar by an earlier (outer) ellipsis level is naturally held
;;; constant -- replicated -- when a deeper sibling drives further (inner)
;;; iteration, which is exactly the innermost-repeats rule. Verified
;;; against both of the spec's own worked examples (my-append's consecutive
;;; flatten; foo's mixed-depth a/b siblings) plus 2 additional cases -- see
;;; tests/scheme/srfi/srfi149.scm and the "SRFI 149" tests in
;;; src/tests_macros.zig.
;;;
;;; One PRE-EXISTING, unrelated gap found at the time and deliberately left
;;; alone: a template ellipsis with NO driving variable at all (e.g. a
;;; single variable asked for MORE ellipses than its own maximum depth,
;;; with no sibling reaching the requested depth either) silently produced
;;; an empty result instead of erroring. This predated SRFI 149 entirely --
;;; it was not a new case this SRFI introduced or one it needed to support,
;;; and fixing the underlying error-detection leniency was a separate,
;;; broader-blast-radius correctness project of its own, not part of
;;; adding this SRFI's features. FIXED by kaappi#1791: instantiateEllipsis
;;; now raises EllipsisNoPatternVariable instead of silently producing zero
;;; copies, proven safe against this SRFI's own legitimate mixed-depth
;;; sibling case (both call sites already gate on the identical
;;; ellipsisReferencesOuter predicate before reaching the raise site).
;;;
;;; Like SRFI 46 (a sibling "these R7RS extensions are already native"
;;; library), this is a conformance statement, not new functionality: it
;;; just re-exports the same syntax-rules already bound in (scheme base).
(define-library (srfi 149)
  (import (only (scheme base) syntax-rules))
  (export syntax-rules))
