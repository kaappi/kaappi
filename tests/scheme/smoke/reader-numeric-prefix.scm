;; Regression test for issue #79:
;; Malformed #-prefixed numeric literals must produce clean read errors,
;; not abort the interpreter.

(import (scheme base) (scheme read) (scheme write))

(define (read-from-string s)
  (read (open-input-string s)))

(define (read-errors? s)
  (guard (exn (#t #t))
    (read-from-string s)
    #f))

;; Bug A: #d / #e / #i at EOF must error, not OOB panic
(unless (read-errors? "#d")
  (display "FAIL: #d at EOF should error") (newline) (exit 1))
(unless (read-errors? "#i")
  (display "FAIL: #i at EOF should error") (newline) (exit 1))
(unless (read-errors? "#e#d")
  (display "FAIL: #e#d at EOF should error") (newline) (exit 1))

;; Bug B: #e of large flonum must not panic from intFromFloat overflow
(let ((v (read-from-string "#e1e19")))
  (unless (number? v)
    (display "FAIL: #e1e19 should produce a number") (newline) (exit 1)))
(let ((v (read-from-string "#e1e308")))
  (unless (number? v)
    (display "FAIL: #e1e308 should produce a number") (newline) (exit 1)))
(let ((v (read-from-string "#e9.5e18")))
  (unless (number? v)
    (display "FAIL: #e9.5e18 should produce a number") (newline) (exit 1)))

;; Valid #e cases still work
(unless (= (read-from-string "#e1.5") 3/2)
  (display "FAIL: #e1.5 should be 3/2") (newline) (exit 1))
(unless (= (read-from-string "#e42") 42)
  (display "FAIL: #e42 should be 42") (newline) (exit 1))

(display "OK")
(newline)
