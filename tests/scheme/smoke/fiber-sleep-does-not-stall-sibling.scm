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
(define sleeper-woke-at #f)
(define sleep-seconds 0.3)
(define t0 (now))

(define sleeper (spawn (lambda ()
                         (thread-sleep! sleep-seconds)
                         (set! sleeper-woke-at (now))
                         'slept)))
(define fast (spawn (lambda () (set! fast-done-at (now)) 'fast-done)))

(define sleeper-result (fiber-join sleeper))
(define t-end (now))
(define fast-result (fiber-join fast))

(check "sleeper-result" sleeper-result 'slept)
(check "fast-result" fast-result 'fast-done)
(check "fast-ran" (not (eq? fast-done-at #f)) #t)
(check "sleeper-woke" (not (eq? sleeper-woke-at #f)) #t)
;; The property under test is an ORDERING, so assert the ordering rather
;; than a duration: the fast fiber's completion must precede the sleeper's
;; wake-up. Under the pre-KEP-0001 behaviour (a whole-thread nanosleep) the
;; fast fiber could not run at all until the sleeper woke, so its timestamp
;; would land after -- the same discrimination the old assertion made, but
;; with no wall-clock bound to blow on an emulated leg. The old form
;; required the fast fiber to finish within sleep-seconds/2 = 150 ms of t0,
;; which is an upper bound on how slow the machine may be (audit v2 phase
;; 5E; cf. the campaign footgun "never assert wall-clock timing -- assert
;; relative ordering").
(check "fast-ran-during-the-sleep-not-after"
       (and fast-done-at sleeper-woke-at (< fast-done-at sleeper-woke-at))
       #t)
;; A lower bound is the safe direction: a slow machine can only make the
;; measured interval longer.
(check "sleep-actually-took-a-while" (>= (- t-end t0) (* sleep-seconds 0.8)) #t)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
