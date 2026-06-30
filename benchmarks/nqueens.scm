(include "benchmarks/common.scm")

(define (nqueens n)
  (define (queen-cols k)
    (if (= k 0)
        (list '())
        (filter
         (lambda (positions) (safe? k positions))
         (flatmap
          (lambda (rest-of-queens)
            (map-interval
             (lambda (new-row) (cons new-row rest-of-queens))
             1 n))
          (queen-cols (- k 1))))))
  (length (queen-cols n)))

(define (safe? k positions)
  (let ((new-row (car positions))
        (rest (cdr positions)))
    (let loop ((r rest) (dist 1))
      (if (null? r)
          #t
          (let ((row (car r)))
            (if (or (= new-row row)
                    (= new-row (+ row dist))
                    (= new-row (- row dist)))
                #f
                (loop (cdr r) (+ dist 1))))))))

(define (map-interval f low high)
  (let loop ((i high) (acc '()))
    (if (< i low) acc
        (loop (- i 1) (cons (f i) acc)))))

(define (flatmap proc lst)
  (let loop ((remaining lst) (acc '()))
    (if (null? remaining)
        (reverse acc)
        (let ((chunk (proc (car remaining))))
          (let copy ((c chunk) (a acc))
            (if (null? c)
                (loop (cdr remaining) a)
                (copy (cdr c) (cons (car c) a))))))))

(define (filter pred lst)
  (let loop ((remaining lst) (acc '()))
    (cond ((null? remaining) (reverse acc))
          ((pred (car remaining))
           (loop (cdr remaining) (cons (car remaining) acc)))
          (else (loop (cdr remaining) acc)))))

(let* ((count (read))
       (n (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "nqueens(" (number->string n) ")")
   count
   (lambda () (nqueens n))
   (lambda (result) (= result expected))))
