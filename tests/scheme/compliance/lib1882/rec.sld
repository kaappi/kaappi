;; Fixture for #1882: a library body whose R7RS `define-record-type` has a
;; constructor named `fields`.
;;
;; Library bodies reach the record desugarer through a different door than
;; the top level -- compiler_lambda's body scan, via
;; vm_records.collectRecordTypeDefNames/expandRecordTypeDefines -- and those
;; two reject R6RS clause syntax outright (it is a documented top-level-only
;; feature). So a misdetection here didn't just mangle one form: the whole
;; library failed to load, and every importer saw `undefined variable` for
;; every name it exports.
(define-library (lib1882 rec)
  (export make-lib-point lib-point? lib-point-x lib-point-y)
  (import (scheme base))
  (begin

    (define-record-type lib-point
      (fields x y)
      lib-point?
      (x lib-point-x)
      (y lib-point-y))

    ;; `fields` itself stays library-internal -- an importer shouldn't have
    ;; to take a binding with that name to exercise the fix.
    (define (make-lib-point x y) (fields x y))))
