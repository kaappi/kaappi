;; Regression test for issue #80:
;; string-ci comparisons must use case-folding, not bare downcase.

(import (scheme base) (scheme char) (scheme write))

;; Long-s (U+017F) must fold to s
(unless (string-ci=? "ſ" "s")
  (display "FAIL: long-s vs s") (newline) (exit 1))

;; Micro sign (U+00B5) must fold to Greek mu (U+03BC)
(unless (string-ci=? "µ" "μ")
  (display "FAIL: micro sign vs mu") (newline) (exit 1))

;; Consistency: string-ci=? should agree with char-ci=?
(unless (eq? (char-ci=? #\ſ #\s) (string-ci=? "ſ" "s"))
  (display "FAIL: char-ci vs string-ci consistency for long-s") (newline) (exit 1))

;; Basic ASCII case insensitive
(unless (string-ci=? "Hello" "hello")
  (display "FAIL: basic ASCII") (newline) (exit 1))

;; Ordering with case folding
(unless (string-ci<? "abc" "abd")
  (display "FAIL: ci ordering") (newline) (exit 1))

(display "OK")
(newline)
