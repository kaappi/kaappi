(import (scheme base) (scheme read) (scheme write) (scheme time))

(define (run-r7rs-benchmark name count thunk verify)
  (let ((start (current-jiffy)))
    (let loop ((i count) (result #f))
      (if (= i 0)
          (let* ((end (current-jiffy))
                 (jps (jiffies-per-second))
                 (elapsed (inexact (/ (- end start) jps))))
            (display name)
            (display ": ")
            (display elapsed)
            (display "s")
            (if (verify result)
                (display " [OK]")
                (display " [FAIL]"))
            (newline))
          (loop (- i 1) (thunk))))))

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
