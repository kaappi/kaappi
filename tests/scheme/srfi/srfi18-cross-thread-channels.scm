;; KEP-0002 Phase 2 (#1467): envelopes at thread boundaries.
;;
;; thread-start! now copies the thunk into an envelope on the parent thread,
;; before spawning the child -- the only place a channel captured by the
;; thunk can legally promote (KEP-0002 Phase 1, #1482). thread-join!'s
;; result/exception cross the same way, via an envelope built on the child
;; thread right before it exits. Together these make cross-thread channels
;; actually usable end to end for the first time.
;;
;; Phase 3 (#1468) has not landed yet, so every scenario here is restricted
;; to "send completes before receive is attempted" interleavings: a receive
;; on an empty *shared* channel has no wakeup machinery to park on yet.
;; Ordering is made deterministic via thread-join! (which only returns once
;; the child is fully done, including any sends it made) rather than by
;; timing/luck.

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

(let ((runner (test-runner-current)))
  (test-end "srfi18-cross-thread-channels")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
