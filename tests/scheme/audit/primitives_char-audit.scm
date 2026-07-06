;; Audit tests for src/primitives_char.zig — (scheme char) Unicode operations.
;; Audit campaign Phase 2.3 (#1137). Complements compliance/chars.scm,
;; compliance/r7rs-chars-strings-gaps.scm, and the R7RS suite section 6.6.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme char) (scheme write))
(import (chibi test))

(test-begin "primitives_char audit")

;;; --- char-numeric? is Numeric_Type=Decimal only (R7RS 6.6) ---
(test #t (char-numeric? #\5))
(test #t (char-numeric? #\x0664))   ; Arabic-Indic four (Nd)
(test #t (char-numeric? #\xFF13))   ; fullwidth three (Nd)
(test #f (char-numeric? #\x00B2))   ; superscript two: No, not decimal
(test #f (char-numeric? #\x2160))   ; Roman numeral: Nl, not decimal
(test #f (char-numeric? #\a))

;;; --- digit-value agrees with char-numeric? ---
(test 3 (digit-value #\xFF13))
(test #f (digit-value #\x00B2))
(test 0 (digit-value #\x0AE6))

;;; --- classification (see #1145 for the failing property-based cases) ---
(test #t (char-alphabetic? #\x05D0))   ; Hebrew alef, uncased letter
(test #f (char-alphabetic? #\x0664))   ; digits are not alphabetic
(test #t (char-whitespace? #\x00A0))   ; NBSP
(test #t (char-whitespace? #\x2028))   ; LINE SEPARATOR
(test #t (char-whitespace? #\x2029))   ; PARAGRAPH SEPARATOR
(test #t (char-whitespace? #\x0B))     ; vertical tab
(test #f (char-whitespace? #\x200B))   ; ZERO WIDTH SPACE is NOT White_Space

;;; --- case conversion: simple mappings ---
(test #\a (char-downcase #\A))
(test #\A (char-upcase #\a))
(test 105 (char->integer (char-downcase #\x0130))) ; I-with-dot: simple = i
(test #\x00DF (char-upcase #\x00DF))               ; sharp-s: no simple upcase
(test #\x13A0 (char-upcase #\xAB70))               ; Cherokee case pair
(test #\xAB70 (char-downcase #\x13A0))
(test #\3 (char-upcase #\3))                       ; uncased returns argument
(test #\x05D0 (char-downcase #\x05D0))

;;; --- char-foldcase: simple fold ---
(test #\a (char-foldcase #\A))
(test #\x03C3 (char-foldcase #\x03A3))  ; capital sigma -> sigma
(test #\x03C3 (char-foldcase #\x03C2))  ; final sigma -> sigma
(test #\x00DF (char-foldcase #\x00DF))  ; sharp-s folds to itself (simple)

;;; --- char-ci comparisons behave as if char-foldcase applied ---
(test #t (char-ci=? #\A #\a))
(test #t (char-ci=? #\x03A3 #\x03C2))   ; sigma ci= final sigma via fold
(test #t (char-ci=? #\a #\A #\a))
(test #f (char-ci=? #\a #\b))
(test #t (char-ci<? #\a #\B #\c))
(test #t (char-ci<=? #\a #\B #\b))
(test #t (char-ci>? #\c #\B #\a))
(test #t (char-ci>=? #\b #\B #\a))

;;; --- string-ci comparisons via string-foldcase ---
(test #t (string-ci=? "AbC" "aBc" "ABC"))
(test #t (string-ci=? "Stra\xDF;e" "STRASSE"))     ; full fold: eszett = ss
(test #t (string-ci=? "\x03A3;" "\x03C2;"))        ; sigma forms
(test #t (string-ci<? "apple" "BANANA"))
(test #f (string-ci<? "BANANA" "apple"))
(test #t (string-ci<=? "a" "A"))
(test #t (string-ci>=? "B" "a"))
(test #f (string-ci>? "a" "B"))

;;; --- string casing: full (multi-char) mappings ---
(test "STRASSE" (string-upcase "Stra\xDF;e"))      ; length change
(test "FFI" (string-upcase "\xFB03;"))             ; ligature expands
(test "strasse" (string-foldcase "STRA\xDF;E"))
(test 2 (string-length (string-downcase "\x0130;"))) ; I-dot -> i + U+0307
;; Greek final sigma is contextual in string-downcase:
(test "\x03BF;\x03C2;" (string-downcase "\x039F;\x03A3;"))         ; word-final
(test "\x03BF;\x03C3;\x03BF;" (string-downcase "\x039F;\x03A3;\x039F;")) ; medial
(test "" (string-upcase ""))
(test "abc" (string-downcase "ABC"))

;;; --- type errors are catchable ---
(test #t (guard (e (#t #t)) (char-upcase 5)))
(test #t (guard (e (#t #t)) (char-foldcase "a")))
(test #t (guard (e (#t #t)) (digit-value 7)))
(test #t (guard (e (#t #t)) (char-ci=? #\a 5)))
(test #t (guard (e (#t #t)) (string-ci=? "a" 5)))
(test #t (guard (e (#t #t)) (string-upcase 42)))
(test #t (guard (e (#t #t)) (char-alphabetic? "a")))

;;; --- #1145: property-based classification (fixed) ---
(test '(#f #f) (list (char-upper-case? #\x01C5) (char-lower-case? #\x01C5)))
(test #t (char-lower-case? #\x00DF))
(test '(#t #t) (list (char-alphabetic? #\x00AA) (char-lower-case? #\x00AA)))

(test-end "primitives_char audit")
