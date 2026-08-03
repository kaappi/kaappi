;; Regression tests for #842 and #848

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "exact-inexact-842-848")

;; #842: exact with dyadic denominator 2^47 must not produce negative denominator
(let ((x (exact (/ 3.0 (expt 2.0 47)))))
  (test-assert "(exact 3/2^47) is positive" (positive? x))
  (test-assert "(inexact (exact 3/2^47)) is positive" (> (inexact x) 0)))

;; #848: inexact on rationals with huge components must not return NaN
(test-equal "inexact of (10^400+1)/10^399"
            10.0 (inexact (/ (+ (expt 10 400) 1) (expt 10 399))))
(test-equal "inexact of (2^2000+1)/2^2000"
            1.0 (inexact (/ (+ (expt 2 2000) 1) (expt 2 2000))))

(let ((runner (test-runner-current)))
  (test-end "exact-inexact-842-848")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
