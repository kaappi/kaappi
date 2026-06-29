;; Regression test for #422: open-binary-* should be in (scheme file), not (scheme base)

(import (scheme base) (scheme write))

;; These should come from (scheme file), not (scheme base)
(import (only (scheme file) open-binary-input-file open-binary-output-file))

(display "PASS")
(newline)
