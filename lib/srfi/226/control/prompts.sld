;;; SRFI 226 (srfi 226 control prompts) — delimited escape via tagged prompts
;;;
;;; SRFI 226 as a whole is enormous — 12 sub-libraries unifying delimited
;;; continuations, continuation marks, parameters, fluids, promises,
;;; exceptions, and threads into one system, superseding SRFI 15/34/39/
;;; 154/155/157. Most of that needs either genuine new VM primitives
;;; (composable/re-entrant delimited continuations, per-frame
;;; continuation marks) or identifier-macro support R7RS syntax-rules
;;; doesn't guarantee (fluids). This port covers only what's honestly
;;; buildable as a portable library on top of Kaappi's existing call/cc,
;;; dynamic-wind, and make-parameter: prompts (this file, escape-only —
;;; see below), non-composable continuations and a couple of small
;;; procedures (control/continuations.sld), and times (control/times.sld).
;;; Composable continuations, continuation marks, fluids, the exceptions/
;;; conditions/threads libraries (all redundant with or need more than
;;; R7RS's own raise/guard/with-exception-handler and SRFI-18 already
;;; provide), interrupts, and thread-locals are not implemented.
;;;
;;; call-with-continuation-prompt/abort-current-continuation are built
;;; from Kaappi's full call/cc: a prompt captures an escape continuation
;;; keyed by its tag onto a dynamically-scoped stack (a parameter, so
;;; nesting/unwinding is automatic), and abort-current-continuation looks
;;; up the nearest matching tag and invokes it. Since this is built on
;;; ESCAPE continuations only, calling abort finds the target and jumps
;;; there and applies its handler there — it does not support resuming
;;; back into the aborted computation (that would need composable
;;; continuations, out of scope here).
;;;
;;; Two further honest gaps from this same escape-only limitation: (1)
;;; the spec's default abort handler, when none is supplied, reinstalls
;;; the prompt and *resumes* the aborted computation's continuation with
;;; no arguments — that resumption is exactly the composable-continuation
;;; capability this port doesn't have, so the default handler here only
;;; does the first-order approximation of "the aborted values become the
;;; result of call-with-continuation-prompt" (matching the case where the
;;; real default handler's resumed continuation would immediately return
;;; those values anyway), without reinstalling the prompt for reuse
;;; afterward; (2) aborting to an unavailable tag raises a plain R7RS
;;; `error` rather than a Racket-style `&continuation` condition object,
;;; since R7RS has no equivalent condition-type hierarchy to model it against.

(define-library (srfi 226 control prompts)
  (export make-continuation-prompt-tag
          default-continuation-prompt-tag
          continuation-prompt-tag?
          call-with-continuation-prompt
          abort-current-continuation
          ;; Not part of the SRFI's public API — exported only so
          ;; (srfi 226 control continuations) can implement
          ;; continuation-prompt-available? against the same stack.
          %prompt-tag-active?)
  (import (scheme base))
  (begin

    (define (make-continuation-prompt-tag . maybe-name)
      (list 'continuation-prompt-tag (if (pair? maybe-name) (car maybe-name) #f)))

    (define (continuation-prompt-tag? obj)
      (and (pair? obj) (eq? (car obj) 'continuation-prompt-tag)))

    (define %default-prompt-tag (make-continuation-prompt-tag 'default))
    (define (default-continuation-prompt-tag) %default-prompt-tag)

    ;; Dynamically-scoped alist of (tag . escape-procedure), innermost
    ;; prompt first. A parameter (rather than a manually set!-mutated
    ;; list) so entries are automatically popped on any non-local exit.
    ;;
    ;; Per spec, a prompt tagged with the default tag is available in the
    ;; initial continuation of every thread, so the parameter's own
    ;; default value pre-populates one entry for it. There is no real
    ;; call/cc capture to escape to at this level (the "initial
    ;; continuation" isn't something this library controls), so its
    ;; escape procedure is just a plain values-returning passthrough --
    ;; aborting to the default tag with nothing else installed simply
    ;; yields the aborted values as an ordinary return, which is the
    ;; closest honest approximation reachable without controlling the
    ;; program's own entry point.
    (define %prompt-stack (make-parameter (list (cons %default-prompt-tag (lambda vals (apply values vals))))))

    (define (call-with-continuation-prompt thunk . rest)
      (let* ((tag (if (pair? rest) (car rest) (default-continuation-prompt-tag)))
             (handler (if (and (pair? rest) (pair? (cdr rest)))
                          (cadr rest)
                          (lambda vals (apply values vals)))))
        (call-with-current-continuation
          (lambda (k)
            (parameterize
                ((%prompt-stack
                   (cons (cons tag (lambda vals (call-with-values (lambda () (apply handler vals)) k)))
                         (%prompt-stack))))
              (thunk))))))

    (define (abort-current-continuation tag . vals)
      (let ((entry (assoc tag (%prompt-stack) eq?)))
        (if entry
            (apply (cdr entry) vals)
            (error "abort-current-continuation: no matching prompt installed" tag))))

    (define (%prompt-tag-active? tag)
      (and (assoc tag (%prompt-stack) eq?) #t))))
