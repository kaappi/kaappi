;; Regression tests for reader token validation
;; Issues: #313 (codepoints above U+10FFFF), #312 (char literal delimiters),
;;         #311 (boolean literal delimiters)

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "reader-token-validation")

;; ---- #313: Valid Unicode codepoints should still work ----
(test-assert "#\\x41 is #\\A" (eqv? #\x41 #\A))
(test-assert "#\\x0 is #\\null" (eqv? #\x0 #\null))
(test-equal "#\\xD7FF, just below the surrogates" 55295 (char->integer #\xD7FF))
(test-equal "#\\xE000, just above the surrogates" 57344 (char->integer #\xE000))
(test-equal "#\\x10FFFF, the maximum codepoint" 1114111 (char->integer #\x10FFFF))

;; ---- #311: Boolean literals followed by delimiters should work ----
(test-equal "#t before a delimiter" #t #t)
(test-equal "#f before a delimiter" #f #f)
(test-equal "#true before a delimiter" #t #true)
(test-equal "#false before a delimiter" #f #false)
(test-equal "booleans inside a list" '(#t #f) (list #t #f))
(test-equal "#t as an if condition" "yes" (if #t "yes" "no"))

;; ---- #312: Character literals followed by delimiters should work ----
(test-equal "#\\a before a delimiter" 97 (char->integer #\a))
(test-equal "#\\space before a delimiter" 32 (char->integer #\space))
(test-equal "hex and named char literals inside a list"
            '(65 10)
            (map char->integer (list #\x41 #\newline)))
;; #\x is the character x, not an empty hex escape
(test-equal "#\\x before a delimiter is the letter x" 120 (char->integer #\x))

(let ((runner (test-runner-current)))
  (test-end "reader-token-validation")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
