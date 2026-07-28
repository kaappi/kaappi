;; Fixture for #1812: exports `tw`, whose expansion references the
;; library-internal (unexported) procedure `helper2`. Also exports
;; `self-check`, which calls `tw` from *within* the library body, so the
;; driver can confirm the fix doesn't change same-library macro-use
;; behavior.
(define-library (lib1812 srmac)
  (import (scheme base))
  (export tw self-check)
  (begin
    (define (helper2 x) (* x 2))
    (define-syntax tw (syntax-rules () ((_ e) (helper2 e))))
    (define (self-check) (tw 1))))
