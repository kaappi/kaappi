(define-library (srfi 222)
  (import (scheme base))
  (export make-compound compound? compound-subobjects
          compound-length compound-ref)
  (begin
    (define-record-type <compound>
      (make-compound-record subobjects)
      compound?
      (subobjects compound-subobjects))

    (define (make-compound . subobjects)
      (make-compound-record subobjects))

    (define (compound-length obj)
      (if (compound? obj)
          (length (compound-subobjects obj))
          1))

    (define (compound-ref obj k)
      (if (compound? obj)
          (list-ref (compound-subobjects obj) k)
          (if (= k 0)
              obj
              (error "compound-ref: index out of range" k))))))
