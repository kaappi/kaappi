;; Regression test for #1177: (features), expression cond-expand, and
;; library cond-expand must agree on the same feature set.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "features-consistency")

;; (features) must return all platform features
(test-assert "r7rs in features" (and (memq 'r7rs (features)) #t))
(test-assert "kaappi in features" (and (memq 'kaappi (features)) #t))
(test-assert "ieee-float in features" (and (memq 'ieee-float (features)) #t))
(test-assert "posix in features" (and (memq 'posix (features)) #t))
(test-assert "exact-closed in features" (and (memq 'exact-closed (features)) #t))
(test-assert "exact-complex in features" (and (memq 'exact-complex (features)) #t))

;; Expression-level cond-expand must agree
(test-equal "expr cond-expand exact-closed" 'yes
  (cond-expand (exact-closed 'yes) (else 'no)))
(test-equal "expr cond-expand exact-complex" 'yes
  (cond-expand (exact-complex 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "features-consistency")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
