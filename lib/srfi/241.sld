;;; SRFI 241 — Match
;;;
;;; A syntax-rules-only port of the Wright-Cartwright-Shinn matcher (Kaappi
;;; has no syntax-case). The "trick" throughout is giving every helper macro
;;; a custom ellipsis identifier (%%%) so the literal three-dot token can be
;;; matched as ordinary data instead of triggering syntax-rules' own
;;; repetition — that is what lets a pattern like (,x ... . ,y) be recognized
;;; by shape rather than misinterpreted as "repeat the sub-pattern ,x".
;;;
;;; Scope, relative to the full SRFI:
;;;  - Ellipsis-repeated sub-patterns are supported only in the two shapes
;;;    (subpat ...) and (subpat ... . tailpat), and only when subpat is a
;;;    plain ,var, ,_, or a repeated default-cata ,(var) (which collects
;;;    (map self ...) — the shape used by the SRFI's own "(+ ,[x*] ...)"
;;;    example) — not an arbitrary compound pattern. This covers the
;;;    overwhelmingly common "collect the rest" use.
;;;  - Vector patterns support fixed length (#(p1 p2 ...)) and whole-vector
;;;    ellipsis (#(p ...)), not a mixed mandatory-prefix/suffix segment.
;;;  - Square-bracket clause notation isn't available (Kaappi's reader has no
;;;    bracket syntax); write clauses and cata patterns with plain parens,
;;;    e.g. (,(f -> x y) ...) rather than [,[f -> x y] ...].
;;;  - The ellipsis-aware quasiquote that SRFI 241 binds inside match bodies
;;;    is not provided; ordinary (scheme base) quasiquote is in scope there,
;;;    which covers everything but templates that splice an ellipsis-bound
;;;    variable.
;;;  - Per the spec, cata operators are evaluated only after a clause's
;;;    guard passes. This implementation evaluates them as part of the
;;;    structural match instead (before the guard), which only differs
;;;    observably if a cata operator has a side effect and the guard then
;;;    rejects the clause.

(define-library (srfi 241)
  (import (scheme base))
  (export match)
  (begin

    (define (%match-fail val)
      (error "match: no matching clause" val))

    (define (%scan-tail-to-end val)
      (if (pair? val) (%scan-tail-to-end (cdr val)) val))

    (define (%split-tail val)
      (let loop ((v val) (acc '()))
        (if (pair? v)
            (loop (cdr v) (cons (car v) acc))
            (values (reverse acc) v))))

    ;; (%match-ellipsis-var val self var tailpat kt kf)
    ;; var/tailpat are unexpanded syntax fragments from the original pattern.
    (define-syntax %match-ellipsis-var
      (syntax-rules %%% (unquote _)
        ((_ val self _ () kt kf)
         (if (list? val) kt kf))
        ((_ val self _ (unquote tv) kt kf)
         (let ((tv (%scan-tail-to-end val))) kt))
        ((_ val self var () kt kf)
         (if (list? val) (let ((var val)) kt) kf))
        ((_ val self var (unquote tv) kt kf)
         (let-values (((var tv) (%split-tail val))) kt))))

    ;; Dispatches on the shape of the repeated sub-pattern; only ,var / ,_
    ;; and repeated default-cata ,(var) are supported (see file header).
    (define-syntax %match-ellipsis-list
      (syntax-rules %%% (unquote)
        ;; (,(var) ...)  repeated default-cata: collect (map self ...)
        ((_ val self (unquote (var)) () kt kf)
         (if (list? val) (let ((var (map self val))) kt) kf))
        ((_ val self (unquote var) tailpat kt kf)
         (%match-ellipsis-var val self var tailpat kt kf))))

    (define-syntax %match-pat
      (syntax-rules %%% (unquote _ -> ...)
        ;; ,_  wildcard
        ((_ val self (unquote _) kt kf) kt)

        ;; ,(op -> v ...)  named cata: op is applied to val, results bound to v ...
        ((_ val self (unquote (op -> v %%%)) kt kf)
         (let-values (((v %%%) (op val))) kt))

        ;; ,(v ...)  default cata: re-invokes the enclosing match on val
        ((_ val self (unquote (v %%%)) kt kf)
         (let-values (((v %%%) (self val))) kt))

        ;; ,var  variable binding
        ((_ val self (unquote var) kt kf)
         (let ((var val)) kt))

        ;; ()  empty list
        ((_ val self () kt kf)
         (if (null? val) kt kf))

        ;; #(sub ...)  whole-vector ellipsis ("..." matched literally)
        ((_ val self #(sub ...) kt kf)
         (if (vector? val)
             (%match-ellipsis-list (vector->list val) self sub () kt kf)
             kf))

        ;; #(p1 p2 ...)  fixed-length vector
        ((_ val self #(p %%%) kt kf)
         (if (vector? val)
             (%match-pat (vector->list val) self (p %%%) kt kf)
             kf))

        ;; (p1 ... . prest)  ellipsis + tail ("..." matched literally)
        ((_ val self (p1 ... . prest) kt kf)
         (%match-ellipsis-list val self p1 prest kt kf))

        ;; (p1 . p2)  pair
        ((_ val self (p1 . p2) kt kf)
         (if (pair? val)
             (%match-pat (car val) self p1 (%match-pat (cdr val) self p2 kt kf) kf)
             kf))

        ;; symbol or self-evaluating constant, matched via equal?
        ((_ val self k kt kf)
         (if (equal? val (quote k)) kt kf))))

    (define-syntax %match-clauses
      (syntax-rules %%% (guard)
        ((_ t self () fail-expr) fail-expr)
        ((_ t self ((pat (guard g %%%) body1 body2 %%%) rest %%%) fail-expr)
         (let ((kf (lambda () (%match-clauses t self (rest %%%) fail-expr))))
           (%match-pat t self pat
                       (if (and g %%%) (begin body1 body2 %%%) (kf))
                       (kf))))
        ((_ t self ((pat body1 body2 %%%) rest %%%) fail-expr)
         (let ((kf (lambda () (%match-clauses t self (rest %%%) fail-expr))))
           (%match-pat t self pat (begin body1 body2 %%%) (kf))))))

    (define-syntax match
      (syntax-rules ()
        ((_ expr clause ...)
         (letrec ((self (lambda (t) (%match-clauses t self (clause ...) (%match-fail t)))))
           (self expr)))))))
