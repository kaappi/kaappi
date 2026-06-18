;;; Time library compliance tests (R7RS 6.14)
(import (scheme base) (scheme time) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "time")

;; --- current-second ---
(test-group "current-second"
  (test-assert "current-second returns a number" (number? (current-second)))
  (test-assert "current-second is positive" (> (current-second) 0)))

;; --- current-jiffy ---
(test-group "current-jiffy"
  (test-assert "current-jiffy returns an integer" (integer? (current-jiffy))))

;; --- jiffies-per-second ---
(test-group "jiffies-per-second"
  (test-assert "jiffies-per-second is positive" (> (jiffies-per-second) 0)))

;; --- monotonicity ---
(test-group "monotonicity"
  (let ((j1 (current-jiffy))
        (j2 (current-jiffy)))
    (test-assert "consecutive jiffies are non-decreasing" (>= j2 j1))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "time")
(if (> %test-fail-count 0) (exit 1))
