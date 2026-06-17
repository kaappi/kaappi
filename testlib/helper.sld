(define-library (testlib helper)
  (import (scheme base))
  (export double triple)
  (begin
    (define (double x) (* x 2))
    (define (triple x) (* x 3))))
