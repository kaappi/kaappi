;; Benchmark for IR constant folding + dead branch elimination
;; With optimization: inner expressions fold to constants, branches eliminated
;; Without optimization: evaluates arithmetic + conditionals at runtime
(define (bench n)
  (define (go i acc)
    (if (= i 0) acc
        (go (- i 1)
            (+ acc
               (if (not (< 2 1)) (+ 10 20) (- 100 200))
               (if (< 1 2) (* 3 7) (* 0 1))
               (+ 0 (+ 5 10))
               (* 1 (- 50 20))))))
  (go n 0))
(bench 5000000)
