(define-library (srfi 145)
  (import (scheme base))
  (export assume)
  (begin
    (define-syntax assume
      (syntax-rules ()
        ((assume expression message ...)
         (or expression
             (error "assumption violated" 'expression message ...)))))))
