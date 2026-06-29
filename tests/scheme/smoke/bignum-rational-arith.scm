;; Regression test for #437:
;; toRationalParts must not treat bignums as zero.

(import (scheme base) (scheme write))

;; (- bignum rational) should not return (- 0 rational)
(let ((result (- (expt 2 60) 1/3)))
  (if (> result (expt 2 59))
      (display "PASS: (- 2^60 1/3) is large")
      (begin
        (display "FAIL: (- 2^60 1/3) returned ")
        (display result))))
(newline)

;; (/ bignum rational) should not return 0
(let ((result (/ (expt 2 60) 1/3)))
  (if (> result (expt 2 59))
      (display "PASS: (/ 2^60 1/3) is large")
      (begin
        (display "FAIL: (/ 2^60 1/3) returned ")
        (display result))))
(newline)

;; Sanity: (+ bignum rational) should still work
(let ((result (+ (expt 2 60) 1/3)))
  (if (> result (expt 2 59))
      (display "PASS: (+ 2^60 1/3) is large")
      (begin
        (display "FAIL: (+ 2^60 1/3) returned ")
        (display result))))
(newline)

;; Sanity: (* bignum rational) should still work
(let ((result (* (expt 2 60) 1/3)))
  (if (> result (expt 2 58))
      (display "PASS: (* 2^60 1/3) is large")
      (begin
        (display "FAIL: (* 2^60 1/3) returned ")
        (display result))))
(newline)
