;; Regression tests for #1600/#1603: rendezvous channels (capacity 0)
;; across real OS threads — the promoted SharedChannel representation
;; (KEP-0002 §6 as amended, kaappi/keps#28). The channel must be CAPTURED
;; by the thunk (let-bound): that is the §2 legal sharing path that
;; promotes it; a top-level global would fail the foreign-owner check on
;; the child instead.
(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 18) (srfi 64))

(test-begin "fiber-channel-rendezvous-thread")

;; --- child thread sends, parent receives (the #1600 cross-thread shape) ---
(test-equal "child-thread sender pairs with parent receiver"
  'x
  (let* ((ch (make-channel 0))
         (t (thread-start! (make-thread (lambda () (channel-send ch 'x) 'sent)))))
    (let ((v (channel-receive ch)))
      (thread-join! t)
      v)))

;; --- parent sends, child thread receives ---
(test-equal "parent sender pairs with child-thread receiver"
  'hello
  (let* ((ch (make-channel 0))
         (t (thread-start! (make-thread (lambda () (channel-receive ch))))))
    (channel-send ch 'hello)
    (thread-join! t)))

;; --- several values, one at a time (each send waits for its receive) ---
(test-equal "sequential rendezvous handoffs across the thread boundary"
  '(1 2 3)
  (let* ((ch (make-channel 0))
         (t (thread-start!
             (make-thread (lambda ()
                            (channel-send ch 1)
                            (channel-send ch 2)
                            (channel-send ch 3)
                            'done)))))
    (let ((vs (list (channel-receive ch)
                    (channel-receive ch)
                    (channel-receive ch))))
      (thread-join! t)
      vs)))

;; --- timeouts stay the unpaired escape hatch on the promoted path ---
(test-equal "promoted rendezvous: unpaired timed send times out"
  'sto
  (let ((ch (make-channel 0)))
    ;; promote by round-tripping through a thread that ignores the channel
    (let ((t (thread-start! (make-thread (lambda () (channel-closed? ch))))))
      (thread-join! t)
      (channel-send ch 'v 0.05 'sto))))

(test-equal "promoted rendezvous: unpaired timed receive times out"
  'rto
  (let ((ch (make-channel 0)))
    (let ((t (thread-start! (make-thread (lambda () (channel-closed? ch))))))
      (thread-join! t)
      (channel-receive ch 0.05 'rto))))

;; --- close crosses the boundary: parent closes, parked child receiver eofs ---
(test-equal "channel-close! wakes a child-thread rendezvous receiver with eof"
  'eof
  (let* ((ch (make-channel 0))
         (t (thread-start!
             (make-thread (lambda ()
                            (if (eof-object? (channel-receive ch)) 'eof 'val))))))
    (thread-sleep! 0.05) ; let the child park
    (channel-close! ch)
    (thread-join! t)))

(let ((runner (test-runner-current)))
  (test-end "fiber-channel-rendezvous-thread")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
