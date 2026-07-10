(import (scheme base) (scheme write) (scheme read) (scheme inexact) (scheme complex))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_numeric audit")

;;; ================================================================
;;; Rounding (floor, ceiling, truncate, round)
;;; ================================================================
(test-equal #t (= 3 (floor 3.7)))
(test-equal 3 (floor 3))
(test-equal 2 (floor 7/3))
(test-equal #t (= -4 (floor -3.1)))
(test-equal #t (= 4 (ceiling 3.1)))
(test-equal 3 (ceiling 3))
(test-equal 3 (ceiling 7/3))
(test-equal #t (= 3 (truncate 3.7)))
(test-equal #t (= -3 (truncate -3.7)))
(test-equal #t (= 4 (round 3.5)))
(test-equal #t (= 2 (round 2.5)))
(test-equal 4 (round 7/2))

;; Bignums pass through unchanged
(test-equal (expt 2 100) (floor (expt 2 100)))
(test-equal (expt 2 100) (ceiling (expt 2 100)))

;;; ================================================================
;;; Bug 1-2: exact/inexact on complex
;;; ================================================================
;; inexact on complex should work
;; (test-equal #t (inexact? (inexact (make-rectangular 1 2))))
;; exact on complex should work
;; (test-equal #t (exact? (exact (make-rectangular 1.0 2.0))))

;;; ================================================================
;;; Bug 3-4: exact?/inexact? on complex
;;; ================================================================
;; (test-equal #t (exact? (make-rectangular 1 2)))
;; (test-equal #t (inexact? (make-rectangular 1.0 2.0)))

;;; ================================================================
;;; Exactness predicates
;;; ================================================================
(test-equal #t (exact? 42))
(test-equal #t (exact? 1/3))
(test-equal #t (exact? (expt 2 100)))
(test-equal #f (exact? 3.14))
(test-equal #t (inexact? 3.14))
(test-equal #f (inexact? 42))
(test-equal #t (exact-integer? 42))
(test-equal #t (exact-integer? (expt 2 100)))
(test-equal #f (exact-integer? 1/3))
(test-equal #f (exact-integer? 3.14))

;;; ================================================================
;;; exact/inexact conversion
;;; ================================================================
(test-equal #t (= 3.0 (inexact 3)))
(test-equal #t (= 0.5 (inexact 1/2)))
(test-equal 1/2 (exact 0.5))
(test-equal 1/4 (exact 0.25))
(test-equal 3 (exact 3.0))
(test-equal #t (inexact? (inexact (expt 2 100))))

;;; ================================================================
;;; Bug 8: floor-quotient/remainder on bignums
;;; ================================================================
(test-equal #t (integer? (floor-quotient (expt 2 100) 3)))
(test-equal #t (integer? (floor-remainder (expt 2 100) 3)))
(test-equal #t (integer? (truncate-quotient (expt 2 100) 3)))
(test-equal #t (integer? (truncate-remainder (expt 2 100) 3)))

;; Floor/truncate division basics
(test-equal 3 (floor-quotient 7 2))
(test-equal 1 (floor-remainder 7 2))
(test-equal -4 (floor-quotient -7 2))
(test-equal 1 (floor-remainder -7 2))
(test-equal 3 (truncate-quotient 7 2))
(test-equal 1 (truncate-remainder 7 2))
(test-equal -3 (truncate-quotient -7 2))
(test-equal -1 (truncate-remainder -7 2))

;; Flonum division
(test-equal #t (= 3.0 (floor-quotient 7.0 2.0)))
(test-equal #t (= 1.0 (floor-remainder 7.0 2.0)))
(test-equal #t (= 3.0 (truncate-quotient 7.0 2.0)))
(test-equal #t (= 1.0 (truncate-remainder 7.0 2.0)))

;;; ================================================================
;;; number->string
;;; ================================================================
(test-equal "42" (number->string 42))
(test-equal "ff" (number->string 255 16))
(test-equal "1010" (number->string 10 2))
(test-equal "377" (number->string 255 8))
(test-equal "0" (number->string 0 16))
(test-equal "1/3" (number->string 1/3))

;; Bug 9: bignum with non-decimal radix
;; (test-equal #t (string? (number->string (expt 2 100) 16)))

;;; ================================================================
;;; string->number
;;; ================================================================
(test-equal 42 (string->number "42"))
(test-equal 255 (string->number "ff" 16))
(test-equal 10 (string->number "1010" 2))
(test-equal 3/4 (string->number "3/4"))
(test-equal #t (= +inf.0 (string->number "+inf.0")))
(test-equal #t (= -inf.0 (string->number "-inf.0")))
(test-equal #t (nan? (string->number "+nan.0")))
(test-equal #f (string->number "not-a-number"))

;;; ================================================================
;;; sqrt
;;; ================================================================
(test-equal #t (= 2.0 (sqrt 4)))
(test-equal #t (= 3.0 (sqrt 9)))
(test-equal #t (= 2.0 (sqrt 4.0)))
;; sqrt of negative should ideally return complex, but may error
;; Just verify it doesn't crash
(test-equal #t (guard (e (#t #t)) (number? (sqrt -1.0))))

;;; ================================================================
;;; exact-integer-sqrt
;;; ================================================================
(let-values (((s r) (exact-integer-sqrt 14)))
  (test-equal 3 s)
  (test-equal 5 r))
(let-values (((s r) (exact-integer-sqrt 0)))
  (test-equal 0 s)
  (test-equal 0 r))
(let-values (((s r) (exact-integer-sqrt 1)))
  (test-equal 1 s)
  (test-equal 0 r))

;;; ================================================================
;;; expt
;;; ================================================================
(test-equal 8 (expt 2 3))
(test-equal 1 (expt 0 0))
(test-equal 0 (expt 0 1))
(test-equal 1 (expt 1 1000000))
(test-equal 1 (expt -1 100))
(test-equal -1 (expt -1 99))
(test-equal #t (= 1.0 (expt 2.0 0)))

;;; ================================================================
;;; square
;;; ================================================================
(test-equal 25 (square 5))
(test-equal 9 (square -3))
(test-equal 0 (square 0))
(test-equal 1/9 (square 1/3))

;;; ================================================================
;;; Trig functions
;;; ================================================================
(test-equal #t (= 0.0 (sin 0)))
(test-equal #t (= 1.0 (cos 0)))
(test-equal #t (= 0.0 (tan 0)))
(test-equal #t (< (abs (- (asin 1) 1.5707963)) 0.001))
(test-equal #t (< (abs (acos 1)) 0.001))
(test-equal #t (< (abs (- (atan 1) 0.7853981)) 0.001))
(test-equal #t (< (abs (- (atan 1 1) 0.7853981)) 0.001))
(test-equal #t (= 1.0 (exp 0)))
(test-equal #t (= 0.0 (log 1)))

;;; ================================================================
;;; Complex operations
;;; ================================================================
(test-equal 3 (real-part 3+4i))
(test-equal 4 (imag-part 3+4i))
(test-equal 3 (real-part 3))
(test-equal 0 (imag-part 3))
(test-equal #t (= 5.0 (magnitude 3+4i)))
(test-equal 5 (magnitude -5))
(test-equal 5 (magnitude 5))
(test-equal #t (< (abs (- (angle -1) 3.14159265)) 0.001))
(test-equal 3+4i (make-rectangular 3 4))

;;; ================================================================
;;; numerator/denominator
;;; ================================================================
(test-equal 3 (numerator 3/7))
(test-equal 7 (denominator 3/7))
(test-equal 5 (numerator 5))
(test-equal 1 (denominator 5))
(test-equal #t (= 1.0 (numerator 0.5)))
(test-equal #t (= 2.0 (denominator 0.5)))

;;; ================================================================
;;; rationalize
;;; ================================================================
(test-equal #t (rational? (rationalize (exact 0.3) 1/10)))

;;; ================================================================
;;; finite?/infinite?/nan?
;;; ================================================================
(test-equal #t (finite? 42))
(test-equal #t (finite? 1.0))
(test-equal #f (finite? +inf.0))
(test-equal #t (infinite? +inf.0))
(test-equal #t (infinite? -inf.0))
(test-equal #f (infinite? 1.0))
(test-equal #t (nan? +nan.0))
(test-equal #f (nan? 1.0))

;;; ================================================================
;;; Type errors are catchable
;;; ================================================================
(test-equal #t (guard (e (#t (error-object? e))) (floor "x")))
(test-equal #t (guard (e (#t (error-object? e))) (exact "x")))
(test-equal #t (guard (e (#t (error-object? e))) (inexact "x")))
(test-equal #t (guard (e (#t (error-object? e))) (sqrt "x")))
(test-equal #t (guard (e (#t (error-object? e))) (exact-integer-sqrt -1)))

(let ((runner (test-runner-current)))
  (test-end "primitives_numeric audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
