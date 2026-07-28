;; Fixture for #1812: an er-macro-transformer macro whose expansion
;; references a library-internal (unexported) procedure via `rename`. ER
;; macros inherit the same hygiene hole syntax-rules macros do, since
;; `rename` is implemented on top of the same renameForHygiene mechanism.
(define-library (lib1812 ermac)
  (import (scheme base) (srfi 211 explicit-renaming))
  (export etw)
  (begin
    (define (helper3 x) (+ x 1000))
    (define-syntax etw
      (er-macro-transformer
       (lambda (form rename compare)
         (list (rename 'helper3) (cadr form)))))))
