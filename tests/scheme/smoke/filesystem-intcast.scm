(import (scheme base) (scheme write) (srfi 170))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-error name thunk)
  (guard (exn (#t (set! pass (+ pass 1))))
    (thunk)
    (set! fail (+ fail 1))
    (display "FAIL: ") (display name) (display " did not raise error") (newline)))

(define test-file "/tmp/kaappi-intcast-test.txt")
(call-with-output-file test-file (lambda (p) (write-char #\x p)))

;; set-file-mode with negative value should raise error, not crash
(check-error "set-file-mode negative"
  (lambda () (set-file-mode test-file -1)))

;; set-file-mode with value larger than u16 max should raise error
(check-error "set-file-mode too large"
  (lambda () (set-file-mode test-file 100000)))

;; set-file-mode with valid value should work
(set-file-mode test-file #o644)
(check "set-file-mode valid" #t #t)

;; set-umask! with negative value should raise error
(check-error "set-umask! negative"
  (lambda () (set-umask! -1)))

;; set-umask! with value too large should raise error
(check-error "set-umask! too large"
  (lambda () (set-umask! 100000)))

;; set-umask! with valid value should work
(let ((old (umask)))
  (set-umask! #o022)
  (let ((cur (umask)))
    (set-umask! old)
    (check "set-umask! valid" cur #o022)))

;; create-directory with negative mode should raise error
(check-error "create-directory negative mode"
  (lambda () (create-directory "/tmp/kaappi-intcast-dir" -1)))

;; Regression test for #800: nice with an out-of-range integer must raise a
;; recoverable Scheme error instead of panicking the interpreter (SIGABRT).
;; The delta is cast to a C int, so values outside i32 range are rejected.
(check-error "nice too large"
  (lambda () (nice 4294967296)))

(check-error "nice negative out of range"
  (lambda () (nice -2147483649)))

;; nice with a valid in-range delta must still return an integer.
(check "nice valid" (integer? (nice 0)) #t)

;; Clean up
(delete-file test-file)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "filesystem intcast tests failed" fail))
