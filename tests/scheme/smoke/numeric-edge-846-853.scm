;; Regression tests for #846 (exact/numerator/denominator abort on 2^63)
;; and #853 (string->number raises OutOfMemory for bignum rationals)

;; #846: exact of 2^63 must not panic
(display (= (exact (expt 2.0 63)) (expt 2 63)))
(newline)

;; #853: string->number with bignum rational components
(display (= (string->number "123456789012345678901234567890/3")
             41152263004115226300411522630))
(newline)
(display (rational? (string->number "3/123456789012345678901234567890")))
(newline)
(display (eq? (string->number "bad/input") #f))
(newline)
