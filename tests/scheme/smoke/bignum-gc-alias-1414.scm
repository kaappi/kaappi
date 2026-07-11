;; Regression test for #1414: bignum/bignum division returned 1 and
;; same-magnitude bignum subtraction returned 0 under -Dgc-stress=true.
;; The rational accumulation loops in +, -, *, / left a freshly allocated
;; product unrooted while computing the next one; the collection triggered
;; by that second multiplication freed the first, whose memory the second
;; then reused — numerator and denominator became the same object.
;; On a normal build the window only opens when a threshold collection
;; lands mid-loop; a gc-stress build makes these checks decisive.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "bignum-gc-alias-1414")

;; 2^50 / 2^48 = 4
(test-equal 4 (/ 1125899906842624 281474976710656))
;; 2^48 / 2^50 = 1/4
(test-equal 1/4 (/ 281474976710656 1125899906842624))
;; (3 * 2^48) / 2^50 = 3/4
(test-equal 3/4 (/ (* 3 281474976710656) 1125899906842624))
;; 2^50 - 2^48 = 3 * 2^48 (aliased operands made this 0)
(test-equal 844424930131968 (- 1125899906842624 281474976710656))
;; 2^49 + 2^49 = 2^50 through the same accumulation path
(test-equal 1125899906842624 (+ 562949953421312 562949953421312))
;; Rational arithmetic mixing bignum numerators/denominators
(test-equal 1/2 (/ 562949953421312 1125899906842624))
(test-assert (= (* 281474976710656 4) 1125899906842624))

(let ((runner (test-runner-current)))
  (test-end "bignum-gc-alias-1414")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
