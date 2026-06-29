;; Regression test for #443:
;; (* expr 0) optimization must not drop side effects from expr.

(import (scheme base) (scheme write))

;; (* side-effecting-expr 0) must still execute the side effect
(define output '())

(define (track! x)
  (set! output (cons x output))
  x)

(define r1 (* (track! 5) 0))
(if (and (= r1 0) (equal? output '(5)))
    (display "PASS: (* (track! 5) 0) preserves side effect")
    (begin
      (display "FAIL: r1=") (display r1)
      (display " output=") (display output)))
(newline)

;; (* 0 side-effecting-expr) must also preserve side effects
(set! output '())
(define r2 (* 0 (track! 7)))
(if (and (= r2 0) (equal? output '(7)))
    (display "PASS: (* 0 (track! 7)) preserves side effect")
    (begin
      (display "FAIL: r2=") (display r2)
      (display " output=") (display output)))
(newline)

;; Pure (* const 0) should still fold to 0
(define r3 (* 42 0))
(if (= r3 0)
    (display "PASS: (* 42 0) folds to 0")
    (begin (display "FAIL: r3=") (display r3)))
(newline)
