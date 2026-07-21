(define-library (srfi 190)
  (import (scheme base) (srfi 158))
  (export coroutine-generator define-coroutine-generator)
  (begin
    (define-syntax coroutine-generator
      (syntax-rules ()
        ((_ body ...)
         (make-coroutine-generator
           (lambda (yield) body ...)))))

    (define-syntax define-coroutine-generator
      (syntax-rules ()
        ((_ (name . formals) body ...)
         (define (name . formals)
           (coroutine-generator body ...)))
        ((_ name body ...)
         (define name (coroutine-generator body ...)))))))
