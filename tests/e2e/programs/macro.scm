(import (scheme base) (scheme write))
(define-syntax my-when
  (syntax-rules ()
    ((_ test body ...)
     (if test (begin body ...)))))
(my-when #t (display 42))
(newline)
