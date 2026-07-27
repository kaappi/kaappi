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
;;; SRFI 169 (the spec doesn't ask for it), but `string->number` does
;;; validate underscore placement to the same rule: `stringToNumber`
;;; (src/primitives_numeric.zig) calls `bignum.stripUnderscores` once, up
;;; front on the whole numeric body, before any shape-specific parsing --
;;; so the plain-integer, rational numerator/denominator, hex-float,
;;; bignum-overflow, decimal-float, and complex-parts paths all see
;;; already-validated, already-stripped digits. This closed a real gap
;;; (#1724): the small-integer and rational fast paths used to call Zig's
;;; std.fmt.parseInt directly on unvalidated input, which has its own,
;;; more permissive underscore convenience (mirroring Zig's own integer
;;; literal syntax) that wrongly accepted a doubled underscore
;;; ("1__2" -> 12) SRFI 169 requires rejecting.

(define-library (srfi 169)
  (export)
  (import (scheme base)))
