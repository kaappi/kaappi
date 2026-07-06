;; Regression test for #1190: load with optional environment-specifier
(import (scheme base) (scheme write) (scheme file) (scheme load) (scheme eval)
        (scheme process-context))

(define tmp "/tmp/kaappi-load-env-1190.scm")
(define pass 0)
(define fail 0)

(define (check name expected actual)
  (if (equal? expected actual)
    (set! pass (+ pass 1))
    (begin (set! fail (+ fail 1))
           (display "FAIL: ") (display name)
           (display " expected ") (write expected)
           (display " got ") (write actual) (newline))))

;; Single-argument form works (load evaluates for side effects)
(with-output-to-file tmp (lambda () (display "(define load-test-var-1 42)")))
(load tmp)
(check "single-arg load defines variable" 42 load-test-var-1)

;; Two-argument form with (interaction-environment)
(with-output-to-file tmp (lambda () (display "(define load-test-var-2 99)")))
(load tmp (interaction-environment))
(check "load with interaction-environment" 99 load-test-var-2)

;; Two-argument form with a custom environment — does not leak into globals
(with-output-to-file tmp (lambda () (display "(define load-test-var-3 77)")))
(load tmp (environment '(scheme base)))
(check "load with custom env does not define globally" 'caught
  (guard (e (#t 'caught)) load-test-var-3))

;; Non-environment second arg raises an error
(with-output-to-file tmp (lambda () (display "(+ 1 2)")))
(check "load with bad env type" 'caught
  (guard (e (#t 'caught)) (load tmp 42)))

(delete-file tmp)

(display pass) (display " passed, ") (display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
