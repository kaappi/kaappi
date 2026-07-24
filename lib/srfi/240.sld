;;; SRFI 240: Reconciled Records.
;;;
;;; Per the spec: "The record mechanism described in this SRFI is based on
;;; the record mechanism described in SRFI 237" -- SRFI 240 adds no new
;;; semantics, just a `define-record-type` that accepts EITHER R6RS clause
;;; syntax or the R7RS/SRFI-9 positional syntax, both producing
;;; interoperable record types. In Kaappi, `define-record-type` is a
;;; global, always-available special form (src/vm_eval.zig) whose
;;; desugarer (src/vm_records.zig) already dispatches between both
;;; syntaxes unconditionally -- so the reconciliation this SRFI exists to
;;; provide is already the engine's default top-level behavior, with or
;;; without this library imported. This file exists purely so
;;; `(import (srfi 240))` resolves and re-exports SRFI 237's procedural and
;;; inspection surface, matching the spec's own "everything else comes
;;; entirely from SRFI 237."
(define-library (srfi 240)
  (import (srfi 237))
  (export
    make-record-type-descriptor record-type-descriptor?
    make-record-descriptor record-descriptor-rtd record-descriptor-parent record-descriptor?
    record-constructor record-predicate record-accessor record-mutator
    record? record-rtd record-type-name record-type-parent record-type-uid
    record-type-generative? record-type-sealed? record-type-opaque?
    record-type-field-names record-field-mutable? record-uid->rtd))
