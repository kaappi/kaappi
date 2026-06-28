;; Regression test for #211: native arithmetic must handle
;; non-fixnum operands and fixnum overflow correctly.

;; Flonum operands
(display (+ 1 2.5))
(newline)
(display (+ 1.0 2.0))
(newline)
(display (- 5.5 2.5))
(newline)
(display (* 3 2.5))
(newline)

;; Flonum comparisons
(display (< 1 2.5))
(newline)
(display (= 2.0 2))
(newline)

;; Fixnum overflow (i48 max is 140737488355327)
(display (+ 140737488355327 1))
(newline)
(display (* 140737488355327 2))
(newline)
