;; (kaappi parallel) -- worker pools and parallel map/for-each.
;;
;; Pure Scheme over (srfi 18) + (kaappi fibers) (KEP-0002 Phase 5): a pool
;; is a fixed set of workers draining a shared task channel, whose
;; cross-thread promotion and close/drain semantics come entirely from the
;; channel runtime (KEP-0002 Phases 1-4). Every task thunk and result
;; crosses a pool worker boundary BY COPY (SRFI-18 thread deep-copy /
;; channel envelopes) -- a pool shares no mutable state with its caller.
;;
;; When real OS threads are unavailable (WASM, --sandbox), make-pool
;; degrades to spawning fiber workers on the calling thread's scheduler
;; instead: structurally the same pool, cooperative instead of parallel.
;;
;; Known limitation (kaappi#1520): a closure that crosses a thread-start!
;; boundary and then CALLS a separately-defined library-top-level procedure
;; hangs (the identical logic inlined directly into the closure works) --
;; so a pool must only be used from the thread that created it (or one that
;; received it some other way that doesn't route through a fresh
;; thread-start! thunk); do not thread-start! your own worker whose thunk
;; calls pool-submit/task-wait/pool-shutdown!. This is why the worker loop
;; below is inlined into each spawned thunk rather than factored into a
;; shared procedure -- see the comment at %spawn-worker.
;;
;; Known limitation (kaappi#1487, kaappi#1489): parallel-map/parallel-for-each
;; submit one task per list element, so a large list means many concurrent
;; pool-submit/task-wait round trips on the shared task/reply channels --
;; and the cross-thread wakeup path has open correctness issues that surface
;; as an intermittent hang somewhere past a few hundred concurrent
;; submissions (probability grows with count, not a hard cutoff). Reliable
;; in testing through list sizes in the low hundreds. For larger inputs,
;; chunk manually with make-pool/pool-submit/task-wait -- one task per
;; processor, each covering a slice of the input with an ordinary
;; sequential loop -- which is also simply more efficient for this shape of
;; work. See kaappi-examples/parallel-primes for a worked chunking example.

(define-library (kaappi parallel)
  (import (scheme base) (srfi 1) (kaappi fibers))

  (cond-expand
    ((library (srfi 18)) (import (srfi 18)))
    (else))

  (export make-pool pool-submit task-wait pool-shutdown!
          parallel-map parallel-for-each processor-count)

  (begin
    (define-record-type %pool
      (%make-pool tasks workers) pool?
      (tasks %pool-tasks) (workers %pool-workers))

    ;; The worker loop is inlined directly into each spawned thunk below,
    ;; not factored into a shared named procedure called from within it.
    ;; A library-level procedure *called* (not just referenced) from inside
    ;; a closure that crosses thread-start!'s thread boundary hangs -- the
    ;; identical logic inlined into the thunk itself works correctly. Fully
    ;; inlining also matches the KEP-0002 §8 reference pseudocode, which
    ;; never factors this loop out.
    ;;
    ;; Parks on the tasks channel's notifier; closed => drain queue, then
    ;; exit on eof. A task's exception is caught here (not left to escape)
    ;; so one bad task can't kill this worker permanently -- without this,
    ;; an uncaught exception would unwind the loop, and pool-shutdown!'s
    ;; unconditional join would then raise instead of shutting down cleanly.
    (cond-expand
      ((library (srfi 18))
       (define (%spawn-worker tasks)
         (thread-start!
           (make-thread
             (lambda ()
               (let loop ((msg (channel-receive tasks)))
                 (unless (eof-object? msg)
                   (let ((thunk (car msg)) (reply (cdr msg)))
                     (channel-send reply
                       (guard (e (#t (cons 'error e)))
                         (cons 'ok (thunk)))))
                   (loop (channel-receive tasks))))))))
       (define (%join-worker w) (thread-join! w)))
      (else
       (define (%spawn-worker tasks)
         (spawn
           (lambda ()
             (let loop ((msg (channel-receive tasks)))
               (unless (eof-object? msg)
                 (let ((thunk (car msg)) (reply (cdr msg)))
                   (channel-send reply
                     (guard (e (#t (cons 'error e)))
                       (cons 'ok (thunk)))))
                 (loop (channel-receive tasks)))))))
       (define (%join-worker w) (fiber-join w))))

    (define (make-pool n)
      (if (not (and (integer? n) (exact? n) (> n 0)))
          (error "type error in 'make-pool': expected a positive exact integer, got" n))
      (let ((tasks (make-channel)))
        (%make-pool tasks (map (lambda (_) (%spawn-worker tasks)) (iota n)))))

    ;; Raises after shutdown (channel-send on a closed channel raises); the
    ;; reply channel is promoted on send and aliased in for the worker.
    (define (pool-submit pool thunk)
      (if (not (procedure? thunk))
          (error "type error in 'pool-submit': expected procedure, got" thunk))
      (let ((reply (make-channel)))
        (channel-send (%pool-tasks pool) (cons thunk reply))
        reply))

    (define (task-wait reply)
      (let ((r (channel-receive reply)))
        (if (eq? (car r) 'ok) (cdr r) (raise (cdr r)))))

    ;; Closing wakes every worker at once; each drains whatever is still
    ;; queued and exits on eof, so a submit racing this call still runs to
    ;; completion before any worker observes end-of-stream.
    (define (pool-shutdown! pool)
      (channel-close! (%pool-tasks pool))
      (for-each %join-worker (%pool-workers pool)))

    (define (%with-pool n proc)
      (let ((pool (make-pool n)))
        (dynamic-wind (lambda () #f)
                       (lambda () (proc pool))
                       (lambda () (pool-shutdown! pool)))))

    (define (parallel-map f lst)
      (if (not (procedure? f))
          (error "type error in 'parallel-map': expected procedure, got" f))
      (%with-pool (processor-count)
        (lambda (pool)
          (map task-wait
               (map (lambda (x) (pool-submit pool (lambda () (f x)))) lst)))))

    (define (parallel-for-each f lst)
      (if (not (procedure? f))
          (error "type error in 'parallel-for-each': expected procedure, got" f))
      (%with-pool (processor-count)
        (lambda (pool)
          (for-each task-wait
                     (map (lambda (x) (pool-submit pool (lambda () (f x)))) lst)))))))
