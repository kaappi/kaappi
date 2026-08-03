;; Regression tests for #865 (magnitude on rationals) and #834 (car/cdr type error)

(import (scheme base) (scheme complex) (scheme process-context) (srfi 64))

(test-begin "magnitude-runtime-fixes")

;; #865: magnitude on exact rationals should preserve exactness
(test-assert "(magnitude -1/2) = 1/2" (= (magnitude -1/2) 1/2))
(test-assert "(magnitude 1/2) = 1/2" (= (magnitude 1/2) 1/2))
(test-assert "(magnitude -1/2) stays exact" (exact? (magnitude -1/2)))
(test-assert "(magnitude -5) = 5" (= (magnitude -5) 5))
(test-assert "(magnitude 3.0) = 3.0" (= (magnitude 3.0) 3.0))

(let ((runner (test-runner-current)))
  (test-end "magnitude-runtime-fixes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
