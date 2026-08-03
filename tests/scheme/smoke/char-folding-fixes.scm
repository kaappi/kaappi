;; Regression tests for char folding fixes
;; #290: charFoldcase ignores Unicode fold table
;; #291: string-ci comparisons fail on multi-character fold mappings

(import (scheme base) (scheme char) (scheme write) (scheme process-context) (srfi 64))

(test-begin "char-folding-fixes")

;; ---- #290: charFoldcase uses fold table ----
;; U+00B5 (MICRO SIGN) should fold to U+03BC (GREEK SMALL MU)
(test-assert "U+00B5 MICRO SIGN folds to U+03BC GREEK SMALL MU"
             (char-ci=? #\xB5 #\x3BC))

;; U+017F (LONG S) should fold to 's'
(test-assert "U+017F LONG S folds to s" (char-ci=? #\x17F #\s))

;; ---- #291: string-ci with multi-char fold ----
;; Eszett (U+00DF) folds to "ss"
(test-assert "eszett folds to ss" (string-ci=? "\xDF;" "ss"))
(test-assert "eszett folds to SS" (string-ci=? "\xDF;" "SS"))

;; ff ligature (U+FB00) folds to "ff"
(test-assert "ff ligature folds to ff" (string-ci=? "\xFB00;" "ff"))

;; fi ligature (U+FB01) folds to "fi"
(test-assert "fi ligature folds to fi" (string-ci=? "\xFB01;" "fi"))

;; string-ci<? with multi-char fold: "a"+eszett folds to "ass", equal to "ass"
(test-assert "a + eszett folds to ass" (string-ci=? "a\xDF;" "ass"))

;; Ordering: "a" < "ass" since "a" is shorter
(test-assert "string-ci<? orders a before ass" (string-ci<? "a" "ass"))

;; Equal strings
(test-assert "Strasse = strasse under case folding"
             (string-ci=? "stra\xDF;e" "strasse"))

(let ((runner (test-runner-current)))
  (test-end "char-folding-fixes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
