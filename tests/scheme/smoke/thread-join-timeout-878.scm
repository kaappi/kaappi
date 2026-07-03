;; Regression tests for #878: thread-join! must honour timeout/timeout-val
;; for OS threads and never-started threads.
;;
;; Uses thread-sleep! (nanosleep) instead of busy-loops so timing is
;; constant regardless of build mode (Debug vs ReleaseSafe).

(import (scheme base) (scheme write) (srfi 18))

(define pass 0)

(define (check name ok?)
  (if ok?
      (begin (set! pass (+ pass 1))
             (display "  PASS  ") (display name) (newline))
      (begin (display "  FAIL  ") (display name) (newline)
             (exit 1))))

;; Helper: spawn a thread that sleeps ~1s then returns 'done.
(define (spawn-slow)
  (thread-start!
   (make-thread
    (lambda ()
      (thread-sleep! 1)
      'done))))

;; 1. OS thread with timeout-val: must return 'timed-out quickly
(display "--- thread-join! timeout (OS thread, timeout-val) ---") (newline)
(let* ((t (spawn-slow))
       (r (thread-join! t 0.05 'timed-out)))
  (check "returns timeout-val" (eq? r 'timed-out))
  (thread-join! t))

;; 2. OS thread with timeout but no timeout-val: must raise join-timeout-exception
(display "--- thread-join! timeout (OS thread, no timeout-val) ---") (newline)
(let* ((t (spawn-slow))
       (got-exception #f))
  (guard (e ((join-timeout-exception? e)
             (set! got-exception #t)))
    (thread-join! t 0.05))
  (check "raises join-timeout-exception" got-exception)
  (thread-join! t))

;; 3. OS thread with no timeout: still blocks until completion
(display "--- thread-join! no timeout (OS thread) ---") (newline)
(let* ((t (spawn-slow))
       (r (thread-join! t)))
  (check "returns thread result" (eq? r 'done)))

;; 4. Never-started thread with timeout-val: must return timeout-val
(display "--- thread-join! timeout (never-started, timeout-val) ---") (newline)
(let* ((t (make-thread (lambda () 42)))
       (r (thread-join! t 0.05 'timed-out)))
  (check "returns timeout-val" (eq? r 'timed-out)))

;; 5. Never-started thread with timeout, no timeout-val: raises
(display "--- thread-join! timeout (never-started, no timeout-val) ---") (newline)
(let* ((t (make-thread (lambda () 42)))
       (got-exception #f))
  (guard (e ((join-timeout-exception? e)
             (set! got-exception #t)))
    (thread-join! t 0.05))
  (check "raises join-timeout-exception" got-exception))

;; 6. Zero timeout = immediate check (thread still running)
(display "--- thread-join! zero timeout ---") (newline)
(let* ((t (spawn-slow))
       (r (thread-join! t 0 'not-done)))
  (check "zero timeout returns timeout-val immediately" (eq? r 'not-done))
  (thread-join! t))

;; 7. Re-join after timeout returns the actual result
(display "--- thread-join! re-join after timeout ---") (newline)
(let* ((t (spawn-slow))
       (r1 (thread-join! t 0.05 'timed-out))
       (r2 (thread-join! t)))
  (check "first join returns timeout-val" (eq? r1 'timed-out))
  (check "second join returns thread result" (eq? r2 'done)))

(display pass) (display "/8 tests passed") (newline)
