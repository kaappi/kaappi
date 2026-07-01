;; Regression test for #648: equal? hangs on shared DAGs deeper than 128

(import (scheme base) (scheme write) (scheme process-context))

(define pass 0)
(define fail 0)

(define (check name expected actual)
  (display name)
  (display ": ")
  (if (equal? expected actual)
    (begin (set! pass (+ pass 1)) (display "ok"))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL - expected ")
      (write expected)
      (display " got ")
      (write actual)))
  (newline))

;; Build a shared DAG: each node's car and cdr point to the same subtree
(define (make-dag n)
  (let loop ((i 0) (x (cons 1 1)))
    (if (= i n) x (loop (+ i 1) (cons x x)))))

;; Depth 200: previously hung due to exponential blowup past 128 memoized entries
(let ((a (make-dag 200))
      (b (make-dag 200)))
  (check "equal? on depth-200 DAG (equal)" #t (equal? a b)))

;; Depth 500: deeper than any fixed-size visited array could handle
(let ((a (make-dag 500))
      (b (make-dag 500)))
  (check "equal? on depth-500 DAG (equal)" #t (equal? a b)))

;; Unequal DAGs at depth 200
(let ((a (make-dag 200))
      (b (let loop ((i 0) (x (cons 2 2)))
           (if (= i 200) x (loop (+ i 1) (cons x x))))))
  (check "equal? on depth-200 DAG (unequal)" #f (equal? a b)))

;; Small DAGs still work correctly
(check "equal? on small pairs" #t (equal? '(1 2 3) '(1 2 3)))
(check "equal? on small vectors" #t (equal? #(1 2 3) #(1 2 3)))
(check "equal? on nested" #t (equal? '(1 (2 (3))) '(1 (2 (3)))))
(check "equal? on unequal" #f (equal? '(1 2) '(1 3)))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
