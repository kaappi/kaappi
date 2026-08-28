;;; SRFI 211 — Scheme Macro Libraries: (srfi 211 explicit-renaming).
;;;
;;; Explicit-renaming macros (Clinger's er-macro-transformer, as
;;; standardized by SRFI 211). A transformer procedure receives the fully
;;; unwrapped macro-use form and two procedures:
;;;
;;;   (rename datum)   — replaces the symbols at the datum's leaves by
;;;                      their renamings: identifiers that resolve in the
;;;                      macro's definition environment stay resolvable
;;;                      there, fresh identifiers become hygienic gensyms
;;;                      that cannot capture (or be captured by) use-site
;;;                      names. Renaming the same symbol twice within one
;;;                      expansion yields the same identifier.
;;;   (compare a b)    — free-identifier=?: the two identifiers denote the
;;;                      same binding, or both are unbound — the rule a
;;;                      syntax-rules literal matches by (R7RS 4.3.2), at
;;;                      the same strength this engine answers it for
;;;                      literals (see the compare paragraph below).
;;;
;;; SRFI 211 permits providing only some of its libraries but each provided
;;; one whole; this library's full export set is er-macro-transformer plus
;;; preidentifier? under the name identifier?. Kaappi's expander represents
;;; syntax as plain s-expressions — the presyntax representation — so an
;;; identifier is exactly a symbol (hygienic renames included).
;;;
;;; Engine notes (the mechanism lives in expander.expandProceduralMacro,
;;; compiler_macro.resolveTransformerSpecRec, and vm_library's
;;; whole-def-env import copy):
;;;
;;;   * The transformer expression is evaluated at macro-DEFINITION time in
;;;     the global environment — deliberate phase separation: enclosing
;;;     runtime locals have no values at expansion time and are invisible.
;;;     Library-internal helpers ARE visible to the expansion's output: an
;;;     imported procedural macro's whole definition environment is made
;;;     resolvable at the use site, the procedural analogue of the
;;;     template-free-reference copying syntax-rules macros get (a
;;;     procedural macro's references are computed by running code, so the
;;;     whole environment is the honest static over-approximation).
;;;
;;;   * Hygiene strength equals this engine's own syntax-rules hygiene
;;;     exactly for the auxiliary-keyword spellings — the documented
;;;     guarantee (KEP-0018 unresolved question 6, decided with
;;;     kaappi#2388): rename routes through the same renameForHygiene the
;;;     template instantiator uses, and compare through the same binding
;;;     machinery literal matching uses, so for reserved forms and macro
;;;     keywords (the spellings rename keeps bare and records) and for
;;;     gensym-marked renames of any other spelling, the two macro systems
;;;     answer every keyword-check quadrant identically
;;;     (regression-pinned, quadrant for quadrant, by the KEP-0006
;;;     four-quadrant test in tests/scheme/srfi/srfi211.scm). The
;;;     guarantee does NOT extend to spellings whose bare rename comes
;;;     from renameForHygiene's other bare-returning branches (e.g. the
;;;     VOID sentinel for a name defined later in the use-site body):
;;;     there compare keeps the reflexive use-token view while a
;;;     syntax-rules literal refuses — a pre-existing divergence, pinned
;;;     as such by the same suite. Shared, pre-existing limitations,
;;;     identical on both paths: a use-site TOP-LEVEL redefinition of a
;;;     name the macro's output references reaches the expansion; and a
;;;     reserved-form spelling the hygiene engine keeps bare (else, _,
;;;     ...) is shadowed by a use-site local of that spelling for a
;;;     macro-INTRODUCED occurrence just as surely as for a user-typed
;;;     one, while identifiers the engine CAN mark (any non-reserved
;;;     spelling, e.g. =>) stay hygienic.
;;;
;;;   * compare is binding-aware (kaappi#2388): (compare x (rename 'kw))
;;;     answers whether the use-site identifier x and the definition-side
;;;     keyword denote the same binding — an unshadowed use is #t, a
;;;     use-site local rebinding of the spelling is #f, and a renamed
;;;     (macro-introduced or global-name) keyword never resolves to a
;;;     use-site local. A rename of a name bound in the transformer's own
;;;     library (def-env-marked outside it) compares equal to a use-site
;;;     reference of the same exported binding, refusing only under a
;;;     local shadow. Symbols are interned, so a bare-rename product is
;;;     the same object as a use-site token of that spelling; compare
;;;     recognizes the classic (compare <token> (rename 'kw)) shape from
;;;     the invocation's rename record together with whether the spelling
;;;     occurs in the macro-use input (a bounded walk — datum labels make
;;;     inputs genuinely circular, and exhaustion conservatively counts as
;;;     occurrence) — which makes the answer independent of argument
;;;     order, and reflexive for two plain use-site tokens (the pairwise
;;;     input-comparison idiom) and for two of the invocation's own
;;;     rename products whenever the spelling is absent from the input.
;;;     The shape compare cannot settle, stated plainly: a spelling that
;;;     occurs in the input AND was bare-renamed this invocation, compared
;;;     under a use-site local shadow — if one argument is that input
;;;     token, the refusal is exactly the answer free-identifier=? demands
;;;     (the shadowing local is a different binding); if both arguments
;;;     were the invocation's own rename products, the #f is known-wrong
;;;     (a broken reflexivity), because interned symbols make the two
;;;     cases representationally identical and a distinguishable wrapper
;;;     for bare rename products would break the compiler's bare matching
;;;     of the reserved forms macros emit.
;;;
;;;   * `(rename 'x)` used to BIND x when x names a global procedure
;;;     returns x unrenamed (reference semantics win); rename fresh names
;;;     for binders — the classic ER idiom — and they gensym correctly.
;;;
;;; Verified: tests/scheme/srfi/srfi211.scm (including the KEP-0006
;;; four-quadrant acceptance test and the ER/syntax-rules parity suite)
;;; and the "SRFI 211" tests in src/tests_macros_procedural.zig
;;; (swap!/my-or hygiene, compare quadrants, rename of whole trees,
;;; library-helper resolution, let-syntax bodies).
(define-library (srfi 211 explicit-renaming)
  (import (scheme base)
          (srfi 211 primitives))
  (export er-macro-transformer identifier?)
  (begin
    (define (identifier? x) (symbol? x))))
