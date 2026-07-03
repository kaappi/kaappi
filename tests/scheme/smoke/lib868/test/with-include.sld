(define-library (test with-include)
  (export included-value)
  (begin
    (include "incbody.scm")))
