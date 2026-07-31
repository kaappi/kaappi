;; Middle library depending on util (kaappi#700).
(define-library (bundle700 math)
  (import (scheme base) (bundle700 util))
  (export quad)
  (begin (define (quad x) (double (double x)))))
