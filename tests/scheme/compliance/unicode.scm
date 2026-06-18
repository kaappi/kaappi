;;; R7RS Unicode compliance tests (SRFI 64)

(import (scheme base) (scheme char) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "unicode")

;; ---- string-length: count codepoints, not bytes ----
(test-group "string-length"
  (test-eqv "string-length ascii" 5 (string-length "hello"))
  (test-eqv "string-length empty" 0 (string-length ""))
  (test-eqv "string-length with e-acute" 5 (string-length "h\x00E9;llo"))
  (test-eqv "string-length with lambda" 10 (string-length "\x03BB;-calculus")))

;; ---- string-ref: codepoint indexing ----
(test-group "string-ref"
  (test-eqv "string-ref ascii first" #\h (string-ref "hello" 0))
  (test-eqv "string-ref e-acute codepoint" 233
    (char->integer (string-ref "h\x00E9;llo" 1)))
  (test-eqv "string-ref lambda codepoint" 955
    (char->integer (string-ref "\x03BB;-calculus" 0))))

;; ---- substring: codepoint indices ----
(test-group "substring"
  (test-eqv "substring with e-acute length" 2
    (string-length (substring "h\x00E9;llo" 0 2)))
  (test-equal "substring ascii portion" "llo"
    (substring "h\x00E9;llo" 2 5)))

;; ---- string->list: iterate codepoints ----
(test-group "string->list"
  (test-eqv "string->list ascii length" 3
    (length (string->list "abc")))
  (test-eqv "string->list unicode length" 5
    (length (string->list "h\x00E9;llo")))
  (test-eqv "string->list lambda first char" 955
    (char->integer (car (string->list "\x03BB;x")))))

;; ---- string-copy: codepoint indices ----
(test-group "string-copy"
  (test-eqv "string-copy unicode range length" 2
    (string-length (string-copy "h\x00E9;llo" 1 3))))

;; ---- make-string: non-ASCII fill ----
(test-group "make-string"
  (test-eqv "make-string length" 3
    (string-length (make-string 3 #\a)))
  (test-equal "make-string with fill" "aaa"
    (make-string 3 #\a)))

;; ---- char-alphabetic? with Unicode ----
(test-group "char-alphabetic?"
  (test-assert "char-alphabetic? lowercase" (char-alphabetic? #\a))
  (test-assert "char-alphabetic? uppercase" (char-alphabetic? #\Z))
  (test-eqv "char-alphabetic? digit" #f (char-alphabetic? #\1))
  (test-assert "char-alphabetic? lambda" (char-alphabetic? (integer->char 955)))
  (test-assert "char-alphabetic? e-acute" (char-alphabetic? (integer->char 233))))

;; ---- char-numeric? ----
(test-group "char-numeric?"
  (test-assert "char-numeric? digit" (char-numeric? #\5))
  (test-eqv "char-numeric? letter" #f (char-numeric? #\a)))

;; ---- char-whitespace? ----
(test-group "char-whitespace?"
  (test-assert "char-whitespace? space" (char-whitespace? #\space))
  (test-assert "char-whitespace? tab" (char-whitespace? #\tab))
  (test-eqv "char-whitespace? letter" #f (char-whitespace? #\a)))

;; ---- char-upper-case? / char-lower-case? ----
(test-group "char-upper-case? / char-lower-case?"
  (test-assert "char-upper-case? A" (char-upper-case? #\A))
  (test-eqv "char-upper-case? a" #f (char-upper-case? #\a))
  (test-assert "char-lower-case? a" (char-lower-case? #\a))
  (test-eqv "char-lower-case? A" #f (char-lower-case? #\A))
  (test-assert "char-upper-case? E-acute" (char-upper-case? (integer->char 201)))
  (test-assert "char-lower-case? e-acute" (char-lower-case? (integer->char 233))))

;; ---- char-upcase / char-downcase ----
(test-group "char-upcase / char-downcase"
  (test-eqv "char-upcase a" 65 (char->integer (char-upcase #\a)))
  (test-eqv "char-downcase A" 97 (char->integer (char-downcase #\A)))
  (test-eqv "char-upcase e-acute" 201
    (char->integer (char-upcase (integer->char 233))))
  (test-eqv "char-downcase E-acute" 233
    (char->integer (char-downcase (integer->char 201)))))

;; ---- string-upcase / string-downcase ----
(test-group "string-upcase / string-downcase"
  (test-equal "string-upcase ascii" "HELLO" (string-upcase "hello"))
  (test-equal "string-downcase ascii" "hello" (string-downcase "HELLO"))
  (test-eqv "string-upcase unicode length" 5
    (string-length (string-upcase "h\x00E9;llo")))
  (test-eqv "string-upcase unicode char 1 codepoint" 201
    (char->integer (string-ref (string-upcase "h\x00E9;llo") 1))))

;; ---- string-set! ----
(test-group "string-set!"
  (test-equal "string-set! first char"
    "Hello"
    (let ((s (string-copy "hello")))
      (string-set! s 0 #\H)
      s)))

;; ---- string-fill! ----
(test-group "string-fill!"
  (test-equal "string-fill! all"
    "zzz"
    (let ((sf (make-string 3 #\a)))
      (string-fill! sf #\z)
      sf)))

;; ---- string-for-each ----
(test-group "string-for-each"
  (test-eqv "string-for-each counts codepoints" 5
    (let ((count 0))
      (string-for-each (lambda (c) (set! count (+ count 1))) "h\x00E9;llo")
      count)))

;; ---- string->vector ----
(test-group "string->vector"
  (test-eqv "string->vector unicode length" 5
    (vector-length (string->vector "h\x00E9;llo"))))

;; ---- string comparisons ----
(test-group "string comparisons"
  (test-assert "string=? equal" (string=? "abc" "abc"))
  (test-assert "string<? less" (string<? "abc" "abd")))

;; ---- char CI comparisons ----
(test-group "char CI comparisons"
  (test-assert "char-ci=? case insensitive" (char-ci=? #\A #\a))
  (test-assert "char-ci<? case insensitive" (char-ci<? #\a #\B)))

;; ---- string CI comparisons ----
(test-group "string CI comparisons"
  (test-assert "string-ci=? case insensitive" (string-ci=? "Hello" "hello")))

;; ---- digit-value ----
(test-group "digit-value"
  (test-eqv "digit-value 0" 0 (digit-value #\0))
  (test-eqv "digit-value 9" 9 (digit-value #\9))
  (test-eqv "digit-value non-digit" #f (digit-value #\a)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "unicode")
(if (> %test-fail-count 0) (exit 1))
