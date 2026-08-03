;; Regression test for #55: string-replace start > end must error

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "string-replace-range")

;; start > end must error, not silently corrupt
(test-assert "string-replace start > end raises"
             (guard (exn (#t #t))
               (string-replace "abcdef" "XY" 4 2)
               #f))

;; Normal replacements still work
(test-equal "string-replace normal"
  "abXYef"
  (string-replace "abcdef" "XY" 2 4))

(test-equal "string-replace at start"
  "XYcdef"
  (string-replace "abcdef" "XY" 0 2))

(test-equal "string-replace equal start/end (insert)"
  "abXYcdef"
  (string-replace "abcdef" "XY" 2 2))

(let ((runner (test-runner-current)))
  (test-end "string-replace-range")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
