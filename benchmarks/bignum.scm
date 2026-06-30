(include "benchmarks/common.scm")

(define (fact n)
  (if (<= n 1) 1 (* n (fact (- n 1)))))

(define (bench-bignum n)
  (string-length (number->string (fact n))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "bignum(" (number->string input) ")")
   count
   (lambda () (bench-bignum input))
   (lambda (result) (= result expected))))
