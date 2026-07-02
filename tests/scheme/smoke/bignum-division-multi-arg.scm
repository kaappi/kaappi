;; Regression test for #739: (/ bignum bignum bignum) stops after first
;; non-exact division, ignoring remaining arguments.

(import (scheme base) (scheme write))

;; (/ 2^100 3 7) should be 2^100/21, not 2^100/3
(let ((result (/ (expt 2 100) 3 7)))
  (unless (and (exact? result)
               (= (denominator result) 21))
    (display "FAIL: (/ (expt 2 100) 3 7) denominator should be 21, got ")
    (display (denominator result))
    (newline)
    (exit 1)))

;; (/ 60 3 4) = 5 (exact division through all args)
(let ((result (/ (expt 2 60) (expt 2 20) (expt 2 10))))
  (unless (= result (expt 2 30))
    (display "FAIL: (/ 2^60 2^20 2^10) should be 2^30, got ")
    (display result)
    (newline)
    (exit 1)))

(display "OK")
(newline)
