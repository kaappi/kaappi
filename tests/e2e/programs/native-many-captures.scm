; #1498: a closure capturing more free variables than the old [16] free_vars
; buffer now compiles as a native closure. The inner lambda captures all 20 of
; make-summer's parameters as upvalues.
(define (make-summer a b c d e f g h i j k l m n o p q r s t)
  (lambda (x)
    (+ x a b c d e f g h i j k l m n o p q r s t)))
(define summer (make-summer 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20))
(display (summer 100))
(newline)
