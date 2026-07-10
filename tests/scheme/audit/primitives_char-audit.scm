;; Audit tests for src/primitives_char.zig — (scheme char) Unicode operations.
;; Audit campaign Phase 2.3 (#1137). Complements compliance/chars.scm,
;; compliance/r7rs-chars-strings-gaps.scm, and the R7RS suite section 6.6.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme char) (scheme write))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_char audit")

;;; --- char-numeric? is Numeric_Type=Decimal only (R7RS 6.6) ---
(test-equal #t (char-numeric? #\5))
(test-equal #t (char-numeric? #\x0664))   ; Arabic-Indic four (Nd)
(test-equal #t (char-numeric? #\xFF13))   ; fullwidth three (Nd)
(test-equal #f (char-numeric? #\x00B2))   ; superscript two: No, not decimal
(test-equal #f (char-numeric? #\x2160))   ; Roman numeral: Nl, not decimal
(test-equal #f (char-numeric? #\a))

;;; --- digit-value agrees with char-numeric? ---
(test-equal 3 (digit-value #\xFF13))
(test-equal #f (digit-value #\x00B2))
(test-equal 0 (digit-value #\x0AE6))

;;; --- classification (see #1145 for the failing property-based cases) ---
(test-equal #t (char-alphabetic? #\x05D0))   ; Hebrew alef, uncased letter
(test-equal #f (char-alphabetic? #\x0664))   ; digits are not alphabetic
(test-equal #t (char-whitespace? #\x00A0))   ; NBSP
(test-equal #t (char-whitespace? #\x2028))   ; LINE SEPARATOR
(test-equal #t (char-whitespace? #\x2029))   ; PARAGRAPH SEPARATOR
(test-equal #t (char-whitespace? #\x0B))     ; vertical tab
(test-equal #f (char-whitespace? #\x200B))   ; ZERO WIDTH SPACE is NOT White_Space

;;; --- case conversion: simple mappings ---
(test-equal #\a (char-downcase #\A))
(test-equal #\A (char-upcase #\a))
(test-equal 105 (char->integer (char-downcase #\x0130))) ; I-with-dot: simple = i
(test-equal #\x00DF (char-upcase #\x00DF))               ; sharp-s: no simple upcase
(test-equal #\x13A0 (char-upcase #\xAB70))               ; Cherokee case pair
(test-equal #\xAB70 (char-downcase #\x13A0))
(test-equal #\3 (char-upcase #\3))                       ; uncased returns argument
(test-equal #\x05D0 (char-downcase #\x05D0))

;;; --- char-foldcase: simple fold ---
(test-equal #\a (char-foldcase #\A))
(test-equal #\x03C3 (char-foldcase #\x03A3))  ; capital sigma -> sigma
(test-equal #\x03C3 (char-foldcase #\x03C2))  ; final sigma -> sigma
(test-equal #\x00DF (char-foldcase #\x00DF))  ; sharp-s folds to itself (simple)

;;; --- char-ci comparisons behave as if char-foldcase applied ---
(test-equal #t (char-ci=? #\A #\a))
(test-equal #t (char-ci=? #\x03A3 #\x03C2))   ; sigma ci= final sigma via fold
(test-equal #t (char-ci=? #\a #\A #\a))
(test-equal #f (char-ci=? #\a #\b))
(test-equal #t (char-ci<? #\a #\B #\c))
(test-equal #t (char-ci<=? #\a #\B #\b))
(test-equal #t (char-ci>? #\c #\B #\a))
(test-equal #t (char-ci>=? #\b #\B #\a))

;;; --- string-ci comparisons via string-foldcase ---
(test-equal #t (string-ci=? "AbC" "aBc" "ABC"))
(test-equal #t (string-ci=? "Stra\xDF;e" "STRASSE"))     ; full fold: eszett = ss
(test-equal #t (string-ci=? "\x03A3;" "\x03C2;"))        ; sigma forms
(test-equal #t (string-ci<? "apple" "BANANA"))
(test-equal #f (string-ci<? "BANANA" "apple"))
(test-equal #t (string-ci<=? "a" "A"))
(test-equal #t (string-ci>=? "B" "a"))
(test-equal #f (string-ci>? "a" "B"))

;;; --- string casing: full (multi-char) mappings ---
(test-equal "STRASSE" (string-upcase "Stra\xDF;e"))      ; length change
(test-equal "FFI" (string-upcase "\xFB03;"))             ; ligature expands
(test-equal "strasse" (string-foldcase "STRA\xDF;E"))
(test-equal 2 (string-length (string-downcase "\x0130;"))) ; I-dot -> i + U+0307
;; Greek final sigma is contextual in string-downcase:
(test-equal "\x03BF;\x03C2;" (string-downcase "\x039F;\x03A3;"))         ; word-final
(test-equal "\x03BF;\x03C3;\x03BF;" (string-downcase "\x039F;\x03A3;\x039F;")) ; medial
(test-equal "" (string-upcase ""))
(test-equal "abc" (string-downcase "ABC"))

;;; --- type errors are catchable ---
(test-equal #t (guard (e (#t #t)) (char-upcase 5)))
(test-equal #t (guard (e (#t #t)) (char-foldcase "a")))
(test-equal #t (guard (e (#t #t)) (digit-value 7)))
(test-equal #t (guard (e (#t #t)) (char-ci=? #\a 5)))
(test-equal #t (guard (e (#t #t)) (string-ci=? "a" 5)))
(test-equal #t (guard (e (#t #t)) (string-upcase 42)))
(test-equal #t (guard (e (#t #t)) (char-alphabetic? "a")))

;;; --- #1145: property-based classification (fixed) ---
(test-equal '(#f #f) (list (char-upper-case? #\x01C5) (char-lower-case? #\x01C5)))
(test-equal #t (char-lower-case? #\x00DF))
(test-equal '(#t #t) (list (char-alphabetic? #\x00AA) (char-lower-case? #\x00AA)))

(let ((runner (test-runner-current)))
  (test-end "primitives_char audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
