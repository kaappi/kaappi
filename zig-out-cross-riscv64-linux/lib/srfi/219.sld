(define-library (srfi 219)
  (import (scheme base))
  (export define)
  (begin
    (define-syntax define
      (syntax-rules ()
        ((define ((name . outer-args) . args) . body)
         (define (name . outer-args) (lambda args . body)))
        ((define (name . args) . body)
         (define name (lambda args . body)))
        ((define name expr)
         (define name expr))))))
