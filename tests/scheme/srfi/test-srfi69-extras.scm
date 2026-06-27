;; Test SRFI-69 extra procedures

(import (scheme base) (scheme write) (srfi 69))

(define ht (make-hash-table))
(hash-table-set! ht "key" 42)

;; hash-table-equivalence-function returns a procedure
(display (procedure? (hash-table-equivalence-function ht)))
(newline)
;; Expected: #t

;; hash-table-hash-function returns a procedure
(display (procedure? (hash-table-hash-function ht)))
(newline)
;; Expected: #t

;; The equivalence function should be equal?
(let ((equiv (hash-table-equivalence-function ht)))
  (display (equiv "hello" "hello")))
(newline)
;; Expected: #t

;; The hash function should work
(let ((h (hash-table-hash-function ht)))
  (display (number? (h "test"))))
(newline)
;; Expected: #t

(display "srfi69-extras-ok")
(newline)
