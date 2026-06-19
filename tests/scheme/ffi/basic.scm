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

(define (check-approx name got expected epsilon)
  (if (< (abs (- got expected)) epsilon)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected≈ ") (write expected)
        (display " got ") (write got)
        (newline))))

(define libm (ffi-open "libm"))
(define c-sqrt (ffi-fn libm "sqrt" '(double) 'double))
(define c-ceil (ffi-fn libm "ceil" '(double) 'double))
(define c-pow (ffi-fn libm "pow" '(double double) 'double))

(check-approx "sqrt(4.0)" (c-sqrt 4.0) 2.0 1e-12)
(check-approx "sqrt(2.0)" (c-sqrt 2.0) 1.4142135623730951 1e-12)
(check "ceil(3.2)" (c-ceil 3.2) 4.0)
(check "pow(2.0, 10.0)" (c-pow 2.0 10.0) 1024.0)

(ffi-close libm)
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI tests failed" fail))
