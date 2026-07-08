;; Regression test for #1186: char FFI type accepts Scheme characters and
;; produces Scheme character return values.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "ffi-char-type")

(define lib (ffi-open #f))
(define c-tolower (ffi-fn lib "tolower" '(char) 'char))
(define c-toupper (ffi-fn lib "toupper" '(char) 'char))

;; char param accepts integers (backward compat)
(test-assert "tolower(65) returns char" (char? (c-tolower 65)))
(test-equal "tolower(65) = #\\a" #\a (c-tolower 65))

;; char param accepts Scheme characters
(test-equal "tolower(#\\A) = #\\a" #\a (c-tolower #\A))
(test-equal "toupper(#\\a) = #\\A" #\A (c-toupper #\a))

;; char return produces Scheme characters
(test-assert "return is char?" (char? (c-tolower #\Z)))

;; codepoint > 255 rejected for char param
(test-error "char > 255 rejected" (c-tolower #\λ))

(ffi-close lib)

(let ((runner (test-runner-current)))
  (test-end "ffi-char-type")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
