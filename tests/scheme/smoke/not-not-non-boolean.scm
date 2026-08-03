;; Regression test for #440:
;; (not (not X)) must return a boolean, not X itself.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "not-not-non-boolean")

(test-equal "(not (not \"hello\")) is #t" #t (not (not "hello")))
(test-equal "(not (not (+ 1 2))) is #t" #t (not (not (+ 1 2))))
(test-equal "(not (not #f)) is #f" #f (not (not #f)))
(test-equal "(not (not '())) is #t" #t (not (not '())))

(let ((runner (test-runner-current)))
  (test-end "not-not-non-boolean")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
