;; Regression test for #602: -o must not be stripped from (command-line)
;; in normal script execution mode.
;; This test is invoked by run-all.sh as: kaappi this-file.scm
;; So (command-line) should be ("kaappi" "this-file.scm") with no -o stripping.
(import (scheme base) (scheme write) (scheme process-context))

(define args (command-line))

;; Verify (command-line) returns a list with at least the program name and script
(unless (and (list? args) (>= (length args) 2))
  (display "FAIL: (command-line) too short")
  (newline)
  (exit 1))

(display "all passed")
(newline)
