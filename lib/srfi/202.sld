;;; SRFI 202 — Pattern-matching Variant of the and-let* Form
;;;
;;; Extends SRFI 2's and-let* with SRFI-200-style patterns. A pattern claw
;;; is written quasiquoted, e.g. (`(,x . ,y) expr) — the leading backtick is
;;; what distinguishes a pattern claw from a plain SRFI 2 variable claw
;;; (var expr), since a bare identifier is otherwise ambiguous between "bind
;;; this variable" and "match this symbol literally". Self-contained (does
;;; not import (srfi 241)): and-let* claws only ever need wildcard/variable/
;;; pair/literal patterns, not 241's ellipsis, cata, or vector patterns.

(define-library (srfi 202)
  (import (scheme base))
  (export and-let*)
  (begin

    ;; Structural matcher for a single quasiquoted pattern.
    (define-syntax %qpat
      (syntax-rules (unquote _)
        ((_ val (unquote _) kt kf) kt)
        ((_ val (unquote var) kt kf) (let ((var val)) kt))
        ((_ val () kt kf) (if (null? val) kt kf))
        ((_ val (p1 . p2) kt kf)
         (if (pair? val)
             (%qpat (car val) p1 (%qpat (cdr val) p2 kt kf) kf)
             kf))
        ((_ val k kt kf) (if (equal? val (quote k)) kt kf))))

    ;; Peels patterns off an already-collected value list one at a time.
    ;; Running out of vals before the pattern list is exhausted means "too
    ;; few values" (kf). tailvar = #f means surplus values are discarded;
    ;; any other identifier means they're collected and bound to it.
    (define-syntax %match-vals
      (syntax-rules (quasiquote)
        ((_ vals () #f kt kf) kt)
        ((_ vals () tailvar kt kf) (let ((tailvar vals)) kt))
        ((_ vals ((quasiquote p1) p2 ...) tailvar kt kf)
         (if (pair? vals)
             (%qpat (car vals) p1 (%match-vals (cdr vals) (p2 ...) tailvar kt kf) kf)
             kf))
        ((_ vals (var p2 ...) tailvar kt kf)
         (if (pair? vals)
             (let ((var (car vals))) (%match-vals (cdr vals) (p2 ...) tailvar kt kf))
             kf))))

    ;; Like %match-vals, but the FIRST pattern additionally requires a
    ;; truthy value when it's a bare identifier — SRFI 202's rule for the
    ;; leading pattern of a multi-value (non-"values"-keyword) claw.
    (define-syntax %match-vals-first
      (syntax-rules (quasiquote)
        ((_ vals ((quasiquote p1) p2 ...) kt kf)
         (if (pair? vals)
             (%qpat (car vals) p1 (%match-vals (cdr vals) (p2 ...) #f kt kf) kf)
             kf))
        ((_ vals (var p2 ...) kt kf)
         (if (pair? vals)
             (let ((var (car vals)))
               (and var (%match-vals (cdr vals) (p2 ...) #f kt kf)))
             kf))))

    ;; Standard syntax-rules "peel off the last element" idiom: splits a
    ;; claw's raw (pat1 pat2 ... expr) into ((pat1 pat2 ...) expr), since
    ;; a general multi-pattern claw has no keyword to anchor the split on
    ;; (unlike the "values" form below).
    (define-syntax %split-claw
      (syntax-rules ()
        ((_ (last) (pat ...) (k more ...))
         (k (pat ...) last more ...))
        ((_ (p1 p2 more ...) (pat ...) k)
         (%split-claw (p2 more ...) (pat ... p1) k))))

    ;; Dispatches on the shape of the dotted tail captured from
    ;; (values p1 p2 ... . v*): when the claw is written without an
    ;; explicit collector (a proper list, e.g. (values a b)), that tail is
    ;; the literal () rather than a bindable identifier — %match-vals's #f
    ;; sentinel must be substituted in that case instead.
    (define-syntax %claw-values
      (syntax-rules ()
        ((_ (p ...) () expr cont)
         (call-with-values
           (lambda () expr)
           (lambda vals (%match-vals vals (p ...) #f cont #f))))
        ((_ (p ...) v* expr cont)
         (call-with-values
           (lambda () expr)
           (lambda vals (%match-vals vals (p ...) v* cont #f))))))

    (define-syntax %claw-multi
      (syntax-rules ()
        ((_ (pat ...) expr cont)
         (call-with-values
           (lambda () expr)
           (lambda vals (%match-vals-first vals (pat ...) cont #f))))))

    (define-syntax %and-let*-claws
      (syntax-rules (values quasiquote)
        ((_ ()) #t)
        ((_ () body1 body2 ...) (let () body1 body2 ...))

        ;; guard-only: (expr)
        ((_ ((gexpr) rest ...) body ...)
         (and gexpr (%and-let*-claws (rest ...) body ...)))

        ;; values-collecting: ((values p1 p2 ... . v*) expr)
        ((_ (((values p1 p2 ... . v*) expr) rest ...) body ...)
         (%claw-values (p1 p2 ...) v* expr (%and-let*-claws (rest ...) body ...)))

        ;; single quasiquoted pattern: (`pat expr)
        ((_ (((quasiquote pat) expr) rest ...) body ...)
         (%qpat expr pat (%and-let*-claws (rest ...) body ...) #f))

        ;; single bare-identifier claw: (var expr)  [SRFI 2, truthiness applies]
        ((_ ((var expr) rest ...) body ...)
         (let ((var expr)) (and var (%and-let*-claws (rest ...) body ...))))

        ;; general multi-value pattern claw: (pat1 pat2 pat3 ... expr)
        ((_ ((pat1 pat2 pat3 more ...) rest ...) body ...)
         (%split-claw (pat1 pat2 pat3 more ...) ()
                      (%claw-multi (%and-let*-claws (rest ...) body ...))))))

    (define-syntax and-let*
      (syntax-rules ()
        ((_ (claw ...) body ...)
         (%and-let*-claws (claw ...) body ...))))))
