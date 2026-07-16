;; Regression test for #1177: (features), expression cond-expand, and
;; library cond-expand must agree on the same feature set.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "features-consistency")

;; (features) must return all platform features
(test-assert "r7rs in features" (and (memq 'r7rs (features)) #t))
(test-assert "kaappi in features" (and (memq 'kaappi (features)) #t))
(test-assert "ieee-float in features" (and (memq 'ieee-float (features)) #t))
;; Exactly one OS-class identifier: windows on Windows, posix elsewhere.
(test-assert "os feature in features"
  (cond-expand
    (windows (and (memq 'windows (features)) (not (memq 'posix (features))) #t))
    (else (and (memq 'posix (features)) (not (memq 'windows (features))) #t))))
(test-assert "exact-closed in features" (and (memq 'exact-closed (features)) #t))
(test-assert "exact-complex in features" (and (memq 'exact-complex (features)) #t))

;; KEP-0004 Phase 1: fibers/reactor/threads compiled in on this (native)
;; target. kaappi-threads is omitted on wasm32-wasi, not tested here.
(test-assert "kaappi-fibers in features" (and (memq 'kaappi-fibers (features)) #t))
(test-assert "kaappi-reactor in features" (and (memq 'kaappi-reactor (features)) #t))
(test-assert "kaappi-threads in features" (and (memq 'kaappi-threads (features)) #t))

;; Expression-level cond-expand must agree
(test-equal "expr cond-expand exact-closed" 'yes
  (cond-expand (exact-closed 'yes) (else 'no)))
(test-equal "expr cond-expand exact-complex" 'yes
  (cond-expand (exact-complex 'yes) (else 'no)))
(test-equal "expr cond-expand kaappi-fibers" 'yes
  (cond-expand (kaappi-fibers 'yes) (else 'no)))
(test-equal "expr cond-expand kaappi-reactor" 'yes
  (cond-expand (kaappi-reactor 'yes) (else 'no)))
(test-equal "expr cond-expand kaappi-threads" 'yes
  (cond-expand (kaappi-threads 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "features-consistency")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
