;; Regression test for #837: round on negative exact rationals with
;; fraction < 1/2 rounds away from zero instead of toward it.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "round-neg-rational-837")

;; Fraction < 1/2 — should round toward zero
(test-equal "(round -1/3)" 0 (round -1/3))
(test-equal "(round -1/4)" 0 (round -1/4))
(test-equal "(round -4/3)" -1 (round -4/3))

;; Fraction > 1/2 — should round away from zero
(test-equal "(round -2/3)" -1 (round -2/3))
(test-equal "(round -5/3)" -2 (round -5/3))

;; Ties to even
(test-equal "(round -5/2) ties to even" -2 (round -5/2))
(test-equal "(round -7/2) ties to even" -4 (round -7/2))
(test-equal "(round -3/2) ties to even" -2 (round -3/2))

;; Positive rationals (sanity check)
(test-equal "(round 1/3)" 0 (round 1/3))
(test-equal "(round 2/3)" 1 (round 2/3))
(test-equal "(round 5/2) ties to even" 2 (round 5/2))

(let ((runner (test-runner-current)))
  (test-end "round-neg-rational-837")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
