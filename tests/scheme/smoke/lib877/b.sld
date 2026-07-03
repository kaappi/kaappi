;; Fixture for #877: also defines a macro named `tag` (expanding to 'from-b)
;; but only exports the procedure `bfun`. Loading this library must not
;; clobber a `tag` macro imported from (lib877 a).
(define-library (lib877 b)
  (import (scheme base))
  (export tag bfun)
  (begin
    (define (bfun) 'bfun)
    (define-syntax tag (syntax-rules () ((_) 'from-b)))))
