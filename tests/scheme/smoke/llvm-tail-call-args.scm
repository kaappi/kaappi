;; Regression test for issue #639: tail call with args passing pointer
;; to caller's stack alloca, corrupting arguments in native backend.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "llvm-tail-call-args")

(define (add3 a b c) (+ a b c))
(test-equal "3-argument call" 60 (add3 10 20 30))

(define (sum5 a b c d e) (+ a b c d e))
(test-equal "5-argument call" 15 (sum5 1 2 3 4 5))

(define (forward a b c) (add3 a b c))
(test-equal "tail call forwarding all three arguments" 600 (forward 100 200 300))

(let ((runner (test-runner-current)))
  (test-end "llvm-tail-call-args")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
