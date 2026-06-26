(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; exact of large integer-valued flonum (should not crash, must promote to bignum)
(check "exact 1e15" (exact 1e15) 1000000000000000)
(check "exact type" (integer? (exact 1e15)) #t)

;; exact of very large flonum (should not crash)
(check "exact 1e19 type" (number? (exact 1e19)) #t)

;; string->number of large integer (must not truncate)
(check "string->number large" (string->number "9000000000000000") 9000000000000000)
(check "string->number negative large" (string->number "-9000000000000000") -9000000000000000)
(check "string->number very large" (string->number "100000000000000000") 100000000000000000)

;; real-part of large exact complex (must not truncate)
(check "real-part large" (real-part (make-rectangular 1000000000000000 2)) 1000000000000000)

;; numerator should not crash on large flonum
(check "numerator finite" (number? (numerator 1e15)) #t)
(check "numerator very large" (number? (numerator 1e30)) #t)

;; floor/ceiling/truncate/round of flonum (should not crash for large values)
(check "floor large flonum" (floor 2.5e15) 2.5e15)
(check "round large flonum" (round 2.5e15) 2.5e15)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "numeric overflow tests failed" fail))
