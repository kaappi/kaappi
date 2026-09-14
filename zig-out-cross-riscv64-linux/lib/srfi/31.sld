(define-library (srfi 31)
  (import (scheme base))
  (export rec)
  (begin
    (define-syntax rec
      (syntax-rules ()
        ((rec (name . formals) body ...)
         (letrec ((name (lambda formals body ...))) name))
        ((rec name expr)
         (letrec ((name expr)) name))))))
