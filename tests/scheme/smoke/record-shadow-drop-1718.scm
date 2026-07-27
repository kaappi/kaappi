;; Regression test for #1718: a program that imports a library exporting
;; its own define-record-type macro (the SRFI-136/131/57-style extended
;; record syntax pattern) must not silently drop define-record-type forms
;; in unrelated libraries loaded afterward.
;;
;; Before the fix, vm_eval.zig's handleTopLevelForm/isSpecialTopLevelForm
;; decided whether define-record-type was shadowed by checking the
;; process-global vm.macros, and vm_library.zig's compileLibExpr
;; unconditionally returned once it decided (correctly, per that check) to
;; defer to macro-aware compilation -- but never actually performed that
;; macro-aware compilation, so an unrelated library's own plain
;; define-record-type was silently dropped: no error, its accessors just
;; never got defined. See lib1718/drt-shadow.sld, lib1718/drt-victim.sld.
(import (scheme base) (scheme write) (srfi 64))

(test-begin "record-shadow-drop-1718")

;; Import a library exporting its own define-record-type macro -- this
;; puts a `define-record-type` macro into the process-global vm.macros.
(import (lib1718 drt-shadow))

;; Import an unrelated library with its own, un-shadowed define-record-type.
;; Before the fix, this was silently dropped.
(import (lib1718 drt-victim))

(test-assert "record constructor defined" (procedure? make-color))
(test-assert "record predicate defined" (procedure? color?))
(test-assert "record accessor defined" (procedure? color-r))
(test-equal "record works end-to-end" 42 (color-r (make-color 42)))

(let ((runner (test-runner-current)))
  (test-end "record-shadow-drop-1718")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
