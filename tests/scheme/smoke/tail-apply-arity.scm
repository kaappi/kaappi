;; Regression test for #445: tail_apply missing arity check for
;; native functions. Previously crashed (panic) on too few args
;; and silently ignored extra args.

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ")
        (display name)
        (display " got=")
        (write got)
        (display " expected=")
        (write expected)
        (newline))))

;; Test 1: too few args to car via tail apply (was: PANIC)
(define (test-car-no-args)
  (apply car (list)))

(check "car-no-args"
       (guard (e (#t (error-object? e)))
         (test-car-no-args)
         #f)
       #t)

;; Test 2: too many args to cons via tail apply (was: silently dropped)
(define (test-cons-too-many)
  (apply cons (list 1 2 3)))

(check "cons-too-many"
       (guard (e (#t (error-object? e)))
         (test-cons-too-many)
         #f)
       #t)

;; Test 3: correct arity still works
(define (test-car-ok) (apply car (list '(a b c))))
(check "car-ok" (test-car-ok) 'a)

(define (test-cons-ok) (apply cons (list 1 2)))
(check "cons-ok" (test-cons-ok) '(1 . 2))

;; Test 4: variadic native function with too few args
(define (test-plus-no-args) (apply + (list)))
(check "plus-no-args" (test-plus-no-args) 0)

(define (test-list-variadic) (apply list (list 1 2 3)))
(check "list-variadic" (test-list-variadic) '(1 2 3))

;; Test 5: mixed fixed + list args
(define (test-apply-mixed) (apply cons 1 (list 2)))
(check "apply-mixed" (test-apply-mixed) '(1 . 2))

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
