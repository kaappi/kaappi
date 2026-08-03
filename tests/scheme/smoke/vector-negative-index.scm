;; Regression test for #50: negative index args must error, not panic

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "vector-negative-index")

(define (raises? thunk)
  (guard (exn (#t #t)) (thunk) #f))

(define-syntax test-raises
  (syntax-rules ()
    ((_ name expr) (test-assert name (raises? (lambda () expr))))))

(test-raises "vector-reverse! negative start"
             (vector-reverse! (vector 1 2 3) -1))
(test-raises "vector-reverse! negative end"
             (vector-reverse! (vector 1 2 3) 0 -1))
(test-raises "vector-reverse-copy negative start"
             (vector-reverse-copy (vector 1 2 3) -1))
(test-raises "vector-reverse-copy negative end"
             (vector-reverse-copy (vector 1 2 3) 0 -1))
(test-raises "vector-unfold negative length"
             (vector-unfold (lambda (i) i) -5))

(let ((runner (test-runner-current)))
  (test-end "vector-negative-index")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
