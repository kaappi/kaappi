;; SRFI-129 (Titlecase procedures) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi129.scm

(import (scheme base) (scheme char) (scheme process-context) (srfi 129) (srfi 64))

(test-begin "srfi-129")

;;; --- char-title-case? ---
(test-assert "char-title-case?: Dz digraph"
  (char-title-case? (integer->char #x01C5)))
(test-assert "char-title-case?: Lj digraph"
  (char-title-case? (integer->char #x01C8)))
(test-assert "char-title-case?: not uppercase A"
  (not (char-title-case? #\A)))
(test-assert "char-title-case?: not lowercase a"
  (not (char-title-case? #\a)))
(test-assert "char-title-case?: not digit"
  (not (char-title-case? #\0)))

;;; --- char-titlecase ---
(test-equal "char-titlecase: lowercase a"
  #\A (char-titlecase #\a))
(test-equal "char-titlecase: uppercase A stays"
  #\A (char-titlecase #\A))
(test-equal "char-titlecase: digit stays"
  #\5 (char-titlecase #\5))
(test-equal "char-titlecase: DZ -> Dz"
  (integer->char #x01C5) (char-titlecase (integer->char #x01C4)))
(test-equal "char-titlecase: dz -> Dz"
  (integer->char #x01C5) (char-titlecase (integer->char #x01C6)))
(test-equal "char-titlecase: Dz -> Dz"
  (integer->char #x01C5) (char-titlecase (integer->char #x01C5)))

;;; --- string-titlecase ---
(test-equal "string-titlecase: simple"
  "Hello World" (string-titlecase "hello world"))
(test-equal "string-titlecase: mixed case"
  "Hello World" (string-titlecase "HELLO WORLD"))
(test-equal "string-titlecase: already titlecase"
  "Hello" (string-titlecase "Hello"))
(test-equal "string-titlecase: empty string"
  "" (string-titlecase ""))
(test-equal "string-titlecase: single char"
  "A" (string-titlecase "a"))
(test-equal "string-titlecase: with punctuation"
  "It'S A Test" (string-titlecase "it's a test"))
(test-equal "string-titlecase: numbers are caseless"
  "123Abc" (string-titlecase "123abc"))

(let ((runner (test-runner-current)))
  (test-end "srfi-129")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
