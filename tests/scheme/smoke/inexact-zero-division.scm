;; Regression test for #511: (/ x 0.0) must yield +inf.0/+nan.0, not error.
;; R7RS §6.2.6: inexact zero division follows IEEE 754.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "inexact-zero-division")

(test-equal "(/ 1.0 0.0) = +inf.0" +inf.0 (/ 1.0 0.0))
(test-equal "(/ -1.0 0.0) = -inf.0" -inf.0 (/ -1.0 0.0))
(test-assert "(/ 0.0 0.0) = +nan.0" (nan? (/ 0.0 0.0)))
(test-equal "(/ 0.0) = +inf.0" +inf.0 (/ 0.0))
(test-equal "(/ 5 0.0) = +inf.0" +inf.0 (/ 5 0.0))
(test-equal "(/ -5 0.0) = -inf.0" -inf.0 (/ -5 0.0))

;; Exact zero must still raise an error
(test-assert "(/ 5 0) raises error"
  (guard (exn (#t #t))
    (/ 5 0)
    #f))

(let ((runner (test-runner-current)))
  (test-end "inexact-zero-division")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
