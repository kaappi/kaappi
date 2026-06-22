(define (sum-to n acc)
  (if (= n 0) acc
      (sum-to (- n 1) (+ acc n))))
(sum-to 10000000 0)
