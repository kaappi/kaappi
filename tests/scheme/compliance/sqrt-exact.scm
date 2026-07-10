;; Regression tests for #1412: sqrt returns exact results for exact
;; rational and bignum perfect squares (R7RS 6.2.6 encourages returning
;; an exact result when the argument is exact and the root is exactly
;; representable).
(import (scheme base) (scheme complex) (scheme inexact)
        (scheme write) (scheme process-context) (srfi 64))

(test-begin "sqrt-exact")

;; Exact integer perfect squares (pre-existing behavior)
(test-equal "(sqrt 4)" 2 (sqrt 4))
(test-assert "(sqrt 4) exact" (exact? (sqrt 4)))
(test-equal "(sqrt 0)" 0 (sqrt 0))

;; Exact rational perfect squares -> exact rationals
(test-equal "(sqrt 9/4)" 3/2 (sqrt 9/4))
(test-assert "(sqrt 9/4) exact" (exact? (sqrt 9/4)))
(test-equal "(sqrt 1/4)" 1/2 (sqrt 1/4))
(test-equal "(sqrt 16/9)" 4/3 (sqrt 16/9))
(test-equal "(sqrt 100/49)" 10/7 (sqrt 100/49))

;; Bignum perfect squares -> exact integer roots
(define big 12345678901234567)  ; > 2^47, so (* big big) is a bignum
(test-equal "bignum perfect square" big (sqrt (* big big)))
(test-assert "bignum sqrt exact" (exact? (sqrt (* big big))))

;; Rationals with bignum components
(test-equal "bignum numerator" (/ big 2) (sqrt (/ (* big big) 4)))
(test-equal "bignum denominator" (/ 3 big) (sqrt (/ 9 (* big big))))

;; Non-perfect squares stay inexact
(test-assert "(sqrt 2) inexact" (inexact? (sqrt 2)))
(test-assert "(sqrt 2/3) inexact" (inexact? (sqrt 2/3)))
(test-assert "(sqrt 9/2) inexact" (inexact? (sqrt 9/2)))   ; num square, den not
(test-assert "(sqrt 2/9) inexact" (inexact? (sqrt 2/9)))   ; den square, num not
(test-assert "bignum non-square inexact" (inexact? (sqrt (* big big big))))
(test-approximate "(sqrt 9/2) value" 2.1213203435596424 (sqrt 9/2) 1e-9)

;; Inexact arguments keep returning inexact results
(test-assert "(sqrt 4.0) inexact" (inexact? (sqrt 4.0)))
(test-equal "(sqrt 4.0)" 2.0 (sqrt 4.0))

;; Negative exact rational -> complex (inexact) result, not an error
(test-approximate "(sqrt -9/4) imag" 1.5 (imag-part (sqrt -9/4)) 1e-9)
(test-approximate "(sqrt -9/4) real" 0.0 (real-part (sqrt -9/4)) 1e-9)

;; exact-integer-sqrt still works through the shared helper
(test-equal "(exact-integer-sqrt 17)" '(4 1)
  (call-with-values (lambda () (exact-integer-sqrt 17)) list))
(test-equal "(exact-integer-sqrt 0)" '(0 0)
  (call-with-values (lambda () (exact-integer-sqrt 0)) list))
(test-equal "exact-integer-sqrt bignum" (list big 0)
  (call-with-values (lambda () (exact-integer-sqrt (* big big))) list))
(test-equal "exact-integer-sqrt bignum remainder" (list big 1)
  (call-with-values (lambda () (exact-integer-sqrt (+ (* big big) 1))) list))
(test-assert "exact-integer-sqrt negative raises"
  (guard (e (#t #t)) (exact-integer-sqrt -5) #f))

(let ((runner (test-runner-current)))
  (test-end "sqrt-exact")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
