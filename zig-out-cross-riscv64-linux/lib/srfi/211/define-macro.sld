;;; SRFI 211 — Scheme Macro Libraries: (srfi 211 define-macro).
;;;
;;; Old-style (non-hygienic) Lisp macros. `(lisp-transformer proc)` makes a
;;; transformer that replaces a macro use with the result of invoking
;;; `proc` on the datum representing the WHOLE macro use (keyword
;;; included), exactly as SRFI 211 specifies; no renaming of any kind is
;;; applied to the result — that non-hygiene is the feature. define-macro
;;; is the classic sugar, in both SRFI 211 forms:
;;;
;;;   (define-macro (name . formals) body ...)   ; destructures (cdr use)
;;;   (define-macro name expander)               ; expander gets whole use
;;;
;;; The first form's equivalence is per the SRFI: the use's cdr is applied
;;; to (lambda formals body ...). The expander expression is evaluated at
;;; macro-definition time in the global environment (phase separation —
;;; see (srfi 211 explicit-renaming)'s header; the engine mechanism is
;;; shared).
;;;
;;; Verified: tests/scheme/srfi/srfi211.scm (quasiquoted swap!, both
;;; definition forms, non-hygiene demonstrated deliberately).
(define-library (srfi 211 define-macro)
  (import (scheme base)
          (srfi 211 primitives))
  (export define-macro lisp-transformer)
  (begin
    (define-syntax define-macro
      (syntax-rules ()
        ((_ (name . formals) body ...)
         (define-syntax name
           (lisp-transformer
            (lambda (%form) (apply (lambda formals body ...) (cdr %form))))))
        ((_ name expander)
         (define-syntax name (lisp-transformer expander)))))))
