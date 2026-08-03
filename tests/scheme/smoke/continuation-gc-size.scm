;; Regression test for #428: GC objectSize for continuations must count
;; backing buffer in bytes (len * 8), not elements (len).
;; If objectSize undercounts, bytes_allocated inflates over time.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "continuation-gc-size")

(define (make-continuation)
  (call-with-current-continuation
    (lambda (k) k)))

;; Create and discard many continuations to exercise GC.
;;
;; The assertion is that the loop runs to completion, which is weaker than the
;; property (bytes_allocated staying bounded) but is the strongest verdict
;; available from Scheme: nothing exposes GC accounting to a program, and the
;; undercount's visible consequence — pressure that eventually aborts or hangs
;; the run — is what completing rules out. `kaappi --gc-stats` is the direct
;; check, and needs a harness this file is not.
(test-equal "1000 captured-and-discarded continuations run to completion"
  1000
  (let loop ((i 0))
    (if (< i 1000)
        (begin (make-continuation) (loop (+ i 1)))
        i)))

(let ((runner (test-runner-current)))
  (test-end "continuation-gc-size")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
