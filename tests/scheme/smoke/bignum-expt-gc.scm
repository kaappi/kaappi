(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

;; expt with large bignums — squared base must survive GC
(check "7^20" (expt 7 20) 79792266297612001)
(check "10^30" (expt 10 30) 1000000000000000000000000000000)
(check "2^100" (expt 2 100) 1267650600228229401496703205376)
(check "3^50" (expt 3 50) 717897987691852588770249)
(check "(-2)^31" (expt -2 31) -2147483648)
(check "(-3)^19" (expt -3 19) -1162261467)

;; Allocate many objects to push GC threshold, then compute large expt
(define keep (make-vector 4000 #f))
(do ((i 0 (+ i 1))) ((= i 4000))
  (vector-set! keep i (list i)))

(check "7^100 after heap pressure"
  (expt 7 100)
  3234476509624757991344647769100216810857203198904625400933895331391691459636928060001)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "bignum expt GC tests failed" fail))
