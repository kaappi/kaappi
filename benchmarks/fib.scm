(include "benchmarks/common.scm")

(define (fib n)
  (if (< n 2) n
      (+ (fib (- n 1)) (fib (- n 2)))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "fib(" (number->string input) ")")
   count
   (lambda () (fib input))
   (lambda (result) (= result expected))))
