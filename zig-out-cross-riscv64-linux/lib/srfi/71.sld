;;; SRFI 71 — Extended LET-syntax for multiple values
;;;
;;; Extends `let`/`let*`/`letrec` so a binding can destructure the
;;; multiple values an expression returns, while staying fully backward
;;; compatible with ordinary single-value bindings (including named let,
;;; whose bindings SRFI 71 leaves untouched since they double as lambda
;;; arguments). A binding clause is one of:
;;;   (var expr)                       ; ordinary, same as R7RS
;;;   (var1 var2 ... expr)             ; shorthand for the values form below
;;;   ((values var ...) expr)          ; explicit, fixed arity
;;;   ((values var ... . rest) expr)   ; explicit, with a rest list
;;; This library's own reference implementation isn't inlined in the SRFI
;;; document (it only links external files); the design here is an
;;; independent implementation of the specified semantics, shaped by two
;;; empirically-confirmed Kaappi constraints (both worth knowing if you
;;; touch this file):
;;;
;;; 1. Once a library redefines a core special-form name (here, "let",
;;;    "let*", "letrec"), that name can no longer be used to reach the
;;;    *original* form from anywhere in the same program — not via a
;;;    separate helper library that never itself touches the name (its
;;;    reference gets silently recaptured by the shadowing definition
;;;    visible at the final expansion site), and not via renaming on
;;;    import (a renamed special form stops being recognized as a
;;;    binding form at all — see kaappi/kaappi#1718). So named let and
;;;    letrec below are built from `lambda` and `define` only, which
;;;    this library leaves untouched.
;;; 2. `define-values` does not provide letrec*-style mutual/forward
;;;    visibility the way plain `define` does — `(define-values (f)
;;;    (lambda () (g))) (define-values (g) (lambda () 1))` fails to
;;;    resolve `g` inside `f`, even with zero macros involved, while the
;;;    equivalent with two plain `define`s works. So letrec's variables
;;;    are pre-declared with plain `define` (one per flattened name, so
;;;    forward/mutual references work) and then assigned via
;;;    call-with-values + set!, not routed through define-values.
;;;
;;; A macro that needs to splice multiple definitions into a body must be
;;; the body's *sole* form, with the rest of the body threaded through as
;;; a trailing argument — a definition-producing macro call that's one of
;;; several sequential body forms is not recognized as introducing
;;; bindings (also empirically confirmed; this shaped both named let and
;;; letrec's design below, both of which lead with exactly one such call).

(define-library (srfi 71)
  (export let let* letrec
          uncons uncons-2 uncons-3 uncons-4 uncons-cons unlist unvector
          values->list values->vector)
  (import (except (scheme base) let let* letrec) (scheme cxr))
  (begin

    ;; --- let ------------------------------------------------------------

    (define-syntax let
      (syntax-rules ()
        ;; named let: bindings are untouched, single-value only. Built
        ;; from an internal `define`, which is itself letrec*-scoped, so
        ;; the named procedure can call itself with no need for letrec.
        ((_ name ((var val) ...) body ...)
         ((lambda ()
            (define (name var ...) body ...)
            (name val ...))))
        ;; anonymous let: normalize every clause, then one parallel let-values
        ((_ (clause ...) body ...)
         (%srfi71-let-all (clause ...) () body ...))))

    (define-syntax %srfi71-let-all
      (syntax-rules (values)
        ((_ () (normalized ...) body ...)
         (let-values (normalized ...) body ...))
        ((_ (((values v ... . rest) expr) more ...) (normalized ...) body ...)
         (%srfi71-let-all (more ...) (normalized ... ((v ... . rest) expr)) body ...))
        ((_ ((var ... expr) more ...) (normalized ...) body ...)
         (%srfi71-let-all (more ...) (normalized ... ((var ...) expr)) body ...))))

    ;; --- let* -------------------------------------------------------------
    ;; Sequential: each clause's bindings are visible to the next clause's
    ;; expression, built by nesting one let-values per clause.

    (define-syntax let*
      (syntax-rules (values)
        ((_ () body ...) (let () body ...))
        ((_ (((values v ... . rest) expr) more ...) body ...)
         (let-values (((v ... . rest) expr)) (let* (more ...) body ...)))
        ((_ ((var ... expr) more ...) body ...)
         (let-values (((var ...) expr)) (let* (more ...) body ...)))))

    ;; --- letrec -----------------------------------------------------------
    ;; All variables (flattened across every clause) are pre-declared via
    ;; plain `define` (mutually visible to every clause's expression,
    ;; letrec*-style — see note 2 above for why this can't be
    ;; define-values), then each clause's expression is evaluated and its
    ;; values assigned via set!, in order, before the body runs.

    (define-syntax letrec
      (syntax-rules ()
        ((_ (clause ...) body ...)
         ((lambda () (%srfi71-letrec-vars (clause ...) () body ...))))))

    (define-syntax %srfi71-letrec-vars
      (syntax-rules (values)
        ((_ () (assign ...) body ...)
         (%srfi71-letrec-emit (assign ...) body ...))
        ((_ (((values v ... . rest) expr) more ...) (assign ...) body ...)
         (%srfi71-letrec-vars (more ...) (assign ... ((v ... . rest) expr)) body ...))
        ((_ ((var ... expr) more ...) (assign ...) body ...)
         (%srfi71-letrec-vars (more ...) (assign ... ((var ...) expr)) body ...))))

    ;; Collects the flattened variable names (proper-list clause first, so
    ;; the dotted rule below only ever catches a genuine dotted tail) as
    ;; its own pass, then emits: all `define`s, then the assignments.
    (define-syntax %srfi71-letrec-emit
      (syntax-rules ()
        ((_ (assign ...) body ...)
         (%srfi71-letrec-collect (assign ...) () (assign ...) body ...))))

    (define-syntax %srfi71-letrec-collect
      (syntax-rules ()
        ((_ () (allvars ...) (assign ...) body ...)
         (begin
           (define allvars #f) ...
           (%srfi71-letrec-assign (assign ...) body ...)))
        ((_ (((v ...) expr) more ...) (allvars ...) assigns body ...)
         (%srfi71-letrec-collect (more ...) (allvars ... v ...) assigns body ...))
        ((_ (((v ... . rest) expr) more ...) (allvars ...) assigns body ...)
         (%srfi71-letrec-collect (more ...) (allvars ... v ... rest) assigns body ...))))

    (define-syntax %srfi71-letrec-assign
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((formals expr) more ...) body ...)
         (begin
           (call-with-values (lambda () expr) (lambda vals (%srfi71-set-list formals vals)))
           (%srfi71-letrec-assign (more ...) body ...)))))

    (define-syntax %srfi71-set-list
      (syntax-rules ()
        ((_ () vals) (if #f #f))
        ((_ (v . more) vals)
         (begin (set! v (car vals)) (%srfi71-set-list more (cdr vals))))
        ((_ rest vals) (set! rest vals))))

    ;; --- un- procedures ---------------------------------------------------

    (define (uncons pair) (values (car pair) (cdr pair)))
    (define (uncons-2 list) (values (car list) (cadr list) (cddr list)))
    (define (uncons-3 list) (values (car list) (cadr list) (caddr list) (cdddr list)))
    (define (uncons-4 list) (values (car list) (cadr list) (caddr list) (cadddr list) (cddddr list)))
    (define (uncons-cons alist) (values (caar alist) (cdar alist) (cdr alist)))
    (define (unlist list) (apply values list))
    (define (unvector vector) (apply values (vector->list vector)))

    ;; --- values->list / values->vector ------------------------------------

    (define-syntax values->list
      (syntax-rules ()
        ((_ expr) (call-with-values (lambda () expr) list))))

    (define-syntax values->vector
      (syntax-rules ()
        ((_ expr) (call-with-values (lambda () expr) vector))))))
