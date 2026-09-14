;;; SRFI 139 — Syntax parameters.
;;;
;;; Solves the anaphoric-macro hygiene problem: rather than a macro
;;; unhygienically injecting a fresh identifier (e.g. a `return` or
;;; `abort` that only "works" because it happens to be visible at the use
;;; site), `define-syntax-parameter` declares one real keyword binding,
;;; and `syntax-parameterize` temporarily adjusts that keyword's
;;; transformer for the dynamic (well, lexical -- at macro-expansion
;;; time) extent of expanding a body, the way `parameterize` adjusts a
;;; runtime parameter's value. Once expansion finishes, the output is
;;; ordinary lexically-scoped code with no unhygienic injection anywhere.
;;;
;;; Fully portable on Kaappi's existing syntax-rules-only expander, no
;;; engine changes: `let-syntax` (`compileLetSyntax`, compiler_macro.zig)
;;; already implements exactly this "adjust the live macro table for a
;;; bounded compile extent, then restore it" behavior for its own body,
;;; which is syntax-parameterize's entire semantics. Verified against 5
;;; scenarios beyond the spec's own two examples: nested
;;; syntax-parameterize of the same keyword (shadow/restore), a body-local
;;; variable literally named the same as an unrelated keyword (capture
;;; avoidance), and using the keyword again after a syntax-parameterize
;;; extent has exited (must see the original transformer, not a stale
;;; one) -- see tests/scheme/srfi/srfi139.scm.
(define-library (srfi 139)
  (import (only (scheme base) define-syntax let-syntax syntax-rules))
  (export define-syntax-parameter syntax-parameterize)
  (begin
    (define-syntax define-syntax-parameter
      (syntax-rules ()
        ((_ name transformer-spec) (define-syntax name transformer-spec))))

    (define-syntax syntax-parameterize
      (syntax-rules ()
        ((_ ((name transformer-spec) ...) body ...)
         (let-syntax ((name transformer-spec) ...) body ...))))))
