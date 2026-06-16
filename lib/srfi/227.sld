(define-library (srfi 227)
  (import (scheme base) (scheme case-lambda))
  (export opt-lambda opt*-lambda let-optionals let-optionals*)
  (begin
    (define-syntax opt-lambda
      (syntax-rules ()
        ((opt-lambda ((name default)) body ...)
         (case-lambda
           (() (let ((name default)) body ...))
           ((name) body ...)))
        ((opt-lambda ((n1 d1) (n2 d2)) body ...)
         (case-lambda
           (() (let ((n1 d1) (n2 d2)) body ...))
           ((n1) (let ((n2 d2)) body ...))
           ((n1 n2) body ...)))
        ((opt-lambda (req (name default)) body ...)
         (case-lambda
           ((req) (let ((name default)) body ...))
           ((req name) body ...)))
        ((opt-lambda (r1 (n1 d1) (n2 d2)) body ...)
         (case-lambda
           ((r1) (let ((n1 d1) (n2 d2)) body ...))
           ((r1 n1) (let ((n2 d2)) body ...))
           ((r1 n1 n2) body ...)))
        ((opt-lambda (r1 r2 (n1 d1)) body ...)
         (case-lambda
           ((r1 r2) (let ((n1 d1)) body ...))
           ((r1 r2 n1) body ...)))
        ((opt-lambda formals body ...)
         (lambda formals body ...))))

    (define-syntax opt*-lambda
      (syntax-rules ()
        ((opt*-lambda formals body ...)
         (opt-lambda formals body ...))))

    (define-syntax let-optionals
      (syntax-rules ()
        ((let-optionals expr ((name default) ...) body ...)
         (apply (opt-lambda ((name default) ...) body ...) expr))))

    (define-syntax let-optionals*
      (syntax-rules ()
        ((let-optionals* expr ((name default) ...) body ...)
         (apply (opt*-lambda ((name default) ...) body ...) expr))))))
