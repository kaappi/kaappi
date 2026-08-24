;; Regression test for #2293: equal? recurses into record fields, so two
;; distinct instances of the same record type with equal? fields are equal?.
;; eq?/eqv? stay identity-based (R7RS 6.1 requires that; the equal? behavior
;; is a permitted extension under the "all other cases" clause).
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "record-equal-2293")

(define-record-type point (make-point x y) point? (x point-x) (y point-y))
(define-record-type other (make-other x)   other? (x other-x))

;; The headline case from the Reddit report.
(test-assert "distinct-but-equal records are equal?"
  (equal? (make-point 1 2) (make-point 1 2)))

;; eq?/eqv? must remain identity-based.
(test-assert "eqv? on distinct records is #f"
  (not (eqv? (make-point 1 2) (make-point 1 2))))
(test-assert "eq? on distinct records is #f"
  (not (eq? (make-point 1 2) (make-point 1 2))))

;; A record is equal? to itself.
(test-assert "record equal? to itself"
  (let ((p (make-point 1 2))) (equal? p p)))

;; Differing fields are not equal?.
(test-assert "differing field values not equal?"
  (not (equal? (make-point 1 2) (make-point 1 9))))

;; Fields compared recursively.
(test-assert "recursive field comparison (equal? contents)"
  (equal? (make-point (list 1 2) "ab") (make-point (list 1 2) "ab")))
(test-assert "recursive field comparison (differing contents)"
  (not (equal? (make-point (list 1 2) "ab") (make-point (list 1 2) "ac"))))

;; Records of different types are never equal?, even with equal fields.
(test-assert "different record types not equal?"
  (not (equal? (make-point 1 2) (make-other 1))))

;; Cyclic records must terminate (the cycle-tracking visited set handles it).
(define-record-type node (make-node v) node? (v node-v set-node-v!))
(test-assert "isomorphic cyclic records are equal?"
  (let ((x (make-node 1)) (y (make-node 1)))
    (set-node-v! x x)
    (set-node-v! y y)
    (equal? x y)))

(let ((runner (test-runner-current)))
  (test-end "record-equal-2293")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
