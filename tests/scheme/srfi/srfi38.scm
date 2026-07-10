;; SRFI-38 (external representation of shared structure) tests — Phase 3b
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi38.scm

(import (scheme base) (scheme read) (scheme write) (srfi 38) (scheme process-context) (srfi 64))

(test-begin "srfi-38")

(define (wss->string obj)
  (let ((p (open-output-string)))
    (write-with-shared-structure obj p)
    (get-output-string p)))

(define (rt obj)                     ; write/read round trip
  (read-with-shared-structure (open-input-string (wss->string obj))))

;;; --- plain data is written normally ---
(test-equal "(1 2 3)" (wss->string '(1 2 3)))
(test-equal "#(a b)" (wss->string #(a b)))
(test-equal '(1 (2) "x") (rt '(1 (2) "x")))

;;; --- cyclic list round trip ---
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (let ((c2 (rt c)))
    (test-equal 1 (car c2))
    (test-equal 2 (cadr c2))
    (test-equal #t (eq? c2 (cddr c2)))))       ; cycle reconstructed

;;; --- shared (acyclic) substructure preserved ---
(let* ((x (list 'a))
       (shared (list x x))
       (s2 (rt shared)))
  (test-equal '(a) (car s2))
  (test-equal #t (eq? (car s2) (cadr s2))))

;;; --- self-referential vector ---
(let ((v (vector 1 2)))
  (vector-set! v 1 v)
  (let ((v2 (rt v)))
    (test-equal 1 (vector-ref v2 0))
    (test-equal #t (eq? v2 (vector-ref v2 1)))))

;;; --- labels parse via plain read too (R7RS datum labels) ---
(let ((c (read (open-input-string "#0=(1 2 . #0#)"))))
  (test-equal 1 (car c))
  (test-equal #t (eq? c (cddr c))))

;;; --- default port arguments exist (write to current-output via string port) ---
(test-equal #t (procedure? write-with-shared-structure))
(test-equal #t (procedure? read-with-shared-structure))

(let ((runner (test-runner-current)))
  (test-end "srfi-38")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
