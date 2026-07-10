(import (scheme base) (scheme write) (scheme inexact) (scheme complex))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_arithmetic audit")

;;; ================================================================
;;; Bug 1: min/max must work on rationals
;;; ================================================================
(test-equal 1/3 (min 1/3 1/2))
(test-equal 1/2 (max 1/3 1/2))
(test-equal 1/4 (min 1 1/2 1/4 3/4))
(test-equal 1 (max 1 1/2 1/4 3/4))
;; Mixed rational + fixnum
(test-equal 1/3 (min 1 1/3))
(test-equal 1 (max 1/3 1))
;; Mixed rational + flonum (result is inexact)
(test-equal #t (< (min 1/3 0.25) 0.26))
(test-equal #t (> (max 1/3 0.5) 0.49))

;;; ================================================================
;;; Bug 2: quotient must accept integer-valued flonums
;;; ================================================================
(test-equal #t (= 3.0 (quotient 10.0 3.0)))
(test-equal #t (= 3.0 (quotient 10.0 3)))
(test-equal #t (= -3.0 (quotient -10.0 3.0)))
;; modulo on flonums
(test-equal #t (= 1.0 (modulo 10.0 3.0)))
(test-equal #t (= 2.0 (modulo -10.0 3.0)))

;;; ================================================================
;;; Bug 3: gcd must accept integer-valued flonums
;;; ================================================================
(test-equal #t (= 2.0 (gcd 4.0 6.0)))
(test-equal #t (= 3.0 (gcd 6.0 9.0)))
(test-equal #t (= 4.0 (gcd 4.0)))
;; gcd with mixed fixnum + flonum
(test-equal #t (= 2.0 (gcd 4 6.0)))

;;; ================================================================
;;; Bug 439: gcd must not crash on inexact args outside i64 range
;;; ================================================================
(test-equal #t (number? (gcd +nan.0 1.0)))
(test-equal #t (number? (gcd +inf.0 6.0)))
(test-equal #t (= 1e100 (gcd 1e100 0.0)))
(test-equal #t (= 2.0 (gcd 1e100 2.0)))

;;; ================================================================
;;; Bug 5: lcm should not overflow — large values
;;; (lcm on large values should promote to bignum, not panic)
;;; ================================================================
(test-equal #t (integer? (lcm (expt 2 40) (expt 2 41))))
(test-equal (expt 2 41) (lcm (expt 2 40) (expt 2 41)))

;;; ================================================================
;;; Standard correctness checks for all types
;;; ================================================================

;; + with all types
(test-equal 3 (+ 1 2))
(test-equal #t (= 3.5 (+ 1 2.5)))
(test-equal 5/6 (+ 1/3 1/2))
(test-equal 3+4i (+ 1+2i 2+2i))
(test-equal #t (> (+ (expt 2 100) 1) (expt 2 100)))

;; - with all types
(test-equal -1 (- 1 2))
(test-equal #t (= -1.5 (- 1 2.5)))
(test-equal 1/6 (- 1/2 1/3))
(test-equal #t (= 1 (- 3+2i 2+2i)))
(test-equal 0 (- (expt 2 100) (expt 2 100)))

;; * with all types
(test-equal 6 (* 2 3))
(test-equal #t (= 6.0 (* 2 3.0)))
(test-equal 1/6 (* 1/2 1/3))
(test-equal -5+10i (* 1+2i 3+4i))

;; / with all types
(test-equal 1/2 (/ 1 2))
(test-equal #t (= 0.5 (/ 1 2.0)))
(test-equal 3/2 (/ 3/4 1/2))

;; zero? on all types
(test-equal #t (zero? 0))
(test-equal #t (zero? 0.0))
(test-equal #t (zero? 0+0i))
(test-equal #f (zero? 1/3))
(test-equal #f (zero? (expt 2 100)))

;; positive?/negative? on all types
(test-equal #t (positive? 1))
(test-equal #t (positive? 0.5))
(test-equal #t (positive? 1/3))
(test-equal #t (positive? (expt 2 100)))
(test-equal #f (positive? -1))
(test-equal #f (positive? -0.5))
(test-equal #f (positive? -1/3))

(test-equal #t (negative? -1))
(test-equal #t (negative? -0.5))
(test-equal #t (negative? -1/3))
(test-equal #f (negative? 1))
(test-equal #f (negative? (expt 2 100)))

;; abs on all types
(test-equal 5 (abs -5))
(test-equal 5 (abs 5))
(test-equal #t (= 3.0 (abs -3.0)))
(test-equal 1/3 (abs -1/3))
(test-equal 1/3 (abs 1/3))
(test-equal (expt 2 100) (abs (- (expt 2 100))))

;; even?/odd? on all types
(test-equal #t (even? 4))
(test-equal #f (even? 3))
(test-equal #t (even? 4.0))
(test-equal #f (even? 3.0))
(test-equal #t (even? (expt 2 100)))
(test-equal #t (odd? (+ (expt 2 100) 1)))

;; gcd/lcm basics
(test-equal 0 (gcd))
(test-equal 1 (lcm))
(test-equal 5 (gcd 5))
(test-equal 5 (lcm 5))
(test-equal 4 (gcd 12 8))
(test-equal 24 (lcm 12 8))
(test-equal 4 (gcd -12 8))
(test-equal 24 (lcm -12 8))
(test-equal 0 (gcd 0 0))
(test-equal 5 (gcd 0 5))
(test-equal 0 (lcm 0 5))

;; comparisons with all types
(test-equal #t (= 1 1))
(test-equal #t (= 1 1.0))
(test-equal #t (= 1/2 0.5))
(test-equal #t (< 1 2 3))
(test-equal #t (> 3 2 1))
(test-equal #t (<= 1 1 2))
(test-equal #t (>= 2 2 1))
(test-equal #t (< 1/3 1/2))
(test-equal #t (> (expt 2 100) (expt 2 50)))

;; Type errors are catchable
(test-equal #t (guard (e (#t (error-object? e))) (+ 1 "hello")))
(test-equal #t (guard (e (#t (error-object? e))) (quotient 1 "hello")))
(test-equal #t (guard (e (#t (error-object? e))) (even? "hello")))
(test-equal #t (guard (e (#t (error-object? e))) (abs "hello")))

;; Division by zero
(test-equal #t (guard (e (#t #t)) (/ 1 0)))
(test-equal #t (guard (e (#t #t)) (quotient 1 0)))
(test-equal #t (guard (e (#t #t)) (remainder 1 0)))
(test-equal #t (guard (e (#t #t)) (modulo 1 0)))

(let ((runner (test-runner-current)))
  (test-end "primitives_arithmetic audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
