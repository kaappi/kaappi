;;; SRFI 242 — The CFG Language
;;;
;;; The full spec describes a language for composing control-flow graphs
;;; (CFGs) from nested "CFG terms": execute (multi-way branch), halt,
;;; bind (parallel let-values-style bindings), two flavors of labeled
;;; blocks — label*/labels — plus finally, permute, and a family of
;;; define-cfg-syntax*/define-cfg-label* forms for extending the CFG
;;; language itself with new macros.
;;;
;;; This port implements the STATIC subset: cfg, execute, halt, bind,
;;; label*, and call (always resolving to a label* binding). It does not
;;; implement labels/finally/permute or the define-cfg-* extension forms.
;;; Two independent reasons, both fundamental rather than incidental:
;;;
;;; 1. label* labels are "static": per spec, a call to one is equivalent
;;;    to re-expanding its bound CFG term inline at the call site. That's
;;;    exactly what this port does (via a local 0-ary let-syntax macro per
;;;    label), which is why a label* term naturally sees whatever loop
;;;    variables are lexically live at each call site with zero extra
;;;    machinery. labels labels are "dynamic": bound to a mutable CFG
;;;    location rather than inlined, which is what lets them form real
;;;    cycles (a static label's term can never mention itself — inlining
;;;    it would diverge at expansion time). But a dynamic label's block
;;;    can be *reached* from multiple call sites with different variables
;;;    live at each one, so the reference implementation must run a
;;;    dominance analysis over the whole CFG to work out which loop
;;;    variables the block needs as parameters and rewrite every call to
;;;    pass the right ones automatically — a genuine compiler back-end
;;;    pass, not a pattern-matching macro. That's beyond what a portable
;;;    syntax-rules transformer can reasonably do (the reference
;;;    implementation itself needs SRFI 213 and full syntax-case).
;;;    finally (return variables flowing out of a halted block) and
;;;    permute (non-deterministic block materialization) sit on top of
;;;    that same dynamic-label machinery, so they're out of scope for the
;;;    same reason.
;;; 2. define-cfg-syntax(*) let a program add new keywords to the CFG
;;;    language itself at the same expansion pass cfg/execute/labels use.
;;;    That needs procedural macros over the CFG term's own syntax
;;;    (matching R6RS syntax-case's er/rsc-style transformers, per the
;;;    spec's own sample implementation) — see keps/0006 and keps/0007 for
;;;    why Kaappi's syntax-rules-only macro system can't do this yet.
;;;
;;; None of this makes the static subset a toy: per SRFI 265 (this SRFI's
;;; successor), the CFG language "is not meant to be directly used in
;;; programs but by library authors to build abstractions like loop
;;; facilities on top of it" — and genuine iteration is still reachable
;;; within this subset by having execute's proc-expr call out to an
;;; ordinary (mutually) tail-recursive Scheme procedure that itself wraps
;;; a fresh cfg term per step; see tests/scheme/srfi/srfi242.scm for a
;;; worked factorial loop built exactly that way.

(define-library (srfi 242)
  (import (scheme base))
  ;; execute/halt/label*/call/bind are unbound syntactic keywords (like
  ;; cond's else/=>) recognized only inside a cfg term — they have no
  ;; independent binding to export, so only the cfg entry point is.
  (export cfg)
  (begin

    (define-syntax %cfg-expand
      (syntax-rules (execute halt label* call bind)

        ;; halt: the result expression, evaluated wherever this halt sits.
        ((_ (halt) result) result)

        ;; call: invoke the local macro a label* binding introduced —
        ;; re-expands that label's stored term right here.
        ((_ (call label) result) (label))

        ;; bind: parallel bindings, like let-values.
        ((_ (bind ((formals expr) ...) term) result)
         (let-values ((formals expr) ...) (%cfg-expand term result)))

        ;; execute: call proc-expr with one continuation procedure per
        ;; clause; proc-expr decides (via a tail call) which one runs.
        ((_ (execute proc-expr (formals term) ...) result)
         (proc-expr (lambda formals (%cfg-expand term result)) ...))

        ;; label*: no bindings left, just the body.
        ((_ (label* () body) result)
         (%cfg-expand body result))

        ;; label*: bind the first label as a local 0-ary macro standing
        ;; for its (unevaluated) term, then continue with the rest —
        ;; so a later label's term, or the body, can call an earlier
        ;; label, but a label's own term can't call itself (it isn't in
        ;; scope yet when its own term is bound).
        ((_ (label* ((label term) more ...) body) result)
         (let-syntax ((label (syntax-rules () ((_) (%cfg-expand term result)))))
           (%cfg-expand (label* (more ...) body) result)))))

    (define-syntax cfg
      (syntax-rules ()
        ((_ term result) (%cfg-expand term result))))))
