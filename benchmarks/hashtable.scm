(include "benchmarks/common.scm")
(import (srfi 69))

(define (hashtable-bench n keys)
  (let ((ht (make-hash-table)))
    (let insert ((i 0))
      (when (< i n)
        (hash-table-set! ht (vector-ref keys i) i)
        (insert (+ i 1))))
    (let lookup ((i 0) (sum 0))
      (if (= i n) sum
          (lookup (+ i 1) (+ sum (hash-table-ref ht (vector-ref keys i))))))))

(let* ((count (read))
       (input (read))
       (expected (read))
       (keys (let build ((i 0) (acc '()))
               (if (= i input) (list->vector acc)
                   (build (+ i 1) (cons (number->string i) acc))))))
  (run-r7rs-benchmark
   (string-append "hashtable(" (number->string input) ")")
   count
   (lambda () (hashtable-bench input keys))
   (lambda (result) (= result expected))))
