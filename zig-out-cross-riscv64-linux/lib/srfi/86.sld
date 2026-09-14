;;; SRFI 86 — MU and NU simulating VALUES and CALL-WITH-VALUES
;;;
;;; mu/nu are exactly the two tiny macros the spec defines them as
;;; (nothing more to scope down). alet/alet* are a much larger feature —
;;; 22 binding-spec forms, plus a Scsh-style opt/cat/key sub-language for
;;; positional and keyword arguments — described only in prose, with the
;;; multi-hundred-line reference implementation linked rather than
;;; inlined. This port implements the binding-spec forms that compose
;;; cleanly with mu/nu's own CPS style and don't need the opt/cat/key
;;; machinery (a whole separate feature in its own right):
;;;   (var expr)                 ; ordinary binding
;;;   ((var ...) expr)           ; multi-value destructure via mu/nu:
;;;   ((var ... . rest) expr)    ;   expr is called with a continuation
;;;   (var1 var2 ... expr)       ; same, without the extra wrapping
;;;   (var)                      ; escape procedure: call it with the
;;;                              ;   alet['s] own result values to exit
;;;   (rec (var expr) ...)       ; mutually-recursive single-value group
;;;   (() expr ...)              ; effects only, no new binding
;;; Not implemented: the positional/keyword argument forms (opt/cat/key),
;;; the `and`-integration form, the whole-alet-as-recursive-procedure
;;; form (a binding-spec list ending in a dotted variable), a bare
;;; unparenthesized `var expr` pair spliced directly into the bindings
;;; list (as opposed to the parenthesized shorthand above, which is
;;; supported), the call-with-values-based binding forms (redundant with
;;; the mu/nu ones above), and named alet/alet* (a named-let-like
;;; self-reference layered on top of all the above). alet and alet* are
;;; both implemented as
;;; strictly sequential (left-to-right, each binding visible to every
;;; later one) — the spec's own examples of alet (not alet*) using an
;;; escape procedure or later bindings never rely on anything an earlier
;;; binding couldn't see, so this doesn't change any of them, but it is a
;;; real reduction from the letter of the spec, which describes alet's
;;; scoping as parallel (like plain `let`) and alet*'s as sequential.

(define-library (srfi 86)
  (export mu nu alet alet*)
  (import (scheme base))
  (begin

    (define-syntax mu
      (syntax-rules ()
        ((mu argument ...) (lambda (f) (f argument ...)))))

    (define-syntax nu
      (syntax-rules ()
        ((nu argument ...) (lambda (f) (apply f argument ...)))))

    (define-syntax alet
      (syntax-rules ()
        ((_ . rest) (alet* . rest))))

    (define-syntax alet*
      (syntax-rules (rec)
        ((_ () body ...) (begin body ...))
        ((_ ((rec (v e) ...) . more) body ...)
         ((lambda () (define v e) ... (alet* more body ...))))
        ((_ ((() expr ...) . more) body ...)
         (begin expr ... (alet* more body ...)))
        ((_ ((var) . more) body ...)
         (call-with-current-continuation (lambda (var) (alet* more body ...))))
        ((_ (((v1 . vmore) expr) . more) body ...)
         (expr (lambda (v1 . vmore) (alet* more body ...))))
        ((_ ((var expr) . more) body ...)
         ((lambda (var) (alet* more body ...)) expr))
        ;; flat shorthand: (var1 var2 ... expr), 2+ vars, no wrapping —
        ;; only ever reached for 3+ element clauses, since the exact
        ;; 2-element case is already caught by the plain-binding rule
        ;; above it.
        ((_ ((var ... expr) . more) body ...)
         (expr (lambda (var ...) (alet* more body ...))))))))
