;; Regression test for #643: thread-join! on (current-thread) must
;; signal an error, not silently return void.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18))

(guard (exn
        ((error-object? exn)
         (display "PASS")
         (newline)))
  (thread-join! (current-thread))
  (display "FAIL: no error raised")
  (newline)
  (exit 1))
