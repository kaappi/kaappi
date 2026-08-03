;; Regression test for #54: negative index args must error, not panic

(import (scheme base) (scheme char) (scheme write)
        (scheme process-context) (srfi 13) (srfi 64))

(test-begin "string-negative-index")

(define (raises? thunk)
  (guard (exn (#t #t)) (thunk) #f))

(define-syntax test-raises
  (syntax-rules ()
    ((_ name expr) (test-assert name (raises? (lambda () expr))))))

(test-raises "string-take negative" (string-take "hello" -1))
(test-raises "string-drop negative" (string-drop "hello" -1))
(test-raises "string-take-right negative" (string-take-right "hello" -1))
(test-raises "string-drop-right negative" (string-drop-right "hello" -1))
(test-raises "string-pad negative" (string-pad "hello" -1))
(test-raises "string-pad-right negative" (string-pad-right "hello" -1))
(test-raises "string-replace negative start" (string-replace "abcdef" "XY" -1 2))
(test-raises "string-replace negative end" (string-replace "abcdef" "XY" 0 -1))
(test-raises "string-tabulate negative" (string-tabulate char-upcase -1))
(test-raises "string-index negative start (parseStartEnd)"
             (string-index "hello" char-alphabetic? -1))
(test-raises "string-contains negative start (parseStartEnd)"
             (string-contains "hello" "l" -1))

(let ((runner (test-runner-current)))
  (test-end "string-negative-index")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
