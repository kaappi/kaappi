;;; SRFI 236 — Evaluating expressions in an unspecified order
;;;
;;; A single form, `independently`, that combines side-effecting
;;; expressions like `begin` but explicitly does not promise any
;;; evaluation order between them (unlike `begin`, which is strictly
;;; left-to-right) — useful both as documentation of intent and to leave
;;; room for reordering. This is a direct port of the SRFI's own portable
;;; R7RS-small reference implementation.

(define-library (srfi 236)
  (export independently)
  (import (scheme base))
  (begin

    (define-syntax independently
      (syntax-rules ()
        ((independently expr ...)
         (independently-aux (expr ...)))))

    (define-syntax independently-aux
      (syntax-rules ()
        ((independently-aux () (expr tmp) ...)
         (let ((tmp (begin expr #f)) ...) (values)))
        ((independently-aux (expr . exprs) . binds)
         (independently-aux exprs (expr tmp) . binds))))))
