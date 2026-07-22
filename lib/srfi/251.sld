;;; SRFI 251 — Mixing groups of definitions with expressions within bodies
;;;
;;; SRFI 251 relaxes R7RS's body grammar (definitions must all precede all
;;; expressions) to allow them to interleave, as long as no command or
;;; definition initializer references an identifier defined by a *later*
;;; definition group in the same body. It is specified purely as a grammar
;;; change with a translation function T into ordinary R7RS bodies:
;;;
;;;   T[command  body]        => command T[body]
;;;   T[definition+ body]     => ((lambda () definition+ T[body]))
;;;   T[expression]           => expression
;;;
;;; i.e. each maximal run of adjacent definitions opens a fresh,
;;; mutually-recursive scope (an immediately-invoked lambda) covering the
;;; rest of the body; a command before or between definition groups just
;;; stays where it is. The reference implementation is "a 5-line patch" to
;;; a host interpreter's own body parser — there is no reference macro.
;;;
;;; Since SRFI 251 introduces no new syntax of its own (the whole point is
;;; that ordinary bodies parse differently), a portable library has nothing
;;; to export under names of its own invention except by providing
;;; body-accepting forms explicitly. This library provides `mixed-lambda`,
;;; `mixed-define`, `mixed-let`, and `mixed-let*` — drop-in counterparts of
;;; `lambda`/`define`/`let`/`let*` whose bodies run through the T
;;; translation above (`mixed-let`/`mixed-let*`/`mixed-define` all desugar
;;; to `mixed-lambda` applications, so the translation is implemented once).
;;;
;;; Why not literally shadow `lambda`/`define`/`let`/`let*` (importing with
;;; `(except (scheme base) ...)` the way `(srfi 219)` shadows `define`)?
;;; Testing that against Kaappi during the sibling `(srfi 201)` port (see
;;; its header for the full writeup) found a real engine bug: a
;;; `define-syntax` whose bound name is literally one of the compiler's
;;; built-in special-form names, and whose expansion does anything beyond
;;; reproducing its input completely unchanged, either expands forever or
;;; corrupts the GC's root-tracking stack (surfacing much later as an
;;; unrelated panic in an unrelated library's `define-record-type`). Every
;;; one of these forms needs to restructure its body, so shadowing is not
;;; an option here either; hence the `mixed-` names.
;;;
;;; Scope, relative to the full SRFI:
;;;  - Only `mixed-lambda`/`mixed-define`/`mixed-let`/`mixed-let*` get the
;;;    relaxed grammar (covering SRFI 251's own worked examples, which are
;;;    all `let` bodies or a `define`d function body). `letrec`/`letrec*`/
;;;    `do`/named-let are not covered; nest a `mixed-lambda` call inside
;;;    them if you need interleaving there (`(letrec () ((mixed-lambda ()
;;;    ...)))`).
;;;  - "Is this form a definition?" is decided by literal leading keyword
;;;    (`define`, `define-values`, `define-syntax`, `define-record-type`)
;;;    at the macro level, not by fully macro-expanding every command to
;;;    see whether *it* produces a definition (SRFI 251's own text notes a
;;;    complete implementation needs to repeat "definition discovery"
;;;    after each command, which is exactly this whole-program-expansion
;;;    step). An unrecognized macro call is treated as a command and
;;;    placed in whatever `mixed-lambda` segment it falls into; Kaappi's
;;;    own body compiler *does* independently recognize a macro-produced
;;;    `define` reached that way, but only when the macro is invoked in
;;;    the same lambda-body scope where it (or an enclosing macro that
;;;    expands to it) was defined. SRFI 251's own `define-thunk` worked
;;;    example nests the definition group containing `define-thunk`'s use
;;;    one level deeper than the group defining `define-thunk` itself
;;;    (there's a `display` command, hence a new group, in between) —
;;;    confirmed empirically (not just asserted) to raise "undefined
;;;    variable" here, rather than the spec's "the result is: 0": a
;;;    body-local macro that expands to a `define`, invoked from a nested
;;;    lambda scope different from the one where the macro itself was
;;;    defined, isn't recognized as introducing a definition in that
;;;    inner scope, regardless of how the body reached that shape (this
;;;    reproduces with a hand-written pair of nested `(lambda () ...)`
;;;    forms and no SRFI 251 macro involved at all). The test suite
;;;    exercises and documents this precisely rather than asserting the
;;;    spec's answer.
;;;  - The spec requires rejecting, as a static (compile-time) error, a
;;;    command or initializer that illegally references an identifier from
;;;    a *later* definition group. This is not enforced: Kaappi bodies
;;;    have ordinary lexical scoping, so an illegal forward reference
;;;    simply resolves outward to whatever binding (if any) is visible in
;;;    an enclosing scope instead of being rejected — the same answer a
;;;    plain nested-lambda desugaring gives without any special-case
;;;    checking. This only differs observably from the spec on programs
;;;    that violate the visibility constraint in the first place (i.e.
;;;    programs the spec says must be rejected); every conforming body
;;;    gets the specified answer. The test suite includes and documents
;;;    this one discrepancy against SRFI 251's own example rather than
;;;    leaving it to be rediscovered as a surprise.

(define-library (srfi 251)
  (import (scheme base))
  (export mixed-lambda mixed-define mixed-let mixed-let*)
  (begin

    ;; T[<body>], dispatching on the shape of the first remaining form.
    (define-syntax %251-body
      (syntax-rules (define define-values define-syntax define-record-type)
        ;; base case: exactly one form left
        ((_ e) e)
        ;; a run of definitions starts here -- collect the maximal run
        ((_ (define . x) rest ...) (%251-defs ((define . x)) rest ...))
        ((_ (define-values . x) rest ...) (%251-defs ((define-values . x)) rest ...))
        ((_ (define-syntax . x) rest ...) (%251-defs ((define-syntax . x)) rest ...))
        ((_ (define-record-type . x) rest ...) (%251-defs ((define-record-type . x)) rest ...))
        ;; a command, with more body following: keep it in place, recurse
        ((_ command rest1 rest2 ...) (begin command (%251-body rest1 rest2 ...)))))

    ;; Collects a maximal run of adjacent definitions, then closes the
    ;; group with a fresh (lambda () defs... T[rest]) per the spec's T.
    (define-syntax %251-defs
      (syntax-rules (define define-values define-syntax define-record-type)
        ((_ (collected ...) (define . x) rest ...)
         (%251-defs (collected ... (define . x)) rest ...))
        ((_ (collected ...) (define-values . x) rest ...)
         (%251-defs (collected ... (define-values . x)) rest ...))
        ((_ (collected ...) (define-syntax . x) rest ...)
         (%251-defs (collected ... (define-syntax . x)) rest ...))
        ((_ (collected ...) (define-record-type . x) rest ...)
         (%251-defs (collected ... (define-record-type . x)) rest ...))
        ((_ (collected ...) rest ...)
         ((lambda () collected ... (%251-body rest ...))))))

    (define-syntax mixed-lambda
      (syntax-rules ()
        ((_ formals body1 body2 ...)
         (lambda formals (%251-body body1 body2 ...)))))

    (define-syntax mixed-define
      (syntax-rules ()
        ((_ (name . args) body1 body2 ...)
         (define name (mixed-lambda args body1 body2 ...)))
        ((_ name expr)
         (define name expr))))

    (define-syntax mixed-let
      (syntax-rules ()
        ((_ name ((v init) ...) body1 body2 ...)
         (letrec ((name (mixed-lambda (v ...) body1 body2 ...)))
           (name init ...)))
        ((_ ((v init) ...) body1 body2 ...)
         ((mixed-lambda (v ...) body1 body2 ...) init ...))))

    (define-syntax mixed-let*
      (syntax-rules ()
        ((_ () body1 body2 ...)
         (mixed-let () body1 body2 ...))
        ((_ ((v init) rest ...) body1 body2 ...)
         (mixed-let ((v init)) (mixed-let* (rest ...) body1 body2 ...)))))))
