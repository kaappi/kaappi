;; Regression test: SRFI 59's program-vicinity tracks whatever file is
;; *currently loading*, not just the top-level script. Previously it only
;; ever reported the top-level script's path (backed by the static
;; %script-path), even from inside a nested `load` -- so a loaded file's own
;; call to program-vicinity incorrectly saw the outer script's directory
;; instead of its own. Found via PR #1733 review; fixed by tracking
;; vm.current_lib_dir (the same "currently loading file" state .sld/include
;; resolution already maintains) instead.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 59))

(test-begin "srfi-59-nested-load-vicinity")

;; Both the direct `kaappi ... srfi59-nested-load-vicinity.scm` invocation
;; and run-all.sh run this file as the top-level script, so program-vicinity
;; must see this file's own directory before any load happens.
(let* ((outer-vicinity (program-vicinity))
       (fixture (string-append outer-vicinity "fixtures/srfi59-nested-vicinity.scm")))
  (load fixture)
  (test-equal "program-vicinity: reports the loaded file's own directory while loading"
              (string-append outer-vicinity "fixtures/")
              %srfi59-nested-vicinity-result)
  (test-equal "program-vicinity: reverts to the outer script's directory after load returns"
              outer-vicinity
              (program-vicinity)))

(let ((runner (test-runner-current)))
  (test-end "srfi-59-nested-load-vicinity")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
