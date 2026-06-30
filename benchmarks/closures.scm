(include "benchmarks/common.scm")

(define (make-list-iota n)
  (let loop ((i 0) (acc '()))
    (if (= i n) acc (loop (+ i 1) (cons i acc)))))

(define (bench-closures n size)
  (let loop ((i n) (lst (make-list-iota size)))
    (if (= i 0) (length lst)
        (loop (- i 1) (map (lambda (x) (+ x 1)) lst)))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "closures(" (number->string input) ")")
   count
   (lambda () (bench-closures input 1000))
   (lambda (result) (= result expected))))
