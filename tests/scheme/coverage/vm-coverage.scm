(import (scheme base) (scheme write) (scheme read) (scheme char)
        (scheme case-lambda) (scheme lazy) (scheme cxr))

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
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- tail_apply opcode: apply in tail position ----
(define (sum-list lst) (apply + lst))
(check "tail apply" (sum-list '(1 2 3 4 5)) 15)

(define (tail-apply-cons a b) (apply cons (list a b)))
(check "tail apply cons" (tail-apply-cons 'x 'y) '(x . y))

(define (apply-multi . args) (apply + args))
(check "apply variadic" (apply-multi 1 2 3) 6)

;;; ---- apply with continuation ----
(check "apply identity via call/cc"
  (call-with-current-continuation (lambda (k) (apply k '(42))))
  42)

;;; ---- Parameter as callee ----
(define p (make-parameter 10))
(check "parameter call 0 args" (p) 10)
(p 20)
(check "parameter call 1 arg" (p) 20)

(define (get-param) (p))
(check "parameter tail call" (get-param) 20)

;;; ---- Parameter with converter ----
(define p2 (make-parameter 5 (lambda (x) (* x 2))))
(check "parameter converter" (p2) 10)

;;; ---- get_box_local / set_box_local (mutable letrec variables) ----
(check "letrec mutable"
  (letrec ((x 1))
    (set! x 10)
    x)
  10)

(check "letrec mutual mutable"
  (letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
           (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
    (even? 10))
  #t)

;;; ---- Dynamic-wind with escape continuation ----
(let ((log '()))
  (call-with-current-continuation
    (lambda (k)
      (dynamic-wind
        (lambda () (set! log (cons 'in log)))
        (lambda () (k 'escaped))
        (lambda () (set! log (cons 'out log))))))
  (check-true "dw escape has out" (memq 'out log))
  (check-true "dw escape has in" (memq 'in log)))

;;; ---- Nested dynamic-wind ----
(let ((log '()))
  (dynamic-wind
    (lambda () (set! log (cons 'outer-in log)))
    (lambda ()
      (dynamic-wind
        (lambda () (set! log (cons 'inner-in log)))
        (lambda () (set! log (cons 'body log)))
        (lambda () (set! log (cons 'inner-out log)))))
    (lambda () (set! log (cons 'outer-out log))))
  (check "nested dw order" (reverse log) '(outer-in inner-in body inner-out outer-out)))

;;; ---- with-exception-handler replace semantics ----
(check "exception handler replace"
  (with-exception-handler
    (lambda (e) 'caught)
    (lambda () (vector-ref '#(1 2) 5)))
  'caught)

;;; ---- Guard with re-raise to outer handler ----
(check "guard re-raise"
  (guard (e ((string? (error-object-message e)) (error-object-message e)))
    (guard (e ((number? e) 'number))
      (error "outer-error")))
  "outer-error")

;;; ---- raise-continuable ----
(check "raise-continuable"
  (with-exception-handler
    (lambda (e) (+ e 100))
    (lambda () (raise-continuable 42)))
  142)

;;; ---- Multiple values edge cases ----
(check "call-with-values sum" (call-with-values (lambda () (values 1 2 3)) +) 6)
(check "call-with-values no args" (call-with-values (lambda () (values)) (lambda () 'none)) 'none)
(check "receive-values"
  (let-values (((a b c) (values 10 20 30)))
    (+ a b c))
  60)

;;; ---- define-values ----
(define-values (dv-a dv-b dv-c) (values 1 2 3))
(check "define-values a" dv-a 1)
(check "define-values b" dv-b 2)
(check "define-values c" dv-c 3)

;;; ---- Tail calls in various positions ----
(define (tail-in-and n)
  (if (= n 0) #t (and #t (tail-in-and (- n 1)))))
(check "tail in and" (tail-in-and 10000) #t)

(define (tail-in-or n)
  (if (= n 0) 'done (or #f (tail-in-or (- n 1)))))
(check "tail in or" (tail-in-or 10000) 'done)

(define (tail-in-when n)
  (when (> n 0) (tail-in-when (- n 1))))
(tail-in-when 10000)
(check-true "tail in when" #t)

(define (tail-in-unless n)
  (unless (= n 0) (tail-in-unless (- n 1))))
(tail-in-unless 10000)
(check-true "tail in unless" #t)

(define (tail-in-cond n)
  (cond ((= n 0) 'done)
        ((even? n) (tail-in-cond (- n 2)))
        (else (tail-in-cond (- n 1)))))
(check "tail in cond" (tail-in-cond 10000) 'done)

(define (tail-in-case n)
  (case (modulo n 3)
    ((0) (if (= n 0) 'done (tail-in-case (- n 3))))
    ((1) (tail-in-case (- n 1)))
    ((2) (tail-in-case (- n 2)))))
(check "tail in case" (tail-in-case 9999) 'done)

;;; ---- Deep closures / upvalue access ----
(define (make-counter start)
  (let ((n start))
    (lambda (msg)
      (case msg
        ((get) n)
        ((inc) (set! n (+ n 1)) n)
        ((dec) (set! n (- n 1)) n)))))
(let ((c (make-counter 0)))
  (c 'inc)
  (c 'inc)
  (c 'inc)
  (check "counter" (c 'get) 3)
  (c 'dec)
  (check "counter dec" (c 'get) 2))

;;; ---- Deeply nested function calls ----
(define (deep n)
  (if (= n 0) 0
      (+ 1 (deep (- n 1)))))
(check "deep recursion" (deep 500) 500)

;;; ---- Error in error-object-irritants ----
(let ((e (guard (e (#t e)) (error "msg" 'a 'b 'c))))
  (check "error-object-message" (error-object-message e) "msg")
  (check "error-object-irritants" (error-object-irritants e) '(a b c))
  (check-true "error-object?" (error-object? e)))

;;; ---- Error predicates ----
(check-false "file-error? on regular error"
  (guard (e (#t (file-error? e))) (error "not file")))
(check-false "read-error? on regular error"
  (guard (e (#t (read-error? e))) (error "not read")))

;;; ---- eval ----
(check "eval quote" (eval ''hello (interaction-environment)) 'hello)
(check "eval define"
  (begin (eval '(define eval-test-var 42) (interaction-environment))
         (eval 'eval-test-var (interaction-environment)))
  42)

;;; ---- Quasiquote in tail position ----
(define (quasi-tail x) `(result ,x))
(check "quasiquote tail" (quasi-tail 42) '(result 42))

;;; ---- set! undefined variable errors ----
(check "set! undefined"
  (guard (e (#t 'caught))
    (eval '(set! completely-undefined-var-xyz 42) (interaction-environment)))
  'caught)

;;; ---- cxr compositions ----
(check "caaar" (caaar '(((1)))) 1)
(check "cdaar" (cdaar '(((1 2)))) '(2))
(check "caadr" (caadr '(1 (2 3))) 2)
(check "cdadr" (cdadr '(1 (2 3))) '(3))
(check "cadar" (cadar '((1 2) 3)) 2)
(check "cddar" (cddar '((1 2 3) 4)) '(3))
(check "caddr" (caddr '(1 2 3)) 3)
(check "cdddr" (cdddr '(1 2 3 4)) '(4))
(check "caaaar" (caaaar '((((1))))) 1)
(check "cadadr" (cadadr '(1 (2 3))) 3)
(check "caddar" (caddar '((1 2 3) 4)) 3)
(check "cadddr" (cadddr '(1 2 3 4)) 4)
(check "cddddr" (cddddr '(1 2 3 4 5)) '(5))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "VM coverage tests failed" fail))
