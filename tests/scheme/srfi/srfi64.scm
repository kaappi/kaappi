;;; SRFI 64 (Test Suites) conformance tests

(import (scheme base) (scheme process-context) (srfi 64) (srfi 35))

(define %fail-count 0)

(test-begin "srfi-64")

;; Basic assertions
(test-group "assertions"
  (test-assert "assert true" #t)
  (test-equal "equal numbers" 42 (* 6 7))
  (test-equal "equal strings" "hello" (string-append "hel" "lo"))
  (test-equal "equal lists" '(1 2 3) (list 1 2 3))
  (test-eqv "eqv numbers" 100 (* 10 10))
  (test-eq "eq symbols" 'foo 'foo))

;; Approximate
(test-group "approximate"
  (test-approximate "float approx" 3.14 3.141 0.01)
  (test-approximate "exact match" 1.0 1.0 0.001))

;; Error testing
(test-group "errors"
  (test-error "error with #t" #t (error "boom"))
  (test-error "error with condition type" &error
    (raise (make-condition &error))))

;; Test groups
(test-group "groups"
  (test-assert "in group" #t)
  (test-group "nested"
    (test-assert "in nested group" #t)))

;; Skip and expect-fail
(test-group "skip-xfail"
  (test-skip "skipped")
  (test-assert "skipped" (error "should not run"))

  (test-expect-fail "expected-fail")
  (test-assert "expected-fail" #f))

;; Test runner state
(test-group "runner-state"
  (let ((r (test-runner-get)))
    (test-assert "runner exists" (test-runner? r))
    (test-assert "group path" (pair? (test-runner-group-path r)))))

;; Match predicates
(test-group "predicates"
  (test-assert "match-name" (procedure? (test-match-name "foo")))
  (test-assert "match-nth" (procedure? (test-match-nth 1)))
  (test-assert "match-all" (procedure? (test-match-all (test-match-name "x"))))
  (test-assert "match-any" (procedure? (test-match-any (test-match-name "x")))))

;; test-with-runner
(test-group "with-runner"
  (let ((null-runner (test-runner-null)))
    (test-with-runner null-runner
      (test-assert "under null runner" #t))
    (test-assert "back to original" #t)))

;; Result access
(test-group "results"
  (test-assert "result-ref" (let ((r (test-runner-get)))
    (test-result-set! r 'my-key 42)
    (eqv? (test-result-ref r 'my-key) 42))))

(set! %fail-count (test-runner-fail-count (test-runner-current)))
(test-end "srfi-64")
(if (> %fail-count 0) (exit 1))
