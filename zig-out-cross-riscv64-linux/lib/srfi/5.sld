;;; SRFI 5 — A compatible let form with signatures and rest arguments
;;;
;;; A faithful port of the SRFI's own syntax-rules reference implementation.
;;; No scope reduction was needed: the reference algorithm is already plain
;;; portable syntax-rules (no syntax-case, no brackets).
;;;
;;; This library redefines `let` itself rather than adding a new name.
;;; That works because Kaappi checks a use-site's macro bindings before
;;; falling back to built-in special forms (the same mechanism that lets
;;; SRFI 219 redefine `define`), so importing (srfi 5) makes plain `let`
;;; understand two extensions while remaining fully backward compatible:
;;;
;;;   - Signature-style named let: (let (name (var val) ...) body ...)
;;;     as an alternative to (let name ((var val) ...) body ...).
;;;   - Rest arguments on named let, in either style, via a dotted final
;;;     binding: (let name ((var val) ... . (rest-var rest-arg ...)) body ...)
;;;     or (let (name (var val) ... . (rest-var rest-arg ...)) body ...).
;;;
;;; The SRFI's rationale explicitly deprecates a third informal extension
;;; (binding names to unspecified values, e.g. (let (a b c) ...)) in favor
;;; of the existing (let ((a) (b) (c)) ...); that usage is correctly NOT
;;; supported here.

(define-library (srfi 5)
  (import (scheme base))
  (export let)
  (begin

    ;; The plain lambda-call let that `let` itself is defined in terms of.
    ;; Kept as a separate name (matching the SRFI reference, which calls it
    ;; standard-let) because `let` is about to be redefined below — the
    ;; macro can no longer refer to "the original let" by that name once
    ;; its own definition shadows it for the rest of any importing scope.
    (define-syntax %standard-let
      (syntax-rules ()
        ((_ ((var val) ...) body ...)
         ((lambda (var ...) body ...) val ...))))

    (define-syntax let
      (syntax-rules ()
        ;; No bindings: use %standard-let.
        ((let () body ...)
         (%standard-let () body ...))

        ;; All standard bindings: use %standard-let.
        ((let ((var val) ...) body ...)
         (%standard-let ((var val) ...) body ...))

        ;; One standard binding then more (a rest binding must follow):
        ;; peel it off and loop.
        ((let ((var val) . bindings) body ...)
         (%let-loop #f bindings (var) (val) (body ...)))

        ;; Signature-style name: (let (name binding ...) body ...).
        ((let (name binding ...) body ...)
         (%let-loop name (binding ...) () () (body ...)))

        ;; defun-style name: (let name bindings body ...).
        ((let name bindings body ...)
         (%let-loop name bindings () () (body ...)))))

    (define-syntax %let-loop
      (syntax-rules ()
        ;; Standard binding: destructure and loop.
        ((%let-loop name ((var0 val0) binding ...) (var ...) (val ...) body)
         (%let-loop name (binding ...) (var ... var0) (val ... val0) body))

        ;; Rest binding, no name: use %standard-let, listing the rest values.
        ((%let-loop #f (rest-var rest-val ...) (var ...) (val ...) body)
         (%standard-let ((var val) ... (rest-var (list rest-val ...))) . body))

        ;; No bindings left, name: call a letrec'ed lambda.
        ((%let-loop name () (var ...) (val ...) body)
         ((letrec ((name (lambda (var ...) . body)))
            name)
          val ...))

        ;; Rest binding, name: call a letrec'ed lambda with a rest parameter.
        ((%let-loop name (rest-var rest-val ...) (var ...) (val ...) body)
         ((letrec ((name (lambda (var ... . rest-var) . body)))
            name)
          val ... rest-val ...))))))
