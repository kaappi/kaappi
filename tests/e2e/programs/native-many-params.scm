; #1498: a function with more fixed parameters than the old [16] analysis
; buffer now compiles natively instead of silently falling back to the
; interpreter. 20 params exceeds every retired fixed-size limit.
(define (sum20 a b c d e f g h i j k l m n o p q r s t)
  (+ a b c d e f g h i j k l m n o p q r s t))
(display (sum20 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20))
(newline)
