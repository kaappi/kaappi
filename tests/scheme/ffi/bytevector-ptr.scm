;; Regression test for #232: ffi-bytevector-ptr must return a non-negative
;; integer (fixnum or bignum) for any data pointer address.

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

;; Empty bytevector returns 0
(check "empty-bv" (ffi-bytevector-ptr (bytevector)) 0)

;; Non-empty bytevector returns a positive integer
(let ((ptr (ffi-bytevector-ptr (bytevector 1 2 3))))
  (check "non-negative" (>= ptr 0) #t)
  (check "is-integer" (integer? ptr) #t)
  (check "is-exact" (exact? ptr) #t))

;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
