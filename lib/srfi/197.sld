;;; SRFI 197 — Pipeline Operators
;;;
;;; Supports the _ placeholder for explicit value placement in steps.
;;; Steps without _ ignore the pipeline value (per SRFI-197 spec).
;;; Does not support the ... (ellipsis) rest-argument feature or
;;; custom placeholder symbols.
(define-library (srfi 197)
  (import (scheme base))
  (export chain chain-and chain-when chain-lambda nest nest-reverse)
  (begin

    ;; --- chain helpers: substitute _ in step arguments ---

    ;; Scan phase — no _ found yet
    (define-syntax %chain-subst
      (syntax-rules (_)
        ((%chain-subst v (acc ...) (_ . more) rest ...)
         (%chain-subst* v (acc ... v) more rest ...))
        ((%chain-subst v (acc ...) (x . more) rest ...)
         (%chain-subst v (acc ... x) more rest ...))
        ;; Done, no _ found — step ignores pipeline value
        ((%chain-subst v (acc ...) () rest ...)
         (chain (acc ...) rest ...))))

    ;; Copy phase — at least one _ was found, replace remaining _
    (define-syntax %chain-subst*
      (syntax-rules (_)
        ((%chain-subst* v (acc ...) (_ . more) rest ...)
         (%chain-subst* v (acc ... v) more rest ...))
        ((%chain-subst* v (acc ...) (x . more) rest ...)
         (%chain-subst* v (acc ... x) more rest ...))
        ((%chain-subst* v (acc ...) () rest ...)
         (chain (acc ...) rest ...))))

    ;; --- chain ---
    (define-syntax chain
      (syntax-rules ()
        ((chain initial) initial)
        ((chain initial (datum ...) rest ...)
         (let ((v initial))
           (%chain-subst v () (datum ...) rest ...)))))

    ;; --- chain-and: short-circuits on #f ---
    (define-syntax chain-and
      (syntax-rules ()
        ((chain-and initial) initial)
        ((chain-and initial step rest ...)
         (let ((v initial))
           (and v (chain-and (chain v step) rest ...))))))

    ;; --- chain-when: conditional steps ---
    (define-syntax chain-when
      (syntax-rules ()
        ((chain-when initial) initial)
        ((chain-when initial (guard? step) rest ...)
         (let ((v initial))
           (chain-when (if (guard? v) (chain v step) v) rest ...)))))

    ;; --- chain-lambda ---
    (define-syntax chain-lambda
      (syntax-rules ()
        ((chain-lambda steps ...)
         (lambda (v) (chain v steps ...)))))

    ;; --- nest helpers ---

    ;; Scan phase — no _ found yet
    (define-syntax %nest-subst
      (syntax-rules (_)
        ((%nest-subst (acc ...) (_ . more) inner)
         (%nest-subst* (acc ... inner) more inner))
        ((%nest-subst (acc ...) (x . more) inner)
         (%nest-subst (acc ... x) more inner))
        ((%nest-subst (acc ...) () inner)
         (acc ...))))

    ;; Copy phase — _ found, replace remaining _
    (define-syntax %nest-subst*
      (syntax-rules (_)
        ((%nest-subst* (acc ...) (_ . more) inner)
         (%nest-subst* (acc ... inner) more inner))
        ((%nest-subst* (acc ...) (x . more) inner)
         (%nest-subst* (acc ... x) more inner))
        ((%nest-subst* (acc ...) () inner)
         (acc ...))))

    ;; --- nest: outermost-first nesting ---
    ;; (nest (a _) (b _) c) => (a (b c))
    (define-syntax nest
      (syntax-rules ()
        ((nest expr) expr)
        ((nest (datum ...) rest ...)
         (%nest-subst () (datum ...) (nest rest ...)))))

    ;; --- nest-reverse helpers ---

    ;; Scan phase — no _ found yet
    (define-syntax %nest-rev-subst
      (syntax-rules (_)
        ((%nest-rev-subst val (acc ...) (_ . more) rest ...)
         (%nest-rev-subst* val (acc ... val) more rest ...))
        ((%nest-rev-subst val (acc ...) (x . more) rest ...)
         (%nest-rev-subst val (acc ... x) more rest ...))
        ((%nest-rev-subst val (acc ...) () rest ...)
         (nest-reverse (acc ...) rest ...))))

    ;; Copy phase — _ found, replace remaining _
    (define-syntax %nest-rev-subst*
      (syntax-rules (_)
        ((%nest-rev-subst* val (acc ...) (_ . more) rest ...)
         (%nest-rev-subst* val (acc ... val) more rest ...))
        ((%nest-rev-subst* val (acc ...) (x . more) rest ...)
         (%nest-rev-subst* val (acc ... x) more rest ...))
        ((%nest-rev-subst* val (acc ...) () rest ...)
         (nest-reverse (acc ...) rest ...))))

    ;; --- nest-reverse: innermost-first nesting ---
    ;; (nest-reverse c (b _) (a _)) => (a (b c))
    (define-syntax nest-reverse
      (syntax-rules ()
        ((nest-reverse expr) expr)
        ((nest-reverse expr (datum ...) rest ...)
         (%nest-rev-subst expr () (datum ...) rest ...))))))
