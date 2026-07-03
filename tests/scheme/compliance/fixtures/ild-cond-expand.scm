(export inner-x)
(cond-expand
  (else (begin (define inner-x 'from-cond-expand))))
