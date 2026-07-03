;;; Regression tests for #868 and #879
;;;
;;; #868: cond-expand (library ...) should detect importable .sld
;;;       libraries that haven't been loaded yet
;;; #879: (include ...) inside a library begin block should work
;;;
;;; The fixture libraries live in lib868/ next to this script. They are
;;; found because the script's directory is on the library search path.

(import (scheme base) (scheme write) (scheme process-context))

(define (check what expected actual)
  (unless (equal? expected actual)
    (display "FAIL ")
    (display what)
    (display ": expected ")
    (write expected)
    (display ", got ")
    (write actual)
    (newline)
    (exit 1)))

;; --- Test #868: cond-expand (library ...) for unloaded .sld library ---
;; (lib868 helpers) is a .sld file on the lib path but not yet imported.
;; cond-expand should detect it via file existence check.
(check "cond-expand finds unloaded library" "found"
       (cond-expand
         ((library (lib868 helpers)) "found")
         (else "not-found")))

;; Non-existent libraries must not be detected.
(check "cond-expand rejects nonexistent library" "not-found"
       (cond-expand
         ((library (test nonexistent-library-xyz)) "found")
         (else "not-found")))

;; --- Test #879: include inside library begin block ---
;; (lib868 with-include) uses (include "incbody.scm") in its begin block.
(import (lib868 with-include))
(check "include inside library begin block" 99 included-value)

;; A library detected by cond-expand must also actually import.
(import (lib868 helpers))
(check "importing the detected library" 42 helper-value)

(display "condexpand-include-lib-ok")
(newline)
