;; Test include-library-declarations — R7RS §5.6.1
;;
;; Fixtures live in fixtures/ so run-all.sh doesn't execute them
;; as standalone tests — they are only meaningful spliced into define-library.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "include-library-declarations")

;; Basic export via include-library-declarations
(define-library (test ild basic)
  (import (scheme base))
  (include-library-declarations "fixtures/include-lib-decls-exports.scm")
  (begin
    (define (my-add a b) (+ a b))
    (define (my-mul a b) (* a b))))

(import (test ild basic))

(test-equal "basic export via include-library-declarations"
  7 (my-add 3 4))
(test-equal "basic export via include-library-declarations (2)"
  30 (my-mul 5 6))

;; Regression #874: cond-expand inside include-library-declarations
(define-library (test ild cond-expand)
  (import (scheme base))
  (include-library-declarations "fixtures/ild-cond-expand.scm"))

(import (test ild cond-expand))

(test-equal "cond-expand inside include-library-declarations"
  'from-cond-expand inner-x)

;; Regression #874: nested include-library-declarations
(define-library (test ild nested)
  (import (scheme base))
  (include-library-declarations "fixtures/ild-nested-outer.scm"))

(import (test ild nested))

(test-equal "nested include-library-declarations"
  'nested-ild inner-y)

(let ((runner (test-runner-current)))
  (test-end "include-library-declarations")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
