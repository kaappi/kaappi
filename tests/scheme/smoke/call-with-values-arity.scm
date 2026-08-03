;; Regression test for call-with-values ArityMismatch in multi-value branch
;; Issue #268

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "call-with-values-arity")

;; Multi-value arity mismatch should raise an error, not a type error
(test-equal "3 values into a 1-argument consumer raises"
            'error-caught
            (guard (exn (#t 'error-caught))
              (call-with-values (lambda () (values 1 2 3)) (lambda (x) x))))

;; Normal multi-value case still works
(test-equal "3 values into a 3-argument consumer"
            6
            (call-with-values (lambda () (values 1 2 3)) (lambda (a b c) (+ a b c))))

;; Single-value case still works
(test-equal "a single value into a 1-argument consumer"
            84
            (call-with-values (lambda () 42) (lambda (x) (* x 2))))

(let ((runner (test-runner-current)))
  (test-end "call-with-values-arity")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
