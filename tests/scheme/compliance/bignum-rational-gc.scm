;;; Regression tests for #1414: bignum/bignum arithmetic returned wrong
;;; results when a GC ran between accumulator updates in the rational
;;; paths of +, -, *, / (visible under -Dgc-stress=true builds, where the
;;; unrooted intermediate was collected and its memory reused, aliasing
;;; the operands: / and * collapsed to 1, + doubled one operand, - gave 0).

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "bignum-rational-gc")

;; 2^50 and 2^48: both exceed the ±2^47 fixnum range, so both are bignums.
(define big-a 1125899906842624)
(define big-b 281474976710656)

(test-group "bignum/bignum division (#1414)"
  (test-eqv "2^50 / 2^48" 4 (/ big-a big-b))
  (test-eqv "2^50 / 2^50" 1 (/ big-a big-a))
  (test-eqv "2^48 / 2^50 is exact 1/4" 1/4 (/ big-b big-a))
  (test-eqv "multi-limb product / bignum"
            1000000007
            (/ (* 1234567890123456789 1000000007) 1234567890123456789)))

(test-group "bignum/bignum addition and subtraction"
  (test-eqv "2^50 + 2^48" 1407374883553280 (+ big-a big-b))
  (test-eqv "2^50 - 2^48" 844424930131968 (- big-a big-b))
  (test-eqv "unary minus bignum" -1125899906842624 (- big-a)))

(test-group "bignum multiplication with rationals"
  (test-eqv "2^50 * 2^48" 316912650057057350374175801344 (* big-a big-b))
  (test-eqv "2^50 * 1/2^48" 4 (* big-a (/ 1 big-b)))
  (test-eqv "rational add with bignum denominators"
            (/ 5 big-a)
            (+ (/ 1 big-a) (/ 1 big-b))))

;; string->number's rational parse holds the numerator bignum across the
;; denominator parse — the same unrooted-intermediate hazard as above.
(test-group "string->number bignum rationals"
  (test-eqv "bignum/bignum parts fitting i64"
            4 (string->number "1125899906842624/281474976710656"))
  (test-eqv "parts overflowing i64 (2^65/2^64)"
            2 (string->number "36893488147419103232/18446744073709551616"))
  (test-eqv "negative bignum numerator"
            -4 (string->number "-1125899906842624/281474976710656"))
  (test-eqv "fixnum/bignum stays exact"
            (/ 1 big-b) (string->number "1/281474976710656")))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "bignum-rational-gc")
(if (> %test-fail-count 0) (exit 1))
