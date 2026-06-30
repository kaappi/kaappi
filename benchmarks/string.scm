(include "benchmarks/common.scm")

(define (string-bench n)
  (let loop ((i 0) (s ""))
    (if (= i n) (string-length s)
        (loop (+ i 1) (string-append s "x")))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "string(" (number->string input) ")")
   count
   (lambda () (string-bench input))
   (lambda (result) (= result expected))))
