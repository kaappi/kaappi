;; Regression test for #417: number->string ignores radix for bignums

(import (scheme base) (scheme write))

;; 2^64 in hex should be "10000000000000000"
(unless (string=? (number->string (expt 2 64) 16) "10000000000000000")
  (error "bignum hex failed" (number->string (expt 2 64) 16)))

;; 2^64 in binary should be 1 followed by 64 zeros
(unless (string=? (number->string (expt 2 64) 2)
                  "10000000000000000000000000000000000000000000000000000000000000000")
  (error "bignum binary failed"))

;; Negative bignum in hex
(unless (string=? (number->string (- (expt 2 64)) 16) "-10000000000000000")
  (error "negative bignum hex failed"))

;; Octal
(unless (string=? (number->string (expt 2 64) 8) "2000000000000000000000")
  (error "bignum octal failed"))

;; Decimal (default) still works
(unless (string=? (number->string (expt 2 64)) "18446744073709551616")
  (error "bignum decimal failed"))

(display "PASS")
(newline)
