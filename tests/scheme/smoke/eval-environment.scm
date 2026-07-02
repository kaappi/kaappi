;; Regression test for #691: eval must honor its environment-specifier argument

(import (scheme base) (scheme write) (scheme eval))

;; null-environment should not have procedure bindings
(guard (exn (#t 'ok))
  (eval '(+ 1 2) (null-environment 5))
  (display "FAIL: null-environment should not have +") (newline) (exit 1))

;; environment with (scheme base) should work
(let ((result (eval '(+ 1 2) (environment '(scheme base)))))
  (unless (= result 3)
    (display "FAIL: environment (scheme base) gave wrong result") (newline) (exit 1)))

;; scheme-report-environment should work like (scheme base)
(let ((result (eval '(* 6 7) (scheme-report-environment 5))))
  (unless (= result 42)
    (display "FAIL: scheme-report-environment gave wrong result") (newline) (exit 1)))

;; interaction-environment should see user defines
(define x 42)
(let ((result (eval 'x (interaction-environment))))
  (unless (= result 42)
    (display "FAIL: interaction-environment did not see define") (newline) (exit 1)))

;; environment? predicate via type check
(let ((e (environment '(scheme base))))
  (unless (eval '(+ 10 20) e)
    (display "FAIL: eval in environment returned false") (newline) (exit 1)))

(display "PASS") (newline)
