;; Leaf library with no dependencies (kaappi#700).
(define-library (bundle700 util)
  (import (scheme base))
  (export double sq)
  (begin (define (double x) (* x 2)) (define (sq x) (* x x))))
