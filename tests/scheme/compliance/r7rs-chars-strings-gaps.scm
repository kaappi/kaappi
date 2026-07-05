;; R7RS sections 6.6-6.9 conformance gap tests — audit Phase 1C.
;; Covers spec requirements not exercised by tests/scheme/r7rs/r7rs-tests.scm
;; sections 6.6 (characters), 6.7 (strings), 6.8 (vectors), 6.9 (bytevectors).
;; Spec references cite docs/errata-corrected-r7rs.pdf.

(import (scheme base) (scheme char) (scheme write) (scheme process-context)
        (srfi 64))

(test-begin "r7rs-chars-strings-gaps")

;; --- 6.6 digit-value (p. 45) ---
;; Returns the numeric value for any Numeric_Type=Decimal digit, not just
;; ASCII; #f otherwise. Spec examples verbatim:
(test-equal "digit-value ASCII" 3 (digit-value #\3))
(test-equal "digit-value Arabic-Indic four" 4 (digit-value #\x0664))
(test-equal "digit-value Gujarati zero" 0 (digit-value #\x0AE6))
(test-equal "digit-value non-digit" #f (digit-value #\x0EA6))

;; --- 6.6 char classification vs Unicode properties (p. 45) ---
;; "they must return #t when applied to characters with the Unicode
;; properties Alphabetic, ..., Uppercase, and Lowercase respectively, and
;; #f when applied to any other Unicode characters."
(test-equal "Lu is upper not lower" '(#t #t #f)
  (let ((c #\x01C4)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
(test-equal "Ll is lower not upper" '(#t #f #t)
  (let ((c #\x01C6)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
(test-equal "uncased letter (Hebrew alef) is alphabetic only" '(#t #f #f)
  (let ((c #\x05D0)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
(test-equal "Other_Uppercase (Roman numeral) is uppercase" '(#t #t #f)
  (let ((c #\x2160)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
;; FAIL: #1145 (classification derives from case mappings, not properties)
;; (test-equal "titlecase Dz-caron is neither upper nor lower" '(#t #f #f)
;;   (let ((c #\x01C5)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
;; FAIL: #1145
;; (test-equal "titlecase alpha-prosgegrammeni is not upper" #f
;;   (char-upper-case? #\x1FBC))
;; FAIL: #1145
;; (test-equal "sharp-s is lowercase despite no simple upcase mapping" #t
;;   (char-lower-case? #\x00DF))
;; FAIL: #1145
;; (test-equal "feminine ordinal is alphabetic and lowercase" '(#t #f #t)
;;   (let ((c #\x00AA)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))

;; --- 6.6 case conversion (p. 45) ---
;; Titlecase characters still have simple up/down mappings:
(test-equal "char-upcase of titlecase" #\x01C4 (char-upcase #\x01C5))
(test-equal "char-downcase of titlecase" #\x01C6 (char-downcase #\x01C5))
;; "If the argument is not the lowercase member of such a pair, it is
;; returned" — sharp-s has no single-char uppercase:
(test-equal "char-upcase of sharp-s returns argument" #\x00DF (char-upcase #\x00DF))
(test-equal "char-foldcase" #\a (char-foldcase #\A))
(test-equal "char-downcase of digit returns argument" #\3 (char-downcase #\3))

;; --- 6.7 string literals (p. 45-46) ---
;; Escape sequences:
(test-equal "escape alarm" 7 (char->integer (string-ref "\a" 0)))
(test-equal "escape backspace" 8 (char->integer (string-ref "\b" 0)))
(test-equal "escape tab" 9 (char->integer (string-ref "\t" 0)))
(test-equal "escape newline" 10 (char->integer (string-ref "\n" 0)))
(test-equal "escape return" 13 (char->integer (string-ref "\r" 0)))
(test-equal "escape quote" 34 (char->integer (string-ref "\"" 0)))
(test-equal "escape backslash" 92 (char->integer (string-ref "\\" 0)))
(test-equal "escape vertical line" 124 (char->integer (string-ref "\|" 0)))
(test-equal "hex escape with semicolon" #\x03B1 (string-ref "\x03B1;" 0))
;; "A line ending which is preceded by \<intraline whitespace> expands to
;; nothing (along with any trailing intraline whitespace)" (p. 46)
(test-equal "line continuation collapses"
  "Heres text containing just one line"
  "Heres text \
    containing just one line")

;; --- 6.7 full Unicode casing (p. 47) ---
;; "These procedures apply the Unicode full string uppercasing, lowercasing,
;; and case-folding algorithms ... the result differs in length from the
;; argument" — sharp-s uppercases to SS.
(test-equal "string-upcase changes length" "STRASSE" (string-upcase "Stra\xDF;e"))
(test-equal "string-foldcase folds sharp-s" "strasse" (string-foldcase "STRA\xDF;E"))
;; "-ci procedures behave as if they applied string-foldcase to their
;; arguments before invoking the corresponding procedures without -ci"
(test-equal "string-ci=? via foldcase" #t (string-ci=? "Stra\xDF;e" "STRASSE"))

;; --- 6.7 string-copy! (p. 47) ---
;; Spec example:
(let ((a "12345") (b (string-copy "abcde")))
  (string-copy! b 1 a 0 2)
  (test-equal "string-copy! spec example" "a12de" b))
;; "if the source and destination overlap, copying takes place as if the
;; source is first copied into a temporary string"
(let ((b (string-copy "abcde")))
  (string-copy! b 1 b 0 3)
  (test-equal "string-copy! forward self-overlap" "aabce" b))

;; --- 6.7 string-fill! with range (p. 48) ---
(let ((s (string-copy "abcde")))
  (string-fill! s #\x 2 4)
  (test-equal "string-fill! with start/end" "abxxe" s))

;; --- 6.8 vectors (p. 48-49) ---
(test-equal "vector->list with start/end" '(dah)
  (vector->list #(dah dah didah) 1 2))
(test-equal "vector->string range" "bc"
  (vector->string (vector #\a #\b #\c #\d) 1 3))
(test-equal "string->vector with start" #(#\B #\C) (string->vector "ABC" 1))
;; vector-copy! spec example and overlap guarantee (p. 49)
(let ((a (vector 1 2 3 4 5)) (b (vector 10 20 30 40 50)))
  (vector-copy! b 1 a 0 2)
  (test-equal "vector-copy! spec example" #(10 1 2 40 50) b))
(let ((v (vector 1 2 3 4 5)))
  (vector-copy! v 1 v 0 3)
  (test-equal "vector-copy! forward self-overlap" #(1 1 2 3 5) v))
;; vector-fill! with range (p. 49), spec example:
(let ((a (vector 1 2 3 4 5)))
  (vector-fill! a 'smash 2 4)
  (test-equal "vector-fill! with start/end" #(1 2 smash smash 5) a))
(test-equal "vector-append" #(a b c d e f)
  (vector-append #(a b c) #(d e f)))

;; --- 6.9 bytevectors (p. 49-50) ---
(let ((bv (bytevector 1 2 3 4 5)))
  (bytevector-copy! bv 1 bv 0 3)
  (test-equal "bytevector-copy! forward self-overlap" #u8(1 1 2 3 5) bv))
(test-equal "bytevector-append" #u8(0 1 2 3 4 5)
  (bytevector-append #u8(0 1 2) #u8(3 4 5)))
(test-equal "bytevector-copy with range" #u8(3 4)
  (bytevector-copy #u8(1 2 3 4 5) 2 4))
;; UTF-8 conversions: string->utf8 start/end index by CODEPOINT, while
;; utf8->string start/end index by BYTE (p. 50).
(test-equal "string->utf8 with codepoint start" #u8(#xCE #xBC)
  (string->utf8 "\x3BB;\x3BC;" 1))
(test-equal "utf8->string with byte start" "\x3BC;"
  (utf8->string (bytevector #xCE #xBB #xCE #xBC) 2))
(test-equal "string->utf8 spec example" #u8(#xCE #xBB) (string->utf8 "\x3BB;"))
(test-equal "utf8->string spec example" "A" (utf8->string #u8(#x41)))

(let ((runner (test-runner-current)))
  (test-end "r7rs-chars-strings-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
