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

(define (gc-pressure)
  (let loop ((i 0))
    (when (< i 5000)
      (cons i (make-list 5 i))
      (loop (+ i 1)))))

;; Test 1: set! on a captured mutable variable (set_upvalue opcode, boxed case)
(define (make-box init)
  (let ((slot init))
    (lambda (op . args)
      (cond ((eq? op 'get) slot)
            ((eq? op 'set!) (set! slot (car args)))))))

(define b (make-box '()))
(gc-pressure)
(b 'set! (cons 'live 'value))
(gc-pressure)
(check "set_upvalue box survives GC" (b 'get) '(live . value))

;; Test 2: multiple set! cycles on captured variable
(define (make-counter)
  (let ((n 0))
    (lambda ()
      (set! n (+ n 1))
      n)))

(define c (make-counter))
(gc-pressure)
(c)
(gc-pressure)
(c)
(gc-pressure)
(check "set_upvalue counter after GC" (c) 3)

;; Test 3: set! storing a fresh heap object into a long-lived closure
(define (make-accumulator)
  (let ((acc '()))
    (lambda (x)
      (set! acc (cons x acc))
      acc)))

(define a (make-accumulator))
(gc-pressure)
(a (string-copy "one"))
(gc-pressure)
(a (string-copy "two"))
(gc-pressure)
(a (string-copy "three"))
(gc-pressure)
(let ((result (a (string-copy "four"))))
  (check "set_upvalue accumulator length" (length result) 4)
  (check "set_upvalue accumulator first" (car result) "four")
  (check "set_upvalue accumulator last" (list-ref result 3) "one"))

;; Test 4: set_box_local — local mutable variable re-bound in a loop
(define (sum-with-mutation n)
  (let ((total 0))
    (let loop ((i 0))
      (when (< i n)
        (set! total (+ total i))
        (gc-pressure)
        (loop (+ i 1))))
    total))

(check "set_box_local loop mutation" (sum-with-mutation 10) 45)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "upvalue write barrier tests failed" fail))
