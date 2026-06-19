(define-library (srfi 166 pretty)
  (import (scheme base) (scheme write) (srfi 166))
  (export pretty pretty-shared pretty-simply)
  (begin

    (define (pretty obj)
      (lambda (st)
        (let ((p (open-output-string)))
          (write obj p)
          ((displayed (get-output-string p)) st))))

    (define pretty-shared pretty)
    (define pretty-simply pretty)

    ))
