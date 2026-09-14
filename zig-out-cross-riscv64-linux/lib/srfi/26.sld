(define-library (srfi 26)
  (import (scheme base))
  (export cut cute)
  (begin
    ;; Recursive helper for cut — accumulates slot-names and the call form.
    ;; Slots become lambda parameters; all expressions stay in the body
    ;; so they evaluate at call time.
    (define-syntax srfi-26-internal-cut
      (syntax-rules (<> <...>)
        ((srfi-26-internal-cut (slot-name ...) (proc arg ...))
         (lambda (slot-name ...) (proc arg ...)))
        ((srfi-26-internal-cut (slot-name ...) (proc arg ...) <...>)
         (lambda (slot-name ... . rest-slot) (apply proc arg ... rest-slot)))
        ((srfi-26-internal-cut (slot-name ...) (proc arg ...) <> . se)
         (srfi-26-internal-cut (slot-name ... x) (proc arg ... x) . se))
        ((srfi-26-internal-cut (slot-name ...) (proc arg ...) nse . se)
         (srfi-26-internal-cut (slot-name ...) (proc arg ... nse) . se))))

    ;; Entry: separate the operator so (proc arg ...) always has >= 1 element.
    (define-syntax cut
      (syntax-rules (<> <...>)
        ((cut <> . se)
         (srfi-26-internal-cut (x) (x) . se))
        ((cut f . se)
         (srfi-26-internal-cut () (f) . se))))

    ;; Recursive helper for cute — wraps each non-slot expression in a
    ;; nested let immediately, so it evaluates once at construction time.
    (define-syntax srfi-26-internal-cute
      (syntax-rules (<> <...>)
        ((srfi-26-internal-cute (slot-name ...) (proc arg ...))
         (lambda (slot-name ...) (proc arg ...)))
        ((srfi-26-internal-cute (slot-name ...) (proc arg ...) <...>)
         (lambda (slot-name ... . rest-slot) (apply proc arg ... rest-slot)))
        ((srfi-26-internal-cute (slot-name ...) (proc arg ...) <> . se)
         (srfi-26-internal-cute (slot-name ... x) (proc arg ... x) . se))
        ((srfi-26-internal-cute (slot-name ...) (proc arg ...) nse . se)
         (let ((y nse))
           (srfi-26-internal-cute (slot-name ...) (proc arg ... y) . se)))))

    ;; Entry: operator slot passes through; operator expression is let-bound.
    (define-syntax cute
      (syntax-rules (<> <...>)
        ((cute <> . se)
         (srfi-26-internal-cute (x) (x) . se))
        ((cute f . se)
         (let ((t f))
           (srfi-26-internal-cute () (t) . se)))))))
