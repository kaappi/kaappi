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
;;;   (compare a b)    — free-identifier=? to the strength this engine can
;;;                      answer (see limitations below).
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
;;;     exactly — rename routes through the same renameForHygiene the
;;;     template instantiator uses. The shared, pre-existing limitation:
;;;     a use-site TOP-LEVEL redefinition of a name the macro's output
;;;     references (e.g. redefining a library helper's name after import)
;;;     reaches the expansion, for procedural and syntax-rules macros
;;;     alike. compare is name-based (hygiene-stripped equality), which
;;;     answers the classic literal checks (else, =>) correctly but cannot
;;;     distinguish two same-named bindings.
;;;
;;;   * `(rename 'x)` used to BIND x when x names a global procedure
;;;     returns x unrenamed (reference semantics win); rename fresh names
;;;     for binders — the classic ER idiom — and they gensym correctly.
;;;
;;; Verified: tests/scheme/srfi/srfi211.scm and the "SRFI 211" tests in
;;; src/tests_macros.zig (swap!/my-or hygiene, compare on else, rename of
;;; whole trees, library-helper resolution, let-syntax bodies).
(define-library (srfi 211 explicit-renaming)
  (import (scheme base)
          (srfi 211 primitives))
  (export er-macro-transformer identifier?)
  (begin
    (define (identifier? x) (symbol? x))))
