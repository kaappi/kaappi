(include "benchmarks/common.scm")

(define (nqueens n)
  (define (queen-cols k)
    (if (= k 0)
        (list '())
        (filter
         (lambda (positions) (safe? k positions))
         (flatmap
          (lambda (rest-of-queens)
            (map (lambda (new-row)
                   (cons new-row rest-of-queens))
                 (enumerate-interval 1 n)))
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

(define (enumerate-interval low high)
  (if (> low high) '()
      (cons low (enumerate-interval (+ low 1) high))))

(define (flatmap proc lst)
  (apply append (map proc lst)))

(define (filter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
        (else (filter pred (cdr lst)))))

(let* ((count (read))
       (n (read))
       (expected (read)))
  (run-r7rs-benchmark
   (string-append "nqueens(" (number->string n) ")")
   count
   (lambda () (nqueens n))
   (lambda (result) (= result expected))))
