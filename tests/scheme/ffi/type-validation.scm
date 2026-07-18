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

;; sqrt lives in libm on POSIX; on Windows the CRT (ucrtbase.dll) hosts the
;; math functions — there is no libm.dll. abs is a libc function, resolved
;; from the process's own libc (the null/default handle) on POSIX — dlsym on
;; an OpenBSD libm handle does not find it — and from ucrtbase on Windows.
(define libm (ffi-open (cond-expand (windows "ucrtbase") (else "libm"))))
(define abs-lib (ffi-open (cond-expand (windows "ucrtbase") (else #f))))
(define c-sqrt (ffi-fn libm "sqrt" '(double) 'double))
(define c-abs (ffi-fn abs-lib "abs" '(int) 'int))

;; --- Valid calls still work ---
(let ((r (c-sqrt 4.0)))
  (check "sqrt(4.0) valid" (and (> r 1.99) (< r 2.01)) #t))

;; --- Type errors: passing wrong types to FFI ---
(check-error "string where double expected"
  (lambda () (c-sqrt "hello")))

(check-error "boolean where double expected"
  (lambda () (c-sqrt #t)))

(check-error "list where double expected"
  (lambda () (c-sqrt '(1 2 3))))

(check-error "string where int expected"
  (lambda () (c-abs "hello")))

(check-error "boolean where int expected"
  (lambda () (c-abs #t)))

(check-error "vector where int expected"
  (lambda () (c-abs (vector 1 2 3))))

(check-error "pair where int expected"
  (lambda () (c-abs (cons 1 2))))

;; Fixnum passed to double should work (auto-coercion)
(let ((r (c-sqrt 4)))
  (check "fixnum->double coercion" (and (> r 1.99) (< r 2.01)) #t))

(ffi-close libm)
(ffi-close abs-lib)
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI type validation tests failed" fail))
