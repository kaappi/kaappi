(import (srfi 1))
(display (fold + 0 '(1 2 3 4 5)))     ; 15
(newline)
(display (filter even? '(1 2 3 4 5)))  ; (2 4)
(newline)
(display (find even? '(1 3 5 8 9)))    ; 8
(newline)
(display (any even? '(1 3 5)))          ; #f
(newline)
(display (iota 5))                      ; (0 1 2 3 4)
(newline)
(display (take '(a b c d) 2))           ; (a b)
(newline)
(display (drop '(a b c d) 2))           ; (c d)
(newline)
