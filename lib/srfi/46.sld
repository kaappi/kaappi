;;; SRFI 46 — Basic Syntax-rules Extensions
;;;
;;; Specifies two extensions to R5RS syntax-rules: (1) an optional custom
;;; ellipsis identifier as syntax-rules's first argument, and (2) "tail
;;; patterns" — fixed patterns allowed after an ellipsis-matched sequence
;;; in the same list or vector pattern, e.g. (p1 p2 ... pn) matching a
;;; variable-length middle with fixed head p1 and fixed tail pn.
;;;
;;; Both are already native behavior of Kaappi's syntax-rules (custom
;;; ellipsis identifiers are used throughout this codebase, e.g.
;;; lib/srfi/241.sld and lib/srfi/153.sld; tail patterns work for both list
;;; and vector patterns — verified directly against this SRFI's own
;;; examples: (foo ?x ?y ... ?z), fake-begin's (?body ... ?tail), and the
;;; vector form #(?x ?y ... ?z)). So, like SRFI 149, this library is a
;;; conformance statement, not new functionality: it just re-exports the
;;; same syntax-rules already bound in (scheme base).

(define-library (srfi 46)
  (import (only (scheme base) syntax-rules))
  (export syntax-rules))
