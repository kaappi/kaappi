(include "benchmarks/common.scm")

(define (tak x y z)
  (if (not (< y x))
      z
      (tak (tak (- x 1) y z)
           (tak (- y 1) z x)
           (tak (- z 1) x y))))

(let* ((count 1)
       (x 33)
       (y 22)
       (z 11)
       (expected 22))
  (run-r7rs-benchmark
   (string-append "tak(" (number->string x) "," (number->string y) "," (number->string z) ")")
   count
   (lambda () (tak x y z))
   (lambda (result) (= result expected))))
