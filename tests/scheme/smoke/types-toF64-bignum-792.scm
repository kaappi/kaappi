;; Regression test for #792: types.toF64 missing bignum case
;; Bignum-backed rationals passed as FFI double args marshaled as
;; 0.0 (bignum numerator) or +inf.0 (bignum denominator).
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "types-toF64-bignum-792")

;; Direct bignum → inexact conversion (exercises the same toF64 path)
(test-assert "bignum to inexact is finite"
  (finite? (inexact (expt 10 20))))

(test-assert "bignum-numerator rational to inexact"
  (> (inexact (/ (expt 10 20) 3)) 3e19))

(test-assert "bignum-denominator rational to inexact"
  (< (inexact (/ 1 (expt 10 20))) 1e-19))

(test-assert "bignum-denominator rational is not +inf.0"
  (finite? (inexact (/ 1 (expt 10 20)))))

(let ((runner (test-runner-current)))
  (test-end "types-toF64-bignum-792")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
