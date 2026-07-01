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

;; Regression for #603: floor-quotient/truncate-quotient must promote to bignum
(check "truncate-quotient minInt÷-1" (truncate-quotient -140737488355328 -1) 140737488355328)
(check "floor-quotient minInt÷-1" (floor-quotient -140737488355328 -1) 140737488355328)
(check "truncate-quotient minInt÷-1 positive" (positive? (truncate-quotient -140737488355328 -1)) #t)
(check "floor-quotient minInt÷-1 positive" (positive? (floor-quotient -140737488355328 -1)) #t)

;; Regression for #610: rational literals with large num/den must not truncate
(check "rational literal large num" 200000000000000/3 200000000000000/3)
(check "rational literal large den" 1/140737488355328 1/140737488355328)
(check "rational large den positive" #t (positive? (denominator 1/140737488355328)))

;; Regression for #611: rationals with bignum fields must not produce garbage
(check "add bignum-field rational" #t (number? (+ (exact 0.1) 0)))
(check "mul bignum-field rational" #t (number? (* (exact 0.1) 1)))
(check "negate bignum-field rational" #t (negative? (- (exact 0.1))))
(check "compare bignum-field rational" #t (< (exact 0.1) 1))
(check "equality bignum-field rational" #t (= (exact 0.1) (exact 0.1)))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "numeric overflow tests failed" fail))
