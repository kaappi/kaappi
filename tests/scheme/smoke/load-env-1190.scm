;; Regression test for #1190: load with optional environment-specifier
(import (scheme base) (scheme write) (scheme file) (scheme load) (scheme eval)
        (scheme process-context) (srfi 64))

(define tmp "/tmp/kaappi-load-env-1190.scm")

(test-begin "load-env-1190")

;; Single-argument form works (load evaluates for side effects)
(with-output-to-file tmp (lambda () (display "(define load-test-var-1 42)")))
(load tmp)
(test-equal "single-arg load defines variable" 42 load-test-var-1)

;; Two-argument form with (interaction-environment)
(with-output-to-file tmp (lambda () (display "(define load-test-var-2 99)")))
(load tmp (interaction-environment))
(test-equal "load with interaction-environment" 99 load-test-var-2)

;; Two-argument form with immutable (environment ...) — define must error (#1147)
(define custom-env (environment '(scheme base) '(scheme eval)))
(with-output-to-file tmp (lambda () (display "(define load-test-var-3 77)")))
(test-equal "load define into immutable env signals error" 'caught
  (guard (e (#t 'caught)) (load tmp custom-env)))

;; Non-environment second arg raises an error
(with-output-to-file tmp (lambda () (display "(+ 1 2)")))
(test-equal "load with bad env type" 'caught
  (guard (e (#t 'caught)) (load tmp 42)))

(delete-file tmp)

(let ((runner (test-runner-current)))
  (test-end "load-env-1190")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
