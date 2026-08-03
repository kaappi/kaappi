;; Regression test for string->number R7RS radix and exactness prefixes
;; Issue #369

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "string-to-number-prefix")

;; Radix prefixes
(test-equal "#xff" 255 (string->number "#xff"))
(test-equal "#b1010" 10 (string->number "#b1010"))
(test-equal "#o17" 15 (string->number "#o17"))
(test-equal "#d42" 42 (string->number "#d42"))
(test-equal "#XFF" 255 (string->number "#XFF"))
(test-equal "#xeff" 3839 (string->number "#xeff"))

;; Exactness prefixes
(test-equal "#i42" 42.0 (string->number "#i42"))
(test-assert "#e1.5 is rational" (rational? (string->number "#e1.5")))
(test-equal "#e1.5" 3/2 (string->number "#e1.5"))
(test-equal "#e2.0" 2 (string->number "#e2.0"))

;; Both in either order
(test-equal "#e#xff" 255 (string->number "#e#xff"))
(test-equal "#i#b1010" 10.0 (string->number "#i#b1010"))
(test-equal "#b#i1010" 10.0 (string->number "#b#i1010"))

;; Prefix overrides parameter
(test-equal "#x10 base 10" 16 (string->number "#x10" 10))

;; Rational with non-decimal radix
(test-equal "a/b base 16" 10/11 (string->number "a/b" 16))

;; Regression for #604: #e with large floats must not abort
(test-equal "#e1e20" 100000000000000000000 (string->number "#e1e20"))
(test-equal "#e9.5e18" 9500000000000000000 (string->number "#e9.5e18"))
(test-equal "#e1e19" 10000000000000000000 (string->number "#e1e19"))
(test-assert "#e1e20 = (exact 1e20)" (= (string->number "#e1e20") (exact 1e20)))

;; Existing functionality preserved
(test-equal "42" 42 (string->number "42"))
(test-equal "3.14" 3.14 (string->number "3.14"))
(test-equal "ff base 16" 255 (string->number "ff" 16))
(test-equal "+inf.0" +inf.0 (string->number "+inf.0"))
(test-equal "#b (empty)" #f (string->number "#b"))
(test-equal "#z42 (invalid)" #f (string->number "#z42"))

(let ((runner (test-runner-current)))
  (test-end "string-to-number-prefix")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
