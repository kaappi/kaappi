(import (scheme base) (scheme write) (scheme inexact) (scheme complex))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-approx name got expected eps)
  (if (< (abs (- got expected)) eps) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ~") (write expected)
             (display " got ") (write got) (newline))))

;;; ---- Complex number arithmetic ----
(check "complex +" (+ 1+2i 3+4i) 4+6i)
(check "complex -" (- 3+4i 1+2i) 2+2i)
(check "complex * " (* 1+2i 3+4i) -5+10i)
(check "complex negate" (- 1+2i) -1-2i)
(check "complex = same" (= 1+2i 1+2i) #t)
(check-false "complex = diff" (= 1+2i 1+3i))
(check-true "complex zero?" (zero? 0+0i))
(check-false "complex zero? nonzero" (zero? 1+0i))
(check "complex real-part" (real-part 3+4i) 3)
(check "complex imag-part" (imag-part 3+4i) 4)
(check-approx "complex magnitude" (magnitude 3+4i) 5.0 0.001)
(check-approx "complex angle" (angle 0+1i) 1.5707963 0.001)

;; Division of complex
(let ((result (/ 1+2i 3+4i)))
  (check-approx "complex / real" (real-part result) 0.44 0.01)
  (check-approx "complex / imag" (imag-part result) 0.08 0.01))

;; make-rectangular / make-polar
(check "make-rectangular" (make-rectangular 3 4) 3+4i)
(let ((p (make-polar 1.0 0.0)))
  (check-approx "make-polar real" (real-part p) 1.0 0.001))

;;; ---- Rational arithmetic ----
(check "rational +" (+ 1/3 1/6) 1/2)
(check "rational -" (- 1/2 1/3) 1/6)
(check "rational *" (* 2/3 3/4) 1/2)
(check "rational /" (/ 2/3 4/5) 5/6)
(check-true "rational positive?" (positive? 1/3))
(check-true "rational negative?" (negative? -1/3))
(check "rational abs" (abs -1/3) 1/3)
(check "rational abs positive" (abs 2/5) 2/5)
(check "fixnum min" (min 1 2) 1)
(check "fixnum max" (max 1 2) 2)
(check "flonum min" (min 1.0 2.0) 1.0)
(check "flonum max" (max 1.0 2.0) 2.0)
(check "rational floor" (floor 7/3) 2)
(check "rational ceiling" (ceiling 7/3) 3)
(check "rational truncate" (truncate 7/3) 2)
(check "rational round" (round 7/2) 4)
(check "rational round down" (round 5/2) 2)
(check-true "rational exact?" (exact? 1/3))
(check "numerator" (numerator 3/7) 3)
(check "denominator" (denominator 3/7) 7)
(check "numerator fixnum" (numerator 5) 5)
(check "denominator fixnum" (denominator 5) 1)

;;; ---- Bignum arithmetic ----
(let ((big (expt 2 100)))
  (check-true "bignum integer?" (integer? big))
  (check-true "bignum exact?" (exact? big))
  (check "bignum + fixnum" (+ big 1) (+ (expt 2 100) 1))
  (check "bignum - bignum" (- big big) 0)
  (check "bignum * 2" (* big 2) (expt 2 101))
  (check-true "bignum > fixnum" (> big 100))
  (check-true "bignum < negative" (< (- big) 0)))

;; Bignum quotient/remainder/modulo
(check "bignum quotient" (quotient (expt 10 60) (expt 10 30)) (expt 10 30))
(check "bignum remainder" (remainder (expt 10 60) (expt 10 30)) 0)
(check "bignum modulo" (modulo (expt 10 60) (+ (expt 10 30) 1)) (modulo (expt 10 60) (+ (expt 10 30) 1)))

;; Negative bignum
(check "negative bignum" (- (expt 2 64)) (- (expt 2 64)))
(check "bignum negate" (- (expt 2 100)) (- 0 (expt 2 100)))
(check "negative bignum expt" (expt -2 100) (expt 2 100))
(check-true "negative odd expt" (negative? (expt -2 99)))

;; Bignum gcd/lcm
(check "bignum gcd" (gcd (expt 2 100) (expt 2 50)) (expt 2 50))

;; Bignum min/max
(check "bignum min" (min (expt 2 100) (expt 2 50)) (expt 2 50))
(check "bignum max" (max (expt 2 100) (expt 2 50)) (expt 2 100))

;; Bignum number->string
(check-true "bignum->string" (string? (number->string (expt 10 30))))
(check-true "neg bignum->string" (string? (number->string (- (expt 10 30)))))

;; Bignum exact->inexact
(check-true "bignum->inexact" (inexact? (inexact (expt 2 100))))

;;; ---- Mixed type arithmetic ----
(check "fixnum + flonum" (+ 1 1.5) 2.5)
(check "fixnum + rational" (+ 1 1/2) 3/2)
(check "rational + flonum" (inexact (+ 1/3 0.0)) (inexact 1/3))

;;; ---- Comparisons ----
(check-true "< mixed" (< 1 1.5 2))
(check-true "<= mixed" (<= 1 1 2))
(check-true "> mixed" (> 3 2.5 2))
(check-true ">= mixed" (>= 3 3 2))
(check-true "= exact/inexact" (= 1 1.0))

;;; ---- Exact/inexact conversion ----
(check "exact 0.5" (exact 0.5) 1/2)
(check "exact 0.25" (exact 0.25) 1/4)
(check "inexact 1/2" (inexact 1/2) 0.5)
(check "inexact 1/3" (inexact 1/3) (/ 1.0 3.0))

;;; ---- Numeric predicates ----
(check-true "finite? fixnum" (finite? 42))
(check-true "finite? flonum" (finite? 1.5))
(check-false "finite? +inf" (finite? +inf.0))
(check-false "finite? -inf" (finite? -inf.0))
(check-true "infinite? +inf" (infinite? +inf.0))
(check-false "infinite? 1.0" (infinite? 1.0))
(check-true "nan? +nan" (nan? +nan.0))
(check-false "nan? 1.0" (nan? 1.0))

;;; ---- Exact integer operations ----
(check "quotient" (quotient 7 2) 3)
(check "remainder" (remainder 7 2) 1)
(check "modulo" (modulo 7 2) 1)
(check "quotient negative" (quotient -7 2) -3)
(check "remainder negative" (remainder -7 2) -1)
(check "modulo negative" (modulo -7 2) 1)

;;; ---- Floor/truncate division ----
(check "floor-quotient" (floor-quotient 7 2) 3)
(check "floor-remainder" (floor-remainder 7 2) 1)
(check "truncate-quotient" (truncate-quotient 7 2) 3)
(check "truncate-remainder" (truncate-remainder 7 2) 1)
(check "floor-quotient neg" (floor-quotient -7 2) -4)
(check "floor-remainder neg" (floor-remainder -7 2) 1)

;;; ---- exact-integer-sqrt ----
(let-values (((s r) (exact-integer-sqrt 14)))
  (check "exact-integer-sqrt root" s 3)
  (check "exact-integer-sqrt remainder" r 5))
(let-values (((s r) (exact-integer-sqrt 16)))
  (check "exact-integer-sqrt perfect" s 4)
  (check "exact-integer-sqrt perfect rem" r 0))

;;; ---- Trig ----
(check-approx "sin 0" (sin 0) 0.0 0.001)
(check-approx "cos 0" (cos 0) 1.0 0.001)
(check-approx "tan 0" (tan 0) 0.0 0.001)
(check-approx "asin 1" (asin 1) 1.5707963 0.001)
(check-approx "acos 1" (acos 1) 0.0 0.001)
(check-approx "atan 1" (atan 1) 0.7853981 0.001)
(check-approx "atan 1 1" (atan 1 1) 0.7853981 0.001)
(check-approx "exp 0" (exp 0) 1.0 0.001)
(check-approx "log 1" (log 1) 0.0 0.001)
(check-approx "log e" (log (exp 1)) 1.0 0.001)
(check-approx "sqrt 4" (sqrt 4) 2.0 0.001)
(check-approx "sqrt 2" (sqrt 2) 1.41421356 0.001)

;;; ---- Number -> String with radix ----
(check "number->string base 2" (number->string 10 2) "1010")
(check "number->string base 8" (number->string 255 8) "377")
(check "number->string base 16" (number->string 255 16) "ff")
(check "number->string neg base 16" (number->string -255 16) "-ff")

;;; ---- String -> Number with radix ----
(check "string->number hex" (string->number "ff" 16) 255)
(check "string->number octal" (string->number "377" 8) 255)
(check "string->number binary" (string->number "1010" 2) 10)
(check "string->number rational" (string->number "3/4") 3/4)
(check "string->number +inf" (string->number "+inf.0") +inf.0)
(check "string->number -inf" (string->number "-inf.0") -inf.0)
(check-true "string->number +nan" (nan? (string->number "+nan.0")))

;;; ---- make-polar / angle / magnitude ----
(check-approx "angle -1" (angle -1) 3.14159265 0.001)
(check-approx "angle -1.0" (angle -1.0) 3.14159265 0.001)
(check "magnitude -5" (magnitude -5) 5)
(check "magnitude -3.0" (magnitude -3.0) 3.0)
(check "magnitude 4" (magnitude 4) 4)

;;; ---- number->string of rational ----
(check "number->string 1/3" (number->string 1/3) "1/3")
(check "number->string -2/5" (number->string -2/5) "-2/5")

;;; ---- expt edge cases ----
(check "expt 0 0" (expt 0 0) 1)
(check "expt 0 1" (expt 0 1) 0)
(check "expt 1 big" (expt 1 1000000) 1)
(check "expt -1 even" (expt -1 100) 1)
(check "expt -1 odd" (expt -1 99) -1)
(check-approx "expt float" (expt 2.0 0.5) 1.41421 0.001)

;;; ---- rationalize ----
(let ((r (rationalize (exact 0.3) 1/10)))
  (check-true "rationalize is rational" (rational? r))
  (check-true "rationalize close" (<= (abs (- r 0.3)) 0.1)))

;;; ---- numerator/denominator of flonum ----
(check "numerator 0.5" (numerator 0.5) 1.0)
(check "denominator 0.5" (denominator 0.5) 2.0)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Arithmetic coverage tests failed" fail))
