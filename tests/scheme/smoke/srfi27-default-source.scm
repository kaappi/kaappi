;; Regression test for #1192: default-random-source must be a variable
;; bound to a random source, not a procedure.

(import (scheme base) (scheme process-context) (srfi 27) (srfi 64))

(test-begin "srfi27-default-source")

(test-assert "default-random-source is a random source"
  (random-source? default-random-source))

(test-assert "default-random-source is not a procedure"
  (not (procedure? default-random-source)))

(test-assert "random-source-state-ref accepts default-random-source"
  (pair? (random-source-state-ref default-random-source)))

(let ((runner (test-runner-current)))
  (test-end "srfi27-default-source")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
