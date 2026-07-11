;; Regression test for KEP-0001 Phase 2 (kaappi/kaappi#1440): a timed
;; mutex-lock! must expire promptly even while a busy, repeatedly-yielding
;; sibling fiber keeps the scheduler's dispatch loop from ever going idle.
;;
;; Before this fix, timer expiry was only checked in parkOnReactor (the
;; idle branch of the scheduler), so a runnable sibling starved the timeout
;; check: a 0.05s timeout fired only once the sibling finished (~0.74s in
;; the reviewer's repro) instead of at ~0.05s. schedule() now pops expired
;; reactor timers on every dispatch tick, not just when idle.

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

(define m (make-mutex))
(mutex-lock! m)

(define waiter
  (spawn (lambda ()
           (let ((t0 (now)))
             (let ((r (mutex-lock! m 0.05)))
               (list r (- (now) t0)))))))

;; Busy sibling: yields repeatedly without ever parking, so the scheduler's
;; dispatch loop stays busy (never reaches the idle/parkOnReactor branch)
;; for well over the waiter's 0.05s timeout.
(define busy
  (spawn (lambda ()
           (let loop ((i 0))
             (if (< i 8000000)
                 (begin (yield) (loop (+ i 1)))
                 'done)))))

(define result (fiber-join waiter))

(check "lock-timed-out" (car result) #f)
;; Generous bound: must resolve well before the busy sibling's ~0.7s+
;; runtime, not merely finish eventually.
(check "resolved-near-timeout-not-after-sibling" (< (cadr result) 0.3) #t)

(fiber-join busy)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
