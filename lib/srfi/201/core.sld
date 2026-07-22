;;; (srfi 201 core) -- internal helper library for (srfi 201): the
;;; pattern-matching engine behind `mlambda`, factored out into its own
;;; library purely for organization (it has no dependency on anything
;;; `(srfi 201)`-specific). See lib/srfi/201.sld for why `(srfi 201)`
;;; exports `mlambda` rather than a macro literally named `lambda` --
;;; that finding is about the *bound name* the compiler ultimately sees,
;;; not about which library a helper macro happens to live in (an earlier
;;; theory here blamed cross-library visibility of `define-syntax`
;;; specifically; that theory didn't survive testing a macro named
;;; `lambda` that used this same separately-defined engine, which still
;;; hit the bug -- only renaming the compiler-visible macro away from
;;; `lambda` fixed it). `%201-core-lambda` below is an unremarkable alias
;;; and could just as well be plain `lambda` used directly in
;;; `(srfi 201)`.

(define-library (srfi 201 core)
  (import (scheme base))
  (export %201-fail %201-match-formals %201-core-lambda)
  (begin

    (define (%201-fail who val)
      (error "arguments do not match pattern" who val))

    (define-syntax %201-core-lambda
      (syntax-rules ()
        ((_ formals body1 body2 ...)
         (lambda formals body1 body2 ...))))

    (define-syntax %201-match-qq
      (syntax-rules (unquote)
        ((_ val (unquote var) kt kf)
         (let ((var val)) kt))
        ((_ val () kt kf)
         (if (null? val) kt kf))
        ((_ val (t1 . t2) kt kf)
         (if (pair? val)
             (%201-match-qq (car val) t1 (%201-match-qq (cdr val) t2 kt kf) kf)
             kf))
        ((_ val #(t ...) kt kf)
         (if (vector? val)
             (%201-match-qq (vector->list val) (t ...) kt kf)
             kf))
        ((_ val lit kt kf)
         (if (equal? val (quote lit)) kt kf))))

    (define-syntax %201-match-one
      (syntax-rules (quasiquote)
        ((_ val (quasiquote qpat) kt kf)
         (%201-match-qq val qpat kt kf))
        ((_ val var kt kf)
         (let ((var val)) kt))))

    (define-syntax %201-match-formals
      (syntax-rules ()
        ((_ val () kt kf)
         (if (null? val) kt kf))
        ((_ val (p1 . prest) kt kf)
         (if (pair? val)
             (%201-match-one (car val) p1
                              (%201-match-formals (cdr val) prest kt kf)
                              kf)
             kf))
        ((_ val p kt kf)
         (%201-match-one val p kt kf))))))
