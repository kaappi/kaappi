;; Regression test for #1145: char classification uses Unicode derived
;; properties (Uppercase, Lowercase, Alphabetic) instead of case mappings.

(import (scheme base) (scheme char) (scheme write) (scheme process-context)
        (srfi 64))

(test-begin "char-unicode-properties")

;; Titlecase letters (Lt) are alphabetic but neither upper nor lower
(test-equal "titlecase Dz-caron" '(#t #f #f)
  (let ((c #\x01C5)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
(test-equal "titlecase alpha-prosgegrammeni" '(#t #f #f)
  (let ((c #\x1FBC)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))

;; Sharp-s is Lowercase despite no simple uppercase mapping
(test-assert "sharp-s is lowercase" (char-lower-case? #\x00DF))
(test-assert "sharp-s is alphabetic" (char-alphabetic? #\x00DF))
(test-assert "sharp-s is not uppercase" (not (char-upper-case? #\x00DF)))

;; Ordinal indicators have Other_Lowercase (Alphabetic + Lowercase)
(test-equal "feminine ordinal" '(#t #f #t)
  (let ((c #\x00AA)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
(test-equal "masculine ordinal" '(#t #f #t)
  (let ((c #\x00BA)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))

;; Existing behavior must still work
(test-assert "ASCII upper" (char-upper-case? #\A))
(test-assert "ASCII lower" (char-lower-case? #\z))
(test-assert "ASCII alpha" (char-alphabetic? #\m))
(test-assert "Latin-1 upper" (char-upper-case? #\x00C0))
(test-assert "Latin-1 lower" (char-lower-case? #\x00E9))
(test-equal "Hebrew alef: alpha, not cased" '(#t #f #f)
  (let ((c #\x05D0)) (list (char-alphabetic? c) (char-upper-case? c) (char-lower-case? c))))
(test-assert "CJK ideograph is alphabetic" (char-alphabetic? #\x4E00))
(test-assert "Cherokee uppercase" (char-upper-case? #\x13A0))
(test-assert "Cherokee lowercase" (char-lower-case? #\xAB70))
(test-assert "digit not alphabetic" (not (char-alphabetic? #\0)))
(test-assert "space not alphabetic" (not (char-alphabetic? #\space)))

(let ((runner (test-runner-current)))
  (test-end "char-unicode-properties")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
