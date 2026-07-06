;; Regression test for #560: define-record-type in body contexts
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "560-record-body")

;;; let body
(test-equal "record in let body"
  42
  (let ()
    (define-record-type pt (make-pt x) pt? (x get-x))
    (get-x (make-pt 42))))

;;; lambda body
(test-equal "record in lambda body"
  7
  ((lambda ()
     (define-record-type lb (mk-lb v) lb? (v lb-v))
     (lb-v (mk-lb 7)))))

;;; multiple fields
(test-equal "record with multiple fields in body"
  '(1 2)
  (let ()
    (define-record-type pair2 (mk a b) pair2? (a get-a) (b get-b))
    (let ((p (mk 1 2)))
      (list (get-a p) (get-b p)))))

;;; mutator in body
(test-equal "record with mutator in body"
  99
  (let ()
    (define-record-type cell (mk-cell v) cell? (v cell-val set-cell-val!))
    (let ((c (mk-cell 0)))
      (set-cell-val! c 99)
      (cell-val c))))

;;; predicate in body
(test-assert "record predicate in body"
  (let ()
    (define-record-type tag (mk-tag) tag?)
    (tag? (mk-tag))))

(test-assert "record predicate negative"
  (let ()
    (define-record-type tag2 (mk-tag2) tag2?)
    (not (tag2? 42))))

;;; nested let: inner record type does not leak
(test-equal "nested records are independent"
  '(10 20)
  (let ()
    (define-record-type outer (mk-o v) outer? (v o-v))
    (let ()
      (define-record-type inner (mk-i v) inner? (v i-v))
      (list (o-v (mk-o 10)) (i-v (mk-i 20))))))

;;; generative pattern: fresh record type per call
(test-assert "generative record types are distinct"
  (let ()
    (define (make-fresh)
      (define-record-type gen (mk-gen) gen?)
      (cons mk-gen gen?))
    (let ((a (make-fresh))
          (b (make-fresh)))
      (not ((cdr b) ((car a)))))))

;;; record with define-syntax sibling in body
(test-equal "record with define-syntax in body"
  5
  (let ()
    (define-record-type ds-rec (mk-ds v) ds-rec? (v ds-val))
    (define-syntax ds-get
      (syntax-rules ()
        ((_ r) (ds-val r))))
    (ds-get (mk-ds 5))))

;;; constructor field order differs from field spec order
(test-equal "constructor field reordering in body"
  '(2 1)
  (let ()
    (define-record-type swapped (mk-sw b a) swapped? (a sw-a) (b sw-b))
    (let ((s (mk-sw 1 2)))
      (list (sw-a s) (sw-b s)))))

;;; letrec body
(test-equal "record in letrec body"
  3
  (letrec ((f (lambda (x) x)))
    (define-record-type lr (mk-lr v) lr? (v lr-v))
    (lr-v (mk-lr (f 3)))))

(let ((runner (test-runner-current)))
  (test-end "560-record-body")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
