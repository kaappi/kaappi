;; Regression test for #838 and #839: rational ops with bignum operands
;; must process all arguments, not return early after the first bignum.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "rational-bignum-838-839")

(define big (expt 2 100))

;; #838: remaining args not dropped
(test-assert "(+ big 1/2)" (= (+ big 1/2) (/ (+ (* big 2) 1) 2)))
(test-assert "(+ 1/2 big 10)" (= (+ 1/2 big 10) (/ (+ (* big 2) 21) 2)))
(test-assert "(* big 1/2)" (= (* big 1/2) (expt 2 99)))
(test-assert "(* 1/2 big 10)" (= (* 1/2 big 10) (* 5 big)))

;; #839: bignum-first argument path
(test-assert "(- big 1/2)" (= (- big 1/2) (/ (- (* big 2) 1) 2)))
(test-assert "(/ big 2)" (= (/ big 2) (expt 2 99)))

(let ((runner (test-runner-current)))
  (test-end "rational-bignum-838-839")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
