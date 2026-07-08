;;; SRFI 61 — A more general cond clause
;;; Extends cond with (generator guard => receiver) clauses.
(define-library (srfi 61)
  (import (scheme base))
  (export cond)
  (begin
    (define-syntax cond
      (syntax-rules (=> else)
        ((cond (else expr1 expr2 ...))
         (begin expr1 expr2 ...))
        ((cond (generator guard => receiver) rest ...)
         (call-with-values (lambda () generator)
           (lambda args
             (if (apply guard args)
                 (apply receiver args)
                 (cond rest ...)))))
        ((cond (test => proc) rest ...)
         (let ((t test))
           (if t (proc t) (cond rest ...))))
        ((cond (test) rest ...)
         (or test (cond rest ...)))
        ((cond (test body1 body2 ...) rest ...)
         (if test (begin body1 body2 ...) (cond rest ...)))
        ((cond)
         (if #f #f))))))
