;; Regression test for #608: importing a macro must not leak the entire
;; def_env — only template-referenced names should be injected.
(import (scheme base) (scheme write) (scheme process-context))

(define-library (leak-test-lib)
  (export the-macro)
  (import (scheme base))
  (begin
    (define totally-unrelated 777)
    (define used-helper 999)
    (define-syntax the-macro
      (syntax-rules ()
        ((_ x) (+ x used-helper))))))

(import (only (leak-test-lib) the-macro))

(define failures 0)
(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (begin (set! failures (+ failures 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write actual) (newline))))

;; The macro itself must still work (used-helper is a template free ref)
(check "macro works" 1000 (the-macro 1))

;; totally-unrelated must NOT leak (never referenced by any template)
(check "unreferenced binding not leaked" #f
       (guard (exn (#t #f))
         (eval 'totally-unrelated (interaction-environment))))

(if (= failures 0)
    (begin (display "all passed") (newline))
    (begin (display failures) (display " failures") (newline) (exit 1)))
