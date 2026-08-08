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

;; #751: #e/#i exactness prefixes apply to complex numbers (R7RS 7.1.1)
;; All four complex paths in parseNumberText must route through
;; applyExactness, whose Complex arm rebuilds with both exactness flags.
(test-equal "#e1+2i" 1+2i (string->number "#e1+2i"))
(test-assert "#e1+2i is exact" (exact? (string->number "#e1+2i")))
(test-equal "#i1+2i" 1.0+2.0i (string->number "#i1+2i"))
(test-assert "#i1+2i is inexact" (inexact? (string->number "#i1+2i")))
;; General a+bi with a decimal real part: #e rebuilds digit-exactly.
(test-equal "#e1.5+2i" 3/2+2i (string->number "#e1.5+2i"))
(test-assert "#e1.5+2i is exact" (exact? (string->number "#e1.5+2i")))
;; Pure imaginary +i/-i (R7RS <complex R> -> `+ i` | `- i`).
(test-equal "#e+i" +i (string->number "#e+i"))
(test-assert "#e+i is exact" (exact? (string->number "#e+i")))
(test-assert "#e-i is exact" (exact? (string->number "#e-i")))
(test-equal "#i+i" 0.0+1.0i (string->number "#i+i"))
;; Pure imaginary with a magnitude: +3i, -2i.
(test-equal "#e+3i" +3i (string->number "#e+3i"))
(test-assert "#e+3i is exact" (exact? (string->number "#e+3i")))
(test-assert "#e-2i is exact" (exact? (string->number "#e-2i")))
(test-assert "#i+3i is inexact" (inexact? (string->number "#i+3i")))
;; #e past i64 keeps exact digits in the real part (#1910's write half).
(test-equal "#e1e19+1i" 10000000000000000000+1i (string->number "#e1e19+1i"))
(test-assert "#e1e19+1i is exact" (exact? (string->number "#e1e19+1i")))
;; A non-finite part has no exact representation -- #f, same rule as the
;; flonum arm (#419).
(test-assert "#e+inf.0+1i is #f" (not (string->number "#e+inf.0+1i")))
(test-assert "#e+nan.0+1i is #f" (not (string->number "#e+nan.0+1i")))
;; Radix prefix combined with exactness and a complex tail.
(test-equal "#e#x1+2i" 1+2i (string->number "#e#x1+2i"))
(test-equal "#x#e1+2i" 1+2i (string->number "#x#e1+2i"))
(test-equal "#i#x1+2i" 1.0+2.0i (string->number "#i#x1+2i"))

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
