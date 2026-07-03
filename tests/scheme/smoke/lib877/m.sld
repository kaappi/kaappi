;; Fixture for #877: a library with a PRIVATE (unexported) macro that is
;; used by an exported procedure. The macro must not leak to importers.
(define-library (lib877 m)
  (import (scheme base))
  (export public-f)
  (begin
    (define-syntax private-mac
      (syntax-rules () ((_ x) (list 'private x))))
    (define (public-f) (private-mac 1))))
