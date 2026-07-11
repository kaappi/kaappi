;; Regression test for KEP-0001 Phase 2 (kaappi/kaappi#1440): thread-join!'s
;; fiber path must clear me.deadline_ns once its wait resolves, exactly
;; like thread-sleep!/mutex-lock!/mutex-unlock! already do.
;;
;; Before this fix, a timed thread-join! that resolved before its deadline
;; left the stale deadline_ns in place. A later, unrelated *untimed* wait
;; on the same fiber was then misread by hasRunnableFibers() as a live
;; timed wait (`.waiting` + `deadline_ns != null`), even though the
;; reactor no longer had a timer for it. That made parkOnReactor's
;; deadlock check falsely conclude "more progress is possible" and block
;; forever in reactor.poll(null) instead of detecting the genuine deadlock
;; below (an untimed mutex-lock! on a mutex held by a fiber that can never
;; release it).

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

;; Timed join that resolves well before its deadline — the stale
;; deadline_ns bug requires a *resolved* (not timed-out) timed wait.
(define f1 (spawn (lambda () (yield) 'quick)))
(define kick (spawn (lambda () 'kick)))
(fiber-join kick)
(check "timed-join-result" (thread-join! f1 5.0) 'quick)

;; A mutex held forever by a fiber blocked receiving on a channel no one
;; will ever send to: any wait on `m` can never resolve.
(define m (make-mutex))
(define ch (make-channel))
(define holder
  (spawn (lambda ()
           (mutex-lock! m)
           (channel-send ch 'locked)
           (channel-receive (make-channel)))))
(check "holder-locked" (channel-receive ch) 'locked)

;; Untimed lock on the permanently-held mutex: on the buggy code this
;; hangs forever (caught by the test runner's timeout); on the fixed code
;; it raises a deadlock error promptly.
(define deadlock-detected
  (guard (e (#t 'deadlock-raised))
    (mutex-lock! m)
    'unexpectedly-succeeded))

(check "untimed-lock-on-dead-mutex-raises-deadlock" deadlock-detected 'deadlock-raised)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
