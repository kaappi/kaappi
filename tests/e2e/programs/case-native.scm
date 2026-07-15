; case: multiple datums per clause, symbols, else
(define (classify n)
  (case n
    ((0 2 4 6 8) 'even-digit)
    ((1 3 5 7 9) 'odd-digit)
    (else 'big)))
(for-each (lambda (n) (display (classify n)) (display " ")) '(4 7 42))
(newline)
(display (case (string->symbol "b")
          ((a) 1) ((b) 2) (else 0)))
(newline)
