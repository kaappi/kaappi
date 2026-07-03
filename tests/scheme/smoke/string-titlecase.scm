(import (scheme base) (scheme process-context) (srfi 13) (srfi 64))

(define %test-fail-count 0)
(test-begin "string-titlecase")

;; Basic whitespace word boundaries
(test-equal "basic whitespace" "Hello World" (string-titlecase "hello world"))
(test-equal "mixed case" "Hello World" (string-titlecase "hELLO wORLD"))

;; Non-whitespace word boundaries (issue #824)
(test-equal "hyphen boundary" "One-Two-Three" (string-titlecase "one-two-three"))
(test-equal "underscore boundary" "One_Two_Three" (string-titlecase "one_two_three"))
(test-equal "digit boundary" "Hello2World" (string-titlecase "hello2world"))

;; SRFI-13 spec example
(test-equal "SRFI-13 example" "--Capitalize This--" (string-titlecase "--capitalize tHIS--"))

;; Unicode case mapping (issue #824)
(test-equal "unicode lowercase start" "\xc9;lan Vital" (string-titlecase "\xe9;lan vital"))

;; Edge cases
(test-equal "empty string" "" (string-titlecase ""))
(test-equal "single char" "A" (string-titlecase "a"))
(test-equal "single uppercase" "A" (string-titlecase "A"))
(test-equal "all caps" "Hello" (string-titlecase "HELLO"))

;; Optional start/end arguments
(test-equal "start/end" "World" (string-titlecase "hello world" 6 11))
(test-equal "start/end middle" "Two" (string-titlecase "one-two-three" 4 7))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "string-titlecase")
(if (> %test-fail-count 0) (exit 1))
