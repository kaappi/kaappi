;; case expression tests
(display (case (+ 1 1)
  ((1) 'one)
  ((2) 'two)
  ((3) 'three)))
(newline)

(display (case 'b
  ((a) 1)
  ((b c) 2)
  (else 3)))
(newline)
