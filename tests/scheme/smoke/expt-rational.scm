;; Regression test for #433: expt with exact rational base returns inexact

(import (scheme base) (scheme write))

;; Positive exponent
(unless (and (exact? (expt 1/2 3)) (= (expt 1/2 3) 1/8))
  (error "(expt 1/2 3) should be exact 1/8"))

(unless (and (exact? (expt 2/3 2)) (= (expt 2/3 2) 4/9))
  (error "(expt 2/3 2) should be exact 4/9"))

;; Negative exponent: (expt 1/2 -2) = (2/1)^2 = 4
(unless (and (exact? (expt 1/2 -2)) (= (expt 1/2 -2) 4))
  (error "(expt 1/2 -2) should be exact 4"))

;; (expt 2/3 -1) = 3/2
(unless (and (exact? (expt 2/3 -1)) (= (expt 2/3 -1) 3/2))
  (error "(expt 2/3 -1) should be exact 3/2"))

;; Zero exponent
(unless (= (expt 3/4 0) 1)
  (error "(expt 3/4 0) should be 1"))

;; Large exponent
(unless (exact? (expt 1/3 10))
  (error "(expt 1/3 10) should be exact"))

(display "PASS")
(newline)
