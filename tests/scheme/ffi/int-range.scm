;; Regression test for issue #513: FFI integer args out of range
;; for the C parameter type should raise an error, not crash.

(import (scheme base) (scheme write))

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
    (display "FAIL: ") (display name) (display " should have raised error")
    (newline)))

;; abs is a libc function: resolve it from the process's own libc (the
;; null/default handle) on POSIX — dlsym on an OpenBSD libm handle does not
;; find abs — and from the CRT (ucrtbase.dll) on Windows, which has no
;; libm.dll.
(define abs-lib (ffi-open (cond-expand (windows "ucrtbase") (else #f))))
(define c-abs (ffi-fn abs-lib "abs" '(int) 'int))

;; Valid in-range call
(check "abs(-42)" (c-abs -42) 42)

;; 5 billion exceeds c_int (i32) range — must error, not crash
(check-error "abs(5000000000) out of c_int range"
  (lambda () (c-abs 5000000000)))

;; Negative out of range
(check-error "abs(-5000000000) out of c_int range"
  (lambda () (c-abs -5000000000)))

(ffi-close abs-lib)
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI int-range tests failed" fail))
