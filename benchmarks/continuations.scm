(include "benchmarks/common.scm")

(define (bench-callcc n)
  (let loop ((i n) (a 0))
    (if (= i 0) a
        (loop (- i 1) (+ a (call-with-current-continuation (lambda (k) (k 1))))))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "callcc(" (number->string input) ")")
   count
   (lambda () (bench-callcc input))
   (lambda (result) (= result expected))))
