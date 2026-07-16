;; Regression tests for #1600/#1602: (make-channel 0) is a rendezvous
;; channel (KEP-0002 §6 as amended, kaappi/keps#28) — channel-send completes
;; only against a committed receiver, channel-receive only when a sender
;; provides a value; whichever side arrives first waits. Before the fix,
;; capacity 0 was "permanently full" and every untimed pairing deadlocked.
(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 64))

(test-begin "fiber-channel-rendezvous")

;; --- the #1600 repro, verbatim shape: spawned sender, main receiver ---
(test-equal "sender-first handoff (the #1600 repro)"
  'x
  (let ((ch (make-channel 0)))
    (spawn (lambda () (channel-send ch 'x)))
    (channel-receive ch)))

;; --- receiver first, main sender ---
(test-equal "receiver-first handoff"
  'hello
  (let* ((ch (make-channel 0))
         (f (spawn (lambda () (channel-receive ch)))))
    (channel-send ch 'hello)
    (fiber-join f)))

;; --- the synchronous guarantee: a send cannot complete unpaired ---
(test-equal "send completes only after a receiver commits"
  '(not-sent-yet v sent)
  (let* ((ch (make-channel 0))
         (state 'not-sent-yet)
         (f (spawn (lambda () (channel-send ch 'v) (set! state 'sent)))))
    (yield) ; the sender runs and parks — a buffered channel would complete it
    (let ((pre state)
          (got (channel-receive ch)))
      (fiber-join f)
      (list pre got state))))

;; --- unpaired operations still deadlock cleanly (fail-loud preserved) ---
(test-assert "unpaired untimed send raises a deadlock error"
  (guard (e (#t #t)) (channel-send (make-channel 0) 1) #f))

(test-assert "unpaired untimed receive raises a deadlock error"
  (guard (e (#t #t)) (channel-receive (make-channel 0)) #f))

;; --- timeouts stay the unpaired escape hatch ---
(test-equal "unpaired send times out with timeout-val"
  'sto
  (channel-send (make-channel 0) 'v 0.05 'sto))

(test-equal "unpaired receive times out with timeout-val"
  'rto
  (channel-receive (make-channel 0) 0.05 'rto))

(test-assert "unpaired send timeout without timeout-val raises channel-timeout"
  (let ((ch (make-channel 0)))
    (guard (e (#t (channel-timeout-exception? e)))
      (channel-send ch 1 0.05)
      #f)))

;; --- a timed operation paired with a waiting counterparty never waits out ---
(test-equal "timed receive with a parked sender returns the value immediately"
  'fast
  (let ((ch (make-channel 0)))
    (spawn (lambda () (channel-send ch 'fast)))
    (yield) ; let the sender park
    (channel-receive ch 5 'never)))

(test-equal "timed send with a parked receiver completes immediately"
  'got-it
  (let* ((ch (make-channel 0))
         (f (spawn (lambda () (channel-receive ch)))))
    (yield) ; let the receiver park (commit demand)
    (channel-send ch 'got-it 5)
    (fiber-join f)))

;; --- a timed-out receive withdraws its demand and strands nothing ---
(test-equal "timed-out receive leaves no phantom demand and no stranded value"
  '(rto sto empty)
  (let ((ch (make-channel 0)))
    (list (channel-receive ch 0.05 'rto)
          (channel-send ch 'v 0.05 'sto)
          (channel-receive ch 0.05 'empty))))

;; --- close wakes both sides ---
(test-equal "channel-close! wakes a parked rendezvous receiver with eof"
  'eof
  (let* ((ch (make-channel 0))
         (f (spawn (lambda () (if (eof-object? (channel-receive ch)) 'eof 'val)))))
    (yield)
    (channel-close! ch)
    (fiber-join f)))

(test-equal "channel-close! wakes a parked rendezvous sender with a raise"
  'raised
  (let* ((ch (make-channel 0))
         (f (spawn (lambda () (guard (e (#t 'raised)) (channel-send ch 1) 'sent)))))
    (yield)
    (channel-close! ch)
    (fiber-join f)))

;; --- two parked timed senders, one receiver: exactly one handoff ---
;; (regression for the frozen-ancestor interleaving found in #1602: this
;; raised a spurious deadlock when timed senders parked in-call)
(test-assert "one of two parked timed senders pairs; the other times out"
  (let* ((ch (make-channel 0))
         (s1 (spawn (lambda () (channel-send ch 'a 0.3 'ta))))
         (s2 (spawn (lambda () (channel-send ch 'b 0.3 'tb)))))
    (yield)
    (let ((got (channel-receive ch)))
      (fiber-join s1)
      (fiber-join s2)
      (memq got '(a b)))))

;; --- two parked receivers, two sends: both delivered ---
(test-assert "two parked receivers each collect one of two sends"
  (let* ((ch (make-channel 0))
         (r1 (spawn (lambda () (channel-receive ch))))
         (r2 (spawn (lambda () (channel-receive ch)))))
    (yield)
    (channel-send ch 'one)
    (channel-send ch 'two)
    (let ((got (list (fiber-join r1) (fiber-join r2))))
      (and (memq 'one got) (memq 'two got) #t))))

;; --- rendezvous ping-pong: repeated pairing over two channels ---
(test-equal "ping-pong across two rendezvous channels"
  '(10 20 30)
  (let ((ping (make-channel 0))
        (pong (make-channel 0)))
    (spawn (lambda ()
             (let loop ((n 0))
               (unless (= n 3)
                 (channel-send pong (* 10 (channel-receive ping)))
                 (loop (+ n 1))))))
    (list (begin (channel-send ping 1) (channel-receive pong))
          (begin (channel-send ping 2) (channel-receive pong))
          (begin (channel-send ping 3) (channel-receive pong)))))

;; --- eof-objects stay rejected on rendezvous channels too ---
(test-assert "channel-send rejects an eof-object on a rendezvous channel"
  (let* ((ch (make-channel 0))
         (f (spawn (lambda () (channel-receive ch 0.2 'nothing)))))
    (yield)
    (guard (e (#t #t)) (channel-send ch (eof-object)) #f)))

(let ((runner (test-runner-current)))
  (test-end "fiber-channel-rendezvous")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
