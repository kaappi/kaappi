(define-library (srfi 2)
  (import (scheme base))
  (export and-let*)
  (begin
    (define-syntax and-let*
      (syntax-rules ()
        ;; No claws: the form is #t, or the body runs (SRFI 2's
        ;; eval[(AND-LET* () FORM1 ...)] = eval[(LET* () FORM1 ...)]).
        ((and-let* () body ...)
         (begin #t body ...))
        ;; Last claw with no body: return the claw's value, per the formal
        ;; semantics eval[(AND-LET* (CLAW)), env] = eval_claw[CLAW, env]
        ;; (#2073). Each claw shape keeps the #f short-circuit.
        ((and-let* ((var expr)))
         (let ((var expr))
           (if var var #f)))
        ((and-let* ((expr)))
         (let ((t expr))
           (if t t #f)))
        ((and-let* (bound-var))
         (if bound-var bound-var #f))
        ;; At least one claw consumed, recursing into the rest; the body (if
        ;; any) runs once every claw has passed.
        ((and-let* ((var expr) rest ...) body ...)
         (let ((var expr))
           (if var (and-let* (rest ...) body ...) #f)))
        ((and-let* ((expr) rest ...) body ...)
         (if expr (and-let* (rest ...) body ...) #f))
        ((and-let* (bound-var rest ...) body ...)
         (if bound-var (and-let* (rest ...) body ...) #f))))))
