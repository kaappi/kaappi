;;; SRFI 239 — Destructuring Lists
;;;
;;; `list-case` is the syntactic fundamental list destructor: it evaluates
;;; its expression once and dispatches on shape, running whichever clause
;;; matches — a `(a . d)` clause for a pair (binding car/cdr), a `()`
;;; clause for the empty list, or a bare-variable clause for anything else
;;; (an improper list's final non-null atom). `_` in a binding position
;;; means "don't bind this." Clauses are optional and may appear in any
;;; order; a value that hits an omitted clause signals an error.
;;;
;;; No portable reference implementation is given by the SRFI itself (the
;;; sample implementation is R6RS-only); this is an independent R7RS
;;; syntax-rules port of the specified semantics. It reports the
;;; no-matching-clause case via R7RS `error` rather than R6RS's
;;; `&assertion-violation` condition type, since Kaappi's condition
;;; system is R7RS error-object based, not R6RS conditions.

(define-library (srfi 239)
  (export list-case)
  (import (scheme base))
  (begin

    ;; `_` is an unbound auxiliary keyword, like `else` in `cond` — it has
    ;; no binding to export; list-case's clauses just use the bare symbol
    ;; `_`, matched purely by name via syntax-rules' free-identifier
    ;; matching for unbound literals (same mechanism `cond`'s `else` uses).
    ;; `%lc-unset` is a second such sentinel, marking an accumulator slot
    ;; ("no clause of this shape seen yet") so %lc-classify can tell a
    ;; first clause of a shape from a second one.

    (define-syntax list-case
      (syntax-rules ()
        ((_ expr clause ...)
         (%lc-classify expr (clause ...) %lc-unset %lc-unset %lc-unset))))

    ;; Scans clauses one at a time, sorting each by head shape into the
    ;; matching accumulator slot (pair-handler null-handler atom-handler).
    ;; Each shape starts %lc-unset; a rule pair per shape either fills an
    ;; unset slot or, if it's already filled, reports the second clause
    ;; of the same shape as a mistake (pair/null/atom are exhaustive and
    ;; disjoint, so a shape is never legitimately given twice). Order
    ;; matters: null and pair rules (specific clause-head shapes) must
    ;; precede the atom rules (a bare pattern variable, matching any
    ;; clause head not already claimed by a more specific rule above).
    (define-syntax %lc-classify
      (syntax-rules (%lc-unset)
        ((_ expr () pair-h null-h atom-h)
         (%lc-dispatch expr
           (%lc-or-error pair-h (lambda (%a %d) (error "list-case: value is a pair, but no (a . d) clause was given")))
           (%lc-or-error null-h (lambda () (error "list-case: value is the empty list, but no () clause was given")))
           (%lc-or-error atom-h (lambda (%x) (error "list-case: no matching clause" %x)))))

        ((_ expr ((() . cbody) . rest) pair-h %lc-unset atom-h)
         (%lc-classify expr rest pair-h (lambda () . cbody) atom-h))
        ((_ expr ((() . cbody) . rest) pair-h null-h atom-h)
         (error "list-case: more than one () clause"))

        ((_ expr (((a . d) . cbody) . rest) %lc-unset null-h atom-h)
         (%lc-classify expr rest
           (lambda (%a %d) (%lc-pair-body a d %a %d cbody))
           null-h atom-h))
        ((_ expr (((a . d) . cbody) . rest) pair-h null-h atom-h)
         (error "list-case: more than one (a . d) clause"))

        ((_ expr ((x . cbody) . rest) pair-h null-h %lc-unset)
         (%lc-classify expr rest pair-h null-h (lambda (%x) (%lc-atom-body x %x cbody))))
        ((_ expr ((x . cbody) . rest) pair-h null-h atom-h)
         (error "list-case: more than one atom clause"))))

    ;; If a slot is still %lc-unset (no clause of that shape was given),
    ;; substitute the fallback error-raiser; otherwise keep the real
    ;; handler a clause already installed there.
    (define-syntax %lc-or-error
      (syntax-rules (%lc-unset)
        ((_ %lc-unset fallback) fallback)
        ((_ handler fallback) handler)))

    ;; Binds a/d to the already-computed car/cdr (%a/%d) unless either is
    ;; the `_` placeholder, in which case that binding is skipped — this
    ;; is what lets (_ . _) avoid ever generating a lambda with the same
    ;; parameter name twice.
    (define-syntax %lc-pair-body
      (syntax-rules (_)
        ((_ _ _ %a %d cbody) (begin . cbody))
        ((_ _ d %a %d cbody) (let ((d %d)) . cbody))
        ((_ a _ %a %d cbody) (let ((a %a)) . cbody))
        ((_ a d %a %d cbody) (let ((a %a) (d %d)) . cbody))))

    ;; Same "_ means don't bind" treatment as %lc-pair-body, for the
    ;; atom clause's single variable. Unlike the pair clause -- where
    ;; skipping the binding is load-bearing (a (_ . _) clause would
    ;; otherwise generate a lambda binding `_` twice) -- the atom clause
    ;; only ever has one variable, so this is purely for consistency
    ;; with the documented "_ in a binding position means don't bind
    ;; this" contract, not for avoiding a duplicate-binding error.
    (define-syntax %lc-atom-body
      (syntax-rules (_)
        ((_ _ %x cbody) (begin . cbody))
        ((_ x %x cbody) (let ((x %x)) . cbody))))

    (define-syntax %lc-dispatch
      (syntax-rules ()
        ((_ expr pair-h null-h atom-h)
         (let ((v expr))
           (cond ((pair? v) (pair-h (car v) (cdr v)))
                 ((null? v) (null-h))
                 (else (atom-h v)))))))))
