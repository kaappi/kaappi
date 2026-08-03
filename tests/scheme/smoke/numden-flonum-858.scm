;; Regression test for #858: numerator/denominator on flonums must return
;; the exact dyadic fraction, not a decimal approximation.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "numden-flonum-858")

(test-assert "pi = (numerator pi) / (denominator pi)"
  (let ((x 3.141592653589793))
    (= x (/ (numerator x) (denominator x)))))

(test-assert "(denominator 0.3) agrees with (denominator (exact 0.3))"
  (= (denominator 0.3) (denominator (exact 0.3))))

(let ((runner (test-runner-current)))
  (test-end "numden-flonum-858")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
