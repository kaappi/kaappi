(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

(define (is-pair? x) (pair? x))

;; Warm up to trigger JIT compilation (threshold = 100)
(let loop ((i 0))
  (when (< i 200)
    (is-pair? (cons 1 2))
    (is-pair? 42)
    (is-pair? '())
    (is-pair? #t)
    (is-pair? #\a)
    (loop (+ i 1))))

;; Test all value types through JIT-compiled pair?
(check "pair? cons" #t (is-pair? (cons 1 2)))
(check "pair? list" #t (is-pair? '(1 2 3)))
(check "pair? nested" #t (is-pair? '((a) b)))

;; Non-pointer immediates (exercise the branch path)
(check "pair? fixnum" #f (is-pair? 42))
(check "pair? zero" #f (is-pair? 0))
(check "pair? negative" #f (is-pair? -1))
(check "pair? nil" #f (is-pair? '()))
(check "pair? true" #f (is-pair? #t))
(check "pair? false" #f (is-pair? #f))
(check "pair? char" #f (is-pair? #\x))

;; Pointer types that are not pairs
(check "pair? string" #f (is-pair? "hello"))
(check "pair? vector" #f (is-pair? #(1 2 3)))
(check "pair? symbol" #f (is-pair? 'foo))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "JIT pair? predicate tests failed" fail))
