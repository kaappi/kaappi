;; Regression test for #447: unrooted closure during upvalue capture.
;; Creates closures that capture local variables under GC pressure,
;; exercising the allocPair boxing path in the closure opcode.

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

(define (gc-pressure)
  (let loop ((i 0))
    (when (< i 300)
      (make-vector 40 (list i))
      (loop (+ i 1)))))

;; Closure capturing multiple locals (forces boxing via allocPair)
(define (make-multi-capture a b c d e)
  (gc-pressure)
  (lambda ()
    (list a b c d e)))

(define f1 (make-multi-capture
             (make-string 10 #\a)
             (make-string 10 #\b)
             (make-string 10 #\c)
             (make-string 10 #\d)
             (make-string 10 #\e)))
(gc-pressure)
(let ((result (f1)))
  (check "capture-a" (string-length (list-ref result 0)) 10)
  (check "capture-e" (string-length (list-ref result 4)) 10))

;; Nested closures with shared mutable upvalues
(define (make-counter init)
  (let ((count init))
    (gc-pressure)
    (let ((inc (lambda () (set! count (+ count 1)) count))
          (get (lambda () count)))
      (gc-pressure)
      (list inc get))))

(let* ((ctr (make-counter 0))
       (inc (car ctr))
       (get (cadr ctr)))
  (check "counter-init" (get) 0)
  (inc)
  (gc-pressure)
  (check "counter-inc" (get) 1)
  (inc)
  (inc)
  (check "counter-3" (get) 3))

;; Many closures in a loop, each capturing a fresh local
(define closures
  (let loop ((i 0) (acc '()))
    (if (= i 20)
        (reverse acc)
        (let ((val (make-string 5 (integer->char (+ 65 (modulo i 26))))))
          (gc-pressure)
          (loop (+ i 1) (cons (lambda () val) acc))))))

(for-each
  (lambda (f)
    (gc-pressure)
    (check "loop-closure" (string-length (f)) 5))
  closures)

(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
