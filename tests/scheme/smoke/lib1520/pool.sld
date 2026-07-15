(define-library (lib1520 pool)
  (export run-pool/helper run-pool/inlined)
  (import (scheme base) (srfi 18) (kaappi fibers))
  (begin
    ;; worker-loop is a SEPARATELY-defined library top-level procedure. The
    ;; #1520 bug: spawn-worker/helper's thread thunk *calls* it after crossing
    ;; thread-start!. Deep-copying the thunk to the child OS thread used to
    ;; drop the closure's lib_env (gc_deep_copy.zig set new_func.env = null),
    ;; so the child couldn't resolve worker-loop, died silently, and the
    ;; parent parked on (channel-receive reply) forever -- a pure hang, no
    ;; error. Fixed in #1526 (new_func.env = func.env), same root cause as
    ;; #1479's cross-library variant.
    (define (worker-loop tasks)
      (let loop ((msg (channel-receive tasks)))
        (unless (eof-object? msg)
          (let ((thunk (car msg)) (reply (cdr msg)))
            (channel-send reply (thunk)))
          (loop (channel-receive tasks)))))

    ;; HELPER form: the thunk calls the separately-named worker-loop. Hung
    ;; before #1526.
    (define (spawn-worker/helper tasks)
      (thread-start! (make-thread (lambda () (worker-loop tasks)))))

    ;; INLINED form: the identical loop body, inlined into the thunk. The
    ;; issue's contrast case -- this always worked, even before the fix.
    (define (spawn-worker/inlined tasks)
      (thread-start!
        (make-thread
          (lambda ()
            (let loop ((msg (channel-receive tasks)))
              (unless (eof-object? msg)
                (let ((thunk (car msg)) (reply (cdr msg)))
                  (channel-send reply (thunk)))
                (loop (channel-receive tasks))))))))

    ;; Drive one task through a freshly spawned worker, then shut it down
    ;; deterministically (channel-close! ends the stream -- worker-loop's
    ;; (eof-object? msg) guard sees the resulting eof -- then join) so the
    ;; test never leaks a parked thread. `tasks` is a proper lexical channel
    ;; throughout -- not a shared global -- so this is not the KEP-0002 Path 2
    ;; case.
    (define (drive spawn)
      (let ((tasks (make-channel))
            (reply (make-channel)))
        (let ((worker (spawn tasks)))
          (channel-send tasks (cons (lambda () (* 6 7)) reply))
          (let ((result (channel-receive reply)))
            (channel-close! tasks)
            (thread-join! worker)
            result))))

    (define (run-pool/helper) (drive spawn-worker/helper))
    (define (run-pool/inlined) (drive spawn-worker/inlined))))
