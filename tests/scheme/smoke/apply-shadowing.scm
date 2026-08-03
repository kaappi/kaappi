;; Regression test for #444:
;; apply tail-call optimization must respect local variable shadowing.

;; When 'apply' is shadowed by a local binding, calls to that binding
;; should treat it as a regular function call, not as the built-in apply.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "apply-shadowing")

(define (test-apply-shadowed)
  (let ((apply +))
    (apply 1 2)))

(test-equal "shadowed apply uses local binding" 3 (test-apply-shadowed))

;; Non-tail position should also work
(define (test-apply-shadowed-non-tail)
  (let ((apply +))
    (let ((r (apply 10 20)))
      r)))

(test-equal "shadowed apply in non-tail position" 30 (test-apply-shadowed-non-tail))

;; Unshadowed apply should still work normally
(define (test-normal-apply)
  (apply + '(1 2 3)))

(test-equal "unshadowed apply works normally" 6 (test-normal-apply))

(let ((runner (test-runner-current)))
  (test-end "apply-shadowing")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
