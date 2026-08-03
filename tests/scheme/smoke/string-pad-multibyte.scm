;; Regression test for #53: string-pad/pad-right with multi-byte pad chars

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "string-pad-multibyte")

;; Multi-byte pad char (λ = U+03BB, 2 bytes in UTF-8)
(test-equal "string-pad with lambda char"
  "λλλ42"
  (string-pad "42" 5 #\λ))

(test-equal "string-pad-right with lambda char"
  "42λλλ"
  (string-pad-right "42" 5 #\λ))

;; Codepoint 128-255 (é = U+00E9, 2 bytes in UTF-8)
(test-equal "string-pad with é"
  "ééé42"
  (string-pad "42" 5 #\é))

(test-equal "string-pad-right with é length"
  5
  (string-length (string-pad-right "42" 5 #\é)))

;; ASCII pad char still works
(test-equal "string-pad with ASCII"
  "***42"
  (string-pad "42" 5 #\*))

(test-equal "string-pad-right with ASCII"
  "42***"
  (string-pad-right "42" 5 #\*))

;; No padding needed (string already long enough)
(test-equal "string-pad no padding needed"
  "hello"
  (string-pad "hello" 5))

(test-equal "string-pad truncation"
  "ello"
  (string-pad "hello" 4))

(let ((runner (test-runner-current)))
  (test-end "string-pad-multibyte")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
