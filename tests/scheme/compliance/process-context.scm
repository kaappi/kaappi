;;; Process-context library compliance tests (R7RS 6.14)
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "process-context")

;; --- command-line ---
(test-group "command-line"
  (test-assert "command-line returns a list" (list? (command-line))))

;; --- get-environment-variable ---
(test-group "get-environment-variable"
  (test-assert "known env var returns a string" (string? (get-environment-variable "HOME")))
  (test-eqv "unknown env var returns #f" #f (get-environment-variable "KAAPPI_NONEXISTENT_VAR_12345")))

;; --- get-environment-variables ---
(test-group "get-environment-variables"
  (test-assert "get-environment-variables returns a list" (list? (get-environment-variables))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "process-context")
(if (> %test-fail-count 0) (exit 1))
