;;; SRFI 244 — Multiple-value Definitions
;;;
;;; `define-values` is already a built-in Kaappi special form (part of
;;; its core (scheme base) support, predating this SRFI's existence as a
;;; way to bring R7RS's define-values to R6RS systems). So, like SRFI 46,
;;; this library is a conformance statement, not new functionality: it
;;; just re-exports the same define-values already bound in
;;; (scheme base).

(define-library (srfi 244)
  (import (only (scheme base) define-values))
  (export define-values))
