(include "benchmarks/common.scm")

(define (vector-bench n)
  (let ((v (make-vector n 0)))
    (let fill ((i 0))
      (when (< i n)
        (vector-set! v i (* i i))
        (fill (+ i 1))))
    (let sum ((i 0) (total 0))
      (if (= i n) total
          (sum (+ i 1) (+ total (vector-ref v i)))))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "vector(" (number->string input) ")")
   count
   (lambda () (vector-bench input))
   (lambda (result) (= result expected))))
