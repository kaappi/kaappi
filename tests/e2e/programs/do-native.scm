; do: parallel step, a var without a step, a command body, and no result exprs
(display (do ((i 0 (+ i 1)) (acc 0 (+ acc i))) ((= i 5) acc)))
(newline)
(display (do ((i 0 (+ i 1)) (s 0)) ((= i 5) s) (set! s (+ s (* i i)))))
(newline)
(define v (make-vector 4 0))
(do ((i 0 (+ i 1))) ((= i 4)) (vector-set! v i (* i 10)))
(display v)
(newline)
