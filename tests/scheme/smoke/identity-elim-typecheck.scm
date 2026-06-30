;; Regression test for issue #498: identity elimination must preserve
;; type checks and IEEE signed-zero semantics.

(import (scheme base) (scheme write) (scheme process-context))

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

;; (+ non-number 0) must raise error, not return the non-number
(define g "hello")
(check-error "(+ string 0) must error"
  (lambda () (+ g 0)))

(check-error "(+ 0 string) must error"
  (lambda () (+ 0 g)))

(check-error "(* string 1) must error"
  (lambda () (* g 1)))

(check-error "(- string 0) must error"
  (lambda () (- g 0)))

;; Signed zero: (+ -0.0 0) must be +0.0
(define nz -0.0)
(check "(+ -0.0 0) = +0.0" (eqv? (+ nz 0) 0.0) #t)
(check "(+ -0.0 0) != -0.0" (eqv? (+ nz 0) -0.0) #f)

;; Valid identity cases still work
(check "(+ 5 0)" (+ 5 0) 5)
(check "(+ 0 5)" (+ 0 5) 5)
(check "(* 7 1)" (* 7 1) 7)
(check "(- 3 0)" (- 3 0) 3)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (exit 1))
