(import (scheme base) (scheme write))
(define (my-len lst)
  (if (null? lst) 0
      (+ 1 (my-len (cdr lst)))))
(display (my-len '(1 2 3 4 5)))
(newline)
