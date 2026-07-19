;; Regression test for KEP-0001 Phase 2 (kaappi/kaappi#1440): a timed
;; mutex-lock! must expire promptly even while a busy, repeatedly-yielding
;; sibling fiber keeps the scheduler's dispatch loop from ever going idle.
;;
;; Before this fix, timer expiry was only checked in parkOnReactor (the
;; idle branch of the scheduler), so a runnable sibling starved the timeout
;; check: a 0.05s timeout fired only once the sibling finished (~0.74s in
;; the reviewer's repro) instead of at ~0.05s. schedule() now pops expired
;; reactor timers on every dispatch tick, not just when idle.
;;
;; The regression signal is an ORDERING, not an absolute duration: with the
;; fix the timed lock resolves early in the sibling's run; without it, only
;; once the sibling has finished. So the sibling timestamps its own
;; completion, and the test asserts the timed lock resolved BEFORE that.
;; Both samples come from one clock, so a slow/loaded QEMU VM (the netbsd CI
;; runner) stretches them together and cannot invert their order — whereas
;; the earlier absolute "< 0.3s" bound flaked there whenever a host
;; deschedule near the 0.05s expiry pushed the single sample past 0.3s.
;; (Widening that bound is not an option: the broken build resolves at
;; ~0.7s, so any absolute bound loose enough to never flake would also let
;; a genuinely-broken build pass.)

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

(define timeout 0.05)

(define m (make-mutex))
(mutex-lock! m)

;; Single shared origin so the waiter's and sibling's elapsed samples are
;; directly comparable.
(define t0 (now))

(define waiter
  (spawn (lambda ()
           (let ((r (mutex-lock! m timeout)))
             (list r (- (now) t0))))))

;; Busy sibling: yields repeatedly without ever parking, so the scheduler's
;; dispatch loop stays busy (never reaches the idle/parkOnReactor branch)
;; for well over the waiter's timeout. It timestamps its own completion so
;; the test can compare the two fibers on one clock.
(define busy
  (spawn (lambda ()
           (let loop ((i 0))
             (if (< i 8000000)
                 (begin (yield) (loop (+ i 1)))
                 (- (now) t0))))))

(define result (fiber-join waiter))
(define busy-elapsed (fiber-join busy))
(define wait-elapsed (cadr result))

(check "lock-timed-out" (car result) #f)

;; Premise: the busy sibling must genuinely outlast the timeout by a wide
;; margin, otherwise "resolved before the sibling finished" proves little.
;; This can only fail if the sibling ran too FAST (needs more iterations) —
;; emulation slowdown makes busy-elapsed larger, never smaller.
(if (> busy-elapsed (* timeout 4))
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: busy-sibling-outlasts-timeout busy-elapsed=")
      (write busy-elapsed)
      (display " (expected > ")
      (write (* timeout 4))
      (display "; bump the iteration count)")
      (newline)))

;; The regression signal: the timed lock must resolve BEFORE the busy
;; sibling completes, not only once it has finished. With the fix
;; wait-elapsed is sampled (~timeout) well before busy-elapsed (~0.7s+);
;; without it, the lock resolves at busy-finish+e so this inverts.
(if (< wait-elapsed busy-elapsed)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: resolved-before-sibling-finished wait-elapsed=")
      (write wait-elapsed)
      (display " busy-elapsed=")
      (write busy-elapsed)
      (display " (timed lock did not resolve before the busy sibling finished)")
      (newline)))

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
