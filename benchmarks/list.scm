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
