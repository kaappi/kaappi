;; Regression test for #796: FFI `bool` parameters must coerce their argument
;; to exactly 0/1 before it reaches the C _Bool parameter. Passing a raw integer
;; like 2 into a _Bool is undefined behavior (and aborts UBSan-instrumented
;; libraries built with `zig cc`).
;;
;; We declare libc `abs` (really `int abs(int)`) with a `bool` parameter. The
;; marshaler coerces the Scheme argument to 0/1 and loads it into the trampoline;
;; `abs` then simply returns that 0 or 1. Before the fix, the raw argument was
;; passed through: (abs-bool 2) returned 2 and (abs-bool -5) returned 5.

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

(define libc (ffi-open #f))
;; abs is int abs(int); we lie about the parameter type to exercise bool marshaling.
(define abs-bool (ffi-fn libc "abs" '(bool) 'int))

(check "bool arg 2 coerces to 1"   (abs-bool 2)  1)
(check "bool arg -5 coerces to 1"  (abs-bool -5) 1)
(check "bool arg 1 stays 1"        (abs-bool 1)  1)
(check "bool arg 0 stays 0"        (abs-bool 0)  0)
(check "bool arg #t is 1"          (abs-bool #t) 1)
(check "bool arg #f is 0"          (abs-bool #f) 0)
;; A bignum-range flag is still just truthy -> 1.
(check "bool arg bignum coerces to 1" (abs-bool 4294967296) 1)

;; bool return type still normalizes any nonzero to #t.
(define abs-ret-bool (ffi-fn libc "abs" '(bool) 'bool))
(check "bool return of true is #t"  (abs-ret-bool 2) #t)
(check "bool return of false is #f" (abs-ret-bool 0) #f)

(ffi-close libc)
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI bool coercion tests failed" fail))
