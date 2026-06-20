;; SRFI-13 + SRFI-14 char-set integration tests
(import (scheme base) (scheme write) (srfi 13) (srfi 14))

(define pass 0)
(define fail 0)
(define (check name expected actual)
  (if (equal? expected actual)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display name)
      (display " expected=") (write expected)
      (display " got=") (write actual)
      (newline))))

;; string-index with char-set
(check "string-index char-set:digit"
  0 (string-index "123abc" char-set:digit))
(check "string-index char-set:letter"
  3 (string-index "123abc" char-set:letter))
(check "string-index char-set:upper-case"
  #f (string-index "hello" char-set:upper-case))
(check "string-index char-set:upper-case found"
  5 (string-index "helloWorld" char-set:upper-case))

;; string-count with char-set
(check "string-count char-set:digit"
  3 (string-count "a1b2c3" char-set:digit))
(check "string-count char-set:letter"
  3 (string-count "a1b2c3" char-set:letter))
(check "string-count char-set:whitespace"
  3 (string-count "hello world ! " char-set:whitespace))

;; string-filter with char-set
(check "string-filter char-set:digit"
  "123" (string-filter char-set:digit "a1b2c3"))
(check "string-filter char-set:letter"
  "abc" (string-filter char-set:letter "a1b2c3"))

;; string-delete with char-set
(check "string-delete char-set:digit"
  "abc" (string-delete char-set:digit "a1b2c3"))
(check "string-delete char-set:whitespace"
  "hello" (string-delete char-set:whitespace "h e l l o"))

;; string-trim with char-set
(check "string-trim char-set:whitespace"
  "hello  " (string-trim "  hello  " char-set:whitespace))

;; string-trim-right with char-set
(check "string-trim-right char-set:whitespace"
  "  hello" (string-trim-right "  hello  " char-set:whitespace))

;; string-trim-both with char-set
(check "string-trim-both char-set:whitespace"
  "hello" (string-trim-both "  hello  " char-set:whitespace))

;; string-every with char-set
(check "string-every char-set:digit true"
  #t (string-every char-set:digit "12345"))
(check "string-every char-set:digit false"
  #f (string-every char-set:digit "123a5"))
(check "string-every char-set:letter"
  #t (string-every char-set:letter "hello"))

;; string-any with char-set
(check "string-any char-set:digit true"
  #t (string-any char-set:digit "abc1def"))
(check "string-any char-set:digit false"
  #f (string-any char-set:digit "abcdef"))

;; string-index-right with char-set
(check "string-index-right char-set:digit"
  4 (string-index-right "abc12d" char-set:digit))

;; string-skip with char-set
(check "string-skip char-set:digit"
  3 (string-skip "123abc" char-set:digit))
(check "string-skip char-set:letter"
  #f (string-skip "hello" char-set:letter))

;; string-skip-right with char-set
(check "string-skip-right char-set:digit"
  2 (string-skip-right "abc123" char-set:digit))

(display pass) (display " pass, ")
(display fail) (display " fail")
(newline)
(if (> fail 0) (exit 1))
