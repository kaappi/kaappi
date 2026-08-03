;; Regression test for #441:
;; even? and odd? must reject non-integer flonums.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "even-odd-non-integer")

(define (raises? thunk)
  (guard (exn (#t #t)) (thunk) #f))

;; Non-integer flonum should error
(test-assert "(odd? 2.5) raises" (raises? (lambda () (odd? 2.5))))
(test-assert "(even? 2.5) raises" (raises? (lambda () (even? 2.5))))

;; Infinity should error
(test-assert "(odd? +inf.0) raises" (raises? (lambda () (odd? +inf.0))))

;; NaN should error
(test-assert "(even? +nan.0) raises" (raises? (lambda () (even? +nan.0))))

;; Integer-valued flonums should work
(test-assert "(even? 4.0) is #t" (even? 4.0))
(test-assert "(odd? 3.0) is #t" (odd? 3.0))

(let ((runner (test-runner-current)))
  (test-end "even-odd-non-integer")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
