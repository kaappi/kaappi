;; Regression tests for fiber error handling
;; Issues: #565 (fiber limit error), #564 (error propagation), #551 (native proc rejection)
;;
;; Note: fibers inside SRFI-64 assertion expressions don't work correctly
;; (pre-existing issue, see fiber-native-thunk.scm), so every fiber operation
;; below runs OUTSIDE the assertion and the assertion checks a captured result.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 64))

(test-begin "fiber-error-handling")

;; --- #551, superseded by #1155: spawn ACCEPTS native procedures ---
;;
;; This block used to assert the #551 behaviour — that `(spawn random-real)`
;; raises. kaappi#1155 deliberately reversed that (spawn must accept built-in
;; procedures, not only closures; fiber-native-thunk.scm is its own test), so
;; the check has been wrong ever since. It went unnoticed because it printed
;; `FAIL - should have raised` and exited 0, which is exactly the cannot-fail
;; shape kaappi#2116 is about: widening run-all.sh's stdout net to match a
;; bare FAIL token is what surfaced it.
(define native-spawn-result
  (guard (exn (#t 'raised))
    (let ((f (spawn random-real)))
      (yield)
      (fiber-join f))))

(test-assert "spawn accepts a native procedure (#1155 supersedes #551)"
             (real? native-spawn-result))

;; --- #564: errors in fibers propagate via fiber-join ---
(define propagated
  (let ((f (spawn (lambda () (error "fiber-boom" 42)))))
    (guard (exn (#t exn))
      (fiber-join f)
      'no-error)))

(test-assert "an error raised in a fiber reaches the joiner"
             (error-object? propagated))
(test-equal "the fiber's error message is preserved"
            "fiber-boom" (error-object-message propagated))

;; --- #564: division by zero in fiber propagates ---
(define div-zero
  (let ((f (spawn (lambda () (/ 1 0)))))
    (guard (exn (#t 'raised))
      (fiber-join f)
      'no-error)))

(test-equal "division by zero in a fiber reaches the joiner" 'raised div-zero)

;; --- #565: fiber limit exceeded gives a proper error, not an abort ---
;;
;; Whether 200 fibers exceed the limit is not fixed by anything this test
;; controls, so both outcomes are accepted — what #565 was about is that
;; exceeding it raises a catchable error object rather than aborting.
(define limit-result
  (guard (exn (#t (if (error-object? exn) 'error-object 'non-error-condition)))
    (let loop ((i 0))
      (if (< i 200)
          (begin (spawn (lambda () (yield) (yield) (yield) i))
                 (loop (+ i 1)))
          'no-error))))

(test-assert "spawning 200 fibers either succeeds or raises an error object"
             (memq limit-result '(no-error error-object)))

(let ((runner (test-runner-current)))
  (test-end "fiber-error-handling")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
