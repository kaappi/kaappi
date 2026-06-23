;;; SRFI 17 — Generalized set!
(define-library (srfi 17)
  (import (scheme base))
  (export setter getter-with-setter)
  (begin

    (define setters '())

    (define (setter proc)
      (let ((entry (assq proc setters)))
        (if entry (cdr entry)
            (error "no setter defined for procedure" proc))))

    (define (getter-with-setter getter setter-proc)
      (set! setters (cons (cons getter setter-proc) setters))
      getter)))
