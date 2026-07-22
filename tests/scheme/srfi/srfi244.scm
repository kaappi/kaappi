;; SRFI-244 (Multiple-value Definitions) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi244.scm
;;
;; define-values is already a Kaappi core special form; this just
;; confirms the (srfi 244) re-export path works.

(import (scheme base) (scheme process-context) (srfi 244) (srfi 64))

(test-begin "srfi-244")

;; the spec's own examples
(define-values (x y) (values 1 2))
(test-equal "define-values: fixed-arity binding" 3 (+ x y))

(define-values (a . b) (values 1 2 3))
(test-equal "define-values: dotted-tail formals collect the rest" '(2 3) b)
(test-equal "define-values: dotted-tail example, spec's own check" '(1 2 3) (cons a b))

;; single-variable and all-rest shapes
(define-values (single) (values 42))
(test-equal "define-values: single variable" 42 single)

(define-values all (values 1 2 3))
(test-equal "define-values: bare identifier collects all values" '(1 2 3) all)

;; internal (body-position) define-values
(define (f)
  (define-values (p q) (values 10 20))
  (+ p q))
(test-equal "define-values: works as an internal definition" 30 (f))

(let ((runner (test-runner-current)))
  (test-end "srfi-244")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
