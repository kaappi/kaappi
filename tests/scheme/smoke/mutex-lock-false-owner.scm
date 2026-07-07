;; Regression test for #1154: mutex-lock! with explicit #f thread argument
;; must yield locked/not-owned, not assign the current thread as owner.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "mutex-lock-false-owner")

;; Basic case: lock with #f thread, #f timeout
(let ((m (make-mutex)))
  (mutex-lock! m #f #f)
  (test-equal "mutex-state is not-owned" 'not-owned (mutex-state m)))

;; Lock with #f thread, no timeout
(let ((m (make-mutex)))
  (mutex-lock! m #f #f)
  (test-assert "mutex is locked" (not (eq? (mutex-state m) 'not-abandoned))))

;; Default (no thread arg) should still assign the current thread
(let ((m (make-mutex)))
  (mutex-lock! m)
  (test-assert "default lock assigns current thread"
    (not (eq? (mutex-state m) 'not-owned))))

(let ((runner (test-runner-current)))
  (test-end "mutex-lock-false-owner")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
