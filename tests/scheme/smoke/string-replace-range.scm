;; Regression test for #55: string-replace start > end must error

(import (scheme base) (scheme write))

(define (test name expected actual)
  (if (equal? expected actual)
    (begin (display "PASS: ") (display name) (newline))
    (begin (display "FAIL: ") (display name)
           (display " expected=") (write expected)
           (display " actual=") (write actual) (newline))))

(define (expect-error thunk name)
  (guard (exn (#t (begin (display "PASS: ") (display name) (newline))))
    (thunk)
    (display "FAIL: ") (display name) (display " did not error") (newline)))

;; start > end must error, not silently corrupt
(expect-error (lambda () (string-replace "abcdef" "XY" 4 2))
              "string-replace start > end")

;; Normal replacements still work
(test "string-replace normal"
  "abXYef"
  (string-replace "abcdef" "XY" 2 4))

(test "string-replace at start"
  "XYcdef"
  (string-replace "abcdef" "XY" 0 2))

(test "string-replace equal start/end (insert)"
  "abXYcdef"
  (string-replace "abcdef" "XY" 2 2))
