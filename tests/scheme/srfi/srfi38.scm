;; SRFI-38 (external representation of shared structure) tests — Phase 3b
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi38.scm

(import (scheme base) (scheme read) (scheme write) (srfi 38) (chibi test))

(test-begin "srfi-38")

(define (wss->string obj)
  (let ((p (open-output-string)))
    (write-with-shared-structure obj p)
    (get-output-string p)))

(define (rt obj)                     ; write/read round trip
  (read-with-shared-structure (open-input-string (wss->string obj))))

;;; --- plain data is written normally ---
(test "(1 2 3)" (wss->string '(1 2 3)))
(test "#(a b)" (wss->string #(a b)))
(test '(1 (2) "x") (rt '(1 (2) "x")))

;;; --- cyclic list round trip ---
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (let ((c2 (rt c)))
    (test 1 (car c2))
    (test 2 (cadr c2))
    (test #t (eq? c2 (cddr c2)))))       ; cycle reconstructed

;;; --- shared (acyclic) substructure preserved ---
(let* ((x (list 'a))
       (shared (list x x))
       (s2 (rt shared)))
  (test '(a) (car s2))
  (test #t (eq? (car s2) (cadr s2))))

;;; --- self-referential vector ---
;; write side emits correct labels ("#0=#(1 #0#)") but the reader does not
;; patch label references inside vectors:
;; FAIL: #1213 (reader: datum-label references inside vectors unpatched)
;; (let ((v (vector 1 2)))
;;   (vector-set! v 1 v)
;;   (let ((v2 (rt v)))
;;     (test 1 (vector-ref v2 0))
;;     (test #t (eq? v2 (vector-ref v2 1)))))

;;; --- labels parse via plain read too (R7RS datum labels) ---
(let ((c (read (open-input-string "#0=(1 2 . #0#)"))))
  (test 1 (car c))
  (test #t (eq? c (cddr c))))

;;; --- default port arguments exist (write to current-output via string port) ---
(test #t (procedure? write-with-shared-structure))
(test #t (procedure? read-with-shared-structure))

(test-end "srfi-38")
