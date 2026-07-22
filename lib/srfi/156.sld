;;; SRFI 156 — Syntactic combiners for binary predicates
;;;
;;; `is`/`isnt` move a predicate from prefix to infix position for more
;;; readable comparisons: `(is x < y)` reads as "x is less than y" instead
;;; of `(< x y)`. Chains of more than two operands become a conjunction
;;; of adjacent comparisons (each middle term evaluated once via a
;;; hygienic temporary), and `_` marks a position that should instead
;;; become a lambda parameter, letting `is`/`isnt` also build predicate
;;; closures: `(is _ < 10)` is `(lambda (_) (< _ 10))`.
;;;
;;; Direct port of the SRFI's own portable reference implementation.

(define-library (srfi 156)
  (export is isnt)
  (import (scheme base))
  (begin

    (define-syntax infix/postfix
      (syntax-rules ()
        ((infix/postfix x somewhat?)
         (somewhat? x))

        ((infix/postfix left related-to? right)
         (related-to? left right))

        ((infix/postfix left related-to? right . likewise)
         (let ((right* right))
           (and (infix/postfix left related-to? right*)
                (infix/postfix right* . likewise))))))

    (define-syntax extract-placeholders
      (syntax-rules (_)
        ((extract-placeholders final () () body)
         (final (infix/postfix . body)))

        ((extract-placeholders final () args body)
         (lambda args (final (infix/postfix . body))))

        ((extract-placeholders final (_ op . rest) (args ...) (body ...))
         (extract-placeholders final rest (args ... arg) (body ... arg op)))

        ((extract-placeholders final (arg op . rest) args (body ...))
         (extract-placeholders final rest args (body ... arg op)))

        ((extract-placeholders final (_) (args ...) (body ...))
         (extract-placeholders final () (args ... arg) (body ... arg)))

        ((extract-placeholders final (arg) args (body ...))
         (extract-placeholders final () args (body ... arg)))))

    (define-syntax identity-syntax
      (syntax-rules ()
        ((identity-syntax form)
         form)))

    (define-syntax is
      (syntax-rules ()
        ((is . something)
         (extract-placeholders identity-syntax something () ()))))

    (define-syntax isnt
      (syntax-rules ()
        ((isnt . something)
         (extract-placeholders not something () ()))))))
