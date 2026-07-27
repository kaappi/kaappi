;; Regression test for #1725: expt doesn't promote to complex for a negative
;; real base combined with a non-integer real exponent.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "expt-negative-base-1725")

(define (close-enough? a b)
  (< (magnitude (- a b)) 1e-9))

;; (-8.0)^0.5 has no real value; principal branch is 2*sqrt(2)*i.
(let ((r (expt -8.0 0.5)))
  (test-assert "expt -8.0 0.5 is not real" (not (real? r)))
  (test-assert "expt -8.0 0.5 is not nan"
    (and (not (nan? (real-part r))) (not (nan? (imag-part r)))))
  (test-assert "expt -8.0 0.5 value"
    (close-enough? r (make-rectangular 0.0 (* 2 (sqrt 2))))))

;; (-8)^(1/3) has no real value; principal branch is 1 + sqrt(3)*i.
(let ((r (expt -8 1/3)))
  (test-assert "expt -8 1/3 is not real" (not (real? r)))
  (test-assert "expt -8 1/3 value"
    (close-enough? r (make-rectangular 1.0 (sqrt 3)))))

;; sqrt already got this right — expt should agree with it.
(test-assert "expt -8.0 0.5 agrees with sqrt"
  (close-enough? (expt -8.0 0.5) (sqrt -8.0)))

;; Integer exponents (even via a flonum) must stay real for a negative base.
(test-equal "expt -8.0 -2 stays real" 0.015625 (expt -8.0 -2))
(test-equal "expt -8.0 2 stays real" 64.0 (expt -8.0 2))
(test-equal "expt -8.0 3.0 stays real" -512.0 (expt -8.0 3.0))

;; A non-negative base must never be promoted to complex.
(test-equal "expt 2.0 0.5 stays real" (sqrt 2.0) (expt 2.0 0.5))
(test-equal "expt 0.0 0.0 stays real" 1.0 (expt 0.0 0.0))

(let ((runner (test-runner-current)))
  (test-end "expt-negative-base-1725")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
