(define-library (badlib dep)
  (import (scheme base) (srfi 999))
  (export dummy)
  (begin (define (dummy) #t)))
