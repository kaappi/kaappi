;; Regression test for #494: (exact x) on non-integer flonums must return
;; the exact IEEE-754 value so the round-trip (inexact (exact x)) = x holds.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "inexact-to-exact")

;; Round-trip invariant: (inexact (exact x)) must equal x
(test-assert "round-trip 0.1" (= (inexact (exact 0.1)) 0.1))
(test-assert "round-trip 0.3" (= (inexact (exact 0.3)) 0.3))
(test-assert "round-trip 0.7" (= (inexact (exact 0.7)) 0.7))
(test-assert "round-trip 1.5" (= (inexact (exact 1.5)) 1.5))
(test-assert "round-trip -0.25" (= (inexact (exact -0.25)) -0.25))
(test-assert "round-trip 1e-10" (= (inexact (exact 1e-10)) 1e-10))

;; exact of integer-valued float
(test-equal "exact 2.0" 2 (exact 2.0))
(test-equal "exact -3.0" -3 (exact -3.0))

;; exact 0.5 = 1/2
(test-equal "exact 0.5" 1/2 (exact 0.5))
(test-equal "exact 0.25" 1/4 (exact 0.25))

;; Result must be exact
(test-assert "result is exact" (exact? (exact 0.1)))

(let ((runner (test-runner-current)))
  (test-end "inexact-to-exact")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
