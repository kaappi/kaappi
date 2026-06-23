;;; SRFI 197 — Pipeline Operators
(define-library (srfi 197)
  (import (scheme base))
  (export chain chain-and chain-when chain-lambda)
  (begin

    (define-syntax chain
      (syntax-rules ()
        ((_ initial) initial)
        ((_ initial (proc args ...) rest ...)
         (chain (proc initial args ...) rest ...))
        ((_ initial proc rest ...)
         (chain (proc initial) rest ...))))

    (define-syntax chain-and
      (syntax-rules ()
        ((_ initial) initial)
        ((_ initial step rest ...)
         (let ((v initial))
           (and v (chain-and (chain v step) rest ...))))))

    (define-syntax chain-when
      (syntax-rules ()
        ((_ initial) initial)
        ((_ initial (pred? (proc args ...)) rest ...)
         (let ((v initial))
           (chain-when (if (pred? v) (proc v args ...) v) rest ...)))
        ((_ initial (pred? proc) rest ...)
         (let ((v initial))
           (chain-when (if (pred? v) (proc v) v) rest ...)))))

    (define-syntax chain-lambda
      (syntax-rules ()
        ((_ steps ...)
         (lambda (v) (chain v steps ...)))))))
