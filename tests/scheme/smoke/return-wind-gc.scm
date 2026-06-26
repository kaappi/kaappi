(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; Return a heap-allocated value through a dynamic-wind that allocates
;; heavily in its after-thunk, pressuring the GC while the return value
;; is in flight.
(define (return-through-wind)
  (call-with-current-continuation
    (lambda (escape)
      (dynamic-wind
        (lambda () #f)
        (lambda () (escape (list 'a 'b 'c)))
        (lambda ()
          ;; Allocate enough to cross the GC threshold
          (let loop ((i 0))
            (when (< i 500)
              (cons i (make-string 10 #\x))
              (loop (+ i 1)))))))))

(check "return through wind" (return-through-wind) '(a b c))

;; Multiple nested dynamic-winds
(define (nested-wind-return)
  (call-with-current-continuation
    (lambda (escape)
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (dynamic-wind
            (lambda () #f)
            (lambda () (escape (cons 1 (cons 2 '()))))
            (lambda ()
              (let loop ((i 0))
                (when (< i 200) (cons i '()) (loop (+ i 1)))))))
        (lambda ()
          (let loop ((i 0))
            (when (< i 200) (cons i '()) (loop (+ i 1)))))))))

(check "nested wind return" (nested-wind-return) '(1 2))

;; Simple dynamic-wind with return value (no continuation escape)
(define (simple-wind-return)
  (dynamic-wind
    (lambda () #f)
    (lambda () (list 1 2 3))
    (lambda ()
      (let loop ((i 0))
        (when (< i 300) (cons i '()) (loop (+ i 1)))))))

(check "simple wind return" (simple-wind-return) '(1 2 3))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "return-wind-gc tests failed" fail))
