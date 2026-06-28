(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

;; define-values must root the formals list across compilation and execution.
;; Without rooting, GC can collect the pair cells linking the formal symbols.

;; Create GC pressure before define-values
(let loop ((i 0))
  (when (< i 2000)
    (make-list 10 i)
    (loop (+ i 1))))

(define-values (a b c) (values 1 2 3))

(check "define-values a" a 1)
(check "define-values b" b 2)
(check "define-values c" c 3)

;; Test with more formals to exercise longer pair chains
(let loop ((i 0))
  (when (< i 2000)
    (make-list 10 i)
    (loop (+ i 1))))

(define-values (x y z w) (values 10 20 30 40))

(check "define-values x" x 10)
(check "define-values y" y 20)
(check "define-values z" z 30)
(check "define-values w" w 40)

;; Test with rest parameter
(define-values (p q . r) (values 100 200 300 400))

(check "define-values p" p 100)
(check "define-values q" q 200)
(check "define-values r" r '(300 400))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "define-values GC tests failed" fail))
