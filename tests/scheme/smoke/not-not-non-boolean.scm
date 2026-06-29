;; Regression test for #440:
;; (not (not X)) must return a boolean, not X itself.

(import (scheme base) (scheme write))

(define y (not (not "hello")))
(if (eq? y #t)
    (display "PASS: (not (not \"hello\")) is #t")
    (begin
      (display "FAIL: (not (not \"hello\")) returned ")
      (write y)))
(newline)

(define z (not (not (+ 1 2))))
(if (eq? z #t)
    (display "PASS: (not (not 3)) is #t")
    (begin
      (display "FAIL: (not (not 3)) returned ")
      (write z)))
(newline)

(define w (not (not #f)))
(if (eq? w #f)
    (display "PASS: (not (not #f)) is #f")
    (begin
      (display "FAIL: (not (not #f)) returned ")
      (write w)))
(newline)

(define v (not (not '())))
(if (eq? v #t)
    (display "PASS: (not (not '())) is #t")
    (begin
      (display "FAIL: (not (not '())) returned ")
      (write v)))
(newline)
