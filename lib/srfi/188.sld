;;; SRFI 188 — Splicing binding constructs for syntactic keywords
;;;
;;; SRFI 188 defines `splicing-let-syntax`/`splicing-letrec-syntax`: like
;;; `let-syntax`/`letrec-syntax`, except that in a definition context their
;;; body forms are spliced into the *enclosing* definition context, the same
;;; way `begin` splices rather than introducing a new scope. The SRFI's own
;;; text is explicit that this cannot be done portably: "A portable R7RS
;;; implementation of the binding constructs described here is not
;;; possible" — every existing implementation (Chibi, Chez, Racket) provides
;;; it as a primitive expander feature, not a library.
;;;
;;; This port confirms that verdict for Kaappi specifically (rather than
;;; taking the SRFI's word for it) and documents exactly what is missing.
;;; Kaappi's internal-definition scanner (`scanBodyDefs` in
;;; src/compiler_lambda.zig) recognizes a definition only when a *literal*
;;; `define`, `define-record-type`, or `define-syntax` token appears
;;; directly as a body element; it does not macro-expand an unrecognized
;;; head symbol to see whether it produces one, and it has no splicing rule
;;; for a `begin` reached that way (`begin`'s own splicing is handled
;;; earlier, by the reader/expander, only when `begin` is the literal head
;;; symbol actually written by the user). A macro that expands to
;;; `(begin (define k v) ...)` therefore cannot make `k` escape into the
;;; surrounding body — confirmed empirically (not just by reading the code):
;;; even a hand-written, non-macro
;;;   (let ((x 'outer)) (begin (define x 'inner) #f) x)
;;; evaluates to `outer`, not `inner`, in Kaappi. Splicing a *fresh* (i.e.
;;; non-shadowing) name out of a `begin` reached this way does work — the
;;; failure is specifically that redefining a name already bound in the
;;; enclosing scope, via a `define` that isn't itself the literal leading
;;; body form, does not shadow it — but that narrower case is not what SRFI
;;; 188's own defining example exercises (it is a shadowing example — see
;;; below), so special-casing it here would not make the flagship behavior
;;; correct and was left out for a simpler, uniform implementation.
;;;
;;; Given that, this library implements both forms as plain, direct
;;; delegates to their non-splicing R7RS counterparts:
;;;
;;;   splicing-let-syntax    == let-syntax
;;;   splicing-letrec-syntax == letrec-syntax
;;;
;;; Consequences:
;;;  - Whenever `form ...` contains no definitions meant to outlive the
;;;    construct (by far the common case — reaching for a local helper
;;;    macro across a sequence of expressions), this is observationally
;;;    identical to a real splicing implementation.
;;;  - The one case SRFI 188 exists for — an internal definition inside
;;;    `form ...` that should become visible to code *after* the
;;;    splicing-let-syntax/splicing-letrec-syntax form — does not work here:
;;;    it stays scoped to the (non-spliced) body, exactly as with ordinary
;;;    let-syntax/letrec-syntax. The SRFI's own worked example demonstrates
;;;    precisely this case; the test suite includes it and documents the
;;;    resulting (non-spliced) answer rather than silently asserting the
;;;    spec's answer.
;;;  - The `keyword`/`transformer spec` bindings themselves behave exactly
;;;    as they do for non-splicing `let-syntax`/`letrec-syntax` (unaffected
;;;    by the above): `splicing-let-syntax`'s transformers see the
;;;    surrounding environment, `splicing-letrec-syntax`'s transformers see
;;;    each other, matching R7RS `let-syntax`/`letrec-syntax` exactly.

(define-library (srfi 188)
  (import (scheme base))
  (export splicing-let-syntax splicing-letrec-syntax)
  (begin

    (define-syntax splicing-let-syntax
      (syntax-rules ()
        ((_ bindings form ...) (let-syntax bindings form ...))))

    (define-syntax splicing-letrec-syntax
      (syntax-rules ()
        ((_ bindings form ...) (letrec-syntax bindings form ...))))))
