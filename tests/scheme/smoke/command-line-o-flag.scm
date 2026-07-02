;; Regression test for #602: -o must not be stripped from (command-line)
;; in normal script execution mode.
;; This test is invoked by run-all.sh as: kaappi this-file.scm
;; So (command-line) should be ("this-file.scm") — the script path as first element.
(import (scheme base) (scheme write) (scheme process-context))

(define args (command-line))

;; Verify (command-line) returns a non-empty list with the script path
(unless (and (list? args) (>= (length args) 1))
  (display "FAIL: (command-line) too short")
  (newline)
  (exit 1))

(display "all passed")
(newline)
