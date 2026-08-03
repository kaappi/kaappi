;; Regression test for #442:
;; (zero? #t) and (zero? #f) must raise type errors, not fold to #f.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "zero-pred-type-error")

(define (raises? thunk)
  (guard (exn (#t #t)) (thunk) #f))

(test-assert "(zero? #t) raises" (raises? (lambda () (zero? #t))))
(test-assert "(zero? #f) raises" (raises? (lambda () (zero? #f))))
(test-assert "(zero? \"hello\") raises" (raises? (lambda () (zero? "hello"))))

;; Sanity checks
(test-equal "(zero? 0) is #t" #t (zero? 0))
(test-equal "(zero? 1) is #f" #f (zero? 1))

(let ((runner (test-runner-current)))
  (test-end "zero-pred-type-error")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
