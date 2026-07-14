;; Regression test for kaappi#1489: a lost cross-thread wakeup.
;;
;; A local sibling fiber's channel-send + channel-receive, executed during a
;; receiver's SharedChannelPoll drive, used to consume the receiver's one-shot
;; recv_waiters notifier registration and leave it parked-but-unregistered, so a
;; later send from a real peer thread rang nothing and the receiver hung forever
;; (the fix re-derives readiness through receive() after the drive, re-arming the
;; registration under the channel lock before the park).
;;
;; Bounded by a receive timeout so a regression is a FAIL, not a hang (which
;; tests/scheme/run-all.sh would SKIP and thereby hide): pre-fix, the parked
;; receiver's notifier is disarmed, the remote send rings nothing, and only the
;; 5 s timer fires (=> 'timed-out); post-fix, the remote send wakes it (=> 42).
;; The remote sleep makes the receiver reach its park before the send arrives,
;; so the send must travel the wakeup path this test guards.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 18) (srfi 64))

(test-begin "fiber-channel-lost-wakeup-1489")

(define result
  (let ((ch (make-channel)))            ; local => captured by the thunk => promoted
    (define t (make-thread (lambda ()
                             (thread-sleep! 0.5)   ; let the receiver park first
                             (channel-send ch 42))))
    (thread-start! t)
    (spawn (lambda ()
             (channel-send ch 'decoy)   ; snapshots-and-clears recv_waiters, rings
             (channel-receive ch)))     ; drains its own value back
    (let ((got (channel-receive ch 5 'timed-out)))  ; parks; must be woken by the remote send
      (thread-join! t)
      got)))

(test-equal "remote send wakes a receiver whose notifier a local decoy disarmed"
  42 result)

(let ((runner (test-runner-current)))
  (test-end "fiber-channel-lost-wakeup-1489")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
