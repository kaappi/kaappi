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

;; Supplementary-plane (and non-ASCII BMP) Nd digits — char-numeric? must
;; consult the full Unicode General_Category=Nd set, not a BMP-only list
;; (kaappi#1925). digit-value must stay in lockstep: R7RS requires it to
;; return a value for every char that char-numeric? reports as #t.
(test-group "char-numeric? supplementary plane"
  ;; ASCII sanity
  (test-assert "char-numeric? #\\7" (char-numeric? #\7))
  ;; BMP fullwidth digit
  (test-assert "char-numeric? U+FF10 FULLWIDTH DIGIT ZERO"
    (char-numeric? (integer->char #xFF10)))
  ;; Supplementary-plane Nd digits
  (test-assert "char-numeric? U+1D7CE MATHEMATICAL BOLD DIGIT ZERO"
    (char-numeric? (integer->char #x1D7CE)))
  (test-assert "char-numeric? U+104A0 OSMANYA DIGIT ZERO"
    (char-numeric? (integer->char #x104A0)))
  ;; Supplementary-plane non-digit letter must NOT be numeric
  (test-eqv "char-numeric? U+1D400 MATHEMATICAL BOLD CAPITAL A" #f
    (char-numeric? (integer->char #x1D400)))
  ;; digit-value agrees with char-numeric? across planes
  (test-eqv "digit-value U+1D7CE" 0 (digit-value (integer->char #x1D7CE)))
  (test-eqv "digit-value U+1D7D7 (bold digit nine)" 9
    (digit-value (integer->char #x1D7D7)))
  (test-eqv "digit-value U+104A5 (osmanya five)" 5
    (digit-value (integer->char #x104A5)))
  (test-eqv "digit-value U+1D400 (non-digit)" #f
    (digit-value (integer->char #x1D400))))

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
