; Inline fixnum fast paths for + - * < = null? (#1493), plus the runtime
; slow-path fallbacks they must defer to: overflow out of the i48 fixnum range
; (bignum promotion), non-fixnum operands (flonum, rational), and negative
; values (which exercise sign-extension in the < ordering path). The native
; binary's output must match the interpreter exactly.

; Fixnum fast paths
(display (+ 3 4)) (newline)            ; 7
(display (- 10 3)) (newline)           ; 7
(display (* 6 7)) (newline)            ; 42
(display (+ -5 2)) (newline)           ; -3
(display (* -4 -3)) (newline)          ; 12

; Comparisons, including negatives (sign-extension)
(display (< 2 5)) (newline)            ; #t
(display (< -3 -1)) (newline)          ; #t
(display (< -1 -3)) (newline)          ; #f
(display (= 7 7)) (newline)            ; #t
(display (= -4 -4)) (newline)          ; #t

; null?
(display (null? '())) (newline)        ; #t
(display (null? '(1))) (newline)       ; #f
(display (null? 5)) (newline)          ; #f

; Overflow → bignum promotion (i48 max is 140737488355327)
(display (* 1000000000 1000000000)) (newline)   ; 1000000000000000000
(display (+ 140737488355327 1)) (newline)       ; 140737488355328

; Non-fixnum operands → runtime fallback
(display (+ 1.5 2.5)) (newline)        ; 4.0
(display (< 1.5 2.5)) (newline)        ; #t
(display (= 2.0 2)) (newline)          ; #t
(display (+ 1/3 1/6)) (newline)        ; 1/2

; Recursion that leans on the inline fast paths in a hot loop
(define (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(display (fib 20)) (newline)           ; 6765
