;; SRFI 66 (octet vectors) tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi66.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 66))

(test-begin "srfi-66")

(test-equal #t (u8vector? (u8vector 1 2 3)))
(test-equal #f (u8vector? "not"))
(test-equal 3 (u8vector-length (make-u8vector 3 7)))
(test-equal '(7 7 7) (u8vector->list (make-u8vector 3 7)))
(test-equal '(1 2 3) (u8vector->list (list->u8vector '(1 2 3))))
(let ((v (u8vector 1 2 3)))
  (u8vector-set! v 0 9)
  (test-equal 9 (u8vector-ref v 0)))

(test-equal '(1 2 3) (u8vector->list (u8vector-copy (u8vector 1 2 3))))
(let ((a (u8vector 1 2 3)) (b (make-u8vector 3 0)))
  (u8vector-copy! a 1 b 0 2)
  (test-equal '(2 3 0) (u8vector->list b)))
;; overlapping regions within the same vector must also work.
(let ((v (u8vector 1 2 3 4 5)))
  (u8vector-copy! v 0 v 2 3)
  (test-equal '(1 2 1 2 3) (u8vector->list v)))

(test-equal #t (u8vector=? (u8vector 1 2 3) (u8vector 1 2 3)))
(test-equal #f (u8vector=? (u8vector 1 2 3) (u8vector 1 2 4)))
(test-equal #f (u8vector=? (u8vector 1 2) (u8vector 1 2 3)))

(test-equal -1 (u8vector-compare (u8vector 1 2) (u8vector 1 2 3)))
(test-equal 1 (u8vector-compare (u8vector 1 3) (u8vector 1 2)))
(test-equal 0 (u8vector-compare (u8vector 1 2) (u8vector 1 2)))
(test-equal 1 (u8vector-compare (u8vector 1 2 3) (u8vector 1 2)))

(let ((runner (test-runner-current)))
  (test-end "srfi-66")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
