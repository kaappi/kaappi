(import (scheme base) (scheme write))

;; Regression test for #222: ffi-close leaves dangling symbol pointers.
;; Calling an FFI function after its library is closed must raise an error,
;; not crash via dangling pointer.

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

;; libm on POSIX; on Windows the CRT (ucrtbase.dll) hosts the math
;; functions — there is no libm.dll.
(define libm (ffi-open (cond-expand (windows "ucrtbase") (else "libm"))))
(define c-sqrt (ffi-fn libm "sqrt" '(double) 'double))

;; Verify the function works before close
(check "sqrt before close" (< (abs (- (c-sqrt 4.0) 2.0)) 1e-12) #t)

;; Close the library
(ffi-close libm)

;; Calling c-sqrt after close must raise an error
(check "use-after-close raises error"
  (guard (exn (#t 'caught))
    (c-sqrt 4.0)
    'no-error)
  'caught)

;; Double close should be safe (no-op)
(ffi-close libm)
(check "double close is safe" #t #t)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI use-after-close tests failed" fail))
