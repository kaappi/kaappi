;;; Regression test for issue #632: create-temp-file must give a descriptive
;;; error message when the prefix is too long, not a bare TypeError.

(import (scheme base) (scheme write) (srfi 170))

;; Over-long prefix should give descriptive error with irritants
(guard (exn
  (#t
   (unless (string-contains (error-object-message exn) "prefix too long")
     (display "FAIL: expected 'prefix too long' in message, got: ")
     (display (error-object-message exn))
     (newline)
     (exit 1))
   (when (null? (error-object-irritants exn))
     (display "FAIL: expected non-empty irritants")
     (newline)
     (exit 1))))
  (create-temp-file (make-string 250 #\a))
  (display "FAIL: should have raised error")
  (newline)
  (exit 1))

;; Normal prefix should work
(let ((path (create-temp-file "/tmp/kaappi-test-")))
  (unless (string? path)
    (display "FAIL: expected string path")
    (newline)
    (exit 1))
  (delete-file path))

(display "OK")
(newline)
