(include "benchmarks/common.scm")

(define (primes-up-to n)
  (let loop ((i 2) (result '()))
    (if (> i n)
        (reverse result)
        (if (prime? i)
            (loop (+ i 1) (cons i result))
            (loop (+ i 1) result)))))

(define (prime? n)
  (let loop ((d 2))
    (cond ((> (* d d) n) #t)
          ((= (remainder n d) 0) #f)
          (else (loop (+ d 1))))))

(let* ((count (read))
       (n (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "primes(" (number->string n) ")")
   count
   (lambda () (length (primes-up-to n)))
   (lambda (result) (= result expected))))
