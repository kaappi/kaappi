(define (fact n)
  (if (= n 0) 1
      (* n (fact (- n 1)))))
(let loop ((i 0))
  (when (< i 100000)
    (fact 20)
    (loop (+ i 1))))
