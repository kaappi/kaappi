;; Regression test for #2293: equal? recurses into record fields, so two
;; distinct instances of the same record type with equal? fields are equal?.
;; eq?/eqv? stay identity-based (R7RS 6.1 requires that; the equal? behavior
;; is a permitted extension under the "all other cases" clause).
(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 69))

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

;; member/assoc default to equal? and share deepEqual, so they now find
;; records structurally — every equal? consumer moved together.
(test-assert "member finds a structurally-equal record"
  (pair? (member (make-point 1 2) (list (make-point 1 2)))))
(test-assert "assoc finds a structurally-equal record key"
  (pair? (assoc (make-point 1 2) (list (cons (make-point 1 2) 'v)))))

;; The hash/equality contract: deepEqual is structural on records, so valueHash
;; must be too — two equal? records have to hash alike, or a default SRFI 69
;; table (equal? + valueHash) silently loses record entries (kaappi#2293).
(test-assert "equal? records hash equal"
  (= (hash (make-point 1 2)) (hash (make-point 1 2))))

(test-assert "populated equal?-table round-trips structurally-equal record keys"
  (let ((ht (make-hash-table)))
    (do ((i 0 (+ i 1))) ((= i 200))
      (hash-table-set! ht (make-point i i) i))
    (let loop ((i 0) (ok #t))
      (if (= i 200)
          ok
          (loop (+ i 1)
                (and ok (= (hash-table-ref/default ht (make-point i i) -1) i)))))))

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
