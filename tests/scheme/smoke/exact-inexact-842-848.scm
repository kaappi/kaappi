;; Regression tests for #842 and #848

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "exact-inexact-842-848")

;; #842: exact with dyadic denominator 2^47 must not produce negative denominator
(let ((x (exact (/ 3.0 (expt 2.0 47)))))
  (test-assert "(exact 3/2^47) is positive" (positive? x))
  (test-assert "(inexact (exact 3/2^47)) is positive" (> (inexact x) 0)))

;; #848: inexact on rationals with huge components must not return NaN
(test-equal "inexact of (10^400+1)/10^399"
            10.0 (inexact (/ (+ (expt 10 400) 1) (expt 10 399))))
(test-equal "inexact of (2^2000+1)/2^2000"
            1.0 (inexact (/ (+ (expt 2 2000) 1) (expt 2 2000))))

;; #2183: rational->flonum must be correct when a single side leaves f64
;; range while the quotient is representable -- the old toF64(num)/
;; toF64(den) collapsed to 0.0 (subnormal results), +inf (ordinary
;; integers), or nan (both overflow, on the parser paths).
(test-group "rational->flonum past f64 range on one side (#2183)"
  ;; Denominator alone overflows: the true value is the min subnormal.
  (test-assert "1/2^1074 is the min subnormal"
    (= (inexact (/ 1 (expt 2 1074))) 5e-324))
  (test-assert "1/2^1049 is the right subnormal"
    (= (inexact (/ 1 (expt 2 1049))) 1.6578092e-316))
  ;; exact->inexact round-trip no longer destroyed by the collapse.
  (test-assert "(inexact (exact 1e-320)) is 1e-320"
    (= (inexact (exact 1e-320)) 1e-320))
  ;; Numerator alone overflows: the true value is an ordinary integer.
  (test-assert "(2^1030+1)/2^1000 is 2^30"
    (= (inexact (/ (+ (expt 2 1030) 1) (expt 2 1000))) 1073741824.0))
  ;; Both overflow: string->number and read used to give nan.
  (test-assert "parser inf/inf is 2^50, not nan"
    (let ((s (string-append "#i" (number->string (+ (expt 2 1100) 1))
                            "/" (number->string (expt 2 1050)))))
      (and (= (string->number s) 1125899906842624.0)
           (= (read (open-input-string s)) 1125899906842624.0))))
  ;; Correct rounding at the subnormal tie: 1/2^1075 rounds to 0.0.
  (test-assert "1/2^1075 rounds to 0.0"
    (= (inexact (/ 1 (expt 2 1075))) 0.0))
  ;; Lopsided ratio keeps full mantissa precision (was off by 1-2 ulp).
  (test-assert "(10^400+1)/10^399 is exactly 10.0"
    (= (inexact (/ (+ (expt 10 400) 1) (expt 10 399))) 10.0))
  ;; Signs survive.
  (test-assert "negative subnormal"
    (= (inexact (/ -1 (expt 2 1074))) -5e-324)))

(let ((runner (test-runner-current)))
  (test-end "exact-inexact-842-848")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
