;; Regression test for #208: write barriers in promise forcing.
;; Forces promises under GC pressure to verify old→young references
;; in promise.value are tracked by the generational GC.

(import (scheme base)
        (scheme write)
        (scheme lazy))

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
    (when (< i 500)
      (make-vector 50 (list i i i))
      (loop (+ i 1)))))

;; Test 1: basic delay/force with GC pressure
(define p1 (delay (begin (gc-pressure) (list 'a 'b 'c))))
(gc-pressure)
(check "force-basic" (force p1) '(a b c))
(gc-pressure)
(check "force-cached" (force p1) '(a b c))

;; Test 2: chained promises (SRFI-45 forwarding)
(define p2 (delay (delay (begin (gc-pressure) (vector 1 2 3)))))
(gc-pressure)
(check "force-chained" (force p2) #(1 2 3))
(gc-pressure)
(check "force-chained-cached" (force p2) #(1 2 3))

;; Test 3: make-promise with non-promise value
(define p3 (make-promise 42))
(gc-pressure)
(check "make-promise-val" (force p3) 42)

;; Test 4: deeply nested delay chain
(define p4 (delay (delay (delay (begin (gc-pressure) "deep")))))
(gc-pressure)
(check "force-deep" (force p4) "deep")

;; Test 5: promise producing large heap object
(define p5 (delay (begin
                    (gc-pressure)
                    (let ((v (make-vector 100 #f)))
                      (vector-set! v 0 'first)
                      (vector-set! v 99 'last)
                      v))))
(gc-pressure)
(let ((r (force p5)))
  (check "large-result-first" (vector-ref r 0) 'first)
  (check "large-result-last" (vector-ref r 99) 'last))

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
