;;; R7RS Char compliance tests (SRFI 64)

(import (scheme base) (scheme char) (scheme process-context) (srfi 64))

(test-begin "chars")

(test-group "character classification"
  ;; char-alphabetic?
  (test-assert "char-alphabetic? #\\a" (char-alphabetic? #\a))
  (test-assert "char-alphabetic? #\\Z" (char-alphabetic? #\Z))
  (test-eqv "char-alphabetic? #\\1" #f (char-alphabetic? #\1))
  (test-eqv "char-alphabetic? #\\space" #f (char-alphabetic? #\space))

  ;; char-numeric?
  (test-assert "char-numeric? #\\0" (char-numeric? #\0))
  (test-assert "char-numeric? #\\9" (char-numeric? #\9))
  (test-eqv "char-numeric? #\\a" #f (char-numeric? #\a))

  ;; char-whitespace?
  (test-assert "char-whitespace? #\\space" (char-whitespace? #\space))
  (test-assert "char-whitespace? #\\newline" (char-whitespace? #\newline))
  (test-eqv "char-whitespace? #\\a" #f (char-whitespace? #\a))

  ;; char-upper-case?
  (test-assert "char-upper-case? #\\A" (char-upper-case? #\A))
  (test-eqv "char-upper-case? #\\a" #f (char-upper-case? #\a))

  ;; char-lower-case?
  (test-assert "char-lower-case? #\\a" (char-lower-case? #\a))
  (test-eqv "char-lower-case? #\\A" #f (char-lower-case? #\A)))

(test-group "case operations"
  (test-eqv "char-upcase #\\a" #\A (char-upcase #\a))
  (test-eqv "char-upcase #\\A" #\A (char-upcase #\A))
  (test-eqv "char-downcase #\\A" #\a (char-downcase #\A))
  (test-eqv "char-downcase #\\a" #\a (char-downcase #\a))
  (test-eqv "char-foldcase #\\A" #\a (char-foldcase #\A)))

(test-group "digit-value"
  (test-eqv "digit-value #\\0" 0 (digit-value #\0))
  (test-eqv "digit-value #\\5" 5 (digit-value #\5))
  (test-eqv "digit-value #\\9" 9 (digit-value #\9))
  (test-eqv "digit-value #\\a" #f (digit-value #\a)))

(test-group "case-insensitive char comparison"
  (test-assert "char-ci=? #\\A #\\a" (char-ci=? #\A #\a))
  (test-assert "char-ci<? #\\A #\\b" (char-ci<? #\A #\b))
  (test-assert "char-ci>? #\\z #\\A" (char-ci>? #\z #\A)))

(test-group "string case operations"
  (test-equal "string-upcase hello" "HELLO" (string-upcase "hello"))
  (test-equal "string-downcase HELLO" "hello" (string-downcase "HELLO"))
  (test-equal "string-foldcase HeLLo" "hello" (string-foldcase "HeLLo")))

(test-group "case-insensitive string comparison"
  (test-assert "string-ci=? Hello hello" (string-ci=? "Hello" "hello"))
  (test-assert "string-ci<? abc ABD" (string-ci<? "abc" "ABD"))
  (test-assert "string-ci>? abd ABC" (string-ci>? "abd" "ABC")))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "chars")
(if (> %test-fail-count 0) (exit 1))
