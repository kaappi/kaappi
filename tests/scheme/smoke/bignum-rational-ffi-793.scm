;; Regression test for #793: types.toF64 returns 0.0 for bignums,
;; causing bignum-backed rationals to marshal as 0.0 or +inf.0 in FFI.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "bignum-rational-ffi-793")

(define libm (ffi-open "libm"))
(define c-ceil (ffi-fn libm "ceil" '(double) 'double))

;; Fixnum-backed rational (sanity check — always worked)
(test-equal "fixnum rational via ffi" 4.0 (c-ceil 7/2))

;; Bignum numerator: (expt 10 20) / 3 ≈ 3.33e19
(define big-rat (/ (expt 10 20) 3))
(test-assert "big-rat is rational" (rational? big-rat))
(let ((result (c-ceil big-rat)))
  (test-assert "bignum numerator not zero" (> result 0.0))
  (test-assert "bignum numerator magnitude" (> result 3e19)))

;; Bignum denominator: 1 / (expt 10 20) ≈ 1e-20
(define small-rat (/ 1 (expt 10 20)))
(test-assert "small-rat is rational" (rational? small-rat))
(let ((result (c-ceil small-rat)))
  (test-assert "bignum denominator not inf" (finite? result))
  (test-equal "bignum denominator ceil" 1.0 result))

(ffi-close libm)

(let ((runner (test-runner-current)))
  (test-end "bignum-rational-ffi-793")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
