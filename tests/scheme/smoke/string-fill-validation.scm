;; Regression test for issue #74:
;; string-fill! must validate start/end arguments instead of panicking.

(import (scheme base) (scheme write))

(define (errors? thunk)
  (guard (exn (#t #t))
    (thunk)
    #f))

;; Valid uses
(let ((s (make-string 5 #\a)))
  (string-fill! s #\z)
  (unless (equal? s "zzzzz")
    (display "FAIL: basic fill") (newline) (exit 1)))

(let ((s (make-string 5 #\a)))
  (string-fill! s #\z 1 3)
  (unless (equal? s "azzaa")
    (display "FAIL: fill with start/end") (newline) (exit 1)))

;; start > end must error
(unless (errors? (lambda () (string-fill! (make-string 3 #\x) #\z 3 1)))
  (display "FAIL: start > end should error") (newline) (exit 1))

;; start/end > len must error
(unless (errors? (lambda () (string-fill! (make-string 3 #\x) #\z 5 10)))
  (display "FAIL: start > len should error") (newline) (exit 1))

;; Negative start must error
(unless (errors? (lambda () (string-fill! (make-string 3 #\x) #\z -1)))
  (display "FAIL: negative start should error") (newline) (exit 1))

;; Non-fixnum start must error
(unless (errors? (lambda () (string-fill! (make-string 3 #\x) #\z "no")))
  (display "FAIL: non-fixnum start should error") (newline) (exit 1))

(display "OK")
(newline)
