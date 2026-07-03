;;; Regression: define-syntax forms produced by macro expansion mid-body
;;; must not escape their body scope (R7RS 5.3). The compiler previously
;;; registered them untracked, leaking the generated macro into the VM
;;; macro table for all subsequent top-level forms.
;;;
;;; Uses manual assertions instead of (srfi 64): a leaked macro keyword is
;;; a compile-time effect, and the checks must not depend on macro-heavy
;;; test machinery.
(import (scheme base) (scheme write) (scheme process-context))

(define failures 0)
(define (check label expected actual)
  (if (equal? expected actual)
      (begin (display "ok - ") (display label) (newline))
      (begin (set! failures (+ failures 1))
             (display "FAIL - ") (display label)
             (display ": expected ") (write expected)
             (display ", got ") (write actual) (newline))))

;; Inside the body, the generated macro must be usable for the rest of
;; the body.
(check "generated macro visible in rest of body" 'inner
  (let ()
    (define-syntax gen
      (syntax-rules ()
        ((gen name)
         (define-syntax name
           (syntax-rules ()
             ((name) 'inner))))))
    (gen probe)
    (probe)))

;; After the body, the name must be an ordinary identifier again: this
;; top-level definition and call must not expand the leaked macro.
(define (probe) 'proc)
(check "generated macro does not leak to top level" 'proc (probe))

;; Leading define-syntax in a body must also stay body-local.
(check "leading define-syntax visible in body" 1
  (let ()
    (define-syntax m (syntax-rules () ((m) 1)))
    (m)))
(define (m) 2)
(check "leading define-syntax does not leak to top level" 2 (m))

;; Top-level begin splices its body (R7RS 5.1), so a define-syntax inside
;; it is a top-level definition and must persist.
(begin
  (define-syntax keep (syntax-rules () ((keep) 7))))
(check "top-level begin define-syntax persists" 7 (keep))

(when (> failures 0) (exit 1))
