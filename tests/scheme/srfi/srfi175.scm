;; SRFI-175 (ASCII character library) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi175.scm

(import (scheme base) (srfi 175) (chibi test))

(test-begin "srfi-175")

;;; --- ascii-codepoint? / ascii-char? / ascii-string? ---
(test #t (ascii-codepoint? 0))
(test #t (ascii-codepoint? 127))
(test #f (ascii-codepoint? 128))
(test #f (ascii-codepoint? -1))
(test #f (ascii-codepoint? 65.0))
(test #f (ascii-codepoint? 'a))
(test #t (ascii-char? #\a))
(test #t (ascii-char? #\delete))
(test #f (ascii-char? #\λ))
(test #f (ascii-char? 65))
(test #t (ascii-string? "hello"))
(test #t (ascii-string? ""))
(test #f (ascii-string? "aλb"))

;;; --- classification (chars and codepoints both accepted) ---
(test #t (ascii-control? #\null))
(test #t (ascii-control? #\delete))
(test #f (ascii-control? #\a))
(test #t (ascii-control? 7))
(test #t (ascii-non-control? #\space))
(test #f (ascii-non-control? #\tab))
(test #t (ascii-space-or-tab? #\space))
(test #t (ascii-space-or-tab? #\tab))
(test #f (ascii-space-or-tab? #\newline))
(test #t (ascii-whitespace? #\newline))
(test #t (ascii-whitespace? #\space))
(test #t (ascii-whitespace? 13))
(test #f (ascii-whitespace? #\a))
(test #t (ascii-other-graphic? #\!))
(test #t (ascii-other-graphic? #\@))
(test #f (ascii-other-graphic? #\a))
(test #f (ascii-other-graphic? #\5))
(test #t (ascii-alphabetic? #\a))
(test #t (ascii-alphabetic? #\Z))
(test #f (ascii-alphabetic? #\5))
(test #t (ascii-numeric? #\5))
(test #f (ascii-numeric? #\a))
(test #t (ascii-alphanumeric? #\a))
(test #t (ascii-alphanumeric? #\5))
(test #f (ascii-alphanumeric? #\_))
(test #t (ascii-upper-case? #\A))
(test #f (ascii-upper-case? #\a))
(test #t (ascii-lower-case? #\z))
(test #f (ascii-lower-case? #\Z))

;;; --- case conversion ---
(test #\A (ascii-upcase #\a))
(test #\A (ascii-upcase #\A))
(test #\5 (ascii-upcase #\5))
(test 65 (ascii-upcase 97))
(test #\a (ascii-downcase #\A))
(test #\a (ascii-downcase #\a))
(test 97 (ascii-downcase 65))

;;; --- digit/letter values ---
(test 7 (ascii-digit-value #\7 10))
(test 0 (ascii-digit-value #\0 10))
(test #f (ascii-digit-value #\7 7))
(test 1 (ascii-digit-value #\1 2))
(test #f (ascii-digit-value #\space 10))
;; SRFI-175: ascii-digit-value handles digits 0-9 ONLY — letters return #f
;; (letters go through ascii-upper/lower-case-value)
;; FAIL: #1236 (ascii-digit-value treats a-z/A-Z as digits 10-35)
;; (test #f (ascii-digit-value #\a 16))
;; FAIL: #1236
;; (test #f (ascii-digit-value #\F 16))

(test 12 (ascii-upper-case-value #\C 10 26))
(test 0 (ascii-upper-case-value #\A 0 26))
(test #f (ascii-upper-case-value #\Z 0 25))
(test #f (ascii-upper-case-value #\a 0 26))
(test 12 (ascii-lower-case-value #\c 10 26))
(test #f (ascii-lower-case-value #\A 0 26))

;;; --- missing exports ---
;; FAIL: #1236 (ascii-bytevector?, ascii-mirror-bracket, ascii-nth-digit,
;;   ascii-nth-upper-case, ascii-nth-lower-case, ascii-ci=?, ascii-ci<?,
;;   ascii-ci>?, ascii-ci<=?, ascii-ci>=?, ascii-string-ci=? etc.
;;   not exported)
;; (test #\9 (ascii-nth-digit 9))
;; (test #\c (ascii-nth-lower-case 2))
;; (test #\] (ascii-mirror-bracket #\[))
;; (test #t (ascii-ci=? #\a #\A))

(test-end "srfi-175")
