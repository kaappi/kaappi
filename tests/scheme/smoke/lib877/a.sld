;; Fixture for #877: exports macro `tag` expanding to 'from-a.
(define-library (lib877 a)
  (import (scheme base))
  (export tag)
  (begin
    (define-syntax tag (syntax-rules () ((_) 'from-a)))))
