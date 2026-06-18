;;; Numeric gap compliance tests (R7RS 6.2, SRFI 64)

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "numeric-gaps")

(test-group "floor-quotient and floor-remainder"
  (test-eqv "floor-quotient 7 3" 2 (floor-quotient 7 3))
  (test-eqv "floor-remainder 7 3" 1 (floor-remainder 7 3))
  (test-eqv "floor-quotient -7 3" -3 (floor-quotient -7 3))
  (test-eqv "floor-remainder -7 3" 2 (floor-remainder -7 3)))

(test-group "truncate-quotient and truncate-remainder"
  (test-eqv "truncate-quotient 7 3" 2 (truncate-quotient 7 3))
  (test-eqv "truncate-remainder 7 3" 1 (truncate-remainder 7 3))
  (test-eqv "truncate-quotient -7 3" -2 (truncate-quotient -7 3))
  (test-eqv "truncate-remainder -7 3" -1 (truncate-remainder -7 3)))

(test-group "numerator and denominator"
  (test-eqv "numerator 3" 3 (numerator 3))
  (test-eqv "denominator 3" 1 (denominator 3)))

(test-group "exactness conversion"
  (test-approximate "exact->inexact 3" 3.0 (exact->inexact 3) 0.0001)
  (test-eqv "inexact->exact 3.0" 3 (inexact->exact 3.0)))

(test-group "rationalize"
  (test-eqv "rationalize 3 1" 3 (rationalize 3 1)))

(test-group "features"
  (test-assert "features returns a list" (list? (features))))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "numeric-gaps")
(if (> %test-fail-count 0) (exit 1))
