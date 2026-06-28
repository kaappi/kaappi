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

;; Test that bignum integer arguments are correctly passed to C functions.
;; Previously, toFixnum extracted pointer bits from bignums instead of
;; the numeric value.

(define libc (ffi-open #f))
(define c-abs (ffi-fn libc "abs" '(int) 'int))
(define c-labs (ffi-fn libc "labs" '(long) 'long))

;; Fixnum args should still work
(check "abs fixnum positive" (c-abs 42) 42)
(check "abs fixnum negative" (c-abs -42) 42)
(check "abs fixnum zero" (c-abs 0) 0)

;; Bignum that fits in an int (> 2^47 but < 2^31 is impossible, so test
;; with large fixnum boundary values)
(check "labs large positive" (c-labs (expt 2 50)) (expt 2 50))
(check "labs large negative" (c-labs (- (expt 2 50))) (expt 2 50))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI bignum argument tests failed" fail))
