;;; Phase 4: Numeric Tower (flonums / inexact numbers)
(import (scheme base) (scheme inexact) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "numeric")

;; --- Float literals ---
(test-approximate "3.14" 3.14 3.14 0.0001)
(test-approximate "0.5" 0.5 0.5 0.0001)
(test-approximate ".5" 0.5 .5 0.0001)
(test-approximate "1e10" 1e10 1e10 1.0)
(test-approximate "2.5e2" 250.0 2.5e2 0.0001)
(test-approximate "-1.5" -1.5 -1.5 0.0001)

;; --- Special float values ---
(test-assert "+inf.0" (infinite? +inf.0))
(test-assert "-inf.0" (infinite? -inf.0))
(test-assert "+nan.0" (nan? +nan.0))

;; --- Mixed arithmetic ---
(test-approximate "(+ 1 2.0)" 3.0 (+ 1 2.0) 0.0001)
(test-eqv "(+ 1 2 3)" 6 (+ 1 2 3))
(test-approximate "(* 2 3.5)" 7.0 (* 2 3.5) 0.0001)
(test-approximate "(- 10.0 3)" 7.0 (- 10.0 3) 0.0001)
(test-approximate "(- 5.0)" -5.0 (- 5.0) 0.0001)

;; --- Division ---
(test-eqv "(/ 10 2)" 5 (/ 10 2))
(test-equal "(/ 10 3)" 10/3 (/ 10 3))
(test-equal "(/ 1 3)" 1/3 (/ 1 3))
(test-equal "(/ 4)" 1/4 (/ 4))
(test-approximate "(/ 6.0 2.0)" 3.0 (/ 6.0 2.0) 0.0001)

;; --- Rounding ---
(test-approximate "(floor 3.7)" 3.0 (floor 3.7) 0.0001)
(test-approximate "(ceiling 3.2)" 4.0 (ceiling 3.2) 0.0001)
(test-approximate "(truncate -3.7)" -3.0 (truncate -3.7) 0.0001)
(test-approximate "(round 3.5)" 4.0 (round 3.5) 0.0001)
(test-eqv "(floor 42)" 42 (floor 42))

;; --- Exactness ---
(test-eqv "exact? 42" #t (exact? 42))
(test-eqv "inexact? 3.14" #t (inexact? 3.14))
(test-eqv "exact? 3.14" #f (exact? 3.14))
(test-eqv "inexact? 42" #f (inexact? 42))
(test-eqv "exact 3.0" 3 (exact 3.0))
(test-approximate "inexact 42" 42.0 (inexact 42) 0.0001)
(test-eqv "exact-integer? 42" #t (exact-integer? 42))
(test-eqv "exact-integer? 3.0" #f (exact-integer? 3.0))

;; --- Type predicates ---
(test-eqv "number? 3.14" #t (number? 3.14))
(test-eqv "integer? 3.0" #t (integer? 3.0))
(test-eqv "integer? 3.5" #f (integer? 3.5))
(test-eqv "real? 3.14" #t (real? 3.14))
(test-eqv "zero? 0.0" #t (zero? 0.0))
(test-eqv "positive? 1.5" #t (positive? 1.5))
(test-eqv "negative? -2.3" #t (negative? -2.3))

;; --- Comparisons with mixed types ---
(test-eqv "(= 1 1.0)" #t (= 1 1.0))
(test-eqv "(< 1 2.5)" #t (< 1 2.5))
(test-eqv "(> 3.5 2)" #t (> 3.5 2))
(test-eqv "(<= 1 1.0)" #t (<= 1 1.0))
(test-eqv "(>= 2.0 2)" #t (>= 2.0 2))

;; --- Powers and roots ---
(test-approximate "(sqrt 4)" 2.0 (sqrt 4) 0.0001)
(test-approximate "(sqrt 2.0)" 1.41421356 (sqrt 2.0) 0.0001)
(test-eqv "(expt 2 10)" 1024 (expt 2 10))
(test-eqv "(square 5)" 25 (square 5))
(test-approximate "(square 2.5)" 6.25 (square 2.5) 0.0001)

;; --- Trigonometry ---
(test-approximate "(sin 0)" 0.0 (sin 0) 0.0001)
(test-approximate "(cos 0)" 1.0 (cos 0) 0.0001)
(test-approximate "(atan 1.0)" 0.7853981 (atan 1.0) 0.0001)

;; --- Exp/Log ---
(test-approximate "(exp 0)" 1.0 (exp 0) 0.0001)
(test-approximate "(log 1)" 0.0 (log 1) 0.0001)

;; --- Float predicates ---
(test-eqv "finite? 1" #t (finite? 1))
(test-eqv "infinite? +inf.0" #t (infinite? +inf.0))
(test-eqv "nan? +nan.0" #t (nan? +nan.0))
(test-eqv "finite? +inf.0" #f (finite? +inf.0))

;; --- GCD/LCM ---
(test-eqv "(gcd 32 -36)" 4 (gcd 32 -36))
(test-eqv "(lcm 4 6)" 12 (lcm 4 6))
(test-eqv "(gcd)" 0 (gcd))
(test-eqv "(lcm)" 1 (lcm))

;; --- Even/Odd ---
(test-eqv "even? 4" #t (even? 4))
(test-eqv "odd? 3" #t (odd? 3))
(test-eqv "even? 5" #f (even? 5))
(test-eqv "odd? 4" #f (odd? 4))

;; --- string->number ---
(test-eqv "(string->number \"42\")" 42 (string->number "42"))
(test-approximate "(string->number \"3.14\")" 3.14 (string->number "3.14") 0.0001)
(test-eqv "(string->number \"hello\")" #f (string->number "hello"))
(test-assert "(string->number \"+inf.0\")" (infinite? (string->number "+inf.0")))

;; --- number->string ---
(test-equal "(number->string 42)" "42" (number->string 42))
(test-equal "(number->string 3.14)" "3.14" (number->string 3.14))
(test-equal "(number->string +inf.0)" "+inf.0" (number->string +inf.0))

;; --- abs with flonum ---
(test-approximate "(abs -3.5)" 3.5 (abs -3.5) 0.0001)
(test-approximate "(abs 3.5)" 3.5 (abs 3.5) 0.0001)

;; --- min/max with flonum ---
(test-approximate "(min 1 2.5 0.5)" 0.5 (min 1 2.5 0.5) 0.0001)
(test-approximate "(max 1 2.5 0.5)" 2.5 (max 1 2.5 0.5) 0.0001)

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "numeric")
(if (> %test-fail-count 0) (exit 1))
