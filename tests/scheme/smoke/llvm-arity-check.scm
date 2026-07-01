;;; Regression test for issue #636: emitDirectCall must validate arity
;;; Native-compiled direct calls should raise arity errors, not silently
;;; compute wrong results or read out-of-bounds stack memory.

(import (scheme base) (scheme write))

(define (add2 a b) (+ a b))

;; Correct arity — should work
(let ((r (add2 10 20)))
  (unless (= r 30)
    (display "FAIL: add2 correct arity")
    (newline)
    (exit 1)))

;; Over-application — should raise error
(guard (exn
  (#t
   (unless (string-contains (error-object-message exn) "expected 2 arguments")
     (display "FAIL: over-application error message")
     (newline)
     (exit 1))))
  (add2 1 2 3)
  (display "FAIL: over-application did not error")
  (newline)
  (exit 1))

;; Under-application — should raise error
(guard (exn
  (#t
   (unless (string-contains (error-object-message exn) "expected 2 arguments")
     (display "FAIL: under-application error message")
     (newline)
     (exit 1))))
  (add2 1)
  (display "FAIL: under-application did not error")
  (newline)
  (exit 1))

(display "OK")
(newline)
