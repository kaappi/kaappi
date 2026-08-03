;; Regression test for #437:
;; toRationalParts must not treat bignums as zero.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "bignum-rational-arith")

;; (- bignum rational) should not return (- 0 rational)
(test-assert "(- 2^60 1/3) is large" (> (- (expt 2 60) 1/3) (expt 2 59)))

;; (/ bignum rational) should not return 0
(test-assert "(/ 2^60 1/3) is large" (> (/ (expt 2 60) 1/3) (expt 2 59)))

;; Sanity: (+ bignum rational) should still work
(test-assert "(+ 2^60 1/3) is large" (> (+ (expt 2 60) 1/3) (expt 2 59)))

;; Sanity: (* bignum rational) should still work
(test-assert "(* 2^60 1/3) is large" (> (* (expt 2 60) 1/3) (expt 2 58)))

(let ((runner (test-runner-current)))
  (test-end "bignum-rational-arith")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
