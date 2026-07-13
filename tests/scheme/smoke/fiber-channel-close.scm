;; KEP-0002 §6 (#1469): channel-close!/channel-closed? on the local
;; (unpromoted) representation -- end-of-stream as a first-class state.
;; Receivers drain whatever is queued before eof; sends after close raise;
;; close is idempotent; sending a literal eof-object is rejected (the one
;; backward-compat carve-out, since it would be indistinguishable from
;; close's own end-of-stream at the receiver).

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 18) (srfi 64))

(test-begin "fiber-channel-close")

(test-assert "channel-closed? is #f on a fresh channel"
  (not (channel-closed? (make-channel))))

(test-equal "channel-close! drains queued values before eof"
  '(1 2 done)
  (let ((ch (make-channel)))
    (channel-send ch 1)
    (channel-send ch 2)
    (channel-close! ch)
    (list (channel-receive ch)
          (channel-receive ch)
          (if (eof-object? (channel-receive ch)) 'done 'not-done))))

(test-assert "channel-closed? is #t after channel-close!"
  (let ((ch (make-channel)))
    (channel-close! ch)
    (channel-closed? ch)))

(test-assert "channel-close! is idempotent"
  (let ((ch (make-channel)))
    (channel-close! ch)
    (channel-close! ch) ; must not raise
    (channel-closed? ch)))

(test-assert "channel-send on a closed channel raises"
  (let ((ch (make-channel)))
    (channel-close! ch)
    (guard (e (#t #t)) (channel-send ch 1) #f)))

(test-assert "sending a literal eof-object raises (use channel-close! instead)"
  (let ((ch (make-channel)))
    (guard (e (#t #t)) (channel-send ch (eof-object)) #f)))

;; --- close wakes a parked receiver on an empty channel ---
(test-equal "channel-close! wakes a fiber parked on channel-receive"
  'eof
  (let* ((ch (make-channel))
         (f (spawn (lambda () (if (eof-object? (channel-receive ch)) 'eof 'value)))))
    (yield) ; let the receiver run and park on the empty channel
    (channel-close! ch)
    (fiber-join f))) ; drives the scheduler until f completes -- no hang

;; --- close wakes a parked sender on a full bounded channel too ---
(test-assert "channel-close! wakes a fiber parked on channel-send (raises, not hangs)"
  (let* ((ch (make-channel 0))
         (f (spawn (lambda ()
                     (guard (e (#t 'raised)) (channel-send ch 1) 'not-raised)))))
    (yield) ; let the sender run and park (capacity 0: always full)
    (channel-close! ch)
    (eq? 'raised (fiber-join f))))

(let ((runner (test-runner-current)))
  (test-end "fiber-channel-close")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
