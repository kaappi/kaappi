;;; SRFI 213 — Identifier Properties.
;;;
;;; `(define-property <identifier> <key> <expression>)` evaluates
;;; <expression> at macro-expansion time and attaches the value to the pair
;;; (binding of <identifier>, binding of <key>) without disturbing either
;;; binding's meaning. A macro transformer reads properties back through a
;;; `lookup` procedure: per the SRFI, a transformer that returns the result
;;; of invoking `capture-lookup` on a procedure is re-entered with `lookup`
;;; as that procedure's argument — and the SRFI explicitly permits
;;; `capture-lookup` to be "substitutable by the identity
;;; (lambda (proc) proc)", which is exactly this implementation: the
;;; expander re-enters ANY procedural-transformer result that is a
;;; procedure (expander.expandProceduralMacro's re-entry loop), so
;;; returning `proc` bare and returning `(capture-lookup proc)` behave
;;; identically. `(lookup id key)` returns the property value or #f.
;;;
;;; define-property is an engine-level definition form (a compiler form,
;;; compiler_macro.compileDefineProperty; the properties live in a VM-owned
;;; table shared with the expander via globals.zig). Like syntax-rules it
;;; is recognized ambiently, so the export below is a declaration of intent
;;; rather than a binding — R7RS library export of engine-recognized syntax
;;; follows the same shape as SRFI 46/149's syntax-rules re-exports.
;;;
;;; Deliberate v1 scope reductions, documented here per this codebase's
;;; convention:
;;;
;;;   * Definition contexts: program and library top level only — a region
;;;     that extends to the end of the program, which the global table
;;;     models faithfully. Body-level define-property (whose properties
;;;     would need scoped retraction) is rejected at compile time.
;;;
;;;   * Binding resolution is nominal (name-based on hygiene-stripped
;;;     effective names), matching this symbol-based expander's identity
;;;     model — the same honesty note as SRFI 57's nominal conformance.
;;;     The SRFI's post-finalization note on merging properties across
;;;     re-imports is moot under name keying.
;;;
;;;   * lookup is available to procedural transformers (SRFI 211's
;;;     er-macro-transformer / lisp-transformer); syntax-rules transformers
;;;     have no way to receive a procedure, which matches the SRFI (its
;;;     lookup reaches transformers only through procedural macro
;;;     facilities).
;;;
;;; Verified: tests/scheme/srfi/srfi213.scm (top-level and library-level
;;; properties, wrapped and bare capture-lookup returns, missing-property
;;; #f, binding meaning undisturbed).
(define-library (srfi 213)
  (import (scheme base))
  (export define-property capture-lookup)
  (begin
    (define (capture-lookup proc) proc)))
