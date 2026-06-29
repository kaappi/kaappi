;; Regression test for #423: real-part, imag-part, magnitude, angle
;; must accept bignum and rational arguments

(import (scheme base) (scheme write) (scheme inexact))

;; Rational arguments
(unless (= (real-part 1/2) 1/2)
  (error "(real-part 1/2) should be 1/2"))
(unless (= (imag-part 1/2) 0)
  (error "(imag-part 1/2) should be 0"))
(unless (> (magnitude 1/2) 0)
  (error "(magnitude 1/2) should be positive"))
(unless (= (angle 1/2) 0)
  (error "(angle 1/2) should be 0 for positive rational"))
(unless (> (angle -1/2) 3)
  (error "(angle -1/2) should be pi for negative rational"))

;; Bignum arguments
(let ((big (expt 2 100)))
  (unless (= (real-part big) big)
    (error "(real-part bignum) should return the bignum"))
  (unless (= (imag-part big) 0)
    (error "(imag-part bignum) should be 0"))
  (unless (= (magnitude big) big)
    (error "(magnitude bignum) should return abs value"))
  (unless (= (angle big) 0)
    (error "(angle bignum) should be 0 for positive bignum")))

;; Negative bignum
(let ((neg-big (- (expt 2 100))))
  (unless (> (angle neg-big) 3)
    (error "(angle neg-bignum) should be pi")))

(display "PASS")
(newline)
