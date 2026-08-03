;; Regression test for #806: vector-unfold / vector-unfold-right must not
;; abort when the step procedure returns (values) (zero values).

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 133))

(test-begin "vector-unfold-empty-values-806")

(define (raises? thunk)
  (guard (exn (#t #t)) (thunk) #f))

(test-assert "vector-unfold with (values) raises rather than aborting"
             (raises? (lambda () (vector-unfold (lambda (i) (values)) 1))))
(test-assert "vector-unfold-right with (values) raises rather than aborting"
             (raises? (lambda () (vector-unfold-right (lambda (i) (values)) 3))))

(let ((runner (test-runner-current)))
  (test-end "vector-unfold-empty-values-806")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
