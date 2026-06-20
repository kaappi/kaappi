(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; disassemble outputs to stdout and returns void
;;; We test that it doesn't error on various procedure types

;;; ---- Simple lambda ----
(let ((result (disassemble (lambda (x) x))))
  (check-true "disassemble identity returns" #t))

(let ((result (disassemble (lambda (x y) (+ x y)))))
  (check-true "disassemble add returns" #t))

(let ((result (disassemble (lambda () 42))))
  (check-true "disassemble no-args returns" #t))

;;; ---- Complex procedures ----
(define (factorial n)
  (if (<= n 1) 1 (* n (factorial (- n 1)))))
(disassemble factorial)
(check-true "disassemble factorial" #t)

(define (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(disassemble fib)
(check-true "disassemble fib" #t)

;;; ---- Closures ----
(define (make-adder n) (lambda (x) (+ n x)))
(disassemble (make-adder 5))
(check-true "disassemble closure" #t)

;;; ---- Variadic ----
(define (variadic . args) (apply + args))
(disassemble variadic)
(check-true "disassemble variadic" #t)

;;; ---- With if ----
(disassemble (lambda (x) (if x 1 0)))
(check-true "disassemble if" #t)

;;; ---- With let ----
(disassemble (lambda (x) (let ((y (* x 2))) (+ y 1))))
(check-true "disassemble let" #t)

;;; ---- With begin ----
(disassemble (lambda () (begin 1 2 3)))
(check-true "disassemble begin" #t)

;;; ---- With cond ----
(disassemble (lambda (x) (cond ((= x 0) 'zero) ((= x 1) 'one) (else 'other))))
(check-true "disassemble cond" #t)

;;; ---- With case ----
(disassemble (lambda (x) (case x ((0) 'zero) ((1) 'one) (else 'other))))
(check-true "disassemble case" #t)

;;; ---- With and/or ----
(disassemble (lambda (x y) (and x y)))
(check-true "disassemble and" #t)

(disassemble (lambda (x y) (or x y)))
(check-true "disassemble or" #t)

;;; ---- Recursive with tail call ----
(define (loop n acc)
  (if (= n 0) acc (loop (- n 1) (+ acc n))))
(disassemble loop)
(check-true "disassemble tail-recursive" #t)

;;; ---- With multiple arguments ----
(disassemble (lambda (a b c d e) (+ a b c d e)))
(check-true "disassemble multi-arg" #t)

;;; ---- Nested lambda ----
(disassemble (lambda (x) (lambda (y) (+ x y))))
(check-true "disassemble nested lambda" #t)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Disassembler coverage tests failed" fail))
