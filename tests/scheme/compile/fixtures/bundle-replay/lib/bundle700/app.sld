;; Top library depending on both — the nested load the preamble replay must
;; survive (kaappi#700).
(define-library (bundle700 app)
  (import (scheme base) (bundle700 util) (bundle700 math))
  (export run-app)
  (begin (define (run-app n) (+ (quad n) (sq n)))))
