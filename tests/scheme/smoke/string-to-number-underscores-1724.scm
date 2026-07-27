;; Regression test for #1724: string->number wrongly accepted misplaced
;; SRFI-169-style digit-separator underscores ("1__2" -> 12 instead of #f).
;;
;; Root cause: the small-integer fast path (and the rational
;; numerator/denominator parse) called Zig's std.fmt.parseInt directly on
;; unvalidated input. That function has its own, more permissive underscore
;; convenience (mirroring Zig's own integer-literal syntax) that only
;; rejects a leading/trailing underscore, not a doubled one -- unlike
;; bignum.stripUnderscores, which the reader and the hex-float/bignum-
;; overflow paths already used. The fix validates+strips underscores once,
;; up front in string->number, before any shape-specific parsing.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "string-to-number-underscores-1724")

;;; --- exact repro from the issue ---

(test-equal "doubled underscore rejected, not silently collapsed" #f (string->number "1__2"))
(test-equal "trailing underscore rejected" #f (string->number "123_"))
(test-equal "leading underscore rejected" #f (string->number "_123"))
(test-equal "single well-placed underscores accepted" 123 (string->number "1_2_3"))
(test-equal "single underscore, single digit each side" 12 (string->number "1_2"))

;;; --- same root cause, other numeric shapes reachable from string->number ---

(test-equal "doubled underscore in rational numerator rejected" #f (string->number "1__2/3"))
(test-equal "doubled underscore in rational denominator rejected" #f (string->number "1/3__4"))
(test-equal "valid underscores in rational numerator and denominator" 6/17 (string->number "1_2/3_4"))

(test-equal "doubled underscore in hex integer rejected" #f (string->number "#xFF__FF"))
(test-equal "valid underscore in hex integer" 65535 (string->number "#xFF_FF"))

(test-equal "doubled underscore in complex real part rejected" #f (string->number "1__2+3i"))
(let ((z (string->number "1_2+3_4i")))
  (test-assert "valid underscores in complex real and imaginary parts"
    (and z (= (real-part z) 12) (= (imag-part z) 34))))

(test-equal "doubled underscore in decimal float rejected" #f (string->number "1__2.5"))
(test-equal "doubled underscore rejected under #e prefix" #f (string->number "#e1__2.5"))

;; Already correct before the fix (i64 overflow routes to parseBignumString,
;; which validates internally) -- kept here to pin the boundary alongside
;; the previously-buggy small-integer case above.
(test-equal "doubled underscore rejected in a bignum-sized literal" #f
  (string->number "99999999999999999999__999999999999999999"))
(test-equal "valid underscores throughout a bignum-sized literal" 12345678901234567890
  (string->number "12_34_56_78_90_12_34_56_78_90"))

(let ((runner (test-runner-current)))
  (test-end "string-to-number-underscores-1724")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
