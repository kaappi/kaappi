;; Regression test for #858: numerator/denominator on flonums must return
;; the exact dyadic fraction, not a decimal approximation.

(let ((x 3.141592653589793))
  (display (= x (/ (numerator x) (denominator x)))))
(newline)

(display (= (denominator 0.3) (denominator (exact 0.3))))
(newline)
