(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; gcd: result must be non-negative, even at fixnum boundary
(check "gcd minInt48 0" (gcd -140737488355328 0) 140737488355328)
(check "gcd minInt48" (gcd -140737488355328) 140737488355328)
(check "gcd large" (gcd 140737488355328 2) 2)

;; lcm: must not truncate large results
(check "lcm large" (lcm 16777216 16777259) 281475698130944)
(check "lcm overflow" (lcm 100000000000 99999999999) 9999999999900000000000)
(check "lcm basic" (lcm 6 10) 30)
(check "lcm zero" (lcm 0 5) 0)

;; rational add: integer result past fixnum range
(check "rational+ overflow" (+ 1/3 2/3 140737488355327) 140737488355328)

;; rational mul: result past fixnum range
(check "rational* overflow" (* 3/2 2 70368744177665) 211106232532995)

;; rational sub: integer result past fixnum range
(check "rational- overflow" (- 2/3 -1/3 -140737488355327) 140737488355328)

;; rational div: integer result past fixnum range
(check "rational/ overflow" (/ 281474976710656 2) 140737488355328)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "arithmetic overflow tests failed" fail))
