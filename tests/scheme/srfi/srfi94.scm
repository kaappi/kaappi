;; SRFI-94 (Type-Restricted Numerical Functions) conformance tests
;; Run: zig-out/bin/kaappi --lib-path lib tests/scheme/srfi/srfi94.scm
;;
;; See lib/srfi/94.sld's header for why this library does not re-export
;; abs, atan (2-arg), make-rectangular, make-polar, quotient, remainder,
;; or modulo under their standard (scheme base) names, and for a documented
;; gap in Kaappi's `expt' around negative-base/non-integer-exponent input
;; that this library's real-expt deliberately never exercises.

(import (scheme base) (scheme process-context) (srfi 94) (srfi 64))

(test-begin "srfi-94")

;;; --- real-exp / real-sin / real-cos / real-tan: plain "must be real" ---

(test-equal "real-exp 0" 1.0 (real-exp 0))
(test-approximate "real-exp 1 ~= e" 2.718281828459045 (real-exp 1) 1e-9)
(test-equal "real-sin 0" 0.0 (real-sin 0))
(test-equal "real-cos 0" 1.0 (real-cos 0))
(test-equal "real-tan 0" 0.0 (real-tan 0))
(test-error "real-exp: complex argument is a type error" (real-exp 3+4i))
(test-error "real-sin: complex argument is a type error" (real-sin 3+4i))
(test-error "real-cos: complex argument is a type error" (real-cos 3+4i))
(test-error "real-tan: complex argument is a type error" (real-tan 3+4i))

;;; --- real-ln: non-negative real required ---

(test-equal "real-ln 1" 0.0 (real-ln 1))
(test-approximate "real-ln e ~= 1" 1.0 (real-ln 2.718281828459045) 1e-9)
(test-equal "real-ln 0 is allowed (must-be-real+ permits zero)" -inf.0 (real-ln 0))
(test-error "real-ln: negative argument is a type error" (real-ln -1))
(test-error "real-ln: complex argument is a type error" (real-ln 3+4i))

;;; --- real-sqrt: non-negative real required ---

(test-equal "real-sqrt 4 stays exact" 2 (real-sqrt 4))
(test-approximate "real-sqrt 2" 1.4142135623730951 (real-sqrt 2) 1e-9)
(test-equal "real-sqrt 0" 0 (real-sqrt 0))
(test-error "real-sqrt: negative argument is a type error" (real-sqrt -4))
(test-error "real-sqrt: complex argument is a type error" (real-sqrt 3+4i))

;;; --- real-asin / real-acos: real in [-1, 1] required ---

(test-equal "real-asin 0" 0.0 (real-asin 0))
(test-approximate "real-asin 1 ~= pi/2" 1.5707963267948966 (real-asin 1) 1e-9)
(test-equal "real-acos 1" 0.0 (real-acos 1))
(test-approximate "real-acos 0 ~= pi/2" 1.5707963267948966 (real-acos 0) 1e-9)
(test-error "real-asin: 2 is out of [-1, 1]" (real-asin 2))
(test-error "real-asin: -2 is out of [-1, 1]" (real-asin -2))
(test-error "real-acos: 2 is out of [-1, 1]" (real-acos 2))
(test-error "real-acos: complex argument is a type error" (real-acos 3+4i))

;;; --- real-atan: one or two real arguments ---

(test-equal "real-atan 0 (1-arg)" 0.0 (real-atan 0))
(test-approximate "real-atan 1 (1-arg) ~= pi/4" 0.7853981633974483 (real-atan 1) 1e-9)
(test-approximate "real-atan 1 1 (2-arg) ~= pi/4" 0.7853981633974483 (real-atan 1 1) 1e-9)
(test-equal "real-atan 0 1 (2-arg)" 0.0 (real-atan 0 1))
(test-error "real-atan: complex 1-arg is a type error" (real-atan 3+4i))
(test-error "real-atan: complex y in 2-arg form is a type error" (real-atan 3+4i 1))
(test-error "real-atan: complex x in 2-arg form is a type error" (real-atan 1 3+4i))

