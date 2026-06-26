;; Regression test for #53: string-pad/pad-right with multi-byte pad chars

(import (scheme base) (scheme write))

(define (test name expected actual)
  (if (equal? expected actual)
    (begin (display "PASS: ") (display name) (newline))
    (begin (display "FAIL: ") (display name)
           (display " expected=") (write expected)
           (display " actual=") (write actual) (newline))))

;; Multi-byte pad char (λ = U+03BB, 2 bytes in UTF-8)
(test "string-pad with lambda char"
  "λλλ42"
  (string-pad "42" 5 #\λ))

(test "string-pad-right with lambda char"
  "42λλλ"
  (string-pad-right "42" 5 #\λ))

;; Codepoint 128-255 (é = U+00E9, 2 bytes in UTF-8)
(test "string-pad with é"
  "ééé42"
  (string-pad "42" 5 #\é))

(test "string-pad-right with é length"
  5
  (string-length (string-pad-right "42" 5 #\é)))

;; ASCII pad char still works
(test "string-pad with ASCII"
  "***42"
  (string-pad "42" 5 #\*))

(test "string-pad-right with ASCII"
  "42***"
  (string-pad-right "42" 5 #\*))

;; No padding needed (string already long enough)
(test "string-pad no padding needed"
  "hello"
  (string-pad "hello" 5))

(test "string-pad truncation"
  "ello"
  (string-pad "hello" 4))
