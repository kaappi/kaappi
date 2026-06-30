;; Regression test for #606: deepCopyValue record_instance cycle guard
;; A cyclic record deep-copied across a thread boundary must not stack overflow.
(import (scheme base) (scheme write) (scheme process-context) (srfi 18))

(define-record-type node
  (make-node val next)
  node?
  (val node-val)
  (next node-next set-node-next!))

;; Create a cyclic record
(define n (make-node 42 #f))
(set-node-next! n n)

;; Deep-copy it via thread boundary
(define t (make-thread (lambda () (node-val (node-next n)))))
(thread-start! t)
(define result (thread-join! t))

(if (= result 42)
    (begin (display "all passed") (newline))
    (begin (display "FAIL: expected 42, got ") (display result) (newline) (exit 1)))
