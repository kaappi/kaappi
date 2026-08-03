;; Regression tests for #e/#i exactness prefix handling
;; Issue #296

(import (scheme base) (scheme complex) (scheme inexact)
        (scheme write) (scheme process-context) (srfi 64))

(test-begin "exactness-prefix")

;; #e on complex numbers
(test-assert "#e1+2i has exact components"
             (exact? (make-rectangular (real-part #e1+2i) (imag-part #e1+2i))))
(test-assert "(real-part #e1+2i) is 1" (= (real-part #e1+2i) 1))
(test-assert "(imag-part #e1+2i) is 2" (= (imag-part #e1+2i) 2))

;; #i on large integers (bignums)
(test-assert "#i on a bignum is inexact" (inexact? #i99999999999999999999999999999))
(test-assert "#i on a bignum is a number" (number? #i99999999999999999999999999999))

;; #e on flonum still works
(test-assert "#e1.5 is exact" (exact? #e1.5))
(test-assert "#e1.5 = 3/2" (= #e1.5 3/2))

;; #i on fixnum still works
(test-assert "#i42 is inexact" (inexact? #i42))

(let ((runner (test-runner-current)))
  (test-end "exactness-prefix")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
