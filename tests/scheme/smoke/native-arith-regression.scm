;; Native backend arithmetic NaN-boxing regression test
;; Exercises natively compiled fixnum arithmetic, comparisons, and predicates
;; with positive, negative, zero, and mixed-sign operands.

(import (scheme base) (scheme write) (scheme process-context))

(define pass 0)
(define fail 0)

(define (check name expected actual)
  (if (equal? expected actual)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ")
        (display name)
        (display " expected=")
        (display expected)
        (display " got=")
        (display actual)
        (newline))))

(define (add a b) (+ a b))
(define (sub a b) (- a b))
(define (mul a b) (* a b))
(define (lt? a b) (< a b))
(define (gt? a b) (> a b))
(define (le? a b) (<= a b))
(define (ge? a b) (>= a b))
(define (eq? a b) (= a b))
(define (is-zero? x) (zero? x))
(define (is-pair? x) (pair? x))
(define (is-null? x) (null? x))
(define (get-car x) (car x))
(define (get-cdr x) (cdr x))

;; Call each function 200+ times to trigger native compilation (threshold=100)
(let loop ((i 0))
  (when (< i 200)
    (add 1 2) (sub 5 3) (mul 2 3) (lt? 1 2) (gt? 2 1) (le? 1 1) (ge? 1 1) (eq? 5 5)
    (is-zero? 0) (is-zero? 1) (is-pair? (cons 1 2)) (is-null? '())
    (get-car (cons 10 20)) (get-cdr (cons 10 20))
    (add -1 -2) (sub -1 1) (mul -2 3) (lt? -1 1) (gt? 1 -1) (eq? -1 -1)
    (loop (+ i 1))))

;; Now test with natively compiled versions
(check "add positive" 5 (add 2 3))
(check "add zero" 42 (add 42 0))
(check "add negative" -3 (add -1 -2))
(check "add mixed" 1 (add -1 2))
(check "add even" 4 (add 2 2))
(check "add large" 100000 (add 50000 50000))

(check "sub positive" 2 (sub 5 3))
(check "sub zero" 7 (sub 7 0))
(check "sub negative" -5 (sub -2 3))
(check "sub to-negative" -1 (sub 2 3))

(check "mul positive" 6 (mul 2 3))
(check "mul zero" 0 (mul 0 5))
(check "mul negative" -6 (mul -2 3))
(check "mul neg-neg" 6 (mul -2 -3))

(check "lt positive" #t (lt? 1 2))
(check "lt equal" #f (lt? 2 2))
(check "lt reverse" #f (lt? 3 1))
(check "lt negative" #t (lt? -2 -1))
(check "lt mixed" #t (lt? -1 1))
(check "lt mixed2" #f (lt? 1 -1))
(check "lt zero" #t (lt? -1 0))

(check "gt positive" #t (gt? 2 1))
(check "gt mixed" #t (gt? 1 -1))
(check "gt mixed2" #f (gt? -1 1))

(check "le equal" #t (le? 2 2))
(check "ge equal" #t (ge? 2 2))
(check "eq same" #t (eq? 42 42))
(check "eq diff" #f (eq? 1 2))
(check "eq neg" #t (eq? -1 -1))

(check "zero? 0" #t (is-zero? 0))
(check "zero? 1" #f (is-zero? 1))
(check "zero? -1" #f (is-zero? -1))

(check "pair? pair" #t (is-pair? (cons 1 2)))
(check "pair? num" #f (is-pair? 42))
(check "pair? nil" #f (is-pair? '()))

(check "null? nil" #t (is-null? '()))
(check "null? pair" #f (is-null? (cons 1 2)))

(check "car" 10 (get-car (cons 10 20)))
(check "cdr" 20 (get-cdr (cons 10 20)))

(display pass)
(display "/")
(display (+ pass fail))
(display " tests passed")
(newline)
(when (> fail 0) (exit 1))
