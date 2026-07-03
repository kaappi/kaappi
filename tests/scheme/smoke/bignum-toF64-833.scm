;; Regression test for #833: bignum toF64 double-rounds per limb
;; n = (2^53 + 1) * 2^64 + 1 — exercises the guard bit
(define n 166153499473114502559719956244594689)
(define f (inexact n))
(define back (exact f))
;; Should match Python's int(float(n)):
(display (= back 166153499473114521006464029954146304))
(newline)
