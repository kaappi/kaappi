;; Regression test for #430: number->string ignores radix for rationals

(import (scheme base) (scheme write))

(unless (string=? (number->string 255/256 16) "ff/100")
  (error "rational hex failed" (number->string 255/256 16)))

(unless (string=? (number->string 10/3 2) "1010/11")
  (error "rational binary failed" (number->string 10/3 2)))

(unless (string=? (number->string 1/2 16) "1/2")
  (error "rational hex simple failed"))

;; Decimal (default) still works
(unless (string=? (number->string 1/2) "1/2")
  (error "rational decimal failed"))

(unless (string=? (number->string 7/8 8) "7/10")
  (error "rational octal failed"))

(display "PASS")
(newline)
