;; KEP-0002 Phase 2 (#1467): envelopes at thread boundaries.
;;
;; thread-start! now copies the thunk into an envelope on the parent thread,
;; before spawning the child -- the only place a channel captured by the
;; thunk can legally promote (KEP-0002 Phase 1, #1482). thread-join!'s
;; result/exception cross the same way, via an envelope built on the child
;; thread right before it exits. Together these make cross-thread channels
;; actually usable end to end for the first time.
;;
;; The scenarios through Phase 2's original tests below are restricted to
;; "send completes before receive is attempted" interleavings, with
;; ordering made deterministic via thread-join! (which only returns once
;; the child is fully done, including any sends it made) rather than by
;; timing/luck. Phase 3 (#1468) added cross-thread wakeup (a receive parked
;; on an empty shared channel now resolves when another thread sends) and
;; Phase 4 (#1469) added capacity/timeouts/close!, both exercised further
;; down this file.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (kaappi fibers) (srfi 64))

(test-begin "srfi18-cross-thread-channels")

;; --- Motivation Path 1: a channel captured lexically in the thread thunk ---
;; Before Phase 1+2: deepCopy rejected the channel outright ("thread thunk
;; contains uncopyable type"). Now: `ch` is promoted on the parent thread as
;; part of the envelope build, aliased into the child's heap on copy-out.
(test-equal "channel captured in thread thunk: send from child, receive from parent"
  42
  (let* ((ch (make-channel))
         (t (make-thread (lambda () (channel-send ch 42)))))
    (thread-start! t)
    (thread-join! t)
    (channel-receive ch)))

;; --- Thunk snapshot: mutation after thread-start! returns is invisible ---
;; The envelope copy runs synchronously inside thread-start!, before it ever
;; returns, so this is deterministic -- not a race the test might get lucky
;; on. Before Phase 2, the child deepCopy'd fiber.thunk at some arbitrary
;; later point, so this mutation could (nondeterministically) already have
;; been visible to it.
(test-equal "thunk snapshot: mutation after thread-start! not visible to child"
  1
  (let* ((v (vector 1))
         (t (make-thread (lambda () (vector-ref v 0)))))
    (thread-start! t)
    (vector-set! v 0 999)
    (thread-join! t)))

;; --- A channel created and returned by the child ---
;; The join result crosses via an envelope built on the CHILD thread (the
;; channel's owner), not deepCopy'd by the parent at join time -- promotion
;; requires gc_instance to match the channel's owner, true only while the
;; child itself is still running.
(test-equal "channel created and returned by the child promotes correctly"
  'hello
  (let* ((t (make-thread (lambda ()
                            (let ((inner (make-channel)))
                              (channel-send inner 'hello)
                              inner)))))
    (thread-start! t)
    (let ((returned-ch (thread-join! t)))
      (channel-receive returned-ch))))

;; --- Reply-channel identity survives two promotion/alias hops ---
;; `tasks` is sent to *before* thread-start!, so thread-start!'s promotion
;; drains its (already-populated) local queue into the shared representation
;; -- the worker's receive never parks. `reply`, nested inside that queued
;; message, is promoted transitively during the same drain. thread-join!
;; establishes the happens-before edge that makes the final receive safe.
(test-equal "reply-channel identity survives a captured round trip"
  42
  (let* ((tasks (make-channel))
         (reply (make-channel))
         (worker (make-thread
                   (lambda ()
                     (let* ((msg (channel-receive tasks))
                            (task-reply (cdr msg)))
                       (channel-send task-reply (* 2 (car msg))))))))
    (channel-send tasks (cons 21 reply))
    (thread-start! worker)
    (thread-join! worker)
    (channel-receive reply)))

;; --- Repeated cross-thread round trips (thread churn) ---
(test-equal "20 sequential cross-thread channel round trips"
  190 ; sum 0..19
  (let loop ((i 0) (acc 0))
    (if (= i 20)
        acc
        (let* ((ch (make-channel))
               (t (make-thread (lambda () (channel-send ch i)))))
          (thread-start! t)
          (thread-join! t)
          (loop (+ i 1) (+ acc (channel-receive ch)))))))

;; --- Motivation Path 2 regression: a channel reached through a shared
;; global (not captured by the thunk) still raises a descriptive
;; foreign-owner error instead of corrupting memory. Phase 2 only changes
;; how the thunk *itself* crosses the boundary, so this must be unaffected.
;; `ch-path2` must be a genuine top-level define (a real global, resolved
;; through vm.globals) rather than let-bound -- an internal define inside a
;; `let` body is lexically scoped (R7RS letrec* semantics) and would be
;; captured as a thunk upvalue instead, testing Path 1 again by accident.
(define ch-path2 (make-channel))
(test-assert "channel reached through a shared global still raises (not captured by thunk)"
  (guard (e (#t #t))
    (thread-join! (thread-start! (make-thread (lambda () (channel-send ch-path2 42)))))
    #f))

;; --- A thunk that still legitimately captures an uncopyable type (mutex)
;; keeps failing exactly as before -- Phase 2 changes *when* the thunk is
;; copied (parent-side, before spawn), not *what* is copyable.
(test-assert "thunk capturing a mutex still raises uncaught-exception at join"
  (let* ((t (let* ((m (make-mutex)))
              (make-thread (lambda () (mutex-lock! m))))))
    (thread-start! t)
    (guard (e (#t (uncaught-exception? e)))
      (thread-join! t)
      #f)))

;; --- KEP-0002 Phase 4 (#1469): capacity, timeouts, close, now exercised
;; across real OS threads (Phase 3's cross-thread wakeup makes a receiver
;; parked in one thread's scheduler resolvable by a send from another).

;; --- bounded shared channel: a full channel backpressures a sender on
;; another thread until the main thread drains a slot ---
(test-equal "bounded shared channel: worker thread blocks on a full channel until the main thread receives"
  '(1 2)
  (let* ((ch (make-channel 1))
         (t (make-thread (lambda ()
                            (channel-send ch 1)  ; fills the one slot
                            (channel-send ch 2))))) ; must park until drained
    (thread-start! t)
    (let ((first (channel-receive ch)))  ; frees the slot -- wakes the worker
      (thread-join! t) ; only returns once the second send completes
      (list first (channel-receive ch)))))

;; --- channel-close! from the main thread wakes a channel-receive loop on
;; a worker thread, draining what was already sent before eof ---
(test-equal "channel-close! from the main thread wakes a worker's receive loop, draining queued sends first"
  '(1 2 3)
  (let* ((ch (make-channel))
         (t (make-thread
              (lambda ()
                (let loop ((acc '()))
                  (let ((v (channel-receive ch)))
                    (if (eof-object? v)
                        (reverse acc)
                        (loop (cons v acc)))))))))
    (thread-start! t)
    (channel-send ch 1)
    (channel-send ch 2)
    (channel-send ch 3)
    (channel-close! ch)
    (thread-join! t)))

;; --- a timed channel-receive on a shared channel is the documented escape
;; hatch for §5's weakened deadlock detection: with no other live thread
;; and no more references, a plain channel-receive would either deadlock
;; or hang, but a timeout still resolves ---
(test-equal "timed channel-receive on a shared channel with no future sender returns timeout-val, not a hang"
  'gave-up
  (let* ((ch (make-channel))
         (t (make-thread (lambda () ch)))) ; capturing ch promotes it
    (thread-start! t)
    (thread-join! t) ; the thread is now gone; ch stays promoted (sticky)
    (channel-receive ch 0.05 'gave-up)))

(let ((runner (test-runner-current)))
  (test-end "srfi18-cross-thread-channels")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
