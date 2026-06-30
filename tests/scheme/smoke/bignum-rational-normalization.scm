;; Regression test for #517/#515: makeRationalReduced must normalize sign
;; and reduce by GCD for bignum-component rationals. positive?/negative?
;; must handle bignum numerators in rationals.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "bignum-rational-normalization")

;; (-2/3)^-41 = -(3^41)/(2^41) — negative
(test-assert "negative? on bignum rational"
  (negative? (expt (/ -2 3) -41)))

(test-assert "not positive? on negative bignum rational"
  (not (positive? (expt (/ -2 3) -41))))

;; (2/3)^-41 = (3^41)/(2^41) — positive
(test-assert "positive? on positive bignum rational"
  (positive? (expt (/ 2 3) -41)))

(test-assert "not negative? on positive bignum rational"
  (not (negative? (expt (/ 2 3) -41))))

;; abs of negative bignum rational
(test-assert "abs of negative bignum rational is positive"
  (positive? (abs (expt (/ -2 3) -41))))

;; Denominator must be positive after normalization
(test-assert "denominator of bignum rational is positive"
  (positive? (denominator (expt (/ -2 3) -41))))

;; Denominator normalization through expt with negative exponent
;; (expt -2/3 -2) = 9/4, check it's properly reduced and positive
(let ((r (expt (/ -2 3) -2)))
  (test-equal "(-2/3)^-2 numerator" 9 (numerator r))
  (test-equal "(-2/3)^-2 denominator" 4 (denominator r)))

(let ((runner (test-runner-current)))
  (test-end "bignum-rational-normalization")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
