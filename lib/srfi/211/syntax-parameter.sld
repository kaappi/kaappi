;;; SRFI 211 — Scheme Macro Libraries: (srfi 211 syntax-parameter).
;;;
;;; SRFI 211's standardized library name for the syntax-parameter facility,
;;; whose semantics it defines by reference to SRFI 139 ("This syntax is
;;; defined in SRFI 139"). Kaappi ships SRFI 139 as a portable library over
;;; let-syntax (see lib/srfi/139.sld's header for the mechanism and its
;;; verification); this is a pure re-export under the SRFI 211 name.
(define-library (srfi 211 syntax-parameter)
  (import (srfi 139))
  (export define-syntax-parameter syntax-parameterize))
