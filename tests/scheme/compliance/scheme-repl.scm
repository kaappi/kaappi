;; Test (scheme repl) library — R7RS §6.4

(import (scheme base) (scheme eval) (scheme write)
        (scheme process-context) (scheme repl) (srfi 64))

(test-begin "scheme-repl")

;; interaction-environment should be accessible
(test-assert "interaction-environment is a procedure"
             (procedure? interaction-environment))

;; interaction-environment returns an environment usable by eval
(test-assert "interaction-environment returns something, not #f"
             (not (eq? (interaction-environment) #f)))
(test-equal "eval works in the interaction environment"
            3 (eval '(+ 1 2) (interaction-environment)))

(let ((runner (test-runner-current)))
  (test-end "scheme-repl")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
