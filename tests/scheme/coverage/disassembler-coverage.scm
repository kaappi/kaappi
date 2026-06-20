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

;;; ---- Trigger all opcode types ----

;; load_nil, load_true, load_false, load_void
(disassemble (lambda () '()))
(disassemble (lambda () #t))
(disassemble (lambda () #f))
(disassemble (lambda () (if #f #f)))
(check-true "disassemble constants" #t)

;; set_global / define_global
(disassemble (lambda () (define x 42) x))
(check-true "disassemble define" #t)

;; get_local / set_local
(disassemble (lambda (x) (set! x 42) x))
(check-true "disassemble set_local" #t)

;; closure / get_upvalue / set_upvalue / close_upvalue
(disassemble (lambda (x) (lambda () x)))
(disassemble (lambda (x) (lambda () (set! x 42))))
(check-true "disassemble closure/upvalue" #t)

;; cons
(disassemble (lambda (a b) (cons a b)))
(check-true "disassemble cons" #t)

;; jump_true
(disassemble (lambda (x) (or x 42)))
(check-true "disassemble jump_true" #t)

;; push_handler / pop_handler
(disassemble (lambda ()
  (with-exception-handler
    (lambda (e) e)
    (lambda () (error "test")))))
(check-true "disassemble handler" #t)

;; box_local / get_box_local / set_box_local (letrec)
(disassemble (lambda ()
  (letrec ((x 1)) (set! x 2) x)))
(check-true "disassemble box_local" #t)

;; self_tail_call (named let)
(disassemble (lambda (n)
  (let loop ((i n))
    (if (= i 0) 'done (loop (- i 1))))))
(check-true "disassemble self_tail_call" #t)

;; tail_apply
(disassemble (lambda (f args) (apply f args)))
(check-true "disassemble tail_apply" #t)

;; call_global / tail_call_global
(disassemble (lambda (x) (+ x 1)))
(disassemble (lambda (x y) (+ x y)))
(check-true "disassemble call_global" #t)

;; halt (top-level expression — implicitly used)
(check-true "disassemble comprehensive done" #t)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Disassembler coverage tests failed" fail))
