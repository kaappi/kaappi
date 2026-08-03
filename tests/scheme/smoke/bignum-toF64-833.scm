;; Regression test for #833: bignum toF64 double-rounds per limb
;; n = (2^53 + 1) * 2^64 + 1 — exercises the guard bit

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "bignum-toF64-833")

(define n 166153499473114502559719956244594689)
(define f (inexact n))
(define back (exact f))

;; Should match Python's int(float(n)):
(test-equal "inexact->exact round trip matches the correctly-rounded double"
            166153499473114521006464029954146304
            back)

(let ((runner (test-runner-current)))
  (test-end "bignum-toF64-833")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