;;; --- real-log: y (base) and x (value) both positive reals ---
;;; Call form is (real-log y x), meaning log base y of x -- the OPPOSITE
;;; argument order from Kaappi's native two-argument `log' -- see the
;;; .sld header for why real-log is computed directly rather than by
;;; delegating to two-argument `log'.

(test-equal "real-log 2 8 = 3" 3.0 (real-log 2 8))
(test-approximate "real-log 10 100 = 2" 2.0 (real-log 10 100) 1e-9)
(test-error "real-log: negative base is a type error" (real-log -2 8))
(test-error "real-log: negative value is a type error" (real-log 2 -8))
(test-error "real-log: zero value is a type error (strictly positive required)" (real-log 2 0))
(test-error "real-log: zero base is a type error (strictly positive required)" (real-log 0 8))
(test-error "real-log: complex value is a type error" (real-log 2 3+4i))

;;; --- real-expt: real base/exponent, and the result must be real ---

(test-equal "real-expt 2 10" 1024 (real-expt 2 10))
(test-equal "real-expt 2 -3 stays exact" 1/8 (real-expt 2 -3))
(test-equal "real-expt 0.0 0.0 -> 1.0" 1.0 (real-expt 0.0 0.0))
(test-equal "real-expt 0.0 3 -> 0.0" 0.0 (real-expt 0.0 3))
(test-equal "real-expt -8 -2 (integer exponent keeps result real)" 1/64 (real-expt -8 -2))
(test-error "real-expt: complex base is a type error" (real-expt 3+4i 2))
(test-error "real-expt: 0.0 to a negative power is undefined per spec" (real-expt 0.0 -2))
(test-error "real-expt: negative base with non-integer exponent would be complex"
  (real-expt -8 1/3))
(test-error "real-expt: negative base with inexact non-integer exponent would be complex"
  (real-expt -8.0 0.5))

;;; --- integer-sqrt: non-negative exact integer required ---

(test-equal "integer-sqrt 16" 4 (integer-sqrt 16))
(test-equal "integer-sqrt 17 floors" 4 (integer-sqrt 17))
(test-equal "integer-sqrt 0" 0 (integer-sqrt 0))
(test-equal "integer-sqrt 1" 1 (integer-sqrt 1))
(test-error "integer-sqrt: negative argument is a type error" (integer-sqrt -1))
(test-error "integer-sqrt: inexact argument is a type error" (integer-sqrt 4.0))
(test-error "integer-sqrt: non-integer rational is a type error" (integer-sqrt 1/2))

;;; --- integer-expt: exact-integer args whose power is itself an exact integer ---

(test-equal "integer-expt 2 10" 1024 (integer-expt 2 10))
(test-equal "integer-expt 2 0" 1 (integer-expt 2 0))
(test-equal "integer-expt 0 5" 0 (integer-expt 0 5))
(test-equal "integer-expt 0 0" 1 (integer-expt 0 0))
(test-equal "integer-expt -1 -5 stays an exact integer" -1 (integer-expt -1 -5))
(test-equal "integer-expt 1 -5 stays an exact integer" 1 (integer-expt 1 -5))
(test-error "integer-expt: 2^-3 is not an integer" (integer-expt 2 -3))
(test-error "integer-expt: 0^-2 is a type error" (integer-expt 0 -2))
(test-error "integer-expt: inexact base is a type error" (integer-expt 2.0 3))
(test-error "integer-expt: inexact exponent is a type error" (integer-expt 2 3.0))

;;; --- integer-log: base > 1, bound > 0, both exact integers ---

(test-equal "integer-log 2 100 = 6 (2^6=64<=100<128=2^7)" 6 (integer-log 2 100))
(test-equal "integer-log 10 999 = 2" 2 (integer-log 10 999))
(test-equal "integer-log 2 1 = 0" 0 (integer-log 2 1))
(test-equal "integer-log 3 27 = 3" 3 (integer-log 3 27))
(test-error "integer-log: base of 1 is undefined and rejected" (integer-log 1 10))
(test-error "integer-log: non-positive bound is a type error" (integer-log 2 0))
(test-error "integer-log: inexact base is a type error" (integer-log 2.0 10))
(test-error "integer-log: inexact bound is a type error" (integer-log 2 10.0))

;;; --- quo / rem / mod: real-number (Common Lisp) division trio ---
;;; Verbatim spec examples (SRFI 94 "Specification" section).

(test-equal "quo 2/3 1/5" 3 (quo 2/3 1/5))
(test-equal "mod 2/3 1/5" 1/15 (mod 2/3 1/5))
(test-equal "quo .666 1/5" 3.0 (quo .666 1/5))
(test-approximate "mod .666 1/5 ~= 0.066" 0.06599999999999995 (mod .666 1/5) 1e-12)

;; Identity (= x1 (+ (* x2 (quo x1 x2)) (rem x1 x2))) for exact inputs.
(test-assert "quo/rem identity holds for exact inputs"
  (let ((x1 17/3) (x2 5/2))
    (= x1 (+ (* x2 (quo x1 x2)) (rem x1 x2)))))

(test-error "quo: complex argument is a type error" (quo 3+4i 2))
(test-error "rem: complex argument is a type error" (rem 3+4i 2))
(test-error "mod: complex argument is a type error" (mod 3+4i 2))

;;; --- ln: a plain (non type-restricted) synonym for `log' ---

(test-equal "ln 1" 0.0 (ln 1))
(test-approximate "ln e ~= 1" 1.0 (ln 2.718281828459045) 1e-9)

(let ((runner (test-runner-current)))
  (test-end "srfi-94")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
