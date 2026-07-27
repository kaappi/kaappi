;; Fixture for #1718: exports a `lambda`-shadowing macro whose expansion
;; does not reproduce its input unchanged (wraps the body in `begin`).
;; Importing this must not corrupt compilation of unrelated libraries
;; loaded afterward in the same program.
(define-library (lib1718 shadow)
  (import (scheme base))
  (export lambda)
  (begin
    (define-syntax lambda
      (syntax-rules ()
        ((_ formals body1 body2 ...)
         (lambda formals (begin body1 body2 ...)))))))
