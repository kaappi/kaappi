;; Regression tests for #846 (exact/numerator/denominator abort on 2^63)
;; and #853 (string->number raises OutOfMemory for bignum rationals)

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "numeric-edge-846-853")

;; #846: exact of 2^63 must not panic
(test-equal "(exact 2.0^63) = 2^63" (expt 2 63) (exact (expt 2.0 63)))

;; #853: string->number with bignum rational components
(test-equal "bignum numerator over a fixnum denominator reduces"
            41152263004115226300411522630
            (string->number "123456789012345678901234567890/3"))
(test-assert "fixnum numerator over a bignum denominator is rational"
             (rational? (string->number "3/123456789012345678901234567890")))
(test-equal "string->number rejects \"bad/input\""
            #f (string->number "bad/input"))

(let ((runner (test-runner-current)))
  (test-end "numeric-edge-846-853")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
