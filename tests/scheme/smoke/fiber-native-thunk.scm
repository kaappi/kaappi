;; Regression test for #1155: spawn must accept native (built-in)
;; procedures, not only closures.
;;
;; Note: fibers inside SRFI-64 test-assert expressions don't work
;; correctly (pre-existing issue), so we run the fiber operations
;; outside test assertions and check the captured results.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 64))

(test-begin "fiber-native-thunk")

;;; --- spawn with native procedures ---

(define result-list
  (let ((f (spawn list)))
    (yield)
    (fiber-join f)))

(test-assert "spawn + list (zero-arg native)" (null? result-list))

;;; --- spawn still works with closures ---

(define result-lambda
  (let ((f (spawn (lambda () 42))))
    (yield)
    (fiber-join f)))

(test-equal "spawn + lambda" 42 result-lambda)

;;; --- error on non-procedures ---

(test-assert "spawn rejects non-procedure"
  (guard (e (#t #t))
    (spawn 42)
    #f))

(let ((runner (test-runner-current)))
  (test-end "fiber-native-thunk")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
