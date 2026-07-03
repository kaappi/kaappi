;; Regression test: (thread-yield!) from the main fiber at the top level
;; of a file.
;;
;; Bug 1: a top-level define whose body yields aborted with error.Yielded —
;; the scheduler is created lazily by spawn *during* the run, so run() had
;; already committed to the non-scheduler path when the yield surfaced.
;;
;; Bug 2: when the main fiber's form completed inside a nested scheduler
;; loop (a blocked fiber's native primitive resuming it via runUntil), the
;; top-level form's value was replaced by the spawned fiber's thunk result.

(import (scheme base)
        (scheme write)
        (kaappi fibers)
        (srfi 18))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " got=") (write got)
        (display " expected=") (write expected)
        (newline))))

;; Bug 1: top-level define with a yielding body. Without the fix this
;; aborts with error.Yielded and x is never defined.
(define x (let ((f (spawn (lambda () 12345))))
            (thread-yield!)
            (fiber-join f)
            99))

(check "define with yielding body" x 99)

;; Bug 2: the main fiber completes its form inside the nested scheduler
;; loop run by the spawned fiber's blocking mutex-lock!. The form's value
;; must be the main fiber's result (99), not the fiber's thunk result
;; (12345). Also checks that the main fiber finishing a top-level form
;; does not abandon the mutex it still holds.
(define m (make-mutex))
(define locked (mutex-lock! m))
(define f2 (spawn (lambda () (mutex-lock! m) (mutex-unlock! m) 12345)))
(define y (let () (thread-yield!) (mutex-unlock! m) 99))

(check "form value survives nested scheduler resume" y 99)
(check "fiber saw no abandoned mutex" (fiber-join f2) 12345)

;; Yield with no other runnable fiber must resume the main fiber.
(define z (let ((v 41)) (thread-yield!) (+ v 1)))
(check "yield with nothing to schedule resumes main" z 42)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (error "top-level yield tests failed" fail))
