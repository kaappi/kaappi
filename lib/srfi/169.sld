;;; SRFI 169 — Underscores in numbers
;;;
;;; Allows a single underscore as a digit separator strictly between two
;;; digits anywhere in a numeric literal -- the integer, fractional, and
;;; exponent parts of a real; the numerator and denominator of a ratio;
;;; the real and imaginary parts of a complex number; in any radix
;;; (#b/#o/#d/#x). Underscores are rejected (not silently accepted, not
;;; silently dropped) when leading, trailing, doubled, or adjacent to any
;;; non-digit (a sign, `.`, an exponent marker, `/`, or a radix-prefix
;;; letter). Per the spec, this is purely a *reading* feature -- it says
;;; nothing about `number->string` or any other printing.
;;;
;;; This is a genuine reader/lexer change with no portable-library
;;; equivalent, implemented directly in the engine: the digit-scanning
;;; loops (`readNumber`'s mantissa/exponent/imaginary-part loops,
;;; `readIntegerWithRadix`, `scanDenominatorDigits`, and SRFI 270's
;;; `readHexFloatSuffix`, all in src/reader_tokens.zig) tolerate an
;;; embedded underscore without stopping the scan early, and the actual
;;; validation + stripping happens once, centrally, in
;;; `bignum.stripUnderscores` (src/bignum.zig) -- called from
;;; `parseDecimalReal`, `parseHexFloat`, `parseBignumString`, and directly
;;; before every remaining `std.fmt.parseInt` call on a captured numeric
;;; token. This library exists only so `(import (srfi 169))` succeeds;
;;; there is nothing to export.
;;;
;;; Scope note: this port makes no deliberate `string->number` change for
;;; SRFI 169 (the spec doesn't ask for it). In practice `string->number`
;;; already tolerates *some* underscore placements today, for two
;;; unrelated, pre-existing reasons: its small-integer fast path calls
;;; Zig's std.fmt.parseInt directly, which has its own (more permissive
;;; than SRFI 169) underscore convenience -- e.g. it wrongly accepts a
;;; doubled underscore ("1__2" -> 12) that SRFI 169 requires rejecting,
;;; a pre-existing gap unrelated to this port, filed as #1724 rather than
;;; silently left -- and its hex-float path shares `parseHexFloat` with
;;; the reader (added for SRFI 270, which *does* require `string->number`
;;; support), which does apply this library's own stricter validation.
;;; Bottom line: do not rely on `string->number` for SRFI-169-correct
;;; underscore handling; only the reader syntax itself is validated to
;;; spec.

(define-library (srfi 169)
  (export)
  (import (scheme base)))
