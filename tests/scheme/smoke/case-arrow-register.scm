;; Regression test for #541: case ((datum ...) => proc) must not clobber
;; live local variables at dst+1.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "case-arrow-register")

(define (f k)
  (let ((r 0) (a 111) (b 222))
    (set! r (case k ((1 2 3) => (lambda (v) (* v 10))) (else 0)))
    (list r a b)))

(test-equal "case => does not clobber locals" '(20 111 222) (f 2))
(test-equal "case => else branch" '(0 111 222) (f 9))

(let ((runner (test-runner-current)))
  (test-end "case-arrow-register")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
