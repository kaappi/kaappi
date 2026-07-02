;; Regression test for #861: GC safety in primitives_numeric.zig
;; Exercises functions that had unrooted intermediate values across allocations.

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check desc val expected)
  (if (equal? val expected)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display desc)
      (display " got ") (write val)
      (display " expected ") (write expected) (newline))))

;; exactFn: numerator bignum unrooted across denominator allocation
(check "exact 0.7" (exact 0.7) 3152519739159347/4503599627370496)
(check "exact 0.1" (exact 0.1) 3602879701896397/36028797018963968)
(check "exact 0.3" (exact 0.3) 5404319552844595/18014398509481984)
(check "exact -0.7" (exact -0.7) -3152519739159347/4503599627370496)

;; exact on complex
(check "exact 1.0+0.0i" (exact 1.0+0.0i) 1)

;; rationalFloor: q unrooted across remainder
(check "floor 7/3" (floor 7/3) 2)
(check "floor -7/3" (floor -7/3) -3)
(check "floor 1/1" (floor 1/1) 1)

;; rationalCeiling: q unrooted across remainder
(check "ceiling 7/3" (ceiling 7/3) 3)
(check "ceiling -7/3" (ceiling -7/3) -2)

;; rationalRound: q and rem unrooted across absVal/mul
(check "round 7/2" (round 7/2) 4)
(check "round 5/2" (round 5/2) 2)
(check "round -7/2" (round -7/2) -4)
(check "round 3/2" (round 3/2) 2)

;; exptFn rational: num_pow unrooted across second expt
(check "expt 2/3 2" (expt 2/3 2) 4/9)
(check "expt 2/3 -1" (expt 2/3 -1) 3/2)
(check "expt 3/4 3" (expt 3/4 3) 27/64)

;; squareFn rational: num_sq unrooted across den_sq
(check "square 2/3" (square 2/3) 4/9)
(check "square 5/7" (square 5/7) 25/49)

;; exactIntegerSqrt: s/s2/s1/s1_sq unrooted in Newton loop
(let-values (((s r) (exact-integer-sqrt 25)))
  (check "exact-integer-sqrt 25 root" s 5)
  (check "exact-integer-sqrt 25 rem" r 0))
(let-values (((s r) (exact-integer-sqrt 26)))
  (check "exact-integer-sqrt 26 root" s 5)
  (check "exact-integer-sqrt 26 rem" r 1))
(let-values (((s r) (exact-integer-sqrt 0)))
  (check "exact-integer-sqrt 0 root" s 0)
  (check "exact-integer-sqrt 0 rem" r 0))

;; floorQuotient bignum: q unrooted across remainder
(check "floor-quotient 7 3" (floor-quotient 7 3) 2)
(check "floor-quotient -7 3" (floor-quotient -7 3) -3)
(check "floor-quotient 7 -3" (floor-quotient 7 -3) -3)

;; floorRemainder bignum: rem unrooted across add
(check "floor-remainder 7 3" (floor-remainder 7 3) 1)
(check "floor-remainder -7 3" (floor-remainder -7 3) 2)

;; floor/ and truncate/: q_val/r_val unrooted across allocMultipleValues
(let-values (((q r) (floor/ 7 3)))
  (check "floor/ 7 3 q" q 2)
  (check "floor/ 7 3 r" r 1))
(let-values (((q r) (truncate/ 7 3)))
  (check "truncate/ 7 3 q" q 2)
  (check "truncate/ 7 3 r" r 1))
(let-values (((q r) (floor/ -7 3)))
  (check "floor/ -7 3 q" q -3)
  (check "floor/ -7 3 r" r 2))

;; Hammer exact 0.7 in a loop to catch intermittent GC corruption
(define e07 (exact 0.7))
(let loop ((i 0))
  (when (< i 5000)
    (let ((e (exact 0.7)))
      (unless (equal? e e07)
        (set! fail (+ fail 1))
        (display "FAIL: exact 0.7 loop iter ") (display i)
        (display " got ") (write e) (newline)))
    (loop (+ i 1))))
(set! pass (+ pass 1))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
