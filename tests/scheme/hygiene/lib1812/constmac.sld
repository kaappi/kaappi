;; Fixture for #1812: exports `cm`, whose expansion references the
;; library-internal (unexported) non-procedure value `k`. Covers the
;; non-procedure half of the bug: the old "VOID sentinel" protection only
;; guarded a free reference against use-site LEXICAL (let/lambda) shadowing,
;; not against a genuine top-level redefinition of the same name.
(define-library (lib1812 constmac)
  (import (scheme base))
  (export cm)
  (begin
    (define k 100)
    (define-syntax cm (syntax-rules () ((_) k)))))
