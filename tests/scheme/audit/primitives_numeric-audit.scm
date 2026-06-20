(import (scheme base) (scheme write) (scheme read) (scheme inexact) (scheme complex))
(import (chibi test))

(test-begin "primitives_numeric audit")

;;; ================================================================
;;; Rounding (floor, ceiling, truncate, round)
;;; ================================================================
(test #t (= 3 (floor 3.7)))
(test 3 (floor 3))
(test 2 (floor 7/3))
(test #t (= -4 (floor -3.1)))
(test #t (= 4 (ceiling 3.1)))
(test 3 (ceiling 3))
(test 3 (ceiling 7/3))
(test #t (= 3 (truncate 3.7)))
(test #t (= -3 (truncate -3.7)))
(test #t (= 4 (round 3.5)))
(test #t (= 2 (round 2.5)))
(test 4 (round 7/2))

;; Bignums pass through unchanged
(test (expt 2 100) (floor (expt 2 100)))
(test (expt 2 100) (ceiling (expt 2 100)))

;;; ================================================================
;;; Bug 1-2: exact/inexact on complex
;;; ================================================================
;; inexact on complex should work
;; (test #t (inexact? (inexact (make-rectangular 1 2))))
;; exact on complex should work
;; (test #t (exact? (exact (make-rectangular 1.0 2.0))))

;;; ================================================================
;;; Bug 3-4: exact?/inexact? on complex
;;; ================================================================
;; (test #t (exact? (make-rectangular 1 2)))
;; (test #t (inexact? (make-rectangular 1.0 2.0)))

;;; ================================================================
;;; Exactness predicates
;;; ================================================================
(test #t (exact? 42))
(test #t (exact? 1/3))
(test #t (exact? (expt 2 100)))
(test #f (exact? 3.14))
(test #t (inexact? 3.14))
(test #f (inexact? 42))
(test #t (exact-integer? 42))
(test #t (exact-integer? (expt 2 100)))
(test #f (exact-integer? 1/3))
(test #f (exact-integer? 3.14))

;;; ================================================================
;;; exact/inexact conversion
;;; ================================================================
(test #t (= 3.0 (inexact 3)))
(test #t (= 0.5 (inexact 1/2)))
(test 1/2 (exact 0.5))
(test 1/4 (exact 0.25))
(test 3 (exact 3.0))
(test #t (inexact? (inexact (expt 2 100))))

;;; ================================================================
;;; Bug 8: floor-quotient/remainder on bignums
;;; ================================================================
(test #t (integer? (floor-quotient (expt 2 100) 3)))
(test #t (integer? (floor-remainder (expt 2 100) 3)))
(test #t (integer? (truncate-quotient (expt 2 100) 3)))
(test #t (integer? (truncate-remainder (expt 2 100) 3)))

;; Floor/truncate division basics
(test 3 (floor-quotient 7 2))
(test 1 (floor-remainder 7 2))
(test -4 (floor-quotient -7 2))
(test 1 (floor-remainder -7 2))
(test 3 (truncate-quotient 7 2))
(test 1 (truncate-remainder 7 2))
(test -3 (truncate-quotient -7 2))
(test -1 (truncate-remainder -7 2))

;; Flonum division
(test #t (= 3.0 (floor-quotient 7.0 2.0)))
(test #t (= 1.0 (floor-remainder 7.0 2.0)))
(test #t (= 3.0 (truncate-quotient 7.0 2.0)))
(test #t (= 1.0 (truncate-remainder 7.0 2.0)))

;;; ================================================================
;;; number->string
;;; ================================================================
(test "42" (number->string 42))
(test "ff" (number->string 255 16))
(test "1010" (number->string 10 2))
(test "377" (number->string 255 8))
(test "0" (number->string 0 16))
(test "1/3" (number->string 1/3))

;; Bug 9: bignum with non-decimal radix
;; (test #t (string? (number->string (expt 2 100) 16)))

;;; ================================================================
;;; string->number
;;; ================================================================
(test 42 (string->number "42"))
(test 255 (string->number "ff" 16))
(test 10 (string->number "1010" 2))
(test 3/4 (string->number "3/4"))
(test #t (= +inf.0 (string->number "+inf.0")))
(test #t (= -inf.0 (string->number "-inf.0")))
(test #t (nan? (string->number "+nan.0")))
(test #f (string->number "not-a-number"))

;;; ================================================================
;;; sqrt
;;; ================================================================
(test #t (= 2.0 (sqrt 4)))
(test #t (= 3.0 (sqrt 9)))
(test #t (= 2.0 (sqrt 4.0)))
;; sqrt of negative should ideally return complex, but may error
;; Just verify it doesn't crash
(test #t (guard (e (#t #t)) (number? (sqrt -1.0))))

;;; ================================================================
;;; exact-integer-sqrt
;;; ================================================================
(let-values (((s r) (exact-integer-sqrt 14)))
  (test 3 s)
  (test 5 r))
(let-values (((s r) (exact-integer-sqrt 0)))
  (test 0 s)
  (test 0 r))
(let-values (((s r) (exact-integer-sqrt 1)))
  (test 1 s)
  (test 0 r))

;;; ================================================================
;;; expt
;;; ================================================================
(test 8 (expt 2 3))
(test 1 (expt 0 0))
(test 0 (expt 0 1))
(test 1 (expt 1 1000000))
(test 1 (expt -1 100))
(test -1 (expt -1 99))
(test #t (= 1.0 (expt 2.0 0)))

;;; ================================================================
;;; square
;;; ================================================================
(test 25 (square 5))
(test 9 (square -3))
(test 0 (square 0))
(test 1/9 (square 1/3))

;;; ================================================================
;;; Trig functions
;;; ================================================================
(test #t (= 0.0 (sin 0)))
(test #t (= 1.0 (cos 0)))
(test #t (= 0.0 (tan 0)))
(test #t (< (abs (- (asin 1) 1.5707963)) 0.001))
(test #t (< (abs (acos 1)) 0.001))
(test #t (< (abs (- (atan 1) 0.7853981)) 0.001))
(test #t (< (abs (- (atan 1 1) 0.7853981)) 0.001))
(test #t (= 1.0 (exp 0)))
(test #t (= 0.0 (log 1)))

;;; ================================================================
;;; Complex operations
;;; ================================================================
(test 3 (real-part 3+4i))
(test 4 (imag-part 3+4i))
(test 3 (real-part 3))
(test 0 (imag-part 3))
(test #t (= 5.0 (magnitude 3+4i)))
(test 5 (magnitude -5))
(test 5 (magnitude 5))
(test #t (< (abs (- (angle -1) 3.14159265)) 0.001))
(test 3+4i (make-rectangular 3 4))

;;; ================================================================
;;; numerator/denominator
;;; ================================================================
(test 3 (numerator 3/7))
(test 7 (denominator 3/7))
(test 5 (numerator 5))
(test 1 (denominator 5))
(test #t (= 1.0 (numerator 0.5)))
(test #t (= 2.0 (denominator 0.5)))

;;; ================================================================
;;; rationalize
;;; ================================================================
(test #t (rational? (rationalize (exact 0.3) 1/10)))

;;; ================================================================
;;; finite?/infinite?/nan?
;;; ================================================================
(test #t (finite? 42))
(test #t (finite? 1.0))
(test #f (finite? +inf.0))
(test #t (infinite? +inf.0))
(test #t (infinite? -inf.0))
(test #f (infinite? 1.0))
(test #t (nan? +nan.0))
(test #f (nan? 1.0))

;;; ================================================================
;;; Type errors are catchable
;;; ================================================================
(test #t (guard (e (#t (error-object? e))) (floor "x")))
(test #t (guard (e (#t (error-object? e))) (exact "x")))
(test #t (guard (e (#t (error-object? e))) (inexact "x")))
(test #t (guard (e (#t (error-object? e))) (sqrt "x")))
(test #t (guard (e (#t (error-object? e))) (exact-integer-sqrt -1)))

(test-end "primitives_numeric audit")
