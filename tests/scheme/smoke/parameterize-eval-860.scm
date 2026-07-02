;; Regression test for #860: parameterize evaluates each param expression
;; five times instead of once.

(define p (make-parameter 1))
(define pcount 0)
(define vcount 0)
(define (get-p) (set! pcount (+ pcount 1)) p)
(define (get-v) (set! vcount (+ vcount 1)) 2)

(parameterize (((get-p) (get-v)))
  (display (p))
  (newline))
(display (list 'param-evals pcount 'value-evals vcount))
(newline)

;; After parameterize, old value is restored
(display (p))
(newline)

;; Also test when parameterize is used as an expression (call argument)
(set! pcount 0)
(set! vcount 0)
(define result (parameterize (((get-p) (get-v))) (p)))
(display result)
(newline)
(display (list 'param-evals pcount 'value-evals vcount))
(newline)
