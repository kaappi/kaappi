;;; Numeric gap compliance tests (R7RS 6.2)

;; floor-quotient, floor-remainder
(display (floor-quotient 7 3))     ; => 2
(newline)
(display (floor-remainder 7 3))    ; => 1
(newline)
(display (floor-quotient -7 3))    ; => -3
(newline)
(display (floor-remainder -7 3))   ; => 2
(newline)

;; truncate-quotient, truncate-remainder
(display (truncate-quotient 7 3))    ; => 2
(newline)
(display (truncate-remainder 7 3))   ; => 1
(newline)
(display (truncate-quotient -7 3))   ; => -2
(newline)
(display (truncate-remainder -7 3))  ; => -1
(newline)

;; numerator, denominator
(display (numerator 3))       ; => 3
(newline)
(display (denominator 3))     ; => 1
(newline)

;; exact->inexact, inexact->exact aliases
(display (exact->inexact 3))   ; => 3.0
(newline)
(display (inexact->exact 3.0)) ; => 3
(newline)

;; rationalize
(display (rationalize 3 1))    ; => 3
(newline)

;; features
(display (list? (features)))   ; => #t
(newline)
