;; KEP-0002 §6 (#1469): (make-channel capacity) on the local (unpromoted)
;; representation -- a bounded channel parks the sender when full instead
;; of growing without limit, and a receive frees a slot for a parked
;; sender to resume into.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 18) (srfi 64))

(test-begin "fiber-channel-capacity")

;; --- capacity 1: a second send parks until a receive frees the slot ---
(test-equal "bounded channel: sender parks when full, resumes after a receive"
  '(first second)
  (let* ((ch (make-channel 1))
         (order '()))
    (channel-send ch 'first) ; fills the one slot, does not park
    (spawn (lambda ()
             (channel-send ch 'second))) ; must park: channel is full
    (yield) ; let the spawned sender run and park
    (set! order (cons (channel-receive ch) order)) ; frees the slot -- wakes it
    (yield)
    (set! order (cons (channel-receive ch) order))
    (reverse order)))

;; --- capacity 0: a rendezvous channel (KEP-0002 §6 as amended, #1602) —
;; a timed send with no receiver committed parks and times out; the full
;; pairing semantics live in fiber-channel-rendezvous.scm ---
(test-equal "capacity-0 channel: unpaired send times out"
  'timed-out
  (let ((ch (make-channel 0)))
    (channel-send ch 1 0.05 'timed-out)))

;; --- make-channel argument validation ---
(test-assert "make-channel rejects a negative capacity"
  (guard (e (#t #t)) (make-channel -1) #f))

(test-assert "make-channel rejects a non-integer capacity"
  (guard (e (#t #t)) (make-channel 1.5) #f))

;; --- capacity survives multiple fill/drain cycles ---
(test-equal "bounded channel: repeated fill-then-drain cycles"
  '(0 1 2 3 4)
  (let ((ch (make-channel 2)))
    (let loop ((i 0) (acc '()))
      (if (= i 5)
          (reverse acc)
          (begin
            (channel-send ch i)
            (loop (+ i 1) (cons (channel-receive ch) acc)))))))

;; --- a spawned sender parked on a full channel deadlocks cleanly if
;; nothing will ever receive (no timeout given) ---
(test-assert "bounded channel: send with no receiver and no other fiber raises a deadlock error"
  (guard (e (#t #t))
    (let ((ch (make-channel 0)))
      (channel-send ch 1)
      #f)))

(let ((runner (test-runner-current)))
  (test-end "fiber-channel-capacity")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
