;; Test SRFI-69 extra procedures

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 69))

(test-begin "srfi69-extras")

(define ht (make-hash-table))
(hash-table-set! ht "key" 42)

;; hash-table-equivalence-function returns a procedure
(test-assert "hash-table-equivalence-function returns a procedure"
             (procedure? (hash-table-equivalence-function ht)))

;; hash-table-hash-function returns a procedure
(test-assert "hash-table-hash-function returns a procedure"
             (procedure? (hash-table-hash-function ht)))

;; The equivalence function should be equal?
(let ((equiv (hash-table-equivalence-function ht)))
  (test-assert "the default equivalence compares strings by content"
               (equiv "hello" "hello"))
  (test-assert "the default equivalence separates different strings"
               (not (equiv "hello" "goodbye"))))

;; The hash function should work
(let ((h (hash-table-hash-function ht)))
  (test-assert "the hash function returns a number" (number? (h "test")))
  (test-assert "the hash function agrees with itself" (= (h "test") (h "test"))))

(let ((runner (test-runner-current)))
  (test-end "srfi69-extras")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
