(define-library (srfi 45)
  (import (scheme base) (scheme lazy))
  (export delay force delay-force make-promise promise? lazy eager)
  (begin
    (define-syntax lazy
      (syntax-rules ()
        ((lazy expr) (delay-force expr))))
    (define (eager x) (make-promise x))))
