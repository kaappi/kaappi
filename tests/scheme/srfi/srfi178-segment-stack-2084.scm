;; Regression test for #2084: bitvector-segment recursed once per segment
;; with the cons outside the recursive call, so this legal call consumed one
;; frame per segment and died past the 32,768 frame cap with an uncatchable
;; KP3008. The loop now accumulates in tail position; this file pins that at
;; full, cap-exceeding depth.
;;
;; Its own file, apart from srfi178-audit.scm, deliberately: under
;; -Dgc-stress=true a collection runs on every allocation, so building
;; 200,000 bitvectors is quadratic in the live heap (measured ~3 min at 40k
;; on a fast machine, extrapolating to over an hour at 200k). ci.yml's
;; KAAPPI_GC_STRESS_SKIP lists this file (reason (a), too slow under stress)
;; so the stress leg can skip exactly the deep case without losing the
;; audit file's other assertions — including the n = 0 guard half of #2084,
;; which stays stressed there. run-all.sh runs this plain on every PR,
;; where it takes well under a second.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 178))

(test-begin "srfi178-segment-stack-2084")

(test-equal "segment of a 200,000-bit vector with n=1 (no frame per segment)"
            200000 (length (bitvector-segment (make-bitvector 200000 1) 1)))

(let ((runner (test-runner-current)))
  (test-end "srfi178-segment-stack-2084")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
