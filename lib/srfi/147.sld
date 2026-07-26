;;; SRFI 147 — Custom macro transformers.
;;;
;;; Extends R7RS's <transformer spec> grammar (previously only a literal
;;; `(syntax-rules ...)` form) with two more alternatives: a bare keyword
;;; (making the new name an alias for an existing one) and a macro use
;;; that itself expands -- possibly through several steps -- to one of
;;; the other alternatives. This lets a library define its own named
;;; transformer-generating-transformer, e.g. the spec's own `syntax-rules*`
;;; worked example, which automatically wraps multi-form templates in
;;; `begin` so `((foo a b) (define a 1) (define b 2))` need not be written
;;; as `((foo a b) (begin (define a 1) (define b 2)))`. SRFI 148's
;;; `em-syntax-rules` -- the reason this SRFI was implemented -- is exactly
;;; this pattern: its own transformer-spec use expands to a nested literal
;;; `syntax-rules` form.
;;;
;;; Kaappi's `define-syntax`/`let-syntax`/`letrec-syntax` are native
;;; compiler forms, not macros a portable library could redefine (the
;;; spec's own sample implementation redefines them at the library level;
;;; that path doesn't exist here). Instead, `compileDefineSyntax`/
;;; `compileLetSyntax`/`compileLetrecSyntax` (src/compiler_macro.zig) now
;;; resolve a transformer-spec through `resolveTransformerSpec` before
;;; parsing it: when the spec's head is a registered macro keyword rather
;;; than literally `syntax-rules`, it's expanded (looping, depth-bounded)
;;; via the same `expander.expandMacro` every ordinary macro call already
;;; goes through, reusing the `NESTED_SR_FLAG`/`USERTEXT_MARKER`
;;; infrastructure built for SRFI 257's if-new-var idiom (a macro whose own
;;; template constructs a nested `syntax-rules` form). So, like SRFI 46
;;; and SRFI 149, this library is a conformance statement, not new
;;; functionality on its own: it just re-exports the same
;;; `define-syntax`/`let-syntax`/`letrec-syntax`/`syntax-rules` already
;;; bound in `(scheme base)`.
;;;
;;; Two of the grammar's alternatives are deliberately NOT implemented
;;; (documented scope reduction, matching this codebase's practice of
;;; shipping an honest, reduced subset): a bare keyword aliasing an
;;; existing one -- including a builtin special form, which has no
;;; `Transformer`-shaped value in the compiler's macro table to alias to,
;;; since builtins are recognized structurally rather than through that
;;; table -- and a macro use expanding to `(begin <definition>...
;;; <transformer-spec>)`. Neither is needed by SRFI 148.
(define-library (srfi 147)
  (import (only (scheme base) define-syntax let-syntax letrec-syntax syntax-rules))
  (export define-syntax let-syntax letrec-syntax syntax-rules))
