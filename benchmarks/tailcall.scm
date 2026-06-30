(include "benchmarks/common.scm")

(define (tail-sum n acc)
  (if (= n 0) acc (tail-sum (- n 1) (+ acc n))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "tailcall(" (number->string input) ")")
   count
   (lambda () (tail-sum input 0))
   (lambda (result) (= result expected))))
