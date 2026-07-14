(define-library (lib1479 spawner)
  (export run-in-thread run-in-thread/guarded)
  (import (scheme base) (srfi 18) (lib1479 worker))
  (begin
    ;; run-in-thread is defined INSIDE this library body; its thread thunk
    ;; calls do-work, exported from the *other* library (lib1479 worker).
    (define (run-in-thread x)
      (let ((t (make-thread (lambda () (do-work x)))))
        (thread-start! t)
        (thread-join! t)))
    ;; Same shape as kaappi-http's http-listen-threaded: the thunk wraps the
    ;; cross-library call in a guard. Before the fix, the undefined-variable
    ;; error was caught here and swallowed (a silent hang for an HTTP client).
    (define (run-in-thread/guarded x)
      (let ((t (make-thread
                 (lambda ()
                   (guard (e (#t (list 'swallowed-error x)))
                     (do-work x))))))
        (thread-start! t)
        (thread-join! t)))))
