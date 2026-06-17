(define-library (testlib with-include)
  (import (scheme base))
  (export quadruple)
  (include "testlib/included.scm"))
