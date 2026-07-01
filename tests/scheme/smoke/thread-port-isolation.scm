;;; Regression test for issue #635: VM.initForThread must allocate fresh
;;; Port objects for stdin/stdout/stderr instead of sharing parent's.

(import (scheme base) (scheme write) (srfi 18))

(define (worker n)
  (lambda ()
    (let loop ((i 0))
      (when (< i 500)
        (display "")
        (loop (+ i 1))))
    n))

(define t1 (thread-start! (make-thread (worker 1))))
(define t2 (thread-start! (make-thread (worker 2))))

(define r1 (thread-join! t1))
(define r2 (thread-join! t2))

(unless (and (= r1 1) (= r2 2))
  (display "FAIL: expected 1 and 2, got ")
  (display r1) (display " ") (display r2)
  (newline)
  (exit 1))

(display "OK")
(newline)
