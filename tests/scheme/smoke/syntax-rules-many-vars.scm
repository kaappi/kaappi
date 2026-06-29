;; Regression test for #279: syntax-rules with 17+ pattern variables
;; caused stack buffer overflow via @ptrCast mismatch (16 vs 64 elements).

(define-syntax many-vars
  (syntax-rules ()
    ((many-vars a b c d e f g h i j k l m n o p q)
     (+ a b c d e f g h i j k l m n o p q))))

(display (many-vars 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17))
(newline)
