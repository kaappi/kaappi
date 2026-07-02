;; Regression test for #838 and #839: rational ops with bignum operands
;; must process all arguments, not return early after the first bignum.

(define big (expt 2 100))

;; #838: remaining args not dropped
(display (= (+ big 1/2) (/ (+ (* big 2) 1) 2)))
(newline)
(display (= (+ 1/2 big 10) (/ (+ (* big 2) 21) 2)))
(newline)
(display (= (* big 1/2) (expt 2 99)))
(newline)
(display (= (* 1/2 big 10) (* 5 big)))
(newline)

;; #839: bignum-first argument path
(display (= (- big 1/2) (/ (- (* big 2) 1) 2)))
(newline)
(display (= (/ big 2) (expt 2 99)))
(newline)
