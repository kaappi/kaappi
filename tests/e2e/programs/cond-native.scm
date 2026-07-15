; cond: else, ordinal dispatch, no-body clause, and => arrow
(define (sign n)
  (cond ((< n 0) 'neg)
        ((= n 0) 'zero)
        (else 'pos)))
(for-each (lambda (n) (display (sign n)) (display " ")) '(-2 0 7))
(newline)
; no-body clause returns the test value; => applies proc to the test value
(display (cond ((memv 3 '(1 2 3)) => car) (else 'none)))
(newline)
(display (cond ((assv 5 '((1 . a))) => cdr) (#f 1) (else 'fallthrough)))
(newline)
