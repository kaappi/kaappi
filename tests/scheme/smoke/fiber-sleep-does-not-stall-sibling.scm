;; Regression test for KEP-0001 Phase 2 (kaappi/kaappi#1440): thread-sleep!
;; is now a timed park on the reactor's timer heap instead of a
;; whole-thread nanosleep, so a sibling fiber's unrelated work can finish
;; WHILE this fiber sleeps, not just after it wakes.
;;
;; fiber-join's own round-robin dispatches the sleeper fiber first (it was
;; spawned first), so measuring wall-clock time around fiber-join calls
;; doesn't cleanly show this — the sleeper's own timed wait recursively
;; drives the fast fiber to completion before ever returning control.
;; Instead, the fast fiber timestamps its own completion, and that
;; timestamp must land near the start, not near the end of the sleep.

(import (scheme base) (scheme write) (kaappi fibers) (srfi 18))

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

(define (now) (time->seconds (current-time)))

(define fast-done-at #f)
(define sleep-seconds 0.3)
(define t0 (now))

(define sleeper (spawn (lambda () (thread-sleep! sleep-seconds) 'slept)))
(define fast (spawn (lambda () (set! fast-done-at (now)) 'fast-done)))

(define sleeper-result (fiber-join sleeper))
(define t-end (now))
(define fast-result (fiber-join fast))

(check "sleeper-result" sleeper-result 'slept)
(check "fast-result" fast-result 'fast-done)
(check "fast-ran" (not (eq? fast-done-at #f)) #t)
;; The fast fiber's own work is instant; if it ran DURING the sleep
;; (not stalled behind it) its timestamp lands close to t0, well before
;; the sleep's own duration elapses.
(check "fast-ran-during-the-sleep-not-after"
       (and fast-done-at (< (- fast-done-at t0) (/ sleep-seconds 2)))
       #t)
(check "sleep-actually-took-a-while" (>= (- t-end t0) (* sleep-seconds 0.8)) #t)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
