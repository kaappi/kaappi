;; Regression test for #1269: define-syntax in a custom environment must not
;; leak into the global macro table.
(import (scheme base) (scheme write) (scheme eval) (scheme process-context)
        (srfi 64))

(test-begin "eval-macro-leak-1269")

;; define-syntax via (interaction-environment) must persist (REPL semantics)
(eval '(define-syntax ie-mac (syntax-rules () ((_ x) (+ x 100))))
      (interaction-environment))
(test-equal "macro in interaction-environment persists" 142 (ie-mac 42))

;; define-syntax into immutable (environment ...) signals error and does not leak
(test-equal "define-syntax into immutable env errors" 'caught
  (guard (e (#t 'caught))
    (eval '(define-syntax leaked (syntax-rules () ((_ x) (+ x 999))))
          (environment '(scheme base)))))

(test-equal "macro from failed define-syntax does not leak" 'not-leaked
  (guard (e (#t 'not-leaked))
    (eval '(leaked 1) (interaction-environment))))

(let ((runner (test-runner-current)))
  (test-end "eval-macro-leak-1269")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
