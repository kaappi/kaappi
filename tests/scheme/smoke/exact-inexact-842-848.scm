;; Regression tests for #842 and #848

;; #842: exact with dyadic denominator 2^47 must not produce negative denominator
(let ((x (exact (/ 3.0 (expt 2.0 47)))))
  (display (positive? x))
  (newline)
  (display (> (inexact x) 0))
  (newline))

;; #848: inexact on rationals with huge components must not return NaN
(display (= (inexact (/ (+ (expt 10 400) 1) (expt 10 399))) 10.0))
(newline)
(display (= (inexact (/ (+ (expt 2 2000) 1) (expt 2 2000))) 1.0))
(newline)
