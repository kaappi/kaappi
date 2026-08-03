;; Regression test for #443:
;; (* expr 0) optimization must not drop side effects from expr.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "mul-zero-side-effects")

(define output '())

(define (track! x)
  (set! output (cons x output))
  x)

;; (* side-effecting-expr 0) must still execute the side effect
(define r1 (* (track! 5) 0))
(test-equal "(* (track! 5) 0) is 0" 0 r1)
(test-equal "(* (track! 5) 0) preserves the side effect" '(5) output)

;; (* 0 side-effecting-expr) must also preserve side effects
(set! output '())
(define r2 (* 0 (track! 7)))
(test-equal "(* 0 (track! 7)) is 0" 0 r2)
(test-equal "(* 0 (track! 7)) preserves the side effect" '(7) output)

;; Pure (* const 0) should still fold to 0
(test-equal "(* 42 0) folds to 0" 0 (* 42 0))

(let ((runner (test-runner-current)))
  (test-end "mul-zero-side-effects")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
