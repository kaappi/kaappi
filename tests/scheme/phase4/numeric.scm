;;; Phase 4: Numeric Tower (flonums / inexact numbers)

;; --- Float literals ---
(display "3.14 => ") (display 3.14) (newline)
(display "0.5 => ") (display 0.5) (newline)
(display ".5 => ") (display .5) (newline)
(display "1e10 => ") (display 1e10) (newline)
(display "2.5e2 => ") (display 2.5e2) (newline)
(display "-1.5 => ") (display -1.5) (newline)

;; --- Special float values ---
(display "+inf.0 => ") (display +inf.0) (newline)
(display "-inf.0 => ") (display -inf.0) (newline)
(display "+nan.0 => ") (display +nan.0) (newline)

;; --- Mixed arithmetic ---
(display "(+ 1 2.0) => ") (display (+ 1 2.0)) (newline)
(display "(+ 1 2 3) => ") (display (+ 1 2 3)) (newline)
(display "(* 2 3.5) => ") (display (* 2 3.5)) (newline)
(display "(- 10.0 3) => ") (display (- 10.0 3)) (newline)
(display "(- 5.0) => ") (display (- 5.0)) (newline)

;; --- Division ---
(display "(/ 10 2) => ") (display (/ 10 2)) (newline)
(display "(/ 10 3) => ") (display (/ 10 3)) (newline)
(display "(/ 1 3) => ") (display (/ 1 3)) (newline)
(display "(/ 4) => ") (display (/ 4)) (newline)
(display "(/ 6.0 2.0) => ") (display (/ 6.0 2.0)) (newline)

;; --- Rounding ---
(display "(floor 3.7) => ") (display (floor 3.7)) (newline)
(display "(ceiling 3.2) => ") (display (ceiling 3.2)) (newline)
(display "(truncate -3.7) => ") (display (truncate -3.7)) (newline)
(display "(round 3.5) => ") (display (round 3.5)) (newline)
(display "(floor 42) => ") (display (floor 42)) (newline)

;; --- Exactness ---
(display "(exact? 42) => ") (display (exact? 42)) (newline)
(display "(inexact? 3.14) => ") (display (inexact? 3.14)) (newline)
(display "(exact? 3.14) => ") (display (exact? 3.14)) (newline)
(display "(inexact? 42) => ") (display (inexact? 42)) (newline)
(display "(exact 3.0) => ") (display (exact 3.0)) (newline)
(display "(inexact 42) => ") (display (inexact 42)) (newline)
(display "(exact-integer? 42) => ") (display (exact-integer? 42)) (newline)
(display "(exact-integer? 3.0) => ") (display (exact-integer? 3.0)) (newline)

;; --- Type predicates ---
(display "(number? 3.14) => ") (display (number? 3.14)) (newline)
(display "(integer? 3.0) => ") (display (integer? 3.0)) (newline)
(display "(integer? 3.5) => ") (display (integer? 3.5)) (newline)
(display "(real? 3.14) => ") (display (real? 3.14)) (newline)
(display "(zero? 0.0) => ") (display (zero? 0.0)) (newline)
(display "(positive? 1.5) => ") (display (positive? 1.5)) (newline)
(display "(negative? -2.3) => ") (display (negative? -2.3)) (newline)

;; --- Comparisons with mixed types ---
(display "(= 1 1.0) => ") (display (= 1 1.0)) (newline)
(display "(< 1 2.5) => ") (display (< 1 2.5)) (newline)
(display "(> 3.5 2) => ") (display (> 3.5 2)) (newline)
(display "(<= 1 1.0) => ") (display (<= 1 1.0)) (newline)
(display "(>= 2.0 2) => ") (display (>= 2.0 2)) (newline)

;; --- Powers and roots ---
(display "(sqrt 4) => ") (display (sqrt 4)) (newline)
(display "(sqrt 2.0) => ") (display (sqrt 2.0)) (newline)
(display "(expt 2 10) => ") (display (expt 2 10)) (newline)
(display "(square 5) => ") (display (square 5)) (newline)
(display "(square 2.5) => ") (display (square 2.5)) (newline)

;; --- Trigonometry ---
(display "(sin 0) => ") (display (sin 0)) (newline)
(display "(cos 0) => ") (display (cos 0)) (newline)
(display "(atan 1.0) => ") (display (atan 1.0)) (newline)

;; --- Exp/Log ---
(display "(exp 0) => ") (display (exp 0)) (newline)
(display "(log 1) => ") (display (log 1)) (newline)

;; --- Float predicates ---
(display "(finite? 1) => ") (display (finite? 1)) (newline)
(display "(infinite? +inf.0) => ") (display (infinite? +inf.0)) (newline)
(display "(nan? +nan.0) => ") (display (nan? +nan.0)) (newline)
(display "(finite? +inf.0) => ") (display (finite? +inf.0)) (newline)

;; --- GCD/LCM ---
(display "(gcd 32 -36) => ") (display (gcd 32 -36)) (newline)
(display "(lcm 4 6) => ") (display (lcm 4 6)) (newline)
(display "(gcd) => ") (display (gcd)) (newline)
(display "(lcm) => ") (display (lcm)) (newline)

;; --- Even/Odd ---
(display "(even? 4) => ") (display (even? 4)) (newline)
(display "(odd? 3) => ") (display (odd? 3)) (newline)
(display "(even? 5) => ") (display (even? 5)) (newline)
(display "(odd? 4) => ") (display (odd? 4)) (newline)

;; --- string->number ---
(display "(string->number \"42\") => ") (display (string->number "42")) (newline)
(display "(string->number \"3.14\") => ") (display (string->number "3.14")) (newline)
(display "(string->number \"hello\") => ") (display (string->number "hello")) (newline)
(display "(string->number \"+inf.0\") => ") (display (string->number "+inf.0")) (newline)

;; --- number->string ---
(display "(number->string 42) => ") (display (number->string 42)) (newline)
(display "(number->string 3.14) => ") (display (number->string 3.14)) (newline)
(display "(number->string +inf.0) => ") (display (number->string +inf.0)) (newline)

;; --- abs with flonum ---
(display "(abs -3.5) => ") (display (abs -3.5)) (newline)
(display "(abs 3.5) => ") (display (abs 3.5)) (newline)

;; --- min/max with flonum ---
(display "(min 1 2.5 0.5) => ") (display (min 1 2.5 0.5)) (newline)
(display "(max 1 2.5 0.5) => ") (display (max 1 2.5 0.5)) (newline)

(display "All Phase 4 tests completed.") (newline)
