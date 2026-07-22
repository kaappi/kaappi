;; SRFI-169 (Underscores in numbers) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi169.scm
;;
;; This is purely reader syntax (see lib/srfi/169.sld's header for the
;; engine-side implementation and its scope notes about string->number).
;; Invalid placements are read errors, which this test suite can't
;; provoke from within a running program (they'd fail to parse the test
;; file itself) -- so those are exercised via read from a string port,
;; which raises a catchable error instead of failing to load the file.

(import (scheme base) (scheme read) (scheme process-context) (srfi 169) (srfi 64))

(test-begin "srfi-169")

;;; --- valid placements: every part of every numeric shape ---

(test-equal "integer part" 1000000 1_000_000)
(test-equal "fractional part" 3.14159 3.14_159)
(test-equal "exponent part" 1e13 1_000e1_0)
(test-equal "hex integer" 65535 #xFF_FF)
(test-equal "octal integer" 8 #o1_0)
(test-equal "binary integer" 170 #b1010_1010)
(test-equal "rational numerator and denominator" 6/17 1_2/3_4)
(test-equal "real and imaginary parts of a complex number" 12+34i 1_2+3_4i)
(test-equal "single underscore, single digit on each side" 12 1_2)

;; Composes with SRFI 270's hex float syntax (both implemented in the
;; same reader machinery).
(test-equal "underscore inside a SRFI-270 hex float" 18640.0 #x1_2.3_4p1_0)

;;; --- invalid placements: all rejected, none silently accepted ---

(define (read-fails? s)
  (guard (e (#t #t))
    (read (open-input-string s))
    #f))

;; A leading underscore before any digit means this was never recognized
;; as a number-like token in the first place, so it's read as an ordinary
;; symbol instead of triggering a read error -- still correctly NOT
;; accepted as a number.
(test-equal "leading underscore reads as a symbol, not a number" '_123 (read (open-input-string "_123")))
(test-equal "sign then leading underscore also reads as a symbol" '+_123 (read (open-input-string "+_123")))

(test-assert "trailing underscore" (read-fails? "123_"))
(test-assert "consecutive underscores" (read-fails? "1__2"))
(test-assert "underscore adjacent to an exponent marker (before)" (read-fails? "1_e5"))
(test-assert "underscore adjacent to an exponent marker (after)" (read-fails? "1e_5"))
(test-assert "underscore adjacent to a radix prefix" (read-fails? "#x_1a"))
(test-assert "underscore adjacent to a decimal point (before)" (read-fails? "1_.5"))
(test-assert "underscore adjacent to a decimal point (after)" (read-fails? "1._5"))
(test-assert "underscore adjacent to a rational slash (before)" (read-fails? "1_/2"))
(test-assert "underscore adjacent to a rational slash (after)" (read-fails? "1/_2"))
(test-assert "trailing underscore in a hex integer" (read-fails? "#x1a_"))

(let ((runner (test-runner-current)))
  (test-end "srfi-169")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
