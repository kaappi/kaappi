(include "benchmarks/common.scm")

(define (gc-stress n)
  (let loop ((i n) (keep '()))
    (if (= i 0) (length keep)
        (let ((tmp (cons i (cons (+ i 1) '()))))
          (loop (- i 1)
                (if (= 0 (modulo i 1000)) (cons (car tmp) keep) keep))))))

(let* ((count (read))
       (input (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "gc-pressure(" (number->string input) ")")
   count
   (lambda () (gc-stress input))
   (lambda (result) (= result expected))))
