;; Regression test for #499: floor/ceiling/truncate/round on exact rationals
;; must use exact arithmetic, not route through f64.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "rational-rounding")

;; Basic floor
(test-equal "floor 7/3" 2 (floor 7/3))
(test-equal "floor -7/3" -3 (floor -7/3))
(test-equal "floor 1/2" 0 (floor 1/2))
(test-equal "floor -1/2" -1 (floor -1/2))
(test-equal "floor 4/2" 2 (floor 4/2))

;; Basic ceiling
(test-equal "ceiling 7/3" 3 (ceiling 7/3))
(test-equal "ceiling -7/3" -2 (ceiling -7/3))
(test-equal "ceiling 1/2" 1 (ceiling 1/2))
(test-equal "ceiling -1/2" 0 (ceiling -1/2))

;; Basic truncate
(test-equal "truncate 7/3" 2 (truncate 7/3))
(test-equal "truncate -7/3" -2 (truncate -7/3))

;; Basic round (ties to even)
(test-equal "round 7/3" 2 (round 7/3))
(test-equal "round 1/2" 0 (round 1/2))    ; ties to even (0)
(test-equal "round 3/2" 2 (round 3/2))    ; ties to even (2)
(test-equal "round -1/2" 0 (round -1/2))  ; ties to even (0)
(test-equal "round -3/2" -2 (round -3/2)) ; ties to even (-2)
(test-equal "round 5/2" 2 (round 5/2))    ; ties to even (2)
(test-equal "round 7/2" 4 (round 7/2))    ; ties to even (4)

;; Results must be exact integers
(test-assert "floor of rational is exact" (exact? (floor 7/3)))
(test-assert "ceiling of rational is exact" (exact? (ceiling 7/3)))
(test-assert "truncate of rational is exact" (exact? (truncate 7/3)))
(test-assert "round of rational is exact" (exact? (round 7/3)))

(let ((runner (test-runner-current)))
  (test-end "rational-rounding")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
