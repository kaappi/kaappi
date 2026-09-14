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
;;; This port documents exactly what is missing rather than taking the
;;; SRFI's word for it. The *underlying* splicing mechanism is correct:
;;; since kaappi#2075, a definition-context `begin` splices per R7RS 4.2.3 —
;;; a literal `(begin (define x 'inner) #f)` as a body element shadows an
;;; enclosing `x` and never touches the global, at top level exactly as
;;; inside a procedure (scanBodyDefs in src/compiler_lambda.zig unwraps
;;; spliceable begins before scanning). What still cannot be done is to
;;; reach that mechanism *from a macro*: the body scanner does not
;;; macro-expand an unrecognized head symbol to see whether its expansion
;;; contains definitions, so a macro use in a definition position is not
;;; itself a definition. A splicing-let-syntax implemented by expanding its
;;; body into a `begin` would make the SRFI's defining example work (the
;;; expansion's define then compiles inside the surrounding body scope and
;;; shadows the enclosing binding, exactly as a hand-written spliced
;;; `begin`'s does) — but a syntax-rules implementation cannot know whether
;;; its use site is a definition context, and the SRFI's own text warns the
;;; feature is not portable R7RS. This library therefore implements both
;;; forms as plain, direct delegates to their non-splicing R7RS
;;; counterparts:
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
