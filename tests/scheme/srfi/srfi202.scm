;; SRFI-202 (Pattern-matching and-let*) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi202.scm

(import (scheme base) (scheme process-context) (srfi 202) (srfi 64))

(test-begin "srfi-202")

;;; --- SRFI 2 backward compatibility ---
(test-equal "srfi 2: simple binding" 10 (and-let* ((x 5)) (* x 2)))
(test-equal "srfi 2: binding + guard" 10 (and-let* ((x 5) ((> x 0))) (* x 2)))
(test-equal "srfi 2: falsy binding short-circuits" #f (and-let* ((x #f)) 'never))
(test-equal "srfi 2: failing guard short-circuits" #f (and-let* ((x 5) ((< x 0))) 'never))
(test-equal "srfi 2: no claws" 'ok (and-let* () 'ok))
(test-equal "srfi 2: no body returns #t" #t (and-let* ((x 5))))
(test-equal "srfi 2: multiple bindings" 3 (and-let* ((x 1) (y 2)) (+ x y)))
(test-equal "srfi 2: later binding sees earlier" 6 (and-let* ((x 2) (y (* x 3))) y))

;;; --- single quasiquoted pattern binding ---
(define (lookup k alist)
  (and-let* ((`(,found-key . ,value) (assq k alist)))
    value))

(test-equal "pattern binding: found" 2 (lookup 'b '((a . 1) (b . 2))))
(test-equal "pattern binding: not found (assq gives #f, pattern fails)"
  #f (lookup 'z '((a . 1) (b . 2))))

(test-equal "pattern binding: wildcard"
  'ok
  (and-let* ((`(,_ . ,_) (cons 1 2))) 'ok))

;;; --- literal pattern (negated condition) ---
(test-equal "literal pattern: #f matches a false result"
  'not-empty
  (and-let* ((`#f (null? '(1 2 3)))) 'not-empty))

(test-equal "literal pattern: #f fails to match a true result"
  #f
  (and-let* ((`#f (null? '()))) 'not-empty))

;;; --- nested pattern ---
(test-equal "nested pattern"
  '(1 2 3)
  (and-let* ((`(,a ,b ,c) (list 1 2 3))) (list a b c)))

(test-equal "nested pattern: structural mismatch fails"
  #f
  (and-let* ((`(,a ,b) (list 1 2 3))) (list a b)))

;;; --- values-collecting claw ---
(test-equal "values claw: exact count"
  3
  (and-let* (((values a b) (values 1 2))) (+ a b)))

(test-equal "values claw: too few values fails"
  #f
  (and-let* (((values a b) (values 1))) (+ a b)))

(test-equal "values claw: collects surplus into rest"
  '(1 2 (3 4))
  (and-let* (((values a b . rest) (values 1 2 3 4))) (list a b rest)))

(test-equal "values claw: empty rest when exact"
  '(1 2 ())
  (and-let* (((values a b . rest) (values 1 2))) (list a b rest)))

;;; --- general multi-value pattern claw (no "values" keyword) ---
(test-equal "multi-pattern claw: bare identifiers"
  30
  (and-let* ((a b (values 10 20))) (+ a b)))

(test-equal "multi-pattern claw: leading var truthiness applies"
  #f
  (and-let* ((z b (values #f 20))) (list z b)))

(test-equal "multi-pattern claw: quasiquoted leading pattern (no truthiness)"
  '(0 20)
  (and-let* ((`,z b (values 0 20))) (list z b)))

(test-equal "multi-pattern claw: too few values fails"
  #f
  (and-let* ((a b (values 10))) (+ a b)))

(test-equal "multi-pattern claw: extra values discarded"
  30
  (and-let* ((a b (values 10 20 999))) (+ a b)))

;;; --- combining claws ---
(test-equal "combined: pattern then guard then plain binding"
  6
  (and-let* ((`(,x . ,y) (cons 2 3))
             ((> x 0))
             (z (* x y)))
    z))

(let ((runner (test-runner-current)))
  (test-end "srfi-202")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
