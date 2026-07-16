;; KEP-0002 §6 (#1469): [timeout [timeout-val]] on channel-receive and
;; channel-send, SRFI-18 shape (same as thread-join!): without timeout-val,
;; expiry raises channel-timeout-exception?; with one, it is returned
;; instead. Covers both directions, with and without timeout-val, on both
;; an empty/full local channel and one with data/room ready immediately
;; (timeout must not fire when the operation can complete right away).

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 18) (srfi 64))

(test-begin "fiber-channel-timeout")

;; --- receive: no timeout-val -> raises a channel-timeout-exception? ---
(test-assert "channel-receive on an empty channel times out and raises"
  (let ((ch (make-channel)))
    (guard (e (#t (channel-timeout-exception? e)))
      (channel-receive ch 0.05)
      #f)))

;; --- receive: with timeout-val -> returns it instead of raising ---
(test-equal "channel-receive on an empty channel times out and returns timeout-val"
  'gave-up
  (let ((ch (make-channel)))
    (channel-receive ch 0.05 'gave-up)))

;; --- receive: a value already queued is returned immediately, ignoring
;; the timeout entirely ---
(test-equal "channel-receive with a ready value does not wait out the timeout"
  42
  (let ((ch (make-channel)))
    (channel-send ch 42)
    (channel-receive ch 5)))

;; --- send: no timeout-val -> raises when no receiver ever commits
;; (capacity 0 = rendezvous, KEP-0002 §6 as amended: an unpaired send
;; parks; the timeout is the escape hatch) ---
(test-assert "channel-send with no receiver times out and raises"
  (let ((ch (make-channel 0)))
    (guard (e (#t (channel-timeout-exception? e)))
      (channel-send ch 1 0.05)
      #f)))

;; --- send: with timeout-val -> returns it instead of raising ---
(test-equal "channel-send with no receiver times out and returns timeout-val"
  'gave-up
  (let ((ch (make-channel 0)))
    (channel-send ch 1 0.05 'gave-up)))

;; --- send: room available completes immediately, ignoring the timeout ---
(test-equal "channel-send with room available does not wait out the timeout"
  'ok
  (let ((ch (make-channel 1)))
    (channel-send ch 1 5)
    'ok))

;; --- a fiber timing out on a shared wait still lets siblings run first ---
;; fiber-join (not a thread-sleep!-based polling loop) drives the wait: a
;; polling loop on the main fiber would itself be a *second*, concurrently
;; pending timed wait (thread-sleep!) nested around this one, and nested
;; timed waits on unrelated fibers are a separate, pre-existing scheduler
;; hazard (#1490) this test must not trip over.
(test-equal "a spawned fiber's channel-receive timeout does not block siblings"
  '(sibling-done timed-out)
  (let ((ch (make-channel))
        (log '()))
    (define timeout-fiber
      (spawn (lambda ()
               (guard (e (#t (set! log (cons 'timed-out log))))
                 (channel-receive ch 0.1)))))
    (define sibling-fiber
      (spawn (lambda () (set! log (cons 'sibling-done log)))))
    (fiber-join sibling-fiber)
    (fiber-join timeout-fiber)
    (reverse log)))

;; --- channel-timeout-exception? is #f for other error kinds ---
(test-assert "channel-timeout-exception? is #f for an ordinary error"
  (guard (e (#t (not (channel-timeout-exception? e))))
    (error "not a timeout")
    #f))

(let ((runner (test-runner-current)))
  (test-end "fiber-channel-timeout")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
