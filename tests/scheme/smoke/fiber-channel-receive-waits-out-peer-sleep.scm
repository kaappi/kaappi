;; Regression test for KEP-0001's headline motivating bug (see the KEP's
;; Motivation section): channel-receive must not falsely report deadlock
;; when its only potential sender is currently in a timed sleep (about to
;; send once it wakes) rather than genuinely stuck forever. Before Phase 2,
;; channel-receive's idle branch was a bare `break` with no wait/retry, so
;; a peer's pending timeout was invisible to it.

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

(define ch (make-channel))

(define sender
  (spawn (lambda ()
           (thread-sleep! 0.1)
           (channel-send ch 'delivered))))

;; Must resolve once the sender wakes and sends, not raise a deadlock
;; error and not hang.
(check "delivered-after-peer-sleep" (channel-receive ch) 'delivered)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
