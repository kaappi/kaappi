;;; SRFI 147 — Custom macro transformers.
;;;
;;; Extends R7RS's <transformer spec> grammar (previously only a literal
;;; `(syntax-rules ...)` form) with three more alternatives: a bare
;;; keyword (making the new name an alias for an existing one), a `(begin
;;; <definition>... <transformer spec>)` form (letting a transformer-
;;; generating-transformer introduce its own private helper macros while
;;; building up the final spec), and a macro use that itself expands --
;;; possibly through several steps -- to one of the other alternatives.
;;; This lets a library define its own named transformer-generating-
;;; transformer, e.g. the spec's own `syntax-rules*` worked example, which
;;; automatically wraps multi-form templates in `begin` so `((foo a b)
;;; (define a 1) (define b 2))` need not be written as `((foo a b) (begin
;;; (define a 1) (define b 2)))`. SRFI 148's `em-syntax-rules` -- the
;;; reason this SRFI was implemented -- needs the `begin` and bare-keyword
;;; alternatives together: its own reference implementation's
;;; `em-syntax-rules-aux1`/`em-syntax-rules-aux2` bottoms out through
;;; exactly `(begin (define-syntax a spec) a)`, a private helper followed
;;; by a bare reference to it.
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
;;; template constructs a nested `syntax-rules` form); a bare symbol is
;;; resolved by direct lookup in the same macro table instead. So, like
;;; SRFI 46 and SRFI 149, this library is a conformance statement, not new
;;; functionality on its own: it just re-exports the same
;;; `define-syntax`/`let-syntax`/`letrec-syntax`/`syntax-rules` already
;;; bound in `(scheme base)`.
;;;
;;; One case is deliberately NOT implemented (documented scope reduction,
;;; matching this codebase's practice of shipping an honest, reduced
;;; subset): aliasing a builtin special form (`if`, `lambda`, etc.), which
;;; has no `Transformer`-shaped value in the compiler's macro table to
;;; alias to, since builtins are recognized structurally rather than
;;; through that table. Aliasing any other, user-defined macro works.
(define-library (srfi 147)
  (import (only (scheme base) define-syntax let-syntax letrec-syntax syntax-rules))
  (export define-syntax let-syntax letrec-syntax syntax-rules))
