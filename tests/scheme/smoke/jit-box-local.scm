(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; Mutable captured local: set! forces boxing of n
(define (run)
  (let ((n 0))
    (let ((getter (lambda () n)))
      (set! n (+ n 1))
      (+ n (getter)))))

;; Call 200+ times to trigger JIT compilation (threshold = 100)
(let loop ((i 0) (acc 0))
  (if (< i 200)
      (loop (+ i 1) (+ acc (run)))
      (check "box_local accumulator" acc 400)))

;; Verify individual call after JIT compilation
(check "box_local single call" (run) 2)

;; Mutable captured local with multiple set!
(define (run2)
  (let ((x 10))
    (let ((get (lambda () x))
          (set (lambda (v) (set! x v))))
      (set 42)
      (+ x (get)))))

(let loop ((i 0))
  (when (< i 200) (run2) (loop (+ i 1))))

(check "box_local multi-set!" (run2) 84)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "JIT box_local tests failed" fail))
