;; Regression test for #860: parameterize evaluates each param expression
;; five times instead of once.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "parameterize-eval-860")

(define p (make-parameter 1))
(define pcount 0)
(define vcount 0)
(define (get-p) (set! pcount (+ pcount 1)) p)
(define (get-v) (set! vcount (+ vcount 1)) 2)

(test-equal "parameterize body sees the new value"
            2
            (parameterize (((get-p) (get-v))) (p)))
(test-equal "the parameter expression is evaluated exactly once" 1 pcount)
(test-equal "the value expression is evaluated exactly once" 1 vcount)

;; After parameterize, old value is restored
(test-equal "the old value is restored on exit" 1 (p))

;; Also test when parameterize is used as an expression (call argument)
(set! pcount 0)
(set! vcount 0)
(test-equal "parameterize in expression position yields the body's value"
            2
            (+ 0 (parameterize (((get-p) (get-v))) (p))))
(test-equal "parameter expression still evaluated once in expression position"
            1 pcount)
(test-equal "value expression still evaluated once in expression position"
            1 vcount)

(let ((runner (test-runner-current)))
  (test-end "parameterize-eval-860")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
