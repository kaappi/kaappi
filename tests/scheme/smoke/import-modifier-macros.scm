;; Regression test for #495: import modifiers (only/except/rename/prefix)
;; must apply to exported macros, not just procedures.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "import-modifier-macros")

;; (only ...) should only import cut, not cute
(import (only (srfi 26) cut))
(test-assert "cut available after (only ... cut)"
  (procedure? (cut + 1 <>)))

;; (except ...) should exclude cute
(import (except (srfi 26) cute))
(test-assert "cut available after (except ... cute)"
  (procedure? (cut + 1 <>)))

;; (prefix ...) should prefix macros
(import (prefix (srfi 26) s:))
(test-assert "s:cut available after (prefix ... s:)"
  (procedure? (s:cut + 1 <>)))

(let ((runner (test-runner-current)))
  (test-end "import-modifier-macros")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
