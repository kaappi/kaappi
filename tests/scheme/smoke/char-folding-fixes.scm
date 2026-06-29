;; Regression tests for char folding fixes
;; #290: charFoldcase ignores Unicode fold table
;; #291: string-ci comparisons fail on multi-character fold mappings

(import (scheme base) (scheme char) (scheme write))

;; ---- #290: charFoldcase uses fold table ----
;; U+00B5 (MICRO SIGN) should fold to U+03BC (GREEK SMALL MU)
(display (char-ci=? #\xB5 #\x3BC))   ; #t
(newline)

;; U+017F (LONG S) should fold to 's'
(display (char-ci=? #\x17F #\s))      ; #t
(newline)

;; ---- #291: string-ci with multi-char fold ----
;; Eszett (U+00DF) folds to "ss"
(display (string-ci=? "\xDF;" "ss"))   ; #t
(newline)
(display (string-ci=? "\xDF;" "SS"))   ; #t
(newline)

;; ff ligature (U+FB00) folds to "ff"
(display (string-ci=? "\xFB00;" "ff")) ; #t
(newline)

;; fi ligature (U+FB01) folds to "fi"
(display (string-ci=? "\xFB01;" "fi")) ; #t
(newline)

;; string-ci<? with multi-char fold: "a"+eszett folds to "ass", equal to "ass"
(display (string-ci=? "a\xDF;" "ass")) ; #t
(newline)

;; Ordering: "a" < "ass" since "a" is shorter
(display (string-ci<? "a" "ass"))      ; #t
(newline)

;; Equal strings
(display (string-ci=? "stra\xDF;e" "strasse")) ; #t (Straße = strasse)
(newline)

(display "all passed")
(newline)
