;; Regression: imported library macros must resolve library-internal
;; bindings at the use site, including through internal helper macros
;; (SRFI 64's test-assert -> %test-comp1body -> %test-on-test-begin chain),
;; and template let-bindings named after builtins (exp) must not resolve to
;; the global builtin.

(import (scheme base) (srfi 64))

(define-library (regress mac-internals)
  (import (scheme base))
  (export outer shadow-exp)
  (begin
    (define (%internal x) (+ x 1))
    (define-syntax %helper
      (syntax-rules ()
        ((_ e) (%internal e))))
    (define-syntax outer
      (syntax-rules ()
        ((_ e) (%helper e))))
    (define-syntax shadow-exp
      (syntax-rules ()
        ((_ v) (let ((exp v)) exp))))))

(import (regress mac-internals))

(test-begin "library-macro-internals")

(test-eqv "macro chain reaches non-exported procedure" 42 (outer 41))
(test-eqv "template let-binding named exp stays local" 7 (shadow-exp 7))

(define %fail-count (test-runner-fail-count (test-runner-current)))
(test-end "library-macro-internals")
(if (> %fail-count 0) (exit 1))
