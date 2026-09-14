;;; SRFI 226 (srfi 226 control continuations) — reduced subset
;;;
;;; See srfi/226/prompts.sld for what's out of scope and why. This file
;;; covers only the non-composable (escape-only) corner of the spec's
;;; continuations library:
;;;
;;; - call-with-non-composable-continuation and the call/cc aliases are
;;;   just Kaappi's own real call/cc. That call/cc is strictly more
;;;   capable than "non-composable" requires (it can re-enter, not just
;;;   escape), which is a safe direction to differ in: any client that
;;;   only escapes (the contract non-composable continuations promise)
;;;   behaves identically; nothing is disabled by aliasing.
;;; - call-with-continuation-barrier does NOT install a real barrier
;;;   (nothing here can actually stop a continuation from crossing it) —
;;;   it is a plain pass-through. Code that only depends on the barrier's
;;;   presence for tail-call-shape reasons works fine; code relying on it
;;;   to reject a bad continuation jump for safety gets no such
;;;   protection.
;;; - continuation-prompt-available? only supports the current
;;;   continuation (no second `cont` argument — that would need
;;;   reifying/inspecting an arbitrary captured continuation object,
;;;   which plain call/cc procedures don't expose).
;;; - unwind-protect is a direct port of the SRFI's own reference
;;;   implementation.
;;;
;;; call-with-composable-continuation, call-in-continuation, call-in,
;;; and return-to are not implemented — they need genuine re-entrant
;;; delimited (not just escape) continuation semantics tied to a specific
;;; prompt, which is a VM-level primitive this library can't fake.

(define-library (srfi 226 control continuations)
  (export call-with-non-composable-continuation
          call-with-current-continuation
          call/cc
          call-with-continuation-barrier
          continuation-prompt-available?
          unwind-protect)
  (import (scheme base) (srfi 226 control prompts))
  (begin

    (define (call-with-non-composable-continuation proc . rest)
      (call-with-current-continuation proc))

    ;; call-with-current-continuation/call/cc: re-exported as-is (Kaappi's
    ;; own, imported transitively via (scheme base) already provides
    ;; these names, so no redefinition is needed or attempted here beyond
    ;; what this library's export list already re-surfaces).

    (define (call-with-continuation-barrier thunk) (thunk))

    (define (continuation-prompt-available? tag . rest)
      (%prompt-tag-active? tag))

    (define-syntax unwind-protect
      (syntax-rules ()
        ((unwind-protect protected-expr cleanup-expr ...)
         (dynamic-wind
           (lambda () (values))
           (lambda () (call-with-continuation-barrier (lambda () protected-expr)))
           (lambda () (values) cleanup-expr ...)))))))
