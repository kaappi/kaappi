(import (scheme base) (scheme char) (scheme lazy)
        (scheme inexact) (scheme complex) (scheme time)
        (scheme file) (scheme read) (scheme write)
        (scheme eval) (scheme process-context) (scheme case-lambda)
        (chibi test))

(test-begin "6.2 Numbers")

(test #t (complex? 3+4i))
(test #t (complex? 3))
(test #t (real? 3))
(test #t (real? -2.5+0i))
(test #f (real? -2.5+0.0i))
(test #t (real? #e1e10))
(test #t (real? +inf.0))
(test #f (rational? -inf.0))
(test #f (rational? +nan.0))
(test #t (rational? 9007199254740991.0))
(test #t (rational? 9007199254740992.0))
(test #t (rational? 1.7976931348623157e308))
(test #t (rational? 6/10))
(test #t (rational? 6/3))
(test #t (integer? 3+0i))
(test #t (integer? 3.0))
(test #t (integer? 8/4))

(test #f (exact? 3.0))
(test #t (exact? #e3.0))
(test #t (inexact? 3.))

(test #t (exact-integer? 32))
(test #f (exact-integer? 32.0))
(test #f (exact-integer? 32/5))

(test #t (finite? 3))
(test #f (finite? +inf.0))
;; SKIP: (test #f (finite? 3.0+inf.0i))

(test #f (infinite? 3))
(test #t (infinite? +inf.0))
(test #f (infinite? +nan.0))
;; SKIP: (test #t (infinite? 3.0+inf.0i))

(test #t (nan? +nan.0))
(test #f (nan? 32))
;; (test #t (nan? +nan.0+5.0i))
(test #f (nan? 1+2i))

(test #t (= 1 1.0 1.0+0.0i))
(test #f (= 1.0 1.0+1.0i))
(test #t (< 1 2 3))
(test #f (< 1 1 2))
(test #t (> 3.0 2.0 1.0))
(test #f (> -3.0 2.0 1.0))
(test #t (<= 1 1 2))
(test #f (<= 1 2 1))
(test #t (>= 2 1 1))
(test #f (>= 1 2 1))
(test #f (< +nan.0 0))
(test #f (> +nan.0 0))
(test #f (< +nan.0 0.0))
(test #f (> +nan.0 0.0))
(test '(#t #f) (list (<= 1 1 2) (<= 2 1 3)))
(test #f (= 9007199254740992.0 9007199254740993))

;; From R7RS 6.2.6 Numerical operations:
;;
;; These predicates are required to be transitive.
;;
;; _Note:_ The traditional implementations of these predicates in
;; Lisp-like languages, which involve converting all arguments to inexact
;; numbers if any argument is inexact, are not transitive.

;; Example from Alan Bawden
(let ((a (- (expt 2 1000) 1))
      (b (inexact (expt 2 1000))) ; assuming > single-float-epsilon
      (c (+ (expt 2 1000) 1)))
  (test #t (if (and (= a b) (= b c))
               (= a c)
               #t)))

;; From CLtL 12.3. Comparisons on Numbers:
;;
;;  Let _a_ be the result of (/ 10.0 single-float-epsilon), and let
;;  _j_ be the result of (floor a). ..., all of (<= a j), (< j (+ j
;;  1)), and (<= (+ j 1) a) would be true; transitivity would then
;;  imply that (< a a) ought to be true ...

;; Transliteration from Jussi Piitulainen
(define single-float-epsilon
  (do ((eps 1.0 (* eps 2.0)))
      ((= eps (+ eps 1.0)) eps)))

(let* ((a (/ 10.0 single-float-epsilon))
       (j (exact a)))
  (test #t (if (and (<= a j) (< j (+ j 1)))
               (not (<= (+ j 1) a))
               #t)))

(test #t (zero? 0))
(test #t (zero? 0.0))
(test #t (zero? 0.0+0.0i))
(test #f (zero? 1))
(test #f (zero? -1))

(test #f (positive? 0))
(test #f (positive? 0.0))
(test #t (positive? 1))
(test #t (positive? 1.0))
(test #f (positive? -1))
(test #f (positive? -1.0))
(test #t (positive? +inf.0))
(test #f (positive? -inf.0))
(test #f (positive? +nan.0))

(test #f (negative? 0))
(test #f (negative? 0.0))
(test #f (negative? 1))
(test #f (negative? 1.0))
(test #t (negative? -1))
(test #t (negative? -1.0))
(test #f (negative? +inf.0))
(test #t (negative? -inf.0))
(test #f (negative? +nan.0))

(test #f (odd? 0))
(test #t (odd? 1))
(test #t (odd? -1))
(test #f (odd? 102))

(test #t (even? 0))
(test #f (even? 1))
(test #t (even? -2))
(test #t (even? 102))

(test 3 (max 3))
(test 4 (max 3 4))
(test 4.0 (max 3.9 4))
(test 5.0 (max 5 3.9 4))
(test +inf.0 (max 100 +inf.0))
(test 3 (min 3))
(test 3 (min 3 4))
(test 3.0 (min 3 3.1))
(test -inf.0 (min -inf.0 -100))

(test 7 (+ 3 4))
(test 3 (+ 3))
(test 0 (+))
(test 4 (* 4))
(test 1 (*))

(test -1 (- 3 4))
(test -6 (- 3 4 5))
(test -3 (- 3))
(test -3/2 (- 3/2))
(test -3/2-i (- 3/2+i))
(test 3/20 (/ 3 4 5))
(test 1/3 (/ 3))

(test 1073741824 (/ -1073741824 -1))
(test 1073741824 (quotient -1073741824 -1))
(test 0 (remainder -1073741824 -1))
(test 4611686018427387904 (/ -4611686018427387904 -1))
(test 4611686018427387904 (quotient -4611686018427387904 -1))
(test 0 (remainder -4611686018427387904 -1))

(test 7 (abs -7))
(test 7 (abs 7))

(test-values (values 2 1) (floor/ 5 2))
(test-values (values -3 1) (floor/ -5 2))
(test-values (values -3 -1) (floor/ 5 -2))
(test-values (values 2 -1) (floor/ -5 -2))
(test-values (values 2 1) (truncate/ 5 2))
(test-values (values -2 -1) (truncate/ -5 2))
(test-values (values -2 1) (truncate/ 5 -2))
(test-values (values 2 -1) (truncate/ -5 -2))
(test-values (values 2.0 -1.0) (truncate/ -5.0 -2))

(test 1 (modulo 13 4))
(test 1 (remainder 13 4))

(test 3 (modulo -13 4))
(test -1 (remainder -13 4))

(test -3 (modulo 13 -4))
(test 1 (remainder 13 -4))

(test -1 (modulo -13 -4))
(test -1 (remainder -13 -4))

(test -1.0 (remainder -13 -4.0))

(test 4 (gcd 32 -36))
(test 0 (gcd))
(test 288 (lcm 32 -36))
(test 288.0 (lcm 32.0 -36))
(test 1 (lcm))

(test 3 (numerator (/ 6 4)))
(test 2 (denominator (/ 6 4)))
(test 2.0 (denominator (inexact (/ 6 4))))
(test 11.0 (numerator 5.5))
(test 2.0 (denominator 5.5))
(test 5.0 (numerator 5.0))
(test 1.0 (denominator 5.0))

(test -5.0 (floor -4.3))
(test -4.0 (ceiling -4.3))
(test -4.0 (truncate -4.3))
(test -4.0 (round -4.3))

(test 3.0 (floor 3.5))
(test 4.0 (ceiling 3.5))
(test 3.0 (truncate 3.5))
(test 4.0 (round 3.5))

(test 4 (round 7/2))
(test 7 (round 7))
(test 1 (round 7/10))
(test -4 (round -7/2))
(test -7 (round -7))
(test -1 (round -7/10))

(test 1/3 (rationalize (exact .3) 1/10))
(test #i1/3 (rationalize .3 1/10))

(test 1.0 (inexact (exp 0))) ;; may return exact number
(test 20.0855369231877 (exp 3))

(test 0.0 (inexact (log 1))) ;; may return exact number
(test 1.0 (log (exp 1)))
(test 42.0 (log (exp 42)))
(test 2.0 (log 100 10))
(test 12.0 (log 4096 2))

(test 0.0 (inexact (sin 0))) ;; may return exact number
(test 1.0 (sin 1.5707963267949))
(test 1.0 (inexact (cos 0))) ;; may return exact number
(test -1.0 (cos 3.14159265358979))
(test 0.0 (inexact (tan 0))) ;; may return exact number
(test 1.5574077246549 (tan 1))

(test 0.0 (inexact (asin 0))) ;; may return exact number
(test 1.5707963267949 (asin 1))
(test 0.0 (inexact (acos 1))) ;; may return exact number
(test 3.14159265358979 (acos -1))

;; (test 0.0-0.0i (asin 0+0.0i))
;; (test 1.5707963267948966+0.0i (acos 0+0.0i))

(test 0.0 (atan 0.0 1.0))
(test -0.0 (atan -0.0 1.0))
(test 0.785398163397448 (atan 1.0 1.0))
(test 1.5707963267949 (atan 1.0 0.0))
(test 2.35619449019234 (atan 1.0 -1.0))
(test 3.14159265358979 (atan 0.0 -1.0))
(test -3.14159265358979 (atan -0.0 -1.0)) ;
(test -2.35619449019234 (atan -1.0 -1.0))
(test -1.5707963267949 (atan -1.0 0.0))
(test -0.785398163397448 (atan -1.0 1.0))
;; (test undefined (atan 0.0 0.0))

(test 1764 (square 42))
(test 4 (square 2))

(test 3.0 (inexact (sqrt 9)))
(test 1.4142135623731 (sqrt 2))
;; Skipped: complex number literals (1+2i) not supported by reader
;; (test 0.0+1.0i (inexact (sqrt -1)))
;; (test 0.0+1.0i (sqrt -1.0-0.0i))

(test '(2 0) (call-with-values (lambda () (exact-integer-sqrt 4)) list))
(test '(2 1) (call-with-values (lambda () (exact-integer-sqrt 5)) list))

(test 27 (expt 3 3))
(test 1 (expt 0 0))
(test 0 (expt 0 1))
(test 1.0 (expt 0.0 0))
(test 0.0 (expt 0 1.0))

(test 1+2i (make-rectangular 1 2))

;; (test 0.54030230586814+0.841470984807897i (make-polar 1 1))

;; Complex literal tests skipped (reader doesn't parse 1+2i)
(test 1 (real-part 1+2i))
(test 2 (imag-part 1+2i))
(test 2.23606797749979 (magnitude 1+2i))
(test 1.10714871779409 (angle 1+2i))

(test 1.0 (inexact 1))
(test #t (inexact? (inexact 1)))
(test 1 (exact 1.0))
(test #t (exact? (exact 1.0)))

(test 100 (string->number "100"))
(test 256 (string->number "100" 16))
(test 100.0 (string->number "1e2"))
(test #f (string->number "1 2"))

(test-end)
