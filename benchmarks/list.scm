(include "benchmarks/common.scm")

(define (list-bench n)
  (let ((ls (let build ((i n) (acc '()))
              (if (= i 0) acc
                  (build (- i 1) (cons i acc))))))
    (length (map (lambda (x) (* x x)) ls))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "list(" (number->string input) ")")
   count
   (lambda () (list-bench input))
   (lambda (result) (= result expected))))
