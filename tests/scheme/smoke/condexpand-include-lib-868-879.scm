;;; Regression tests for #868 and #879
;;;
;;; #868: cond-expand (library ...) should detect importable .sld
;;;       libraries that haven't been loaded yet
;;; #879: (include ...) inside a library begin block should work

(import (scheme base) (scheme write))

;; --- Test #868: cond-expand (library ...) for unloaded .sld library ---
;; (test helpers) is a .sld file on the lib path but not yet imported.
;; cond-expand should detect it via file existence check.
(display
  (cond-expand
    ((library (test helpers)) "found")
    (else "not-found")))
(newline)

;; Also verify that non-existent libraries correctly return false
(display
  (cond-expand
    ((library (test nonexistent-library-xyz)) "found")
    (else "not-found")))
(newline)

;; --- Test #879: include inside library begin block ---
;; (test with-include) uses (include "incbody.scm") in its begin block
(import (test with-include))
(display included-value)
(newline)
