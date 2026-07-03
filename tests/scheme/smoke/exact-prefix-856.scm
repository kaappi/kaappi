;; Regression test for #856: string->number #e prefix wrong for small/large decimals
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "exact-prefix-856")

;; Core bug cases — use expressions for rationals whose denominator exceeds i64
(test-equal "#e1e-20" (/ 1 (expt 10 20)) (string->number "#e1e-20"))
(test-equal "#e1.5e-15" (/ 3 (expt 2 1) (expt 10 15)) (string->number "#e1.5e-15"))
(test-equal "#e1e400 is exact" #t (exact? (string->number "#e1e400")))
(test-equal "#e1e400 value" (expt 10 400) (string->number "#e1e400"))

;; Results must be exact
(test-assert "#e1e-20 exact" (exact? (string->number "#e1e-20")))
(test-assert "#e1.5e-15 exact" (exact? (string->number "#e1.5e-15")))

;; Edge cases
(test-equal "#e.5" 1/2 (string->number "#e.5"))
(test-equal "#e5." 5 (string->number "#e5."))
(test-equal "#e-1e-20" (/ -1 (expt 10 20)) (string->number "#e-1e-20"))
(test-equal "#e0.0" 0 (string->number "#e0.0"))
(test-equal "#e1e0" 1 (string->number "#e1e0"))
(test-equal "#e-0.0" 0 (string->number "#e-0.0"))

;; Existing behavior preserved
(test-equal "#e0.1" 1/10 (string->number "#e0.1"))
(test-equal "#e1.5" 3/2 (string->number "#e1.5"))
(test-equal "#e2.0" 2 (string->number "#e2.0"))
(test-equal "#e1e20" (expt 10 20) (string->number "#e1e20"))
(test-equal "#e+inf.0" #f (string->number "#e+inf.0"))
(test-equal "#e+nan.0" #f (string->number "#e+nan.0"))
(test-assert "3.14 inexact" (inexact? (string->number "3.14")))

(let ((runner (test-runner-current)))
  (test-end "exact-prefix-856")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
