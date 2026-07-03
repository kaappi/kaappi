;; Fixture for #877: imports a macro from another library and uses it in its
;; own body. This must keep working after macros stop leaking process-globally
;; (imported macros live in the importing library's environment).
(define-library (lib877 user)
  (import (scheme base) (lib877 a))
  (export use-tag)
  (begin
    (define (use-tag) (tag))))
