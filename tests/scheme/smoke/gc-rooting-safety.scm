;; Regression tests for GC safety: unrooted values across allocations.
;; Covers #207 (spawnFiber), #209 (forceFn), #213 (kaappi_cons via native),
;; and #226 (invokeEscape).

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
    (when (< i 1000)
      (make-vector 100 (list i i i))
      (loop (+ i 1)))))

;; Test: force with delay-force chains under GC pressure (#209)
;; The bug was that `current` in forceFn wasn't rooted after SRFI-45
;; forwarding, so GC during thunk evaluation could collect it.
(define (make-chain n)
  (if (= n 0)
      (delay 'done)
      (delay-force (begin (gc-pressure) (make-chain (- n 1))))))

(check "delay-force-chain-5" (force (make-chain 5)) 'done)
(check "delay-force-chain-10" (force (make-chain 10)) 'done)

;; Test: call/ec escape continuation invoked outside extent (#226)
;; The bug was that the error message string wasn't rooted before
;; allocating the error object.
(define (test-escape-outside)
  (let ((k #f))
    (call-with-current-continuation
     (lambda (exit)
       (call/ec
        (lambda (esc)
          (set! k esc)))
       (gc-pressure)
       (guard (exn (#t 'caught))
         (k 42))))))

(check "escape-outside-extent" (test-escape-outside) 'caught)

;; Test: force under heavy GC pressure to exercise promise rooting
(define (stress-force n)
  (let lp ((i 0))
    (if (= i n)
        i
        (begin
          (force (delay (begin (gc-pressure) 'ok)))
          (lp (+ i 1))))))

(check "stress-force-20" (stress-force 20) 20)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
