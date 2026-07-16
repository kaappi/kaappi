;;; Regression test for issue #630: toCString must reject strings with
;;; embedded NUL bytes instead of silently truncating them.

(import (scheme base) (scheme write))

;; self-dlopen does not expose libc on Windows — skip there.
(cond-expand
  (windows (display "skipped on windows\n") (exit 0))
  (else #f))

(define libc (ffi-open #f))
(define c-strlen (ffi-fn libc "strlen" '(string) 'long))

;; String with embedded NUL should raise error
(guard (exn
  (#t
   (unless (error-object? exn)
     (display "FAIL: expected error object")
     (newline)
     (exit 1))))
  (c-strlen (string #\a #\b #\c #\null #\d #\e #\f))
  (display "FAIL: should have raised error for embedded NUL")
  (newline)
  (exit 1))

;; Normal strings should still work
(unless (= (c-strlen "hello") 5)
  (display "FAIL: strlen of normal string")
  (newline)
  (exit 1))

;; Empty string should work
(unless (= (c-strlen "") 0)
  (display "FAIL: strlen of empty string")
  (newline)
  (exit 1))

(ffi-close libc)
(display "OK")
(newline)
