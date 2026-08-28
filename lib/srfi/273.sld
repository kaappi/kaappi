;;; SRFI 273: Extensions to Data (Type-)Checking
;;;
;;; Quality-of-life extensions layered on SRFI 253: define-check for
;;; aliasing checking predicates under new names, declare-checked for
;;; advisory pre-/post-declarations, define-values-checked for checked
;;; multi-value binding, and the check-impl? auxiliary syntax for
;;; implementation-specific checks.
;;;
;;; The return-value (`=>`) checking this SRFI adds to the SRFI 253 forms
;;; lives in (srfi 253) itself — the SRFI 253 sample implementation carries
;;; it — so this library re-exports those forms rather than redefining them;
;;; importing (srfi 273) alone gives the complete vocabulary.
;;;
;;; Reference: https://srfi.schemers.org/srfi-273/srfi-273.html
;;; License: MIT
;;; Author: Artyom Bologov (reference impl); ported to Kaappi

(define-library (srfi 273)
  (import (scheme base)
          (scheme case-lambda)
          (srfi 253))
  (export
   ;; Re-exported from (srfi 253), with the => return-value checking.
   check-arg values-checked check-case
   lambda-checked define-checked
   case-lambda-checked define-record-type-checked
   ;; New in this SRFI.
   define-check declare-checked define-values-checked
   check-impl?)
  (begin

    ;; check-impl? — auxiliary syntax. (check-impl? datum) hands the datum
    ;; to the implementation in place of a predicate: the wrapper itself is
    ;; discarded as a non-predicate. Kaappi has no implementation-specific
    ;; check datatypes, so the datum is used unaltered as the check
    ;; expression — an unrecognized name (uint, pointer, ...) is an unbound
    ;; variable, which is why the spec's (values-checked ((check-impl? uint))
    ;; -1) is an error here too. Because check-arg is a macro in this
    ;; implementation, (check-arg (check-impl? name) x) also works.
    (define-syntax check-impl?
      (syntax-rules ()
        ((_ datum) datum)))

    ;; define-check — alias a checking predicate under a new name (a
    ;; compiled implementation could instead mint a derived type here).
    (define-syntax define-check
      (syntax-rules ()
        ((_ name predicate)
         (define name predicate))))

    ;; define-values-checked — like R7RS define-values, but the values
    ;; returned by form must satisfy the corresponding predicates.
    ;; call-with-values receives the values exactly once: splicing form
    ;; through values-checked would evaluate it once per value, which is
    ;; wrong for forms with effects or cost.
    (define-syntax define-values-checked
      (syntax-rules ()
        ((_ (var ...) (predicate ...) form)
         (define-values (var ...)
           (call-with-values
               (lambda () form)
             (lambda (var ...)
               (check-arg predicate var 'define-values-checked)
               ...
               (values var ...)))))))

    ;; declare-checked — advisory declaration of the checks for a value or
    ;; for a separately defined procedure. Expands to nothing, as in the
    ;; SRFI's reference implementation: Kaappi has no static checker to
    ;; inform, and re-wrapping an already-defined procedure — possibly an
    ;; imported one, e.g. (declare-checked (negative? (x real?)) =>
    ;; (boolean?)) — cannot be done portably from syntax-rules. Later
    ;; modifications of a declared value are likewise left unchecked. `=>`
    ;; is declared as a literal (as in every other =>-aware macro of this
    ;; port) so the third clause cannot silently capture an unrelated
    ;; form in that position.
    (define-syntax declare-checked
      (syntax-rules (=>)
        ((_ name predicate)
         (when #f #f))
        ((_ (name . args))
         (when #f #f))
        ((_ (name . args) => return)
         (when #f #f))))))
