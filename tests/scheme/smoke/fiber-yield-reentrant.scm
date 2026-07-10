;; Regression test for #1184: an advisory (yield) executed under a
;; re-entrant native frame (e.g. the thunk of guard/with-exception-handler)
;; used to have its in-flight Yielded unwind converted into a contentless
;; "error" exception whenever another fiber was schedulable. Yield must be
;; a no-op in that context instead.
(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 18) (srfi 64))

(test-begin "fiber-yield-reentrant")

;; A spawned-but-never-dispatched fiber makes the scheduler report a
;; runnable candidate; it parks forever once dispatched.
(define parked (spawn (lambda () (channel-receive (make-channel)))))

;; #1184: yield inside guard must not surface a bogus caught error.
(test-equal "yield inside guard is a no-op, not an error"
  'yield-ok
  (guard (e (#t (list 'error-caught e)))
    (begin (yield) 'yield-ok)))

;; The same defect existed in SRFI-18 thread-yield!.
(test-equal "thread-yield! inside guard is a no-op, not an error"
  'yield-ok
  (guard (e (#t (list 'error-caught e)))
    (begin (thread-yield!) 'yield-ok)))

;; A bare top-level yield with runnable fibers must dispatch them and then
;; resume the main fiber: code after the yield still runs.
(define after-yield 'not-reached)
(begin (yield) (set! after-yield 'reached))
(test-equal "main fiber resumes after a bare top-level yield"
  'reached after-yield)

;; And once every other fiber is permanently parked, yield stays a no-op.
(test-equal "yield with only parked fibers is a no-op"
  'still-ok
  (guard (e (#t (list 'error-caught e)))
    (begin (yield) 'still-ok)))

(let ((runner (test-runner-current)))
  (test-end "fiber-yield-reentrant")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
