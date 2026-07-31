;; Leaf library (kaappi#703).
(define-library (bundle703 util)
  (import (scheme base))
  (export greet)
  (begin (define (greet name) (string-append "Hello, " name "!"))))
